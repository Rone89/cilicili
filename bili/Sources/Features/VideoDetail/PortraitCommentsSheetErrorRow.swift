import SwiftUI

struct PortraitCommentsSheetErrorRow: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        CommentErrorView(message: message, retry: retry)
            .padding(.vertical, 18)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
