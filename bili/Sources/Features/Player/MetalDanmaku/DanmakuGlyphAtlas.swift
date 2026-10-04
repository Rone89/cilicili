import CoreText
import Metal
import UIKit

struct DanmakuGlyphPlacement: Equatable, Sendable {
    let pageIndex: Int
    let uvRect: SIMD4<Float>
    let offset: CGPoint
    let size: CGSize
}

struct DanmakuGlyphLayout: Equatable, Sendable {
    let size: CGSize
    let glyphs: [DanmakuGlyphPlacement]
}

@MainActor
final class DanmakuGlyphAtlas {
    private static let minimumPageSize = 8
    private static let maximumPageSize = 4096
    private static let maximumPageCount = 64
    private static let maximumTextUTF16Count = 4096
    private static let maximumLayoutGlyphCount = 512
    private static let maximumLayoutWidth: CGFloat = 65_536
    private static let maximumLayoutHeight: CGFloat = 4_096
    // An extra pixel accommodates CoreText hinting outside its design bounds.
    private static let paddingPixels = 3

    private struct GlyphKey: Hashable {
        let fontIdentity: String
        let fontSizeBits: UInt64
        let fontVariation: String
        let symbolicTraits: UInt32
        let glyph: CGGlyph
        let scaleBits: UInt64
    }

    private struct ShapedGlyph {
        let key: GlyphKey
        let font: CTFont
        let glyph: CGGlyph
        let position: CGPoint
        let bounds: CGRect
        let widthPixels: Int
        let heightPixels: Int
    }

    private struct GlyphEntry {
        let pageIndex: Int
        let x: Int
        let y: Int
        let widthPixels: Int
        let heightPixels: Int
        let bounds: CGRect
    }

    private struct PageCursor {
        var nextX = 0
        var nextY = 0
        var rowHeight = 0
    }

    private struct PageState {
        let texture: MTLTexture
        var cursor = PageCursor()
    }

    private struct Allocation {
        let pageIndex: Int
        let x: Int
        let y: Int
    }

    private struct AllocationPlan {
        let allocations: [Allocation]
        let cursors: [PageCursor]
    }

    private struct RasterizedGlyph {
        let shaped: ShapedGlyph
        let pixels: [UInt8]
    }

    private let device: MTLDevice
    private let pageSize: Int
    private let maximumPages: Int
    private let textureStorageMode: MTLStorageMode
    private var pages: [PageState]
    private var entries: [GlyphKey: GlyphEntry] = [:]

    private(set) var textures: [MTLTexture]
    private(set) var glyphCount = 0
    private(set) var usedPixels = 0
    let capacityPixels: Int
    private(set) var rejectedGlyphs = 0
    private(set) var rasterizationCount = 0

    init?(device: MTLDevice, pageSize: Int = 1024, maximumPages: Int = 4) {
        guard Self.minimumPageSize...Self.maximumPageSize ~= pageSize,
            1...Self.maximumPageCount ~= maximumPages
        else { return nil }

        let capacity = pageSize * pageSize * maximumPages
        guard
            let firstPage = Self.makeTexture(
                device: device,
                pageSize: pageSize,
                storageMode: nil
            )
        else { return nil }

        self.device = device
        self.pageSize = pageSize
        self.maximumPages = maximumPages
        self.textureStorageMode = firstPage.storageMode
        self.pages = [PageState(texture: firstPage.texture)]
        self.textures = [firstPage.texture]
        capacityPixels = capacity
    }

