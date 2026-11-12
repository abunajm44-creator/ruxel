import SwiftUI

// ObjectEraserView — object eraser: the user paints a mask; PatchMatch
// inpainting (multi-scale) would fill it. The inpainting engine is NOT
// built, so this view is HONEST about it: the mask UI works and the mask
// is stored, but Apply stays disabled and the notice says why.
// What: brush size + paint mask via PaintOverlayView + clear mask.
// Inputs-outputs: mask strokes -> viewModel.extras (one undo step each).
// Threading: @MainActor SwiftUI view; view model is @ObservedObject.
// NEVER present this as working removal — see FEATURES.md.
struct ObjectEraserView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BipolarSlider(
                value: Binding(
                    get: { viewModel.extras.eraserSize },
                    set: { newValue in viewModel.updateExtras { $0.eraserSize = newValue } }
                ),
                range: 0...100,
                isBipolar: false,
                titleKey: "eraser.size",
                onBegin: { viewModel.beginChange() },
                onEnd: { viewModel.endChange() }
            )
            Text("eraser.hint")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button(action: clearMask) {
                    Text("eraser.clearMask")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .frame(minHeight: 44)
                .adaptiveGlass(in: RoundedRectangle(cornerRadius: 14), interactive: true)
                .disabled(viewModel.extras.eraserMaskStrokes.isEmpty)
                .accessibilityLabel(Text("eraser.clearMask"))
                Button(action: {}) {
                    Text("eraser.apply")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .frame(minHeight: 44)
                .adaptiveGlass(in: RoundedRectangle(cornerRadius: 14), interactive: true)
                // Disabled on purpose: no inpainting engine exists yet.
                .disabled(true)
                .accessibilityLabel(Text("eraser.apply"))
            }
            Text("eraser.pending")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func clearMask() {
        viewModel.beginChange()
        viewModel.updateExtras { $0.eraserMaskStrokes.removeAll() }
        viewModel.renderGraph?.markSourceSpaceDirty()
        viewModel.endChange()
    }
}
