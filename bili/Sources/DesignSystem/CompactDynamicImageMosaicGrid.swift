import SwiftUI

struct CompactDynamicImageMosaicGrid: View {
    @StateObject private var previewGroup = ZoomyImagePreviewGroup()
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
        if imageCount > 1 {
            CompactCommentMosaicContainer(imageCount: displayedImages.count) {
                GeometryReader { proxy in
                    if proxy.size.width > DynamicImageGridMetrics.spacing * 2 {
                        mosaicContent(width: proxy.size.width)
                    }
                }
            }
        } else if imageCount == 1 {
            mosaicContent(width: CompactDynamicImageMosaicMetrics.compactWidth)
        }
    }

    private func mosaicContent(width: CGFloat) -> some View {
        CompactDynamicImageMosaicContent(
            imageCount: imageCount,
            displayedImages: displayedImages,
            layout: layout,
            previewItems: previewItems,
            previewGroup: previewGroup,
            accessibilityName: accessibilityName,
            placeholderFill: placeholderFill,
            adaptiveWidth: width
        )
    }
}

// The outer proposal determines the canvas, not a measurement of its already
// fixed-width child. No landscape width survives the next portrait proposal.
struct CompactCommentMosaicContainer: Layout {
    let imageCount: Int

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let proposed = proposal.width ?? CompactDynamicImageMosaicMetrics.compactWidth
        let width = proposed.isFinite ? max(0, proposed) : CompactDynamicImageMosaicMetrics.compactWidth
        let height: CGFloat
        if imageCount <= 4 {
            height = width * 9 / 16
        } else {
            let spacing = DynamicImageGridMetrics.spacing
            let rows = CGFloat((imageCount + 2) / 3)
            let side = max(0, (width - spacing * 2) / 3)
            height = rows * side + max(0, rows - 1) * spacing
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading,
                          proposal: ProposedViewSize(bounds.size))
        }
    }
}
