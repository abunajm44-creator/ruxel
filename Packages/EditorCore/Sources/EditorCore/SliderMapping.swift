// What: Maps bipolar -100...100 sliders to safe physical amounts per tool.
// Inputs/Outputs: Slider value + tool in; clamped physical amount out.
// Threading: Pure functions; safe on any thread.
import Foundation

/// A retouch tool whose slider maps to a physical amount.
public enum RetouchTool: String, Codable, Hashable, Sendable {
    case eyeSize
    case eyeHeight
    case eyeWidth
    case eyeLength
    case eyeSpacing
    case eyePuffy
    case eyeAngle
    case eyePosition
    case noseSize
    case noseWidth
    case noseLift
    case noseAla
    case noseRoot
    case noseBridge
    case noseTip
    case lipSize
    case lipWidth
    case lipThickness
    case lipSmile
    case lipPosition
    case lipMShape
    case browHeight
    case browDistance
    case browThickness
    case browAngle
    case browLength
    case browShape
    case faceWidth
    case jawSize
    case chinLength
    case chinWidth
    case cheekbones
    case temples
    case foreheadHeight
    case faceLength
    case vShape
    case bodySlim
    case waist
    case hips
    case legLength
    case shoulders
    case neck
    case skinSmoothing
    case skinTexture
    case skinGrain
    case shineReduction
    case wrinkleReduction
    case acneRemoval
    case darkCircles
    case teethWhitening
    case eyeEnhance
}

/// Every tool that produces a warp displacement (face + body).
/// The no-fold-over test drives all of these at max at once.
public let allWarpTools: [RetouchTool] = [
    .eyeSize, .eyeHeight, .eyeWidth, .eyeLength, .eyeSpacing, .eyePuffy,
    .eyeAngle, .eyePosition, .noseSize, .noseWidth, .noseLift, .noseAla,
    .noseRoot, .noseBridge, .noseTip, .lipSize, .lipWidth, .lipThickness,
    .lipSmile, .lipPosition, .lipMShape, .browHeight, .browDistance,
    .browThickness, .browAngle, .browLength, .browShape, .faceWidth,
    .jawSize, .chinLength, .chinWidth, .cheekbones, .temples,
    .foreheadHeight, .faceLength, .vShape, .bodySlim, .waist, .hips,
    .legLength, .shoulders, .neck
]

/// Per-tool mapping limits. `maxAmount` is the physical amount at
/// slider +100; `bidirectional` tools also allow -maxAmount at -100,
/// while one-way tools (smoothing, whitening, ...) clamp below at 0.
/// For translate tools (eyeLength, eyeSpacing, eyeAngle, eyePosition,
/// noseLift, lipSmile, lipPosition, browHeight, browDistance, browAngle,
/// browLength, chinLength, foreheadHeight) `maxAmount` is a fraction of
/// the inter-pupil distance: faceWarpOps multiplies it by the IPD, so a
/// translate's peak shift scales with the face and its gradient
/// (~1.5 * amount / radius) stays fold-free at any face size.
/// Translate caps were tuned DOWN (2026-11-12) because eight eye/brow
/// translates overlap in a small region: at the old caps (0.12–0.15) the
/// summed displacement folded (Jacobian −8.6 at full max); at the current
/// caps the full max-slider set stays above 0.05 (see WarpMathTests).
/// The negative set needed a second round: chinLength 0.20→0.15, jawSize
/// 0.30→0.25, faceLength 0.25→0.20, bodySlim 0.35→0.30, and the leg-length
/// shift factor 0.25→0.15 — the chin/jaw + leg translates overlap and
/// folded the map at −100 (Jacobian −0.39).
public struct ToolMapping: Codable, Equatable, Sendable {
    public var maxAmount: Float
    public var bidirectional: Bool
    public var radiusInIPD: Float

    public init(maxAmount: Float, bidirectional: Bool, radiusInIPD: Float) {
        self.maxAmount = maxAmount
        self.bidirectional = bidirectional
        self.radiusInIPD = radiusInIPD
    }
}

