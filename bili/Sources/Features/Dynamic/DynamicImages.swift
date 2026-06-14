import SwiftUI

private struct DynamicImageDisplayItem: Identifiable {
    let id: String
    let index: Int
    let image: DynamicImageItem
    let aspectRatio: CGFloat

    var isLongImage: Bool {
        aspectRatio < 0.62
    }
}

private enum DynamicImageDisplayItems {
    static func make(from images: [DynamicImageItem], limit: Int? = nil) -> [DynamicImageDisplayItem] {
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
            return DynamicImageDisplayItem(
                id: id,
                index: index,
                image: image,
                aspectRatio: aspectRatio(for: image, normalizedURLString: normalizedURLString)
            )
        }
    }

    static func previewItems(from displayItems: [DynamicImageDisplayItem]) -> [ZoomyImagePreviewItem] {
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
        return "image-\(fallbackIndex)"
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

private struct DynamicImageHeroPreview: View {
    let images: [DynamicImageItem]
    var cornerRadius: CGFloat = 18
    var aspectRatio: CGFloat = 16 / 9

    private var firstImage: DynamicImageItem? {
        images.first
    }

    var body: some View {
        if let firstImage {
            DynamicImageButton(
                image: firstImage,
                displayMode: .hero(aspectRatio: aspectRatio, cornerRadius: cornerRadius),
            ) {
                heroOverlay
            }
            .accessibilityLabel(accessibilityTitle)
        }
    }

    @ViewBuilder
    private var heroOverlay: some View {
        if images.count > 1 {
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        .clear,
                        .black.opacity(0.46)
                    ],
                    startPoint: .center,
                    endPoint: .bottom
                )

                HStack(alignment: .bottom) {
                    VideoCoverGlassBadge {
                        Label("\(min(images.count, 9))图", systemImage: "photo.on.rectangle.angled")
                            .labelStyle(.titleAndIcon)
                    }

                    Spacer(minLength: 8)

                    VideoCoverGlassBadge {
                        Text("1/\(images.count)")
                            .monospacedDigit()
                    }
                }
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    private var accessibilityTitle: String {
        images.count > 1 ? "查看 \(images.count) 张图片" : "查看图片"
    }
}

struct DynamicImageThumbnailStrip: View {
    @StateObject private var previewGroup = ZoomyImagePreviewGroup()
    @State private var availableWidth: CGFloat = Self.defaultWidth
    let images: [DynamicImageItem]
    var horizontalBleed: CGFloat = 0
    let knownAvailableWidth: CGFloat?
    private let displayedImages: [DynamicImageDisplayItem]
    private let previewItems: [ZoomyImagePreviewItem]
    private static let defaultWidth: CGFloat = 330
    private static let singleImageMaxWidthRatio: CGFloat = 0.60
    private static let minSingleImageWidth: CGFloat = 96

    init(
        images: [DynamicImageItem],
        horizontalBleed: CGFloat = 0,
        availableWidth: CGFloat? = nil
    ) {
        self.images = images
        self.horizontalBleed = horizontalBleed
        self.knownAvailableWidth = availableWidth.map { floor($0) }.flatMap { $0 > 1 ? $0 : nil }
        let displayedImages = DynamicImageDisplayItems.make(from: images)
        self.displayedImages = displayedImages
        self.previewItems = DynamicImageDisplayItems.previewItems(from: displayedImages)
    }

    var body: some View {
        switch displayedImages.count {
        case 0:
            EmptyView()
        case 1:
            measuredContent {
                singleImageContent(width: resolvedWidth)
            }
        default:
            DynamicImageGrid(
                images: images,
                availableWidth: knownAvailableWidth.map { max($0 + horizontalBleed * 2, 1) }
            )
                .padding(.horizontal, -horizontalBleed)
        }
    }

    private var resolvedWidth: CGFloat {
        if let knownAvailableWidth {
            return knownAvailableWidth
        }
        guard availableWidth > 1 else { return Self.defaultWidth }
        return floor(availableWidth)
    }

    @ViewBuilder
    private func measuredContent<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if knownAvailableWidth != nil {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(widthReader)
                .onPreferenceChange(DynamicImageGridWidthPreferenceKey.self) { width in
                    updateAvailableWidth(width)
                }
        }
    }

    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: DynamicImageGridWidthPreferenceKey.self,
                    value: proxy.size.width
                )
        }
    }

    private func updateAvailableWidth(_ width: CGFloat) {
        let roundedWidth = floor(width)
        guard roundedWidth > 1, abs(availableWidth - roundedWidth) > 0.5 else { return }
        availableWidth = roundedWidth
    }

    @ViewBuilder
    private func singleImageContent(width: CGFloat) -> some View {
        if let item = displayedImages.first {
            let fullWidth = max(width + horizontalBleed * 2, 1)
            let imageWidth = floor(max(fullWidth * Self.singleImageMaxWidthRatio, Self.minSingleImageWidth))
            let aspectRatio = max(item.aspectRatio, 0.1)
            let displayMode: DynamicImageCell.DisplayMode = item.isLongImage
                ? .longImage(cornerRadius: 8)
                : .single
            let imageHeight = item.isLongImage
                ? ceil(imageWidth * 16 / 9)
                : ceil(imageWidth / aspectRatio)

            HStack {
                DynamicImageButton(
                    image: item.image,
                    previewItems: previewItems,
                    previewItemID: item.id,
                    previewGroup: previewGroup,
                    displayMode: displayMode
                )
                .frame(width: imageWidth, height: imageHeight)
                .accessibilityLabel(accessibilityTitle(for: item.index))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, horizontalBleed)
            .frame(width: fullWidth, height: imageHeight, alignment: .leading)
            .padding(.horizontal, -horizontalBleed)
        }
    }

    private func accessibilityTitle(for index: Int) -> String {
        images.count > 1 ? "查看第 \(index + 1) 张图片，共 \(images.count) 张" : "查看图片"
    }
}

