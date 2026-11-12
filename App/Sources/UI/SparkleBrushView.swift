import SwiftUI

// SparkleBrushView — creative glow / glitter brushes.
// What: style picker (glow / glitter / star) + size + intensity; strokes
// are painted on the photo through PaintOverlayView and stored in
// ExtraAdjustments. Stamps are rendered by PaintCanvasView (no assets).
// Inputs-outputs: edits -> viewModel.extras (one undo step per stroke).
// Threading: @MainActor SwiftUI view; view model is @ObservedObject.
// NOTE: the render graph has no sparkle pass yet — strokes are stored and
// autosaved; the stamp rendering lands with the pass.
struct SparkleBrushView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("sparkle.style")
                .font(.subheadline)
            Picker("", selection: styleBinding) {
                Text("sparkle.style.glow").tag(ExtraAdjustments.SparkleStyle.glow)
                Text("sparkle.style.glitter").tag(ExtraAdjustments.SparkleStyle.glitter)
                Text("sparkle.style.star").tag(ExtraAdjustments.SparkleStyle.star)
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
            .accessibilityLabel(Text("sparkle.style"))
            BipolarSlider(
                value: Binding(
                    get: { viewModel.extras.sparkleSize },
                    set: { newValue in viewModel.updateExtras { $0.sparkleSize = newValue } }
                ),
                range: 0...100,
                isBipolar: false,
                titleKey: "sparkle.size",
                onBegin: { viewModel.beginChange() },
                onEnd: { viewModel.endChange() }
            )
            BipolarSlider(
                value: Binding(
                    get: { viewModel.extras.sparkleIntensity },
                    set: { newValue in
                        viewModel.updateExtras { $0.sparkleIntensity = newValue }
                        viewModel.renderGraph?.markSourceSpaceDirty()
                    }
                ),
                range: 0...100,
                isBipolar: false,
                titleKey: "sparkle.intensity",
                onBegin: { viewModel.beginChange() },
                onEnd: { viewModel.endChange() }
            )
            Text("sparkle.hint")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button(action: clearStrokes) {
                Text("sparkle.clear")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .frame(minHeight: 44)
            .adaptiveGlass(in: RoundedRectangle(cornerRadius: 14), interactive: true)
            .disabled(viewModel.extras.sparkleStrokes.isEmpty)
            .accessibilityLabel(Text("sparkle.clear"))
        }
    }

    private var styleBinding: Binding<ExtraAdjustments.SparkleStyle> {
        Binding(
            get: { viewModel.extras.sparkleStyle },
            set: { newStyle in
                viewModel.beginChange()
                viewModel.updateExtras { $0.sparkleStyle = newStyle }
                viewModel.endChange()
            }
        )
    }

    private func clearStrokes() {
        viewModel.beginChange()
        viewModel.updateExtras { $0.sparkleStrokes.removeAll() }
        viewModel.renderGraph?.markSourceSpaceDirty()
        viewModel.endChange()
    }
}