    func layout(text: String, font: UIFont, scale: CGFloat) -> DanmakuGlyphLayout? {
        guard !text.isEmpty,
            text.utf16.count <= Self.maximumTextUTF16Count,
            scale.isFinite,
            scale >= 0.25,
            scale <= 8,
            font.pointSize.isFinite,
            font.pointSize > 0,
            font.pointSize <= 256
        else { return nil }

        guard let shapedLine = shape(text: text, font: font, scale: scale) else { return nil }

        var missingDefinitions: [GlyphKey: ShapedGlyph] = [:]
        var missingOrder = [GlyphKey]()
        missingOrder.reserveCapacity(shapedLine.glyphs.count)
        for glyph in shapedLine.glyphs where entries[glyph.key] == nil {
            if missingDefinitions[glyph.key] == nil {
                missingDefinitions[glyph.key] = glyph
                missingOrder.append(glyph.key)
            }
        }

        let definitions = missingOrder.compactMap { missingDefinitions[$0] }
        let existingCursors = pages.map(\.cursor)
        guard let plan = allocationPlan(for: definitions, cursors: existingCursors) else {
            rejectedGlyphs += max(1, definitions.count)
            return nil
        }
        let allocations = plan.allocations

        let rasterized = definitions.compactMap { rasterize($0, scale: scale) }
        guard rasterized.count == definitions.count else {
            rejectedGlyphs += max(1, definitions.count)
            return nil
        }

        let requiredPageCount = plan.cursors.count
        var newPages = [PageState]()
        if requiredPageCount > pages.count {
            newPages.reserveCapacity(requiredPageCount - pages.count)
            for _ in pages.count..<requiredPageCount {
                guard
                    let page = Self.makeTexture(
                        device: device,
                        pageSize: pageSize,
                        storageMode: textureStorageMode
                    )
                else {
                    rejectedGlyphs += max(1, definitions.count)
                    return nil
                }
                newPages.append(PageState(texture: page.texture))
            }
        }

        var committedPages = pages
        committedPages.append(contentsOf: newPages)
        for index in committedPages.indices {
            committedPages[index].cursor = plan.cursors[index]
        }

        for (rasterizedGlyph, allocation) in zip(rasterized, allocations) {
            let texture = committedPages[allocation.pageIndex].texture
            let region = MTLRegionMake2D(
                allocation.x,
                allocation.y,
                rasterizedGlyph.shaped.widthPixels,
                rasterizedGlyph.shaped.heightPixels
            )
            rasterizedGlyph.pixels.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else { return }
                texture.replace(
                    region: region,
                    mipmapLevel: 0,
                    withBytes: baseAddress,
                    bytesPerRow: rasterizedGlyph.shaped.widthPixels
                )
            }
        }

        pages = committedPages
        textures = committedPages.map(\.texture)
        for (rasterizedGlyph, allocation) in zip(rasterized, allocations) {
            entries[rasterizedGlyph.shaped.key] = GlyphEntry(
                pageIndex: allocation.pageIndex,
                x: allocation.x,
                y: allocation.y,
                widthPixels: rasterizedGlyph.shaped.widthPixels,
                heightPixels: rasterizedGlyph.shaped.heightPixels,
                bounds: rasterizedGlyph.shaped.bounds
            )
            glyphCount += 1
            usedPixels += rasterizedGlyph.shaped.widthPixels * rasterizedGlyph.shaped.heightPixels
            rasterizationCount += 1
        }

        let padding = CGFloat(Self.paddingPixels) / scale
        let glyphPlacements = shapedLine.glyphs.compactMap { glyph -> DanmakuGlyphPlacement? in
            guard let entry = entries[glyph.key] else { return nil }
            return DanmakuGlyphPlacement(
                pageIndex: entry.pageIndex,
                uvRect: SIMD4(
                    Float(entry.x) / Float(pageSize),
                    Float(entry.y) / Float(pageSize),
                    Float(entry.widthPixels) / Float(pageSize),
                    Float(entry.heightPixels) / Float(pageSize)
                ),
                offset: CGPoint(
                    x: glyph.position.x + entry.bounds.minX - padding,
                    y: shapedLine.ascent - glyph.position.y - entry.bounds.maxY - padding
                ),
                size: CGSize(
                    width: CGFloat(entry.widthPixels) / scale,
                    height: CGFloat(entry.heightPixels) / scale
                )
            )
        }

