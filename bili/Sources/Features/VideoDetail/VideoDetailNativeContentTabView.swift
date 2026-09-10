import SwiftUI

struct VideoDetailNativeContentTabView<Content: View>: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    @Binding var selection: VideoDetailContentTab
    let layoutWidth: CGFloat
    let topInset: CGFloat
    var scrollAdjustment: VideoDetailScrollAdjustment?
    let mountsSecondaryContent: Bool
    var hidesBottomToolbar = false
    var showsCommentComposerButton = false
    var onOpenCommentComposer: (() -> Void)?
    let onScrollOffsetChange: ((VideoDetailContentTab, CGFloat) -> Void)?
    let content: (VideoDetailContentTab, Bool) -> Content

    var body: some View {
        tabContent
            .ignoresSafeArea(.container, edges: .bottom)
            .toolbar {
                if showsCommentComposerButton {
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        VideoDetailToolbarCommentComposerButton(action: {})
                            .hidden()
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    .sharedBackgroundVisibility(.hidden)
                    ToolbarSpacer(.fixed, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        VideoDetailToolbarSegmentedPickerView(selection: $selection)
                            .frame(width: VideoDetailToolbarSegmentedPickerView.compactWidth)
                    }
                    ToolbarSpacer(.fixed, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        Group {
                            if selection == .comments, let onOpenCommentComposer {
                                VideoDetailToolbarCommentComposerButton(action: onOpenCommentComposer)
                                    .transition(
                                        .scale(scale: 0.82)
                                            .combined(with: .opacity)
                                    )
                            } else {
                                Color.clear
                                    .frame(
                                        width: VideoDetailToolbarCommentComposerButton.size,
                                        height: VideoDetailToolbarCommentComposerButton.size
                                    )
                            }
                        }
                        .animation(.smooth(duration: 0.22), value: selection)
                        .allowsHitTesting(selection == .comments)
                        .accessibilityHidden(selection != .comments)
                    }
                    .sharedBackgroundVisibility(selection == .comments ? .automatic : .hidden)
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                } else {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Spacer(minLength: 0)
                        VideoDetailToolbarSegmentedPickerView(selection: $selection)
                            .frame(width: VideoDetailToolbarSegmentedPickerView.compactWidth)
                        Spacer(minLength: 0)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .bottomBar)
            .toolbarVisibility(hidesBottomToolbar ? .hidden : .automatic, for: .bottomBar)
            .toolbarVisibility(.hidden, for: .tabBar)
            .tint(appTintColor)
    }

    private var tabContent: some View {
        ZStack {
            if selection == .detail {
                page(for: .detail)
                    .transition(.move(edge: .leading))
            }

            if selection == .comments {
                page(for: .comments)
                    .transition(.move(edge: .trailing))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .animation(.smooth(duration: 0.28), value: selection)
        .background(VideoDetailTheme.background)
    }

    private func page(for tab: VideoDetailContentTab) -> some View {
        VideoDetailNativeContentTabPage(
            tab: tab,
            layoutWidth: layoutWidth,
            topInset: topInset,
            scrollAdjustment: scrollAdjustment,
            onScrollOffsetChange: onScrollOffsetChange,
            content: { tab in
                content(
                    tab,
                    mountsSecondaryContent || (tab == .comments && selection == .comments)
                )
            }
        )
    }
}

private struct VideoDetailToolbarCommentComposerButton: View {
    static let size: CGFloat = 38

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "bubble")
                .frame(width: Self.size, height: Self.size)
        }
        .tint(.primary)
        .accessibilityLabel("发表评论")
        .accessibilityIdentifier("video.detail.toolbar-comment-compose")
    }
}
