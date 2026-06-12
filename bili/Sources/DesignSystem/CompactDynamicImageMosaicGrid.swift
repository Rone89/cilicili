import SwiftUI

struct CompactDynamicImageMosaicGrid: View {
    @StateObject private var previewGroup = ZoomyImagePreviewGroup()
    private let imageCount: Int
    private let displayedImages: [CompactDynamicImageDisplayItem]
    private let layout: CompactDynamicImageMosaicLayout
    private let previewItems: [ZoomyImagePreviewItem]
    private let accessibilityName: String
    private let placeholderFill: Color

    private static let spacing: CGFloat = 6
    private static let compactWidth: CGFloat = 270
    private static let smallSide: CGFloat = 86
    private static let mediumSide: CGFloat = 132
    private static let largeSide: CGFloat = 178
    private static let footerSide: CGFloat = 63

    init(
        images: [DynamicImageItem],
        accessibilityName: String,
        placeholderFill: Color
    ) {
        let visibleImages = images.filter { $0.normalizedURL != nil }
        let displayedImages = CompactDynamicImageDisplayItems.make(from: visibleImages, limit: 9)
        self.imageCount = visibleImages.count
        self.displayedImages = displayedImages
        self.layout = CompactDynamicImageMosaicLayout(displayedImages: displayedImages)
        self.previewItems = CompactDynamicImageDisplayItems.previewItems(
            from: CompactDynamicImageDisplayItems.make(from: visibleImages)
        )
        self.accessibilityName = accessibilityName
        self.placeholderFill = placeholderFill
    }