        return DanmakuGlyphLayout(size: shapedLine.size, glyphs: glyphPlacements)
    }

    func reset() {
        entries.removeAll(keepingCapacity: true)
        pages.removeAll(keepingCapacity: true)
        textures.removeAll(keepingCapacity: true)
        glyphCount = 0
        usedPixels = 0
        rejectedGlyphs = 0
        rasterizationCount = 0
    }

    private struct ShapedLine {
        let size: CGSize
        let ascent: CGFloat
        let glyphs: [ShapedGlyph]
    }

    private func shape(text: String, font: UIFont, scale: CGFloat) -> ShapedLine? {
        let attributedString = NSAttributedString(string: text, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attributedString)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let height = max(1, ascent + descent + max(leading, 0))
        guard width.isFinite,
            height.isFinite,
            width >= 0,
            height > 0,
            width <= Self.maximumLayoutWidth,
            height <= Self.maximumLayoutHeight
        else { return nil }

        // UIFont and CTFont are toll-free bridged; preserve the system font descriptor.
        let baseFont = font as CTFont
        let runs = CTLineGetGlyphRuns(line) as NSArray
        var result = [ShapedGlyph]()
        result.reserveCapacity(min(Self.maximumLayoutGlyphCount, text.utf16.count))
        var shapedGlyphCount = 0

        for case let run as CTRun in runs {
            let runFont = Self.font(for: run, fallback: baseFont)
            let count = CTRunGetGlyphCount(run)
            guard count <= Self.maximumLayoutGlyphCount - shapedGlyphCount else { return nil }
            shapedGlyphCount += count
            guard count > 0 else { continue }

            var glyphs = Array(repeating: CGGlyph(), count: count)
            var positions = Array(repeating: CGPoint.zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)

            for (glyph, position) in zip(glyphs, positions) {
                var bounds = CGRect.zero
                var glyphValue = glyph
                CTFontGetBoundingRectsForGlyphs(
                    runFont,
                    .default,
                    &glyphValue,
                    &bounds,
                    1
                )
                bounds = bounds.standardized
                guard Self.isFinite(bounds) else { return nil }
                guard bounds.width > 0, bounds.height > 0 else { continue }
                guard let pixelSize = Self.pixelSize(for: bounds, scale: scale) else {
                    return nil
                }

                let key = GlyphKey(
                    fontIdentity: Self.fontIdentity(runFont),
                    fontSizeBits: Double(CTFontGetSize(runFont)).bitPattern,
                    fontVariation: Self.fontVariation(runFont),
                    symbolicTraits: CTFontGetSymbolicTraits(runFont).rawValue,
                    glyph: glyph,
                    scaleBits: Double(scale).bitPattern
                )
                result.append(
                    ShapedGlyph(
                        key: key,
                        font: runFont,
                        glyph: glyph,
                        position: position,
                        bounds: bounds,
                        widthPixels: pixelSize.width,
                        heightPixels: pixelSize.height
                    )
                )
            }
        }

        return ShapedLine(
            size: CGSize(width: ceil(width), height: ceil(height)),
            ascent: ascent,
            glyphs: result
        )
    }

    private func allocationPlan(for glyphs: [ShapedGlyph], cursors: [PageCursor]) -> AllocationPlan? {
        var provisional = cursors
        var result = [Allocation]()
        result.reserveCapacity(glyphs.count)

        for glyph in glyphs {
            guard
                let allocation = allocate(
                    width: glyph.widthPixels,
                    height: glyph.heightPixels,
                    cursors: &provisional
                )
            else { return nil }
            result.append(allocation)
        }

        return AllocationPlan(allocations: result, cursors: provisional)
    }

    private func allocate(
        width: Int,
        height: Int,
        cursors: inout [PageCursor]
    ) -> Allocation? {
        guard width <= pageSize, height <= pageSize else { return nil }

        for pageIndex in cursors.indices {
            var cursor = cursors[pageIndex]
            if cursor.nextX + width > pageSize {
                cursor.nextX = 0
                cursor.nextY += cursor.rowHeight
                cursor.rowHeight = 0
            }
            guard cursor.nextY + height <= pageSize else { continue }

            let allocation = Allocation(pageIndex: pageIndex, x: cursor.nextX, y: cursor.nextY)
            cursor.nextX += width
            cursor.rowHeight = max(cursor.rowHeight, height)
            cursors[pageIndex] = cursor
            return allocation
        }

        guard cursors.count < maximumPages else { return nil }
        let pageIndex = cursors.count
        var cursor = PageCursor()
        let allocation = Allocation(pageIndex: pageIndex, x: 0, y: 0)
        cursor.nextX = width
        cursor.rowHeight = height
        cursors.append(cursor)
        return allocation
    }

    private func rasterize(_ glyph: ShapedGlyph, scale: CGFloat) -> RasterizedGlyph? {
        let width = glyph.widthPixels
        let height = glyph.heightPixels
        var pixels = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                )
            else { return false }

            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)
            context.setFillColor(gray: 1, alpha: 1)
            context.scaleBy(x: scale, y: scale)
            var glyphValue = glyph.glyph
            var position = CGPoint(
                x: CGFloat(Self.paddingPixels) / scale - glyph.bounds.minX,
                y: CGFloat(Self.paddingPixels) / scale - glyph.bounds.minY
            )
            CTFontDrawGlyphs(glyph.font, &glyphValue, &position, 1, context)
            return true
        }
        guard didDraw else { return nil }

        // CGBitmapContext stores these rows in image (top-left) order already.
        // Flipping here would invert glyphs when uploaded to a Metal texture.
        return RasterizedGlyph(shaped: glyph, pixels: pixels)
    }

    private static func makeTexture(
        device: MTLDevice,
        pageSize: Int,
        storageMode: MTLStorageMode?
    ) -> (texture: MTLTexture, storageMode: MTLStorageMode)? {
        let modes: [MTLStorageMode]
        if let storageMode {
            modes = [storageMode]
        } else {
            #if os(macOS)
                modes = [.shared, .managed]
            #else
                modes = [.shared]
            #endif
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: pageSize,
            height: pageSize,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        for mode in modes {
            descriptor.storageMode = mode
            if let texture = device.makeTexture(descriptor: descriptor) {
                texture.label = "Danmaku glyph atlas page"
                return (texture, mode)
            }
        }
        return nil
    }

    private static func font(for run: CTRun, fallback: CTFont) -> CTFont {
        let attributes = CTRunGetAttributes(run) as NSDictionary
        guard let value = attributes[kCTFontAttributeName as NSAttributedString.Key] else {
            return fallback
        }
        return value as! CTFont
    }

    private static func fontIdentity(_ font: CTFont) -> String {
        let postScriptName = CTFontCopyPostScriptName(font) as String
        if !postScriptName.isEmpty { return postScriptName }
        return CTFontCopyFullName(font) as String
    }

    private static func pixelSize(for bounds: CGRect, scale: CGFloat) -> (width: Int, height: Int)? {
        let width = Double(bounds.width) * Double(scale)
        let height = Double(bounds.height) * Double(scale)
        let maximumInteger = Double(Int.max - paddingPixels * 2)
        let maximumPixelDimension = min(
            Double(maximumPageSize - paddingPixels * 2),
            maximumInteger
        )
        guard width.isFinite,
            height.isFinite,
            width > 0,
            height > 0,
            width <= maximumPixelDimension,
            height <= maximumPixelDimension
        else { return nil }
        let widthCeiling = ceil(width)
        let heightCeiling = ceil(height)
        guard widthCeiling <= maximumInteger, heightCeiling <= maximumInteger else { return nil }
        let widthPixels = Int(widthCeiling) + paddingPixels * 2
        let heightPixels = Int(heightCeiling) + paddingPixels * 2
        guard widthPixels > 0, heightPixels > 0 else { return nil }
        return (widthPixels, heightPixels)
    }

    private static func fontVariation(_ font: CTFont) -> String {
        guard let variation = CTFontCopyVariation(font) as NSDictionary? else { return "" }
        return variation.allKeys.map { key in
            "\(String(describing: key))=\(String(describing: variation[key] as Any))"
        }.sorted().joined(separator: ",")
    }

    private static func isFinite(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.size.width.isFinite && rect.size.height.isFinite
    }
}
