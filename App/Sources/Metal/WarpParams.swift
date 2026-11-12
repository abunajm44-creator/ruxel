import Foundation

// WarpParams — Swift mirror of the Metal struct of the same name in Warp.metal.
// What: one 4-byte flag controlling background locking in applyDisplacement.
// Inputs-outputs: backgroundLock != 0 multiplies displacement by the person mask.
// Threading: value type; created on the main actor, copied into a Metal buffer.
struct WarpParams {
    var backgroundLock: UInt32
}

extension WarpParams {
    /// Expected stride; must equal sizeof(WarpParams) in Warp.metal (4 bytes).
    static let expectedStride = 4
}
