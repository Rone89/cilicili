import SwiftUI

struct DynamicFeedCardTextSection: View {
    let display: DynamicFeedCardDisplayModel
    let preferredWidth: CGFloat?
    let onOpenDetail: (() -> Void)?
    @Binding var isTextExpanded: Bool

    var body: some View {
        if let text = display.topLevelDisplayText, !text.isEmpty {
            DynamicFeedTextContent(
                collapsedInput: display.collapsedTextInput,
                expandedInput: display.expandedTextInput,
                copyText: text,
                preferredWidth: preferredWidth,
                showsExpandButton: display.showsExpandButton,
                onOpenDetail: onOpenDetail,
                isExpanded: $isTextExpanded
            )
        }
    }
}

struct DynamicFeedCardActionSection: View {
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
