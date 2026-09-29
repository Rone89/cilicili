import SwiftUI

struct HomeFeedSingleColumnContent: View {
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
        LazyVStack(spacing: 0) {
            ForEach(cells) { cell in
                if visibleLastSeenMarkerIndex == cell.index {
                    HomeFeedLastSeenMarkerCard(
                        metrics: metrics,
                        action: actions.onRefreshFromLastSeenMarker
                    )
                    .padding(.top, metrics.mode == .borderedSingleColumn ? 6 : 9)
                    .padding(.bottom, metrics.mode == .borderedSingleColumn ? 6 : 14)
                }

                HomeFeedSingleColumnCard(
                    metrics: metrics,
                    cell: cell,
                    isFirstCell: cell.id == cells.first?.id,
                    loadMoreTriggerCellID: loadMoreTriggerCellID,
                    actions: actions
                )
            }

            if isLoadingMore {
                InlineLoadingStateView(title: "正在加载更多")
                    .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, metrics.singleColumnHorizontalPadding)
        .padding(.top, 0)
        .padding(.bottom, 18)
    }
}
