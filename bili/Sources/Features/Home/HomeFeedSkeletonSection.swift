import SwiftUI

struct HomeFeedSkeletonSection: View {
    let metrics: HomeFeedLayoutMetrics

    var body: some View {
        if metrics.mode == .doubleColumn {
            LazyVGrid(columns: metrics.doubleColumns, spacing: metrics.feedSpacing) {
                ForEach(0..<6, id: \.self) { _ in
                    VideoFeedSkeletonCard(style: .grid)
                }
            }
            .padding(.horizontal, metrics.feedHorizontalPadding)
            .padding(.top, 2)
            .allowsHitTesting(false)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { _ in
                    VideoFeedSkeletonCard(style: .singleColumn)
                }
            }
            .padding(.horizontal, metrics.singleColumnHorizontalPadding)
            .padding(.top, 2)
            .allowsHitTesting(false)
        }
    }
}
