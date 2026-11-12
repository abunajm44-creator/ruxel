// What: CPU skin-mask building for export — face-oval rasterization,
// person-mask resampling, and the combined feathered skin mask.
// Inputs/Outputs: tile geometry + landmarks + RGB channels in; mask out.
// Threading: Pure functions; safe on any thread.
import Foundation

/// Ray-casting point-in-polygon test for a normalized point against a
/// normalized contour. Points on the edge count as inside.
public func pointInPolygon(_ point: Vec2, polygon: [Vec2]) -> Bool {
    guard polygon.count >= 3 else { return false }
    var inside = false
    var j = polygon.count - 1
    for i in 0..<polygon.count {
        let a = polygon[i]
        let b = polygon[j]
        if (a.y > point.y) != (b.y > point.y) {
            let intersectX = (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x
            if point.x < intersectX {
                inside.toggle()
            }
        }
        j = i
    }
    return inside
}

/// Face-oval mask for one export tile: 1 inside the landmark contour,
/// 0 outside. Tile pixels map to full-image normalized coordinates via
/// the tile origin and image size. Returns all zeros for an empty contour.
public func faceOvalMask(
    tileWidth: Int,
    tileHeight: Int,
    tileOriginX: Int,
    tileOriginY: Int,
    imageWidth: Int,
    imageHeight: Int,
    contour: [Vec2]
) -> [Float] {
    guard tileWidth > 0, tileHeight > 0, imageWidth > 0, imageHeight > 0 else { return [] }
    guard contour.count >= 3 else { return [Float](repeating: 0, count: tileWidth * tileHeight) }
    var mask = [Float](repeating: 0, count: tileWidth * tileHeight)
    for y in 0..<tileHeight {
        for x in 0..<tileWidth {
            let point = Vec2(
                Float(tileOriginX + x) / Float(imageWidth),
                Float(tileOriginY + y) / Float(imageHeight)
            )
            mask[y * tileWidth + x] = pointInPolygon(point, polygon: contour) ? 1 : 0
        }
    }
    return mask
}

/// Bilinear resampling of a proxy person mask (maskWidth x maskHeight)
/// into one export tile's pixels. Returns all zeros for an empty mask.
public func personMaskRegion(
    mask: [Float],
    maskWidth: Int,
    maskHeight: Int,
    tileWidth: Int,
    tileHeight: Int,
    tileOriginX: Int,
    tileOriginY: Int,
    imageWidth: Int,
    imageHeight: Int
) -> [Float] {
    guard tileWidth > 0, tileHeight > 0, imageWidth > 0, imageHeight > 0 else { return [] }
    guard maskWidth > 0, maskHeight > 0, mask.count == maskWidth * maskHeight else {
        return [Float](repeating: 0, count: tileWidth * tileHeight)
    }
    var out = [Float](repeating: 0, count: tileWidth * tileHeight)
    for y in 0..<tileHeight {
        for x in 0..<tileWidth {
            let sampleX = (Float(tileOriginX + x) / Float(imageWidth)) * Float(maskWidth - 1)
            let sampleY = (Float(tileOriginY + y) / Float(imageHeight)) * Float(maskHeight - 1)
            out[y * tileWidth + x] = bilinearSample(
                src: mask, width: maskWidth, height: maskHeight, x: sampleX, y: sampleY
            )
        }
    }
    return out
}

/// Combined skin mask for one export tile: person mask AND face oval AND
/// per-pixel skin likelihood (Lab/YCbCr heuristic), feathered. Returns []
/// when the person mask or the oval is empty (caller then skips the skin
/// stage — smoothing without a mask would smooth clothes and background).
public func skinMask(
    red: [Float],
    green: [Float],
    blue: [Float],
    width: Int,
    height: Int,
    personMask: [Float],
    faceOval: [Float]
) -> [Float] {
    let count = width * height
    guard width > 0, height > 0,
          red.count == count, green.count == count, blue.count == count,
          personMask.count == count, faceOval.count == count else { return [] }
    guard personMask.contains(where: { $0 > 0 }),
          faceOval.contains(where: { $0 > 0 }) else { return [] }
    var mask = [Float](repeating: 0, count: count)
    for i in 0..<count {
        let likelihood = skinLikelihood(rgb: RGBColor(r: red[i], g: green[i], b: blue[i]))
        mask[i] = min(personMask[i], faceOval[i]) * likelihood
    }
    return feather(mask: mask, width: width, height: height, radius: 2)
}