    var body: some View {
        if imageCount > 0 {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch displayedImages.count {
        case 0:
            EmptyView()
        case 1:
            singleImageLayout
        case 2:
            equalGrid(columns: 2, side: Self.mediumSide)
        case 3:
            threeImageMosaic
        case 4:
            equalGrid(columns: 2, side: Self.mediumSide)
        case 5:
            fiveImageMosaic
        case 6:
            equalGrid(columns: 3, side: Self.smallSide)
        case 7:
            sevenImageMosaic
        case 8:
            eightImageMosaic
        default:
            equalGrid(columns: 3, side: Self.smallSide)
        }
    }

    private var singleImageLayout: some View {
        HStack {
            if let first = displayedImages.first {
                imageTile(first)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: Self.compactWidth, alignment: .leading)
    }

    private var threeImageMosaic: some View {
        HStack(spacing: Self.spacing) {
            if let first = layout.primaryTile {
                imageTile(first, size: CGSize(width: Self.largeSide, height: Self.largeSide))
            }

            VStack(spacing: Self.spacing) {
                ForEach(layout.trailingTiles) { item in
                    imageTile(item, size: CGSize(width: Self.smallSide, height: Self.smallSide))
                }
            }
        }
        .frame(width: Self.compactWidth, height: Self.largeSide, alignment: .leading)
    }

    private var fiveImageMosaic: some View {
        VStack(spacing: Self.spacing) {
            HStack(spacing: Self.spacing) {
                ForEach(layout.topTiles) { item in
                    imageTile(item, size: CGSize(width: Self.mediumSide, height: Self.mediumSide))
                }
            }

            HStack(spacing: Self.spacing) {
                ForEach(layout.bottomTiles) { item in
                    imageTile(item, size: CGSize(width: Self.smallSide, height: Self.smallSide))
                }
            }
        }
        .frame(width: Self.compactWidth, alignment: .topLeading)
    }

    private var sevenImageMosaic: some View {
        VStack(spacing: Self.spacing) {
            HStack(spacing: Self.spacing) {
                if let first = layout.primaryTile {
                    imageTile(first, size: CGSize(width: Self.largeSide, height: Self.largeSide))
                }

                VStack(spacing: Self.spacing) {
                    ForEach(layout.trailingTiles) { item in
                        imageTile(item, size: CGSize(width: Self.smallSide, height: Self.smallSide))
                    }
                }
            }

            HStack(spacing: Self.spacing) {
                ForEach(layout.bottomTiles) { item in
                    imageTile(item, size: CGSize(width: Self.footerSide, height: Self.footerSide))
                }
            }
        }
        .frame(width: Self.compactWidth, alignment: .topLeading)
    }

    private var eightImageMosaic: some View {
        VStack(spacing: Self.spacing) {
            HStack(spacing: Self.spacing) {
                ForEach(layout.topTiles) { item in
                    imageTile(item, size: CGSize(width: Self.mediumSide, height: Self.mediumSide))
                }
            }

            fixedRows(
                layout.rows,
                side: Self.smallSide
            )
        }
        .frame(width: Self.compactWidth, alignment: .topLeading)
    }

    private func equalGrid(columns: Int, side: CGFloat) -> some View {
        VStack(spacing: Self.spacing) {
            ForEach(layout.rows(for: columns)) { row in
                HStack(spacing: Self.spacing) {
                    ForEach(row.items) { item in
                        imageTile(item, size: CGSize(width: side, height: side))
                    }
                }
            }
        }
        .frame(width: gridWidth(columns: columns, side: side), alignment: .topLeading)
    }

    private func fixedRows(_ rows: [CompactDynamicImageMosaicRow], side: CGFloat) -> some View {
        VStack(spacing: Self.spacing) {
            ForEach(rows) { row in
                HStack(spacing: Self.spacing) {
                    ForEach(row.items) { item in
                        imageTile(item, size: CGSize(width: side, height: side))
                    }
                }
            }
        }
    }

    private func imageTile(
        _ item: CompactDynamicImageDisplayItem,
        size: CGSize? = nil
    ) -> some View {
        CompactDynamicImageThumbnail(
            image: item.image,
            previewItems: previewItems,
            previewItemID: item.id,
            previewGroup: previewGroup,
            imageCount: imageCount,
            aspectRatio: item.aspectRatio,
            placeholderFill: placeholderFill,
            thumbnailSizeOverride: size
        )
        .overlay {
            overflowOverlay(for: item)
        }
        .accessibilityLabel(accessibilityTitle(for: item.index))
    }

    @ViewBuilder
    private func overflowOverlay(for item: CompactDynamicImageDisplayItem) -> some View {
        if item.index == 8, imageCount > 9 {
            ZStack {
                Color.clear
                Text("+\(imageCount - 8)")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .glassEffect(.regular, in: Capsule())
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func accessibilityTitle(for index: Int) -> String {
        imageCount > 1 ? "第 \(index + 1) 张\(accessibilityName)，共 \(imageCount) 张" : accessibilityName
    }

    private func gridWidth(columns: Int, side: CGFloat) -> CGFloat {
        side * CGFloat(columns) + Self.spacing * CGFloat(max(columns - 1, 0))
    }
}

private struct CompactDynamicImageMosaicRow: Identifiable {
    let id: Int
    let items: [CompactDynamicImageDisplayItem]
}

private struct CompactDynamicImageMosaicLayout {
    let primaryTile: CompactDynamicImageDisplayItem?
    let topTiles: [CompactDynamicImageDisplayItem]
    let trailingTiles: [CompactDynamicImageDisplayItem]
    let bottomTiles: [CompactDynamicImageDisplayItem]
    let rows: [CompactDynamicImageMosaicRow]
    private let twoColumnRows: [CompactDynamicImageMosaicRow]
    private let threeColumnRows: [CompactDynamicImageMosaicRow]

    init(displayedImages: [CompactDynamicImageDisplayItem]) {
        primaryTile = displayedImages.first
        topTiles = Array(displayedImages.prefix(2))
        trailingTiles = Self.slice(displayedImages, from: 1, count: 2)
        bottomTiles = Self.bottomTiles(for: displayedImages)
        rows = Self.rowsForEightImageMosaic(displayedImages)
        twoColumnRows = Self.chunked(displayedImages, columns: 2)
        threeColumnRows = Self.chunked(displayedImages, columns: 3)
    }

    func rows(for columns: Int) -> [CompactDynamicImageMosaicRow] {
        columns == 2 ? twoColumnRows : threeColumnRows
    }

    private static func bottomTiles(for items: [CompactDynamicImageDisplayItem]) -> [CompactDynamicImageDisplayItem] {
        switch items.count {
        case 5:
            return slice(items, from: 2, count: 3)
        case 7:
            return slice(items, from: 3, count: 4)
        default:
            return []
        }
    }

    private static func rowsForEightImageMosaic(_ items: [CompactDynamicImageDisplayItem]) -> [CompactDynamicImageMosaicRow] {
        chunked(slice(items, from: 2, count: 6), columns: 3)
    }

    private static func slice(
        _ items: [CompactDynamicImageDisplayItem],
        from startIndex: Int,
        count: Int
    ) -> [CompactDynamicImageDisplayItem] {
        guard startIndex < items.count, count > 0 else { return [] }
        let endIndex = min(startIndex + count, items.count)
        return Array(items[startIndex..<endIndex])
    }

    private static func chunked(
        _ items: [CompactDynamicImageDisplayItem],
        columns: Int
    ) -> [CompactDynamicImageMosaicRow] {
        let columnCount = max(columns, 1)
        return stride(from: 0, to: items.count, by: columnCount).map { startIndex in
            CompactDynamicImageMosaicRow(
                id: startIndex / columnCount,
                items: Array(items[startIndex..<min(startIndex + columnCount, items.count)])
            )
        }
    }
}

private struct CompactDynamicImageThumbnail: View {
    let image: DynamicImageItem
    let previewItems: [ZoomyImagePreviewItem]
    let previewItemID: String
    let previewGroup: ZoomyImagePreviewGroup
    let imageCount: Int
    let placeholderFill: Color
    @State private var thumbnailShadowOpacityScale = 1.0
    @State private var thumbnailStrokeOpacityScale = 1.0
    private let normalizedURLString: String?
    private let thumbnailSize: CGSize
    @Environment(\.displayScale) private var displayScale

    init(
        image: DynamicImageItem,
        previewItems: [ZoomyImagePreviewItem],
        previewItemID: String,
        previewGroup: ZoomyImagePreviewGroup,
        imageCount: Int,
        aspectRatio: CGFloat,
        placeholderFill: Color,
        thumbnailSizeOverride: CGSize? = nil
    ) {
        self.image = image
        self.previewItems = previewItems
        self.previewItemID = previewItemID
        self.previewGroup = previewGroup
        self.imageCount = imageCount
        self.placeholderFill = placeholderFill
        let normalizedURLString = image.normalizedURL
        self.normalizedURLString = normalizedURLString
        self.thumbnailSize = thumbnailSizeOverride ?? Self.thumbnailSize(imageCount: imageCount, aspectRatio: aspectRatio)
    }

    var body: some View {
        ZoomyRemoteImage(
            url: thumbnailURL,
            fallbackURL: normalizedURLString.flatMap(URL.init(string:)),
            viewerURL: normalizedURLString.flatMap(URL.init(string:)),
            viewerItems: previewItems,
            viewerItemID: previewItemID,
            viewerGroup: previewGroup,
            targetPixelSize: targetPixelSize,
            cornerRadius: 8,
            onViewerPresentationChange: updateThumbnailShadowVisibility
        ) { phase in
            BiliMediaPlaceholder(
                style: .image,
                phase: phase,
                iconSize: 15
            )
                .background(placeholderFill)
        }
        .frame(width: thumbnailSize.width, height: thumbnailSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .mediaShadow(.subtle, opacityScale: thumbnailShadowOpacityScale)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(.separator).opacity(0.10 * thumbnailStrokeOpacityScale), lineWidth: 0.6)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func updateThumbnailShadowVisibility(isViewerPresented: Bool) {
        if isViewerPresented {
            thumbnailShadowOpacityScale = 0
            thumbnailStrokeOpacityScale = 0
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                thumbnailShadowOpacityScale = 1
                thumbnailStrokeOpacityScale = 1
            }
        }
    }

    private var thumbnailURL: URL? {
        normalizedURLString
            .map { $0.biliCoverThumbnailURL(fitting: thumbnailSize, scale: displayScale) }
            .flatMap(URL.init(string:))
    }

    private var targetPixelSize: Int {
        Int(ceil(max(thumbnailSize.width, thumbnailSize.height) * displayScale))
    }

    private static func thumbnailSize(imageCount: Int, aspectRatio: CGFloat) -> CGSize {
        if imageCount == 1 {
            let width: CGFloat = 132
            let ratio = min(max(aspectRatio, 0.55), 1.85)
            let height = min(max(width / ratio, 78), 176)
            return CGSize(width: width, height: height)
        }
        return CGSize(width: 86, height: 86)
    }
}

private struct CompactDynamicImageDisplayItem: Identifiable {
    let id: String
    let index: Int
    let image: DynamicImageItem
    let aspectRatio: CGFloat
}

private enum CompactDynamicImageDisplayItems {
    static func make(from images: [DynamicImageItem], limit: Int? = nil) -> [CompactDynamicImageDisplayItem] {
        let source = limit.map { Array(images.prefix($0)) } ?? images
        var seenIDs = [String: Int]()
        return source.enumerated().map { index, image in
            let normalizedURLString = image.normalizedURL
            let baseID = stableBaseID(
                for: image,
                normalizedURLString: normalizedURLString,
                fallbackIndex: index
            )
            let occurrence = seenIDs[baseID, default: 0]
            seenIDs[baseID] = occurrence + 1
            let id = occurrence == 0 ? baseID : "\(baseID)#\(occurrence)"
            return CompactDynamicImageDisplayItem(
                id: id,
                index: index,
                image: image,
                aspectRatio: aspectRatio(for: image, normalizedURLString: normalizedURLString)
            )
        }
    }

    static func previewItems(from displayItems: [CompactDynamicImageDisplayItem]) -> [ZoomyImagePreviewItem] {
        displayItems.compactMap { item in
            guard let normalizedURLString = item.image.normalizedURL,
                  let url = URL(string: normalizedURLString)
            else { return nil }
            return ZoomyImagePreviewItem(
                id: item.id,
                fallbackURL: url,
                viewerURL: url
            )
        }
    }

    private static func stableBaseID(
        for image: DynamicImageItem,
        normalizedURLString: String?,
        fallbackIndex: Int
    ) -> String {
        if let normalizedURLString {
            return normalizedURLString
        }
        let trimmedURL = image.url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedURL.isEmpty {
            return trimmedURL
        }
        return "compact-image-\(fallbackIndex)"
    }

    private static func aspectRatio(for image: DynamicImageItem, normalizedURLString: String?) -> CGFloat {
        if let width = image.width, let height = image.height, width > 0, height > 0 {
            return max(CGFloat(width) / CGFloat(height), 0.1)
        }
        if let ratio = normalizedURLString?.biliImageURLAspectRatio {
            return max(CGFloat(ratio), 0.1)
        }
        return 1
    }
}
