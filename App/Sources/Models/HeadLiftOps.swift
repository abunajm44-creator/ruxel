// HeadLiftOps — head size/shape + lift/tighten as WarpOps.
// What: converts the P5 head/lift extras sliders into displacement-field
// ops, using the same WarpOp types (scale / translate / pinch) and the
// same IPD-relative sizing as the face warp ops, so they ride the same
// field kernel, the same export replay, and the same no-fold-over caps.
// The WarpOp direction/amount expresses the INTENDED content motion
// (the displacement functions convert it to the backward field).
// Threading: pure functions; safe on any thread.
import Foundation
import EditorCore

/// Head + lift warp ops for one face. Returns [] when the IPD is 0
/// (no scale reference) or when all four sliders are neutral.
/// - headSize: radial scale about the face center (+ = bigger head).
/// - headShape: horizontal-only scale about the face center
///   (+ = wider head).
/// - lift: upward translate around the jaw (+ = lift the jaw/cheeks).
/// - tighten: pinch about the face center (+ = tighter).
func headLiftWarpOps(extras: ExtraAdjustments, landmarks: FaceLandmarks) -> [WarpOp] {
    let ipd = landmarks.interPupilDistance
    guard ipd > 0 else { return [] }
    let anchors = landmarks.anchors
    var ops: [WarpOp] = []
    // Head size: gentle radial scale; 0.12 at full slider matches the
    // face scale caps (0.20-0.35) while staying well inside the
    // no-fold-over budget.
    if extras.headSize != 0 {
        ops.append(WarpOp(
            type: .scale, center: anchors.faceCenter,
            radius: 1.6 * ipd, amount: extras.headSize / 100 * 0.12))
    }
    if extras.headShape != 0 {
        ops.append(WarpOp(
            type: .scale, center: anchors.faceCenter,
            radius: 1.6 * ipd, amount: extras.headShape / 100 * 0.12,
            axes: .horizontal))
    }
    if extras.lift != 0 {
        let jawCenter = Vec2(
            (anchors.jawLeft.x + anchors.jawRight.x) / 2,
            (anchors.jawLeft.y + anchors.jawRight.y) / 2)
        ops.append(WarpOp(
            type: .translate, center: jawCenter,
            radius: 1.8 * ipd, amount: extras.lift / 100 * 0.10 * ipd,
            direction: Vec2(0, -1)))
    }
    if extras.tighten != 0 {
        ops.append(WarpOp(
            type: .pinch, center: anchors.faceCenter,
            radius: 1.4 * ipd, amount: extras.tighten / 100 * 0.15))
    }
    return ops
}
