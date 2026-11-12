import Foundation
import EditorCore

// PaintStroke — one painted stroke on the photo, in overlay-normalized coords.
// What: points (0...1 in overlay space) + size (fraction of overlay width)
// + color/strength, tagged by kind so one store serves the color brush,
// the eraser mask and the sparkle brush.
// Inputs-outputs: drawn by PaintCanvasView; persisted in ExtraAdjustments.
// Threading: value type; owned by the @MainActor EditorViewModel only.
// NOTE: points are normalized to the paint overlay's bounds, NOT to the
// photo rect — the canvas does not expose its photo rect yet, so the
// render engine must remap them once it does (see FEATURES.md).
struct PaintStroke: Codable, Equatable, Sendable {
    var kind: PaintStrokeKind
    var points: [Vec2]
    var size: Float
    var strength: Float
    var red: Float
    var green: Float
    var blue: Float
    /// Sparkle style raw value ("glow" / "glitter" / "star"); "" otherwise.
    var style: String

    init(
        kind: PaintStrokeKind,
        points: [Vec2] = [],
        size: Float = 0.03,
        strength: Float = 0.6,
        red: Float = 0.9,
        green: Float = 0.2,
        blue: Float = 0.3,
        style: String = ""
    ) {
        self.kind = kind
        self.points = points
        self.size = size
        self.strength = strength
        self.red = red
        self.green = green
        self.blue = blue
        self.style = style
    }

    var isEmpty: Bool { points.isEmpty }
}

/// What the stroke means: paint color, erase (inpaint mask), or sparkle.
enum PaintStrokeKind: String, Codable, Hashable, Sendable {
    case color
    case erase
    case sparkle
}
