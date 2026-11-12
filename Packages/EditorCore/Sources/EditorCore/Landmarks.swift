// What: Landmark and body-pose types plus the landmark-provider protocol.
// Inputs/Outputs: Normalized landmark points in; derived anchors and IPD out.
// Threading: Value types, Sendable; safe on any thread.
import Foundation

/// Face landmarks in normalized image coordinates (0...1, origin top-left).
public struct FaceLandmarks: Codable, Equatable, Sendable {
    public var contour: [Vec2]
    public var leftEye: [Vec2]
    public var rightEye: [Vec2]
    public var leftBrow: [Vec2]
    public var rightBrow: [Vec2]
    public var nose: [Vec2]
    public var noseCrest: [Vec2]
    public var medianLine: [Vec2]
    public var outerLips: [Vec2]
    public var innerLips: [Vec2]
    public var leftPupil: Vec2
    public var rightPupil: Vec2
    public var roll: Float
    public var yaw: Float
    public var pitch: Float

    public init(
        contour: [Vec2] = [],
        leftEye: [Vec2] = [],
        rightEye: [Vec2] = [],
        leftBrow: [Vec2] = [],
        rightBrow: [Vec2] = [],
        nose: [Vec2] = [],
        noseCrest: [Vec2] = [],
        medianLine: [Vec2] = [],
        outerLips: [Vec2] = [],
        innerLips: [Vec2] = [],
        leftPupil: Vec2 = .zero,
        rightPupil: Vec2 = .zero,
        roll: Float = 0,
        yaw: Float = 0,
        pitch: Float = 0
    ) {
        self.contour = contour
        self.leftEye = leftEye
        self.rightEye = rightEye
        self.leftBrow = leftBrow
        self.rightBrow = rightBrow
        self.nose = nose
        self.noseCrest = noseCrest
        self.medianLine = medianLine
        self.outerLips = outerLips
        self.innerLips = innerLips
        self.leftPupil = leftPupil
        self.rightPupil = rightPupil
        self.roll = roll
        self.yaw = yaw
        self.pitch = pitch
    }

    /// Inter-pupil distance: the face scale unit. All warp radii are
    /// expressed in IPD units so results are independent of face size.
    public var interPupilDistance: Float {
        leftPupil.distance(to: rightPupil)
    }

    /// Midpoint between the pupils (face center anchor).
    public var eyeCenter: Vec2 {
        Vec2((leftPupil.x + rightPupil.x) / 2, (leftPupil.y + rightPupil.y) / 2)
    }

    /// Geometric anchors derived from the landmarks (forehead top, cheek
    /// centers, jaw angles, ...). Every anchor falls back to a nearby
    /// landmark when its source region is empty, so warp-op building
    /// never has to unwrap anything.
    public var anchors: FaceAnchors {
        FaceAnchors(landmarks: self)
    }
}

/// Derived geometric anchors for warp-op placement. All points are
/// normalized top-left coordinates; empty source regions fall back to
/// the eye center / pupils so no anchor is ever missing.
public struct FaceAnchors: Codable, Equatable, Sendable {
    public var leftEyeCenter: Vec2
    public var rightEyeCenter: Vec2
    /// Unit vector from the left pupil to the right pupil.
    public var eyeAxis: Vec2
    public var noseCenter: Vec2
    public var noseTip: Vec2
    public var noseRoot: Vec2
    public var noseBase: Vec2
    public var lipCenter: Vec2
    public var lipLeftCorner: Vec2
    public var lipRightCorner: Vec2
    public var upperLipCenter: Vec2
    public var leftBrowCenter: Vec2
    public var rightBrowCenter: Vec2
    public var leftBrowTail: Vec2
    public var rightBrowTail: Vec2
    public var chin: Vec2
    public var jawLeft: Vec2
    public var jawRight: Vec2
    public var cheekLeft: Vec2
    public var cheekRight: Vec2
    public var foreheadTop: Vec2
    public var templeLeft: Vec2
    public var templeRight: Vec2
    public var faceCenter: Vec2

