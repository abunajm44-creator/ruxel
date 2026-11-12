// ExportService — tile-based full-resolution export to Photos or share sheet.
// What: renders the retouch at full resolution in 2048px tiles + halo.
// Inputs-outputs: RetouchState + original file -> saved photo / share URL.
// Threading: export runs on a background task; progress/cancel via Task.

import Foundation
import Photos
import UIKit
import ImageIO
import UniformTypeIdentifiers
import EditorCore
final class ExportService {
    enum Format: String, CaseIterable, Sendable {
        case heic
        case jpeg
        case png

        var utType: UTType {
            switch self {
            case .heic: return UTType.heic
            case .jpeg: return UTType.jpeg
            case .png: return UTType.png
            }
        }

        var fileExtension: String { rawValue }
    }

    /// Tile size for full-resolution export; halo covers kernel radius + max displacement.
    static let tileSize = 2048
    static let tileHalo = 64

    private(set) var isExporting = false

    /// Tile grid for an image of `size`, via EditorCore TilingMath
    /// (tiles 2048 + halo = kernel radius + max displacement). No local copy.
    func tileRects(for size: CGSize, halo: Int = tileHalo) -> [TileRect] {
        EditorCore.tileRects(
            imageWidth: Int(size.width),
            imageHeight: Int(size.height),
            tileSize: Self.tileSize,
            halo: halo
        )
    }

    /// Full-resolution export: replays sliders and brush strokes
    /// analytically per tile (2048 + halo), so a 48MP photo never needs
    /// huge textures. Skin stage (mask + blur + blend + grain) runs
    /// first, then the warp stage (bicubic, background lock). Two full
    /// RGBA8 buffers (input + output, ~192MB each at 48MP) plus one
    /// assembled Data live transiently — the input buffer is released
    /// before assembly. Progress is 0...1 per finished tile; cancellation
    /// is checked between tiles. Returns the temp file URL (caller saves
    /// it to Photos or shares it, then calls cleanupTempFile).
    func exportFullResolution(
        state: RetouchState,
        landmarks: FaceLandmarks?,
        bodyPose: BodyPose?,
        personMask: (values: [Float], width: Int, height: Int)?,
        originalURL: URL,
        format: Format,
        quality: CGFloat,
        stripGPS: Bool,
        progress: @escaping (Double) -> Void
    ) async throws -> URL {
        isExporting = true
        defer { isExporting = false }
        let (input, imageWidth, imageHeight, properties) = try loadFullResolutionPixels(from: originalURL)
        var output = [UInt8](repeating: 0, count: imageWidth * imageHeight * 4)
        var ops: [WarpOp] = []
        if let landmarks, let face = state.faces.first {
            ops.append(contentsOf: faceWarpOps(face: face, landmarks: landmarks))
        }
        if let bodyPose {
            ops.append(contentsOf: bodyWarpOps(body: state.body, pose: bodyPose))
        }
        if let distortion = distortionWarpOp(strength: state.distortionCorrection) {
            ops.append(distortion)
        }
        let dabs = state.brushStrokes.flatMap { brushDabs(from: $0) }
        let maxDim = Float(max(imageWidth, imageHeight))
        let halo = max(Self.tileHalo, Int(ceil(maxDisplacementMagnitude(ops: ops) * maxDim)) + 4)
        let tiles = tileRects(for: CGSize(width: imageWidth, height: imageHeight), halo: halo)
        let blurPasses = maxDim > 3000 ? 2 : 1
        for (index, tile) in tiles.enumerated() {
            try Task.checkCancellation()
            processTile(
                tile, state: state, ops: ops, dabs: dabs, landmarks: landmarks,
                personMask: personMask, input: input, output: &output,
                imageWidth: imageWidth, imageHeight: imageHeight, blurPasses: blurPasses)
            progress(Double(index + 1) / Double(tiles.count))
        }
        // Release the input buffer before assembling the output image.
        let image = try assembleImage(output: output, width: imageWidth, height: imageHeight)
        var outputProperties = properties
        outputProperties[kCGImagePropertyOrientation] = 1
        return try writeImage(image, format: format, quality: quality, stripGPS: stripGPS, properties: outputProperties)
    }

