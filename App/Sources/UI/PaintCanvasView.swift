import UIKit
import EditorCore

// PaintCanvasView — transparent touch surface that draws paint strokes.
// What: a pan gesture collects points; strokes are drawn as round-cap
// polylines (color), a translucent red mask (erase), or stamped dots
// (sparkle). Points are stored normalized to this view's bounds.
// Inputs-outputs: strokes in (committed strokes redrawn), brush settings in;
// a finished PaintStroke out via onStrokeEnded.
// Threading: UIKit, main thread only. Callbacks fire on the main thread.
// NOTE: points are normalized to the OVERLAY bounds, not the photo rect —
// the canvas does not expose its photo rect yet (see PaintStroke header).
final class PaintCanvasView: UIView {
    /// Committed strokes, redrawn on every setNeedsDisplay.
    var strokes: [PaintStroke] = [] {
        didSet { setNeedsDisplay() }
    }
    /// Brush diameter in points, as displayed.
    var brushSizePoints: CGFloat = 30
    var brushColor: UIColor = .red
    var brushStrength: CGFloat = 0.6
    var brushKind: PaintStrokeKind = .color
    var sparkleStyle: String = ""
    var isPaintingEnabled = true

    /// Fires once when a stroke starts (undo snapshot point).
    var onStrokeBegan: (() -> Void)?
    /// Fires once when a stroke ends, with the finished stroke.
    var onStrokeEnded: ((PaintStroke) -> Void)?

    private var currentPoints: [CGPoint] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        // Programmatic-only view; never instantiated from a storyboard.
        return nil
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard isPaintingEnabled else { return }
        let point = gesture.location(in: self)
        switch gesture.state {
        case .began:
            currentPoints = [point]
            onStrokeBegan?()
            setNeedsDisplay()
        case .changed:
            currentPoints.append(point)
            setNeedsDisplay()
        case .ended, .cancelled:
            currentPoints.append(point)
            finishStroke()
            setNeedsDisplay()
        default:
            break
        }
    }

    private func finishStroke() {
        guard currentPoints.isEmpty == false else { return }
        let normalized = currentPoints.map { normalizedPoint($0) }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        brushColor.getRed(&red, green: &green, blue: &blue, alpha: nil)
        let stroke = PaintStroke(
            kind: brushKind,
            points: normalized,
            size: Float(bounds.width > 0 ? brushSizePoints / bounds.width : 0.03),
            strength: Float(brushStrength),
            red: Float(red),
            green: Float(green),
            blue: Float(blue),
            style: sparkleStyle
        )
        currentPoints.removeAll()
        onStrokeEnded?(stroke)
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        for stroke in strokes {
            drawStroke(stroke, in: context)
        }
        if currentPoints.isEmpty == false {
            let preview = PaintStroke(
                kind: brushKind,
                points: currentPoints.map { normalizedPoint($0) },
                size: Float(bounds.width > 0 ? brushSizePoints / bounds.width : 0.03),
                strength: Float(brushStrength),
                style: sparkleStyle
            )
            drawStroke(preview, in: context)
        }
    }

    /// View point -> normalized 0...1 point (0 when the view has no size yet).
    private func normalizedPoint(_ point: CGPoint) -> Vec2 {
        Vec2(
            Float(bounds.width > 0 ? point.x / bounds.width : 0),
            Float(bounds.height > 0 ? point.y / bounds.height : 0)
        )
    }

    private func drawStroke(_ stroke: PaintStroke, in context: CGContext) {
        guard stroke.points.count > 0 else { return }
        let viewPoints = stroke.points.map { point in
            CGPoint(x: CGFloat(point.x) * bounds.width, y: CGFloat(point.y) * bounds.height)
        }
        let width = max(CGFloat(stroke.size) * bounds.width, 2)
        switch stroke.kind {
        case .color:
            context.setStrokeColor(
                UIColor(
                    red: CGFloat(stroke.red),
                    green: CGFloat(stroke.green),
                    blue: CGFloat(stroke.blue),
                    alpha: CGFloat(stroke.strength)
                ).cgColor
            )
            context.setLineWidth(width)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.addLines(between: viewPoints)
            context.strokePath()
        case .erase:
            // The eraser mask: translucent red so the masked area is visible.
            context.setStrokeColor(UIColor.red.withAlphaComponent(0.45).cgColor)
            context.setLineWidth(width)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.addLines(between: viewPoints)
            context.strokePath()
        case .sparkle:
            drawSparkleStamps(viewPoints, width: width, stroke: stroke, in: context)
        }
    }

    private func drawSparkleStamps(
        _ points: [CGPoint], width: CGFloat, stroke: PaintStroke, in context: CGContext
    ) {
        // One stamp per ~half-diameter of travel, so fast drags stay dotted.
        var lastStamp: CGPoint?
        for point in points {
            if let last = lastStamp, last.distance(to: point) < width * 0.5 {
                continue
            }
            lastStamp = point
            let radius = width * 0.5
            let alpha = CGFloat(stroke.strength)
            if stroke.style == "star" {
                drawStar(at: point, radius: radius, alpha: alpha, in: context)
            } else if stroke.style == "glitter" {
                drawStar(at: point, radius: radius * 0.6, alpha: alpha, in: context)
                context.setFillColor(UIColor.white.withAlphaComponent(alpha * 0.5).cgColor)
                context.fillEllipse(in: CGRect(
                    x: point.x - radius, y: point.y - radius,
                    width: radius * 2, height: radius * 2))
            } else {
                // Glow: soft white disc.
                context.setFillColor(UIColor.white.withAlphaComponent(alpha * 0.7).cgColor)
                context.fillEllipse(in: CGRect(
                    x: point.x - radius, y: point.y - radius,
                    width: radius * 2, height: radius * 2))
            }
        }
    }

    private func drawStar(at center: CGPoint, radius: CGFloat, alpha: CGFloat, in context: CGContext) {
        // 4-point star: two overlapping diamonds, no asset needed.
        let path = CGMutablePath()
        let points = [
            CGPoint(x: center.x, y: center.y - radius),
            CGPoint(x: center.x + radius * 0.28, y: center.y - radius * 0.28),
            CGPoint(x: center.x + radius, y: center.y),
            CGPoint(x: center.x + radius * 0.28, y: center.y + radius * 0.28),
            CGPoint(x: center.x, y: center.y + radius),
            CGPoint(x: center.x - radius * 0.28, y: center.y + radius * 0.28),
            CGPoint(x: center.x - radius, y: center.y),
            CGPoint(x: center.x - radius * 0.28, y: center.y - radius * 0.28),
        ]
        path.move(to: points[0])
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        context.setFillColor(UIColor.white.withAlphaComponent(alpha).cgColor)
        context.addPath(path)
        context.fillPath()
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
