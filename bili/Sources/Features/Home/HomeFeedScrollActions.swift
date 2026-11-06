import Combine
import SwiftUI

@MainActor
final class HomeFeedScrollActions: ObservableObject {
    @Published private(set) var topScrollRequestID = 0
    @Published private(set) var programmaticRefreshRequestID = 0
    /// 最近一次回顶请求是否带动画。切换推荐/热门时要求瞬时回顶，
    /// 点首页 tab 回顶仍保留平滑滚动。
    private(set) var topScrollRequestIsAnimated = true

    func requestScrollToTop(animated: Bool = true) {
        topScrollRequestIsAnimated = animated
        topScrollRequestID &+= 1
    }

    func requestProgrammaticRefresh() {
        programmaticRefreshRequestID &+= 1
    }

    func updateFeedContainerWidth(
        _ width: CGFloat,
        state: HomeFeedViewportState
    ) -> HomeFeedViewportState {
        var updatedState = state
        updatedState.updateFeedContainerWidth(width)
        return updatedState
    }

    func updateViewportHeight(
        _ height: CGFloat,
        state: HomeFeedViewportState
    ) -> HomeFeedViewportState {
        var updatedState = state
        _ = updatedState.updateViewportHeight(height)
        return updatedState
    }

}
