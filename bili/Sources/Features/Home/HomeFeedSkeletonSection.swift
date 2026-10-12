import SwiftUI

struct HomeFeedSkeletonSection: View {
    let metrics: HomeFeedLayoutMetrics
    var viewportHeight: CGFloat? = nil

    var body: some View {
        SkeletonLoadingContainer {
            if metrics.mode.isDoubleColumn {
                LazyVGrid(columns: metrics.feedColumns, spacing: metrics.feedSpacing) {
                    ForEach(0..<itemCount, id: \.self) { _ in
                        VideoFeedSkeletonCard(style: .grid)
                    }
                }
                .padding(.horizontal, metrics.feedHorizontalPadding)
            } else if metrics.mode == .borderedSingleColumn {
                LazyVStack(spacing: 0) {
                    ForEach(0..<itemCount, id: \.self) { _ in
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
                    ForEach(0..<itemCount, id: \.self) { _ in
                        VideoFeedSkeletonCard(style: .singleColumn)
                    }
                }
                .padding(.horizontal, metrics.singleColumnHorizontalPadding)
            }
        }
        .allowsHitTesting(false)
    }

    private var itemCount: Int {
        // Other screens keep their existing preview counts. Home supplies its viewport.
        guard let viewportHeight else {
            return metrics.mode.isDoubleColumn ? 6 : (metrics.mode == .borderedSingleColumn ? 5 : 3)
        }
        let columns = metrics.mode.isDoubleColumn ? 2 : 1
        let rowHeight: CGFloat
        let fallbackCount: Int
        if metrics.mode.isDoubleColumn {
            // The grid skeleton uses a 16:9 cover and 62pt of text/spacing.
            rowHeight = (metrics.doubleColumnFixedCoverSize?.width ?? 0) * 9 / 16 + 62
            fallbackCount = 12
        } else if metrics.mode == .borderedSingleColumn {
            rowHeight = max((metrics.borderedSingleColumnCoverSize?.height ?? 88) + 20, 108) + 12
            fallbackCount = 10
        } else {
            rowHeight = (metrics.singleColumnFixedCoverSize?.height ?? 0) + 65
            fallbackCount = 5
        }
        guard viewportHeight > 0, metrics.singleColumnFixedCoverSize != nil else { return fallbackCount }
        // One extra row also covers the area revealed as the navigation bar collapses.
        let rows = Int(ceil((viewportHeight + metrics.feedSpacing) / (rowHeight + metrics.feedSpacing))) + 1
        return rows * columns
    }
}
