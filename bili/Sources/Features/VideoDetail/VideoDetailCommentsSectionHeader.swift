import SwiftUI

struct CommentsSectionHeader: View {
    @Environment(\.commentSectionHorizontalPadding) private var configuredHorizontalPadding

    @ObservedObject var store: VideoDetailCommentsRenderStore
    let style: CommentSectionStyle
    let selectCommentSort: (CommentSort) -> Void

    private var horizontalPadding: CGFloat {
        configuredHorizontalPadding ?? style.horizontalPadding
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("评论")
                .font(.headline)

            if let count = store.replyCountText {
                Text(count)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("评论排序", selection: Binding(
                get: { store.selectedSort },
                set: { selectCommentSort($0) }
            )) {
                ForEach(CommentSort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 124)
            .controlSize(.small)
            .accessibilityLabel("评论排序")
        }
        .padding(.horizontal, horizontalPadding)
    }
}
