import SwiftUI
import EditorCore

// EditorBottomBar — bottom row: cancel (undo) / scope chip / face picker / apply.
// What: the scope chip (General / Left / Right) applies to the SELECTED
// face; the face picker chip appears once more than one face has
// adjustments and picks which face the face tools + scope apply to.
// Inputs-outputs: viewModel in; apply out via onApply.
// Threading: @MainActor SwiftUI view; view model is @ObservedObject.
struct EditorBottomBar: View {
    @ObservedObject var viewModel: EditorViewModel
    var onApply: () -> Void

    var body: some View {
        HStack {
            Button(action: { viewModel.cancelEditing() }) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .adaptiveGlass(in: Circle(), interactive: true)
            .disabled(viewModel.canUndo == false)
            .accessibilityLabel(Text("editor.cancel"))

            Spacer()

            scopeMenu

            // Multi-face selector: appears once more than one face has
            // adjustments. Picks which face the face tools + scope apply to.
            if viewModel.state.faces.count > 1 {
                facePicker
            }

            Spacer()

            Button(action: onApply) {
                Image(systemName: "checkmark")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .adaptiveGlass(in: Circle(), tint: Color.accentColor.opacity(0.3), interactive: true)
            .accessibilityLabel(Text("editor.apply"))
        }
    }

    private var scopeMenu: some View {
        Menu {
            Picker("editor.scope", selection: scopeBinding) {
                Text("editor.scope.general").tag(FaceScope.general)
                Text("editor.scope.left").tag(FaceScope.left)
                Text("editor.scope.right").tag(FaceScope.right)
            }
        } label: {
            HStack(spacing: 4) {
                Text("editor.scope")
                Image(systemName: "chevron.down")
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .adaptiveGlass(in: Capsule(), interactive: true)
    }

    /// The face the face tools + scope chip apply to (0 = first face).
    private var selectedFaceIndex: Int {
        viewModel.state.clampedFaceIndex(viewModel.extras.selectedFaceIndex)
    }

    private var facePicker: some View {
        Menu {
            Picker("editor.facePicker", selection: faceIndexBinding) {
                ForEach(viewModel.state.faces.indices, id: \.self) { index in
                    Text("\(index + 1)").tag(index)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("editor.facePicker")
                Text("\(selectedFaceIndex + 1)")
                Image(systemName: "chevron.down")
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .adaptiveGlass(in: Capsule(), interactive: true)
        .accessibilityLabel(Text("editor.facePicker"))
        .accessibilityValue(Text("\(selectedFaceIndex + 1)"))
    }

    private var faceIndexBinding: Binding<Int> {
        Binding(
            get: { selectedFaceIndex },
            set: { newValue in
                viewModel.beginChange()
                viewModel.updateExtras { $0.selectedFaceIndex = newValue }
                viewModel.endChange()
            }
        )
    }

    /// The scope chip (General / Left / Right) for the SELECTED face.
    private var scopeBinding: Binding<FaceScope> {
        Binding(
            get: {
                guard viewModel.state.faces.indices.contains(selectedFaceIndex) else { return .general }
                return viewModel.state.faces[selectedFaceIndex].scope
            },
            set: { newValue in
                viewModel.beginChange()
                viewModel.state.ensureFace(at: selectedFaceIndex)
                viewModel.state.faces[selectedFaceIndex].scope = newValue
                viewModel.renderGraph?.markGeometryDirty()
                viewModel.endChange()
            }
        )
    }
}
