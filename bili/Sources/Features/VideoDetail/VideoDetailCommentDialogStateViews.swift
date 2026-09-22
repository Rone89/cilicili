import SwiftUI

struct CommentDialogLoadingContent: View {
    @Environment(\.videoDetailStandardHorizontalInset) private var standardHorizontalInset

    var body: some View {
        let horizontalPadding = standardHorizontalInset

        CommentLoadingSkeletonList(count: 3)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 6)
    }
}
