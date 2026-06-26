import SwiftUI

struct HomeFeedContentSection: View {
    let metrics: HomeFeedLayoutMetrics
    let cells: [HomeVideoCellModel]
    let isLoadingMore: Bool
    let actions: HomeFeedContentActions

    var body: some View {
        HomeFeedContentSectionResolver(
            metrics: metrics,
            cells: cells,
            isLoadingMore: isLoadingMore,
            actions: actions
        )
    }
}
