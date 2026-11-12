#include <metal_stdlib>
using namespace metal;

// Warp.metal — displacement warp + skin frequency-separation blend + low pass.
// What: compute kernels for the retouch render graph (see RenderGraph.swift).
// Inputs: source / field / mask textures + small params buffers. Outputs: dst texture.
// Threading: Metal compute; one thread per output pixel; no CPU work here.

// Must match Swift WarpParams in App/Sources/Metal/WarpParams.swift exactly:
// one 4-byte uint. Keep scalar fields 4-byte aligned; add explicit padding
// when a struct grows so MemoryLayout stride still matches on both sides.
struct WarpParams {
    uint backgroundLock;
};

// Must match Swift SmoothParams in App/Sources/Metal/SmoothParams.swift:
// two 4-byte floats = 8 bytes, no padding needed.
struct SmoothParams {
    float strength;
    float textureKeep;
};

// applyDisplacement — warp src by a normalized-UV displacement field.
// field texture1: rg16Float, rg = displacement in normalized UV units.
// lockMask texture2: r8Unorm person mask; when backgroundLock is set the
// displacement is multiplied by the mask so the background does not move.
// dst texture3: same size/format as src.
kernel void applyDisplacement(
    texture2d<float, access::sample> src [[texture(0)]],
    texture2d<float, access::sample> field [[texture(1)]],
    texture2d<float, access::sample> lockMask [[texture(2)]],
    texture2d<float, access::write> dst [[texture(3)]],
    constant WarpParams &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) { return; }
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 size = float2(dst.get_width(), dst.get_height());
    float2 uv = (float2(gid) + 0.5f) / size;
    float2 d = field.sample(s, uv).rg;
    float m = params.backgroundLock != 0 ? lockMask.sample(s, uv).r : 1.0f;
    dst.write(src.sample(s, uv + d * m), gid);
}

// skinSmoothBlend — frequency-separation blend for skin smoothing.
// smoothed = low + (src - low) * textureKeep keeps fine detail (textureKeep
// near 1) while the low pass carries the smoothing. The result is mixed
// with the original by the skin mask scaled by strength.
kernel void skinSmoothBlend(
    texture2d<float, access::sample> src [[texture(0)]],
    texture2d<float, access::sample> low [[texture(1)]],
    texture2d<float, access::sample> skinMask [[texture(2)]],
    texture2d<float, access::write> dst [[texture(3)]],
    constant SmoothParams &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) { return; }
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 size = float2(dst.get_width(), dst.get_height());
    float2 uv = (float2(gid) + 0.5f) / size;
    float4 srcColor = src.sample(s, uv);
    float4 lowColor = low.sample(s, uv);
    float mask = skinMask.sample(s, uv).r;
    float4 smoothed = lowColor + (srcColor - lowColor) * params.textureKeep;
    float t = clamp(mask * params.strength, 0.0f, 1.0f);
    dst.write(mix(srcColor, smoothed, t), gid);
}

// skinLowPass — 5x5 separable-approximation gaussian blur (single pass).
// This is the low pass for frequency separation: skinSmoothBlend receives
// its output as `low`. Weights are the 5-tap binomial row [1,4,6,4,1]/16
// applied in both axes (outer product), normalized to sum 1.
kernel void skinLowPass(
    texture2d<float, access::sample> src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) { return; }
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 size = float2(dst.get_width(), dst.get_height());
    float2 uv = (float2(gid) + 0.5f) / size;
    float2 texel = 1.0f / size;
    const float w[5] = { 1.0f / 16.0f, 4.0f / 16.0f, 6.0f / 16.0f, 4.0f / 16.0f, 1.0f / 16.0f };
    float4 sum = float4(0.0f);
    for (int y = -2; y <= 2; ++y) {
        for (int x = -2; x <= 2; ++x) {
            float2 offset = float2(float(x), float(y)) * texel;
            sum += src.sample(s, uv + offset) * (w[x + 2] * w[y + 2]);
        }
    }
    dst.write(sum, gid);
}

// NOTE — bicubicSample: not a kernel. A bicubic (Catmull-Rom) texture
// sampler is intentionally NOT used yet: the warp kernel uses the hardware
// linear sampler for speed, and bicubic upsampling for export zoom is a
// future step. If added, implement it as a Metal function (not a kernel)
// taking a texture2d + sampler + uv, sampling the 4x4 neighbourhood with
// Catmull-Rom weights, and call it from applyDisplacement behind a flag.

