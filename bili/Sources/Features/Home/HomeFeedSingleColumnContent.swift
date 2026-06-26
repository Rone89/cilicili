import SwiftUI

struct HomeFeedSingleColumnContent: View {
    let metrics: HomeFeedLayoutMetrics
    let cells: [HomeVideoCellModel]
    let isLoadingMore: Bool
    let actions: HomeFeedContentActions

    private var loadMoreTriggerCellID: String? {
        cells.last?.id
    }

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                HomeFeedSingleColumnCard(
                    metrics: metrics,
                    cell: cell,
                    index: index,
                    loadMoreTriggerCellID: loadMoreTriggerCellID,
                    actions: actions
                )
            }

            if isLoadingMore {
                VideoFeedSkeletonCard(style: .singleColumn)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, metrics.singleColumnHorizontalPadding)
        .padding(.top, 0)
        .padding(.bottom, 18)
    }
}
