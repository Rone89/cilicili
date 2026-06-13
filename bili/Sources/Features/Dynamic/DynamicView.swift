import SwiftUI

struct DynamicView: View {
    @EnvironmentObject private var dependencies: AppDependencies

    var body: some View {
        DynamicContentRoot(
            api: dependencies.api,
            libraryStore: dependencies.libraryStore,
            sessionStore: dependencies.sessionStore
        )
        .rootNavigationTitle("动态")
        .nativeTopNavigationChrome()
    }
}

private struct DynamicContentRoot: View {
    let api: BiliAPIClient
    let libraryStore: LibraryStore
    @ObservedObject var sessionStore: SessionStore
    @StateObject private var holder = DynamicViewModelHolder()

    var body: some View {
        Group {
            if let viewModel = holder.viewModel {
                content(viewModel, isLoggedIn: sessionStore.isLoggedIn)
            } else {
                initialContent(isLoggedIn: sessionStore.isLoggedIn)
                    .task {
                        holder.configure(
                            api: api,
                            libraryStore: libraryStore,
                            sessionStore: sessionStore
                        )
                    }
            }
        }
    }

    @ViewBuilder
    private func initialContent(isLoggedIn: Bool) -> some View {
        if isLoggedIn {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { index in
                        DynamicFeedSkeletonCard()

                        if index != 2 {
                            Divider()
                                .padding(.leading, 66)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 28)
            }
            .rootFloatingTabBarContentPadding()
            .background(Color(.systemBackground))
        } else {
            dynamicLoginEmptyState
                .rootFloatingTabBarContentPadding()
                .background(Color(.systemBackground))
        }
    }

    @ViewBuilder
    private func content(_ viewModel: DynamicViewModel, isLoggedIn: Bool) -> some View {
        GeometryReader { proxy in
            let contentWidth = max(floor(proxy.size.width - 32), 0)

            ScrollView {
            LazyVStack(spacing: 0) {
                FollowedLiveStrip(rooms: viewModel.followedLiveRooms)

                if !isLoggedIn {
                    dynamicLoginEmptyState
                        .frame(maxWidth: .infinity)
                        .padding(.top, 110)
                } else if viewModel.items.isEmpty && viewModel.state.isLoading {
                    ForEach(0..<3, id: \.self) { index in
                        DynamicFeedSkeletonCard()
                            .allowsHitTesting(false)

                        if index != 2 {
                            Divider()
                                .padding(.leading, 66)
                        }
                    }
                } else if viewModel.items.isEmpty {
                    EmptyStateView(
                        title: "暂无动态",
                        systemImage: "sparkles",
                        message: "登录后会显示你关注 UP 的动态。"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 110)
                } else {
                    let items = viewModel.items
                    let lastItemID = items.last?.id
                    ForEach(items) { item in
                        VStack(spacing: 0) {
                            DynamicFeedCard(
                                item: item,
                                api: api,
                                contentWidth: contentWidth
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .dynamicLoadMoreTask(if: item.id == lastItemID, id: item.id) {
                                await viewModel.loadMoreIfNeeded(current: item)
                            }

                            if item.id != lastItemID {
                                Divider()
                                    .padding(.leading, 66)
                            }
                        }
                    }

                    dynamicFooter(viewModel)
                        .padding(.top, 6)
                }
            }
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
            if isLoggedIn, case .failed(let message) = viewModel.state, viewModel.items.isEmpty {
                ErrorStateView(title: "动态加载失败", message: message) {
                    Task { await viewModel.refresh() }
                }
                .background(.background.opacity(0.96))
            }
        }
        }
    }

    private var dynamicLoginEmptyState: some View {
        EmptyStateView(
            title: "暂无动态",
            systemImage: "sparkles",
            message: "登录后会显示你关注 UP 的动态。"
        )
    }

    @ViewBuilder
    private func dynamicFooter(_ viewModel: DynamicViewModel) -> some View {
        if viewModel.state.isLoading {
            DynamicFeedSkeletonCard()
                .allowsHitTesting(false)
        } else if viewModel.hasMoreItems {
            Button {
                Task { await viewModel.loadMore() }
            } label: {
                Label("加载更多", systemImage: "chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(.pink)
            .padding(.top, 10)
        } else {
            Text("没有更多动态了")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
    }
}

extension View {
    @ViewBuilder
    func dynamicLoadMoreTask<ID: Equatable>(
        if condition: Bool,
        id: ID,
        action: @escaping () async -> Void
    ) -> some View {
        if condition {
            task(id: id) {
                await action()
            }
        } else {
            self
        }
    }
}
