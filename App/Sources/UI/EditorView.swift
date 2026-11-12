import SwiftUI
import EditorCore

// EditorView — the full-bleed photo editor: canvas + floating glass controls.
// What: top bar (back, compare, background lock, distortion), tool panel,
// tool strip, bottom row (cancel / scope / apply). 5 taps on the version
// label opens the hidden debug overlay.
// Inputs-outputs: project in; edits autosave via EditorViewModel.
// Threading: @MainActor SwiftUI view; view model is @StateObject.
struct EditorView: View {
    @StateObject private var viewModel: EditorViewModel
    var onClose: () -> Void

    @State private var versionTaps = 0
    @State private var isPanelExpanded = true

    init(project: ProjectInfo, store: ProjectStore, onClose: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: EditorViewModel(project: project, store: store))
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            CanvasView(viewModel: viewModel)
                .ignoresSafeArea()
            // Paint tools draw on the photo through this overlay; it sits
            // above the canvas and below the controls, and only while a
            // paint tool (color brush / eraser / sparkle) is selected.
            if isPaintTool {
                PaintOverlayView(viewModel: viewModel)
                    .ignoresSafeArea()
            }
            VStack(spacing: 0) {
                topBar
                Spacer()
                if viewModel.isDebugVisible {
                    DebugOverlay(viewModel: viewModel)
                        .padding()
                }
                if isPanelExpanded {
                    toolPanel
                        .padding(.horizontal, 12)
                }
                ToolStripView(selectedTool: $viewModel.selectedTool)
                    .padding(.vertical, 8)
                bottomRow
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .alert(
            Text("error.title"),
            isPresented: .constant(viewModel.errorMessage != nil),
            actions: { Button("common.ok") { viewModel.errorMessage = nil } },
            message: { Text(viewModel.errorMessage ?? "") }
        )
        .sheet(isPresented: Binding(
            get: { viewModel.exportedFileURL != nil },
            set: { newValue in if newValue == false { viewModel.cleanupExportFile() } }
        )) {
            exportShareSheet
        }
        .onAppear {
            Task {
                if let proxy = try? PhotoImportService().makeProxy(from: viewModel.project.originalURL) {
                    viewModel.runAnalysis(image: proxy)
                }
            }
        }
    }

    /// True while a paint tool owns the canvas (color brush / eraser / sparkle).
    private var isPaintTool: Bool {
        viewModel.selectedTool == .colorBrush
            || viewModel.selectedTool == .eraser
            || viewModel.selectedTool == .brush
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "chevron.backward")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .adaptiveGlass(in: Circle(), interactive: true)
            .accessibilityLabel(Text("common.back"))

            Spacer()

            compareButton

            backgroundLockButton

            distortionButton

            exportButton

