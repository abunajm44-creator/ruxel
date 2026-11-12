// What: sRGB / linear / XYZ / Lab color conversions and skin likelihood.
// Inputs/Outputs: RGB/Lab colors in; converted colors and 0...1 likelihoods out.
// Threading: Pure functions; safe on any thread.
import Foundation

/// An RGB color with components in 0...1.
public struct RGBColor: Codable, Equatable, Sendable {
    public var r: Float
    public var g: Float
    public var b: Float

    public init(r: Float, g: Float, b: Float) {
        self.r = r
        self.g = g
        self.b = b
    }

    public static let black = RGBColor(r: 0, g: 0, b: 0)
    public static let white = RGBColor(r: 1, g: 1, b: 1)
}

/// CIE XYZ color (D65 white point).
public struct XYZColor: Codable, Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var z: Float

    public init(x: Float, y: Float, z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }
}

/// CIE Lab color (D65 white point). L in 0...100, a/b roughly -128...127.
public struct LabColor: Codable, Equatable, Sendable {
    public var l: Float
    public var a: Float
    public var b: Float

    public init(l: Float, a: Float, b: Float) {
        self.l = l
        self.a = a
        self.b = b
    }
}

/// D65 reference white.
public let d65White = XYZColor(x: 0.95047, y: 1.0, z: 1.08883)

private func clamp01(_ value: Float) -> Float {
    min(max(value, 0), 1)
}

private func powFloat(_ base: Float, _ exponent: Float) -> Float {
    Float(pow(Double(base), Double(exponent)))
}

/// One sRGB channel (0...1) to linear light.
public func srgbToLinear(_ value: Float) -> Float {
    let v = clamp01(value)
    if v <= 0.04045 {
        return v / 12.92
    }
    return powFloat((v + 0.055) / 1.055, 2.4)
}

/// One linear-light channel (0...1) to sRGB.
public func linearToSrgb(_ value: Float) -> Float {
    let v = clamp01(value)
    if v <= 0.0031308 {
        return v * 12.92
    }
    return 1.055 * powFloat(v, 1.0 / 2.4) - 0.055
}

/// sRGB (gamma-encoded) to linear RGB.
/// Note: the app works in Display P3 on device; sRGB and P3 share the
/// same transfer function, so this conversion is valid for both primaries
/// up to the (different) RGB->XYZ matrix. This module uses sRGB primaries.
public func srgbToLinear(_ color: RGBColor) -> RGBColor {
    RGBColor(r: srgbToLinear(color.r), g: srgbToLinear(color.g), b: srgbToLinear(color.b))
}

/// Linear RGB to sRGB (gamma-encoded).
public func linearToSrgb(_ color: RGBColor) -> RGBColor {
    RGBColor(r: linearToSrgb(color.r), g: linearToSrgb(color.g), b: linearToSrgb(color.b))
}

/// Linear sRGB to CIE XYZ (D65).
public func linearRGBToXYZ(_ color: RGBColor) -> XYZColor {
    XYZColor(
        x: 0.4124 * color.r + 0.3576 * color.g + 0.1805 * color.b,
        y: 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b,
        z: 0.0193 * color.r + 0.1192 * color.g + 0.9505 * color.b
    )
}

/// CIE XYZ (D65) to linear sRGB.
public func xyzToLinearRGB(_ color: XYZColor) -> RGBColor {
    RGBColor(
        r: 3.2406 * color.x - 1.5372 * color.y - 0.4986 * color.z,
        g: -0.9689 * color.x + 1.8758 * color.y + 0.0415 * color.z,
        b: 0.0557 * color.x - 0.2040 * color.y + 1.0570 * color.z
    )
}

private func labForward(_ t: Float) -> Float {
    let delta: Float = 6.0 / 29.0
    if t > delta * delta * delta {
        return powFloat(t, 1.0 / 3.0)
    }
    return t / (3 * delta * delta) + 4.0 / 29.0
}

private func labInverse(_ t: Float) -> Float {
    let delta: Float = 6.0 / 29.0
    if t > delta {
        return t * t * t
    }
    return 3 * delta * delta * (t - 4.0 / 29.0)
}

/// CIE XYZ (D65) to CIE Lab.
public func xyzToLab(_ color: XYZColor) -> LabColor {
    let fx = labForward(color.x / d65White.x)
    let fy = labForward(color.y / d65White.y)
    let fz = labForward(color.z / d65White.z)
    return LabColor(l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz))
}

/// CIE Lab to CIE XYZ (D65).
public func labToXYZ(_ color: LabColor) -> XYZColor {
    let fy = (color.l + 16) / 116
    let fx = fy + color.a / 500
    let fz = fy - color.b / 200
    return XYZColor(
        x: d65White.x * labInverse(fx),
        y: d65White.y * labInverse(fy),
        z: d65White.z * labInverse(fz)
    )
}

/// sRGB to CIE Lab (via linear RGB and XYZ, D65).
public func srgbToLab(_ color: RGBColor) -> LabColor {
    xyzToLab(linearRGBToXYZ(srgbToLinear(color)))
}

/// CIE Lab to sRGB (via XYZ and linear RGB, D65).
public func labToSrgb(_ color: LabColor) -> RGBColor {
    linearToSrgb(xyzToLinearRGB(labToXYZ(color)))
}

/// Relative luminance (linear, 0...1) of an sRGB color.
public func luminance(_ color: RGBColor) -> Float {
    let linear = srgbToLinear(color)
    return 0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b
}

private func smoothBand(_ value: Float, low: Float, high: Float, feather: Float) -> Float {
    if value < low - feather || value > high + feather { return 0 }
    if value >= low && value <= high { return 1 }
    if value < low {
        return (value - (low - feather)) / feather
    }
    return ((high + feather) - value) / feather
}

/// Skin likelihood in 0...1 from a Lab color: skin sits at moderate
/// lightness with warm a/b. Heuristic only; the real mask also uses
/// the person mask and landmark regions.
public func skinLikelihood(lab: LabColor) -> Float {
    let lScore = smoothBand(lab.l, low: 30, high: 85, feather: 15)
    let aScore = smoothBand(lab.a, low: 5, high: 35, feather: 8)
    let bScore = smoothBand(lab.b, low: 5, high: 40, feather: 10)
    return lScore * aScore * bScore
}

/// Skin likelihood in 0...1 from an sRGB color, via the YCbCr skin
/// range (Cb 77...127, Cr 133...173) combined with the Lab heuristic.
public func skinLikelihood(rgb: RGBColor) -> Float {
    let r = rgb.r * 255
    let g = rgb.g * 255
    let b = rgb.b * 255
    let cb = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b
    let cr = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b
    let cbScore = smoothBand(cb, low: 77, high: 127, feather: 12)
    let crScore = smoothBand(cr, low: 133, high: 173, feather: 12)
    return cbScore * crScore * skinLikelihood(lab: srgbToLab(rgb))
}
