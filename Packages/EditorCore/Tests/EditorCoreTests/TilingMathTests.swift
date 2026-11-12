// What: Tests export tiling counts, exact sizes, halo overlap, and tiny images.
// Inputs/Outputs: Image size + tile size + halo in; tile rect assertions out.
// Threading: XCTest, single thread.
import XCTest
@testable import EditorCore

final class TilingMathTests: XCTestCase {

    func testExactTilesNoHalo() {
        let tiles = tileRects(imageWidth: 4096, imageHeight: 4096, tileSize: 2048, halo: 0)
        XCTAssertEqual(tiles.count, 4)
        for tile in tiles {
            XCTAssertEqual(tile.w, 2048)
            XCTAssertEqual(tile.h, 2048)
            XCTAssertEqual(tile.haloW, 2048)
            XCTAssertEqual(tile.haloH, 2048)
        }
        XCTAssertEqual(tiles[0].x, 0)
        XCTAssertEqual(tiles[0].y, 0)
        XCTAssertEqual(tiles[1].x, 2048)
        XCTAssertEqual(tiles[1].y, 0)
        XCTAssertEqual(tiles[2].x, 0)
        XCTAssertEqual(tiles[2].y, 2048)
        XCTAssertEqual(tiles[3].x, 2048)
        XCTAssertEqual(tiles[3].y, 2048)
    }

    func testHaloOverlap() {
        let tiles = tileRects(imageWidth: 4096, imageHeight: 4096, tileSize: 2048, halo: 64)
        XCTAssertEqual(tiles.count, 4)
        // Left tile's halo extends 64px into the right tile's core.
        XCTAssertEqual(tiles[0].haloW, 2048 + 64)
        // Right tile's halo starts 64px before its core.
        XCTAssertEqual(tiles[1].haloX, 2048 - 64)
        XCTAssertLessThan(tiles[1].haloX, tiles[0].haloX + tiles[0].haloW)
        // Bottom tile's halo starts 64px before its core.
        XCTAssertEqual(tiles[2].haloY, 2048 - 64)
    }

    func testHaloClampedAtImageEdge() {
        let tiles = tileRects(imageWidth: 4096, imageHeight: 4096, tileSize: 2048, halo: 64)
        XCTAssertEqual(tiles[0].haloX, 0)
        XCTAssertEqual(tiles[0].haloY, 0)
        XCTAssertEqual(tiles[3].haloX + tiles[3].haloW, 4096)
        XCTAssertEqual(tiles[3].haloY + tiles[3].haloH, 4096)
    }

    func testTinyImageIsOneTile() {
        let tiles = tileRects(imageWidth: 100, imageHeight: 80, tileSize: 2048, halo: 16)
        XCTAssertEqual(tiles.count, 1)
        XCTAssertEqual(tiles[0].x, 0)
        XCTAssertEqual(tiles[0].y, 0)
        XCTAssertEqual(tiles[0].w, 100)
        XCTAssertEqual(tiles[0].h, 80)
        XCTAssertEqual(tiles[0].haloW, 100)
        XCTAssertEqual(tiles[0].haloH, 80)
    }

    func testPartialEdgeTiles() {
        let tiles = tileRects(imageWidth: 3000, imageHeight: 1000, tileSize: 2048, halo: 0)
        XCTAssertEqual(tiles.count, 2)
        XCTAssertEqual(tiles[0].w, 2048)
        XCTAssertEqual(tiles[1].w, 952)
        XCTAssertEqual(tiles[1].x, 2048)
    }

    func testCoreTilesDoNotOverlap() {
        let tiles = tileRects(imageWidth: 5000, imageHeight: 5000, tileSize: 2048, halo: 32)
        for i in 0..<tiles.count {
            for j in (i + 1)..<tiles.count {
                let a = tiles[i]
                let b = tiles[j]
                let overlapsX = a.x < b.x + b.w && b.x < a.x + a.w
                let overlapsY = a.y < b.y + b.h && b.y < a.y + a.h
                XCTAssertFalse(overlapsX && overlapsY, "core tiles \(i) and \(j) overlap")
            }
        }
    }

    func testInvalidSizesReturnEmpty() {
        XCTAssertTrue(tileRects(imageWidth: 0, imageHeight: 100, tileSize: 2048, halo: 0).isEmpty)
        XCTAssertTrue(tileRects(imageWidth: 100, imageHeight: 100, tileSize: 0, halo: 0).isEmpty)
    }
}
