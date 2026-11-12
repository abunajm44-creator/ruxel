// EditorViewModel — owns the editing session for one project (P1/P2/P3/P4).
// What: EditorCore RetouchState + app extras, undo/redo, dirty flags,
// autosave, brush strokes, analysis results, committed-snapshot cancel.
// Inputs-outputs: slider/brush writes -> state -> RenderGraph dirty flags
// -> autosave. Threading: @MainActor ObservableObject; history is owned here only.

import Foundation
import SwiftUI
import UIKit
import CoreVideo
import ImageIO
import Metal
import EditorCore
@MainActor
final class EditorViewModel: ObservableObject {
    @Published var state: RetouchState
    @Published var extras: ExtraAdjustments
    @Published var selectedTool: EditorTool = .face {
        didSet { beginToolSession() }
    }
    @Published var isComparing = false
    @Published var hasFace = false
    @Published var hasBody = false
    @Published var isAnalyzing = false
    @Published var errorMessage: String?
    @Published var canUndo = false
    @Published var canRedo = false
    @Published var showDistortionHelp = false

    // Analysis results (landmarks + pose drive the warp ops; the person
    // mask drives background lock and the export skin mask).
    @Published var landmarks: FaceLandmarks?
    @Published var bodyPose: BodyPose?
    @Published var personMaskImage: UIImage?
    /// Raw person-mask pixel buffer, for the canvas mask texture.
    var personMaskPixelBuffer: CVPixelBuffer?
    /// Person mask as floats (0...1, row-major) at proxy size, for export.
    var personMaskFloat: (values: [Float], width: Int, height: Int)?

    /// The photo's pixel size (from the original file's EXIF, no decode).
    var imageSize: CGSize = .zero
    /// The canvas size in points, reported by CanvasView. Drives the
    /// overlay bitmap (photo rect + brush circularity).
    var canvasSize: CGSize = .zero
    /// Rasterized paint overlay (photo space) + its Metal texture, built
    /// from the color/sparkle strokes whenever they change. Nil when
    /// there is nothing to paint. Export samples the bitmap on CPU.
    var overlayBitmap: PaintOverlayBitmap?
    var overlayTexture: MTLTexture?
    /// Live skin mask texture (person mask AND face oval), built after
    /// analysis so the interactive smoothing stage has a mask to blend
    /// with. Nil until analysis produces a mask + landmarks.
    var skinMaskTexture: MTLTexture?
    /// Last overlay inputs, to rebuild only when strokes, intensities,
    /// canvas size or image size actually changed.
    private var lastOverlayKey: (colorStrokes: [PaintStroke], sparkleStrokes: [PaintStroke],
                                 colorIntensity: Float, sparkleIntensity: Float,
                                 canvasSize: CGSize, imageSize: CGSize)?

    /// Distortion is available when a face OR a body was found; the
    /// distortion button greys out otherwise (see EditorView).
    var hasFaceOrBody: Bool { hasFace || hasBody }

    // Brush state (Body tool, manual mode). The canvas reads these to
    // decide whether touches stamp strokes instead of panning.
    @Published var brushMode: BrushMode = .classic
    @Published var brushSizeStop: Int = 2
    @Published var isBrushActive = false

    /// Five discrete brush sizes (points, proxy space).
    static let brushSizeStops: [CGFloat] = [12, 24, 48, 96, 192]

    // Debug overlay state (see DebugOverlay.swift).
    @Published var isDebugVisible = false
    @Published var fps: Double = 0
    @Published var renderMs: Double = 0
    @Published var memoryMB: Double = 0
    @Published var showLandmarksOverlay = false
    @Published var showMasksOverlay = false
    @Published var showFieldOverlay = false
    @Published var isExporting = false
    @Published var exportProgress: Double = 0
    /// URL of the last exported file (for the share sheet); nil until
    /// an export succeeds. The EditorView owner saves it to Photos or
    /// presents the share sheet, then calls cleanupExportFile().
    @Published var exportedFileURL: URL?

    private var exportTask: Task<URL, Error>?

    /// Full-resolution export (tile loop in ExportService): replays the
    /// current sliders and brush strokes analytically at the original
    /// resolution. Runs off the main thread; progress 0...1. Call
    /// cancelExport() to abort (the temp file is not produced).
    func export(format: ExportService.Format = .heic, quality: CGFloat = 0.9, stripGPS: Bool = false) {
        guard exportTask == nil else { return }
        isExporting = true
        exportProgress = 0
        let service = ExportService()
        let state = state
        let extras = extras
        let overlay = overlayBitmap
        let landmarks = landmarks
        let bodyPose = bodyPose
        let personMask = personMaskFloat
        let originalURL = project.originalURL
        exportTask = Task {
            let url = try await service.exportFullResolution(
                state: state, extras: extras, overlay: overlay,
                landmarks: landmarks, bodyPose: bodyPose,
                personMask: personMask, originalURL: originalURL,
                format: format, quality: quality, stripGPS: stripGPS
            ) { [weak self] progress in
                Task { @MainActor in self?.exportProgress = progress }
            }
            await MainActor.run {
                self.exportedFileURL = url
                self.isExporting = false
                self.exportTask = nil
            }
            return url
        }
        Task {
            do {
                _ = try await exportTask?.value
            } catch is CancellationError {
                await MainActor.run {
                    self.isExporting = false
                    self.exportTask = nil
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = AppError.exportFailed.localizedDescription
                    self.isExporting = false
                    self.exportTask = nil
                }
            }
        }
    }

