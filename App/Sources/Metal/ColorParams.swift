// ColorParams — Swift mirror of the Metal `ColorParams` struct in Warp.metal.
// What: resolved color-grade parameters for the colorGrade kernel.
// The exposure/contrast/saturation/warmth values already include the
// filter preset deltas (folded by EditorCore resolveColorGrade), so the
// kernel applies them blindly. Layout must match Metal exactly:
// cropRect (float4) first, then five floats; stride is 48 bytes.
// Threading: value type; created on the render thread.
import Foundation
import EditorCore

/// Mirror of Metal `ColorParams`. Stride must be 48 bytes.
struct ColorParams {
    var cropRect: SIMD4<Float>
    var exposure: Float
    var contrast: Float
    var saturation: Float
    var warmth: Float
    var cropRotation: Float

    /// Expected stride; must equal sizeof(ColorParams) in Warp.metal.
    static let expectedStride = 48

    /// Builds kernel parameters from the extras + source size.
    init(extras: ExtraAdjustments, sourceWidth: Int, sourceHeight: Int) {
        let grade = resolveColorGrade(
            exposure: extras.exposure,
            contrast: extras.contrast,
            saturation: extras.saturation,
            warmth: extras.warmth,
            preset: extras.filterPreset,
            intensity: extras.filterIntensity / 100
        )
        let rect = cropRect(
            aspect: extras.cropAspect,
            sourceWidth: Float(sourceWidth),
            sourceHeight: Float(sourceHeight)
        )
        cropRect = SIMD4<Float>(rect.min.x, rect.min.y, rect.size.x, rect.size.y)
        exposure = grade.exposureEV
        contrast = grade.contrastFactor
        saturation = grade.saturationFactor
        warmth = grade.warmth
        cropRotation = extras.cropRotation * Float.pi / 180
    }

    /// Layout check. RenderGraph refuses to run the color stage when
    /// the Swift/Metal structs drift apart (a mismatch makes the
    /// kernel read garbage).
    static func stridesMatch() -> Bool {
        MemoryLayout<ColorParams>.stride == ColorParams.expectedStride
    }
}
