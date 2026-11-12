// CanvasView — UIKit MTKView canvas: pinch/pan/zoom, double-tap, long-press compare.
// What: renders via RenderGraph on demand (isPaused); gestures are UIKit
// recognizers, never SwiftUI gestures, for minimum latency. Zoom to 800%.
// Brush strokes (Body manual mode) and the debug overlay ride on top as
// transparent UIViews. Inputs-outputs: EditorViewModel (source texture +
// render graph + compare + landmarks + pose + masks).
// Threading: the MTKView delegate runs off the main actor, so it talks only
// to RenderBridge (nonisolated); SwiftUI pushes state into the bridge.

import SwiftUI
import MetalKit
import UIKit
import CoreVideo
import EditorCore
struct CanvasView: UIViewRepresentable {
    @ObservedObject var viewModel: EditorViewModel

    func makeUIView(context: Context) -> MTKView {
        let metalView = MTKView()
        metalView.device = context.coordinator.bridge.context?.device
        metalView.isPaused = true
        metalView.enableSetNeedsDisplay = true
        metalView.preferredFramesPerSecond = 120
        // NOTE: MTKView's default maximumDrawableCount is already 3;
        // the property is not settable on iOS, so it is left at default.
        metalView.delegate = context.coordinator
        metalView.colorPixelFormat = .bgra8Unorm
        context.coordinator.attachGestures(to: metalView)
        context.coordinator.attachOverlays(to: metalView)
        context.coordinator.bridge.loadSource(
            from: viewModel.project.originalURL, into: metalView)
        return metalView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        let coordinator = context.coordinator
        coordinator.bridge.state = viewModel.state
        coordinator.bridge.extras = viewModel.extras
        coordinator.bridge.isComparing = viewModel.isComparing
        coordinator.bridge.graph = viewModel.renderGraph
        coordinator.bridge.landmarks = viewModel.landmarks
        coordinator.bridge.bodyPose = viewModel.bodyPose
        coordinator.bridge.setPersonMask(from: viewModel.personMaskPixelBuffer)
        // The canvas size drives the paint overlay (photo rect + brush
        // circularity); rebuild the overlay when it changes.
        if viewModel.canvasSize != uiView.bounds.size {
            viewModel.canvasSize = uiView.bounds.size
            viewModel.rebuildOverlayIfNeeded()
        }
        // Brush is armed only in Body manual mode; arming disables the
        // navigation gestures so a drag stamps a stroke instead of panning.
        let brushArmed = viewModel.isBrushActive
            && (viewModel.selectedTool == .slim || viewModel.selectedTool == .bodySculpt)
        coordinator.setBrushArmed(brushArmed)
        // Debug overlay: data + toggles from the view model.
        let debug = coordinator.debugView
        debug.landmarks = viewModel.landmarks
        debug.personMaskImage = viewModel.personMaskImage
        debug.fieldGrid = viewModel.showFieldOverlay ? viewModel.debugFieldGrid() : nil
        debug.showLandmarks = viewModel.showLandmarksOverlay
        debug.showMasks = viewModel.showMasksOverlay
        debug.showField = viewModel.showFieldOverlay
        debug.isHidden = !(viewModel.showLandmarksOverlay
            || viewModel.showMasksOverlay || viewModel.showFieldOverlay)
        debug.setNeedsDisplay()
        uiView.setNeedsDisplay()
    }

