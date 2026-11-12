// AnalysisService — one-shot Vision analysis per photo, cached on disk.
// What: face landmarks + person segmentation + body pose, at proxy size.
// Inputs-outputs: proxy CGImage -> AnalysisResult (landmarks, masks, pose).
// Threading: all Vision work on a background queue; results delivered async.
// NOTE: the FaceLandmarkProviding protocol lives in EditorCore (Landmarks.swift)
// with signature landmarks(for faceId:) -> FaceLandmarks?. This file only
// adapts Vision results to it; it defines no competing protocol.

import Foundation
import Vision
import CoreGraphics
import CoreVideo
import CoreImage
import UIKit
import EditorCore
final class AnalysisService {
    /// The single place Vision bottom-left coordinates become top-left.
    static func toTopLeft(_ point: CGPoint, imageHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: imageHeight - point.y)
    }

    /// Normalized Vision point (0...1, bottom-left origin) -> top-left.
    static func toTopLeftNormalized(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: 1 - point.y)
    }

    private let workQueue = DispatchQueue(
        label: "com.abunajm44creator.ruxel.analysis", qos: .userInitiated)

    func analyze(image: CGImage, cacheURL: URL?) async throws -> AnalysisResult {
        try await withCheckedThrowingContinuation { continuation in
            workQueue.async {
                do {
                    let result = try self.runAnalysis(image: image)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runAnalysis(image: CGImage) throws -> AnalysisResult {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        // VERIFY: VNDetectFaceLandmarksRequest revision / properties on iOS 16.
        let faceRequest = VNDetectFaceLandmarksRequest()
        // VERIFY: VNGeneratePersonSegmentationRequest qualityLevel .accurate.
        let segmentationRequest = VNGeneratePersonSegmentationRequest()
        segmentationRequest.qualityLevel = .accurate
        // VERIFY: VNDetectHumanBodyPoseRequest availability on iOS 16.
        let poseRequest = VNDetectHumanBodyPoseRequest()
        try handler.perform([faceRequest, segmentationRequest, poseRequest])
        let faces = (faceRequest.results as? [VNFaceObservation]) ?? []
        let personMask = segmentationRequest.results?.first?.pixelBuffer
        let poses = (poseRequest.results as? [VNHumanBodyPoseObservation]) ?? []
        let imageSize = CGSize(width: image.width, height: image.height)
        let partial = AnalysisResult(
            faceCount: faces.count,
            hasFace: faces.isEmpty == false,
            faceObservations: faces,
            personMaskPixelBuffer: personMask,
            imageSize: imageSize
        )
        let adapter = VisionFaceLandmarksAdapter(result: partial)
        var landmarks: [FaceLandmarks] = []
        for index in faces.indices {
            if let faceLandmarks = adapter.landmarks(for: "face-\(index)") {
                landmarks.append(faceLandmarks)
            }
        }
        return AnalysisResult(
            faceCount: faces.count,
            hasFace: faces.isEmpty == false,
            faceObservations: faces,
            personMaskPixelBuffer: personMask,
            imageSize: imageSize,
            faceLandmarks: landmarks,
            bodyPose: Self.bodyPose(from: poses.first),
            hasBody: poses.isEmpty == false
        )
    }

    /// Converts a Vision body-pose observation into EditorCore joints.
    /// Only joints BodyJointName knows are kept; low-confidence points
    /// are kept too (the capsule builder filters them at confidence 0.2).
    /// VERIFY: VNRecognizedPoint locations are normalized bottom-left
    /// origin like other Vision points (converted here to top-left).
    static func bodyPose(from observation: VNHumanBodyPoseObservation?) -> BodyPose? {
        guard let observation else { return nil }
        let mapping: [(VNHumanBodyPoseObservation.JointName, BodyJointName)] = [
            (.neck, .neck),
            (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
            (.leftElbow, .leftElbow), (.rightElbow, .rightElbow),
            (.leftWrist, .leftWrist), (.rightWrist, .rightWrist),
            (.leftHip, .leftHip), (.rightHip, .rightHip),
            (.leftKnee, .leftKnee), (.rightKnee, .rightKnee),
            (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle)
        ]
        var joints: [BodyJoint] = []
        for (visionName, coreName) in mapping {
            guard let point = try? observation.recognizedPoint(visionName) else { continue }
            let topLeft = toTopLeftNormalized(point.location)
            joints.append(BodyJoint(
                name: coreName,
                position: Vec2(Float(topLeft.x), Float(topLeft.y)),
                confidence: point.confidence
            ))
        }
        return joints.isEmpty ? nil : BodyPose(joints: joints)
    }

    /// Renders a person-segmentation pixel buffer as a UIImage for the
    /// debug mask overlay. Nil when the buffer cannot be converted.
    /// VERIFY: CIImage(cvPixelBuffer:) + CIContext rendering of a
    /// segmentation mask on iOS 16.
    static func maskImage(from pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Reads a person-segmentation pixel buffer into floats (0...1,
    /// row-major) at the buffer's own size, for export. Handles the
    /// single-channel 8-bit and 32-bit-float mask formats; other formats
    /// return nil (the caller then skips mask-dependent stages).
    /// VERIFY: the person-segmentation pixel format on iOS 16.
    static func floatMask(from pixelBuffer: CVPixelBuffer) -> (values: [Float], width: Int, height: Int)? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0,
              let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        var values = [Float](repeating: 0, count: width * height)
        if format == kCVPixelFormatType_OneComponent8 {
            for y in 0..<height {
                let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                for x in 0..<width {
                    values[y * width + x] = Float(row[x]) / 255
                }
            }
        } else if format == kCVPixelFormatType_OneComponent32Float {
            for y in 0..<height {
                let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float.self)
                for x in 0..<width {
                    values[y * width + x] = min(max(row[x], 0), 1)
                }
            }
        } else {
            return nil
        }
        return (values: values, width: width, height: height)
    }
}

// AnalysisResult — what the editor needs from Vision, in app coordinates.
struct AnalysisResult: Sendable {
    var faceCount: Int
    var hasFace: Bool
    var faceObservations: [VNFaceObservation]
    var personMaskPixelBuffer: CVPixelBuffer?
    var imageSize: CGSize
    /// Landmarks per detected face, in detection order ("face-0", ...).
    var faceLandmarks: [FaceLandmarks]
    /// First detected body pose, if any.
    var bodyPose: BodyPose?
    var hasBody: Bool

    init(
        faceCount: Int,
        hasFace: Bool,
        faceObservations: [VNFaceObservation],
        personMaskPixelBuffer: CVPixelBuffer?,
        imageSize: CGSize,
        faceLandmarks: [FaceLandmarks] = [],
        bodyPose: BodyPose? = nil,
        hasBody: Bool = false
    ) {
        self.faceCount = faceCount
        self.hasFace = hasFace
        self.faceObservations = faceObservations
        self.personMaskPixelBuffer = personMaskPixelBuffer
        self.imageSize = imageSize
        self.faceLandmarks = faceLandmarks
        self.bodyPose = bodyPose
        self.hasBody = hasBody
    }
}

// VisionFaceLandmarksAdapter — adapts a Vision result to EditorCore's
// FaceLandmarkProviding, converting bottom-left coords to top-left once.
struct VisionFaceLandmarksAdapter: FaceLandmarkProviding {
    let result: AnalysisResult

    /// faceId is "face-0", "face-1", ... in detection order.
    func landmarks(for faceId: String) -> FaceLandmarks? {
        let index = Int(faceId.replacingOccurrences(of: "face-", with: "")) ?? 0
        guard result.faceObservations.indices.contains(index) else { return nil }
        let face = result.faceObservations[index]
        guard let landmarks = face.landmarks else { return nil }
        // VERIFY: VNFaceObservation.roll / yaw are NSNumber? on iOS 16;
        // pitch is not provided by Vision — it stays 0 here.
        return FaceLandmarks(
            contour: points(of: landmarks.faceContour),
            leftEye: points(of: landmarks.leftEye),
            rightEye: points(of: landmarks.rightEye),
            leftBrow: points(of: landmarks.leftEyebrow),
            rightBrow: points(of: landmarks.rightEyebrow),
            nose: points(of: landmarks.nose),
            noseCrest: points(of: landmarks.noseCrest),
            medianLine: points(of: landmarks.medianLine),
            outerLips: points(of: landmarks.outerLips),
            innerLips: points(of: landmarks.innerLips),
            leftPupil: singlePoint(of: landmarks.leftPupil),
            rightPupil: singlePoint(of: landmarks.rightPupil),
            roll: face.roll?.floatValue ?? 0,
            yaw: face.yaw?.floatValue ?? 0,
            pitch: 0
        )
    }

    private func points(of region: VNFaceLandmarkRegion2D?) -> [Vec2] {
        guard let region else { return [] }
        return region.normalizedPoints.map { point in
            let topLeft = AnalysisService.toTopLeftNormalized(point)
            return Vec2(Float(topLeft.x), Float(topLeft.y))
        }
    }

    private func singlePoint(of region: VNFaceLandmarkRegion2D?) -> Vec2 {
        guard let point = region?.normalizedPoints.first else { return .zero }
        let topLeft = AnalysisService.toTopLeftNormalized(point)
        return Vec2(Float(topLeft.x), Float(topLeft.y))
    }
}
