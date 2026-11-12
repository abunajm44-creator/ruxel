import SwiftUI

// HeadToolView — head size / shape sliders, -100...100 (IPD-based radii).
// What: two bipolar sliders on ExtraAdjustments (no EditorCore head fields
// yet); radii are expressed in inter-pupil-distance units when the head
// warp lands, so results stay independent of face size and resolution.
// Inputs-outputs: drags -> EditorViewModel (one undo step per drag).
// Threading: @MainActor SwiftUI view; view model is @ObservedObject.
struct HeadToolView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.hasFace == false {
                Text("editor.noFace")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            BipolarSlider(
                value: Binding(
                    get: { viewModel.extras.headSize },
                    set: { newValue in viewModel.updateExtras { $0.headSize = newValue } }
                ),
                titleKey: "head.size",
                onBegin: { viewModel.beginChange() },
                onEnd: { viewModel.endChange() }
            )
            BipolarSlider(
                value: Binding(
                    get: { viewModel.extras.headShape },
                    set: { newValue in viewModel.updateExtras { $0.headShape = newValue } }
                ),
                titleKey: "head.shape",
                onBegin: { viewModel.beginChange() },
                onEnd: { viewModel.endChange() }
            )
            Text("head.note")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .disabled(viewModel.hasFace == false)
    }
}
