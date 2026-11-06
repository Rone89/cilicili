import SwiftUI

struct HomeFeedScrollContent<FeedContent: View>: View {
    let isShowingInitialPlaceholder: Bool
    let isEmpty: Bool
    let mode: HomeFeedMode
    @ViewBuilder let feedContent: () -> FeedContent

    var body: some View {
        // 推荐/热门切换不做过渡动画：两个分支保持不同 identity，
        // 切换时整块内容直接替换，避免横向滑入滑出。
        ZStack(alignment: .top) {
            if mode == .recommend {
                feedStateContent
            } else {
                feedStateContent
            }
        }
        .clipped()
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var feedStateContent: some View {
        VStack(spacing: 6) {
            if isShowingInitialPlaceholder {
                feedContent()
            } else if isEmpty {
                EmptyStateView(
                    title: "暂无内容",
                    systemImage: "play.rectangle",
                    message: "下拉刷新或切换频道再试。"
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 120)
            } else {
                feedContent()
            }
        }
    }
}
