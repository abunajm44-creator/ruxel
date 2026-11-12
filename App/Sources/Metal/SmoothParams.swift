import Foundation

// SmoothParams — Swift mirror of the Metal struct of the same name in Warp.metal.
// What: strength (mask-scaled blend) and textureKeep (detail preserved in low pass).
// Inputs-outputs: both Float, 0...1; stride must be 8 bytes on both sides.
// Threading: value type; created on the main actor, copied into a Metal buffer.
struct SmoothParams {
    var strength: Float
    var textureKeep: Float
}

extension SmoothParams {
    /// Expected stride; must equal sizeof(SmoothParams) in Warp.metal (8 bytes).
    static let expectedStride = 8
}
