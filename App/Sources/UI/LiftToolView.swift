import SwiftUI

// LiftToolView — lift and tighten sliders, -100...100.
// What: two bipolar sliders on ExtraAdjustments (face + neck lift).
// Inputs-outputs: drags -> EditorViewModel (one undo step per drag).
// Threading: @MainActor SwiftUI view; view model is @ObservedObject.
// NOTE: the lift warp is a geometry op; the engine pass is pending, so
// values are stored and autosaved for now (see FEATURES.md).
struct LiftToolView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BipolarSlider(
                value: Binding(
                    get: { viewModel.extras.lift },
                    set: { newValue in viewModel.updateExtras { $0.lift = newValue } }
                ),
                titleKey: "lift.lift",
                onBegin: { viewModel.beginChange() },
                onEnd: { viewModel.endChange() }
            )
            BipolarSlider(
                value: Binding(
                    get: { viewModel.extras.tighten },
                    set: { newValue in viewModel.updateExtras { $0.tighten = newValue } }
                ),
                titleKey: "lift.tighten",
                onBegin: { viewModel.beginChange() },
                onEnd: { viewModel.endChange() }
            )
            Text("lift.note")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
