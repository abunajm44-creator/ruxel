// What: Body reshape from pose capsules — slim pinch, sculpt sliders,
// distortion correction as a displacement field with its own strength.
// Inputs/Outputs: BodyAdjustments + BodyPose in; WarpOps out (zero ops
// when the body is neutral or the pose is missing). Threading: Pure
// functions; safe on any thread.
import Foundation

/// One body segment: a capsule from `start` to `end` with a `radius`
/// (normalized units) around its centerline. Derived from pose joints.
public struct BodyCapsule: Codable, Equatable, Sendable {
    public var start: Vec2
    public var end: Vec2
    public var radius: Float

    public init(start: Vec2, end: Vec2, radius: Float) {
        self.start = start
        self.end = end
        self.radius = radius
    }

    public var center: Vec2 { (start + end) / 2 }
    public var length: Float { start.distance(to: end) }
}

/// Capsules from a detected pose: torso, upper arms, forearms, thighs,
/// calves. Missing joints are skipped; a pose with no usable joints
/// yields []. Radii are fractions of the shoulder width.
public func bodyCapsules(pose: BodyPose) -> [BodyCapsule] {
    func joint(_ name: BodyJointName) -> Vec2? {
        guard let found = pose.joint(name), found.confidence > 0.2 else { return nil }
        return found.position
    }
    guard let leftShoulder = joint(.leftShoulder),
          let rightShoulder = joint(.rightShoulder) else { return [] }
    let shoulderWidth = leftShoulder.distance(to: rightShoulder)
    guard shoulderWidth > 0 else { return [] }
    let shoulderCenter = (leftShoulder + rightShoulder) / 2
    let leftHip = joint(.leftHip)
    let rightHip = joint(.rightHip)
    let hipCenter: Vec2? = {
        guard let left = leftHip, let right = rightHip else { return leftHip ?? rightHip }
        return (left + right) / 2
    }()
    var capsules: [BodyCapsule] = []
    if let hip = hipCenter {
        capsules.append(BodyCapsule(start: shoulderCenter, end: hip, radius: shoulderWidth * 0.45))
    }
    let limbs: [(BodyJointName, BodyJointName, Float)] = [
        (.leftShoulder, .leftElbow, 0.16), (.rightShoulder, .rightElbow, 0.16),
        (.leftElbow, .leftWrist, 0.13), (.rightElbow, .rightWrist, 0.13),
        (.leftHip, .leftKnee, 0.22), (.rightHip, .rightKnee, 0.22),
        (.leftKnee, .leftAnkle, 0.18), (.rightKnee, .rightAnkle, 0.18)
    ]
    for (from, to, fraction) in limbs {
        guard let start = joint(from), let end = joint(to) else { continue }
        capsules.append(BodyCapsule(start: start, end: end, radius: shoulderWidth * fraction))
    }
    return capsules
}

private func midpoint(_ pose: BodyPose, _ first: BodyJointName, _ second: BodyJointName) -> Vec2? {
    guard let a = pose.joint(first), let b = pose.joint(second) else { return nil }
    return (a.position + b.position) / 2
}

/// Warp ops for the body sculpt sliders. Slim is a horizontal pinch of
/// the torso and limb capsules; sculpt moves waist/hips/legs/shoulders/
/// neck around their pose anchors. Body radii come from pose geometry
/// (capsule sizes), not IPD. Returns [] for a neutral body or no pose.
public func bodyWarpOps(body: BodyAdjustments, pose: BodyPose) -> [WarpOp] {
    let capsules = bodyCapsules(pose: pose)
    guard capsules.isEmpty == false else { return [] }
    let shoulderCenter = midpoint(pose, .leftShoulder, .rightShoulder)
    let hipCenter = midpoint(pose, .leftHip, .rightHip)
    let neck = pose.joint(.neck)?.position
    var ops: [WarpOp] = []

    func append(_ op: WarpOp?) {
        guard let op, op.amount != 0 else { return }
        ops.append(op)
    }
    func pinchHorizontal(_ center: Vec2, _ slider: Float, _ tool: RetouchTool, _ radius: Float) {
        append(WarpOp(type: .pinch, center: center, radius: radius, amount: mappedAmount(slider: slider, tool: tool), axes: .horizontal))
    }
    func scaleHorizontal(_ center: Vec2, _ slider: Float, _ tool: RetouchTool, _ radius: Float) {
        append(WarpOp(type: .scale, center: center, radius: radius, amount: mappedAmount(slider: slider, tool: tool), axes: .horizontal))
    }

    // Slim: horizontal pinch of the torso capsule plus every limb capsule.
    let slimAmount = mappedAmount(slider: body.slim, tool: .bodySlim)
    if slimAmount != 0 {
        for capsule in capsules {
            ops.append(WarpOp(
                type: .pinch, center: capsule.center,
                radius: max(capsule.length * 0.6, capsule.radius * 2),
                amount: slimAmount, axes: .horizontal
            ))
        }
    }

    // Waist: pinch at the midpoint between shoulders and hips.
    if let shoulders = shoulderCenter, let hips = hipCenter {
        let waistCenter = (shoulders + hips) / 2
        let torsoWidth = shoulders.distance(to: hips) * 0.4
        pinchHorizontal(waistCenter, body.waist, .waist, max(torsoWidth, 0.05))
        // Hips: horizontal scale at the hip center.
        scaleHorizontal(hips, body.hips, .hips, max(torsoWidth * 1.2, 0.05))
    }

    // Leg length: one translate per leg at the shin midpoint (knee–ankle),
    // radius 0.5, amount scaled to 0.10 so +100 moves the legs at most
    // 2% of the image height. Four separate knee/ankle translates folded
    // the map where they overlap the chin/jaw ops (see WarpMathTests,
    // negative max set); a single wide translate per leg is also the
    // better physical model (the whole lower leg moves down together).
    let legAmount = mappedAmount(slider: body.legLength, tool: .legLength) * 0.10
    if legAmount != 0 {
        for (knee, ankle) in [(BodyJointName.leftKnee, BodyJointName.leftAnkle),
                              (BodyJointName.rightKnee, BodyJointName.rightAnkle)] {
            guard let kneeJoint = pose.joint(knee),
                  let ankleJoint = pose.joint(ankle) else { continue }
            let shinCenter = (kneeJoint.position + ankleJoint.position) / 2
            ops.append(WarpOp(
                type: .translate, center: shinCenter, radius: 0.5,
                amount: legAmount, direction: Vec2(0, 1)
            ))
        }
    }

    // Shoulders: horizontal scale at the shoulder center.
    if let shoulders = shoulderCenter,
       let left = pose.joint(.leftShoulder)?.position,
       let right = pose.joint(.rightShoulder)?.position {
        scaleHorizontal(shoulders, body.shoulders, .shoulders, max(left.distance(to: right), 0.05))
    }

    // Neck: scale at the neck joint.
    if let neck {
        scaleHorizontal(neck, body.neck, .neck, 0.12)
    }

    return ops
}

/// Distortion correction as a single scale op at the image center.
/// Positive strength compresses edge pixels toward the center (wide-angle
/// edge stretch correction); the mapped peak is 0.15 at strength 100.
/// Returns nil when strength is 0 (advanced; disabled when no face/body
/// is found — the UI greys the control out in that case).
public func distortionWarpOp(strength: Float) -> WarpOp? {
    let clamped = min(max(strength, 0), 100)
    guard clamped > 0 else { return nil }
    return WarpOp(
        type: .scale, center: Vec2(0.5, 0.5), radius: 1.0,
        amount: -(clamped / 100) * 0.15
    )
}
