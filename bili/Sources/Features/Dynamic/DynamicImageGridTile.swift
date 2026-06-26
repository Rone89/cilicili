import SwiftUI

struct DynamicImageGridTile: View {
    let item: DynamicImageDisplayItem
    let imagesCount: Int
    let previewItems: [ZoomyImagePreviewItem]
    let previewGroup: ZoomyImagePreviewGroup
    let displayMode: DynamicImageCell.DisplayMode

    var body: some View {
        DynamicImageButton(
            image: item.image,
            previewItems: previewItems,
            previewItemID: item.id,
            previewGroup: previewGroup,
            displayMode: displayMode
        ) {
            overflowOverlay
        }
    }

    @ViewBuilder
    private var overflowOverlay: some View {
        if item.index == 8, imagesCount > 9 {
            ZStack {
                Color.clear
                Text("+\(imagesCount - 8)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .glassEffect(.regular, in: Capsule())
            }
        }
    }
}
