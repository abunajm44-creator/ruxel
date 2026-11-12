// What: Tests export math: bicubic sampling, the 5-tap blur mirror,
// deterministic grain, face-oval rasterization, and the skin mask.
// Inputs/Outputs: Buffers / contours in; sampled / blurred / masked out.
// Threading: XCTest, single thread.
import XCTest
@testable import EditorCore

final class ExportMathTests: XCTestCase {

    func testBicubicSampleAtIntegerCoordsIsExact() {
        let src: [Float] = [1, 2, 3, 4, 5, 6, 7, 8, 9]
        XCTAssertEqual(bicubicSample(src: src, width: 3, height: 3, x: 1, y: 1), 5, accuracy: 0.0001)
        XCTAssertEqual(bicubicSample(src: src, width: 3, height: 3, x: 0, y: 2), 7, accuracy: 0.0001)
    }

    func testCubicWarpWithZeroDisplacementIsIdentity() {
        let width = 8
        let height = 6
        let src = (0..<(width * height)).map { Float($0) / Float(width * height) }
        let zeros = [Vec2](repeating: .zero, count: width * height)
        XCTAssertEqual(warpImageFloatCubic(src: src, width: width, height: height, displacement: zeros), src)
    }

    func testSeparableBlurKeepsConstantImage() {
        let src = [Float](repeating: 0.7, count: 10 * 10)
        let blurred = separableBlurFloat(src: src, width: 10, height: 10)
        for value in blurred {
            XCTAssertEqual(value, 0.7, accuracy: 0.0001)
        }
    }

    func testSeparableBlurSpreadsImpulse() {
        var src = [Float](repeating: 0, count: 9 * 9)
        src[4 * 9 + 4] = 1
        let blurred = separableBlurFloat(src: src, width: 9, height: 9)
        XCTAssertEqual(blurred[4 * 9 + 4], 0.140625, accuracy: 0.0001)
        XCTAssertGreaterThan(blurred[4 * 9 + 5], 0)
        XCTAssertEqual(blurred[0], 0, accuracy: 0.0001)
    }

    func testGrainNoiseIsDeterministicAndBounded() {
        let first = grainNoise(x: 3, y: 7)
        let second = grainNoise(x: 3, y: 7)
        XCTAssertEqual(first, second)
        XCTAssertGreaterThanOrEqual(first, -1)
        XCTAssertLessThanOrEqual(first, 1)
        XCTAssertNotEqual(first, grainNoise(x: 4, y: 7))
    }

    func testPointInPolygon() {
        let square = [Vec2(0, 0), Vec2(1, 0), Vec2(1, 1), Vec2(0, 1)]
        XCTAssertTrue(pointInPolygon(Vec2(0.5, 0.5), polygon: square))
        XCTAssertFalse(pointInPolygon(Vec2(1.5, 0.5), polygon: square))
        XCTAssertFalse(pointInPolygon(Vec2(0.5, 0.5), polygon: []))
    }

    func testFaceOvalMask() {
        let contour = [Vec2(0.25, 0.25), Vec2(0.75, 0.25), Vec2(0.75, 0.75), Vec2(0.25, 0.75)]
        let mask = faceOvalMask(
            tileWidth: 4, tileHeight: 4, tileOriginX: 0, tileOriginY: 0,
            imageWidth: 4, imageHeight: 4, contour: contour
        )
        XCTAssertEqual(mask.count, 16)
        // Center pixels inside, corners outside.
        XCTAssertEqual(mask[1 * 4 + 1], 1, accuracy: 0.0001)
        XCTAssertEqual(mask[2 * 4 + 2], 1, accuracy: 0.0001)
        XCTAssertEqual(mask[0], 0, accuracy: 0.0001)
        XCTAssertEqual(mask[15], 0, accuracy: 0.0001)
    }

    func testFaceOvalMaskEmptyContourIsZero() {
        let mask = faceOvalMask(
            tileWidth: 2, tileHeight: 2, tileOriginX: 0, tileOriginY: 0,
            imageWidth: 2, imageHeight: 2, contour: []
        )
        XCTAssertEqual(mask, [0, 0, 0, 0])
    }

    func testSkinMaskNeedsPersonMaskAndOval() {
        let count = 4
        let rgb = [Float](repeating: 0.6, count: count)
        let person = [Float](repeating: 1, count: count)
        let oval = [Float](repeating: 1, count: count)
        XCTAssertTrue(skinMask(red: rgb, green: rgb, blue: rgb, width: 2, height: 2, personMask: [Float](repeating: 0, count: count), faceOval: oval).isEmpty)
        XCTAssertTrue(skinMask(red: rgb, green: rgb, blue: rgb, width: 2, height: 2, personMask: person, faceOval: [Float](repeating: 0, count: count)).isEmpty)
    }

    func testSkinMaskDetectsSkinColor() {
        // Warm skin-like color inside person mask + oval -> mask > 0.
        let count = 4
        let red = [Float](repeating: 0.8, count: count)
        let green = [Float](repeating: 0.6, count: count)
        let blue = [Float](repeating: 0.5, count: count)
        let person = [Float](repeating: 1, count: count)
        let oval = [Float](repeating: 1, count: count)
        let mask = skinMask(red: red, green: green, blue: blue, width: 2, height: 2, personMask: person, faceOval: oval)
        XCTAssertFalse(mask.isEmpty)
        XCTAssertTrue(mask.allSatisfy { $0 > 0 })
        // Pure blue is not skin -> mask stays 0.
        let blueOnly = skinMask(
            red: [Float](repeating: 0, count: count),
            green: [Float](repeating: 0, count: count),
            blue: [Float](repeating: 1, count: count),
            width: 2, height: 2, personMask: person, faceOval: oval
        )
        XCTAssertTrue(blueOnly.allSatisfy { $0 == 0 })
    }
}
