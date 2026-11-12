import SwiftUI
import EditorCore

// FaceToolView — face reshape tabs (RTL): 3D | Face | Brows | Eyes | Nose | Lips.
// What: bipolar -100...100 sliders on EditorCore FaceAdjustments
// (all 32 spec sliders); the 3D tab also holds the pose attenuation
// factors (0...100 one-way sliders -> 0...1 factors on the face).
// Inputs-outputs: drags -> EditorViewModel (one undo step per drag).
// Threading: @MainActor SwiftUI view; view model is @ObservedObject.
struct FaceToolView: View {
    @ObservedObject var viewModel: EditorViewModel
    @State private var selectedTab: FaceTab = .face

    enum FaceTab: String, CaseIterable, Identifiable {
        case threeD
        case face
        case brows
        case eyes
        case nose
        case lips

        var id: String { rawValue }
        var titleKey: String { "face.tab.\(rawValue)" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            tabRow
            if viewModel.hasFace == false {
                Text("editor.noFace")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            switch selectedTab {
            case .threeD: threeDSliders
            case .face: faceSliders
            case .brows: browSliders
            case .eyes: eyeSliders
            case .nose: noseSliders
            case .lips: lipSliders
            }
        }
    }

    private var tabRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FaceTab.allCases) { tab in
                    Button(action: { selectedTab = tab }) {
                        Text(tab.titleKey)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .adaptiveGlass(
                        in: Capsule(),
                        tint: selectedTab == tab ? Color.accentColor.opacity(0.25) : nil,
                        interactive: true
                    )
                    .accessibilityLabel(Text(tab.titleKey))
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    // MARK: - Tabs

    private var threeDSliders: some View {
        VStack(spacing: 12) {
            Text("face.threeD.body")
                .font(.footnote)
                .foregroundStyle(.secondary)
            slider(face: \.faceLength, key: "face.slider.faceLength")
            slider(face: \.vShape, key: "face.slider.faceVShape")
            // Pose-aware reshape: how much the far side of the face is
            // frozen at a 3/4 pose (0 = no attenuation, 100 = fully frozen).
            attenuationSlider(face: \.yawAttenuation, key: "face.slider.yawAttenuation")
            attenuationSlider(face: \.pitchAttenuation, key: "face.slider.pitchAttenuation")
            attenuationSlider(face: \.rollAttenuation, key: "face.slider.rollAttenuation")
        }
    }

    private var faceSliders: some View {
        VStack(spacing: 12) {
            slider(face: \.faceWidth, key: "face.slider.faceWidth")
            slider(face: \.jawSize, key: "face.slider.jaw")
            slider(face: \.chinLength, key: "face.slider.chin")
            slider(face: \.chinWidth, key: "face.slider.chinWidth")
            slider(face: \.cheekbones, key: "face.slider.cheekbones")
            slider(face: \.temples, key: "face.slider.temples")
            slider(face: \.foreheadHeight, key: "face.slider.forehead")
            slider(face: \.faceLength, key: "face.slider.faceLength")
            slider(face: \.vShape, key: "face.slider.faceVShape")
        }
    }

    private var browSliders: some View {
        VStack(spacing: 12) {
            slider(face: \.browHeight, key: "face.slider.browHeight")
            slider(face: \.browDistance, key: "face.slider.browDistance")
            slider(face: \.browThickness, key: "face.slider.browThickness")
            slider(face: \.browAngle, key: "face.slider.browAngle")
            slider(face: \.browLength, key: "face.slider.browLength")
            slider(face: \.browShape, key: "face.slider.browShape")
        }
    }

    private var eyeSliders: some View {
        VStack(spacing: 12) {
            slider(face: \.eyeSize, key: "face.slider.eyeSize")
            slider(face: \.eyeHeight, key: "face.slider.eyeHeight")
            slider(face: \.eyeWidth, key: "face.slider.eyeWidth")
            slider(face: \.eyeLength, key: "face.slider.eyeLength")
            slider(face: \.eyeSpacing, key: "face.slider.eyeDistance")
            slider(face: \.eyePuffy, key: "face.slider.eyePuffy")
            slider(face: \.eyeAngle, key: "face.slider.eyeAngle")
            slider(face: \.eyePosition, key: "face.slider.eyePosition")
        }
    }

    private var noseSliders: some View {
        VStack(spacing: 12) {
            slider(face: \.noseSize, key: "face.slider.noseSize")
            slider(face: \.noseLift, key: "face.slider.noseLift")
            // Ala (nostril wings) maps to EditorCore noseAla — NOT to the
            // legacy noseWidth field (that was the pre-migration mistake).
            slider(face: \.noseAla, key: "face.slider.noseAla")
            slider(face: \.noseRoot, key: "face.slider.noseRoot")
            slider(face: \.noseBridge, key: "face.slider.noseBridge")
            slider(face: \.noseTip, key: "face.slider.noseTip")
        }
    }

    private var lipSliders: some View {
        VStack(spacing: 12) {
            slider(face: \.lipSize, key: "face.slider.lipSize")
            slider(face: \.lipWidth, key: "face.slider.lipWidth")
            slider(face: \.lipThickness, key: "face.slider.lipThickness")
            slider(face: \.lipSmile, key: "face.slider.lipSmile")
            slider(face: \.lipPosition, key: "face.slider.lipPosition")
            slider(face: \.lipMShape, key: "face.slider.lipShape")
        }
    }

    // MARK: - Slider bindings

    private func slider(face keyPath: WritableKeyPath<FaceAdjustments, Float>, key: String) -> some View {
        BipolarSlider(
            value: Binding(
                get: { viewModel.state.primaryFace[keyPath: keyPath] },
                set: { newValue in
                    viewModel.updateFace { face in face[keyPath: keyPath] = newValue }
                }
            ),
            titleKey: key,
            onBegin: { viewModel.beginChange() },
            onEnd: { viewModel.endChange() }
        )
        .disabled(viewModel.hasFace == false)
    }

    /// One-way 0...100 slider for a 0...1 pose attenuation factor.
    private func attenuationSlider(face keyPath: WritableKeyPath<FaceAdjustments, Float>, key: String) -> some View {
        BipolarSlider(
            value: Binding(
                get: { viewModel.state.primaryFace[keyPath: keyPath] * 100 },
                set: { newValue in
                    viewModel.updateFace { face in face[keyPath: keyPath] = newValue / 100 }
                }
            ),
            range: 0...100,
            isBipolar: false,
            titleKey: key,
            onBegin: { viewModel.beginChange() },
            onEnd: { viewModel.endChange() }
        )
        .disabled(viewModel.hasFace == false)
    }
}
