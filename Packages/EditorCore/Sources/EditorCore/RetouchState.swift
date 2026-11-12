// What: Codable model of a whole retouch project (faces, body, skin, makeup, strokes).
// Inputs/Outputs: JSON-serializable state; all sliders -100...100, defaults 0 / false.
// Threading: Value types, Sendable; safe on any thread.
import Foundation

/// Which side(s) a face adjustment applies to.
public enum FaceScope: String, Codable, Hashable, Sendable {
    case general
    case left
    case right
}

/// Manual brush mode (see brush engine: Classic / Fast / Restore).
public enum BrushMode: String, Codable, Hashable, Sendable {
    case classic
    case fast
    case restore
}

/// Makeup finish: matte, satin sheen, or glossy.
public enum MakeupFinish: String, Codable, Hashable, Sendable {
    case matte
    case satin
    case glossy
}

/// One makeup layer: color + intensity (0...1) + finish.
public struct MakeupLayer: Codable, Equatable, Sendable {
    public var red: Float
    public var green: Float
    public var blue: Float
    public var intensity: Float
    public var finish: MakeupFinish

    public init(
        red: Float = 0.5,
        green: Float = 0.2,
        blue: Float = 0.2,
        intensity: Float = 0,
        finish: MakeupFinish = .matte
    ) {
        self.red = red
        self.green = green
        self.blue = blue
        self.intensity = intensity
        self.finish = finish
    }
}

/// Per-face slider adjustments. All sliders are -100...100, default 0,
/// except the pose attenuation factors (0...1, default 0 = no attenuation).
/// `noseWidth` is a legacy field kept for old state.json files; the UI
/// maps the Ala (nostril wings) slider to `noseAla`, not `noseWidth`.
public struct FaceAdjustments: Codable, Equatable, Sendable {
    public var faceId: String
    public var eyeSize: Float
    public var eyeHeight: Float
    public var eyeWidth: Float
    public var eyeLength: Float
    public var eyeSpacing: Float
    public var eyePuffy: Float
    public var eyeAngle: Float
    public var eyePosition: Float
    public var noseSize: Float
    public var noseWidth: Float
    public var noseLift: Float
    public var noseAla: Float
    public var noseRoot: Float
    public var noseBridge: Float
    public var noseTip: Float
    public var lipSize: Float
    public var lipWidth: Float
    public var lipThickness: Float
    public var lipSmile: Float
    public var lipPosition: Float
    public var lipMShape: Float
    public var browHeight: Float
    public var browDistance: Float
    public var browThickness: Float
    public var browAngle: Float
    public var browLength: Float
    public var browShape: Float
    public var faceWidth: Float
    public var jawSize: Float
    public var chinLength: Float
    public var chinWidth: Float
    public var cheekbones: Float
    public var temples: Float
    public var foreheadHeight: Float
    public var faceLength: Float
    public var vShape: Float
    /// Far-side attenuation at full pose (0 = none, 1 = far side frozen).
    /// Applied by faceWarpOps(); see farSideAttenuationFactor().
    public var yawAttenuation: Float
    public var pitchAttenuation: Float
    public var rollAttenuation: Float
    public var scope: FaceScope

