// What: Tests faceWarpOps: zero face -> no ops, scope filtering,
// yaw attenuation, op count cap, and the IPD guard.
// Inputs/Outputs: FaceAdjustments + synthetic landmarks in; WarpOps out.
// Threading: XCTest, single thread.
import XCTest
@testable import EditorCore

/// Plausible synthetic face (normalized, y down): IPD 0.16, pupils at
/// y 0.40, nose tip (0.50, 0.55), lips around (0.50, 0.63), contour
/// ellipse around (0.50, 0.50). Shared by the warp-op and Jacobian tests.
func makeSyntheticLandmarks() -> FaceLandmarks {
    var contour: [Vec2] = []
    for i in 0..<16 {
        let angle = Float(i) * 2 * Float.pi / 16
        contour.append(Vec2(0.50 + 0.16 * cos(angle), 0.52 + 0.24 * sin(angle)))
    }
    return FaceLandmarks(
        contour: contour,
        leftEye: [Vec2(0.39, 0.40), Vec2(0.42, 0.38), Vec2(0.45, 0.40), Vec2(0.42, 0.42)],
        rightEye: [Vec2(0.55, 0.40), Vec2(0.58, 0.38), Vec2(0.61, 0.40), Vec2(0.58, 0.42)],
        leftBrow: [Vec2(0.38, 0.34), Vec2(0.42, 0.33), Vec2(0.46, 0.34)],
        rightBrow: [Vec2(0.54, 0.34), Vec2(0.58, 0.33), Vec2(0.62, 0.34)],
        nose: [Vec2(0.49, 0.45), Vec2(0.51, 0.45), Vec2(0.50, 0.52), Vec2(0.48, 0.55), Vec2(0.52, 0.55)],
        noseCrest: [Vec2(0.50, 0.42), Vec2(0.50, 0.47), Vec2(0.50, 0.52)],
        medianLine: [Vec2(0.50, 0.35), Vec2(0.50, 0.50), Vec2(0.50, 0.62)],
        outerLips: [Vec2(0.46, 0.63), Vec2(0.48, 0.61), Vec2(0.50, 0.61), Vec2(0.52, 0.61),
                    Vec2(0.54, 0.63), Vec2(0.52, 0.65), Vec2(0.50, 0.65), Vec2(0.48, 0.65)],
        innerLips: [Vec2(0.48, 0.63), Vec2(0.50, 0.62), Vec2(0.52, 0.63), Vec2(0.50, 0.64)],
        leftPupil: Vec2(0.42, 0.40),
        rightPupil: Vec2(0.58, 0.40)
    )
}

/// Face with every slider set to `value` (including legacy noseWidth).
func makeFullFace(value: Float) -> FaceAdjustments {
    var face = FaceAdjustments()
    face.eyeSize = value
    face.eyeHeight = value
    face.eyeWidth = value
    face.eyeLength = value
    face.eyeSpacing = value
    face.eyePuffy = value
    face.eyeAngle = value
    face.eyePosition = value
    face.noseSize = value
    face.noseWidth = value
    face.noseLift = value
    face.noseAla = value
    face.noseRoot = value
    face.noseBridge = value
    face.noseTip = value
    face.lipSize = value
    face.lipWidth = value
    face.lipThickness = value
    face.lipSmile = value
    face.lipPosition = value
    face.lipMShape = value
    face.browHeight = value
    face.browDistance = value
    face.browThickness = value
    face.browAngle = value
    face.browLength = value
    face.browShape = value
    face.faceWidth = value
    face.jawSize = value
    face.chinLength = value
    face.chinWidth = value
    face.cheekbones = value
    face.temples = value
    face.foreheadHeight = value
    face.faceLength = value
    face.vShape = value
    return face
}

final class FaceWarpOpsTests: XCTestCase {

    func testZeroFaceGivesNoOps() {
        let ops = faceWarpOps(face: FaceAdjustments(), landmarks: makeSyntheticLandmarks())
        XCTAssertTrue(ops.isEmpty)
    }

    func testFullFaceStaysUnderOpCap() {
        let ops = faceWarpOps(face: makeFullFace(value: 100), landmarks: makeSyntheticLandmarks())
        XCTAssertGreaterThan(ops.count, 30)
        XCTAssertLessThanOrEqual(ops.count, 64)
    }

    func testScopeLeftKeepsOnlyLeftEyeOps() {
        var face = FaceAdjustments()
        face.eyeSize = 100
        face.scope = .left
        let ops = faceWarpOps(face: face, landmarks: makeSyntheticLandmarks())
        XCTAssertEqual(ops.count, 1)
        XCTAssertLessThan(ops[0].center.x, 0.5)
    }

    func testScopeRightKeepsOnlyRightEyeOps() {
        var face = FaceAdjustments()
        face.eyeSize = 100
        face.scope = .right
        let ops = faceWarpOps(face: face, landmarks: makeSyntheticLandmarks())
        XCTAssertEqual(ops.count, 1)
        XCTAssertGreaterThan(ops[0].center.x, 0.5)
    }

    func testScopeGeneralKeepsBothEyes() {
        var face = FaceAdjustments()
        face.eyeSize = 100
        let ops = faceWarpOps(face: face, landmarks: makeSyntheticLandmarks())
        XCTAssertEqual(ops.count, 2)
    }

    func testYawAttenuationFreezesFarSide() {
        var face = FaceAdjustments()
        face.eyeSize = 100
        face.yawAttenuation = 1
        var landmarks = makeSyntheticLandmarks()
        landmarks.yaw = Float.pi / 4
        // Positive yaw: left side is far (see farSideAttenuationFactor).
        // Far side frozen -> only the right-eye op survives.
        let ops = faceWarpOps(face: face, landmarks: landmarks)
        XCTAssertEqual(ops.count, 1)
        XCTAssertGreaterThan(ops[0].center.x, 0.5)
    }

    func testZeroYawAttenuationKeepsBothSides() {
        var face = FaceAdjustments()
        face.eyeSize = 100
        face.yawAttenuation = 0
        var landmarks = makeSyntheticLandmarks()
        landmarks.yaw = Float.pi / 4
        let ops = faceWarpOps(face: face, landmarks: landmarks)
        XCTAssertEqual(ops.count, 2)
    }

    func testZeroIPDGivesNoOps() {
        var face = FaceAdjustments()
        face.eyeSize = 100
        let landmarks = FaceLandmarks()
        XCTAssertTrue(faceWarpOps(face: face, landmarks: landmarks).isEmpty)
    }

    func testAnchorsFallBackWithoutRegions() {
        let landmarks = FaceLandmarks(leftPupil: Vec2(0.4, 0.4), rightPupil: Vec2(0.6, 0.4))
        let anchors = landmarks.anchors
        XCTAssertEqual(anchors.eyeAxis, Vec2(1, 0))
        XCTAssertEqual(anchors.noseCenter, landmarks.eyeCenter)
        XCTAssertEqual(anchors.chin, landmarks.eyeCenter)
    }
}
