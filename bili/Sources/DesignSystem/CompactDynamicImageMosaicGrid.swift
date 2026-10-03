import SwiftUI

struct CompactDynamicImageMosaicGrid: View {
    @StateObject private var previewGroup = ZoomyImagePreviewGroup()
    @State private var availableWidth: CGFloat = CompactDynamicImageMosaicMetrics.compactWidth
    private let imageCount: Int
    private let displayedImages: [CompactDynamicImageDisplayItem]
    private let layout: CompactDynamicImageMosaicLayout
    private let previewItems: [ZoomyImagePreviewItem]
    private let accessibilityName: String
    private let placeholderFill: Color

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
            if imageCount > 1 {
                mosaicContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(widthReader)
                    .onPreferenceChange(CompactDynamicImageMosaicWidthPreferenceKey.self) { width in
                        updateAvailableWidth(width)
                    }
            } else {
                mosaicContent
            }
        }
    }

    private var mosaicContent: some View {
        CompactDynamicImageMosaicContent(
            imageCount: imageCount,
            displayedImages: displayedImages,
            layout: layout,
            previewItems: previewItems,
            previewGroup: previewGroup,
            accessibilityName: accessibilityName,
            placeholderFill: placeholderFill,
            adaptiveWidth: resolvedWidth
        )
    }

    private var resolvedWidth: CGFloat {
        availableWidth > 1 ? floor(availableWidth) : CompactDynamicImageMosaicMetrics.compactWidth
    }

    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: CompactDynamicImageMosaicWidthPreferenceKey.self,
                value: proxy.size.width
            )
        }
    }

    private func updateAvailableWidth(_ width: CGFloat) {
        let roundedWidth = floor(width)
        guard roundedWidth > 1, abs(availableWidth - roundedWidth) > 0.5 else { return }
        availableWidth = roundedWidth
    }
}

private struct CompactDynamicImageMosaicWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let nextWidth = nextValue()
        if nextWidth > 0 {
            value = nextWidth
        }
    }
}
