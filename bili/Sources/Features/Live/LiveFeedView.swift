import SwiftUI

struct LiveFeedView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var libraryStore: LibraryStore
    @ObservedObject var viewModel: LiveViewModel

    var body: some View {
        let horizontalInset = libraryStore.standardPageHorizontalInset

        ScrollView {
            VStack(spacing: 0) {
                LiveFeedContent(viewModel: viewModel)
                    .padding(.horizontal, horizontalInset)
                    .padding(.bottom, 22)
            }
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .nativeTopScrollEdgeEffect()
        .scrollBounceBehavior(.always, axes: .vertical)
        .background(Color(.systemBackground))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                LiveFeedRefreshButton(viewModel: viewModel)
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

private struct LiveFeedContent: View {
    @ObservedObject var viewModel: LiveViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.rooms.isEmpty && viewModel.state.isLoading {
                LiveFeedLoadingState()
            } else if viewModel.rooms.isEmpty {
                LiveFeedEmptyState(viewModel: viewModel)
            } else {
                LiveFeedRoomList(viewModel: viewModel)
            }
        }
    }
}

private struct LiveFeedLoadingState: View {
    var body: some View {
        LiveFeedSkeletonList()
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

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

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

private struct LiveFeedRefreshButton: View {
    @ObservedObject var viewModel: LiveViewModel

    var body: some View {
        Button {
            Task { await viewModel.refresh() }
        } label: {
            if viewModel.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .disabled(viewModel.isRefreshing || (viewModel.rooms.isEmpty && viewModel.state.isLoading))
        .accessibilityLabel("刷新推荐直播间")
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
