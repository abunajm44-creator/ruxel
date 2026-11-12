// BrushTouchView — transparent touch layer over the canvas for brush strokes.
// What: captures touches only while the brush is armed; reports normalized
// points (0...1) via callbacks. Uses coalesced touches (every sample the
// system recorded, not just the delivered ones) so fast drags stay smooth,
// and predicted touches for the live preview point.
// Inputs-outputs: UITouch events in; normalized CGPoint batches out.
// Threading: UIKit touch callbacks run on the main thread.
import UIKit
import EditorCore

final class BrushTouchView: UIView {
    /// True while the body brush is armed (manual mode). When false the
    /// view ignores touches so pinch/pan gestures work normally.
    var isBrushArmed = false

    var onStrokeBegan: ((CGPoint) -> Void)?
    var onStrokeMoved: (([CGPoint]) -> Void)?
    var onStrokeEnded: (() -> Void)?

    private var activeTouch: UITouch?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isBrushArmed, activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch
        onStrokeBegan?(normalizedPoint(for: touch))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isBrushArmed, let touch = activeTouch, touches.contains(touch) else { return }
        // Coalesced touches: every sample since the last delivery, so a
        // fast drag produces a continuous stroke instead of straight
        // segments between sparse delivered points.
        var points: [CGPoint] = []
        if let event {
            for coalesced in event.coalescedTouches(for: touch) ?? [] {
                points.append(normalizedPoint(for: coalesced))
            }
        }
        if points.isEmpty {
            points.append(normalizedPoint(for: touch))
        }
        onStrokeMoved?(points)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        activeTouch = nil
        onStrokeEnded?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        activeTouch = nil
        onStrokeEnded?()
    }

    /// Touch location in normalized image coordinates. The view covers the
    /// canvas bounds and the image is blitted full-bleed, so view space
    /// maps linearly to image space (aspect-fit letterboxing ignored).
    private func normalizedPoint(for touch: UITouch) -> CGPoint {
        let location = touch.location(in: self)
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        return CGPoint(
            x: min(max(location.x / bounds.width, 0), 1),
            y: min(max(location.y / bounds.height, 0), 1)
        )
    }
}
