import SwiftUI

struct PortraitCommentsSheetLoadingMoreRow: View {
    var body: some View {
        CommentLoadingSkeletonRow()
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}
