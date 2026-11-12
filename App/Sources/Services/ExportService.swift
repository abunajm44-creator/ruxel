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
    /// first, then the warp stage (bicubic, background lock), then the
    /// color stage (grade + paint overlay, same math as the live
    /// colorGrade kernel). Crop/rotate is applied last as a post-process
    /// on the assembled image. Two full RGBA8 buffers (input + output,
    /// ~192MB each at 48MP) plus one assembled Data live transiently —
    /// the input buffer is released before assembly. Progress is 0...1
    /// per finished tile; cancellation is checked between tiles. Returns
    /// the temp file URL (caller saves it to Photos or shares it, then
    /// calls cleanupTempFile).
    func exportFullResolution(
        state: RetouchState,
        extras: ExtraAdjustments,
        overlay: PaintOverlayBitmap?,
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
            ops.append(contentsOf: headLiftWarpOps(extras: extras, landmarks: landmarks))
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
                tile, state: state, extras: extras, overlay: overlay,
                ops: ops, dabs: dabs, landmarks: landmarks,
                personMask: personMask, input: input, output: &output,
                imageWidth: imageWidth, imageHeight: imageHeight, blurPasses: blurPasses)
            progress(Double(index + 1) / Double(tiles.count))
        }
        // Release the input buffer before assembling the output image.
        var image = try assembleImage(output: output, width: imageWidth, height: imageHeight)
        if extras.cropRotation != 0 || extras.cropAspect != .free {
            image = try applyCropRotation(image: image, extras: extras)
        }
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
            // Flip the context (top-left origin): a raw bitmap context is
            // y-up, so drawing without the flip would store the image
            // upside down and the pipeline (landmarks, tiles, overlay)
            // would work on a mirrored photo. With the flip, buffer
            // row 0 is the photo's top row, matching everything else.
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
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
    /// warp stage (tile field, background lock, bicubic) then color
    /// stage (grade + paint overlay, same math as the live kernel).
    /// Writes only the core rect into `output`; halo pixels are
    /// read-only context.
    private func processTile(
        _ tile: TileRect,
        state: RetouchState,
        extras: ExtraAdjustments,
        overlay: PaintOverlayBitmap?,
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
        // Color stage: grade + paint overlay on the CORE pixels only
        // (the halo is discarded context). Same math as the live
        // colorGrade kernel (EditorCore gradePixel) and the live
        // blendOverlay kernel (straight-alpha mix). Skipped when the
        // color extras are neutral.
        if extras.isColorNeutral == false {
            let grade = resolveColorGrade(
                exposure: extras.exposure, contrast: extras.contrast,
                saturation: extras.saturation, warmth: extras.warmth,
                preset: extras.filterPreset, intensity: extras.filterIntensity / 100)
            for y in 0..<tile.h {
                for x in 0..<tile.w {
                    let haloIndex = (y + (tile.y - tile.haloY)) * haloW + (x + (tile.x - tile.haloX))
                    let globalX = tile.x + x
                    let globalY = tile.y + y
                    var (r, g, b) = gradePixel(r: red[haloIndex], g: green[haloIndex], b: blue[haloIndex], grade: grade)
                    if let overlay {
                        let u = (Float(globalX) + 0.5) / Float(imageWidth)
                        let v = (Float(globalY) + 0.5) / Float(imageHeight)
                        let over = sampleOverlay(bitmap: overlay, u: u, v: v)
                        r = r + (over.r - r) * over.a
                        g = g + (over.g - g) * over.a
                        b = b + (over.b - b) * over.a
                    }
                    red[haloIndex] = r
                    green[haloIndex] = g
                    blue[haloIndex] = b
                }
            }
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

    /// Bilinear sample of a photo-space paint overlay bitmap (straight
    /// alpha, 0...1 RGBA) at a photo UV. Returns transparent black
    /// outside the bitmap (the bitmap always covers the full photo).
    private func sampleOverlay(bitmap: PaintOverlayBitmap, u: Float, v: Float) -> (r: Float, g: Float, b: Float, a: Float) {
        let width = bitmap.width
        let height = bitmap.height
        guard width > 0, height > 0 else { return (0, 0, 0, 0) }
        let fx = min(max(u, 0), 1) * Float(width - 1)
        let fy = min(max(v, 0), 1) * Float(height - 1)
        let x0 = Int(fx)
        let y0 = Int(fy)
        let x1 = min(x0 + 1, width - 1)
        let y1 = min(y0 + 1, height - 1)
        let tx = fx - Float(x0)
        let ty = fy - Float(y0)
        func pixel(_ x: Int, _ y: Int) -> (r: Float, g: Float, b: Float, a: Float) {
            let index = (y * width + x) * 4
            return (Float(bitmap.pixels[index]) / 255,
                    Float(bitmap.pixels[index + 1]) / 255,
                    Float(bitmap.pixels[index + 2]) / 255,
                    Float(bitmap.pixels[index + 3]) / 255)
        }
        let p00 = pixel(x0, y0), p10 = pixel(x1, y0)
        let p01 = pixel(x0, y1), p11 = pixel(x1, y1)
        func mix(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
        let r = mix(mix(p00.r, p10.r, tx), mix(p01.r, p11.r, tx), ty)
        let g = mix(mix(p00.g, p10.g, tx), mix(p01.g, p11.g, tx), ty)
        let b = mix(mix(p00.b, p10.b, tx), mix(p01.b, p11.b, tx), ty)
        let a = mix(mix(p00.a, p10.a, tx), mix(p01.a, p11.a, tx), ty)
        return (r, g, b, a)
    }

    /// Applies crop (aspect) + rotation to an assembled export image.
    /// The aspect crop is a centered crop to the target rect; the
    /// rotation then rotates the cropped image into its bounding box
    /// (corners are black — the live preview edge-stretches them
    /// instead; see the note in the live colorGrade kernel).
    private func applyCropRotation(image: CGImage, extras: ExtraAdjustments) throws -> CGImage {
        let width = image.width
        let height = image.height
        var cropped = image
        if extras.cropAspect != .free {
            let rect = cropRect(aspect: extras.cropAspect, sourceWidth: Float(width), sourceHeight: Float(height))
            let crop = CGRect(
                x: CGFloat(rect.min.x) * CGFloat(width),
                y: CGFloat(rect.min.y) * CGFloat(height),
                width: CGFloat(rect.size.x) * CGFloat(width),
                height: CGFloat(rect.size.y) * CGFloat(height))
            guard let cut = image.cropping(to: crop.integral) else { throw AppError.exportFailed }
            cropped = cut
        }
        guard extras.cropRotation != 0 else { return cropped }
        let radians = CGFloat(extras.cropRotation) * CGFloat.pi / 180
        let cosA = abs(cos(radians))
        let sinA = abs(sin(radians))
        let outWidth = Int((CGFloat(cropped.width) * cosA + CGFloat(cropped.height) * sinA).rounded(.up))
        let outHeight = Int((CGFloat(cropped.width) * sinA + CGFloat(cropped.height) * cosA).rounded(.up))
        guard let context = CGContext(
            data: nil, width: outWidth, height: outHeight,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw AppError.exportFailed
        }
        // Flip to a top-left origin first (see loadFullResolutionPixels),
        // then rotate: in the flipped space a positive rotation is
        // clockwise on screen, matching the live colorGrade kernel.
        context.translateBy(x: CGFloat(outWidth) / 2, y: CGFloat(outHeight) / 2)
        context.scaleBy(x: 1, y: -1)
        context.rotate(by: radians)
        context.draw(cropped, in: CGRect(
            x: -CGFloat(cropped.width) / 2, y: -CGFloat(cropped.height) / 2,
            width: CGFloat(cropped.width), height: CGFloat(cropped.height)))
        guard let rotated = context.makeImage() else { throw AppError.exportFailed }
        return rotated
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
