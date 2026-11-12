// What: Brush engine math — Catmull-Rom stroke smoothing, dab placement,
// and stamping dabs into a displacement field (CPU reference for Warp.metal).
// Inputs/Outputs: BrushStroke (normalized coords) in; BrushDab list / field out.
// Threading: Pure functions; safe on any thread.
import Foundation

/// Shared push gain: a push dab moves pixels by at most
/// `brushPushGain * radius * strength` at its center. The Metal
/// `stampBrushDabs` kernel uses the same constant — keep them in sync.
/// 0.15 keeps a full-strength stroke fold-free: overlapping dabs sum to
/// a gradient below 1 (see WarpMathTests.testNoFoldOverFullMaxSliderSet).
public let brushPushGain: Float = 0.15

/// Dab spacing as a fraction of brush diameter (15–25% per the spec;
/// 25% is the wide end: fewer overlapping dabs, so a stroke's summed
/// gradient stays below 1 and the map cannot fold over).
public func dabSpacing(diameter: Float) -> Float {
    diameter * 0.25
}

/// One brush dab: a circular push (or erase) stamped into the field.
/// `radius` is in normalized units (fraction of image width);
/// `direction` is the stroke tangent at the dab (unit length for push,
/// ignored for restore).
public struct BrushDab: Codable, Equatable, Sendable {
    public var center: Vec2
    public var direction: Vec2
    public var radius: Float
    public var strength: Float
    public var mode: BrushMode

    public init(
        center: Vec2,
        direction: Vec2,
        radius: Float,
        strength: Float,
        mode: BrushMode
    ) {
        self.center = center
        self.direction = direction
        self.radius = radius
        self.strength = strength
        self.mode = mode
    }
}

/// Uniform Catmull-Rom smoothing of a stroke polyline. Endpoints are
/// preserved; collinear input stays collinear. Fewer than 3 points are
/// returned unchanged (nothing to smooth).
public func catmullRomSmoothedPoints(_ points: [Vec2], subdivisions: Int = 4) -> [Vec2] {
    guard points.count >= 3, subdivisions > 0 else { return points }
    var out: [Vec2] = [points[0]]
    for i in 0..<(points.count - 1) {
        let p0 = points[max(i - 1, 0)]
        let p1 = points[i]
        let p2 = points[i + 1]
        let p3 = points[min(i + 2, points.count - 1)]
        for step in 1...subdivisions {
            let t = Float(step) / Float(subdivisions)
            let t2 = t * t
            let t3 = t2 * t
            // Standard Catmull-Rom basis (0.5 factor).
            let x = 0.5 * (
                (2 * p1.x)
                + (-p0.x + p2.x) * t
                + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2
                + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3
            )
            let y = 0.5 * (
                (2 * p1.y)
                + (-p0.y + p2.y) * t
                + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2
                + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3
            )
            out.append(Vec2(x, y))
        }
    }
    return out
}

/// Dab centers along a polyline, spaced `spacing` apart (normalized
/// units). The first point is always a dab; the last point is included
/// when the walk reaches it. Returns [] for an empty polyline.
public func dabCenters(points: [Vec2], spacing: Float) -> [Vec2] {
    guard let first = points.first else { return [] }
    guard points.count > 1, spacing > 0 else { return [first] }
    var centers: [Vec2] = [first]
    var carried: Float = 0
    var previous = first
    for point in points.dropFirst() {
        var segment = point - previous
        var remaining = segment.length
        while remaining + carried >= spacing {
            let step = spacing - carried
            let direction = remaining > 0 ? segment / remaining : Vec2.zero
            let dab = previous + direction * step
            centers.append(dab)
            segment = point - dab
            previous = dab
            remaining = segment.length
            carried = 0
        }
        carried += remaining
        previous = point
    }
    if let last = points.last, last != centers.last {
        centers.append(last)
    }
    return centers
}

/// Expands a stored stroke into dabs: smooth the polyline, place dab
/// centers 15–25% of the diameter apart, and give each dab the stroke
/// tangent as its push direction. Fast mode uses a 1.5x radius (coarse
/// push); restore dabs keep the stroke radius and erase instead.
public func brushDabs(from stroke: BrushStroke) -> [BrushDab] {
    let smoothed = catmullRomSmoothedPoints(stroke.points)
    let diameter = max(stroke.size, 0.001)
    let spacing = dabSpacing(diameter: diameter)
    let centers = dabCenters(points: smoothed, spacing: spacing)
    guard centers.count > 0 else { return [] }
    let radius = diameter / 2 * (stroke.mode == .fast ? 1.5 : 1)
    var dabs: [BrushDab] = []
    dabs.reserveCapacity(centers.count)
    for index in centers.indices {
        let before = centers[max(index - 1, 0)]
        let after = centers[min(index + 1, centers.count - 1)]
        var tangent = after - before
        let length = tangent.length
        tangent = length > 0 ? tangent / length : Vec2(1, 0)
        dabs.append(BrushDab(
            center: centers[index],
            direction: tangent,
            radius: radius,
            strength: stroke.strength,
            mode: stroke.mode
        ))
    }
    return dabs
}

