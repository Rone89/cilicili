import SwiftUI

struct CommentsSectionHeader: View {
    @Environment(\.commentSectionHorizontalPadding) private var configuredHorizontalPadding

    @ObservedObject var store: VideoDetailCommentsRenderStore
    let style: CommentSectionStyle
    let selectCommentSort: (CommentSort) -> Void

    var body: some View {
        CommentsSectionHeaderContent(
            replyCountText: store.replyCountText,
            selectedSort: store.selectedSort,
            horizontalPadding: configuredHorizontalPadding ?? style.horizontalPadding,
            selectCommentSort: selectCommentSort
        )
    }
}

/// 值驱动的评论头部：UIKit 集合视图的 cell 里不依赖 `ObservableObject` 订阅，
/// 由外层在数据变化时重新配置 cell 并传入最新值。
struct CommentsSectionHeaderContent: View {
    let replyCountText: String?
    let selectedSort: CommentSort
    let horizontalPadding: CGFloat
    let selectCommentSort: (CommentSort) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("评论")
                .font(.headline)
                .accessibilityIdentifier("comments.header")

            if let replyCountText {
                Text(replyCountText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("评论排序", selection: Binding(
                get: { selectedSort },
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
