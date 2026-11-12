import SwiftUI

// AdaptiveGlass — Liquid Glass on iOS 26+, ultraThinMaterial fallback below.
// What: one modifier for every floating control so glass never leaks onto content.
// Inputs-outputs: View + shape + optional tint/interactive -> glassed View.
// Threading: SwiftUI view code; runs on the main actor.
extension View {
    @ViewBuilder
    func adaptiveGlass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(Self.makeGlass(tint: tint, interactive: interactive), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.15), lineWidth: 0.5))
        }
    }

    @available(iOS 26.0, *)
    private static func makeGlass(tint: Color?, interactive: Bool) -> Glass {
        // VERIFY: Glass.regular, Glass.tint(_:) and Glass.interactive() names
        // in the iOS 26 SDK; gated by #available with the material fallback above.
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}
