// What: Smooth falloff and displacement-field math for face/body warps.
// Inputs/Outputs: Points, centers, radii (IPD units) and amounts in; Vec2 displacements out.
// Threading: Pure functions; safe on any thread.
import Foundation

/// Kind of warp operation.
public enum WarpOpType: String, Codable, Hashable, Sendable {
    case scale
    case translate
    case pinch
}

/// Which axes a warp operation may move.
public enum WarpAxes: String, Codable, Hashable, Sendable {
    case both
    case horizontal
    case vertical
}

/// One warp operation: a slider-driven deformation around a center.
/// - `center`: normalized coordinates (0...1).
/// - `radius`: falloff radius in inter-pupil-distance (IPD) units.
/// - `amount`: signed strength; sign meaning depends on `type`.
/// - `direction`: unit direction used only by `.translate`.
public struct WarpOp: Codable, Equatable, Sendable {
    public var type: WarpOpType
    public var center: Vec2
    public var radius: Float
    public var amount: Float
    public var axes: WarpAxes
    public var direction: Vec2

    public init(
        type: WarpOpType,
        center: Vec2,
        radius: Float,
        amount: Float,
        axes: WarpAxes = .both,
        direction: Vec2 = Vec2(1, 0)
    ) {
        self.type = type
        self.center = center
        self.radius = radius
        self.amount = amount
        self.axes = axes
        self.direction = direction
    }
}

/// 1 at the center, 0 at/after `radius`, zero slope at both ends.
/// Smoothstep: 1 - t*t*(3 - 2t) with t = clamp(d / r, 0, 1).
public func falloff(distance d: Float, radius r: Float) -> Float {
    guard r > 0 else { return 0 }
    let t = min(max(d / r, 0), 1)
    return 1 - t * t * (3 - 2 * t)
}

/// Scale warp: amount > 0 enlarges around `center`, amount < 0 shrinks.
/// Displacement is -offset * falloff * distance * amount.
public func scaleDisplacement(at p: Vec2, center: Vec2, radius: Float, amount: Float) -> Vec2 {
    let dx = p.x - center.x
    let dy = p.y - center.y
    let distance = (dx * dx + dy * dy).squareRoot()
    let w = falloff(distance: distance, radius: radius) * distance * amount
    return Vec2(-dx * w, -dy * w)
}

/// Translate warp: moves content near `center` along `direction` by
/// `amount` (in normalized units), fading to zero at `radius`.
/// BACKWARD-MAP CONVENTION (read before changing this): the renderers
/// sample the source at p + D(p), so a feature moves OPPOSITE to the
/// field vector. The field returned here is therefore the NEGATION of
/// the intended motion: D = -direction * falloff * amount. The WarpOp's
/// `direction` is the intended content motion (e.g. nose lift = up);
/// this function converts it into the backward field the samplers need.
/// The Metal `warpOpDisplacement` kernel must mirror this sign exactly.
public func translateDisplacement(
    at p: Vec2,
    center: Vec2,
    radius: Float,
    amount: Float,
    direction: Vec2 = Vec2(1, 0)
) -> Vec2 {
    let distance = p.distance(to: center)
    let w = falloff(distance: distance, radius: radius) * amount
    return -direction * w
}

/// Pinch warp: pulls content toward `center`. Amount > 0 pinches inward,
/// amount < 0 pushes outward. The pull is strongest near the center and
/// fades to zero at `radius`, and the displacement itself is zero at the
/// center (it is proportional to the offset), so the map stays smooth
/// and fold-free there. Unlike scale, whose profile grows with distance,
/// pinch peaks at the center.
/// BACKWARD-MAP CONVENTION: the renderers sample at p + D(p), so content
/// moves opposite to the field. To pull content toward the center the
/// field must point AWAY from it: D = +offset * falloff * (1-t) * amount.
/// (Scale has the opposite sign because enlarging also moves content
/// away from the center — its field points toward it. The two ops are
/// not the same: scale grows with distance, pinch peaks at the center.)
/// The Metal `warpOpDisplacement` kernel must mirror this sign exactly.
public func pinchDisplacement(at p: Vec2, center: Vec2, radius: Float, amount: Float) -> Vec2 {
    let dx = p.x - center.x
    let dy = p.y - center.y
    let distance = (dx * dx + dy * dy).squareRoot()
    guard radius > 0, distance > 0 else { return .zero }
    let t = min(distance / radius, 1)
    let w = falloff(distance: distance, radius: radius) * (1 - t) * amount
    return Vec2(dx * w, dy * w)
}

/// Displacement of a single op at a point, with its axes mask applied.
public func displacement(of op: WarpOp, at p: Vec2) -> Vec2 {
    let raw: Vec2
    switch op.type {
    case .scale:
        raw = scaleDisplacement(at: p, center: op.center, radius: op.radius, amount: op.amount)
    case .translate:
        raw = translateDisplacement(at: p, center: op.center, radius: op.radius, amount: op.amount, direction: op.direction)
    case .pinch:
        raw = pinchDisplacement(at: p, center: op.center, radius: op.radius, amount: op.amount)
    }
    switch op.axes {
    case .both: return raw
    case .horizontal: return Vec2(raw.x, 0)
    case .vertical: return Vec2(0, raw.y)
    }
}

/// Sum of all ops' displacements at a point.
public func summedDisplacement(at p: Vec2, ops: [WarpOp]) -> Vec2 {
    var total = Vec2.zero
    for op in ops {
        total = total + displacement(of: op, at: p)
    }
    return total
}