/// Safe-limit table. Caps were chosen so the summed displacement keeps
/// a positive Jacobian determinant (see WarpMathTests.noFoldOver).
public func toolMapping(for tool: RetouchTool) -> ToolMapping {
    switch tool {
    case .eyeSize: return ToolMapping(maxAmount: 0.25, bidirectional: true, radiusInIPD: 0.6)
    case .eyeHeight: return ToolMapping(maxAmount: 0.20, bidirectional: true, radiusInIPD: 0.5)
    case .eyeWidth: return ToolMapping(maxAmount: 0.20, bidirectional: true, radiusInIPD: 0.5)
    case .eyeLength: return ToolMapping(maxAmount: 0.10, bidirectional: true, radiusInIPD: 0.6)
    case .eyeSpacing: return ToolMapping(maxAmount: 0.10, bidirectional: true, radiusInIPD: 0.8)
    case .eyePuffy: return ToolMapping(maxAmount: 0.15, bidirectional: true, radiusInIPD: 0.5)
    case .eyeAngle: return ToolMapping(maxAmount: 0.08, bidirectional: true, radiusInIPD: 0.5)
    case .eyePosition: return ToolMapping(maxAmount: 0.08, bidirectional: true, radiusInIPD: 0.6)
    case .noseSize: return ToolMapping(maxAmount: 0.30, bidirectional: true, radiusInIPD: 0.7)
    case .noseWidth: return ToolMapping(maxAmount: 0.25, bidirectional: true, radiusInIPD: 0.5)
    case .noseLift: return ToolMapping(maxAmount: 0.12, bidirectional: true, radiusInIPD: 0.6)
    case .noseAla: return ToolMapping(maxAmount: 0.25, bidirectional: true, radiusInIPD: 0.4)
    case .noseRoot: return ToolMapping(maxAmount: 0.15, bidirectional: true, radiusInIPD: 0.5)
    case .noseBridge: return ToolMapping(maxAmount: 0.25, bidirectional: true, radiusInIPD: 0.5)
    case .noseTip: return ToolMapping(maxAmount: 0.15, bidirectional: true, radiusInIPD: 0.4)
    case .lipSize: return ToolMapping(maxAmount: 0.30, bidirectional: true, radiusInIPD: 0.7)
    case .lipWidth: return ToolMapping(maxAmount: 0.25, bidirectional: true, radiusInIPD: 0.6)
    case .lipThickness: return ToolMapping(maxAmount: 0.25, bidirectional: true, radiusInIPD: 0.5)
    case .lipSmile: return ToolMapping(maxAmount: 0.12, bidirectional: true, radiusInIPD: 0.5)
    case .lipPosition: return ToolMapping(maxAmount: 0.10, bidirectional: true, radiusInIPD: 0.6)
    case .lipMShape: return ToolMapping(maxAmount: 0.15, bidirectional: true, radiusInIPD: 0.5)
    case .browHeight: return ToolMapping(maxAmount: 0.10, bidirectional: true, radiusInIPD: 0.6)
    case .browDistance: return ToolMapping(maxAmount: 0.08, bidirectional: true, radiusInIPD: 0.6)
    case .browThickness: return ToolMapping(maxAmount: 0.20, bidirectional: true, radiusInIPD: 0.6)
    case .browAngle: return ToolMapping(maxAmount: 0.08, bidirectional: true, radiusInIPD: 0.6)
    case .browLength: return ToolMapping(maxAmount: 0.10, bidirectional: true, radiusInIPD: 0.6)
    case .browShape: return ToolMapping(maxAmount: 0.15, bidirectional: true, radiusInIPD: 0.6)
    case .faceWidth: return ToolMapping(maxAmount: 0.35, bidirectional: true, radiusInIPD: 2.0)
    case .jawSize: return ToolMapping(maxAmount: 0.25, bidirectional: true, radiusInIPD: 1.5)
    case .chinLength: return ToolMapping(maxAmount: 0.10, bidirectional: true, radiusInIPD: 1.0)
    case .chinWidth: return ToolMapping(maxAmount: 0.25, bidirectional: true, radiusInIPD: 0.8)
    case .cheekbones: return ToolMapping(maxAmount: 0.25, bidirectional: true, radiusInIPD: 0.8)
    case .temples: return ToolMapping(maxAmount: 0.20, bidirectional: true, radiusInIPD: 0.8)
    case .foreheadHeight: return ToolMapping(maxAmount: 0.15, bidirectional: true, radiusInIPD: 1.0)
    case .faceLength: return ToolMapping(maxAmount: 0.20, bidirectional: true, radiusInIPD: 1.5)
    case .vShape: return ToolMapping(maxAmount: 0.25, bidirectional: true, radiusInIPD: 1.2)
    case .bodySlim: return ToolMapping(maxAmount: 0.30, bidirectional: true, radiusInIPD: 3.0)
    case .waist: return ToolMapping(maxAmount: 0.30, bidirectional: true, radiusInIPD: 2.0)
    case .hips: return ToolMapping(maxAmount: 0.30, bidirectional: true, radiusInIPD: 2.0)
    case .legLength: return ToolMapping(maxAmount: 0.20, bidirectional: true, radiusInIPD: 3.0)
    case .shoulders: return ToolMapping(maxAmount: 0.25, bidirectional: true, radiusInIPD: 2.0)
    case .neck: return ToolMapping(maxAmount: 0.20, bidirectional: true, radiusInIPD: 1.0)
    case .skinSmoothing: return ToolMapping(maxAmount: 0.8, bidirectional: false, radiusInIPD: 0)
    case .skinTexture: return ToolMapping(maxAmount: 1.0, bidirectional: false, radiusInIPD: 0)
    case .skinGrain: return ToolMapping(maxAmount: 1.0, bidirectional: false, radiusInIPD: 0)
    case .shineReduction: return ToolMapping(maxAmount: 1.0, bidirectional: false, radiusInIPD: 0)
    case .wrinkleReduction: return ToolMapping(maxAmount: 1.0, bidirectional: false, radiusInIPD: 0)
    case .acneRemoval: return ToolMapping(maxAmount: 1.0, bidirectional: false, radiusInIPD: 0)
    case .darkCircles: return ToolMapping(maxAmount: 1.0, bidirectional: false, radiusInIPD: 0)
    case .teethWhitening: return ToolMapping(maxAmount: 1.0, bidirectional: false, radiusInIPD: 0)
    case .eyeEnhance: return ToolMapping(maxAmount: 1.0, bidirectional: false, radiusInIPD: 0)
    }
}

/// Clamps a raw slider value into the -100...100 range.
public func clampSlider(_ slider: Float) -> Float {
    min(max(slider, -100), 100)
}

/// Maps a slider (-100...100) to the tool's physical amount.
/// Out-of-range sliders are clamped first; one-way tools never go below 0.
public func mappedAmount(slider: Float, tool: RetouchTool) -> Float {
    let mapping = toolMapping(for: tool)
    let clamped = clampSlider(slider) / 100
    let amount = clamped * mapping.maxAmount
    if mapping.bidirectional {
        return amount
    }
    return max(amount, 0)
}

/// Warp radius for a tool, in inter-pupil-distance units.
public func warpRadius(for tool: RetouchTool) -> Float {
    toolMapping(for: tool).radiusInIPD
}
