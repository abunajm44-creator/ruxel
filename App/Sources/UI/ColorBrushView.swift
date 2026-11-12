import SwiftUI
import UIKit

// ColorBrushView — color/paint brush: paint color onto masked regions.
// What: color picker + intensity + brush size; strokes are painted on the
// photo through PaintOverlayView and stored in ExtraAdjustments.
// Inputs-outputs: edits -> viewModel.extras (one undo step per stroke).
// Threading: @MainActor SwiftUI view; view model is @ObservedObject.
// NOTE: the render graph has no color-brush pass yet — strokes are stored
// and autosaved; the blend (Lab, luminance-preserving) lands with the pass.
struct ColorBrushView: View {
    @ObservedObject var viewModel: EditorViewModel
    @State private var colorSessionOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ColorPicker(
                "colorBrush.color",
                selection: colorBinding,
                supportsOpacity: false
            )
            .frame(minHeight: 44)
            .accessibilityLabel(Text("colorBrush.color"))
            BipolarSlider(
                value: Binding(
                    get: { viewModel.extras.colorBrushIntensity },
                    set: { newValue in
                        viewModel.updateExtras { $0.colorBrushIntensity = newValue }
                        viewModel.renderGraph?.markSourceSpaceDirty()
                    }
                ),
                range: 0...100,
                isBipolar: false,
                titleKey: "colorBrush.intensity",
                onBegin: { viewModel.beginChange() },
                onEnd: { viewModel.endChange() }
            )
            BipolarSlider(
                value: Binding(
                    get: { viewModel.extras.colorBrushSize },
                    set: { newValue in
                        viewModel.updateExtras { $0.colorBrushSize = newValue }
                    }
                ),
                range: 0...100,
                isBipolar: false,
                titleKey: "colorBrush.size",
                onBegin: { viewModel.beginChange() },
                onEnd: { viewModel.endChange() }
            )
            Text("colorBrush.hint")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button(action: clearStrokes) {
                Text("colorBrush.clear")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .frame(minHeight: 44)
            .adaptiveGlass(in: RoundedRectangle(cornerRadius: 14), interactive: true)
            .disabled(viewModel.extras.colorBrushStrokes.isEmpty)
            .accessibilityLabel(Text("colorBrush.clear"))
        }
        .onDisappear { endColorSession() }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                Color(
                    red: Double(viewModel.extras.colorBrushRed),
                    green: Double(viewModel.extras.colorBrushGreen),
                    blue: Double(viewModel.extras.colorBrushBlue)
                )
            },
            set: { newColor in
                if colorSessionOpen == false {
                    viewModel.beginChange()
                    colorSessionOpen = true
                }
                var red: CGFloat = 0
                var green: CGFloat = 0
                var blue: CGFloat = 0
                var alpha: CGFloat = 0
                guard UIColor(newColor).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
                viewModel.updateExtras { extras in
                    extras.colorBrushRed = Float(red)
                    extras.colorBrushGreen = Float(green)
                    extras.colorBrushBlue = Float(blue)
                }
            }
        )
    }

    private func clearStrokes() {
        viewModel.beginChange()
        viewModel.updateExtras { $0.colorBrushStrokes.removeAll() }
        viewModel.renderGraph?.markSourceSpaceDirty()
        viewModel.endChange()
    }

    private func endColorSession() {
        if colorSessionOpen {
            colorSessionOpen = false
            viewModel.endChange()
        }
    }
}