    func makeCoordinator() -> Coordinator {
        let bridge = RenderBridge(context: viewModel.metalContext)
        bridge.onError = { message in
            Task { @MainActor in self.viewModel.errorMessage = message }
        }
        bridge.onFps = { fps in
            Task { @MainActor in self.viewModel.fps = fps }
        }
        bridge.onRenderMs = { ms in
            Task { @MainActor in self.viewModel.renderMs = ms }
        }
        bridge.onCompareChanged = { comparing in
            Task { @MainActor in self.viewModel.isComparing = comparing }
        }
        let coordinator = Coordinator(bridge: bridge)
        coordinator.onBrushBegan = { point, canvasWidth in
            Task { @MainActor in
                let size = self.viewModel.brushSizeNormalized(canvasWidth: canvasWidth)
                self.viewModel.beginBrushStroke(
                    at: Vec2(Float(point.x), Float(point.y)), size: size)
            }
        }
        coordinator.onBrushMoved = { points in
            Task { @MainActor in
                self.viewModel.continueBrushStroke(points: points.map {
                    Vec2(Float($0.x), Float($0.y))
                })
            }
        }
        coordinator.onBrushEnded = {
            Task { @MainActor in self.viewModel.endBrushStroke() }
        }
        return coordinator
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        let bridge: RenderBridge
        let brushView = BrushTouchView()
        let debugView = DebugOverlayView()
        /// Normalized point + canvas width in points (for brush size).
        var onBrushBegan: ((CGPoint, CGFloat) -> Void)?
        var onBrushMoved: (([CGPoint]) -> Void)?
        var onBrushEnded: (() -> Void)?

        private var scale: CGFloat = 1
        private var translation = CGPoint.zero
        private var pinchRecognizer: UIPinchGestureRecognizer?
        private var panRecognizer: UIPanGestureRecognizer?
        private var doubleTapRecognizer: UITapGestureRecognizer?
        private var longPressRecognizer: UILongPressGestureRecognizer?

        init(bridge: RenderBridge) {
            self.bridge = bridge
        }

        func attachGestures(to view: MTKView) {
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            view.addGestureRecognizer(pinch)
            view.addGestureRecognizer(pan)
            view.addGestureRecognizer(doubleTap)
            view.addGestureRecognizer(longPress)
            pinchRecognizer = pinch
            panRecognizer = pan
            doubleTapRecognizer = doubleTap
            longPressRecognizer = longPress
        }

        func attachOverlays(to view: MTKView) {
            brushView.frame = view.bounds
            brushView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            brushView.onStrokeBegan = { [weak self] point in
                guard let self else { return }
                self.onBrushBegan?(point, self.brushView.bounds.width)
            }
            brushView.onStrokeMoved = { [weak self] points in
                self?.onBrushMoved?(points)
            }
            brushView.onStrokeEnded = { [weak self] in
                self?.onBrushEnded?()
            }
            debugView.frame = view.bounds
            debugView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(debugView)
            view.addSubview(brushView)
        }

        /// Arms/disarms the brush. While armed the brush view takes
        /// touches and the navigation gestures are disabled.
        func setBrushArmed(_ armed: Bool) {
            brushView.isBrushArmed = armed
            brushView.isUserInteractionEnabled = armed
            pinchRecognizer?.isEnabled = !armed
            panRecognizer?.isEnabled = !armed
            doubleTapRecognizer?.isEnabled = !armed
            longPressRecognizer?.isEnabled = !armed
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let view = gesture.view else { return }
            // 800% max zoom; 100% min. Interaction drops render resolution
            // (see RenderGraph.isInteracting) while the finger is down.
            scale = min(max(scale * gesture.scale, 1), 8)
            gesture.scale = 1
            bridge.graph?.isInteracting = gesture.state != .ended
            applyTransform(to: view)
            if gesture.state == .ended {
                bridge.graph?.isInteracting = false
                view.setNeedsDisplay()
            }
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let delta = gesture.translation(in: view)
            translation.x += delta.x
            translation.y += delta.y
            gesture.setTranslation(.zero, in: view)
            // Inertia: on release, glide with the release velocity.
            if gesture.state == .ended {
                let velocity = gesture.velocity(in: view)
                let target = CGPoint(
                    x: translation.x + velocity.x * 0.15,
                    y: translation.y + velocity.y * 0.15)
                UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
                    self.translation = target
                    self.applyTransform(to: view)
                }
            }
            bridge.graph?.isInteracting = gesture.state != .ended
            applyTransform(to: view)
        }

        @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            scale = scale > 1.5 ? 1 : 2
            translation = .zero
            UIView.animate(withDuration: 0.25) { self.applyTransform(to: view) }
        }

        @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            // Hold to see the original; release to return to the retouch.
            let comparing = gesture.state == .began || gesture.state == .changed
            bridge.isComparing = comparing
            bridge.onCompareChanged?(comparing)
        }

        private func applyTransform(to view: UIView) {
            view.transform = CGAffineTransform(translationX: translation.x, y: translation.y)
                .scaledBy(x: scale, y: scale)
        }

        // MARK: - MTKViewDelegate

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            bridge.draw(in: view)
        }
    }
}

