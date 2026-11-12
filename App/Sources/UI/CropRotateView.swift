import SwiftUI

// CropRotateView — crop / rotate (baseline extra).
// What: rotation slider (-45...45 degrees) + aspect-ratio picker; values
// are stored in ExtraAdjustments and applied by the export/crop pass.
// Inputs-outputs: edits -> viewModel.extras (one undo step per drag).
// Threading: @MainActor SwiftUI view; view model is @ObservedObject.
// NOTE: on-canvas crop framing is not built yet — rotation and aspect are
// stored and autosaved; the crop pass lands with export work.
struct CropRotateView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BipolarSlider(
                value: Binding(
                    get: { viewModel.extras.cropRotation },
                    set: { newValue in viewModel.updateExtras { $0.cropRotation = newValue } }
                ),
                range: -45...45,
                titleKey: "crop.rotation",
                onBegin: { viewModel.beginChange() },
                onEnd: { viewModel.endChange() }
            )
            Text("crop.aspect")
                .font(.subheadline)
            Picker("", selection: aspectBinding) {
                Text("crop.aspect.free").tag(ExtraAdjustments.CropAspect.free)
                Text("crop.aspect.square").tag(ExtraAdjustments.CropAspect.square)
                Text("crop.aspect.portrait").tag(ExtraAdjustments.CropAspect.portrait)
                Text("crop.aspect.wide").tag(ExtraAdjustments.CropAspect.wide)
                Text("crop.aspect.classic").tag(ExtraAdjustments.CropAspect.classic)
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
            .accessibilityLabel(Text("crop.aspect"))
            Text("crop.note")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var aspectBinding: Binding<ExtraAdjustments.CropAspect> {
        Binding(
            get: { viewModel.extras.cropAspect },
            set: { newAspect in
                viewModel.beginChange()
                viewModel.updateExtras { $0.cropAspect = newAspect }
                viewModel.endChange()
            }
        )
    }
}
