import SwiftUI

private struct HomeFeedCardLifecycleModifier: ViewModifier {
    let cell: HomeVideoCellModel
    let index: Int
    let lifecycleActions: HomeFeedCardLifecycleActions

    func body(content: Content) -> some View {
        content
            .homeVisibleVideoFrame(for: cell.video, index: index)
            .onAppear(perform: lifecycleActions.handleAppear)
            .onDisappear(perform: lifecycleActions.handleDisappear)
            .homeLoadMoreTask(if: lifecycleActions.shouldAttachLoadMoreTask, id: cell.id) {
                await lifecycleActions.loadMoreIfNeeded()
            }
    }
}

extension View {
    func homeFeedCardLifecycle(
        cell: HomeVideoCellModel,
        index: Int,
        loadMoreTriggerCellID: String?,
        actions: HomeFeedContentActions
    ) -> some View {
        modifier(
            HomeFeedCardLifecycleModifier(
                cell: cell,
                index: index,
                lifecycleActions: HomeFeedCardLifecycleActions(
                    cell: cell,
                    index: index,
                    loadMoreTriggerCellID: loadMoreTriggerCellID,
                    actions: actions
                )
            )
        )
    }
}
