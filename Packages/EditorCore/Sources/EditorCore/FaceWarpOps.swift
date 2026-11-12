// What: Turns FaceAdjustments + FaceLandmarks into WarpOps (the displacement
// field input). Radii are in IPD units so results are face-size independent.
// Inputs/Outputs: face sliders + landmarks in; WarpOps out (max 64, zero ops
// for a neutral face). Threading: Pure functions; safe on any thread.
import Foundation

/// Builds the warp ops for one face. Ops with a zero amount are omitted.
/// Scope filters eye/brow ops (left/right asymmetry); nose, lips and face
/// ops always apply. Pose attenuation: yaw scales far-side eye/brow ops
/// (VERFY: positive yaw = left side far), pitch scales vertical translates,
/// roll scales angle ops. Returns [] when the IPD is 0 (no scale reference).
public func faceWarpOps(face: FaceAdjustments, landmarks: FaceLandmarks) -> [WarpOp] {
    let ipd = landmarks.interPupilDistance
    guard ipd > 0 else { return [] }
    let a = landmarks.anchors
    let up = Vec2(0, -1)
    let down = Vec2(0, 1)
    var ops: [WarpOp] = []
    ops.reserveCapacity(56)

    func radius(_ tool: RetouchTool) -> Float {
        warpRadius(for: tool) * ipd
    }
    func amount(_ slider: Float, _ tool: RetouchTool) -> Float {
        mappedAmount(slider: slider, tool: tool)
    }
    func append(_ op: WarpOp?) {
        guard let op, op.amount != 0 else { return }
        ops.append(op)
    }
    func scale(_ center: Vec2, _ tool: RetouchTool, _ slider: Float, axes: WarpAxes = .both) {
        append(WarpOp(type: .scale, center: center, radius: radius(tool), amount: amount(slider, tool), axes: axes))
    }
    func translate(_ center: Vec2, _ tool: RetouchTool, _ slider: Float, _ direction: Vec2) {
        // Translate peak shift is IPD-relative: mappedAmount is a fraction
        // of the inter-pupil distance, not normalized units. A fixed
        // normalized shift would fold the map for small faces (gradient of
        // a translate op is ~1.5 * amount / radius), so the shift scales
        // with the face. See WarpMathTests.testNoFoldOverFullMaxSliderSet.
        append(WarpOp(type: .translate, center: center, radius: radius(tool), amount: amount(slider, tool) * ipd, direction: direction))
    }
    func pinch(_ center: Vec2, _ tool: RetouchTool, _ slider: Float, axes: WarpAxes = .both) {
        append(WarpOp(type: .pinch, center: center, radius: radius(tool), amount: amount(slider, tool), axes: axes))
    }

    // Side selection: which eye/brow ops apply for this scope, and the
    // far-side multiplier for each side at the current yaw.
    let leftActive = face.scope != .right
    let rightActive = face.scope != .left
    let yawFar = farSideAttenuationFactor(poseAngle: landmarks.yaw, attenuation: face.yawAttenuation)
    let pitchFar = farSideAttenuationFactor(poseAngle: landmarks.pitch, attenuation: face.pitchAttenuation)
    let rollFar = farSideAttenuationFactor(poseAngle: landmarks.roll, attenuation: face.rollAttenuation)
    // VERIFY: Vision yaw sign — this assumes positive yaw turns the face
    // so its LEFT side is far (far = left when yaw > 0, right when yaw < 0).
    let leftFarFactor = landmarks.yaw >= 0 ? yawFar : 1
    let rightFarFactor = landmarks.yaw < 0 ? yawFar : 1

    // MARK: - Eyes (per side)
    for side in [(true, a.leftEyeCenter, leftFarFactor, leftActive),
                 (false, a.rightEyeCenter, rightFarFactor, rightActive)] {
        let (isLeft, center, farFactor, active) = side
        guard active else { continue }
        let outward = isLeft ? -a.eyeAxis : a.eyeAxis
        let outerCorner = isLeft
            ? center - a.eyeAxis * ipd * 0.35
            : center + a.eyeAxis * ipd * 0.35
        let eyeAmount = { (slider: Float, tool: RetouchTool) in amount(slider, tool) * farFactor }
        // Translate peak shifts are IPD-relative (see translate() below);
        // scale amounts are dimensionless and must NOT be scaled by IPD.
        let eyeShift = { (slider: Float, tool: RetouchTool) in amount(slider, tool) * farFactor * ipd }
        if eyeAmount(face.eyeSize, .eyeSize) != 0 {
            ops.append(WarpOp(type: .scale, center: center, radius: radius(.eyeSize), amount: eyeAmount(face.eyeSize, .eyeSize)))
        }
        if eyeAmount(face.eyeHeight, .eyeHeight) != 0 {
            ops.append(WarpOp(type: .scale, center: center, radius: radius(.eyeHeight), amount: eyeAmount(face.eyeHeight, .eyeHeight), axes: .vertical))
        }
        if eyeAmount(face.eyeWidth, .eyeWidth) != 0 {
            ops.append(WarpOp(type: .scale, center: center, radius: radius(.eyeWidth), amount: eyeAmount(face.eyeWidth, .eyeWidth), axes: .horizontal))
        }
        if eyeAmount(face.eyeLength, .eyeLength) != 0 {
            ops.append(WarpOp(type: .translate, center: outerCorner, radius: radius(.eyeLength), amount: eyeShift(face.eyeLength, .eyeLength), direction: outward))
        }
        if eyeAmount(face.eyeSpacing, .eyeSpacing) != 0 {
            ops.append(WarpOp(type: .translate, center: center, radius: radius(.eyeSpacing), amount: eyeShift(face.eyeSpacing, .eyeSpacing), direction: outward))
        }
        if eyeAmount(face.eyePuffy, .eyePuffy) != 0 {
            let lowerLid = center + down * ipd * 0.25
            ops.append(WarpOp(type: .scale, center: lowerLid, radius: radius(.eyePuffy), amount: eyeAmount(face.eyePuffy, .eyePuffy)))
        }
        if eyeAmount(face.eyeAngle, .eyeAngle) != 0 {
            ops.append(WarpOp(type: .translate, center: outerCorner, radius: radius(.eyeAngle), amount: eyeShift(face.eyeAngle, .eyeAngle) * rollFar, direction: up))
        }
        if eyeAmount(face.eyePosition, .eyePosition) != 0 {
            ops.append(WarpOp(type: .translate, center: center, radius: radius(.eyePosition), amount: eyeShift(face.eyePosition, .eyePosition) * pitchFar, direction: up))
        }
    }

    // MARK: - Nose
    scale(a.noseCenter, .noseSize, face.noseSize)
    translate(a.noseCenter, .noseLift, face.noseLift, up)
    pinch(a.noseBase, .noseAla, face.noseAla, axes: .horizontal)
    pinch(a.noseRoot, .noseRoot, face.noseRoot, axes: .horizontal)
    pinch((a.noseRoot + a.noseTip) / 2, .noseBridge, face.noseBridge, axes: .horizontal)
    scale(a.noseTip, .noseTip, face.noseTip)
    // Legacy noseWidth (old state.json files): same meaning as a wide
    // nose base; kept rendering so old projects do not change shape.
    scale(a.noseBase, .noseWidth, face.noseWidth, axes: .horizontal)

    // MARK: - Lips
    scale(a.lipCenter, .lipSize, face.lipSize)
    scale(a.lipCenter, .lipWidth, face.lipWidth, axes: .horizontal)
    scale(a.lipCenter, .lipThickness, face.lipThickness, axes: .vertical)
    translate(a.lipLeftCorner, .lipSmile, face.lipSmile, up)
    translate(a.lipRightCorner, .lipSmile, face.lipSmile, up)
    translate(a.lipCenter, .lipPosition, face.lipPosition, up)
    scale(a.upperLipCenter, .lipMShape, face.lipMShape)

    // MARK: - Brows (per side)
    for side in [(true, a.leftBrowCenter, a.leftBrowTail, leftFarFactor, leftActive),
                 (false, a.rightBrowCenter, a.rightBrowTail, rightFarFactor, rightActive)] {
        let (isLeft, center, tail, farFactor, active) = side
        guard active else { continue }
        let outward = isLeft ? -a.eyeAxis : a.eyeAxis
        let browAmount = { (slider: Float, tool: RetouchTool) in amount(slider, tool) * farFactor }
        // Translate peak shifts are IPD-relative (see translate() below);
        // scale amounts are dimensionless and must NOT be scaled by IPD.
        let browShift = { (slider: Float, tool: RetouchTool) in amount(slider, tool) * farFactor * ipd }
        if browAmount(face.browHeight, .browHeight) != 0 {
            ops.append(WarpOp(type: .translate, center: center, radius: radius(.browHeight), amount: browShift(face.browHeight, .browHeight) * pitchFar, direction: up))
        }
        if browAmount(face.browDistance, .browDistance) != 0 {
            ops.append(WarpOp(type: .translate, center: center, radius: radius(.browDistance), amount: browShift(face.browDistance, .browDistance), direction: outward))
        }
        if browAmount(face.browThickness, .browThickness) != 0 {
            ops.append(WarpOp(type: .scale, center: center, radius: radius(.browThickness), amount: browAmount(face.browThickness, .browThickness)))
        }
        if browAmount(face.browAngle, .browAngle) != 0 {
            ops.append(WarpOp(type: .translate, center: tail, radius: radius(.browAngle), amount: browShift(face.browAngle, .browAngle) * rollFar, direction: up))
        }
        if browAmount(face.browLength, .browLength) != 0 {
            ops.append(WarpOp(type: .translate, center: tail, radius: radius(.browLength), amount: browShift(face.browLength, .browLength), direction: outward))
        }
        if browAmount(face.browShape, .browShape) != 0 {
            ops.append(WarpOp(type: .scale, center: center, radius: radius(.browShape), amount: browAmount(face.browShape, .browShape)))
        }
    }

    // MARK: - Face
    scale(a.faceCenter, .faceWidth, face.faceWidth, axes: .horizontal)
    pinch(Vec2(a.faceCenter.x, (a.jawLeft.y + a.jawRight.y) / 2), .jawSize, face.jawSize)
    translate(a.chin, .chinLength, face.chinLength, down)
    scale(a.chin, .chinWidth, face.chinWidth, axes: .horizontal)
    scale(a.cheekLeft, .cheekbones, face.cheekbones)
    scale(a.cheekRight, .cheekbones, face.cheekbones)
    scale(a.templeLeft, .temples, face.temples)
    scale(a.templeRight, .temples, face.temples)
    translate(a.foreheadTop, .foreheadHeight, face.foreheadHeight, up)
    scale(a.faceCenter, .faceLength, face.faceLength, axes: .vertical)
    pinch(a.jawLeft, .vShape, face.vShape)
    pinch(a.jawRight, .vShape, face.vShape)

    return ops
}