// RenderBridge — nonisolated owner of the Metal render path for the canvas.
// What: loads the source texture, renders each drawable, measures fps.
// Inputs-outputs: state snapshot + graph in; drawable out; errors via onError.
// Threading: nonisolated on purpose — the MTKView delegate is not @MainActor.
final class RenderBridge {
    let context: MetalContext?
    var graph: RenderGraph?
    var state = RetouchState()
    var extras = ExtraAdjustments()
    var isComparing = false
    var landmarks: FaceLandmarks?
    var bodyPose: BodyPose?
    var onError: ((String) -> Void)?
    var onFps: ((Double) -> Void)?
    var onRenderMs: ((Double) -> Void)?
    var onCompareChanged: ((Bool) -> Void)?

    private var lastDrawTime = CFAbsoluteTimeGetCurrent()
    private var fpsAccumulator = 0.0
    private var fpsFrames = 0
    private var textureCache: CVMetalTextureCache?
    private var lastMaskPixelBuffer: CVPixelBuffer?

    init(context: MetalContext?) {
        self.context = context
    }

    func loadSource(from url: URL, into metalView: MTKView) {
        guard let device = context?.device else { return }
        Task {
            do {
                let loader = MTKTextureLoader(device: device)
                // VERIFY: MTKTextureLoader.newTexture(URL:options:) + SRGB option key.
                let texture = try await loader.newTexture(
                    URL: url,
                    options: [MTKTextureLoader.Option.SRGB: false])
                graph?.setSource(texture)
                await MainActor.run { metalView.setNeedsDisplay() }
            } catch {
                onError?(AppError.photoLoadFailed.localizedDescription)
            }
        }
    }

    /// Builds the person-mask texture (r8Unorm, feathered by Vision) from
    /// the analysis pixel buffer, once per buffer. The graph multiplies
    /// the displacement field by it when background lock is on.
    /// VERIFY: CVMetalTextureCacheCreateTextureFromImage with .r8Unorm
    /// for a OneComponent8 segmentation buffer on iOS 16.
    func setPersonMask(from pixelBuffer: CVPixelBuffer?) {
        guard let device = context?.device else { return }
        guard let pixelBuffer, pixelBuffer !== lastMaskPixelBuffer else { return }
        lastMaskPixelBuffer = pixelBuffer
        if textureCache == nil {
            var cache: CVMetalTextureCache?
            guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess,
                  let created = cache else { return }
            textureCache = created
        }
        guard let cache = textureCache else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var metalTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, cache, pixelBuffer, nil, .r8Unorm, width, height, 0, &metalTexture)
        guard status == kCVReturnSuccess,
              let metalTexture,
              let texture = CVMetalTextureGetTexture(metalTexture) else { return }
        graph?.personMaskTexture = texture
    }

    func draw(in view: MTKView) {
        let now = CFAbsoluteTimeGetCurrent()
        let delta = now - lastDrawTime
        lastDrawTime = now
        fpsAccumulator += delta
        fpsFrames += 1
        if fpsAccumulator >= 0.5, fpsFrames > 0 {
            let fps = Double(fpsFrames) / fpsAccumulator
            fpsAccumulator = 0
            fpsFrames = 0
            onFps?(fps)
        }
        guard let drawable = view.currentDrawable,
              let renderGraph = graph else { return }
        renderGraph.landmarks = landmarks
        renderGraph.bodyPose = bodyPose
        do {
            // Compare mode shows the unretouched source: render the neutral
            // state AND neutral extras into the drawable instead of the
            // live state (otherwise paint + color grade would still show).
            let state = isComparing ? RetouchState() : state
            let extras = isComparing ? ExtraAdjustments() : extras
            try renderGraph.render(state: state, extras: extras, output: drawable.texture)
            onRenderMs?(renderGraph.lastStageTimings["totalMs"] ?? 0)
            drawable.present()
        } catch {
            onError?(AppError.exportFailed.localizedDescription)
        }
    }
}