private struct DynamicImageGrid: View {
    @StateObject private var previewGroup = ZoomyImagePreviewGroup()
    @State private var availableWidth: CGFloat = Self.defaultWidth
    let images: [DynamicImageItem]
    let knownAvailableWidth: CGFloat?
    private let displayedImages: [DynamicImageDisplayItem]
    private let layout: DynamicImageGridLayout
    private let previewItems: [ZoomyImagePreviewItem]
    private static let defaultWidth: CGFloat = 330
    private static let spacing: CGFloat = 4

    init(images: [DynamicImageItem], availableWidth: CGFloat? = nil) {
        self.images = images
        self.knownAvailableWidth = availableWidth.map { floor($0) }.flatMap { $0 > 1 ? $0 : nil }
        let displayedImages = DynamicImageDisplayItems.make(from: images, limit: 9)
        self.displayedImages = displayedImages
        self.layout = DynamicImageGridLayout(displayedImages: displayedImages)
        self.previewItems = DynamicImageDisplayItems.previewItems(
            from: DynamicImageDisplayItems.make(from: images)
        )
    }

    var body: some View {
        measuredContent {
            content(width: resolvedWidth)
        }
    }

    private var resolvedWidth: CGFloat {
        if let knownAvailableWidth {
            return knownAvailableWidth
        }
        guard availableWidth > 1 else { return Self.defaultWidth }
        return floor(availableWidth)
    }

