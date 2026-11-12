// What: Tests the brush engine: Catmull-Rom smoothing, dab spacing,
// dab expansion, push/restore stamping, and the dab-spacing rule.
// Inputs/Outputs: Strokes / fields in; dabs / stamped fields out.
// Threading: XCTest, single thread.
import XCTest
@testable import EditorCore

final class BrushEngineTests: XCTestCase {

    func testDabSpacingIsTwentyFivePercentOfDiameter() {
        XCTAssertEqual(dabSpacing(diameter: 0.1), 0.025, accuracy: 0.0001)
        XCTAssertEqual(dabSpacing(diameter: 0.05), 0.0125, accuracy: 0.0001)
    }

    func testCatmullRomPreservesEndpoints() {
        let points = [Vec2(0, 0), Vec2(0.3, 0.2), Vec2(0.6, 0.1), Vec2(1, 0.5)]
        let smoothed = catmullRomSmoothedPoints(points)
        XCTAssertEqual(smoothed.first, points.first)
        XCTAssertEqual(smoothed.last, points.last)
        XCTAssertGreaterThan(smoothed.count, points.count)
    }

    func testCatmullRomKeepsCollinearPointsOnLine() {
        let points = [Vec2(0, 0), Vec2(0.5, 0.5), Vec2(1, 1)]
        let smoothed = catmullRomSmoothedPoints(points)
        for point in smoothed {
            XCTAssertEqual(point.x, point.y, accuracy: 0.0001)
        }
    }

    func testCatmullRomShortInputUnchanged() {
        let points = [Vec2(0, 0), Vec2(1, 1)]
        XCTAssertEqual(catmullRomSmoothedPoints(points), points)
    }

    func testDabCentersFollowSpacing() {
        let points = [Vec2(0, 0.5), Vec2(1, 0.5)]
        let centers = dabCenters(points: points, spacing: 0.2)
        XCTAssertEqual(centers.count, 6)
        for index in 1..<centers.count {
            XCTAssertEqual(centers[index].x - centers[index - 1].x, 0.2, accuracy: 0.001)
        }
    }

    func testDabCentersEmptyInput() {
        XCTAssertTrue(dabCenters(points: [], spacing: 0.2).isEmpty)
    }

    func testBrushDabsRadiusAndDirection() {
        let stroke = BrushStroke(
            points: [Vec2(0.2, 0.5), Vec2(0.8, 0.5)],
            size: 0.1, mode: .classic, strength: 1
        )
        let dabs = brushDabs(from: stroke)
        XCTAssertFalse(dabs.isEmpty)
        for dab in dabs {
            XCTAssertEqual(dab.radius, 0.05, accuracy: 0.0001)
            XCTAssertEqual(dab.direction.length, 1, accuracy: 0.001)
            XCTAssertEqual(dab.direction, Vec2(1, 0))
        }
        // Stroke length 0.6 at spacing 0.02 -> about 31 dabs.
        XCTAssertGreaterThan(dabs.count, 20)
    }

    func testFastModeUsesLargerRadius() {
        let classic = BrushStroke(points: [Vec2(0.2, 0.5), Vec2(0.8, 0.5)], size: 0.1, mode: .classic)
        let fast = BrushStroke(points: [Vec2(0.2, 0.5), Vec2(0.8, 0.5)], size: 0.1, mode: .fast)
        XCTAssertEqual(brushDabs(from: fast).first?.radius ?? 0, 0.075, accuracy: 0.0001)
        XCTAssertEqual(brushDabs(from: classic).first?.radius ?? 0, 0.05, accuracy: 0.0001)
    }

    func testPushDabMovesPixelsAlongDirection() {
        // A push dab dragged RIGHT must render content to the RIGHT.
        // The field is the backward map (negated drag direction), so the
        // test renders a bright block through the stamped field and
        // checks the centroid moved right, not the field sign.
        let size = 101
        var field = [Vec2](repeating: .zero, count: size * size)
        let dab = BrushDab(center: Vec2(0.5, 0.5), direction: Vec2(1, 0), radius: 0.2, strength: 1, mode: .classic)
        stampPushDab(field: &field, width: size, height: size, dab: dab)
        var src = [Float](repeating: 0, count: size * size)
        for dy in -1...1 {
            for dx in -1...1 {
                src[(50 + dy) * size + (50 + dx)] = 1
            }
        }
        let pixelField = field.map { Vec2($0.x * Float(size), $0.y * Float(size)) }
        let out = warpImageFloatCubic(src: src, width: size, height: size, displacement: pixelField)
        var sx: Float = 0, total: Float = 0
        for y in 0..<size {
            for x in 0..<size {
                let v = out[y * size + x]
                guard v > 0 else { continue }
                sx += Float(x) * v
                total += v
            }
        }
        let centroidX = sx / total
        XCTAssertGreaterThan(centroidX, 51.5)
    }

    func testPushDabFieldIsNegatedDragDirection() {
        // The stamped field points OPPOSITE to the drag (backward map).
        var field = [Vec2](repeating: .zero, count: 20 * 20)
        let dab = BrushDab(center: Vec2(0.5, 0.5), direction: Vec2(1, 0), radius: 0.2, strength: 1, mode: .classic)
        stampPushDab(field: &field, width: 20, height: 20, dab: dab)
        // Center pixel (10, 10) sits ~0.025 from the dab center; falloff ~0.9,
        // so displacement ~= -0.9 * radius * gain = -0.027.
        let center = field[10 * 20 + 10]
        XCTAssertLessThan(center.x, -0.02)
        XCTAssertEqual(center.y, 0, accuracy: 0.0001)
        // A far corner is untouched.
        XCTAssertEqual(field[0], Vec2.zero)
    }

    func testRestoreDabErasesTowardZero() {
        var field = [Vec2](repeating: Vec2(0.1, 0), count: 20 * 20)
        let dab = BrushDab(center: Vec2(0.5, 0.5), direction: Vec2(1, 0), radius: 0.2, strength: 1, mode: .restore)
        stampRestoreDab(field: &field, width: 20, height: 20, dab: dab)
        // Center is erased almost fully; far corner keeps its displacement.
        XCTAssertLessThan(field[10 * 20 + 10].x, 0.01)
        XCTAssertEqual(field[0], Vec2(0.1, 0))
    }

    func testStrokeRoundTripThroughDabs() {
        // A stroke stamped into a field, then restored by the same path
        // in restore mode, leaves the field (nearly) zero again.
        var field = [Vec2](repeating: .zero, count: 40 * 40)
        let push = BrushStroke(points: [Vec2(0.3, 0.5), Vec2(0.7, 0.5)], size: 0.1, mode: .classic)
        for dab in brushDabs(from: push) {
            stampDab(field: &field, width: 40, height: 40, dab: dab)
        }
        XCTAssertTrue(field.contains { $0.length > 0 })
        let erase = BrushStroke(points: [Vec2(0.3, 0.5), Vec2(0.7, 0.5)], size: 0.1, mode: .restore)
        for dab in brushDabs(from: erase) {
            stampDab(field: &field, width: 40, height: 40, dab: dab)
        }
        XCTAssertTrue(field.allSatisfy { $0.length < 0.01 })
    }
}
