// What: Export tiling: split a large image into tiles with a halo overlap.
// Inputs/Outputs: Image size + tile size + halo in; core tile rects with halo rects out.
// Threading: Pure functions; safe on any thread.
import Foundation

/// One export tile: a core rect plus the halo-expanded rect to render.
/// All values are integer pixels in image coordinates, origin top-left.
/// The halo rect is clamped to the image bounds.
public struct TileRect: Codable, Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var w: Int
    public var h: Int
    public var haloX: Int
    public var haloY: Int
    public var haloW: Int
    public var haloH: Int

    public init(x: Int, y: Int, w: Int, h: Int, haloX: Int, haloY: Int, haloW: Int, haloH: Int) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.haloX = haloX
        self.haloY = haloY
        self.haloW = haloW
        self.haloH = haloH
    }
}

/// Tiles for an image, core tiles of `tileSize` with a `halo` overlap.
/// Halo = kernel radius + max displacement, so a tile's halo rect
/// contains every source pixel its output can sample from. Adjacent
/// tiles' halo rects overlap; core rects never do. A tiny image yields
/// exactly one tile. Returns [] for non-positive sizes.
public func tileRects(
    imageWidth: Int,
    imageHeight: Int,
    tileSize: Int = 2048,
    halo: Int = 0
) -> [TileRect] {
    guard imageWidth > 0, imageHeight > 0, tileSize > 0 else { return [] }
    let clampedHalo = max(halo, 0)
    var tiles: [TileRect] = []
    var y = 0
    while y < imageHeight {
        let h = min(tileSize, imageHeight - y)
        var x = 0
        while x < imageWidth {
            let w = min(tileSize, imageWidth - x)
            let haloX = max(x - clampedHalo, 0)
            let haloY = max(y - clampedHalo, 0)
            let haloRight = min(x + w + clampedHalo, imageWidth)
            let haloBottom = min(y + h + clampedHalo, imageHeight)
            tiles.append(TileRect(
                x: x,
                y: y,
                w: w,
                h: h,
                haloX: haloX,
                haloY: haloY,
                haloW: haloRight - haloX,
                haloH: haloBottom - haloY
            ))
            x += w
        }
        y += h
    }
    return tiles
}
