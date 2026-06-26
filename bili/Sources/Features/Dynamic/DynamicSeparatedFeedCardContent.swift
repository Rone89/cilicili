import SwiftUI

struct DynamicSeparatedFeedCardContent: View {
    let item: DynamicFeedItem
    let display: DynamicFeedCardDisplayModel
    let contentWidth: CGFloat?
    @Binding var isTextExpanded: Bool
    let onShowComments: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            authorHeader
                .padding(.horizontal, 12)

            separatedStoryCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var separatedStoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            DynamicFeedCardTextSection(
                display: display,
                preferredWidth: textWidth,
                isTextExpanded: $isTextExpanded
            )

            if let paidContent = display.paidContent, display.paidContentRendersAsTextOnly {
                DynamicPaidArticleTextRouteLink(content: paidContent, chargeURL: display.paidChargeURL) {
                    DynamicPaidArticleTextPreview(content: paidContent)
                }
            } else if let paidContent = display.paidContent {
                DynamicPaidContentRouteLink(content: paidContent, video: display.paidVideo) {
                    DynamicPaidContentPreview(content: paidContent, style: .compact)
                }
            }

            if !display.imageItems.isEmpty {
                imageSquareGrid
            }

            if let original = item.original {
                DynamicOriginalPreview(
                    item: original,
                    parentID: item.id,
                    contentWidth: textWidth
                )
            } else if item.isForward {
                DynamicForwardUnavailableView()
            }

            DynamicFeedCardActionSection(
                item: item,
                display: display,
                onShowComments: onShowComments
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var imageSquareGrid: some View {
        DynamicImageThumbnailStrip(
            images: display.imageItems,
            horizontalBleed: 12,
            availableWidth: textWidth
        )
    }

    private var authorHeader: some View {
        DynamicFeedAuthorHeader(display: display)
    }

    private var textWidth: CGFloat? {
        dynamicInsetWidth(contentWidth, inset: 12)
    }
}
