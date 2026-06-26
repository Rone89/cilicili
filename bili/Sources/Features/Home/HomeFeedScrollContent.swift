import SwiftUI

struct HomeFeedScrollContent<FeedContent: View>: View {
    let isShowingInitialPlaceholder: Bool
    let isEmpty: Bool
    @ViewBuilder let feedContent: () -> FeedContent

    var body: some View {
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
        .padding(.top, 2)
        .padding(.bottom, 18)
    }
}
