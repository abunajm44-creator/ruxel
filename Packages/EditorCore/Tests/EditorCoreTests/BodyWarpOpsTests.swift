// What: Tests bodyWarpOps: capsules from a pose, slim pinch, sculpt ops,
// distortion op, and the missing-pose guard.
// Inputs/Outputs: BodyAdjustments + synthetic pose in; WarpOps out.
// Threading: XCTest, single thread.
import XCTest
@testable import EditorCore

/// Plausible synthetic full-body pose (normalized, y down).
func makeSyntheticPose() -> BodyPose {
    let joints: [(BodyJointName, Vec2)] = [
        (.neck, Vec2(0.50, 0.30)),
        (.leftShoulder, Vec2(0.38, 0.33)), (.rightShoulder, Vec2(0.62, 0.33)),
        (.leftElbow, Vec2(0.32, 0.50)), (.rightElbow, Vec2(0.68, 0.50)),
        (.leftWrist, Vec2(0.28, 0.66)), (.rightWrist, Vec2(0.72, 0.66)),
        (.leftHip, Vec2(0.42, 0.60)), (.rightHip, Vec2(0.58, 0.60)),
        (.leftKnee, Vec2(0.42, 0.78)), (.rightKnee, Vec2(0.58, 0.78)),
        (.leftAnkle, Vec2(0.42, 0.95)), (.rightAnkle, Vec2(0.58, 0.95))
    ]
    return BodyPose(joints: joints.map { BodyJoint(name: $0.0, position: $0.1, confidence: 1) })
}

final class BodyWarpOpsTests: XCTestCase {

    func testCapsulesFromFullPose() {
        let capsules = bodyCapsules(pose: makeSyntheticPose())
        XCTAssertEqual(capsules.count, 9)
        XCTAssertGreaterThan(capsules[0].length, 0)
    }

    func testCapsulesNeedShoulders() {
        XCTAssertTrue(bodyCapsules(pose: BodyPose()).isEmpty)
        let partial = BodyPose(joints: [
            BodyJoint(name: .leftShoulder, position: Vec2(0.4, 0.3), confidence: 1)
        ])
        XCTAssertTrue(bodyCapsules(pose: partial).isEmpty)
    }

    func testLowConfidenceJointsAreSkipped() {
        var pose = makeSyntheticPose()
        pose.joints = pose.joints.map { joint in
            var copy = joint
            if joint.name == .leftWrist || joint.name == .rightWrist { copy.confidence = 0.1 }
            return copy
        }
        // Torso + 6 limbs (both forearms dropped).
        XCTAssertEqual(bodyCapsules(pose: pose).count, 7)
    }

    func testNeutralBodyGivesNoOps() {
        XCTAssertTrue(bodyWarpOps(body: BodyAdjustments(), pose: makeSyntheticPose()).isEmpty)
    }

    func testNoPoseGivesNoOps() {
        var body = BodyAdjustments()
        body.slim = 100
        XCTAssertTrue(bodyWarpOps(body: body, pose: BodyPose()).isEmpty)
    }

    func testSlimPinchesHorizontally() {
        var body = BodyAdjustments()
        body.slim = 100
        let ops = bodyWarpOps(body: body, pose: makeSyntheticPose())
        XCTAssertFalse(ops.isEmpty)
        for op in ops {
            XCTAssertEqual(op.type, .pinch)
            XCTAssertEqual(op.axes, .horizontal)
        }
    }

    func testSculptOpsPresent() {
        var body = BodyAdjustments()
        body.waist = 100
        body.hips = 100
        body.legLength = 100
        body.shoulders = 100
        body.neck = 100
        let ops = bodyWarpOps(body: body, pose: makeSyntheticPose())
        // waist + hips + 2 shin translates + shoulders + neck = 6.
        XCTAssertEqual(ops.count, 6)
    }

    func testDistortionOpNilAtZero() {
        XCTAssertNil(distortionWarpOp(strength: 0))
        XCTAssertNil(distortionWarpOp(strength: -10))
    }

    func testDistortionOpCompressesAtStrength() {
        let op = distortionWarpOp(strength: 50)
        XCTAssertNotNil(op)
        XCTAssertEqual(op?.type, .scale)
        XCTAssertEqual(op?.center, Vec2(0.5, 0.5))
        XCTAssertLessThan(op?.amount ?? 0, 0)
        XCTAssertEqual(op?.amount ?? 0, -0.075, accuracy: 0.0001)
    }
}