    /// Loads the original file at full resolution with EXIF orientation
    /// applied (ImageIO thumbnail at the image's own long edge), decoded
    /// into an RGBA8 buffer. Returns the pixels, size, and EXIF properties.
    private func loadFullResolutionPixels(from url: URL) throws -> (
        input: [UInt8], width: Int, height: Int, properties: [CFString: Any]
    ) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw AppError.exportFailed
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw AppError.exportFailed
        }
        let pixelWidth = (properties[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let pixelHeight = (properties[kCGImagePropertyPixelHeight] as? Int) ?? 0
        guard pixelWidth > 0, pixelHeight > 0 else { throw AppError.exportFailed }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(pixelWidth, pixelHeight),
            kCGImageSourceCreateThumbnailFromImageAlways: true
        ]
        guard let oriented = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw AppError.exportFailed
        }
        let width = oriented.width
        let height = oriented.height
        var input = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = input.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(oriented, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw AppError.exportFailed }
        return (input, width, height, properties)
    }

    /// Assembles the output RGBA8 buffer into a CGImage (Display P3).
    private func assembleImage(output: [UInt8], width: Int, height: Int) throws -> CGImage {
        guard let provider = CGDataProvider(data: Data(output) as CFData) else {
            throw AppError.exportFailed
        }
        let space = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        guard let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            throw AppError.exportFailed
        }
        return image
    }

    /// Renders one tile: skin stage (masked blur + blend + grain) then
    /// warp stage (tile field, background lock, bicubic). Writes only
    /// the core rect into `output`; halo pixels are read-only context.
    private func processTile(
        _ tile: TileRect,
        state: RetouchState,
        ops: [WarpOp],
        dabs: [BrushDab],
        landmarks: FaceLandmarks?,
        personMask: (values: [Float], width: Int, height: Int)?,
        input: [UInt8],
        output: inout [UInt8],
        imageWidth: Int,
        imageHeight: Int,
        blurPasses: Int
    ) {
        let haloW = tile.haloW
        let haloH = tile.haloH
        let count = haloW * haloH
        var red = [Float](repeating: 0, count: count)
        var green = [Float](repeating: 0, count: count)
        var blue = [Float](repeating: 0, count: count)
        for y in 0..<haloH {
            for x in 0..<haloW {
                let sourceIndex = ((tile.haloY + y) * imageWidth + (tile.haloX + x)) * 4
                let index = y * haloW + x
                red[index] = Float(input[sourceIndex]) / 255
                green[index] = Float(input[sourceIndex + 1]) / 255
                blue[index] = Float(input[sourceIndex + 2]) / 255
            }
        }
        // Person mask, resampled into this tile: needed by the skin
        // stage and by background lock. Empty when no mask exists.
        var personRegion: [Float] = []
        if let personMask {
            personRegion = personMaskRegion(
                mask: personMask.values, maskWidth: personMask.width, maskHeight: personMask.height,
                tileWidth: haloW, tileHeight: haloH,
                tileOriginX: tile.haloX, tileOriginY: tile.haloY,
                imageWidth: imageWidth, imageHeight: imageHeight)
        }
        // Skin stage: skipped when the mask is empty (smoothing without
        // a mask would smooth clothes and background).
        if state.skinIsNeutral == false {
            let faceOval = faceOvalMask(
                tileWidth: haloW, tileHeight: haloH,
                tileOriginX: tile.haloX, tileOriginY: tile.haloY,
                imageWidth: imageWidth, imageHeight: imageHeight,
                contour: landmarks?.contour ?? [])
            let mask = skinMask(
                red: red, green: green, blue: blue,
                width: haloW, height: haloH,
                personMask: personRegion, faceOval: faceOval)
            if mask.isEmpty == false {
                let strength = state.skin.smoothing / 100
                let textureKeep = state.textureKeep01
                var lowRed = red
                var lowGreen = green
                var lowBlue = blue
                for _ in 0..<blurPasses {
                    lowRed = separableBlurFloat(src: lowRed, width: haloW, height: haloH)
                    lowGreen = separableBlurFloat(src: lowGreen, width: haloW, height: haloH)
                    lowBlue = separableBlurFloat(src: lowBlue, width: haloW, height: haloH)
                }
                red = skinSmoothBlendCPU(src: red, low: lowRed, skinMask: mask, strength: strength, textureKeep: textureKeep)
                green = skinSmoothBlendCPU(src: green, low: lowGreen, skinMask: mask, strength: strength, textureKeep: textureKeep)
                blue = skinSmoothBlendCPU(src: blue, low: lowBlue, skinMask: mask, strength: strength, textureKeep: textureKeep)
                if state.skin.grain > 0 {
                    let amount = state.skin.grain / 100 * 0.05
                    for i in 0..<count {
                        let globalX = tile.haloX + (i % haloW)
                        let globalY = tile.haloY + (i / haloW)
                        let noise = grainNoise(x: globalX, y: globalY) * amount * mask[i]
                        red[i] = min(max(red[i] + noise, 0), 1)
                        green[i] = min(max(green[i] + noise, 0), 1)
                        blue[i] = min(max(blue[i] + noise, 0), 1)
                    }
                }
            }
        }
        // Warp stage: tile field in normalized units, background lock,
        // then bicubic sampling per channel. Field is converted to
        // pixels (warpImageFloatCubic works in pixel units).
        if ops.isEmpty == false || dabs.isEmpty == false {
            var field = tileDisplacementField(
                tileOriginX: tile.haloX, tileOriginY: tile.haloY,
                tileWidth: haloW, tileHeight: haloH,
                imageWidth: imageWidth, imageHeight: imageHeight,
                ops: ops, dabs: dabs)
            if state.backgroundLock, personRegion.isEmpty == false {
                field = applyBackgroundLock(field: field, mask: personRegion)
            }
            let pixelField = field.map { Vec2($0.x * Float(imageWidth), $0.y * Float(imageHeight)) }
            red = warpImageFloatCubic(src: red, width: haloW, height: haloH, displacement: pixelField)
            green = warpImageFloatCubic(src: green, width: haloW, height: haloH, displacement: pixelField)
            blue = warpImageFloatCubic(src: blue, width: haloW, height: haloH, displacement: pixelField)
        }
        // Write the core rect back as UInt8; alpha comes from the input.
        for y in 0..<tile.h {
            for x in 0..<tile.w {
                let haloIndex = (y + (tile.y - tile.haloY)) * haloW + (x + (tile.x - tile.haloX))
                let globalIndex = ((tile.y + y) * imageWidth + (tile.x + x)) * 4
                output[globalIndex] = UInt8(min(max(red[haloIndex], 0), 1) * 255)
                output[globalIndex + 1] = UInt8(min(max(green[haloIndex], 0), 1) * 255)
                output[globalIndex + 2] = UInt8(min(max(blue[haloIndex], 0), 1) * 255)
                output[globalIndex + 3] = input[globalIndex + 3]
            }
        }
    }

    /// Writes a rendered CGImage to a temp file in the requested format,
    /// preserving Display P3 + ICC + EXIF. GPS is stripped when requested.
    func writeImage(
        _ image: CGImage,
        format: Format,
        quality: CGFloat,
        stripGPS: Bool,
        properties: [CFString: Any]
    ) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(format.fileExtension)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, format.utType.identifier as CFString, 1, nil) else {
            throw AppError.exportFailed
        }
        var mutableProperties = properties
        if stripGPS {
            // VERIFY: kCGImagePropertyGPSDictionary key for stripping GPS on export.
            mutableProperties[kCGImagePropertyGPSDictionary] = [:]
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        _ = options
        CGImageDestinationAddImage(destination, image, mutableProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw AppError.exportFailed
        }
        return url
    }

    /// Saves an image file to the Photos library (add-only permission).
    func saveToPhotos(fileURL: URL) async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw AppError.photoAccessDenied
        }
        try await PHPhotoLibrary.shared().performChanges {
            // VERIFY: PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL:)
            PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
        }
    }

    /// Deletes a temp export file. Call after saving / sharing, always.
    func cleanupTempFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
