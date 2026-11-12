import Foundation

// RenderError — typed errors for Metal setup and dispatch failures.
// What: every failure mode of MetalContext / RenderGraph, as LocalizedError.
// Inputs-outputs: thrown by pipeline creation and encoding; shown in Arabic by UI.
// Threading: value type; safe to pass across threads.
enum RenderError: LocalizedError {
    case missingFunction(String)
    case noEncoder
    case noDevice
    case noCommandBuffer
    case textureCreationFailed
    /// Swift/Metal param structs drifted apart (stride mismatch).
    case invalidParamsStride
    /// A persistent field-build buffer could not be created.
    case fieldBufferFailed

    var errorDescription: String? {
        switch self {
        case .missingFunction(let name):
            return "Metal kernel not found: \(name)."
        case .noEncoder:
            return "Could not create a Metal compute encoder."
        case .noDevice:
            return "This device has no Metal GPU available."
        case .noCommandBuffer:
            return "Could not create a Metal command buffer."
        case .textureCreationFailed:
            return "Could not create a Metal texture."
        case .invalidParamsStride:
            return "Warp field parameter layout does not match the Metal kernel."
        case .fieldBufferFailed:
            return "Could not create the warp field buffer."
        }
    }
}
