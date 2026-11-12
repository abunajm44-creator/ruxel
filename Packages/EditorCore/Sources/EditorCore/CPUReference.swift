// What: Float-buffer CPU reference of the Metal kernels (warp, skin blend).
// Inputs/Outputs: Row-major Float buffers in; warped / blended buffers out.
// Threading: Pure functions; safe on any thread.
import Foundation

/// Typed errors for CPU-reference buffer operations.
public enum EditorCoreError: Error, Equatable, Sendable {
    case invalidSize
    case mismatchedBufferLengths
    case invalidRadius
}

private func clamp01(_ value: Float) -> Float {
    min(max(value, 0), 1)
}

/// Bilinear sample of a single-channel Float buffer, edges clamped.
/// `x`/`y` are in pixel coordinates (0 = first pixel center).
public func bilinearSample(src: [Float], width: Int, height: Int, x: Float, y: Float) -> Float {
    guard width > 0, height > 0, src.count == width * height else { return 0 }
    let clampedX = min(max(x, 0), Float(width - 1))
    let clampedY = min(max(y, 0), Float(height - 1))
    let x0 = Int(clampedX)
    let y0 = Int(clampedY)
    let x1 = min(x0 + 1, width - 1)
    let y1 = min(y0 + 1, height - 1)
    let fx = clampedX - Float(x0)
    let fy = clampedY - Float(y0)
    let top = src[y0 * width + x0] * (1 - fx) + src[y0 * width + x1] * fx
    let bottom = src[y1 * width + x0] * (1 - fx) + src[y1 * width + x1] * fx
    return top * (1 - fy) + bottom * fy
}

/// Warps a single-channel Float image by a per-pixel displacement field.
/// Inverse mapping (as in the Metal kernel): out[p] = src[p + D(p)].
/// Zero displacement returns the input exactly. Mismatched buffers
/// return the source unchanged.
public func warpImageFloat(
    src: [Float],
    width: Int,
    height: Int,
    displacement: [Vec2]
) -> [Float] {
    guard width > 0, height > 0, src.count == width * height else { return src }
    guard displacement.count == width * height else { return src }
    var out = [Float](repeating: 0, count: src.count)
    for y in 0..<height {
        for x in 0..<width {
            let index = y * width + x
            let d = displacement[index]
            let sampleX = Float(x) + d.x
            let sampleY = Float(y) + d.y
            out[index] = bilinearSample(src: src, width: width, height: height, x: sampleX, y: sampleY)
        }
    }
    return out
}

/// CPU reference of the Metal `skinSmoothBlend` kernel (frequency
/// separation): smoothed = low + (src - low) * textureKeep, then
/// out = mix(src, smoothed, clamp(mask * strength, 0, 1)).
/// All buffers must have the same length; otherwise returns `src`.
public func skinSmoothBlendCPU(
    src: [Float],
    low: [Float],
    skinMask: [Float],
    strength: Float,
    textureKeep: Float
) -> [Float] {
    guard src.count == low.count, src.count == skinMask.count else { return src }
    var out = [Float](repeating: 0, count: src.count)
    for i in 0..<src.count {
        let smoothed = low[i] + (src[i] - low[i]) * textureKeep
        let m = clamp01(skinMask[i] * strength)
        out[i] = src[i] * (1 - m) + smoothed * m
    }
    return out
}

/// Catmull-Rom interpolation of four samples at fractional position `t`
/// (0...1 between p1 and p2). Passes through the grid points, so sampling
/// at integer coordinates returns the exact sample.
public func catmullRomInterpolate(p0: Float, p1: Float, p2: Float, p3: Float, t: Float) -> Float {
    0.5 * (
        (2 * p1)
        + (-p0 + p2) * t
        + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
        + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t
    )
}

