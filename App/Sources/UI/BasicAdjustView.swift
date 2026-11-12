import SwiftUI

// BasicAdjustView — basic adjustments: exposure, contrast, saturation,
// warmth (baseline extra).
// What: four bipolar -100...100 sliders on ExtraAdjustments; the color
// pass applies them in Lab (corrections in Lab, per AGENTS.md 7B).
// Inputs-outputs: drags -> EditorViewModel (one undo step per drag).
// Threading: @MainActor SwiftUI view; view model is @ObservedObject.
// NOTE: the render graph has no color pass yet — values are stored and
// autosaved; they apply once the pass lands.
struct BasicAdjustView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            adjustSlider(extra: \.exposure, key: "adjust.exposure")
            adjustSlider(extra: \.contrast, key: "adjust.contrast")
            adjustSlider(extra: \.saturation, key: "adjust.saturation")
            adjustSlider(extra: \.warmth, key: "adjust.warmth")
            Text("adjust.note")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func adjustSlider(
        extra keyPath: WritableKeyPath<ExtraAdjustments, Float>, key: String
    ) -> some View {
        BipolarSlider(
            value: Binding(
                get: { viewModel.extras[keyPath: keyPath] },
                set: { newValue in
                    viewModel.updateExtras { extras in extras[keyPath: keyPath] = newValue }
                    viewModel.renderGraph?.markColorDirty()
                }
            ),
            titleKey: key,
            onBegin: { viewModel.beginChange() },
            onEnd: { viewModel.endChange() }
        )
    }
}