    func cancelExport() {
        exportTask?.cancel()
    }

    /// Deletes the last exported temp file after saving/sharing it.
    func cleanupExportFile() {
        if let url = exportedFileURL {
            ExportService().cleanupTempFile(url)
            exportedFileURL = nil
        }
    }
    @Published private(set) var logLines: [String] = []

    let project: ProjectInfo
    let store: ProjectStore
    let renderGraph: RenderGraph?
    let metalContext: MetalContext?

    private var history = History<EditorSnapshot>()
    private var dragSnapshot: EditorSnapshot?
    // EditorCore History exposes no counts, so undo/redo depth is tracked
    // here (incremented on record, moved on undo/redo).
    private var undoDepth = 0
    private var redoDepth = 0

    /// Last applied (committed) state: Cancel (X) restores this snapshot
    /// and discards everything changed since the current tool was opened.
    private var committedSnapshot: EditorSnapshot?

    init(project: ProjectInfo, store: ProjectStore) {
        self.project = project
        self.store = store
        var loadedState = (try? store.loadState(projectID: project.id)) ?? RetouchState()
        let loadedExtras = store.loadExtras(projectID: project.id)
        store.migrateLegacyExtras(into: &loadedState, extras: loadedExtras, projectID: project.id)
        self.state = loadedState
        self.extras = loadedExtras
        if let source = CGImageSourceCreateWithURL(project.originalURL as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int {
            self.imageSize = CGSize(width: width, height: height)
        }
        if let context = MetalContext() {
            self.metalContext = context
            self.renderGraph = RenderGraph(context: context)
        } else {
            self.metalContext = nil
            self.renderGraph = nil
            self.errorMessage = RenderError.noDevice.localizedDescription
        }
        beginToolSession()
    }

    // MARK: - Slider writes

    /// Call when a drag starts: snapshots once so one drag = one undo step.
    func beginChange() {
        dragSnapshot = EditorSnapshot(state: state, extras: extras)
    }

    /// Call when a drag ends: pushes the snapshot and autosaves.
    func endChange() {
        if let snapshot = dragSnapshot {
            history.record(snapshot)
            dragSnapshot = nil
            undoDepth += 1
            redoDepth = 0
            refreshUndoRedo()
            autosave()
        }
    }

    func updateFace(_ mutate: (inout FaceAdjustments) -> Void) {
        let index = state.ensurePrimaryFaceIndex()
        mutate(&state.faces[index])
        renderGraph?.markGeometryDirty()
    }

    func updateBody(_ mutate: (inout BodyAdjustments) -> Void) {
        mutate(&state.body)
        renderGraph?.markGeometryDirty()
    }

    func updateSkin(_ mutate: (inout SkinAdjustments) -> Void) {
        mutate(&state.skin)
        renderGraph?.markSourceSpaceDirty()
    }

    func updateExtras(_ mutate: (inout ExtraAdjustments) -> Void) {
        mutate(&extras)
        // Extras span geometry (head/lift), paint (overlay) and color
        // (adjust/filter/crop) — mark all three downstream stages dirty.
        renderGraph?.markGeometryDirty()
        renderGraph?.markOverlayDirty()
        renderGraph?.markColorDirty()
        rebuildOverlayIfNeeded()
    }

    /// Rebuilds the paint overlay bitmap + texture when the strokes,
    /// intensities, canvas size or image size changed. A no-op otherwise
    /// (slider drags that do not touch paint do not re-rasterize).
    func rebuildOverlayIfNeeded() {
        let key = (colorStrokes: extras.colorBrushStrokes, sparkleStrokes: extras.sparkleStrokes,
                   colorIntensity: extras.colorBrushIntensity, sparkleIntensity: extras.sparkleIntensity,
                   canvasSize: canvasSize, imageSize: imageSize)
        if let last = lastOverlayKey, last == key { return }
        lastOverlayKey = key
        guard let bitmap = rasterizeOverlayBitmap(extras: extras, imageSize: imageSize, canvasSize: canvasSize) else {
            overlayBitmap = nil
            overlayTexture = nil
            renderGraph?.overlayTexture = nil
            return
        }
        overlayBitmap = bitmap
        if let device = metalContext?.device {
            overlayTexture = makeOverlayTexture(bitmap: bitmap, device: device)
        }
        renderGraph?.overlayTexture = overlayTexture
    }

    /// Builds the live skin-mask texture (person mask AND face oval, at
    /// the person mask's proxy size) after analysis. Without it the
    /// interactive smoothing stage has no mask and is a no-op. The
    /// likelihood term is skipped live (it needs source pixels); export
    /// keeps the full skinMask() version.
    func rebuildSkinMaskTexture() {
        guard let device = metalContext?.device,
              let mask = personMaskFloat,
              let contour = landmarks?.contour, contour.count >= 3 else {
            skinMaskTexture = nil
            renderGraph?.skinMaskTexture = nil
            return
        }
        let width = mask.width
        let height = mask.height
        let oval = faceOvalMask(
            tileWidth: width, tileHeight: height,
            tileOriginX: 0, tileOriginY: 0,
            imageWidth: width, imageHeight: height, contour: contour)
        guard oval.count == mask.values.count else { return }
        var bytes = [UInt8](repeating: 0, count: width * height)
        for index in 0..<bytes.count {
            bytes[index] = UInt8(min(max(mask.values[index] * oval[index], 0), 1) * 255)
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return }
        bytes.withUnsafeBytes { raw in
            guard let baseAddress = raw.baseAddress else { return }
            texture.replace(region: MTLRegionMake2D(0, 0, width, height),
                            mipmapLevel: 0, withBytes: baseAddress, bytesPerRow: width)
        }
        skinMaskTexture = texture
        renderGraph?.skinMaskTexture = texture
    }
    var scope: FaceScope {
        get { state.primaryFace.scope }
        set {
            let index = state.ensurePrimaryFaceIndex()
            state.faces[index].scope = newValue
            renderGraph?.markGeometryDirty()
        }
    }

    /// One-tap Auto: gentle smoothing + shine + wrinkle reduction (P1).
    /// texture 70 = 70% of skin texture kept (see textureKeep01).
    func applyAuto() {
        beginChange()
        updateSkin { skin in
            skin.smoothing = 45
            skin.texture = 70
            skin.shine = 50
            skin.wrinkle = 40
        }
        endChange()
    }

    func resetAll() {
        beginChange()
        state = RetouchState()
        extras = ExtraAdjustments()
        renderGraph?.markAllDirty()
        endChange()
        beginToolSession()
    }

    // MARK: - Committed snapshot (Cancel / Apply)

    /// Snapshots the current state as the committed baseline. Called when
    /// the editor opens and whenever the selected tool changes: opening a
    /// tool starts one editing unit, and Cancel discards that unit.
    func beginToolSession() {
        committedSnapshot = EditorSnapshot(state: state, extras: extras)
    }

    /// Cancel (X): discards every unapplied change since the current tool
    /// was opened, restores the committed snapshot, and clears the undo
    /// history so the discarded changes cannot come back via undo.
    /// Wired to the X button in EditorBottomBar.
    func cancelEditing() {
        guard let committed = committedSnapshot else { return }
        state = committed.state
        extras = committed.extras
        history = History<EditorSnapshot>()
        undoDepth = 0
        redoDepth = 0
        refreshUndoRedo()
        renderGraph?.markAllDirty()
        autosave()
        beginToolSession()
    }

    /// Apply (checkmark): commits the current state as the new baseline
    /// and autosaves. Called by the editor's Apply action.
    func applyEditing() {
        committedSnapshot = EditorSnapshot(state: state, extras: extras)
        autosave()
    }

    // MARK: - Brush strokes

    /// Normalized brush diameter (fraction of image width) for the
    /// current size stop, given the canvas width in points.
    func brushSizeNormalized(canvasWidth: CGFloat) -> Float {
        guard canvasWidth > 0 else { return 0.05 }
        let points = Self.brushSizeStops[brushSizeStop]
        return Float(points / canvasWidth)
    }

    /// Starts a brush stroke at a normalized point (one undo step for
    /// the whole stroke). The stroke grows in state while the finger
    /// moves, so the canvas previews it live.
    func beginBrushStroke(at point: Vec2, size: Float) {
        beginChange()
        state.brushStrokes.append(BrushStroke(
            points: [point], size: size, mode: brushMode, strength: 1
        ))
        renderGraph?.markGeometryDirty()
    }

    /// Appends coalesced touch points (normalized) to the active stroke.
    func continueBrushStroke(points: [Vec2]) {
        guard state.brushStrokes.isEmpty == false else { return }
        state.brushStrokes[state.brushStrokes.count - 1].points.append(contentsOf: points)
        renderGraph?.markGeometryDirty()
    }

    /// Ends the active stroke. A tap (single point) still counts as a
    /// dab; an empty stroke is dropped.
    func endBrushStroke() {
        if let last = state.brushStrokes.last, last.points.isEmpty {
            state.brushStrokes.removeLast()
        }
        endChange()
        renderGraph?.markGeometryDirty()
    }

    // MARK: - Warp ops (face + body + distortion)

    /// All warp ops for the current state, from the analysis landmarks
    /// and pose. Used by the debug field overlay and by export.
    /// Returns [] when no face/body was detected (face tools are disabled
    /// then, so their sliders are all zero anyway).
    func warpOpsForCurrentState() -> [WarpOp] {
        var ops: [WarpOp] = []
        if let faceLandmarks = landmarks, let face = state.faces.first {
            ops.append(contentsOf: faceWarpOps(face: face, landmarks: faceLandmarks))
            ops.append(contentsOf: headLiftWarpOps(extras: extras, landmarks: faceLandmarks))
        }
        if let pose = bodyPose {
            ops.append(contentsOf: bodyWarpOps(body: state.body, pose: pose))
        }
        if let distortion = distortionWarpOp(strength: state.distortionCorrection) {
            ops.append(distortion)
        }
        return ops
    }

    /// Brush dabs for the current strokes (for the debug field overlay).
    func brushDabsForCurrentState() -> [BrushDab] {
        state.brushStrokes.flatMap { brushDabs(from: $0) }
    }

    /// Coarse displacement field (16x12) for the debug field overlay.
    /// Nil when there is nothing to draw (no ops and no strokes).
    func debugFieldGrid() -> (vectors: [Vec2], cols: Int, rows: Int)? {
        let ops = warpOpsForCurrentState()
        let dabs = brushDabsForCurrentState()
        guard ops.isEmpty == false || dabs.isEmpty == false else { return nil }
        let cols = 16
        let rows = 12
        let field = displacementFieldGrid(cols: cols, rows: rows, ops: ops, dabs: dabs)
        return (vectors: field, cols: cols, rows: rows)
    }

    // MARK: - Undo / redo

    func undo() {
        let current = EditorSnapshot(state: state, extras: extras)
        guard let previous = history.undo(current: current) else { return }
        undoDepth = max(undoDepth - 1, 0)
        redoDepth += 1
        applySnapshot(previous)
    }

    func redo() {
        let current = EditorSnapshot(state: state, extras: extras)
        guard let next = history.redo(current: current) else { return }
        redoDepth = max(redoDepth - 1, 0)
        undoDepth += 1
        applySnapshot(next)
    }

    private func applySnapshot(_ snapshot: EditorSnapshot) {
        state = snapshot.state
        extras = snapshot.extras
        renderGraph?.markAllDirty()
        refreshUndoRedo()
        autosave()
    }

    private func refreshUndoRedo() {
        canUndo = undoDepth > 0
        canRedo = redoDepth > 0
    }

    // MARK: - Autosave + analysis

    func autosave() {
        do {
            try store.saveState(state, projectID: project.id)
            try store.saveExtras(extras, projectID: project.id)
        } catch {
            errorMessage = AppError.saveFailed.localizedDescription
        }
    }

    func runAnalysis(image: CGImage) {
        isAnalyzing = true
        Task {
            do {
                let result = try await AnalysisService().analyze(image: image, cacheURL: nil)
                hasFace = result.hasFace
                hasBody = result.hasBody
                landmarks = result.faceLandmarks.first
                bodyPose = result.bodyPose
                if let pixelBuffer = result.personMaskPixelBuffer {
                    personMaskPixelBuffer = pixelBuffer
                    personMaskImage = AnalysisService.maskImage(from: pixelBuffer)
                    personMaskFloat = AnalysisService.floatMask(from: pixelBuffer)
                }
                rebuildSkinMaskTexture()
                if result.hasFace == false {
                    errorMessage = AppError.noFaceFound.localizedDescription
                }
                log("Analysis: \(result.faceCount) face(s), body: \(result.hasBody)")
            } catch {
                errorMessage = AppError.analysisUnavailable.localizedDescription
                log("Analysis failed: \(error.localizedDescription)")
            }
            isAnalyzing = false
        }
    }

    // MARK: - Debug

    func log(_ line: String) {
        logLines.append(line)
        if logLines.count > 500 { logLines.removeFirst() }
    }

    /// Writes the log to a file and copies it to the pasteboard.
    func copyLog() {
        let text = logLines.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ruxel-log.txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        UIPasteboard.general.string = text
    }

    /// Refreshes the memory readout (see DebugOverlay for the VERIFY note).
    func refreshMemory() {
        memoryMB = DebugMemory.currentMemoryMB()
    }
}