    public init(
        faceId: String = "face-0",
        eyeSize: Float = 0,
        eyeHeight: Float = 0,
        eyeWidth: Float = 0,
        eyeLength: Float = 0,
        eyeSpacing: Float = 0,
        eyePuffy: Float = 0,
        eyeAngle: Float = 0,
        eyePosition: Float = 0,
        noseSize: Float = 0,
        noseWidth: Float = 0,
        noseLift: Float = 0,
        noseAla: Float = 0,
        noseRoot: Float = 0,
        noseBridge: Float = 0,
        noseTip: Float = 0,
        lipSize: Float = 0,
        lipWidth: Float = 0,
        lipThickness: Float = 0,
        lipSmile: Float = 0,
        lipPosition: Float = 0,
        lipMShape: Float = 0,
        browHeight: Float = 0,
        browDistance: Float = 0,
        browThickness: Float = 0,
        browAngle: Float = 0,
        browLength: Float = 0,
        browShape: Float = 0,
        faceWidth: Float = 0,
        jawSize: Float = 0,
        chinLength: Float = 0,
        chinWidth: Float = 0,
        cheekbones: Float = 0,
        temples: Float = 0,
        foreheadHeight: Float = 0,
        faceLength: Float = 0,
        vShape: Float = 0,
        yawAttenuation: Float = 0,
        pitchAttenuation: Float = 0,
        rollAttenuation: Float = 0,
        scope: FaceScope = .general
    ) {
        self.faceId = faceId
        self.eyeSize = eyeSize
        self.eyeHeight = eyeHeight
        self.eyeWidth = eyeWidth
        self.eyeLength = eyeLength
        self.eyeSpacing = eyeSpacing
        self.eyePuffy = eyePuffy
        self.eyeAngle = eyeAngle
        self.eyePosition = eyePosition
        self.noseSize = noseSize
        self.noseWidth = noseWidth
        self.noseLift = noseLift
        self.noseAla = noseAla
        self.noseRoot = noseRoot
        self.noseBridge = noseBridge
        self.noseTip = noseTip
        self.lipSize = lipSize
        self.lipWidth = lipWidth
        self.lipThickness = lipThickness
        self.lipSmile = lipSmile
        self.lipPosition = lipPosition
        self.lipMShape = lipMShape
        self.browHeight = browHeight
        self.browDistance = browDistance
        self.browThickness = browThickness
        self.browAngle = browAngle
        self.browLength = browLength
        self.browShape = browShape
        self.faceWidth = faceWidth
        self.jawSize = jawSize
        self.chinLength = chinLength
        self.chinWidth = chinWidth
        self.cheekbones = cheekbones
        self.temples = temples
        self.foreheadHeight = foreheadHeight
        self.faceLength = faceLength
        self.vShape = vShape
        self.yawAttenuation = yawAttenuation
        self.pitchAttenuation = pitchAttenuation
        self.rollAttenuation = rollAttenuation
        self.scope = scope
    }

    private enum CodingKeys: String, CodingKey {
        case faceId, eyeSize, eyeHeight, eyeWidth, eyeLength, eyeSpacing,
            eyePuffy, eyeAngle, eyePosition, noseSize, noseWidth, noseLift,
            noseAla, noseRoot, noseBridge, noseTip, lipSize, lipWidth,
            lipThickness, lipSmile, lipPosition, lipMShape, browHeight,
            browDistance, browThickness, browAngle, browLength, browShape,
            faceWidth, jawSize, chinLength, chinWidth, cheekbones, temples,
            foreheadHeight, faceLength, vShape, yawAttenuation,
            pitchAttenuation, rollAttenuation, scope
    }

