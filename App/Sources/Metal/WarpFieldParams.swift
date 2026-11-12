// WarpFieldParams — Swift mirrors of the Metal structs in Warp.metal.
// What: WarpOpParams + BrushDabParams, 32 bytes each, layout-checked
// against the Metal side (see stride checks below; a mismatch makes the
// field kernel read garbage, so RenderGraph refuses to build the field).
// Inputs-outputs: EditorCore WarpOp / BrushDab in; Metal-ready params out.
// Threading: value types; created on the render thread, copied into buffers.
import Foundation
import EditorCore

/// Mirror of Metal `WarpOpParams`: type 0 scale, 1 translate, 2 pinch;
/// axes 0 both, 1 horizontal, 2 vertical. Stride must be 32 bytes.
struct WarpOpParams {
    var type: UInt32
    var axes: UInt32
    var center: SIMD2<Float>
    var direction: SIMD2<Float>
    var radius: Float
    var amount: Float

    /// Expected stride; must equal sizeof(WarpOpParams) in Warp.metal.
    static let expectedStride = 32

    init(from op: WarpOp) {
        switch op.type {
        case .scale: type = 0
        case .translate: type = 1
        case .pinch: type = 2
        }
        switch op.axes {
        case .both: axes = 0
        case .horizontal: axes = 1
        case .vertical: axes = 2
        }
        center = SIMD2<Float>(op.center.x, op.center.y)
        direction = SIMD2<Float>(op.direction.x, op.direction.y)
        radius = op.radius
        amount = op.amount
    }
}

/// Mirror of Metal `BrushDabParams`: mode 0 classic, 1 fast, 2 restore.
/// Stride must be 32 bytes.
struct BrushDabParams {
    var center: SIMD2<Float>
    var direction: SIMD2<Float>
    var radius: Float
    var strength: Float
    var mode: UInt32
    var padding: UInt32

    /// Expected stride; must equal sizeof(BrushDabParams) in Warp.metal.
    static let expectedStride = 32

    init(from dab: BrushDab) {
        center = SIMD2<Float>(dab.center.x, dab.center.y)
        direction = SIMD2<Float>(dab.direction.x, dab.direction.y)
        radius = dab.radius
        strength = dab.strength
        switch dab.mode {
        case .classic: mode = 0
        case .fast: mode = 1
        case .restore: mode = 2
        }
        padding = 0
    }
}

/// Layout check for both param structs. RenderGraph calls this before
/// building a field; false means the Swift/Metal structs drifted apart.
enum WarpFieldParams {
    static func stridesMatch() -> Bool {
        MemoryLayout<WarpOpParams>.stride == WarpOpParams.expectedStride
            && MemoryLayout<BrushDabParams>.stride == BrushDabParams.expectedStride
    }

    /// Max ops the field kernel loops over (AGENTS.md 7E: cap 64).
    static let maxOps = 64

    /// Max dabs the stamp kernel loops over per render.
    static let maxDabs = 2048
}
