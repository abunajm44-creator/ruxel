import SwiftUI
import UIKit
import EditorCore

// MakeupToolView — makeup: lips, blush, eye shadow, liner, brows.
// What: region picker + color picker + intensity + matte/satin/glossy
// finish, writing to EditorCore MakeupAdjustments (lips = outer minus
// inner polygon, blush = gaussian on cheeks, per AGENTS.md 7G).
// Inputs-outputs: edits -> viewModel.state.makeup (one undo step per drag).
// Threading: @MainActor SwiftUI view; view model is @ObservedObject.
// NOTE: the render graph has no makeup pass yet — values are stored and
// autosaved, and the footnote below says so. Blend is Lab,
// luminance-preserving, once the pass lands (AGENTS.md 7G).
struct MakeupToolView: View {
    @ObservedObject var viewModel: EditorViewModel
    @State private var selectedRegion: MakeupRegion = .lips
    /// True while a color-picking session is open (one undo step per session).
    @State private var colorSessionOpen = false

    enum MakeupRegion: String, CaseIterable, Identifiable {
        case lips
        case blush
        case shadow
        case liner
        case brows

        var id: String { rawValue }
        var titleKey: String { "makeup.\(rawValue)" }
        var layerKeyPath: WritableKeyPath<MakeupAdjustments, MakeupLayer> {
            switch self {
            case .lips: return \.lips
            case .blush: return \.blush
            case .shadow: return \.shadow
            case .liner: return \.liner
            case .brows: return \.brows
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            regionRow
            ColorPicker(
                "makeup.color",
                selection: colorBinding,
                supportsOpacity: false
            )
            .frame(minHeight: 44)
            .accessibilityLabel(Text("makeup.color"))
            BipolarSlider(
                value: intensityBinding,
                range: 0...100,
                isBipolar: false,
                titleKey: "makeup.intensity",
                onBegin: { viewModel.beginChange() },
                onEnd: { viewModel.endChange() }
            )
            Text("makeup.finish")
                .font(.subheadline)
            Picker("", selection: finishBinding) {
                Text("makeup.finish.matte").tag(MakeupFinish.matte)
                Text("makeup.finish.satin").tag(MakeupFinish.satin)
                Text("makeup.finish.glossy").tag(MakeupFinish.glossy)
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
            .accessibilityLabel(Text("makeup.finish"))
            Text("makeup.pending")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .disabled(viewModel.hasFace == false)
        .onDisappear { endColorSession() }
    }

    private var regionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MakeupRegion.allCases) { region in
                    Button(action: {
                        endColorSession()
                        selectedRegion = region
                    }) {
                        Text(region.titleKey)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .frame(minHeight: 44)
                    .adaptiveGlass(
                        in: Capsule(),
                        tint: selectedRegion == region ? Color.accentColor.opacity(0.25) : nil,
                        interactive: true
                    )
                    .accessibilityLabel(Text(region.titleKey))
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    // MARK: - Bindings

    private var layer: MakeupLayer {
        viewModel.state.makeup[keyPath: selectedRegion.layerKeyPath]
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                Color(
                    red: Double(layer.red),
                    green: Double(layer.green),
                    blue: Double(layer.blue)
                )
            },
            set: { newColor in
                if colorSessionOpen == false {
                    viewModel.beginChange()
                    colorSessionOpen = true
                }
                var red: CGFloat = 0
                var green: CGFloat = 0
                var blue: CGFloat = 0
                var alpha: CGFloat = 0
                guard UIColor(newColor).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
                updateMakeup { makeup in
                    makeup[keyPath: selectedRegion.layerKeyPath].red = Float(red)
                    makeup[keyPath: selectedRegion.layerKeyPath].green = Float(green)
                    makeup[keyPath: selectedRegion.layerKeyPath].blue = Float(blue)
                }
            }
        )
    }

    private var intensityBinding: Binding<Float> {
        Binding(
            get: { layer.intensity * 100 },
            set: { newValue in
                updateMakeup { makeup in
                    makeup[keyPath: selectedRegion.layerKeyPath].intensity =
                        min(max(newValue / 100, 0), 1)
                }
            }
        )
    }

    private var finishBinding: Binding<MakeupFinish> {
        Binding(
            get: { layer.finish },
            set: { newFinish in
                endColorSession()
                viewModel.beginChange()
                updateMakeup { makeup in
                    makeup[keyPath: selectedRegion.layerKeyPath].finish = newFinish
                }
                viewModel.endChange()
            }
        )
    }

    private func updateMakeup(_ mutate: (inout MakeupAdjustments) -> Void) {
        mutate(&viewModel.state.makeup)
        viewModel.renderGraph?.markSourceSpaceDirty()
    }

    private func endColorSession() {
        if colorSessionOpen {
            colorSessionOpen = false
            viewModel.endChange()
        }
    }
}
