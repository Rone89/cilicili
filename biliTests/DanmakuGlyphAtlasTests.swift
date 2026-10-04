import Metal
import UIKit
import XCTest

@testable import bili

@MainActor
final class DanmakuGlyphAtlasTests: XCTestCase {
    func testRepeatedLayoutReusesGlyphSlotsAndRasterization() throws {
        let atlas = try makeAtlas(pageSize: 128, maximumPages: 2)
        let font = UIFont.systemFont(ofSize: 18)

        let first = try XCTUnwrap(atlas.layout(text: "Cache 123", font: font, scale: 2))
        let firstGlyphCount = atlas.glyphCount
        let firstUsedPixels = atlas.usedPixels
        let firstRasterizationCount = atlas.rasterizationCount

        let second = try XCTUnwrap(atlas.layout(text: "Cache 123", font: font, scale: 2))

        XCTAssertEqual(second, first)
        XCTAssertGreaterThan(firstGlyphCount, 0)
        XCTAssertEqual(atlas.glyphCount, firstGlyphCount)
        XCTAssertEqual(atlas.usedPixels, firstUsedPixels)
        XCTAssertEqual(atlas.rasterizationCount, firstRasterizationCount)
    }

    func testFontTraitsSizeAndScaleProduceDistinctGlyphEntries() throws {
        let atlas = try makeAtlas(pageSize: 256, maximumPages: 2)
        let regular = UIFont.systemFont(ofSize: 18)
        let bold = UIFont.systemFont(ofSize: 18, weight: .bold)

        _ = try XCTUnwrap(atlas.layout(text: "A", font: regular, scale: 1))
        let afterBase = atlas.rasterizationCount
        _ = try XCTUnwrap(atlas.layout(text: "A", font: bold, scale: 1))
        let afterTraits = atlas.rasterizationCount
        _ = try XCTUnwrap(atlas.layout(text: "A", font: UIFont.systemFont(ofSize: 22), scale: 1))
        let afterSize = atlas.rasterizationCount
        _ = try XCTUnwrap(atlas.layout(text: "A", font: regular, scale: 2))

        XCTAssertGreaterThan(afterTraits, afterBase)
        XCTAssertGreaterThan(afterSize, afterTraits)
        XCTAssertGreaterThan(atlas.rasterizationCount, afterSize)
        XCTAssertEqual(atlas.glyphCount, atlas.rasterizationCount)
    }

    func testCoreTextShapesMultilingualTextAndPreservesWhitespaceAdvance() throws {
        let atlas = try makeAtlas(pageSize: 512, maximumPages: 2)
        let font = UIFont.systemFont(ofSize: 18)

        let multilingual = try XCTUnwrap(
            atlas.layout(text: "A中123，。", font: font, scale: 2)
        )
        let withoutSpace = try XCTUnwrap(atlas.layout(text: "AB", font: font, scale: 2))
        let withSpace = try XCTUnwrap(atlas.layout(text: "A B", font: font, scale: 2))

        XCTAssertGreaterThanOrEqual(multilingual.glyphs.count, 6)
        XCTAssertGreaterThan(multilingual.size.width, 0)
        XCTAssertGreaterThan(multilingual.size.height, 0)
        XCTAssertTrue(multilingual.glyphs.allSatisfy { atlas.textures.indices.contains($0.pageIndex) })
        XCTAssertGreaterThan(withSpace.size.width, withoutSpace.size.width)
    }

