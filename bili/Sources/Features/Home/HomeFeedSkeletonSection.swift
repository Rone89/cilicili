import SwiftUI

struct HomeFeedSkeletonSection: View {
    let metrics: HomeFeedLayoutMetrics

    var body: some View {
        SkeletonLoadingContainer {
            if metrics.mode.isDoubleColumn {
                LazyVGrid(columns: metrics.feedColumns, spacing: metrics.feedSpacing) {
                    ForEach(0..<6, id: \.self) { _ in
                        VideoFeedSkeletonCard(style: .grid)
                    }
                }
                .padding(.horizontal, metrics.feedHorizontalPadding)
            } else if metrics.mode == .borderedSingleColumn {
                LazyVStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { _ in
                        VideoFeedSkeletonCard(
                            style: .borderedSingleColumn(
                                coverSize: metrics.borderedSingleColumnCoverSize
                                    ?? CGSize(width: 140, height: 88)
                            )
                        )
                    }
                }
                .padding(.horizontal, metrics.singleColumnHorizontalPadding)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { _ in
                        VideoFeedSkeletonCard(style: .singleColumn)
                    }
                }
                .padding(.horizontal, metrics.singleColumnHorizontalPadding)
            }
        }
        .allowsHitTesting(false)
    }
}