/// Minimum Jacobian determinant of the warped map p + D(p) over a grid.
/// `displacement` holds one Vec2 per grid cell, row-major, with
/// `grid.width * grid.height` entries. Returns 1 for a degenerate grid
/// (identity map). A value <= 0 means the map folds over itself.
public func displacementJacobianDeterminant(
    grid: (width: Int, height: Int),
    displacement: [Vec2]
) -> Float {
    let width = grid.width
    let height = grid.height
    guard width >= 3, height >= 3, displacement.count == width * height else { return 1 }
    var minimum: Float = .greatestFiniteMagnitude
    for y in 1..<(height - 1) {
        for x in 1..<(width - 1) {
            let index = y * width + x
            let dux = (displacement[index + 1].x - displacement[index - 1].x) / 2
            let duy = (displacement[index + width].y - displacement[index - width].y) / 2
            let duxDy = (displacement[index + width].x - displacement[index - width].x) / 2
            let duyDx = (displacement[index + 1].y - displacement[index - 1].y) / 2
            // Grid spacing is 1 cell, so d(warped)/d(grid) = I + grad(D).
            let det = (1 + dux) * (1 + duy) - duxDy * duyDx
            if det < minimum { minimum = det }
        }
    }
    return minimum
}

/// Far-side multiplier for a pose-aware warp op. `poseAngle` is the face
/// angle in radians (yaw for left/right, pitch for up/down); `attenuation`
/// is the 0...1 factor stored on the face (0 = no attenuation, 1 = the far
/// side is frozen at a 45-degree pose). Returns 1 at zero pose or zero
/// attenuation. VERIFY: Vision's yaw sign (which side is far) is assumed
/// here — positive yaw turns the face so its left side is far; flip the
/// caller's side choice if the SDK probe says otherwise.
public func farSideAttenuationFactor(poseAngle: Float, attenuation: Float) -> Float {
    let clamped = min(max(attenuation, 0), 1)
    guard clamped > 0 else { return 1 }
    let pose = min(abs(poseAngle) / (Float.pi / 4), 1)
    return 1 - clamped * pose
}

/// Background lock: multiplies every field vector by the feathered person
/// mask (1 = person, may move; 0 = background, locked). Mismatched
/// buffers return the field unchanged.
public func applyBackgroundLock(field: [Vec2], mask: [Float]) -> [Vec2] {
    guard field.count == mask.count else { return field }
    var out = field
    for i in 0..<field.count {
        out[i] = field[i] * mask[i]
    }
    return out
}

/// Summed displacement of `ops` plus brush `dabs` on a `cols` x `rows`
/// grid over normalized [0,1]x[0,1], row-major. Used for the debug field
/// overlay and the CPU export path (one grid per tile).
public func displacementFieldGrid(
    cols: Int,
    rows: Int,
    ops: [WarpOp],
    dabs: [BrushDab]
) -> [Vec2] {
    guard cols > 0, rows > 0 else { return [] }
    var field = [Vec2](repeating: .zero, count: cols * rows)
    for y in 0..<rows {
        for x in 0..<cols {
            let p = Vec2(
                cols > 1 ? Float(x) / Float(cols - 1) : 0.5,
                rows > 1 ? Float(y) / Float(rows - 1) : 0.5
            )
            field[y * cols + x] = summedDisplacement(at: p, ops: ops)
        }
    }
    for dab in dabs {
        stampDab(field: &field, width: cols, height: rows, dab: dab)
    }
    return field
}

/// Displacement field for ONE export tile, in normalized units.
/// Tile pixels map to full-image normalized coordinates via the tile
/// origin and image size, so ops and dabs (stored in full-image
/// coordinates) evaluate exactly as they do on the full grid — a tile's
/// field equals the corresponding crop of the full-image field.
/// Sampling is at pixel centers, unlike displacementFieldGrid's
/// node sampling (used for the debug overlay only).
public func tileDisplacementField(
    tileOriginX: Int,
    tileOriginY: Int,
    tileWidth: Int,
    tileHeight: Int,
    imageWidth: Int,
    imageHeight: Int,
    ops: [WarpOp],
    dabs: [BrushDab]
) -> [Vec2] {
    guard tileWidth > 0, tileHeight > 0, imageWidth > 0, imageHeight > 0 else { return [] }
    var field = [Vec2](repeating: .zero, count: tileWidth * tileHeight)
    for y in 0..<tileHeight {
        for x in 0..<tileWidth {
            let p = Vec2(
                (Float(tileOriginX + x) + 0.5) / Float(imageWidth),
                (Float(tileOriginY + y) + 0.5) / Float(imageHeight))
            field[y * tileWidth + x] = summedDisplacement(at: p, ops: ops)
        }
    }
    for dab in dabs {
        stampDabTile(
            field: &field, tileWidth: tileWidth, tileHeight: tileHeight,
            tileOriginX: tileOriginX, tileOriginY: tileOriginY,
            imageWidth: imageWidth, imageHeight: imageHeight, dab: dab)
    }
    return field
}

/// Largest displacement magnitude any op in `ops` can produce, in
/// normalized units. The export halo is derived from this (plus the
/// blur kernel radius), so no tile samples outside its halo rect.
public func maxDisplacementMagnitude(ops: [WarpOp]) -> Float {
    var maximum: Float = 0
    for op in ops {
        // Scale/pinch peak at ~radius * |amount|; translate peaks at |amount|.
        let peak: Float
        switch op.type {
        case .scale, .pinch:
            peak = abs(op.amount) * op.radius
        case .translate:
            peak = abs(op.amount)
        }
        maximum = max(maximum, peak)
    }
    return maximum
}