    func testFullAtlasRejectsWholeLayoutAndResetAllowsReuse() throws {
        let atlas = try makeAtlas(pageSize: 64, maximumPages: 1)
        let font = UIFont.systemFont(ofSize: 16)
        let first = try XCTUnwrap(atlas.layout(text: "A", font: font, scale: 2))
        let glyphCountBeforeRejection = atlas.glyphCount
        let usedPixelsBeforeRejection = atlas.usedPixels

        var didReject = false
        for character in "BCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" {
            if atlas.layout(text: String(character), font: font, scale: 2) == nil {
                didReject = true
                break
            }
        }

        XCTAssertTrue(didReject)
        XCTAssertGreaterThan(atlas.rejectedGlyphs, 0)
        XCTAssertLessThanOrEqual(atlas.usedPixels, atlas.capacityPixels)

        let stable = try XCTUnwrap(atlas.layout(text: "A", font: font, scale: 2))
        XCTAssertEqual(stable, first)
        XCTAssertGreaterThanOrEqual(atlas.glyphCount, glyphCountBeforeRejection)
        XCTAssertGreaterThanOrEqual(atlas.usedPixels, usedPixelsBeforeRejection)

        atlas.reset()

        XCTAssertEqual(atlas.glyphCount, 0)
        XCTAssertEqual(atlas.usedPixels, 0)
        XCTAssertEqual(atlas.rejectedGlyphs, 0)
        XCTAssertEqual(atlas.rasterizationCount, 0)
        XCTAssertNotNil(atlas.layout(text: "A", font: font, scale: 2))
    }

    func testGlyphPixelsUseTopLeftRowsAndTwoPixelTransparentPadding() throws {
        let pageSize = 128
        let atlas = try makeAtlas(pageSize: pageSize, maximumPages: 1)
        let layout = try XCTUnwrap(
            atlas.layout(text: "L", font: UIFont.monospacedSystemFont(ofSize: 30, weight: .regular), scale: 2)
        )
        let placement = try XCTUnwrap(layout.glyphs.first)
        let texture = try XCTUnwrap(atlas.textures[safe: placement.pageIndex])
        guard texture.storageMode == .shared else {
            throw XCTSkip("CPU texture reads are unavailable for this Metal storage mode")
        }

        let x = Int((placement.uvRect.x * Float(pageSize)).rounded())
        let y = Int((placement.uvRect.y * Float(pageSize)).rounded())
        let width = Int((placement.uvRect.z * Float(pageSize)).rounded())
        let height = Int((placement.uvRect.w * Float(pageSize)).rounded())
        var pixels = [UInt8](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBytes { bytes in
            texture.getBytes(
                bytes.baseAddress!,
                bytesPerRow: width,
                from: MTLRegionMake2D(x, y, width, height),
                mipmapLevel: 0
            )
        }

        let occupiedRows = (0..<height).filter { row in
            pixels[(row * width)..<(row * width + width)].contains { $0 > 0 }
        }
        guard let firstOccupiedRow = occupiedRows.first, let lastOccupiedRow = occupiedRows.last else {
            XCTFail("Rasterized glyph has no pixels")
            return
        }
        for row in 0..<2 {
            XCTAssertTrue(pixels[(row * width)..<(row * width + width)].allSatisfy { $0 == 0 })
            let lastRow = height - row - 1
            XCTAssertTrue(pixels[(lastRow * width)..<(lastRow * width + width)].allSatisfy { $0 == 0 })
        }
        for row in 0..<height {
            XCTAssertTrue(pixels[(row * width)..<(row * width + 2)].allSatisfy { $0 == 0 })
            XCTAssertTrue(pixels[(row * width + width - 2)..<(row * width + width)].allSatisfy { $0 == 0 })
        }

        let inkRows = firstOccupiedRow..<lastOccupiedRow + 1
        let topWidth = maximumInkWidth(
            in: pixels,
            width: width,
            rows: Array(inkRows.prefix(max(1, inkRows.count / 2)))
        )
        let bottomWidth = maximumInkWidth(
            in: pixels,
            width: width,
            rows: Array(inkRows.suffix(max(1, inkRows.count / 2)))
        )
        XCTAssertGreaterThan(bottomWidth, topWidth)
    }

    private func makeAtlas(pageSize: Int, maximumPages: Int) throws -> DanmakuGlyphAtlas {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable on this test runtime")
        }
        return try XCTUnwrap(
            DanmakuGlyphAtlas(device: device, pageSize: pageSize, maximumPages: maximumPages)
        )
    }

    private func maximumInkWidth(in pixels: [UInt8], width: Int, rows: [Int]) -> Int {
        rows.map { row in
            let occupied = (0..<width).filter { pixels[row * width + $0] > 0 }
            guard let first = occupied.first, let last = occupied.last else { return 0 }
            return last - first + 1
        }.max() ?? 0
    }
}

extension Array {
    fileprivate subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
