import SwiftUI
import EditorCore

// FiltersView — filter presets (baseline extra).
// What: preset chips + intensity; each preset is a simple, honest
// combination of saturation / contrast / warmth — no LUT files, no hidden
// processing. The color pass applies the preset once it lands.
// Inputs-outputs: edits -> viewModel.extras (one undo step per tap/drag).
// Threading: @MainActor SwiftUI view; view model is @ObservedObject.
// Preset definitions (applied at intensity 100; scaled by intensity):
//   vivid: saturation +25, contrast +10
//   warm:  warmth +30
//   cool:  warmth -30
//   mono:  saturation -100
//   fade:  contrast -15, exposure +5
struct FiltersView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("filter.preset")
                .font(.subheadline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FilterPresetOption.allCases) { preset in
                        Button(action: { selectPreset(preset.value) }) {
                            Text(preset.titleKey)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                        .frame(minHeight: 44)
                        .adaptiveGlass(
                            in: Capsule(),
                            tint: viewModel.extras.filterPreset == preset.value
                                ? Color.accentColor.opacity(0.25) : nil,
                            interactive: true
                        )
                        .accessibilityLabel(Text(preset.titleKey))
                    }
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
            BipolarSlider(
                value: Binding(
                    get: { viewModel.extras.filterIntensity },
                    set: { newValue in
                        viewModel.updateExtras { $0.filterIntensity = newValue }
                        viewModel.renderGraph?.markColorDirty()
                    }
                ),
                range: 0...100,
                isBipolar: false,
                titleKey: "filter.intensity",
                onBegin: { viewModel.beginChange() },
                onEnd: { viewModel.endChange() }
            )
            .disabled(viewModel.extras.filterPreset == .none)
            Text("filter.note")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func selectPreset(_ preset: FilterPreset) {
        viewModel.beginChange()
        viewModel.updateExtras { extras in
            extras.filterPreset = preset
            if preset == .none {
                extras.filterIntensity = 0
            } else if extras.filterIntensity == 0 {
                extras.filterIntensity = 60
            }
        }
        viewModel.renderGraph?.markColorDirty()
        viewModel.endChange()
    }

    /// Preset options in display order (none first).
    private enum FilterPresetOption: String, CaseIterable, Identifiable {
        case none
        case vivid
        case warm
        case cool
        case mono
        case fade

        var id: String { rawValue }
        var titleKey: String { "filter.\(rawValue)" }
        var value: FilterPreset {
            switch self {
            case .none: return .none
            case .vivid: return .vivid
            case .warm: return .warm
            case .cool: return .cool
            case .mono: return .mono
            case .fade: return .fade
            }
        }
    }
}
