import SwiftUI

struct HomeFeedDoubleColumnContent: View {
    let metrics: HomeFeedLayoutMetrics
    let cells: [HomeVideoCellModel]
    let lastSeenMarkerIndex: Int?
    let isLoadingMore: Bool
    let actions: HomeFeedContentActions

    private var loadMoreTriggerCellID: String? {
        cells.last?.id
    }

    private var visibleLastSeenMarkerIndex: Int? {
        guard let lastSeenMarkerIndex,
              lastSeenMarkerIndex > 0,
              lastSeenMarkerIndex < cells.count
        else { return nil }
        return lastSeenMarkerIndex
    }

    var body: some View {
        LazyVGrid(columns: metrics.feedColumns, spacing: metrics.feedSpacing) {
            ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                if visibleLastSeenMarkerIndex == index {
                    HomeFeedLastSeenMarkerCard(
                        metrics: metrics,
                        action: actions.onRefreshFromLastSeenMarker
                    )
                }

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
