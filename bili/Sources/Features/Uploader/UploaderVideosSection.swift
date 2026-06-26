import SwiftUI

struct UploaderVideosSection: View {
    @ObservedObject var viewModel: UploaderViewModel
    let gridCoverSize: CGSize?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

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
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(viewModel.videos) { video in
                UploaderVideoGridItem(
                    video: video,
                    gridCoverSize: gridCoverSize
                ) {
                    await viewModel.loadMoreIfNeeded(current: video)
                }
            }

            if viewModel.state.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .gridCellColumns(2)
                    .padding()
            }
        }
        .padding(.horizontal, 12)
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
    let gridCoverSize: CGSize?
    let loadMoreIfNeeded: () async -> Void

    var body: some View {
        VideoRouteLink(video) {
            VideoCardView(
                video: video,
                showsCoverViewCountBadge: false,
                fixedCoverSize: gridCoverSize
            )
        }
        .task {
            await loadMoreIfNeeded()
        }
    }
}