/// Stamps one dab into a row-major field (`width` x `height`, normalized
/// coordinates). Push modes add displacement along the dab direction;
/// restore scales the existing displacement toward zero.
public func stampDab(field: inout [Vec2], width: Int, height: Int, dab: BrushDab) {
    switch dab.mode {
    case .classic, .fast:
        stampPushDab(field: &field, width: width, height: height, dab: dab)
    case .restore:
        stampRestoreDab(field: &field, width: width, height: height, dab: dab)
    }
}

/// Push dab: displacement += direction * falloff * strength * radius * gain.
public func stampPushDab(field: inout [Vec2], width: Int, height: Int, dab: BrushDab) {
    guard width > 0, height > 0, field.count == width * height else { return }
    guard dab.radius > 0 else { return }
    let radiusX = dab.radius * Float(width)
    let radiusY = dab.radius * Float(height)
    let centerX = dab.center.x * Float(width)
    let centerY = dab.center.y * Float(height)
    let minX = max(Int((centerX - radiusX).rounded(.down)), 0)
    let maxX = min(Int((centerX + radiusX).rounded(.up)), width - 1)
    let minY = max(Int((centerY - radiusY).rounded(.down)), 0)
    let maxY = min(Int((centerY + radiusY).rounded(.up)), height - 1)
    guard minX <= maxX, minY <= maxY else { return }
    for y in minY...maxY {
        for x in minX...maxX {
            let p = Vec2((Float(x) + 0.5) / Float(width), (Float(y) + 0.5) / Float(height))
            let distance = p.distance(to: dab.center)
            let f = falloff(distance: distance, radius: dab.radius)
            guard f > 0 else { continue }
            let index = y * width + x
            field[index] = field[index] + dab.direction * (f * dab.strength * dab.radius * brushPushGain)
        }
    }
}

/// Restore dab: scales the existing displacement toward zero by
/// (1 - falloff * strength), strongest at the dab center.
public func stampRestoreDab(field: inout [Vec2], width: Int, height: Int, dab: BrushDab) {
    guard width > 0, height > 0, field.count == width * height else { return }
    guard dab.radius > 0 else { return }
    let radiusX = dab.radius * Float(width)
    let radiusY = dab.radius * Float(height)
    let centerX = dab.center.x * Float(width)
    let centerY = dab.center.y * Float(height)
    let minX = max(Int((centerX - radiusX).rounded(.down)), 0)
    let maxX = min(Int((centerX + radiusX).rounded(.up)), width - 1)
    let minY = max(Int((centerY - radiusY).rounded(.down)), 0)
    let maxY = min(Int((centerY + radiusY).rounded(.up)), height - 1)
    guard minX <= maxX, minY <= maxY else { return }
    for y in minY...maxY {
        for x in minX...maxX {
            let p = Vec2((Float(x) + 0.5) / Float(width), (Float(y) + 0.5) / Float(height))
            let distance = p.distance(to: dab.center)
            let f = falloff(distance: distance, radius: dab.radius)
            guard f > 0 else { continue }
            let index = y * width + x
            field[index] = field[index] * (1 - f * dab.strength)
        }
    }
}

/// Stamps one dab into a TILE field: the tile's pixels map to full-image
/// normalized coordinates via the tile origin and the full image size.
/// Same push/restore math as stampDab(); used by the export tile loop,
/// where a dab's center is in full-image coordinates, not tile coordinates.
public func stampDabTile(
    field: inout [Vec2],
    tileWidth: Int,
    tileHeight: Int,
    tileOriginX: Int,
    tileOriginY: Int,
    imageWidth: Int,
    imageHeight: Int,
    dab: BrushDab
) {
    guard tileWidth > 0, tileHeight > 0, imageWidth > 0, imageHeight > 0 else { return }
    guard field.count == tileWidth * tileHeight, dab.radius > 0 else { return }
    let centerX = dab.center.x * Float(imageWidth) - Float(tileOriginX)
    let centerY = dab.center.y * Float(imageHeight) - Float(tileOriginY)
    let radiusX = dab.radius * Float(imageWidth)
    let radiusY = dab.radius * Float(imageHeight)
    let minX = max(Int((centerX - radiusX).rounded(.down)), 0)
    let maxX = min(Int((centerX + radiusX).rounded(.up)), tileWidth - 1)
    let minY = max(Int((centerY - radiusY).rounded(.down)), 0)
    let maxY = min(Int((centerY + radiusY).rounded(.up)), tileHeight - 1)
    guard minX <= maxX, minY <= maxY else { return }
    for y in minY...maxY {
        for x in minX...maxX {
            let p = Vec2(
                (Float(tileOriginX + x) + 0.5) / Float(imageWidth),
                (Float(tileOriginY + y) + 0.5) / Float(imageHeight))
            let distance = p.distance(to: dab.center)
            let f = falloff(distance: distance, radius: dab.radius)
            guard f > 0 else { continue }
            let index = y * tileWidth + x
            switch dab.mode {
            case .classic, .fast:
                field[index] = field[index] + dab.direction * (f * dab.strength * dab.radius * brushPushGain)
            case .restore:
                field[index] = field[index] * (1 - f * dab.strength)
            }
        }
    }
}
