import Foundation

// EditorTool — the 19 retouch tools in the tool strip, right-to-left (RTL).
// What: identity + display key + priority tier for each tool.
// Inputs-outputs: raw order matches the screenshot reading (RTL first = brush).
// Threading: value type; safe from any thread.
// NOTE: distinct from EditorCore.RetouchTool, which is the slider-mapping
// enum (eyeSize, noseWidth, ...) used by SliderMapping. This enum is the
// UI strip identity; it is not a duplicate.
enum EditorTool: String, CaseIterable, Identifiable, Sendable {
    case brush
    case teeth
    case auto
    case makeup
    case face
    case slim
    case bodySculpt
    case smoothing
    case skin
    case wrinkles
    case lift
    case colorBrush
    case acne
    case shine
    case head
    case eyes
    case darkCircles
    case hair
    case eraser
    case cropRotate
    case basicAdjust
    case filters

    var id: String { rawValue }

    /// Localizable.strings key for the tool name.
    var titleKey: String { "tool.\(rawValue)" }

    /// SF Symbol name used for the strip icon (all stock symbols, no copied art).
    var systemImage: String {
        switch self {
        case .brush: return "sparkles"
        case .teeth: return "mouth"
        case .auto: return "wand.and.stars"
        case .makeup: return "paintbrush.pointed"
        case .face: return "face.smiling"
        case .slim: return "figure.walk"
        case .bodySculpt: return "figure.strengthtraining.traditional"
        case .smoothing: return "drop"
        case .skin: return "hand.raised"
        case .wrinkles: return "waveform"
        case .lift: return "arrow.up"
        case .colorBrush: return "paintbrush"
        case .acne: return "circle.dotted"
        case .shine: return "sun.max"
        case .head: return "person.crop.circle"
        case .eyes: return "eye"
        case .darkCircles: return "moon"
        case .hair: return "comb"
        case .eraser: return "eraser"
        case .cropRotate: return "crop.rotate"
        case .basicAdjust: return "slider.horizontal.3"
        case .filters: return "camera.filters"
        }
    }

    /// P1 = core, P2 = next, P3 = later. Used for gating / ordering only.
    var priority: Int {
        switch self {
        case .face, .smoothing, .skin, .auto: return 1
        case .slim, .bodySculpt, .wrinkles, .acne, .shine, .darkCircles,
             .teeth, .eyes, .makeup: return 2
        case .lift, .head, .colorBrush: return 3
        case .eraser, .hair, .brush: return 4
        case .cropRotate, .basicAdjust, .filters: return 5
        }
    }
}
