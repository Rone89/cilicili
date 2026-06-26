import SwiftUI

struct DynamicFeedScrollContent: View {
    let api: BiliAPIClient
    @ObservedObject var viewModel: DynamicViewModel
    let isLoggedIn: Bool
    let contentWidth: CGFloat

    var body: some View {
        ScrollView {
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
        .rootFloatingTabBarContentPadding()
        .nativeTopScrollEdgeEffect()
        .background(Color(.systemBackground))
        .refreshable {
            await viewModel.refresh()
        }
        .task(id: isLoggedIn) {
            await viewModel.loadInitial()
        }
        .overlay {
            DynamicFeedErrorOverlay(viewModel: viewModel, isLoggedIn: isLoggedIn)
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
            FollowedLiveStrip(rooms: viewModel.followedLiveRooms)

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