    /// Backward-compatible decode: state.json files written before the
    /// 32-slider extension lack the new keys; they decode as 0 via
    /// decodeIfPresent instead of failing.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        faceId = try container.decodeIfPresent(String.self, forKey: .faceId) ?? "face-0"
        eyeSize = try container.decodeIfPresent(Float.self, forKey: .eyeSize) ?? 0
        eyeHeight = try container.decodeIfPresent(Float.self, forKey: .eyeHeight) ?? 0
        eyeWidth = try container.decodeIfPresent(Float.self, forKey: .eyeWidth) ?? 0
        eyeLength = try container.decodeIfPresent(Float.self, forKey: .eyeLength) ?? 0
        eyeSpacing = try container.decodeIfPresent(Float.self, forKey: .eyeSpacing) ?? 0
        eyePuffy = try container.decodeIfPresent(Float.self, forKey: .eyePuffy) ?? 0
        eyeAngle = try container.decodeIfPresent(Float.self, forKey: .eyeAngle) ?? 0
        eyePosition = try container.decodeIfPresent(Float.self, forKey: .eyePosition) ?? 0
        noseSize = try container.decodeIfPresent(Float.self, forKey: .noseSize) ?? 0
        noseWidth = try container.decodeIfPresent(Float.self, forKey: .noseWidth) ?? 0
        noseLift = try container.decodeIfPresent(Float.self, forKey: .noseLift) ?? 0
        noseAla = try container.decodeIfPresent(Float.self, forKey: .noseAla) ?? 0
        noseRoot = try container.decodeIfPresent(Float.self, forKey: .noseRoot) ?? 0
        noseBridge = try container.decodeIfPresent(Float.self, forKey: .noseBridge) ?? 0
        noseTip = try container.decodeIfPresent(Float.self, forKey: .noseTip) ?? 0
        lipSize = try container.decodeIfPresent(Float.self, forKey: .lipSize) ?? 0
        lipWidth = try container.decodeIfPresent(Float.self, forKey: .lipWidth) ?? 0
        lipThickness = try container.decodeIfPresent(Float.self, forKey: .lipThickness) ?? 0
        lipSmile = try container.decodeIfPresent(Float.self, forKey: .lipSmile) ?? 0
        lipPosition = try container.decodeIfPresent(Float.self, forKey: .lipPosition) ?? 0
        lipMShape = try container.decodeIfPresent(Float.self, forKey: .lipMShape) ?? 0
        browHeight = try container.decodeIfPresent(Float.self, forKey: .browHeight) ?? 0
        browDistance = try container.decodeIfPresent(Float.self, forKey: .browDistance) ?? 0
        browThickness = try container.decodeIfPresent(Float.self, forKey: .browThickness) ?? 0
        browAngle = try container.decodeIfPresent(Float.self, forKey: .browAngle) ?? 0
        browLength = try container.decodeIfPresent(Float.self, forKey: .browLength) ?? 0
        browShape = try container.decodeIfPresent(Float.self, forKey: .browShape) ?? 0
        faceWidth = try container.decodeIfPresent(Float.self, forKey: .faceWidth) ?? 0
        jawSize = try container.decodeIfPresent(Float.self, forKey: .jawSize) ?? 0
        chinLength = try container.decodeIfPresent(Float.self, forKey: .chinLength) ?? 0
        chinWidth = try container.decodeIfPresent(Float.self, forKey: .chinWidth) ?? 0
        cheekbones = try container.decodeIfPresent(Float.self, forKey: .cheekbones) ?? 0
        temples = try container.decodeIfPresent(Float.self, forKey: .temples) ?? 0
        foreheadHeight = try container.decodeIfPresent(Float.self, forKey: .foreheadHeight) ?? 0
        faceLength = try container.decodeIfPresent(Float.self, forKey: .faceLength) ?? 0
        vShape = try container.decodeIfPresent(Float.self, forKey: .vShape) ?? 0
        yawAttenuation = try container.decodeIfPresent(Float.self, forKey: .yawAttenuation) ?? 0
        pitchAttenuation = try container.decodeIfPresent(Float.self, forKey: .pitchAttenuation) ?? 0
        rollAttenuation = try container.decodeIfPresent(Float.self, forKey: .rollAttenuation) ?? 0
        scope = try container.decodeIfPresent(FaceScope.self, forKey: .scope) ?? .general
    }
}

/// Body sculpt sliders. All sliders are -100...100, default 0.
public struct BodyAdjustments: Codable, Equatable, Sendable {
    public var slim: Float
    public var waist: Float
    public var hips: Float
    public var legLength: Float
    public var shoulders: Float
    public var neck: Float

    public init(
        slim: Float = 0,
        waist: Float = 0,
        hips: Float = 0,
        legLength: Float = 0,
        shoulders: Float = 0,
        neck: Float = 0
    ) {
        self.slim = slim
        self.waist = waist
        self.hips = hips
        self.legLength = legLength
        self.shoulders = shoulders
        self.neck = neck
    }
}

/// Skin retouch sliders. All values are 0...100 unless noted, default 0.
/// `texture` means texture KEPT (100 = full detail preserved, see
/// textureKeep01 in the app); `grain` re-injects fine grain after smoothing.
public struct SkinAdjustments: Codable, Equatable, Sendable {
    public var smoothing: Float
    public var texture: Float
    public var shine: Float
    public var wrinkle: Float
    public var acne: Float
    public var darkCircles: Float
    public var teethWhitening: Float
    public var eyeEnhance: Float
    public var grain: Float

