import SwiftUI

struct VideoDetailNativeContentTabView<Content: View>: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    @Binding var selection: VideoDetailContentTab
    let layoutWidth: CGFloat
    let topInset: CGFloat
    var scrollAdjustment: VideoDetailScrollAdjustment?
    let minimizesTabBarOnScroll: Bool
    let onScrollOffsetChange: (VideoDetailContentTab, CGFloat) -> Void
    let content: (VideoDetailContentTab) -> Content

    var body: some View {
        TabView(selection: $selection) {
            Tab(value: VideoDetailContentTab.detail) {
                VideoDetailNativeContentTabPage(
                    tab: .detail,
                    layoutWidth: layoutWidth,
                    topInset: topInset,
                    scrollAdjustment: scrollAdjustment,
                    onScrollOffsetChange: onScrollOffsetChange,
                    content: content
                )
            } label: {
                Label(VideoDetailContentTab.detail.title, systemImage: VideoDetailContentTab.detail.systemImage)
            }

            Tab(value: VideoDetailContentTab.comments) {
                VideoDetailNativeContentTabPage(
                    tab: .comments,
                    layoutWidth: layoutWidth,
                    topInset: topInset,
                    scrollAdjustment: scrollAdjustment,
                    onScrollOffsetChange: onScrollOffsetChange,
                    content: content
                )
            } label: {
                Label(VideoDetailContentTab.comments.title, systemImage: VideoDetailContentTab.comments.systemImage)
            }
        }
        .tint(appTintColor)
        .tabBarMinimizeBehavior(minimizesTabBarOnScroll ? .onScrollDown : .never)
        .toolbarBackground(.automatic, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .background(VideoDetailTheme.background)
    }
}
