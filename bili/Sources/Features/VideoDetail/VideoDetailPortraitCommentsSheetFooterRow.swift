import SwiftUI

struct PortraitCommentsSheetFooterRow: View {
    @ObservedObject var store: VideoDetailCommentsRenderStore
    let actions: PortraitCommentsSheetActions

    var body: some View {
        if store.loadMoreState.isLoading {
            PortraitCommentsSheetLoadingMoreRow()
        } else if case .failed(let message) = store.loadMoreState {
            PortraitCommentsSheetLoadMoreRetryRow(message: message) {
                actions.loadMoreCommentsAction()
            }
        } else if store.hasMoreComments {
            PortraitCommentsSheetLoadMoreTriggerRow(triggerID: store.commentItems.last?.id ?? -1) {
                await actions.loadMoreComments()
            }
        } else if !store.comments.isEmpty {
            PortraitCommentsSheetEndRow()
        }
    }
}