    public init(
        smoothing: Float = 0,
        texture: Float = 0,
        shine: Float = 0,
        wrinkle: Float = 0,
        acne: Float = 0,
        darkCircles: Float = 0,
        teethWhitening: Float = 0,
        eyeEnhance: Float = 0,
        grain: Float = 0
    ) {
        self.smoothing = smoothing
        self.texture = texture
        self.shine = shine
        self.wrinkle = wrinkle
        self.acne = acne
        self.darkCircles = darkCircles
        self.teethWhitening = teethWhitening
        self.eyeEnhance = eyeEnhance
        self.grain = grain
    }

    private enum CodingKeys: String, CodingKey {
        case smoothing, texture, shine, wrinkle, acne, darkCircles,
            teethWhitening, eyeEnhance, grain
    }

    /// Backward-compatible decode: `grain` is new; old state.json files
    /// without it decode as 0 instead of failing.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        smoothing = try container.decodeIfPresent(Float.self, forKey: .smoothing) ?? 0
        texture = try container.decodeIfPresent(Float.self, forKey: .texture) ?? 0
        shine = try container.decodeIfPresent(Float.self, forKey: .shine) ?? 0
        wrinkle = try container.decodeIfPresent(Float.self, forKey: .wrinkle) ?? 0
        acne = try container.decodeIfPresent(Float.self, forKey: .acne) ?? 0
        darkCircles = try container.decodeIfPresent(Float.self, forKey: .darkCircles) ?? 0
        teethWhitening = try container.decodeIfPresent(Float.self, forKey: .teethWhitening) ?? 0
        eyeEnhance = try container.decodeIfPresent(Float.self, forKey: .eyeEnhance) ?? 0
        grain = try container.decodeIfPresent(Float.self, forKey: .grain) ?? 0
    }
}

/// Makeup: one layer per region (lips, blush, eye shadow, liner, brows).
public struct MakeupAdjustments: Codable, Equatable, Sendable {
    public var lips: MakeupLayer
    public var blush: MakeupLayer
    public var shadow: MakeupLayer
    public var liner: MakeupLayer
    public var brows: MakeupLayer

    public init(
        lips: MakeupLayer = MakeupLayer(red: 0.85, green: 0.2, blue: 0.25),
        blush: MakeupLayer = MakeupLayer(red: 0.95, green: 0.45, blue: 0.4),
        shadow: MakeupLayer = MakeupLayer(red: 0.45, green: 0.3, blue: 0.3),
        liner: MakeupLayer = MakeupLayer(red: 0.1, green: 0.1, blue: 0.1),
        brows: MakeupLayer = MakeupLayer(red: 0.3, green: 0.2, blue: 0.15)
    ) {
        self.lips = lips
        self.blush = blush
        self.shadow = shadow
        self.liner = liner
        self.brows = brows
    }
}

/// One manual brush stroke, stored in normalized coordinates.
/// `points` are normalized image coordinates (0...1); `size` is the brush
/// diameter in normalized units (fraction of image width), so a stroke
/// replays identically at any resolution.
public struct BrushStroke: Codable, Equatable, Sendable {
    public var points: [Vec2]
    public var size: Float
    public var mode: BrushMode
    public var strength: Float

    public init(
        points: [Vec2] = [],
        size: Float = 0.05,
        mode: BrushMode = .classic,
        strength: Float = 1
    ) {
        self.points = points
        self.size = size
        self.mode = mode
        self.strength = strength
    }
}

/// The whole retouch project state, persisted as state.json.
public struct RetouchState: Codable, Equatable, Sendable {
    public var version: Int
    public var faces: [FaceAdjustments]
    public var body: BodyAdjustments
    public var skin: SkinAdjustments
    public var makeup: MakeupAdjustments
    public var brushStrokes: [BrushStroke]
    public var backgroundLock: Bool
    public var distortionCorrection: Float

    public init(
        version: Int = 1,
        faces: [FaceAdjustments] = [],
        body: BodyAdjustments = BodyAdjustments(),
        skin: SkinAdjustments = SkinAdjustments(),
        makeup: MakeupAdjustments = MakeupAdjustments(),
        brushStrokes: [BrushStroke] = [],
        backgroundLock: Bool = false,
        distortionCorrection: Float = 0
    ) {
        self.version = version
        self.faces = faces
        self.body = body
        self.skin = skin
        self.makeup = makeup
        self.brushStrokes = brushStrokes
        self.backgroundLock = backgroundLock
        self.distortionCorrection = distortionCorrection
    }
}
