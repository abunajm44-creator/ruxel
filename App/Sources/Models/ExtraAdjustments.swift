import Foundation
import EditorCore

// ExtraAdjustments — app-side adjustments EditorCore does not model.
// What: P5/P6 tool state (basic adjust, filters, crop, color brush,
// eraser, hair, head, lift, sparkle, multi-face selection). The 32 face
// sliders + skin grain live in EditorCore FaceAdjustments /
// SkinAdjustments — do NOT re-add face/skin slider fields here. Old
// extras.json files with face values are migrated once by
// ProjectStore.migrateLegacyExtras.
// Inputs-outputs: persisted as extras.json next to state.json.
// Threading: value type; owned by the @MainActor EditorViewModel only.
// NOTE: every field has a default so old extras.json files (missing new
// keys) still decode, and so the render passes — which land later — can
// read stored values. The views already manipulate this state; the
// passes apply it when they land (see FEATURES.md).
struct ExtraAdjustments: Codable, Equatable, Sendable {
    // Basic adjust (baseline extra): bipolar -100...100 sliders.
    var exposure: Float = 0
    var contrast: Float = 0
    var saturation: Float = 0
    var warmth: Float = 0

    // Filters (baseline extra).
    var filterPreset: FilterPreset = .none
    var filterIntensity: Float = 0

    // Crop / rotate (baseline extra).
    var cropRotation: Float = 0
    var cropAspect: CropAspect = .free

    // Color brush (P5): picker color (0...1), intensity + size 0...100.
    var colorBrushRed: Float = 0.9
    var colorBrushGreen: Float = 0.2
    var colorBrushBlue: Float = 0.3
    var colorBrushIntensity: Float = 0
    var colorBrushSize: Float = 50
    var colorBrushStrokes: [PaintStroke] = []

    // Object eraser (P6): brush size 0...100 + painted mask strokes.
    // Inpainting is NOT built; Apply stays disabled (see FEATURES.md).
    var eraserSize: Float = 50
    var eraserMaskStrokes: [PaintStroke] = []

    // Hair (P6, experimental): recolor + volume + flyaway smoothing.
    // Gated on a real hair mask, which does not exist yet.
    var hairRed: Float = 0.4
    var hairGreen: Float = 0.3
    var hairBlue: Float = 0.25
    var hairVolume: Float = 0
    var hairFlyaway: Float = 0

    // Head (P5) and lift/tighten (P5): bipolar -100...100 sliders.
    var headSize: Float = 0
    var headShape: Float = 0
    var lift: Float = 0
    var tighten: Float = 0

    // Sparkle brush (P6): style + size + intensity 0...100.
    var sparkleStyle: SparkleStyle = .glow
    var sparkleSize: Float = 50
    var sparkleIntensity: Float = 0
    var sparkleStrokes: [PaintStroke] = []

    // Multi-face selection (P5): index into state.faces.
    var selectedFaceIndex: Int = 0

    /// Crop aspect ratios offered by CropRotateView.
    enum CropAspect: String, Codable, Hashable, Sendable, CaseIterable {
        case free
        case square
        case portrait
        case wide
        case classic
    }

    /// Filter presets (each a fixed mix of saturation / contrast /
    /// warmth / exposure, scaled by filterIntensity).
    enum FilterPreset: String, Codable, Hashable, Sendable, CaseIterable {
        case none
        case vivid
        case warm
        case cool
        case mono
        case fade
    }

    /// Sparkle brush styles; rawValue is stored on PaintStroke.style.
    enum SparkleStyle: String, Codable, Hashable, Sendable, CaseIterable {
        case glow
        case glitter
        case star
    }

    /// True when no adjustment is active. Brush colors/sizes are
    /// settings, not adjustments, so they do not affect neutrality.
    var isNeutral: Bool {
        exposure == 0 && contrast == 0 && saturation == 0 && warmth == 0
            && filterPreset == .none && filterIntensity == 0
            && cropRotation == 0 && cropAspect == .free
            && colorBrushIntensity == 0 && colorBrushStrokes.isEmpty
            && eraserMaskStrokes.isEmpty
            && hairVolume == 0 && hairFlyaway == 0
            && headSize == 0 && headShape == 0
            && lift == 0 && tighten == 0
            && sparkleIntensity == 0 && sparkleStrokes.isEmpty
            && selectedFaceIndex == 0
    }
}

// EditorSnapshot — one undoable unit: EditorCore state + app extras together.
// What: keeps undo/redo coherent across both stores (single History stack).
// Inputs-outputs: recorded before every committed change; restored on undo/redo.
// Threading: value type; owned by the @MainActor EditorViewModel only.
struct EditorSnapshot: Equatable, Sendable {
    var state: RetouchState
    var extras: ExtraAdjustments

    init(state: RetouchState = RetouchState(), extras: ExtraAdjustments = ExtraAdjustments()) {
        self.state = state
        self.extras = extras
    }
}
