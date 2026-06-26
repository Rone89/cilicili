import SwiftUI

struct LiveFeedView: View {
    @ObservedObject var viewModel: LiveViewModel

    var body: some View {
        ScrollView {
            LiveFeedContent(viewModel: viewModel)
            .padding(.horizontal, 12)
            .padding(.top, 2)
            .padding(.bottom, 22)
        }
        .nativeTopScrollEdgeEffect()
        .scrollBounceBehavior(.always, axes: .vertical)
        .background(Color(.systemBackground))
        .refreshable {
            await viewModel.refresh()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                LiveFeedRefreshButton(viewModel: viewModel)
            }
        }
        .task {
            await viewModel.loadInitial()
        }
        .overlay {
            LiveFeedErrorOverlay(viewModel: viewModel)
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
        LiveFeedSkeletonList(horizontalPadding: 0, topPadding: 0)
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

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.rooms) { room in
                LiveFeedRoomLink(room: room, viewModel: viewModel)
            }

            if viewModel.isLoadingMore {
                ForEach(0..<2, id: \.self) { _ in
                    LiveRoomSkeletonCard()
                        .allowsHitTesting(false)
                }
            } else if let message = viewModel.loadMoreMessage {
                LiveFeedFooter(text: message, showsProgress: false)
            }
        }
    }
}

private struct LiveFeedRoomLink: View {
    let room: LiveRoom
    @ObservedObject var viewModel: LiveViewModel

    var body: some View {
        NavigationLink(value: room) {
            LiveRoomCard(room: room)
        }
        .buttonStyle(.plain)
        .padding(.top, 9)
        .padding(.bottom, 14)
        .onAppear {
            Task { await viewModel.loadMoreIfNeeded(current: room) }
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
