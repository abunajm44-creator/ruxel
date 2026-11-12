// OverlayBuilder — rasterizes color-brush + sparkle PaintStrokes into a
// bitmap in PHOTO space, for the live overlay-blend kernel and CPU export.
// What: strokes (overlay-normalized points) + photo rect -> RGBA bitmap.
// The overlay is rasterized in photo space (not overlay space) so the
// render kernels and export can sample it directly at the photo UV,
// with no rect parameter anywhere in the render path. Strokes painted
// outside the photo rect (on the canvas letterbox) are clipped.
// Threading: pure CPU work; call off the render thread, then upload.
import CoreGraphics
import Foundation
import EditorCore
import Metal
import UIKit

/// One rasterized paint overlay: straight (non-premultiplied) alpha RGBA.
struct PaintOverlayBitmap: Equatable, Sendable {
    var pixels: [UInt8]
    var width: Int
    var height: Int
}

/// The photo's rect inside the canvas (overlay), in overlay-normalized
/// coordinates (0...1). The canvas shows the photo aspect-fit, centered.
func photoRectInOverlay(imageSize: CGSize, canvasSize: CGSize) -> CGRect {
    guard imageSize.width > 0, imageSize.height > 0,
          canvasSize.width > 0, canvasSize.height > 0 else {
        return CGRect(x: 0, y: 0, width: 1, height: 1)
    }
    let imageAspect = imageSize.width / imageSize.height
    let canvasAspect = canvasSize.width / canvasSize.height
    if imageAspect >= canvasAspect {
        // Photo is wider than the canvas: full width, letterboxed top/bottom.
        let h = canvasAspect / imageAspect
        return CGRect(x: 0, y: (1 - h) / 2, width: 1, height: h)
    } else {
        // Photo is taller than the canvas: full height, letterboxed sides.
        let w = imageAspect / canvasAspect
        return CGRect(x: (1 - w) / 2, y: 0, width: w, height: 1)
    }
}

/// Rasterizes the color + sparkle strokes into a photo-space bitmap.
/// - `extras`: stroke data + brush intensities (0...100).
/// - `imageSize`: the photo's pixel size (determines bitmap aspect).
/// - `canvasSize`: the canvas size in points (determines the photo rect
///   and the brush circularity correction).
/// - `outputLongSide`: bitmap long side in pixels (1024 is plenty for a
///   paint overlay sampled with linear filtering).
/// Returns nil when there is nothing to paint.
func rasterizeOverlayBitmap(
    extras: ExtraAdjustments,
    imageSize: CGSize,
    canvasSize: CGSize,
    outputLongSide: Int = 1024
) -> PaintOverlayBitmap? {
    guard extras.colorBrushStrokes.isEmpty == false
        || extras.sparkleStrokes.isEmpty == false else { return nil }
    guard imageSize.width > 0, imageSize.height > 0,
          canvasSize.width > 0, canvasSize.height > 0 else { return nil }
    let rect = photoRectInOverlay(imageSize: imageSize, canvasSize: canvasSize)
    guard rect.width > 0, rect.height > 0 else { return nil }
    let imageAspect = imageSize.width / imageSize.height
    let bitmapWidth: Int
    let bitmapHeight: Int
    if imageAspect >= 1 {
        bitmapWidth = outputLongSide
        bitmapHeight = max(Int(CGFloat(outputLongSide) / imageAspect), 1)
    } else {
        bitmapHeight = outputLongSide
        bitmapWidth = max(Int(CGFloat(outputLongSide) * imageAspect), 1)
    }
    let canvasAspect = canvasSize.width / canvasSize.height
    var pixels = [UInt8](repeating: 0, count: bitmapWidth * bitmapHeight * 4)
    let drawn = pixels.withUnsafeMutableBytes { bytes in
        guard let context = CGContext(
            data: bytes.baseAddress, width: bitmapWidth, height: bitmapHeight,
            bitsPerComponent: 8, bytesPerRow: bitmapWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            // Straight alpha: the blend kernel mixes by over.a, so the
            // stored RGB must NOT be premultiplied.
            bitmapInfo: CGImageAlphaInfo.last.rawValue) else { return false }
        // CoreGraphics has a bottom-left origin; flip so bitmap row 0 is
        // the TOP of the photo (matching the texture's UV space).
        context.translateBy(x: 0, y: CGFloat(bitmapHeight))
        context.scaleBy(x: 1, y: -1)
        for stroke in extras.colorBrushStrokes {
            let alpha = stroke.strength * (extras.colorBrushIntensity / 100)
            drawColorStroke(stroke, alpha: alpha, in: context,
                            bitmapWidth: bitmapWidth, bitmapHeight: bitmapHeight,
                            photoRect: rect, canvasAspect: canvasAspect)
        }
        for stroke in extras.sparkleStrokes {
            let alpha = stroke.strength * (extras.sparkleIntensity / 100)
            drawSparkleStroke(stroke, alpha: alpha, style: extras.sparkleStyle,
                              in: context, bitmapWidth: bitmapWidth,
                              bitmapHeight: bitmapHeight, photoRect: rect,
                              canvasAspect: canvasAspect)
        }
        return true
    }
    guard drawn else { return nil }
    return PaintOverlayBitmap(pixels: pixels, width: bitmapWidth, height: bitmapHeight)
}

