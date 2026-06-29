import SwiftUI

struct UploaderVideosSection: View {
    @ObservedObject var viewModel: UploaderViewModel
    let metrics: HomeFeedLayoutMetrics

    var body: some View {
        if viewModel.videos.isEmpty && viewModel.state.isLoading {
            UploaderVideosLoadingState()
        } else if viewModel.videos.isEmpty {
            EmptyStateView(title: "暂无投稿", systemImage: "film", message: "下拉刷新后再试。")
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        } else {
            videoGrid
        }
    }

    private var videoGrid: some View {
        LazyVGrid(columns: metrics.feedColumns, spacing: metrics.feedSpacing) {
            ForEach(viewModel.videos) { video in
                UploaderVideoGridItem(
                    video: video,
                    metrics: metrics
                ) {
                    await viewModel.loadMoreIfNeeded(current: video)
                }
            }

            if viewModel.state.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .gridCellColumns(metrics.feedColumns.count)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, metrics.feedHorizontalPadding)
    }
}

private struct UploaderVideosLoadingState: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()

            Text("正在加载投稿")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

private struct UploaderVideoGridItem: View {
    let video: VideoItem
    let metrics: HomeFeedLayoutMetrics
    let loadMoreIfNeeded: () async -> Void

    var body: some View {
        VideoRouteLink(video) {
            HomeFeedVideoCardLabel(
                metrics: metrics,
                display: VideoCardDisplayModel(video: video),
                showsAuthorIdentity: false
            )
        }
        .task {
            await loadMoreIfNeeded()
        }
    }
}
