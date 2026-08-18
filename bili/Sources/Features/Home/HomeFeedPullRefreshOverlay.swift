import SwiftUI

enum HomePullRefreshLayout {
    static let refreshingTopInset: CGFloat = 52

    static func topInset(isRefreshing: Bool) -> CGFloat {
        isRefreshing ? refreshingTopInset : 0
    }
}

struct HomeFeedPullRefreshOverlay: View {
    let pullDistance: CGFloat
    let triggerDistance: CGFloat
    let isRefreshing: Bool

    var body: some View {
        HomePullRefreshIndicator(
            pullDistance: pullDistance,
            triggerDistance: triggerDistance,
            isRefreshing: isRefreshing
        )
        .padding(.top, 6)
        .allowsHitTesting(false)
    }
}

private struct HomeFeedPullRefreshLayoutModifier: ViewModifier {
    let pullDistance: CGFloat
    let triggerDistance: CGFloat
    let isRefreshing: Bool

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear
                    .frame(height: HomePullRefreshLayout.topInset(isRefreshing: isRefreshing))
                    .animation(.smooth(duration: 0.24), value: isRefreshing)
            }
            .overlay(alignment: .top) {
                HomeFeedPullRefreshOverlay(
                    pullDistance: pullDistance,
                    triggerDistance: triggerDistance,
                    isRefreshing: isRefreshing
                )
            }
    }
}

extension View {
    func homeFeedPullRefreshLayout(
        pullDistance: CGFloat,
        triggerDistance: CGFloat,
        isRefreshing: Bool
    ) -> some View {
        modifier(
            HomeFeedPullRefreshLayoutModifier(
                pullDistance: pullDistance,
                triggerDistance: triggerDistance,
                isRefreshing: isRefreshing
            )
        )
    }
}
