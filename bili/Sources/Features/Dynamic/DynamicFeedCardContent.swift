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

            if let video = display.video {
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

private struct DynamicFeedCardTextSection: View {
    let display: DynamicFeedCardDisplayModel
    let preferredWidth: CGFloat?
    @Binding var isTextExpanded: Bool

    var body: some View {
        if let text = display.topLevelDisplayText, !text.isEmpty {
            DynamicFeedTextContent(
                collapsedInput: display.collapsedTextInput,
                expandedInput: display.expandedTextInput,
                preferredWidth: preferredWidth,
                showsExpandButton: display.showsExpandButton,
                isExpanded: $isTextExpanded
            )
        }
    }
}

private struct DynamicFeedCardActionSection: View {
    let item: DynamicFeedItem
    let display: DynamicFeedCardDisplayModel
    let onShowComments: () -> Void

    var body: some View {
        DynamicFeedActionBar(
            display: display,
            initialIsLiked: item.isLiked,
            initialLikeCount: display.initialLikeCount,
            onShowComments: onShowComments
        )
    }
}

func dynamicInsetWidth(_ contentWidth: CGFloat?, inset: CGFloat) -> CGFloat? {
    contentWidth.map { max(floor($0 - inset * 2), 0) }
}