/// Bicubic (Catmull-Rom) sample of a single-channel Float buffer, edges
/// clamped. Used by the export warp: the interactive path uses the
/// hardware linear sampler, export uses this for a sharper result.
public func bicubicSample(src: [Float], width: Int, height: Int, x: Float, y: Float) -> Float {
    guard width > 0, height > 0, src.count == width * height else { return 0 }
    let clampedX = min(max(x, 0), Float(width - 1))
    let clampedY = min(max(y, 0), Float(height - 1))
    let x0 = Int(clampedX)
    let y0 = Int(clampedY)
    let fx = clampedX - Float(x0)
    let fy = clampedY - Float(y0)
    func sampleAt(_ ix: Int, _ iy: Int) -> Float {
        let cx = min(max(ix, 0), width - 1)
        let cy = min(max(iy, 0), height - 1)
        return src[cy * width + cx]
    }
    var column = [Float](repeating: 0, count: 4)
    for j in 0..<4 {
        column[j] = catmullRomInterpolate(
            p0: sampleAt(x0 - 1, y0 - 1 + j),
            p1: sampleAt(x0, y0 - 1 + j),
            p2: sampleAt(x0 + 1, y0 - 1 + j),
            p3: sampleAt(x0 + 2, y0 - 1 + j),
            t: fx
        )
    }
    return catmullRomInterpolate(p0: column[0], p1: column[1], p2: column[2], p3: column[3], t: fy)
}

/// Warps a single-channel Float image by a per-pixel displacement field
/// with bicubic sampling. Inverse mapping: out[p] = src[p + D(p)].
/// Zero displacement returns the input exactly. Mismatched buffers
/// return the source unchanged.
public func warpImageFloatCubic(
    src: [Float],
    width: Int,
    height: Int,
    displacement: [Vec2]
) -> [Float] {
    guard width > 0, height > 0, src.count == width * height else { return src }
    guard displacement.count == width * height else { return src }
    var out = [Float](repeating: 0, count: src.count)
    for y in 0..<height {
        for x in 0..<width {
            let index = y * width + x
            let d = displacement[index]
            out[index] = bicubicSample(
                src: src, width: width, height: height,
                x: Float(x) + d.x, y: Float(y) + d.y
            )
        }
    }
    return out
}

/// 5-tap binomial blur ([1,4,6,4,1]/16, separable), the CPU mirror of
/// the Metal `skinLowPass` kernel. Radius is fixed at 2 taps; call it
/// repeatedly for a wider blur. Mismatched sizes return the input.
public func separableBlurFloat(src: [Float], width: Int, height: Int) -> [Float] {
    guard width > 0, height > 0, src.count == width * height else { return src }
    let weights: [Float] = [1.0 / 16, 4.0 / 16, 6.0 / 16, 4.0 / 16, 1.0 / 16]
    var horizontal = [Float](repeating: 0, count: src.count)
    for y in 0..<height {
        for x in 0..<width {
            var sum: Float = 0
            for k in -2...2 {
                let cx = min(max(x + k, 0), width - 1)
                sum += src[y * width + cx] * weights[k + 2]
            }
            horizontal[y * width + x] = sum
        }
    }
    var out = [Float](repeating: 0, count: src.count)
    for y in 0..<height {
        for x in 0..<width {
            var sum: Float = 0
            for k in -2...2 {
                let cy = min(max(y + k, 0), height - 1)
                sum += horizontal[cy * width + x] * weights[k + 2]
            }
            out[y * width + x] = sum
        }
    }
    return out
}

/// Deterministic per-pixel grain in -1...1 from integer coordinates and
/// a seed (hash-based, no RNG state). Used for grain re-injection after
/// smoothing: out = src + grain * amount * mask.
public func grainNoise(x: Int, y: Int, seed: Int = 0) -> Float {
    var hash = UInt32(truncatingIfNeeded: x) &* 374761393
    hash &+= UInt32(truncatingIfNeeded: y) &* 668265263
    hash &+= UInt32(truncatingIfNeeded: seed) &* 974634211
    hash ^= hash >> 13
    hash &*= 1274126177
    hash ^= hash >> 16
    return Float(hash) / Float(UInt32.max) * 2 - 1
}