    public init(landmarks: FaceLandmarks) {
        // Locals first: closures in this initializer must not capture
        // self.* properties before all of them are assigned.
        let eyeCenter = landmarks.eyeCenter
        let leftPupil = landmarks.leftPupil
        let rightPupil = landmarks.rightPupil
        func centroid(_ points: [Vec2], fallback: Vec2) -> Vec2 {
            guard points.isEmpty == false else { return fallback }
            var sum = Vec2.zero
            for point in points { sum = sum + point }
            return sum / Float(points.count)
        }
        func extreme(_ points: [Vec2], fallback: Vec2, pick: (Vec2, Vec2) -> Bool) -> Vec2 {
            guard var best = points.first else { return fallback }
            for point in points.dropFirst() where pick(point, best) { best = point }
            return best
        }

        let leftEyeCenter = centroid(landmarks.leftEye, fallback: leftPupil)
        let rightEyeCenter = centroid(landmarks.rightEye, fallback: rightPupil)
        let axis = rightPupil - leftPupil
        let eyeAxis = axis.length > 0 ? axis / axis.length : Vec2(1, 0)

        let noseCenter = centroid(landmarks.nose, fallback: eyeCenter)
        let noseTip = extreme(landmarks.nose, fallback: noseCenter) { $0.y > $1.y }
        let noseRoot = landmarks.noseCrest.first ?? noseCenter
        let noseBase = centroid(
            landmarks.nose.filter { $0.y > noseCenter.y },
            fallback: noseTip
        )
        let lipCenter = centroid(landmarks.outerLips, fallback: noseTip)
        let lipLeftCorner = extreme(landmarks.outerLips, fallback: lipCenter) { $0.x < $1.x }
        let lipRightCorner = extreme(landmarks.outerLips, fallback: lipCenter) { $0.x > $1.x }
        let upperLipCenter = centroid(
            landmarks.outerLips.filter { $0.y < lipCenter.y },
            fallback: lipCenter
        )
        let leftBrowCenter = centroid(landmarks.leftBrow, fallback: leftEyeCenter)
        let rightBrowCenter = centroid(landmarks.rightBrow, fallback: rightEyeCenter)
        let leftBrowTail = extreme(landmarks.leftBrow, fallback: leftBrowCenter) { $0.x < $1.x }
        let rightBrowTail = extreme(landmarks.rightBrow, fallback: rightBrowCenter) { $0.x > $1.x }

        let faceCenter = centroid(landmarks.contour, fallback: eyeCenter)
        let chin = extreme(landmarks.contour, fallback: faceCenter) { $0.y > $1.y }
        let lowerContour = landmarks.contour.filter { $0.y > eyeCenter.y }
        let jawLeft = extreme(lowerContour, fallback: faceCenter) { $0.x < $1.x }
        let jawRight = extreme(lowerContour, fallback: faceCenter) { $0.x > $1.x }
        let leftEyeOuter = extreme(landmarks.leftEye, fallback: leftEyeCenter) { $0.x < $1.x }
        let rightEyeOuter = extreme(landmarks.rightEye, fallback: rightEyeCenter) { $0.x > $1.x }
        let cheekLeft = (leftEyeOuter + lipLeftCorner) / 2
        let cheekRight = (rightEyeOuter + lipRightCorner) / 2
        // Forehead top: mirror the eye-to-nose distance upward from the eyes.
        let foreheadTop = eyeCenter - (noseTip - eyeCenter) * 0.8
        let templeLeft = (foreheadTop + leftEyeOuter) / 2 - eyeAxis * landmarks.interPupilDistance * 0.15
        let templeRight = (foreheadTop + rightEyeOuter) / 2 + eyeAxis * landmarks.interPupilDistance * 0.15

        self.leftEyeCenter = leftEyeCenter
        self.rightEyeCenter = rightEyeCenter
        self.eyeAxis = eyeAxis
        self.noseCenter = noseCenter
        self.noseTip = noseTip
        self.noseRoot = noseRoot
        self.noseBase = noseBase
        self.lipCenter = lipCenter
        self.lipLeftCorner = lipLeftCorner
        self.lipRightCorner = lipRightCorner
        self.upperLipCenter = upperLipCenter
        self.leftBrowCenter = leftBrowCenter
        self.rightBrowCenter = rightBrowCenter
        self.leftBrowTail = leftBrowTail
        self.rightBrowTail = rightBrowTail
        self.faceCenter = faceCenter
        self.chin = chin
        self.jawLeft = jawLeft
        self.jawRight = jawRight
        self.cheekLeft = cheekLeft
        self.cheekRight = cheekRight
        self.foreheadTop = foreheadTop
        self.templeLeft = templeLeft
        self.templeRight = templeRight
    }
}

/// Named body joints from a human-body-pose detector.
public enum BodyJointName: String, Codable, Hashable, Sendable {
    case neck
    case leftShoulder
    case rightShoulder
    case leftElbow
    case rightElbow
    case leftWrist
    case rightWrist
    case leftHip
    case rightHip
    case leftKnee
    case rightKnee
    case leftAnkle
    case rightAnkle
}

/// One detected body joint with a detector confidence in 0...1.
public struct BodyJoint: Codable, Equatable, Sendable {
    public var name: BodyJointName
    public var position: Vec2
    public var confidence: Float

    public init(name: BodyJointName, position: Vec2, confidence: Float = 1) {
        self.name = name
        self.position = position
        self.confidence = confidence
    }
}

/// A detected body pose: joints with confidence values.
public struct BodyPose: Codable, Equatable, Sendable {
    public var joints: [BodyJoint]

    public init(joints: [BodyJoint] = []) {
        self.joints = joints
    }

    public func joint(_ name: BodyJointName) -> BodyJoint? {
        joints.first { $0.name == name }
    }
}

/// Boundary between the warp math and any landmark source (Vision,
/// MediaPipe, or a test mock). Implementations convert their own
/// coordinate system to normalized top-left coordinates.
public protocol FaceLandmarkProviding {
    func landmarks(for faceId: String) -> FaceLandmarks?
}
