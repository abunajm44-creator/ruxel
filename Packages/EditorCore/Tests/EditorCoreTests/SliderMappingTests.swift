// What: Tests slider mapping boundaries, limits, and out-of-range clamping.
// Inputs/Outputs: Slider values + tools in; physical amounts out.
// Threading: XCTest, single thread.
import XCTest
@testable import EditorCore

final class SliderMappingTests: XCTestCase {

    func testBoundariesEyeSize() {
        XCTAssertEqual(mappedAmount(slider: -100, tool: .eyeSize), -0.25, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: 0, tool: .eyeSize), 0, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: 100, tool: .eyeSize), 0.25, accuracy: 0.0001)
    }

    func testBoundariesNoseSize() {
        XCTAssertEqual(mappedAmount(slider: 100, tool: .noseSize), 0.3, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: -100, tool: .noseSize), -0.3, accuracy: 0.0001)
    }

    func testBoundariesFaceWidth() {
        XCTAssertEqual(mappedAmount(slider: 100, tool: .faceWidth), 0.35, accuracy: 0.0001)
    }

    func testBoundariesSkinSmoothing() {
        XCTAssertEqual(mappedAmount(slider: 100, tool: .skinSmoothing), 0.8, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: 0, tool: .skinSmoothing), 0, accuracy: 0.0001)
        // One-way tool: negative sliders clamp to zero, never negative.
        XCTAssertEqual(mappedAmount(slider: -100, tool: .skinSmoothing), 0, accuracy: 0.0001)
    }

    func testMidpointIsHalfMax() {
        XCTAssertEqual(mappedAmount(slider: 50, tool: .eyeSize), 0.125, accuracy: 0.0001)
    }

    func testOutOfRangeClamps() {
        XCTAssertEqual(mappedAmount(slider: 200, tool: .eyeSize), 0.25, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: -200, tool: .eyeSize), -0.25, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: 1000, tool: .skinSmoothing), 0.8, accuracy: 0.0001)
        XCTAssertEqual(mappedAmount(slider: -1000, tool: .skinSmoothing), 0, accuracy: 0.0001)
    }

    func testClampSlider() {
        XCTAssertEqual(clampSlider(150), 100, accuracy: 0.0001)
        XCTAssertEqual(clampSlider(-150), -100, accuracy: 0.0001)
        XCTAssertEqual(clampSlider(42), 42, accuracy: 0.0001)
    }

    func testRadiiArePositiveForWarpTools() {
        XCTAssertGreaterThan(warpRadius(for: .eyeSize), 0)
        XCTAssertGreaterThan(warpRadius(for: .faceWidth), 0)
        XCTAssertGreaterThan(warpRadius(for: .bodySlim), 0)
    }
}
