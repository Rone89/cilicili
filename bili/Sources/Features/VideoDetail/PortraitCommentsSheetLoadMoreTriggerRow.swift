import SwiftUI

struct PortraitCommentsSheetLoadMoreTriggerRow: View {
    let triggerID: Int
    let loadMoreComments: () async -> Void

    var body: some View {
        Color.clear
            .frame(height: 20)
            .commentLoadMoreTrigger(if: true, id: triggerID) {
                await loadMoreComments()
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
