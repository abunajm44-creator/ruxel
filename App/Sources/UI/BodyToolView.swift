import SwiftUI
import EditorCore

// BodyToolView — body sculpt: Manual / Auto tabs, brush modes, pose sliders.
// What: Manual = brush mode (Classic/Fast/Restore) + 5-stop size; Auto =
// pose-driven sliders on EditorCore BodyAdjustments. Background lock
// multiplies displacement by the person mask (see RenderGraph / Warp.metal).
// Inputs-outputs: drags -> EditorViewModel (one undo step per drag).
// Threading: @MainActor SwiftUI view; view model is @ObservedObject.
struct BodyToolView: View {
    @ObservedObject var viewModel: EditorViewModel
    @State private var mode: BodyMode = .auto

    enum BodyMode: String, CaseIterable, Identifiable {
        case manual
        case auto

        var id: String { rawValue }
        var titleKey: String { "body.\(rawValue)" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $mode) {
                ForEach(BodyMode.allCases) { item in
                    Text(item.titleKey).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { newMode in
                // Manual mode arms the canvas brush; auto mode disarms it.
                viewModel.isBrushActive = newMode == .manual
            }
            .onAppear {
                viewModel.isBrushActive = mode == .manual
            }
            .onDisappear {
                viewModel.isBrushActive = false
            }

            if mode == .manual {
                manualControls
            } else {
                autoSliders
            }
        }
    }

    private var manualControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("body.brushMode")
                .font(.subheadline)
            Picker("", selection: $viewModel.brushMode) {
                Text("body.classic").tag(BrushMode.classic)
                Text("body.fast").tag(BrushMode.fast)
                Text("body.restore").tag(BrushMode.restore)
            }
            .pickerStyle(.segmented)
            Text("body.size")
                .font(.subheadline)
            HStack(spacing: 8) {
                ForEach(EditorViewModel.brushSizeStops.indices, id: \.self) { index in
                    Button(action: { viewModel.brushSizeStop = index }) {
                        Circle()
                            .fill(viewModel.brushSizeStop == index ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 12 + CGFloat(index) * 6, height: 12 + CGFloat(index) * 6)
                    }
                    .frame(width: 44, height: 44)
                    .adaptiveGlass(in: Circle(), interactive: true)
                    .accessibilityLabel(Text("body.size"))
                    .accessibilityValue(Text("\(index + 1)"))
                }
            }
            Text("body.manualHint")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var autoSliders: some View {
        VStack(spacing: 12) {
            slider(body: \.slim, key: "body.slim")
            slider(body: \.waist, key: "body.waist")
            slider(body: \.hips, key: "body.hips")
            slider(body: \.legLength, key: "body.legsLength")
            slider(body: \.shoulders, key: "body.shoulders")
            slider(body: \.neck, key: "body.neck")
        }
    }

    private func slider(body keyPath: WritableKeyPath<BodyAdjustments, Float>, key: String) -> some View {
        BipolarSlider(
            value: Binding(
                get: { viewModel.state.body[keyPath: keyPath] },
                set: { newValue in
                    viewModel.updateBody { body in body[keyPath: keyPath] = newValue }
                }
            ),
            titleKey: key,
            onBegin: { viewModel.beginChange() },
            onEnd: { viewModel.endChange() }
        )
    }
}
