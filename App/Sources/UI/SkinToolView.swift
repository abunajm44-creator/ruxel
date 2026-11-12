import SwiftUI
import EditorCore

// SkinToolView — skin retouch: smoothing + texture + grain, Auto, cleanup tools.
// What: one-way 0...100 sliders on EditorCore SkinAdjustments (grain included).
// Inputs-outputs: drags -> EditorViewModel (one undo step per drag).
// Threading: @MainActor SwiftUI view; view model is @ObservedObject.
struct SkinToolView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { viewModel.applyAuto() }) {
                HStack {
                    Image(systemName: "wand.and.stars")
                    Text("skin.auto")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .adaptiveGlass(in: RoundedRectangle(cornerRadius: 14), interactive: true)
            .accessibilityLabel(Text("skin.auto"))

            oneWaySlider(skin: \.smoothing, key: "skin.smoothing")
            oneWaySlider(skin: \.texture, key: "skin.texture")
            oneWaySlider(skin: \.grain, key: "skin.grain")
            oneWaySlider(skin: \.wrinkle, key: "skin.wrinkles")
            oneWaySlider(skin: \.acne, key: "skin.acne")
            oneWaySlider(skin: \.shine, key: "skin.shine")
            oneWaySlider(skin: \.darkCircles, key: "skin.darkCircles")
            oneWaySlider(skin: \.teethWhitening, key: "skin.teeth")
            oneWaySlider(skin: \.eyeEnhance, key: "skin.eyeEnhance")
        }
    }

    private func oneWaySlider(skin keyPath: WritableKeyPath<SkinAdjustments, Float>, key: String) -> some View {
        BipolarSlider(
            value: Binding(
                get: { viewModel.state.skin[keyPath: keyPath] },
                set: { newValue in
                    viewModel.updateSkin { skin in skin[keyPath: keyPath] = newValue }
                }
            ),
            range: 0...100,
            isBipolar: false,
            titleKey: key,
            onBegin: { viewModel.beginChange() },
            onEnd: { viewModel.endChange() }
        )
    }
}
