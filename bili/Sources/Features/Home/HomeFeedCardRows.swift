import SwiftUI

struct HomeFeedSingleColumnCard: View {
    let metrics: HomeFeedLayoutMetrics
    let cell: HomeVideoCellModel
    let index: Int
    let loadMoreTriggerCellID: String?
    let actions: HomeFeedContentActions

    var body: some View {
        HomeFeedVideoCardButton(
            metrics: metrics,
            video: cell.video,
            display: cell.display,
            actions: actions
        )
        .padding(.top, 9)
        .padding(.bottom, 14)
        .homeFeedCardLifecycle(
            cell: cell,
            index: index,
            loadMoreTriggerCellID: loadMoreTriggerCellID,
            actions: actions
        )
    }
}