/// Maps an overlay-normalized point to bitmap pixels (photo space).
private func photoPoint(
    _ point: Vec2, bitmapWidth: Int, bitmapHeight: Int,
    photoRect: CGRect
) -> CGPoint {
    let uvX = (CGFloat(point.x) - photoRect.minX) / photoRect.width
    let uvY = (CGFloat(point.y) - photoRect.minY) / photoRect.height
    return CGPoint(x: uvX * CGFloat(bitmapWidth), y: uvY * CGFloat(bitmapHeight))
}

/// Dab radius in bitmap pixels, circular on screen: `size` is a fraction
/// of the OVERLAY width, so in photo pixels it is size * bitmapWidth /
/// photoRect.width (x) and the aspect-corrected equivalent (y); the two
/// are equal when the bitmap aspect matches the photo aspect.
private func dabRadiusPixels(
    size: Float, bitmapWidth: Int, bitmapHeight: Int,
    photoRect: CGRect, canvasAspect: CGFloat
) -> (rx: CGFloat, ry: CGFloat) {
    let rx = CGFloat(size) / 2 / photoRect.width * CGFloat(bitmapWidth)
    let ry = CGFloat(size) / 2 * canvasAspect / photoRect.height * CGFloat(bitmapHeight)
    return (rx, ry)
}

/// Interpolated dab centers along a stroke polyline, spaced at most
/// half a radius apart so the stroke is continuous.
private func dabCenters(
    stroke: PaintStroke, bitmapWidth: Int, bitmapHeight: Int, photoRect: CGRect
) -> [CGPoint] {
    let points = stroke.points.map {
        photoPoint($0, bitmapWidth: bitmapWidth, bitmapHeight: bitmapHeight, photoRect: photoRect)
    }
    guard points.count > 1 else { return points }
    var centers: [CGPoint] = [points[0]]
    for index in 1..<points.count {
        let from = points[index - 1]
        let to = points[index]
        let distance = hypot(to.x - from.x, to.y - from.y)
        // Step in pixels; radius is computed by the caller, so use a
        // fixed small step here and let the caller skip if too dense.
        let steps = max(Int(distance / 4), 1)
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            centers.append(CGPoint(x: from.x + (to.x - from.x) * t,
                                   y: from.y + (to.y - from.y) * t))
        }
    }
    return centers
}

/// One soft radial-gradient disc (white core fading to transparent),
/// reused as the stamp for color dabs and glow sparkles.
private func softDiscGradient() -> CGGradient? {
    let colors = [
        CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.4),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0)
    ] as CFArray
    return CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1])
}

