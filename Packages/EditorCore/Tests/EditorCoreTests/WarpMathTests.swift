// What: Tests falloff, scale/translate/pinch signs, zero sliders, and no fold-over.
// Inputs/Outputs: Warp ops in; displacement and Jacobian determinant assertions out.
// Threading: XCTest, single thread.
import XCTest
@testable import EditorCore

final class WarpMathTests: XCTestCase {

    func testFalloffAtCenterIsOne() {
        XCTAssertEqual(falloff(distance: 0, radius: 1), 1, accuracy: 0.0001)
    }

    func testFalloffAtEdgeIsZero() {
        XCTAssertEqual(falloff(distance: 1, radius: 1), 0, accuracy: 0.0001)
        XCTAssertEqual(falloff(distance: 2, radius: 1), 0, accuracy: 0.0001)
    }

    func testFalloffAtHalfRadiusIsHalf() {
        XCTAssertEqual(falloff(distance: 0.5, radius: 1), 0.5, accuracy: 0.0001)
    }

    func testFalloffWithZeroRadiusIsZero() {
        XCTAssertEqual(falloff(distance: 0, radius: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(falloff(distance: 0.5, radius: -1), 0, accuracy: 0.0001)
    }

    func testZeroSlidersGiveZeroDisplacement() {
        let center = Vec2(0.5, 0.5)
        let point = Vec2(0.6, 0.55)
        XCTAssertEqual(scaleDisplacement(at: point, center: center, radius: 0.4, amount: 0), Vec2.zero)
        XCTAssertEqual(pinchDisplacement(at: point, center: center, radius: 0.4, amount: 0), Vec2.zero)
        XCTAssertEqual(
            translateDisplacement(at: point, center: center, radius: 0.4, amount: 0),
            Vec2.zero
        )
        let ops = [
            WarpOp(type: .scale, center: center, radius: 0.4, amount: mappedAmount(slider: 0, tool: .eyeSize)),
            WarpOp(type: .pinch, center: center, radius: 0.4, amount: mappedAmount(slider: 0, tool: .noseSize))
        ]
        XCTAssertEqual(summedDisplacement(at: point, ops: ops), Vec2.zero)
    }

    func testScaleEnlargePullsTowardCenter() {
        let center = Vec2(0.5, 0.5)
        let right = Vec2(0.6, 0.5)
        let enlarge = scaleDisplacement(at: right, center: center, radius: 0.4, amount: 0.25)
        XCTAssertLessThan(enlarge.x, 0)
        XCTAssertEqual(enlarge.y, 0, accuracy: 0.0001)
    }

    func testScaleShrinkPushesAwayFromCenter() {
        let center = Vec2(0.5, 0.5)
        let right = Vec2(0.6, 0.5)
        let shrink = scaleDisplacement(at: right, center: center, radius: 0.4, amount: -0.25)
        XCTAssertGreaterThan(shrink.x, 0)
    }

    func testScaleAtCenterIsZero() {
        let center = Vec2(0.5, 0.5)
        XCTAssertEqual(scaleDisplacement(at: center, center: center, radius: 0.4, amount: 0.5), Vec2.zero)
    }

    func testTranslateMovesAlongDirection() {
        let center = Vec2(0.5, 0.5)
        let at = Vec2(0.5, 0.5)
        let moved = translateDisplacement(at: at, center: center, radius: 0.4, amount: 0.1, direction: Vec2(0, 1))
        XCTAssertEqual(moved.x, 0, accuracy: 0.0001)
        XCTAssertEqual(moved.y, 0.1, accuracy: 0.0001)
    }

    func testPinchPullsTowardCenter() {
        let center = Vec2(0.5, 0.5)
        let right = Vec2(0.7, 0.5)
        let pinched = pinchDisplacement(at: right, center: center, radius: 0.4, amount: 0.1)
        XCTAssertLessThan(pinched.x, 0)
        XCTAssertEqual(pinched.y, 0, accuracy: 0.0001)
    }

    func testAxesMasking() {
        let center = Vec2(0.5, 0.5)
        let point = Vec2(0.6, 0.6)
        let horizontal = WarpOp(type: .scale, center: center, radius: 0.4, amount: 0.25, axes: .horizontal)
        let result = displacement(of: horizontal, at: point)
        XCTAssertNotEqual(result.x, 0)
        XCTAssertEqual(result.y, 0, accuracy: 0.0001)
        let vertical = WarpOp(type: .scale, center: center, radius: 0.4, amount: 0.25, axes: .vertical)
        XCTAssertEqual(displacement(of: vertical, at: point).x, 0, accuracy: 0.0001)
    }

    func testNoFoldOverAtMaxSliderAmounts() {
        // Dense 41x41 grid over normalized [0,1]x[0,1], with every
        // face/body tool at its max slider amount, all at once.
        let size = 41
        let center = Vec2(0.5, 0.5)
        let ops = [
            WarpOp(type: .scale, center: Vec2(0.4, 0.45), radius: 0.4, amount: mappedAmount(slider: 100, tool: .eyeSize)),
            WarpOp(type: .scale, center: Vec2(0.6, 0.45), radius: 0.4, amount: mappedAmount(slider: 100, tool: .eyeSize)),
            WarpOp(type: .scale, center: center, radius: 0.4, amount: mappedAmount(slider: 100, tool: .noseSize)),
            WarpOp(type: .scale, center: center, radius: 0.6, amount: mappedAmount(slider: 100, tool: .faceWidth)),
            WarpOp(type: .pinch, center: Vec2(0.5, 0.7), radius: 0.4, amount: mappedAmount(slider: 100, tool: .jawSize)),
            WarpOp(type: .scale, center: Vec2(0.5, 0.3), radius: 0.5, amount: mappedAmount(slider: -100, tool: .faceWidth))
        ]
        var displacement: [Vec2] = []
        displacement.reserveCapacity(size * size)
        for y in 0..<size {
            for x in 0..<size {
                let p = Vec2(Float(x) / Float(size - 1), Float(y) / Float(size - 1))
                // Convert normalized displacement to grid-cell units so
                // the Jacobian is per normalized unit, not per cell.
                let d = summedDisplacement(at: p, ops: ops) * Float(size - 1)
                displacement.append(d)
            }
        }
        let minimum = displacementJacobianDeterminant(grid: (width: size, height: size), displacement: displacement)
        XCTAssertGreaterThan(minimum, 0.05, "Jacobian determinant folded over: \(minimum)")
    }

    func testJacobianOfIdentityIsOne() {
        let size = 5
        let zeros = [Vec2](repeating: .zero, count: size * size)
        let det = displacementJacobianDeterminant(grid: (width: size, height: size), displacement: zeros)
        XCTAssertEqual(det, 1, accuracy: 0.0001)
    }

    func testNoFoldOverFullMaxSliderSet() {
        // The whole engine at once: every face slider at +100, every body
        // slider at +100, plus a push brush stroke across the face — the
        // worst case the caps must survive. The caps in SliderMapping were
        // tuned until this stayed above 0.05.
        let size = 41
        let face = makeFullFace(value: 100)
        var body = BodyAdjustments()
        body.slim = 100
        body.waist = 100
        body.hips = 100
        body.legLength = 100
        body.shoulders = 100
        body.neck = 100
        var ops = faceWarpOps(face: face, landmarks: makeSyntheticLandmarks())
        ops.append(contentsOf: bodyWarpOps(body: body, pose: makeSyntheticPose()))
        if let distortion = distortionWarpOp(strength: 100) {
            ops.append(distortion)
        }
        let stroke = BrushStroke(
            points: [Vec2(0.3, 0.5), Vec2(0.7, 0.5)],
            size: 0.1, mode: .classic, strength: 1
        )
        let dabs = brushDabs(from: stroke)
        let field = displacementFieldGrid(cols: size, rows: size, ops: ops, dabs: dabs)
        // Convert normalized displacement to grid-cell units so the
        // Jacobian is per normalized unit, not per cell.
        let scaled = field.map { $0 * Float(size - 1) }
        let minimum = displacementJacobianDeterminant(grid: (width: size, height: size), displacement: scaled)
        XCTAssertGreaterThan(minimum, 0.05, "Jacobian determinant folded over: \(minimum)")
    }

    func testNoFoldOverFullMaxSliderSetNegative() {
        // Same worst case with every slider at -100.
        let size = 41
        let face = makeFullFace(value: -100)
        var body = BodyAdjustments()
        body.slim = -100
        body.waist = -100
        body.hips = -100
        body.legLength = -100
        body.shoulders = -100
        body.neck = -100
        var ops = faceWarpOps(face: face, landmarks: makeSyntheticLandmarks())
        ops.append(contentsOf: bodyWarpOps(body: body, pose: makeSyntheticPose()))
        let field = displacementFieldGrid(cols: size, rows: size, ops: ops, dabs: [])
        let scaled = field.map { $0 * Float(size - 1) }
        let minimum = displacementJacobianDeterminant(grid: (width: size, height: size), displacement: scaled)
        XCTAssertGreaterThan(minimum, 0.05, "Jacobian determinant folded over: \(minimum)")
    }

    func testFarSideAttenuationFactor() {
        XCTAssertEqual(farSideAttenuationFactor(poseAngle: 0, attenuation: 1), 1, accuracy: 0.0001)
        XCTAssertEqual(farSideAttenuationFactor(poseAngle: Float.pi / 4, attenuation: 0), 1, accuracy: 0.0001)
        XCTAssertEqual(farSideAttenuationFactor(poseAngle: Float.pi / 4, attenuation: 1), 0, accuracy: 0.0001)
        XCTAssertEqual(farSideAttenuationFactor(poseAngle: Float.pi / 8, attenuation: 1), 0.5, accuracy: 0.0001)
        XCTAssertEqual(farSideAttenuationFactor(poseAngle: -Float.pi / 4, attenuation: 1), 0, accuracy: 0.0001)
    }

    func testBackgroundLockMultipliesByMask() {
        let field = [Vec2(0.1, 0.2), Vec2(0.3, 0.4)]
        XCTAssertEqual(
            applyBackgroundLock(field: field, mask: [1, 0]),
            [Vec2(0.1, 0.2), Vec2.zero]
        )
        XCTAssertEqual(applyBackgroundLock(field: field, mask: [0.5, 0.5]), [Vec2(0.05, 0.1), Vec2(0.15, 0.2)])
        XCTAssertEqual(applyBackgroundLock(field: field, mask: [1]), field)
    }

    func testMaxDisplacementMagnitude() {
        let ops = [
            WarpOp(type: .scale, center: Vec2(0.5, 0.5), radius: 0.4, amount: 0.25),
            WarpOp(type: .translate, center: Vec2(0.5, 0.5), radius: 0.4, amount: 0.1)
        ]
        XCTAssertEqual(maxDisplacementMagnitude(ops: ops), 0.1, accuracy: 0.0001)
        XCTAssertEqual(maxDisplacementMagnitude(ops: []), 0, accuracy: 0.0001)
    }

    func testDisplacementFieldGridZeroIsZero() {
        let field = displacementFieldGrid(cols: 5, rows: 5, ops: [], dabs: [])
        XCTAssertTrue(field.allSatisfy { $0 == Vec2.zero })
    }

    func testTileFieldMatchesFullFieldCrop() {
        // A tile's field must equal the corresponding crop of the
        // full-image field, for ops and dabs alike. Both use the
        // pixel-center convention (unlike the debug grid's node
        // sampling), so build the reference field the same way.
        let ops = [
            WarpOp(type: .scale, center: Vec2(0.5, 0.5), radius: 0.4, amount: 0.25),
            WarpOp(type: .translate, center: Vec2(0.3, 0.3), radius: 0.3, amount: 0.1, direction: Vec2(1, 0))
        ]
        let dabs = [BrushDab(center: Vec2(0.6, 0.6), direction: Vec2(0, 1), radius: 0.2, strength: 1, mode: .classic)]
        let size = 10
        var full = [Vec2](repeating: .zero, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                let p = Vec2((Float(x) + 0.5) / Float(size), (Float(y) + 0.5) / Float(size))
                full[y * size + x] = summedDisplacement(at: p, ops: ops)
            }
        }
        for dab in dabs {
            stampDab(field: &full, width: size, height: size, dab: dab)
        }
        let tile = tileDisplacementField(
            tileOriginX: 2, tileOriginY: 3, tileWidth: 4, tileHeight: 4,
            imageWidth: size, imageHeight: size, ops: ops, dabs: dabs)
        for y in 0..<4 {
            for x in 0..<4 {
                XCTAssertEqual(tile[y * 4 + x], full[(y + 3) * size + (x + 2)])
            }
        }
    }

    func testTileFieldEmptyIsZero() {
        let tile = tileDisplacementField(
            tileOriginX: 0, tileOriginY: 0, tileWidth: 4, tileHeight: 4,
            imageWidth: 8, imageHeight: 8, ops: [], dabs: [])
        XCTAssertTrue(tile.allSatisfy { $0 == Vec2.zero })
    }
}
