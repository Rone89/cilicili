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
                .frame(maxWidth: metrics.maxContentWidth ?? .infinity)
                .padding(.horizontal, metrics.feedHorizontalPadding)
                .frame(maxWidth: .infinity, alignment: .center)
            } else if metrics.mode == .borderedSingleColumn {
                Group {
                    if metrics.singleColumnColumns.count > 1 {
                        LazyVGrid(columns: metrics.singleColumnColumns, spacing: metrics.singleColumnGridSpacing) {
                            ForEach(0..<itemCount, id: \.self) { _ in
                                VideoFeedSkeletonCard(
                                    style: .borderedSingleColumn(
                                        coverSize: metrics.borderedSingleColumnCoverSize
                                            ?? CGSize(width: 140, height: 88)
                                    )
                                )
                            }
                        }
                    } else {
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
                    }
                }
                .frame(maxWidth: metrics.maxContentWidth ?? .infinity)
                .padding(.horizontal, metrics.singleColumnHorizontalPadding)
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Group {
                    if metrics.singleColumnColumns.count > 1 {
                        LazyVGrid(columns: metrics.singleColumnColumns, spacing: metrics.singleColumnGridSpacing) {
                            ForEach(0..<itemCount, id: \.self) { _ in
                                VideoFeedSkeletonCard(style: .singleColumn)
                            }
                        }
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(0..<itemCount, id: \.self) { _ in
                                VideoFeedSkeletonCard(style: .singleColumn)
                            }
                        }
                    }
                }
                .frame(maxWidth: metrics.maxContentWidth ?? .infinity)
                .padding(.horizontal, metrics.singleColumnHorizontalPadding)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .allowsHitTesting(false)
    }

    private var itemCount: Int {
        // Other screens keep their existing preview counts. Home supplies its viewport.
        let columns = metrics.mode.isDoubleColumn
            ? max(metrics.doubleColumns.count, 1)
            : max(metrics.singleColumnColumns.count, 1)
        guard let viewportHeight else {
            return metrics.mode.isDoubleColumn ? max(6, columns * 3) : (metrics.mode == .borderedSingleColumn ? 5 : 3)
        }
        let rowHeight: CGFloat
        let fallbackCount: Int
        if metrics.mode.isDoubleColumn {
            // The grid skeleton uses a 16:9 cover and 62pt of text/spacing.
            rowHeight = (metrics.doubleColumnFixedCoverSize?.width ?? 0) * 9 / 16 + 62
            fallbackCount = columns * 6
        } else if metrics.mode == .borderedSingleColumn {
            rowHeight = max((metrics.borderedSingleColumnCoverSize?.height ?? 88) + 20, 108) + 12
            fallbackCount = columns * 5
        } else {
            rowHeight = (metrics.singleColumnFixedCoverSize?.height ?? 0) + 65
            fallbackCount = columns * 3
        }
        guard viewportHeight > 0, metrics.singleColumnFixedCoverSize != nil else { return fallbackCount }
        // One extra row also covers the area revealed as the navigation bar collapses.
        let rows = Int(ceil((viewportHeight + metrics.feedSpacing) / (rowHeight + metrics.feedSpacing))) + 1
        return rows * columns
    }
}
