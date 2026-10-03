import SwiftUI

struct CompactDynamicImageMosaicContent: View {
    let imageCount: Int
    let displayedImages: [CompactDynamicImageDisplayItem]
    let layout: CompactDynamicImageMosaicLayout
    let previewItems: [ZoomyImagePreviewItem]
    let previewGroup: ZoomyImagePreviewGroup
    let accessibilityName: String
    let placeholderFill: Color
    let adaptiveWidth: CGFloat

    var body: some View {
        if displayedImages.count > 1 {
            DynamicAdaptiveImageGrid(
                imagesCount: imageCount,
                displayedImages: adaptiveDisplayedImages,
                previewItems: previewItems,
                previewGroup: previewGroup,
                width: adaptiveWidth,
                outerCornerRadius: CompactDynamicImageMosaicMetrics.groupCornerRadius,
                accessibilityName: accessibilityName
            )
        } else {
            content
        }
    }

    private var adaptiveDisplayedImages: [DynamicImageDisplayItem] {
        displayedImages.map {
            DynamicImageDisplayItem(
                id: $0.id,
                index: $0.index,
                image: $0.image,
                aspectRatio: $0.aspectRatio
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch displayedImages.count {
        case 0:
            EmptyView()
        case 1:
            CompactDynamicSingleImageMosaicLayout(tileContext: tileContext, item: displayedImages.first)
        case 2:
            CompactDynamicEqualImageGrid(tileContext: tileContext, layout: layout, columns: 2, side: CompactDynamicImageMosaicMetrics.mediumSide)
        case 3:
            CompactDynamicThreeImageMosaicLayout(tileContext: tileContext, layout: layout)
        case 4:
            CompactDynamicEqualImageGrid(tileContext: tileContext, layout: layout, columns: 2, side: CompactDynamicImageMosaicMetrics.mediumSide)
        case 5:
            CompactDynamicFiveImageMosaicLayout(tileContext: tileContext, layout: layout)
        case 6:
            CompactDynamicEqualImageGrid(tileContext: tileContext, layout: layout, columns: 3, side: CompactDynamicImageMosaicMetrics.smallSide)
        case 7:
            CompactDynamicSevenImageMosaicLayout(tileContext: tileContext, layout: layout)
        case 8:
            CompactDynamicEightImageMosaicLayout(tileContext: tileContext, layout: layout)
        default:
            CompactDynamicEqualImageGrid(tileContext: tileContext, layout: layout, columns: 3, side: CompactDynamicImageMosaicMetrics.smallSide)
        }
    }

    private var tileContext: CompactDynamicImageTileContext {
        CompactDynamicImageTileContext(
            imageCount: imageCount,
            previewItems: previewItems,
            previewGroup: previewGroup,
            accessibilityName: accessibilityName,
            placeholderFill: placeholderFill
        )
    }
}
