import SwiftUI

struct VideoDetailNativeContentTabView<Content: View>: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    @Binding var selection: VideoDetailContentTab
    let layoutWidth: CGFloat
    let topInset: CGFloat
    var scrollAdjustment: VideoDetailScrollAdjustment?
    let mountsSecondaryContent: Bool
    let onScrollOffsetChange: ((VideoDetailContentTab, CGFloat) -> Void)?
    let content: (VideoDetailContentTab, Bool) -> Content

    var body: some View {
        tabContent
            .ignoresSafeArea(.container, edges: .bottom)
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Spacer(minLength: 0)
                    VideoDetailToolbarSegmentedPickerView(selection: $selection)
                        .frame(width: VideoDetailToolbarSegmentedPickerView.compactWidth)
                    Spacer(minLength: 0)
                }
            }
            .toolbarBackground(.hidden, for: .bottomBar)
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
