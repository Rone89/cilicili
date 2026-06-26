import SwiftUI

struct PortraitCommentsSheetLoadMoreRetryRow: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        CommentLoadMoreRetryButton(message: message) {
            retry()
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}
