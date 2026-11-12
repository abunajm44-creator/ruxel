// What: Tests the CPU reference warp and skin-smooth blend against known values.
// Inputs/Outputs: Float buffers in; warped/blended buffers asserted out.
// Threading: XCTest, single thread.
import XCTest
@testable import EditorCore

final class CPUReferenceTests: XCTestCase {

    func testWarpIdentityEqualsInput() {
        let src: [Float] = [0, 1, 2, 3, 4, 5, 6, 7, 8]
        let zeros = [Vec2](repeating: .zero, count: src.count)
        XCTAssertEqual(warpImageFloat(src: src, width: 3, height: 3, displacement: zeros), src)
    }

    func testWarpShiftByOnePixel() {
        // Displacement +1 in x samples the pixel to the right (clamped at edge).
        let src: [Float] = [10, 20, 30, 40, 50, 60]
        let shift = [Vec2](repeating: Vec2(1, 0), count: src.count)
        let out = warpImageFloat(src: src, width: 3, height: 2, displacement: shift)
        XCTAssertEqual(out, [20, 30, 30, 50, 60, 60])
    }

    func testBilinearSampleHalfPixel() {
        let src: [Float] = [0, 10, 20, 30]
        XCTAssertEqual(bilinearSample(src: src, width: 2, height: 2, x: 0.5, y: 0), 5, accuracy: 0.0001)
        XCTAssertEqual(bilinearSample(src: src, width: 2, height: 2, x: 0, y: 0.5), 10, accuracy: 0.0001)
        XCTAssertEqual(bilinearSample(src: src, width: 2, height: 2, x: 0.5, y: 0.5), 15, accuracy: 0.0001)
    }

    func testBilinearSampleClampsEdges() {
        let src: [Float] = [7, 8, 9, 10]
        XCTAssertEqual(bilinearSample(src: src, width: 2, height: 2, x: -5, y: -5), 7, accuracy: 0.0001)
        XCTAssertEqual(bilinearSample(src: src, width: 2, height: 2, x: 99, y: 99), 10, accuracy: 0.0001)
    }

    func testSkinStrengthZeroEqualsInput() {
        let src: [Float] = [0.1, 0.5, 0.9]
        let low: [Float] = [0.4, 0.4, 0.4]
        let mask: [Float] = [1, 1, 1]
        XCTAssertEqual(skinSmoothBlendCPU(src: src, low: low, skinMask: mask, strength: 0, textureKeep: 0.5), src)
    }

    func testSkinStrengthOneMaskOneEqualsSmoothed() {
        let src: [Float] = [0.1, 0.5, 0.9]
        let low: [Float] = [0.4, 0.4, 0.4]
        let mask: [Float] = [1, 1, 1]
        let textureKeep: Float = 0.5
        let expected = src.enumerated().map { index, value in
            low[index] + (value - low[index]) * textureKeep
        }
        let out = skinSmoothBlendCPU(src: src, low: low, skinMask: mask, strength: 1, textureKeep: textureKeep)
        for (got, want) in zip(out, expected) {
            XCTAssertEqual(got, want, accuracy: 0.0001)
        }
    }

    func testSkinMaskZeroEqualsInput() {
        let src: [Float] = [0.1, 0.5, 0.9]
        let low: [Float] = [0.4, 0.4, 0.4]
        let mask: [Float] = [0, 0, 0]
        XCTAssertEqual(skinSmoothBlendCPU(src: src, low: low, skinMask: mask, strength: 1, textureKeep: 0.5), src)
    }

    func testSkinHalfStrengthHalfBlend() {
        let src: [Float] = [1.0]
        let low: [Float] = [0.0]
        let mask: [Float] = [1.0]
        // smoothed = 0 + (1 - 0) * 0 = 0; out = mix(1, 0, 0.5) = 0.5
        let out = skinSmoothBlendCPU(src: src, low: low, skinMask: mask, strength: 0.5, textureKeep: 0)
        XCTAssertEqual(out, [0.5])
    }
}
