import SwiftUI

struct CommentDialogErrorContent: View {
    @Environment(\.videoDetailStandardHorizontalInset) private var standardHorizontalInset
    let message: String
    let retry: () -> Void

    var body: some View {
        let horizontalPadding = standardHorizontalInset

        CommentErrorView(message: message, retry: retry)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 16)
    }
}