// Warp field building — mirrors EditorCore WarpMath / BrushEngine exactly.
// Must match Swift WarpOpParams / BrushDabParams in
// App/Sources/Metal/WarpFieldParams.swift: 32 bytes each, same field order.
// type: 0 scale, 1 translate, 2 pinch. axes: 0 both, 1 horizontal, 2 vertical.
// mode: 0 classic, 1 fast, 2 restore.
struct WarpOpParams {
    uint type;
    uint axes;
    float2 center;
    float2 direction;
    float radius;
    float amount;
};

struct BrushDabParams {
    float2 center;
    float2 direction;
    float radius;
    float strength;
    uint mode;
    uint _padding;
};

// Smoothstep falloff: 1 at the center, 0 at/after radius, zero slope at
// both ends. Must match EditorCore falloff().
float warpFalloff(float d, float r) {
    if (r <= 0.0f) { return 0.0f; }
    float t = clamp(d / r, 0.0f, 1.0f);
    return 1.0f - t * t * (3.0f - 2.0f * t);
}

// Displacement of one warp op at normalized point p.
// Must match EditorCore scale/translate/pinchDisplacement().
float2 warpOpDisplacement(WarpOpParams op, float2 p) {
    float2 offset = p - op.center;
    float d = length(offset);
    float2 raw = float2(0.0f);
    if (op.type == 0) {
        // Scale: amount > 0 enlarges around the center.
        float w = warpFalloff(d, op.radius) * d * op.amount;
        raw = -offset * w;
    } else if (op.type == 1) {
        // Translate: shift along direction, fading to zero at radius.
        raw = op.direction * (warpFalloff(d, op.radius) * op.amount);
    } else {
        // Pinch: pull toward the center; zero displacement at the center.
        if (op.radius > 0.0f && d > 0.0f) {
            float t = min(d / op.radius, 1.0f);
            float w = warpFalloff(d, op.radius) * (1.0f - t) * op.amount;
            raw = -offset * w;
        }
    }
    if (op.axes == 1) { raw.y = 0.0f; }
    if (op.axes == 2) { raw.x = 0.0f; }
    return raw;
}

// buildDisplacementField — sums up to 64 warp ops into an rg16Float field
// texture (normalized UV displacement). One thread per field pixel; the
// field is written fully, so no separate clear pass is needed.
kernel void buildDisplacementField(
    texture2d<float, access::write> field [[texture(0)]],
    constant WarpOpParams *ops [[buffer(1)]],
    constant uint &opCount [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= field.get_width() || gid.y >= field.get_height()) { return; }
    float2 size = float2(field.get_width(), field.get_height());
    float2 p = (float2(gid) + 0.5f) / size;
    float2 total = float2(0.0f);
    for (uint i = 0; i < opCount; ++i) {
        total += warpOpDisplacement(ops[i], p);
    }
    field.write(float4(total, 0.0f, 1.0f), gid);
}

// stampBrushDabs — stamps brush dabs into an existing field texture
// (read-write, one thread per pixel, no cross-thread dependency).
// Push (classic/fast): d += direction * falloff * strength * radius * 0.15
// (0.15 = EditorCore brushPushGain — keep in sync). Restore: the field is
// scaled toward zero by (1 - falloff * strength). Fast-mode radius is
// baked into dab.radius by the Swift side (brushDabs), not doubled here.
kernel void stampBrushDabs(
    texture2d<float, access::read_write> field [[texture(0)]],
    constant BrushDabParams *dabs [[buffer(1)]],
    constant uint &dabCount [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= field.get_width() || gid.y >= field.get_height()) { return; }
    float2 size = float2(field.get_width(), field.get_height());
    float2 p = (float2(gid) + 0.5f) / size;
    float2 d = field.read(gid).rg;
    for (uint i = 0; i < dabCount; ++i) {
        BrushDabParams dab = dabs[i];
        float dist = distance(p, dab.center);
        float f = warpFalloff(dist, dab.radius);
        if (f <= 0.0f) { continue; }
        if (dab.mode == 2) {
            d *= (1.0f - f * dab.strength);
        } else {
            d += dab.direction * (f * dab.strength * dab.radius * 0.15f);
        }
    }
    field.write(float4(d, 0.0f, 1.0f), gid);
}
