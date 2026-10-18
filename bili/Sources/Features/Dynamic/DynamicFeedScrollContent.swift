import SwiftUI

struct DynamicFeedScrollContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let api: BiliAPIClient
    @ObservedObject var viewModel: DynamicViewModel
    var topUploaderStripViewModel: DynamicViewModel? = nil
    let isLoggedIn: Bool
    let contentWidth: CGFloat
    let horizontalInset: CGFloat
    var selectedUP: VideoOwner? = nil
    var onChooseUP: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                DynamicFeedBodyContent(
                    api: api,
                    viewModel: viewModel,
                    topUploaderStripViewModel: topUploaderStripViewModel ?? viewModel,
                    isLoggedIn: isLoggedIn,
                    contentWidth: contentWidth,
                    selectedUP: selectedUP, onChooseUP: onChooseUP
                )
                .frame(width: contentWidth, alignment: .leading)
                .padding(.horizontal, horizontalInset)
                .padding(.bottom, 18)
            }
        }
        .rootFloatingTabBarContentPadding()
        .environment(\.dynamicArticleFeedContext, viewModel.feedKind == .article)
        .modifier(DynamicFeedScrollRestoration(viewModel: viewModel))
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollBounceBehavior(.always, axes: .vertical)
        .defersRemoteImageLoadsDuringFastScroll()
        .background(Color(.systemBackground))
        .nativeTopScrollEdgeEffect()
        .task(id: DynamicFeedLoadIdentity(model: ObjectIdentifier(viewModel), isLoggedIn: isLoggedIn)) {
            if viewModel.feedKind != .all {
                topUploaderStripViewModel?.loadTopUploaderStripIfNeeded()
            }
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
        if viewModel.feedKind != .all {
            topUploaderStripViewModel?.refreshTopUploaderStrip()
        }
        await viewModel.refresh()
    }

}

private struct DynamicFeedBodyContent: View {
    let api: BiliAPIClient
    @ObservedObject var viewModel: DynamicViewModel
    let topUploaderStripViewModel: DynamicViewModel
    let isLoggedIn: Bool
    let contentWidth: CGFloat
    var selectedUP: VideoOwner? = nil
    var onChooseUP: (() -> Void)? = nil

    var body: some View {
        LazyVStack(spacing: 0) {
            DynamicFeedTopUploaderStrip(viewModel: topUploaderStripViewModel, isLoggedIn: isLoggedIn)

            if let selectedUP, let onChooseUP {
                Button(action: onChooseUP) {
                    HStack {
                        Text("正在查看：\(selectedUP.name)")
                            .lineLimit(1)
                        Spacer()
                        Label("更换", systemImage: "chevron.down")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dynamic.up.change")
            }

            if !isLoggedIn {
                DynamicLoginEmptyState()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 110)
            } else if viewModel.items.isEmpty && viewModel.state != .loaded {
                DynamicFeedSkeletonList()
            } else if viewModel.items.isEmpty {
                DynamicFeedEmptyState(isVideoFeed: viewModel.feedKind == .video, feedKind: viewModel.feedKind)
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

private struct DynamicFeedTopUploaderStrip: View {
    @ObservedObject var viewModel: DynamicViewModel
    let isLoggedIn: Bool

    var body: some View {
        FollowedLiveStrip(
            items: viewModel.topUploaderStripItems,
            isLoading: isLoggedIn && viewModel.isTopUploaderStripLoading
        )
    }
}

private struct DynamicFeedLoadIdentity: Hashable {
    let model: ObjectIdentifier
    let isLoggedIn: Bool
}
