import SwiftUI

struct HomeFeedDoubleColumnContent: View {
    let metrics: HomeFeedLayoutMetrics
    let cells: [HomeVideoCellModel]
    let isLoadingMore: Bool
    let actions: HomeFeedContentActions

    private var loadMoreTriggerCellID: String? {
        cells.last?.id
    }

    var body: some View {
        LazyVGrid(columns: metrics.feedColumns, spacing: metrics.feedSpacing) {
            ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                HomeFeedDoubleColumnCard(
                    metrics: metrics,
                    cell: cell,
                    index: index,
                    loadMoreTriggerCellID: loadMoreTriggerCellID,
                    actions: actions
                )
            }

            if isLoadingMore {
                HomeFeedDoubleColumnLoadingMorePlaceholder(columnCount: metrics.feedColumns.count)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, metrics.feedHorizontalPadding)
    }
}
