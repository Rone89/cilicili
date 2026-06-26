import SwiftUI

enum HomePullRefreshCoordinateSpace {
    static let name = "homePullRefreshScroll"
    static let distanceStep: CGFloat = 10

    static func quantizedPullDistance(_ distance: CGFloat) -> CGFloat {
        let normalized = max(0, distance)
        guard normalized > 0 else { return 0 }
        return (normalized / distanceStep).rounded(.down) * distanceStep
    }
}

struct HomePullRefreshDistancePreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
