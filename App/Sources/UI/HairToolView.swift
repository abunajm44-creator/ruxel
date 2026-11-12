import SwiftUI
import UIKit

// HairToolView — EXPERIMENTAL: hair recolor / volume / flyaway smoothing.
// What: controls write to ExtraAdjustments, but the whole tool is gated on
// a hair mask (AVSemanticSegmentationMatte when the photo has one).
// Inputs-outputs: edits -> viewModel.extras (one undo step per drag).
// Threading: @MainActor SwiftUI view; view model is @ObservedObject.
// NOTE: AnalysisService does not request a hair matte yet, so hasHairMask
// is false and every control is disabled with an honest message. Do NOT
// enable the controls until a real hair mask reaches the view model.
struct HairToolView: View {
    @ObservedObject var viewModel: EditorViewModel
    @State private var colorSessionOpen = false

    /// No hair mask source exists in this build (see header note).
    private var hasHairMask: Bool { false }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hasHairMask == false {
                Text("hair.unavailable")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ColorPicker(
                "hair.color",
                selection: colorBinding,
                supportsOpacity: false
            )
            .frame(minHeight: 44)
            .accessibilityLabel(Text("hair.color"))
            BipolarSlider(
                value: Binding(
                    get: { viewModel.extras.hairVolume },
                    set: { newValue in viewModel.updateExtras { $0.hairVolume = newValue } }
                ),
                titleKey: "hair.volume",
                onBegin: { viewModel.beginChange() },
                onEnd: { viewModel.endChange() }
            )
            BipolarSlider(
                value: Binding(
                    get: { viewModel.extras.hairFlyaway },
                    set: { newValue in viewModel.updateExtras { $0.hairFlyaway = newValue } }
                ),
                titleKey: "hair.flyaway",
                onBegin: { viewModel.beginChange() },
                onEnd: { viewModel.endChange() }
            )
        }
        .disabled(hasHairMask == false)
        .onDisappear { endColorSession() }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                Color(
                    red: Double(viewModel.extras.hairRed),
                    green: Double(viewModel.extras.hairGreen),
                    blue: Double(viewModel.extras.hairBlue)
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
                    extras.hairRed = Float(red)
                    extras.hairGreen = Float(green)
                    extras.hairBlue = Float(blue)
                }
            }
        )
    }

    private func endColorSession() {
        if colorSessionOpen {
            colorSessionOpen = false
            viewModel.endChange()
        }
    }
}
