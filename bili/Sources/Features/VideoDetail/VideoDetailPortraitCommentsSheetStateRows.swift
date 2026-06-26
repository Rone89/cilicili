import SwiftUI

struct PortraitCommentsSheetLoadingRows: View {
    var body: some View {
        CommentLoadingSkeletonList(count: 4)
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
            .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}
