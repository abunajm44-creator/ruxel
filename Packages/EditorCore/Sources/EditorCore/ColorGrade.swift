// ColorGrade — the canonical color-grade math for RUXEL.
// What: exposure / contrast / saturation / warmth + filter presets +
// crop geometry, shared by the Metal colorGrade kernel (Warp.metal),
// the CPU export path (ExportService) and the live preview.
// The Metal kernel MUST mirror gradePixel() exactly: same order, same
// constants (exposure -> warmth -> contrast -> saturation -> clamp).
// Filter presets are honest fixed mixes of the four sliders (no LUTs).
// Threading: pure functions; safe on any thread.
import Foundation

/// Filter presets. Raw values are persisted in extras.json — never rename.
public enum FilterPreset: String, Codable, Hashable, Sendable, CaseIterable {
    case none
    case vivid
    case warm
    case cool
    case mono
    case fade
}

/// Crop aspect ratios. Raw values are persisted in extras.json.
public enum CropAspect: String, Codable, Hashable, Sendable, CaseIterable {
    case free
    case square
    case portrait
    case wide
    case classic

    /// Width / height of the target aspect. Free means "no crop".
    public var ratio: Float? {
        switch self {
        case .free: return nil
        case .square: return 1
        case .portrait: return 4 / 5
        case .wide: return 16 / 9
        case .classic: return 3 / 2
        }
    }
}

/// Resolved per-pixel grade parameters: everything the kernel / CPU loop
/// needs after filter presets have been folded into the four sliders.
public struct ResolvedColorGrade: Equatable, Sendable {
    /// Exposure in stops (-2...+2).
    public var exposureEV: Float
    /// Contrast multiplier (0.2...1.8).
    public var contrastFactor: Float
    /// Saturation multiplier (0...2; 0 = grayscale).
    public var saturationFactor: Float
    /// Warmth (-1...+1; + warms).
    public var warmth: Float

    public init(exposureEV: Float, contrastFactor: Float, saturationFactor: Float, warmth: Float) {
        self.exposureEV = exposureEV
        self.contrastFactor = contrastFactor
        self.saturationFactor = saturationFactor
        self.warmth = warmth
    }
}

/// Slider-unit deltas a filter preset adds (before intensity scaling).
/// Mono is handled separately: it forces saturation to zero.
public func filterDeltas(preset: FilterPreset) -> (exposure: Float, contrast: Float, saturation: Float, warmth: Float) {
    switch preset {
    case .none: return (0, 0, 0, 0)
    case .vivid: return (0, 12, 30, 0)
    case .warm: return (0, 0, 5, 35)
    case .cool: return (0, 0, 5, -35)
    case .mono: return (0, 0, 0, 0)
    case .fade: return (10, -25, -15, 0)
    }
}

/// Folds the base sliders (-100...100) and the filter preset (scaled by
/// intensity 0...1) into resolved kernel parameters.
public func resolveColorGrade(
    exposure: Float,
    contrast: Float,
    saturation: Float,
    warmth: Float,
    preset: FilterPreset,
    intensity: Float
) -> ResolvedColorGrade {
    let t = min(max(intensity, 0), 1)
    let d = filterDeltas(preset: preset)
    let e = exposure + d.exposure * t
    let c = contrast + d.contrast * t
    var s = saturation + d.saturation * t
    let w = warmth + d.warmth * t
    // Mono desaturates fully at full intensity, proportionally below it.
    if preset == .mono {
        s = s * (1 - t) + (-100) * t
    }
    return ResolvedColorGrade(
        exposureEV: (e / 100) * 2,
        contrastFactor: 1 + (c / 100) * 0.8,
        saturationFactor: 1 + (s / 100),
        warmth: w / 100
    )
}

/// Grades one pixel (linear-light RGB in 0...1). MUST match the Metal
/// `colorGrade` kernel: exposure -> warmth -> contrast -> saturation.
public func gradePixel(r: Float, g: Float, b: Float, grade: ResolvedColorGrade) -> (r: Float, g: Float, b: Float) {
    // Exposure: 2^EV.
    var red = r * pow(2, grade.exposureEV)
    var green = g * pow(2, grade.exposureEV)
    var blue = b * pow(2, grade.exposureEV)
    // Warmth: red up / blue down.
    red *= 1 + 0.2 * grade.warmth
    blue *= 1 - 0.2 * grade.warmth
    // Contrast around 0.5.
    red = (red - 0.5) * grade.contrastFactor + 0.5
    green = (green - 0.5) * grade.contrastFactor + 0.5
    blue = (blue - 0.5) * grade.contrastFactor + 0.5
    // Saturation around Rec.709 luma.
    let luma = red * 0.2126 + green * 0.7152 + blue * 0.0722
    red = luma + (red - luma) * grade.saturationFactor
    green = luma + (green - luma) * grade.saturationFactor
    blue = luma + (blue - luma) * grade.saturationFactor
    return (min(max(red, 0), 1), min(max(green, 0), 1), min(max(blue, 0), 1))
}

/// Crop rectangle (min + size, in input UV 0...1) for an aspect ratio on
/// a source of the given size. Centered; free means the full frame.
public func cropRect(aspect: CropAspect, sourceWidth: Float, sourceHeight: Float) -> (min: Vec2, size: Vec2) {
    guard let target = aspect.ratio, sourceWidth > 0, sourceHeight > 0 else {
        return (Vec2(0, 0), Vec2(1, 1))
    }
    let source = sourceWidth / sourceHeight
    if target >= source {
        // Target is wider than the source: crop the height.
        let h = source / target
        return (Vec2(0, (1 - h) / 2), Vec2(1, h))
    } else {
        // Target is taller than the source: crop the width.
        let w = target / source
        return (Vec2((1 - w) / 2, 0), Vec2(w, 1))
    }
}
