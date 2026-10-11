import SwiftUI

struct DynamicFeedScrollContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let api: BiliAPIClient
    @ObservedObject var viewModel: DynamicViewModel
    let isLoggedIn: Bool
    let contentWidth: CGFloat
    let horizontalInset: CGFloat

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                DynamicFeedBodyContent(
                    api: api,
                    viewModel: viewModel,
                    isLoggedIn: isLoggedIn,
                    contentWidth: contentWidth
                )
                .frame(width: contentWidth, alignment: .leading)
                .padding(.horizontal, horizontalInset)
                .padding(.bottom, 18)
            }
        }
        .rootFloatingTabBarContentPadding()
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollBounceBehavior(.always, axes: .vertical)
        .defersRemoteImageLoadsDuringFastScroll()
        .background(Color(.systemBackground))
        .scrollsToTopOnRootTabReselection()
        .nativeTopScrollEdgeEffect()
        .task(id: DynamicFeedLoadIdentity(model: ObjectIdentifier(viewModel), isLoggedIn: isLoggedIn)) {
            await viewModel.loadInitial()
        }
        .refreshable(action: refreshFromNativePull)
        .overlay {
            DynamicFeedErrorOverlay(viewModel: viewModel, isLoggedIn: isLoggedIn)
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    private func refreshFromNativePull() async {
        guard isLoggedIn else { return }
        await viewModel.refresh()
    }

}

private struct DynamicFeedBodyContent: View {
    let api: BiliAPIClient
    @ObservedObject var viewModel: DynamicViewModel
    let isLoggedIn: Bool
    let contentWidth: CGFloat

    var body: some View {
        LazyVStack(spacing: 0) {
            if viewModel.feedKind == .all {
                FollowedLiveStrip(
                    items: viewModel.topUploaderStripItems,
                    isLoading: isLoggedIn && viewModel.isTopUploaderStripLoading
                )
            }

            if !isLoggedIn {
                DynamicLoginEmptyState()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 110)
            } else if viewModel.items.isEmpty && viewModel.state != .loaded {
                DynamicFeedSkeletonList()
            } else if viewModel.items.isEmpty {
                DynamicFeedEmptyState(isVideoFeed: viewModel.feedKind == .video)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 110)
                if viewModel.hasMoreItems {
                    DynamicFeedFooter(viewModel: viewModel)
                }
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

private struct DynamicFeedLoadIdentity: Hashable {
    let model: ObjectIdentifier
    let isLoggedIn: Bool
}