/// Draws one color-brush stroke as soft discs in the stroke color.
private func drawColorStroke(
    _ stroke: PaintStroke, alpha: Float,
    in context: CGContext, bitmapWidth: Int, bitmapHeight: Int,
    photoRect: CGRect, canvasAspect: CGFloat
) {
    guard alpha > 0, stroke.points.isEmpty == false else { return }
    guard let gradient = softDiscGradient() else { return }
    let (rx, ry) = dabRadiusPixels(size: stroke.size, bitmapWidth: bitmapWidth,
                                    bitmapHeight: bitmapHeight, photoRect: photoRect,
                                    canvasAspect: canvasAspect)
    guard rx > 0, ry > 0 else { return }
    let color = CGColor(red: CGFloat(stroke.red), green: CGFloat(stroke.green),
                        blue: CGFloat(stroke.blue), alpha: CGFloat(alpha))
    // Tint the white gradient with the stroke color: draw the gradient
    // clipped to the color using source-in blending per dab.
    for center in dabCenters(stroke: stroke, bitmapWidth: bitmapWidth, bitmapHeight: bitmapHeight, photoRect: photoRect) {
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.scaleBy(x: rx, y: ry)
        context.beginPath()
        context.addEllipse(in: CGRect(x: -1, y: -1, width: 2, height: 2))
        context.clip()
        context.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0,
                                   endCenter: .zero, endRadius: 1, options: [])
        context.setBlendMode(.sourceIn)
        context.setFillColor(color)
        context.fill(CGRect(x: -1, y: -1, width: 2, height: 2))
        context.restoreGState()
    }
}

/// Draws one sparkle stroke: glow = soft disc, glitter/star = 4-point
/// star paths in the stroke color (default white-ish when unset).
private func drawSparkleStroke(
    _ stroke: PaintStroke, alpha: Float, style: ExtraAdjustments.SparkleStyle,
    in context: CGContext, bitmapWidth: Int, bitmapHeight: Int,
    photoRect: CGRect, canvasAspect: CGFloat
) {
    guard alpha > 0, stroke.points.isEmpty == false else { return }
    let (rx, ry) = dabRadiusPixels(size: stroke.size, bitmapWidth: bitmapWidth,
                                    bitmapHeight: bitmapHeight, photoRect: photoRect,
                                    canvasAspect: canvasAspect)
    guard rx > 0, ry > 0 else { return }
    let red = CGFloat(stroke.red), green = CGFloat(stroke.green), blue = CGFloat(stroke.blue)
    let color = CGColor(red: red, green: green, blue: blue, alpha: CGFloat(alpha))
    for center in dabCenters(stroke: stroke, bitmapWidth: bitmapWidth, bitmapHeight: bitmapHeight, photoRect: photoRect) {
        switch style {
        case .glow:
            guard let gradient = softDiscGradient() else { continue }
            context.saveGState()
            context.translateBy(x: center.x, y: center.y)
            context.scaleBy(x: rx, y: ry)
            context.beginPath()
            context.addEllipse(in: CGRect(x: -1, y: -1, width: 2, height: 2))
            context.clip()
            context.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0,
                                       endCenter: .zero, endRadius: 1, options: [])
            context.setBlendMode(.sourceIn)
            context.setFillColor(color)
            context.fill(CGRect(x: -1, y: -1, width: 2, height: 2))
            context.restoreGState()
        case .glitter, .star:
            // 4-point star: 8 vertices alternating tip / valley, starting
            // at the top tip and going clockwise.
            let spike: CGFloat = style == .star ? 1.0 : 0.45
            context.saveGState()
            context.translateBy(x: center.x, y: center.y)
            context.setFillColor(color)
            context.beginPath()
            for k in 0..<8 {
                let angle = -CGFloat.pi / 2 + CGFloat(k) * CGFloat.pi / 4
                let radius: CGFloat = k.isMultiple(of: 2) ? spike : 0.18
                let point = CGPoint(x: cos(angle) * rx * radius,
                                    y: sin(angle) * ry * radius)
                if k == 0 { context.move(to: point) } else { context.addLine(to: point) }
            }
            context.closePath()
            context.fillPath()
            context.restoreGState()
        }
    }
}

/// Uploads a rasterized overlay bitmap to a Metal texture (RGBA8Unorm,
/// shader-read only). Returns nil when the device cannot make it.
func makeOverlayTexture(bitmap: PaintOverlayBitmap, device: MTLDevice) -> MTLTexture? {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm, width: bitmap.width, height: bitmap.height, mipmapped: false)
    descriptor.usage = [.shaderRead]
    guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
    bitmap.pixels.withUnsafeBytes { bytes in
        guard let baseAddress = bytes.baseAddress else { return }
        texture.replace(region: MTLRegionMake2D(0, 0, bitmap.width, bitmap.height),
                        mipmapLevel: 0, withBytes: baseAddress,
                        bytesPerRow: bitmap.width * 4)
    }
    return texture
}
