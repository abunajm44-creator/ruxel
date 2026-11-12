// What: Float-mask operations: feathering, dilation, combination, gaussian weights.
// Inputs/Outputs: Row-major Float masks (0...1) in; processed masks / weights out.
// Threading: Pure functions; safe on any thread.
import Foundation

/// How two masks combine.
public enum MaskCombineOperation: String, Codable, Hashable, Sendable {
    case and
    case or
    case minus
}

/// Gaussian weight for a distance, given a sigma. Returns 0 for sigma <= 0.
public func gaussianWeight(distance: Float, sigma: Float) -> Float {
    guard sigma > 0 else { return 0 }
    let t = distance / sigma
    return Float(exp(Double(-0.5 * t * t)))
}

private func boxBlurPass(
    src: [Float],
    width: Int,
    height: Int,
    radius: Int,
    horizontal: Bool
) -> [Float] {
    var out = [Float](repeating: 0, count: src.count)
    let window = 2 * radius + 1
    if horizontal {
        for y in 0..<height {
            var sum: Float = 0
            for k in -radius...radius {
                let x = min(max(k, 0), width - 1)
                sum += src[y * width + x]
            }
            for x in 0..<width {
                out[y * width + x] = sum / Float(window)
                let removeX = min(max(x - radius, 0), width - 1)
                let addX = min(max(x + radius + 1, 0), width - 1)
                sum += src[y * width + addX] - src[y * width + removeX]
            }
        }
    } else {
        for x in 0..<width {
            var sum: Float = 0
            for k in -radius...radius {
                let y = min(max(k, 0), height - 1)
                sum += src[y * width + x]
            }
            for y in 0..<height {
                out[y * width + x] = sum / Float(window)
                let removeY = min(max(y - radius, 0), height - 1)
                let addY = min(max(y + radius + 1, 0), height - 1)
                sum += src[addY * width + x] - src[removeY * width + x]
            }
        }
    }
    return out
}

/// Feather a mask with a separable box blur of the given radius.
/// Radius 0 returns the input unchanged. Edges are clamped.
public func feather(mask: [Float], width: Int, height: Int, radius: Int) -> [Float] {
    guard width > 0, height > 0, mask.count == width * height else { return mask }
    guard radius > 0 else { return mask }
    let horizontal = boxBlurPass(src: mask, width: width, height: height, radius: radius, horizontal: true)
    return boxBlurPass(src: horizontal, width: width, height: height, radius: radius, horizontal: false)
}

/// Dilate a mask by `radius` pixels (square max filter).
/// Radius 0 returns the input unchanged.
public func dilate(mask: [Float], width: Int, height: Int, radius: Int) -> [Float] {
    guard width > 0, height > 0, mask.count == width * height else { return mask }
    guard radius > 0 else { return mask }
    var out = [Float](repeating: 0, count: mask.count)
    for y in 0..<height {
        for x in 0..<width {
            var best: Float = 0
            for dy in -radius...radius {
                for dx in -radius...radius {
                    let nx = x + dx
                    let ny = y + dy
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    best = max(best, mask[ny * width + nx])
                }
            }
            out[y * width + x] = best
        }
    }
    return out
}

/// Combine two equal-size masks. `and` = min, `or` = max,
/// `minus` = a * (1 - b). Mismatched sizes return the first mask.
public func combineMasks(_ a: [Float], _ b: [Float], operation: MaskCombineOperation) -> [Float] {
    guard a.count == b.count else { return a }
    var out = [Float](repeating: 0, count: a.count)
    for i in 0..<a.count {
        switch operation {
        case .and:
            out[i] = min(a[i], b[i])
        case .or:
            out[i] = max(a[i], b[i])
        case .minus:
            out[i] = a[i] * (1 - b[i])
        }
    }
    return out
}