            Text("editor.version")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .onTapGesture {
                    versionTaps += 1
                    if versionTaps >= 5 {
                        versionTaps = 0
                        viewModel.isDebugVisible.toggle()
                    }
                }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    /// Export (share) button: runs the full-resolution tile export, then
    /// the share sheet appears from exportedFileURL. While exporting the
    /// button shows a spinner and is disabled; cancel via cancelExport.
    private var exportButton: some View {
        Button(action: { viewModel.export() }) {
            if viewModel.isExporting {
                ProgressView()
                    .frame(width: 44, height: 44)
            } else {
                Image(systemName: "square.and.arrow.up")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
        }
        .adaptiveGlass(in: Circle(), interactive: true)
        .disabled(viewModel.isExporting)
        .accessibilityLabel(Text("editor.export"))
    }

    /// Share sheet shown when an export finishes. Done dismisses it and
    /// deletes the temp file via cleanupExportFile().
    @ViewBuilder
    private var exportShareSheet: some View {
        if let url = viewModel.exportedFileURL {
            VStack(spacing: 20) {
                Text("editor.exportDone")
                    .font(.headline)
                ShareLink(item: url) {
                    Label("editor.export", systemImage: "square.and.arrow.up")
                        .font(.headline)
                }
                Button("common.ok") { viewModel.cleanupExportFile() }
            }
            .padding()
        }
    }

    private var compareButton: some View {
        Text("editor.compare")
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .adaptiveGlass(in: Capsule(), interactive: true)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in viewModel.isComparing = true }
                    .onEnded { _ in viewModel.isComparing = false }
            )
            .accessibilityLabel(Text("editor.compare"))
    }

    private var backgroundLockButton: some View {
        Button(action: toggleBackgroundLock) {
            Label("editor.backgroundLock", systemImage: viewModel.state.backgroundLock ? "lock.fill" : "lock.open")
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .adaptiveGlass(
            in: Capsule(),
            tint: viewModel.state.backgroundLock ? Color.accentColor.opacity(0.25) : nil,
            interactive: true
        )
        .accessibilityLabel(Text("editor.backgroundLock"))
    }

    private var distortionButton: some View {
        HStack(spacing: 4) {
            Button(action: toggleDistortion) {
                Label("editor.distortionCorrection", systemImage: "wand.and.rays")
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            // Greyed out when neither a face nor a body is found
            // (viewModel.hasFaceOrBody). The help text says face or body.
            .disabled(viewModel.hasFaceOrBody == false)
            Button(action: { viewModel.showDistortionHelp.toggle() }) {
                Image(systemName: "questionmark.circle")
            }
            .popover(isPresented: $viewModel.showDistortionHelp) {
                Text("editor.distortionHelp")
                    .font(.body)
                    .padding()
            }
            .accessibilityLabel(Text("editor.distortionHelp"))
        }
        .adaptiveGlass(in: Capsule(), interactive: true)
    }

    // MARK: - Tool panel + bottom row

    private var toolPanel: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Distortion strength appears only while the correction is on.
                if viewModel.state.distortionEnabled {
                    BipolarSlider(
                        value: distortionStrengthBinding,
                        range: 0...100,
                        isBipolar: false,
                        titleKey: "editor.distortionStrength",
                        onBegin: { viewModel.beginChange() },
                        onEnd: { viewModel.endChange() }
                    )
                    .disabled(viewModel.hasFaceOrBody == false)
                }
                toolPanelContent
            }
            .padding(16)
        }
        .frame(maxHeight: 320)
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: 20))
    }

    /// Distortion strength 0...100 (EditorCore Float; 0 = off).
    private var distortionStrengthBinding: Binding<Float> {
        Binding(
            get: { viewModel.state.distortionCorrection },
            set: { newValue in
                viewModel.state.distortionCorrection = newValue
                viewModel.renderGraph?.markGeometryDirty()
            }
        )
    }

    @ViewBuilder
    private var toolPanelContent: some View {
        switch viewModel.selectedTool {
        case .face:
            FaceToolView(viewModel: viewModel)
        case .slim, .bodySculpt:
            BodyToolView(viewModel: viewModel)
        case .smoothing, .skin, .wrinkles, .acne, .shine, .darkCircles, .teeth, .eyes, .auto:
            SkinToolView(viewModel: viewModel)
        case .makeup:
            MakeupToolView(viewModel: viewModel)
        case .colorBrush:
            ColorBrushView(viewModel: viewModel)
        case .head:
            HeadToolView(viewModel: viewModel)
        case .lift:
            LiftToolView(viewModel: viewModel)
        case .eraser:
            ObjectEraserView(viewModel: viewModel)
        case .hair:
            HairToolView(viewModel: viewModel)
        case .brush:
            SparkleBrushView(viewModel: viewModel)
        case .cropRotate:
            CropRotateView(viewModel: viewModel)
        case .basicAdjust:
            BasicAdjustView(viewModel: viewModel)
        case .filters:
            FiltersView(viewModel: viewModel)
        }
    }

    private var bottomRow: some View {
        EditorBottomBar(viewModel: viewModel, onApply: applyChanges)
    }

    // MARK: - Actions

    private func toggleBackgroundLock() {
        viewModel.beginChange()
        viewModel.state.backgroundLock.toggle()
        viewModel.renderGraph?.markGeometryDirty()
        viewModel.endChange()
    }

    private func toggleDistortion() {
        viewModel.beginChange()
        // EditorCore distortionCorrection is a Float strength; 0 = off.
        viewModel.state.distortionCorrection = viewModel.state.distortionEnabled ? 0 : 50
        viewModel.renderGraph?.markGeometryDirty()
        viewModel.endChange()
    }

    private func applyChanges() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        viewModel.applyEditing()
        isPanelExpanded = false
    }
}
