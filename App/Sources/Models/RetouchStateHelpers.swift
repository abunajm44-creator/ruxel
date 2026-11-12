import Foundation
import EditorCore

// RetouchStateHelpers — app-side conveniences on EditorCore types (no duplicates).
// What: neutrality checks, 0...1 skin mapping, primary-face access.
// Inputs-outputs: EditorCore RetouchState -> render-graph decisions.
// Threading: pure extensions on value types; safe from any thread.
// NOTE: EditorCore is the single owner of RetouchState, FaceAdjustments,
// BodyAdjustments, SkinAdjustments, BrushStroke, History and SliderMapping.
// This file only extends them; it defines no competing model type.
extension RetouchState {
    /// Index of the first face, creating it when the photo has no faces yet.
    mutating func ensurePrimaryFaceIndex() -> Int {
        if faces.isEmpty { faces.append(FaceAdjustments()) }
        return 0
    }

    /// The face the UI is currently editing: the requested index clamped
    /// into the faces array (0 when there are no faces yet).
    func clampedFaceIndex(_ requested: Int) -> Int {
        guard faces.isEmpty == false else { return 0 }
        return min(max(requested, 0), faces.count - 1)
    }

    /// Appends default faces until `index` exists, so a per-face edit
    /// never indexes out of range. Face ids are "face-0", "face-1", ...
    mutating func ensureFace(at index: Int) {
        while faces.count <= index {
            faces.append(FaceAdjustments(faceId: "face-\(faces.count)"))
        }
    }

    /// The first face, or a default when no face has been detected.
    var primaryFace: FaceAdjustments {
        faces.first ?? FaceAdjustments()
    }

    /// True when nothing at all has been changed (all stages may be skipped).
    var isNeutral: Bool {
        isGeometryNeutral && skinIsNeutral && distortionCorrection == 0
    }

    /// True when no face/body warp is active (stage 3 may be skipped).
    var isGeometryNeutral: Bool {
        faces.allSatisfy { $0.isNeutral }
            && body.isNeutral && brushStrokes.isEmpty
    }

    /// True when no source-space skin work is active (stage 2 may be skipped).
    var skinIsNeutral: Bool { skin.isNeutral }

    /// Skin smoothing 0...100 (EditorCore) -> 0...1 (Metal SmoothParams).
    var skinSmoothing01: Float {
        min(max(skin.smoothing / 100, 0), 1)
    }

    /// Texture preservation 0...100 (EditorCore) -> 0...1 (Metal textureKeep).
    /// DECISION (2026-11-12, see DEBUG_LOG.md): `skin.texture` means texture
    /// KEPT — 100 = full detail preserved, 0 = fully smoothed low pass.
    /// Evidence: the Metal kernel parameter is named `textureKeep` and
    /// computes smoothed = low + (src - low) * textureKeep; the CPU reference
    /// (skinSmoothBlendCPU) and the QA harness agree; Auto sets texture 70
    /// (gentle smoothing that keeps most detail). If a future spec says the
    /// slider means texture REMOVED, this becomes 1 - texture/100.
    var textureKeep01: Float {
        min(max(skin.texture / 100, 0), 1)
    }

    /// Distortion correction is on when its strength (EditorCore Float) is non-zero.
    var distortionEnabled: Bool { distortionCorrection != 0 }
}

extension FaceAdjustments {
    var isNeutral: Bool {
        eyeSize == 0 && eyeHeight == 0 && eyeWidth == 0 && eyeLength == 0
            && eyeSpacing == 0 && eyePuffy == 0 && eyeAngle == 0
            && eyePosition == 0 && noseSize == 0 && noseWidth == 0
            && noseLift == 0 && noseAla == 0 && noseRoot == 0
            && noseBridge == 0 && noseTip == 0 && lipSize == 0
            && lipWidth == 0 && lipThickness == 0 && lipSmile == 0
            && lipPosition == 0 && lipMShape == 0 && browHeight == 0
            && browDistance == 0 && browThickness == 0 && browAngle == 0
            && browLength == 0 && browShape == 0 && faceWidth == 0
            && jawSize == 0 && chinLength == 0 && chinWidth == 0
            && cheekbones == 0 && temples == 0 && foreheadHeight == 0
            && faceLength == 0 && vShape == 0 && yawAttenuation == 0
            && pitchAttenuation == 0 && rollAttenuation == 0
    }
}

extension BodyAdjustments {
    var isNeutral: Bool {
        slim == 0 && waist == 0 && hips == 0 && legLength == 0
            && shoulders == 0 && neck == 0
    }
}

extension SkinAdjustments {
    var isNeutral: Bool {
        smoothing == 0 && texture == 0 && shine == 0 && wrinkle == 0
            && acne == 0 && darkCircles == 0 && teethWhitening == 0
            && eyeEnhance == 0 && grain == 0
    }
}