    @ViewBuilder
    private func measuredContent<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if knownAvailableWidth != nil {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(widthReader)
                .onPreferenceChange(DynamicImageGridWidthPreferenceKey.self) { width in
                    updateAvailableWidth(width)
                }
        }
    }

    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: DynamicImageGridWidthPreferenceKey.self,
                    value: proxy.size.width
                )
        }
    }

    private func updateAvailableWidth(_ width: CGFloat) {
        let roundedWidth = floor(width)
        guard roundedWidth > 1, abs(availableWidth - roundedWidth) > 0.5 else { return }
        availableWidth = roundedWidth
    }

    @ViewBuilder
    private func content(width: CGFloat) -> some View {
        switch displayedImages.count {
        case 0:
            EmptyView()
        case 1:
            singleImageLayout(width: width)
        case 2:
            equalGrid(width: width, columns: 2)
        case 3:
            threeImageMosaic(width: width)
        case 4:
            equalGrid(width: width, columns: 2)
        case 5:
            fiveImageMosaic(width: width)
        case 6:
            equalGrid(width: width, columns: 3)
        case 7:
            sevenImageMosaic(width: width)
        case 8:
            eightImageMosaic(width: width)
        default:
            equalGrid(width: width, columns: 3)
        }
    }

    @ViewBuilder
    private func singleImageLayout(width: CGFloat) -> some View {
        if let item = displayedImages.first {
            let imageWidth = floor(width * 0.82)
            let aspectRatio = item.aspectRatio
            let displayMode: DynamicImageCell.DisplayMode = item.isLongImage
                ? .longImage(cornerRadius: 8)
                : .single
            let imageHeight = item.isLongImage
                ? ceil(imageWidth * 16 / 9)
                : min(max(imageWidth / aspectRatio, 150), 360)
            HStack {
                imageTile(item, displayMode: displayMode)
                .frame(width: imageWidth, height: imageHeight)
                Spacer(minLength: 0)
            }
            .frame(width: width, alignment: .leading)
        }
    }

    private func threeImageMosaic(width: CGFloat) -> some View {
        let smallSide = floor((width - Self.spacing * 2) / 3)
        let largeSide = smallSide * 2 + Self.spacing
        return HStack(spacing: Self.spacing) {
            if let first = layout.primaryTile {
                imageTile(first, cornerRadius: 10)
                .frame(width: largeSide, height: largeSide)
            }

            VStack(spacing: Self.spacing) {
                ForEach(layout.trailingTiles) { item in
                    imageTile(item)
                    .frame(width: smallSide, height: smallSide)
                }
            }
        }
        .frame(width: width, height: largeSide, alignment: .leading)
    }

    private func fiveImageMosaic(width: CGFloat) -> some View {
        let largeSide = floor((width - Self.spacing) / 2)
        let smallSide = tileSide(for: width, columns: 3)
        return VStack(spacing: Self.spacing) {
            HStack(spacing: Self.spacing) {
                ForEach(layout.topTiles) { item in
                    imageTile(item, cornerRadius: 10)
                        .frame(width: largeSide, height: largeSide)
                }
            }

            HStack(spacing: Self.spacing) {
                ForEach(layout.middleTiles) { item in
                    imageTile(item)
                        .frame(width: smallSide, height: smallSide)
                }
            }
        }
        .frame(width: width, height: largeSide + Self.spacing + smallSide, alignment: .topLeading)
    }

    private func sevenImageMosaic(width: CGFloat) -> some View {
        let smallSide = tileSide(for: width, columns: 3)
        let largeSide = smallSide * 2 + Self.spacing
        let footerSide = tileSide(for: width, columns: 4)
        return VStack(spacing: Self.spacing) {
            HStack(spacing: Self.spacing) {
                if let first = layout.primaryTile {
                    imageTile(first, cornerRadius: 10)
                        .frame(width: largeSide, height: largeSide)
                }

                VStack(spacing: Self.spacing) {
                    ForEach(layout.trailingTiles) { item in
                        imageTile(item)
                            .frame(width: smallSide, height: smallSide)
                    }
                }
            }

            HStack(spacing: Self.spacing) {
                ForEach(layout.bottomTiles) { item in
                    imageTile(item)
                        .frame(width: footerSide, height: footerSide)
                }
            }
        }
        .frame(width: width, height: largeSide + Self.spacing + footerSide, alignment: .topLeading)
    }

    private func eightImageMosaic(width: CGFloat) -> some View {
        let largeSide = floor((width - Self.spacing) / 2)
        let smallSide = tileSide(for: width, columns: 3)
        return VStack(spacing: Self.spacing) {
            HStack(spacing: Self.spacing) {
                ForEach(layout.topTiles) { item in
                    imageTile(item, cornerRadius: 10)
                        .frame(width: largeSide, height: largeSide)
                }
            }

            fixedRows(
                layout.eightImageRows,
                width: width,
                tileSide: smallSide
            )
        }
        .frame(width: width, height: largeSide + Self.spacing + smallSide * 2 + Self.spacing, alignment: .topLeading)
    }

    private func equalGrid(width: CGFloat, columns: Int) -> some View {
        let side = tileSide(for: width, columns: columns)
        return VStack(spacing: Self.spacing) {
            ForEach(layout.rows(for: columns)) { row in
                HStack(spacing: Self.spacing) {
                    ForEach(row.items) { item in
                        imageTile(item, cornerRadius: columns == 2 ? 10 : 8)
                            .frame(width: side, height: side)
                    }

                    if row.items.count < columns {
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    private func fixedRows(
        _ rows: [DynamicImageGridRow],
        width: CGFloat,
        tileSide: CGFloat
    ) -> some View {
        return VStack(spacing: Self.spacing) {
            ForEach(rows) { row in
                HStack(spacing: Self.spacing) {
                    ForEach(row.items) { item in
                        imageTile(item)
                            .frame(width: tileSide, height: tileSide)
                    }
                }
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    private func imageTile(
        _ item: DynamicImageDisplayItem,
        cornerRadius: CGFloat = 8
    ) -> some View {
        imageTile(item, displayMode: .square(cornerRadius: cornerRadius))
    }

    private func imageTile(
        _ item: DynamicImageDisplayItem,
        displayMode: DynamicImageCell.DisplayMode
    ) -> some View {
        DynamicImageButton(
            image: item.image,
            previewItems: previewItems,
            previewItemID: item.id,
            previewGroup: previewGroup,
            displayMode: displayMode
        ) {
            overflowOverlay(for: item)
        }
    }

    @ViewBuilder
    private func overflowOverlay(for item: DynamicImageDisplayItem) -> some View {
        if item.index == 8, images.count > 9 {
            ZStack {
                Color.clear
                Text("+\(images.count - 8)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .glassEffect(.regular, in: Capsule())
            }
        }
    }

    private func tileSide(for width: CGFloat, columns: Int) -> CGFloat {
        floor((width - Self.spacing * CGFloat(max(columns - 1, 0))) / CGFloat(max(columns, 1)))
    }
}

private struct DynamicImageGridRow: Identifiable {
    let id: Int
    let items: [DynamicImageDisplayItem]
}

private struct DynamicImageGridLayout {
    let primaryTile: DynamicImageDisplayItem?
    let topTiles: [DynamicImageDisplayItem]
    let trailingTiles: [DynamicImageDisplayItem]
    let middleTiles: [DynamicImageDisplayItem]
    let bottomTiles: [DynamicImageDisplayItem]
    let eightImageRows: [DynamicImageGridRow]
    private let twoColumnRows: [DynamicImageGridRow]
    private let threeColumnRows: [DynamicImageGridRow]

    init(displayedImages: [DynamicImageDisplayItem]) {
        primaryTile = displayedImages.first
        topTiles = Self.slice(displayedImages, from: 0, count: 2)
        trailingTiles = Self.slice(displayedImages, from: 1, count: 2)
        middleTiles = Self.slice(displayedImages, from: 2, count: 3)
        bottomTiles = Self.slice(displayedImages, from: 3, count: 4)
        eightImageRows = Self.chunked(Self.slice(displayedImages, from: 2, count: 6), columns: 3)
        twoColumnRows = Self.chunked(displayedImages, columns: 2)
        threeColumnRows = Self.chunked(displayedImages, columns: 3)
    }

    func rows(for columns: Int) -> [DynamicImageGridRow] {
        columns == 2 ? twoColumnRows : threeColumnRows
    }

    private static func slice(
        _ items: [DynamicImageDisplayItem],
        from startIndex: Int,
        count: Int
    ) -> [DynamicImageDisplayItem] {
        guard startIndex < items.count, count > 0 else { return [] }
        let endIndex = min(startIndex + count, items.count)
        return Array(items[startIndex..<endIndex])
    }

    private static func chunked(
        _ items: [DynamicImageDisplayItem],
        columns: Int
    ) -> [DynamicImageGridRow] {
        let columnCount = max(columns, 1)
        return stride(from: 0, to: items.count, by: columnCount).map { startIndex in
            DynamicImageGridRow(
                id: startIndex / columnCount,
                items: Array(items[startIndex..<min(startIndex + columnCount, items.count)])
            )
        }
    }
}

private struct DynamicImageGridWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let nextValue = nextValue()
        if nextValue > 0 {
            value = nextValue
        }
    }
}

private struct DynamicImageButton<Overlay: View>: View {
    let image: DynamicImageItem
    let previewItems: [ZoomyImagePreviewItem]
    let previewItemID: String?
    let previewGroup: ZoomyImagePreviewGroup?
    let displayMode: DynamicImageCell.DisplayMode
    @ViewBuilder let overlay: () -> Overlay

    init(
        image: DynamicImageItem,
        previewItems: [ZoomyImagePreviewItem] = [],
        previewItemID: String? = nil,
        previewGroup: ZoomyImagePreviewGroup? = nil,
        displayMode: DynamicImageCell.DisplayMode,
        @ViewBuilder overlay: @escaping () -> Overlay
    ) {
        self.image = image
        self.previewItems = previewItems
        self.previewItemID = previewItemID
        self.previewGroup = previewGroup
        self.displayMode = displayMode
        self.overlay = overlay
    }

    var body: some View {
        DynamicImageCell(
            image: image,
            previewItems: previewItems,
            previewItemID: previewItemID,
            previewGroup: previewGroup,
            displayMode: displayMode
        )
            .overlay(overlay())
            .contentShape(RoundedRectangle(cornerRadius: displayMode.cornerRadius, style: .continuous))
    }
}

private extension DynamicImageButton where Overlay == EmptyView {
    init(
        image: DynamicImageItem,
        previewItems: [ZoomyImagePreviewItem] = [],
        previewItemID: String? = nil,
        previewGroup: ZoomyImagePreviewGroup? = nil,
        displayMode: DynamicImageCell.DisplayMode
    ) {
        self.init(
            image: image,
            previewItems: previewItems,
            previewItemID: previewItemID,
            previewGroup: previewGroup,
            displayMode: displayMode
        ) {
            EmptyView()
        }
    }
}

private struct DynamicImageCell: View {
    enum DisplayMode {
        case single
        case longImage(cornerRadius: CGFloat)
        case square(cornerRadius: CGFloat)
        case hero(aspectRatio: CGFloat, cornerRadius: CGFloat)
        case fixedHeight(height: CGFloat, cornerRadius: CGFloat)
    }

    let image: DynamicImageItem
    let previewItems: [ZoomyImagePreviewItem]
    let previewItemID: String?
    let previewGroup: ZoomyImagePreviewGroup?
    let displayMode: DisplayMode
    @State private var thumbnailShadowOpacityScale = 1.0
    private let normalizedURLString: String?
    private let imageAspectRatio: CGFloat

    init(
        image: DynamicImageItem,
        previewItems: [ZoomyImagePreviewItem] = [],
        previewItemID: String? = nil,
        previewGroup: ZoomyImagePreviewGroup? = nil,
        displayMode: DisplayMode
    ) {
        self.image = image
        self.previewItems = previewItems
        self.previewItemID = previewItemID
        self.previewGroup = previewGroup
        self.displayMode = displayMode
        let normalizedURLString = image.normalizedURL
        self.normalizedURLString = normalizedURLString
        self.imageAspectRatio = Self.aspectRatio(for: image, normalizedURLString: normalizedURLString)
    }

    var body: some View {
        switch displayMode {
        case .single:
            imageContent
                .aspectRatio(displayAspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .mediaShadow(.regular, opacityScale: thumbnailShadowOpacityScale)
        case .longImage(let cornerRadius):
            imageContent
                .aspectRatio(9 / 16, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .mediaShadow(.regular, opacityScale: thumbnailShadowOpacityScale)
                .overlay(alignment: .bottomTrailing) {
                    LongImageBadge()
                        .padding(8)
                }
        case .square(let cornerRadius):
            imageContent
                .aspectRatio(1, contentMode: .fill)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .mediaShadow(.subtle, opacityScale: thumbnailShadowOpacityScale)
        case .hero(let aspectRatio, let cornerRadius):
            imageContent
                .aspectRatio(aspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .mediaShadow(.regular, opacityScale: thumbnailShadowOpacityScale)
        case .fixedHeight(let height, let cornerRadius):
            imageContent
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .frame(height: height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .mediaShadow(.regular, opacityScale: thumbnailShadowOpacityScale)
        }
    }

    private var imageContent: some View {
        ZStack {
            BiliMediaPlaceholder(style: .image, iconSize: 19)

            ZoomyRemoteImage(
                url: normalizedURLString
                    .map { $0.biliImageThumbnailURL(maxSide: thumbnailMaxSide) }
                    .flatMap(URL.init(string:)),
                fallbackURL: normalizedURLString.flatMap(URL.init(string:)),
                viewerURL: normalizedURLString.flatMap(URL.init(string:)),
                viewerItems: previewItems,
                viewerItemID: previewItemID,
                viewerGroup: previewGroup,
                targetPixelSize: thumbnailMaxSide,
                cornerRadius: displayMode.cornerRadius,
                contentMode: thumbnailContentMode,
                contentAlignment: thumbnailContentAlignment,
                onViewerPresentationChange: updateThumbnailShadowVisibility
            ) { phase in
                BiliMediaPlaceholder(
                    style: .image,
                    phase: phase,
                    iconSize: 19
                )
            }
        }
    }

    private func updateThumbnailShadowVisibility(isViewerPresented: Bool) {
        if isViewerPresented {
            thumbnailShadowOpacityScale = 0
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                thumbnailShadowOpacityScale = 1
            }
        }
    }

    private var thumbnailContentMode: ZoomyImageContentMode {
        switch displayMode {
        case .fixedHeight:
            return .fit
        case .single, .longImage, .square, .hero:
            return .fill
        }
    }

    private var thumbnailContentAlignment: ZoomyImageContentAlignment {
        switch displayMode {
        case .longImage:
            return .top
        case .single, .square, .hero, .fixedHeight:
            return .center
        }
    }

    private var displayAspectRatio: CGFloat {
        switch displayMode {
        case .single:
            return imageAspectRatio
        case .longImage:
            return 9 / 16
        case .square(_):
            return 1
        case .hero(let aspectRatio, _):
            return aspectRatio
        case .fixedHeight:
            return imageAspectRatio
        }
    }

    private var thumbnailMaxSide: Int {
        let usesCompactImages = PlaybackEnvironment.current.shouldPreferConservativePlayback
        switch displayMode {
        case .single, .longImage, .hero(_, _):
            return usesCompactImages ? 960 : 1280
        case .square(_), .fixedHeight:
            return usesCompactImages ? 360 : 420
        }
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

private extension DynamicImageCell.DisplayMode {
    var cornerRadius: CGFloat {
        switch self {
        case .single:
            return 8
        case .longImage(let cornerRadius), .square(let cornerRadius), .hero(_, let cornerRadius), .fixedHeight(_, let cornerRadius):
            return cornerRadius
        }
    }
}

private struct LongImageBadge: View {
    var body: some View {
        GlassEffectContainer(spacing: 8) {
            Label("长图", systemImage: "scroll")
                .font(.caption2.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .biliPlayerClearGlass(interactive: false, in: Capsule())
                .accessibilityLabel("长图")
        }
    }
}
