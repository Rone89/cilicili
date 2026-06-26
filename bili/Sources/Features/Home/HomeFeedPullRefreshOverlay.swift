import SwiftUI

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
