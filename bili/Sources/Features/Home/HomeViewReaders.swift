import SwiftUI

struct HomePullRefreshOffsetReader: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: HomePullRefreshDistancePreferenceKey.self,
                value: HomePullRefreshCoordinateSpace.quantizedPullDistance(
                    proxy.frame(in: .named(HomePullRefreshCoordinateSpace.name)).minY
                )
            )
        }
        .frame(height: 0)
    }
}
