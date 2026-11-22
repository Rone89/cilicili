import SwiftUI

struct LiveFeedView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.feedChromeTitleState) private var titleState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var libraryStore: LibraryStore
    @ObservedObject var viewModel: LiveViewModel
    var showsNativeRefreshButton = true
    @State private var containerSize: CGSize = .zero

    private var adaptiveEnabled: Bool {
        libraryStore.adaptiveLargeScreenLayoutExperimentEnabled
    }

    private var horizontalInset: CGFloat {
        adaptiveEnabled
            ? AdaptiveLayoutPolicy.horizontalInset(
                for: containerSize.width,
                horizontalSizeClass: horizontalSizeClass,
                containerHeight: containerSize.height,
                adaptiveEnabled: true
            )
            : libraryStore.standardPageHorizontalInset
    }

    private var columnCount: Int {
        adaptiveEnabled && containerSize.width > 0
            ? AdaptiveLayoutPolicy.feedGridColumnCount(
                containerWidth: containerSize.width,
                containerHeight: containerSize.height,
                horizontalSizeClass: horizontalSizeClass,
                horizontalInset: horizontalInset,
                columnSpacing: 12,
                adaptiveEnabled: true
            )
            : 2
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                LiveFeedContent(viewModel: viewModel, columnCount: columnCount)
                    .frame(maxWidth: adaptiveEnabled ? AdaptiveLayoutPolicy.multiColumnFeedMaxWidth : .infinity)
                    .padding(.horizontal, horizontalInset)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 22)
            }
        }
        .onGeometryChange(for: CGSize.self) { geometry in
            CGSize(
                width: AdaptiveLayoutPolicy.safeContentWidth(for: geometry),
                height: geometry.size.height
            )
        } action: { _, size in
            let rounded = CGSize(width: size.width.rounded(.down), height: size.height.rounded(.down))
            guard abs(rounded.width - containerSize.width) > 0.5
                    || abs(rounded.height - containerSize.height) > 0.5 else { return }
            containerSize = rounded
        }
        .rootFloatingTabBarContentPadding()
        .contentMargins(.top, 0, for: .scrollContent)
        .onScrollGeometryChange(for: LiveTitleScrollSample.self) { geometry in
            LiveTitleScrollSample(
                offset: geometry.contentOffset.y + geometry.contentInsets.top,
                topInset: geometry.contentInsets.top
            )
        } action: { _, sample in
            titleState?.update(scrollSum: sample.offset, insetsTop: sample.topInset, isRefreshing: viewModel.isRefreshing)
        }
        .scrollsToTopOnRootTabReselection()
        .nativeTopScrollEdgeEffect(hidesRootNavigationTitle: titleState == nil)
        .scrollBounceBehavior(.always, axes: .vertical)
        .background(Color(.systemBackground))
        .toolbar {
            if showsNativeRefreshButton {
                ToolbarItem(placement: .topBarTrailing) {
                    LiveRefreshToolbarButton(
                        isLoading: viewModel.isRefreshing || (viewModel.rooms.isEmpty && viewModel.state.isLoading)
                    ) {
                        Task { await viewModel.refresh() }
                    }
                }
            }
        }
        .task {
            await viewModel.loadInitial()
        }
        .refreshable(action: viewModel.refresh)
        .overlay {
            LiveFeedErrorOverlay(viewModel: viewModel)
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

}

private struct LiveTitleScrollSample: Equatable {
    let offset: CGFloat
    let topInset: CGFloat
}

private struct LiveFeedContent: View {
    @ObservedObject var viewModel: LiveViewModel
    let columnCount: Int

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.rooms.isEmpty && viewModel.state.isLoading {
                LiveFeedLoadingState(columnCount: columnCount)
            } else if viewModel.rooms.isEmpty {
                LiveFeedEmptyState(viewModel: viewModel)
            } else {
                LiveFeedRoomList(viewModel: viewModel, columnCount: columnCount)
            }
        }
    }
}

private struct LiveFeedLoadingState: View {
    let columnCount: Int

    var body: some View {
        LiveFeedSkeletonList(columnCount: columnCount)
            .allowsHitTesting(false)
    }
}

private struct LiveFeedEmptyState: View {
    @ObservedObject var viewModel: LiveViewModel

    var body: some View {
        EmptyStateView(
            title: viewModel.emptyTitle,
            systemImage: "play.tv",
            message: viewModel.emptyMessage
        )
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }
}

private struct LiveFeedRoomList: View {
    @ObservedObject var viewModel: LiveViewModel
    let columnCount: Int

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: max(columnCount, 1))
    }

    var body: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(viewModel.rooms) { room in
                    LiveFeedRoomLink(room: room, viewModel: viewModel)
                }

                if viewModel.isLoadingMore {
                    InlineLoadingStateView(title: "正在加载更多")
                        .padding(.vertical, 8)
                        .gridCellColumns(columns.count)
                }
            }

            if !viewModel.isLoadingMore, let message = viewModel.loadMoreMessage {
                LiveFeedFooter(text: message, showsProgress: false)
                    .padding(.top, 8)
            }
        }
    }
}

private struct LiveFeedRoomLink: View {
    let room: LiveRoom
    @ObservedObject var viewModel: LiveViewModel
    @Environment(\.openLiveRoomAction) private var openLiveRoom

    @ViewBuilder
    var body: some View {
        if let openLiveRoom {
            Button {
                openLiveRoom(room)
            } label: {
                LiveRoomCard(room: room)
            }
            .buttonStyle(.plain)
            .onAppear {
                Task { await viewModel.loadMoreIfNeeded(current: room) }
            }
        } else {
            NavigationLink(value: room) {
                LiveRoomCard(room: room)
            }
            .buttonStyle(.plain)
            .onAppear {
                Task { await viewModel.loadMoreIfNeeded(current: room) }
            }
        }
    }
}

struct LiveRefreshToolbarButton: View {
    let isLoading: Bool
    let onRefresh: () -> Void

    var body: some View {
        Button(action: onRefresh) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label("刷新推荐直播间", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
        }
        .tint(.primary)
        .disabled(isLoading)
        .accessibilityLabel("刷新推荐直播间")
        .accessibilityIdentifier("live.feed.refresh")
    }
}

private struct LiveFeedErrorOverlay: View {
    @ObservedObject var viewModel: LiveViewModel

    var body: some View {
        if case .failed(let message) = viewModel.state, viewModel.rooms.isEmpty {
            ErrorStateView(title: "直播加载失败", message: message) {
                Task { await viewModel.refresh() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground).opacity(0.96))
        }
    }
}
