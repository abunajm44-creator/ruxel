// What: Tests sRGB/Lab round-trips, black/white, and skin likelihood.
// Inputs/Outputs: Colors in; converted colors and likelihoods out.
// Threading: XCTest, single thread.
import XCTest
@testable import EditorCore

final class ColorMathTests: XCTestCase {

    func testRoundTripSrgbLabSrgb() {
        let colors: [RGBColor] = [
            RGBColor(r: 1, g: 0, b: 0),
            RGBColor(r: 0, g: 1, b: 0),
            RGBColor(r: 0, g: 0, b: 1),
            RGBColor(r: 0.8, g: 0.6, b: 0.5),
            RGBColor(r: 0.2, g: 0.4, b: 0.7),
            RGBColor(r: 0.5, g: 0.5, b: 0.5)
        ]
        for color in colors {
            let back = labToSrgb(srgbToLab(color))
            XCTAssertEqual(back.r, color.r, accuracy: 0.02, "red channel for \(color)")
            XCTAssertEqual(back.g, color.g, accuracy: 0.02, "green channel for \(color)")
            XCTAssertEqual(back.b, color.b, accuracy: 0.02, "blue channel for \(color)")
        }
    }

    func testBlackRoundTrip() {
        let lab = srgbToLab(.black)
        XCTAssertEqual(lab.l, 0, accuracy: 0.01)
        XCTAssertEqual(lab.a, 0, accuracy: 0.01)
        XCTAssertEqual(lab.b, 0, accuracy: 0.01)
        XCTAssertEqual(labToSrgb(lab), .black)
    }

    func testWhiteRoundTrip() {
        let lab = srgbToLab(.white)
        XCTAssertEqual(lab.l, 100, accuracy: 0.5)
        XCTAssertEqual(lab.a, 0, accuracy: 0.5)
        XCTAssertEqual(lab.b, 0, accuracy: 0.5)
        let back = labToSrgb(lab)
        XCTAssertEqual(back.r, 1, accuracy: 0.01)
        XCTAssertEqual(back.g, 1, accuracy: 0.01)
        XCTAssertEqual(back.b, 1, accuracy: 0.01)
    }

    func testSrgbLinearRoundTrip() {
        for value: Float in [0, 0.1, 0.25, 0.5, 0.75, 1.0] {
            XCTAssertEqual(linearToSrgb(srgbToLinear(value)), value, accuracy: 0.001)
        }
    }

    func testLuminanceBlackWhite() {
        XCTAssertEqual(luminance(.black), 0, accuracy: 0.001)
        XCTAssertEqual(luminance(.white), 1, accuracy: 0.001)
        XCTAssertGreaterThan(luminance(RGBColor(r: 1, g: 1, b: 1)), luminance(RGBColor(r: 0, g: 0, b: 1)))
    }

    func testSkinLikelihoodSkinToneHigh() {
        // A typical light skin tone.
        let skin = RGBColor(r: 0.85, g: 0.65, b: 0.5)
        XCTAssertGreaterThan(skinLikelihood(rgb: skin), 0.3)
    }

    func testSkinLikelihoodBlueLow() {
        let blue = RGBColor(r: 0, g: 0, b: 1)
        XCTAssertEqual(skinLikelihood(rgb: blue), 0, accuracy: 0.001)
        XCTAssertEqual(skinLikelihood(rgb: .black), 0, accuracy: 0.001)
    }
}
