import SwiftUI
import EditorCore

// BipolarSlider — custom slider with magnetic center, haptic tick, numeric bubble.
// What: drag on a track; near-zero snaps to 0 with a selection haptic.
// Inputs-outputs: Binding<Float> in `range`; sliders stay LTR in Arabic UI.
// Threading: SwiftUI view code; runs on the main actor.
struct BipolarSlider: View {
    @Binding var value: Float
    var range: ClosedRange<Float> = -100...100
    var isBipolar: Bool = true
    var titleKey: String
    /// Called once when a drag starts / ends (view model snapshots for undo).
    var onBegin: (() -> Void)?
    var onEnd: (() -> Void)?

    @State private var isDragging = false
    @State private var lastTickedAtZero = false

    private var isCentered: Bool { abs(value) < 0.5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(titleKey)
                    .font(.subheadline)
                Spacer()
                Text("\(Int(value))")
                    .font(.subheadline.monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .adaptiveGlass(in: Capsule())
                    .opacity(isDragging ? 1 : 0.85)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(height: 6)
                    if isBipolar {
                        // Center detent line.
                        Rectangle()
                            .fill(Color.secondary.opacity(0.6))
                            .frame(width: 2, height: 18)
                            .offset(x: geometry.size.width / 2 - 1)
                    }
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(filledWidth(in: geometry.size.width), 0), height: 6)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 28, height: 28)
                        .shadow(radius: 2)
                        .offset(x: thumbOffset(in: geometry.size.width) - 14)
                }
                .frame(height: 28)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            if isDragging == false {
                                isDragging = true
                                onBegin?()
                            }
                            setValue(from: drag.location.x, width: geometry.size.width)
                        }
                        .onEnded { _ in
                            isDragging = false
                            onEnd?()
                        }
                )
            }
            .frame(height: 28)
            // 44pt touch target: 8pt of padding above and below the track.
            .padding(.vertical, 8)
        }
        // Sliders stay left-to-right even in the Arabic (RTL) UI.
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityLabel(Text(titleKey))
        .accessibilityValue(Text("\(Int(value))"))
    }

    private func fraction() -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat((value - range.lowerBound) / span)
    }

    private func filledWidth(in width: CGFloat) -> CGFloat {
        width * fraction()
    }

    private func thumbOffset(in width: CGFloat) -> CGFloat {
        width * fraction()
    }

    private func setValue(from x: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let clampedX = min(max(x, 0), width)
        let fractionValue = Float(clampedX / width)
        var newValue = range.lowerBound + fractionValue * (range.upperBound - range.lowerBound)
        if isBipolar {
            // Magnetic center: snap near-zero values to exactly 0.
            newValue = clampSlider(newValue)
            newValue = abs(newValue) <= 3 ? 0 : newValue
            let atZero = newValue == 0
            if atZero && lastTickedAtZero == false {
                UISelectionFeedbackGenerator().selectionChanged()
            }
            lastTickedAtZero = atZero
        }
        value = newValue
    }
}
