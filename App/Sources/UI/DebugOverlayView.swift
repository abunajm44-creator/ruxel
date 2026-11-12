// DebugOverlayView — lightweight canvas overlay for the hidden diagnostics.
// What: draws landmarks (dots + polylines), the person mask (translucent
// green), and the displacement field (arrows on a coarse grid) on top of
// the canvas, each gated by its DebugOverlay toggle. Pure drawing: no
// Metal, no state writes, redrawn only when the view model pushes data.
// Inputs-outputs: landmarks / mask image / field grid in; pixels out.
// Threading: UIKit drawing on the main thread; data is set from updateUIView.
import UIKit
import EditorCore

final class DebugOverlayView: UIView {
    var landmarks: FaceLandmarks?
    var personMaskImage: UIImage?
    var fieldGrid: (vectors: [Vec2], cols: Int, rows: Int)?

    var showLandmarks = false
    var showMasks = false
    var showField = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        if showMasks, let mask = personMaskImage {
            // Translucent green tint over the person mask.
            context.saveGState()
            context.setAlpha(0.35)
            mask.draw(in: bounds)
            context.restoreGState()
        }
        if showLandmarks, let landmarks {
            drawLandmarks(landmarks, in: context)
        }
        if showField, let field = fieldGrid {
            drawField(field, in: context)
        }
    }

    private func point(_ normalized: Vec2) -> CGPoint {
        CGPoint(x: CGFloat(normalized.x) * bounds.width, y: CGFloat(normalized.y) * bounds.height)
    }

    private func drawLandmarks(_ landmarks: FaceLandmarks, in context: CGContext) {
        context.setStrokeColor(UIColor.systemYellow.cgColor)
        context.setFillColor(UIColor.systemYellow.cgColor)
        context.setLineWidth(1)
        let regions: [[Vec2]] = [
            landmarks.contour, landmarks.leftEye, landmarks.rightEye,
            landmarks.leftBrow, landmarks.rightBrow, landmarks.nose,
            landmarks.noseCrest, landmarks.medianLine,
            landmarks.outerLips, landmarks.innerLips
        ]
        for region in regions where region.count > 1 {
            context.beginPath()
            context.move(to: point(region[0]))
            for item in region.dropFirst() {
                context.addLine(to: point(item))
            }
            context.closePath()
            context.strokePath()
        }
        for pupil in [landmarks.leftPupil, landmarks.rightPupil] {
            let center = point(pupil)
            context.fillEllipse(in: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6))
        }
    }

    private func drawField(_ field: (vectors: [Vec2], cols: Int, rows: Int), in context: CGContext) {
        // Arrows are scaled up 8x so the small normalized displacements
        // are visible; direction and relative length stay true.
        let scale: CGFloat = 8
        context.setStrokeColor(UIColor.systemCyan.cgColor)
        context.setLineWidth(1)
        for row in 0..<field.rows {
            for col in 0..<field.cols {
                let vector = field.vectors[row * field.cols + col]
                guard vector.length > 0.001 else { continue }
                let start = CGPoint(
                    x: CGFloat(col) / CGFloat(max(field.cols - 1, 1)) * bounds.width,
                    y: CGFloat(row) / CGFloat(max(field.rows - 1, 1)) * bounds.height)
                let end = CGPoint(
                    x: start.x + CGFloat(vector.x) * bounds.width * scale,
                    y: start.y + CGFloat(vector.y) * bounds.height * scale)
                context.beginPath()
                context.move(to: start)
                context.addLine(to: end)
                context.strokePath()
                // Arrowhead.
                let angle = atan2(end.y - start.y, end.x - start.x)
                let headLength: CGFloat = 5
                context.beginPath()
                context.move(to: end)
                context.addLine(to: CGPoint(
                    x: end.x - headLength * cos(angle - 0.4),
                    y: end.y - headLength * sin(angle - 0.4)))
                context.move(to: end)
                context.addLine(to: CGPoint(
                    x: end.x - headLength * cos(angle + 0.4),
                    y: end.y - headLength * sin(angle + 0.4)))
                context.strokePath()
            }
        }
    }
}
