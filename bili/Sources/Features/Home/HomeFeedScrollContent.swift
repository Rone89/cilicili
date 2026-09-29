import SwiftUI

struct HomeFeedScrollContent<FeedContent: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isShowingInitialPlaceholder: Bool
    let isEmpty: Bool
    let mode: HomeFeedMode
    @ViewBuilder let feedContent: () -> FeedContent

    var body: some View {
        ZStack(alignment: .top) {
            if mode == .recommend {
                feedStateContent
                    .transition(reduceMotion ? .identity : .move(edge: .leading))
            } else {
                feedStateContent
                    .transition(reduceMotion ? .identity : .move(edge: .trailing))
            }
        }
        .clipped()
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: mode)
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
