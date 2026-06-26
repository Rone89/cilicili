import Foundation

struct HomeFeedCardLifecycleActions {
    let cell: HomeVideoCellModel
    let index: Int
    let loadMoreTriggerCellID: String?
    let actions: HomeFeedContentActions

    var shouldAttachLoadMoreTask: Bool {
        cell.id == loadMoreTriggerCellID
    }

    func handleAppear() {
        actions.onVisibleFrame(cell.video, index)
    }

    func handleDisappear() {
        actions.onInvisibleFrame(cell.video)
    }

    func loadMoreIfNeeded() async {
        await actions.onLoadMore(cell.video)
    }
}
