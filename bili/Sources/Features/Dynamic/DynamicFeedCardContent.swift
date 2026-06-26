import SwiftUI

struct DynamicStandardFeedCardContent: View {
    let item: DynamicFeedItem
    let display: DynamicFeedCardDisplayModel
    let contentWidth: CGFloat?
    @Binding var isTextExpanded: Bool
    let onShowComments: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            authorHeader
                .padding(.horizontal, 12)

            DynamicFeedCardTextSection(
                display: display,
                preferredWidth: textWidth,
                isTextExpanded: $isTextExpanded
            )
                .padding(.horizontal, 12)

            if let paidContent = display.paidContent, display.paidContentRendersAsTextOnly {
                DynamicPaidArticleTextRouteLink(content: paidContent, chargeURL: display.paidChargeURL) {
                    DynamicPaidArticleTextPreview(content: paidContent)
                }
                .padding(.horizontal, 12)
            } else if let paidContent = display.paidContent {
                DynamicPaidContentRouteLink(content: paidContent, video: display.paidVideo) {
                    DynamicPaidContentPreview(content: paidContent, style: .large)
                }
            } else if let video = display.video {
                VideoRouteLink(video) {
                    DynamicArchivePreview(video: video, style: .large, showsHeader: false)
                }
            }

            if let live = display.live {
                DynamicLiveRouteLink(room: display.liveRoom) {
                    DynamicLivePreview(live: live, style: .large)
                }
            }

            if !display.imageItems.isEmpty {
                DynamicImageThumbnailStrip(
                    images: display.imageItems,
                    availableWidth: contentWidth
                )
            }

            if let original = item.original {
                DynamicOriginalPreview(
                    item: original,
                    parentID: item.id,
                    contentWidth: textWidth
                )
                .padding(.horizontal, 12)
            } else if item.isForward {
                DynamicForwardUnavailableView()
                    .padding(.horizontal, 12)
            }

            DynamicFeedCardActionSection(
                item: item,
                display: display,
                onShowComments: onShowComments
            )
        }
        .padding(.top, 5)
        .padding(.bottom, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var authorHeader: some View {
        DynamicFeedAuthorHeader(display: display)
    }

    private var textWidth: CGFloat? {
        dynamicInsetWidth(contentWidth, inset: 12)
    }
}
