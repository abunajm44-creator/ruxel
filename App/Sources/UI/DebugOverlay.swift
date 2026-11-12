import SwiftUI

// DebugOverlay — hidden diagnostics overlay (5 taps on the version label).
// What: fps, render ms, memory, landmark/mask/field overlay toggles, copy log.
// Inputs-outputs: reads EditorViewModel debug state; copy writes ruxel-log.txt.
// Threading: SwiftUI view code; runs on the main actor.
struct DebugOverlay: View {
    @ObservedObject var viewModel: EditorViewModel
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("debug.title")
                .font(.headline)
            HStack {
                Text("debug.fps")
                Spacer()
                Text(String(format: "%.0f", viewModel.fps))
                    .monospacedDigit()
            }
            HStack {
                Text("debug.renderMs")
                Spacer()
                Text(String(format: "%.1f", viewModel.renderMs))
                    .monospacedDigit()
            }
            HStack {
                Text("debug.memory")
                Spacer()
                Text(String(format: "%.0f MB", viewModel.memoryMB))
                    .monospacedDigit()
            }
            Toggle("debug.landmarks", isOn: $viewModel.showLandmarksOverlay)
            Toggle("debug.masks", isOn: $viewModel.showMasksOverlay)
            Toggle("debug.field", isOn: $viewModel.showFieldOverlay)
            Button(didCopy ? "debug.copied" : "debug.copyLog") {
                viewModel.copyLog()
                didCopy = true
            }
            .buttonStyle(.bordered)
            Button("debug.close") {
                viewModel.isDebugVisible = false
            }
            .buttonStyle(.bordered)
        }
        .font(.subheadline)
        .padding()
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: 20))
        .onAppear { viewModel.refreshMemory() }
    }
}
