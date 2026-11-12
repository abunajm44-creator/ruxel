import Foundation
import EditorCore

// LegacyExtras — reader for pre-migration extras.json files.
// What: the old app-side slider store (ExtraAdjustments, deleted once
// EditorCore gained all 32 face sliders + skin grain). Old projects
// keep their face/skin values: ProjectStore migrates them into
// RetouchState once, then rewrites extras.json away.
// Inputs-outputs: extras.json data in; FaceAdjustments/SkinAdjustments
// values out. Threading: value type; used on @MainActor only.
struct LegacyExtras: Codable, Sendable {
    var eyeHeight: Float = 0
    var eyeWidth: Float = 0
    var eyeLength: Float = 0
    var eyePuffy: Float = 0
    var noseLift: Float = 0
    var noseAla: Float = 0
    var noseRoot: Float = 0
    var noseBridge: Float = 0
    var noseTip: Float = 0
    var lipWidth: Float = 0
    var lipSmile: Float = 0
    var lipPosition: Float = 0
    var lipShape: Float = 0
    var browHeight: Float = 0
    var browDistance: Float = 0
    var browAngle: Float = 0
    var browLength: Float = 0
    var browShape: Float = 0
    var cheekbones: Float = 0
    var temples: Float = 0
    var forehead: Float = 0
    var faceLength: Float = 0
    var faceVShape: Float = 0
    var grain: Float = 0

    /// True when the file holds any migrated value (face slider or grain).
    var hasMigratableValues: Bool {
        eyeHeight != 0 || eyeWidth != 0 || eyeLength != 0 || eyePuffy != 0
            || noseLift != 0 || noseAla != 0 || noseRoot != 0 || noseBridge != 0
            || noseTip != 0 || lipWidth != 0 || lipSmile != 0 || lipPosition != 0
            || lipShape != 0 || browHeight != 0 || browDistance != 0
            || browAngle != 0 || browLength != 0 || browShape != 0
            || cheekbones != 0 || temples != 0 || forehead != 0
            || faceLength != 0 || faceVShape != 0 || grain != 0
    }

    /// Copies the legacy values into the primary face / skin. Face fields
    /// that were already set in state.json win (state is newer than the
    /// legacy file when both exist); grain always copies (skin had no
    /// grain field before the migration).
    func apply(to state: inout RetouchState) {
        if state.faces.isEmpty {
            state.faces.append(FaceAdjustments())
        }
        var face = state.faces[0]
        func take(_ current: Float, _ legacy: Float) -> Float {
            current == 0 ? legacy : current
        }
        face.eyeHeight = take(face.eyeHeight, eyeHeight)
        face.eyeWidth = take(face.eyeWidth, eyeWidth)
        face.eyeLength = take(face.eyeLength, eyeLength)
        face.eyePuffy = take(face.eyePuffy, eyePuffy)
        face.noseLift = take(face.noseLift, noseLift)
        face.noseAla = take(face.noseAla, noseAla)
        face.noseRoot = take(face.noseRoot, noseRoot)
        face.noseBridge = take(face.noseBridge, noseBridge)
        face.noseTip = take(face.noseTip, noseTip)
        face.lipWidth = take(face.lipWidth, lipWidth)
        face.lipSmile = take(face.lipSmile, lipSmile)
        face.lipPosition = take(face.lipPosition, lipPosition)
        face.lipMShape = take(face.lipMShape, lipShape)
        face.browHeight = take(face.browHeight, browHeight)
        face.browDistance = take(face.browDistance, browDistance)
        face.browAngle = take(face.browAngle, browAngle)
        face.browLength = take(face.browLength, browLength)
        face.browShape = take(face.browShape, browShape)
        face.cheekbones = take(face.cheekbones, cheekbones)
        face.temples = take(face.temples, temples)
        face.foreheadHeight = take(face.foreheadHeight, forehead)
        face.faceLength = take(face.faceLength, faceLength)
        face.vShape = take(face.vShape, faceVShape)
        state.faces[0] = face
        state.skin.grain = take(state.skin.grain, grain)
    }
}
