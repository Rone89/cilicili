import SwiftUI

struct HomeFeedContentSectionResolver: View {
    let metrics: HomeFeedLayoutMetrics
    let cells: [HomeVideoCellModel]
    let isLoadingMore: Bool
    let actions: HomeFeedContentActions

    var body: some View {
        Group {
            if cells.isEmpty {
                HomeFeedSkeletonSection(metrics: metrics)
            } else if metrics.mode != .doubleColumn {
                HomeFeedSingleColumnContent(
                    metrics: metrics,
                    cells: cells,
                    isLoadingMore: isLoadingMore,
                    actions: actions
                )
            } else {
                HomeFeedDoubleColumnContent(
                    metrics: metrics,
                    cells: cells,
                    isLoadingMore: isLoadingMore,
                    actions: actions
                )
            }
        }
    }
}
