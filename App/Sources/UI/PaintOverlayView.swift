import SwiftUI
import UIKit

// PaintOverlayView — SwiftUI bridge for the paint canvas (color brush,
// object eraser, sparkle brush). Shown by EditorView only while a paint
// tool is selected; it sits above the canvas and below the tool panel.
// What: syncs the active tool's strokes + brush settings into
// PaintCanvasView; commits finished strokes into ExtraAdjustments.
// Inputs-outputs: EditorViewModel in; strokes out (one undo step each).
// Threading: @MainActor view; UIKit callbacks hop back via Task.
struct PaintOverlayView: UIViewRepresentable {
    @ObservedObject var viewModel: EditorViewModel

    func makeUIView(context: Context) -> PaintCanvasView {
        let view = PaintCanvasView()
        view.onStrokeBegan = {
            Task { @MainActor in viewModel.beginChange() }
        }
        view.onStrokeEnded = { stroke in
            Task { @MainActor in
                viewModel.updateExtras { extras in
                    switch stroke.kind {
                    case .color:
                        extras.colorBrushStrokes.append(stroke)
                    case .erase:
                        extras.eraserMaskStrokes.append(stroke)
                    case .sparkle:
                        extras.sparkleStrokes.append(stroke)
                    }
                }
                viewModel.renderGraph?.markSourceSpaceDirty()
                viewModel.endChange()
            }
        }
        return view
    }

    func updateUIView(_ uiView: PaintCanvasView, context: Context) {
        switch viewModel.selectedTool {
        case .colorBrush:
            uiView.strokes = viewModel.extras.colorBrushStrokes
            uiView.brushKind = .color
            uiView.brushColor = UIColor(
                red: CGFloat(viewModel.extras.colorBrushRed),
                green: CGFloat(viewModel.extras.colorBrushGreen),
                blue: CGFloat(viewModel.extras.colorBrushBlue),
                alpha: 1
            )
            uiView.brushStrength = CGFloat(viewModel.extras.colorBrushIntensity / 100)
            uiView.brushSizePoints = brushPoints(from: viewModel.extras.colorBrushSize)
            uiView.sparkleStyle = ""
        case .eraser:
            uiView.strokes = viewModel.extras.eraserMaskStrokes
            uiView.brushKind = .erase
            uiView.brushColor = .red
            uiView.brushStrength = 0.45
            uiView.brushSizePoints = brushPoints(from: viewModel.extras.eraserSize)
            uiView.sparkleStyle = ""
        case .brush:
            uiView.strokes = viewModel.extras.sparkleStrokes
            uiView.brushKind = .sparkle
            uiView.brushColor = .white
            uiView.brushStrength = CGFloat(viewModel.extras.sparkleIntensity / 100)
            uiView.brushSizePoints = brushPoints(from: viewModel.extras.sparkleSize)
            uiView.sparkleStyle = viewModel.extras.sparkleStyle.rawValue
        default:
            uiView.strokes = []
            uiView.isPaintingEnabled = false
            return
        }
        uiView.isPaintingEnabled = true
    }

    /// Slider 0...100 -> brush diameter in points (10...120).
    private func brushPoints(from slider: Float) -> CGFloat {
        10 + CGFloat(min(max(slider, 0), 100)) / 100 * 110
    }
}
