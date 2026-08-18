import SwiftUI

private enum DynamicPullRefreshCoordinateSpace {
    static let name = "dynamic-feed-pull-refresh"
}

struct DynamicFeedScrollContent: View {
    let api: BiliAPIClient
    @ObservedObject var viewModel: DynamicViewModel
    let isLoggedIn: Bool
    let contentWidth: CGFloat
    let pullRefreshTriggerDistance: CGFloat
    @State private var pullRefreshDistance: CGFloat = 0
    @State private var pullRefreshActions = HomeFeedRefreshActions()

    var body: some View {
        ScrollView {
            HomePullRefreshOffsetReader(
                coordinateSpaceName: DynamicPullRefreshCoordinateSpace.name
            )

            DynamicFeedBodyContent(
                api: api,
                viewModel: viewModel,
                isLoggedIn: isLoggedIn,
                contentWidth: contentWidth
            )
            .padding(.horizontal, 16)
            .padding(.top, 28)
            .padding(.bottom, 18)
        }
        .coordinateSpace(name: DynamicPullRefreshCoordinateSpace.name)
        .rootFloatingTabBarContentPadding()
        .nativeTopScrollEdgeEffect()
        .scrollBounceBehavior(.always, axes: .vertical)
        .defersRemoteImageLoadsDuringFastScroll()
        .background(Color(.systemBackground))
        .onPreferenceChange(HomePullRefreshDistancePreferenceKey.self) { pullDistance in
            handlePullRefreshDistanceChange(pullDistance)
        }
        .task(id: isLoggedIn) {
            await viewModel.loadInitial()
        }
        .homeFeedPullRefreshLayout(
            pullDistance: pullRefreshDistance,
            triggerDistance: pullRefreshTriggerDistance,
            isRefreshing: viewModel.isRefreshing
        )
        .overlay {
            DynamicFeedErrorOverlay(viewModel: viewModel, isLoggedIn: isLoggedIn)
        }
    }

    private func handlePullRefreshDistanceChange(_ pullDistance: CGFloat) {
        pullRefreshDistance = pullDistance
        guard isLoggedIn else { return }
        pullRefreshActions.handleConfiguredPullRefresh(
            pullDistance: pullDistance,
            triggerDistance: pullRefreshTriggerDistance,
            isRefreshing: viewModel.isRefreshing
        ) {
            await viewModel.refresh()
            return viewModel.state == .loaded
        }
    }
}

private struct DynamicFeedBodyContent: View {
    let api: BiliAPIClient
    @ObservedObject var viewModel: DynamicViewModel
    let isLoggedIn: Bool
    let contentWidth: CGFloat

    var body: some View {
        LazyVStack(spacing: 0) {
            FollowedLiveStrip(
                items: viewModel.topUploaderStripItems,
                isLoading: isLoggedIn && viewModel.isTopUploaderStripLoading
            )

            if !isLoggedIn {
                DynamicLoginEmptyState()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 110)
            } else if viewModel.items.isEmpty && viewModel.state.isLoading {
                DynamicFeedSkeletonList()
            } else if viewModel.items.isEmpty {
                DynamicFeedEmptyState()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 110)
            } else {
                DynamicFeedItemsList(
                    api: api,
                    viewModel: viewModel,
                    items: viewModel.items,
                    contentWidth: contentWidth
                )

                DynamicFeedFooter(viewModel: viewModel)
                    .padding(.top, 6)
            }
        }
    }
}
