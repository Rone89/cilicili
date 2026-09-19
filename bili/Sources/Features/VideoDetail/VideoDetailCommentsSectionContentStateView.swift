import SwiftUI

private struct VideoDetailCommentsEmptyStateMinimumHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var videoDetailCommentsEmptyStateMinimumHeight: CGFloat {
        get { self[VideoDetailCommentsEmptyStateMinimumHeightKey.self] }
        set { self[VideoDetailCommentsEmptyStateMinimumHeightKey.self] = newValue }
    }
}

struct CommentsSectionContentStateView: View {
    let state: CommentsSectionContentState
    @ObservedObject var store: VideoDetailCommentsRenderStore
    let style: CommentSectionStyle
    let maxVisibleComments: Int?
    let actions: VideoDetailCommentsSectionActions
    @Environment(\.videoDetailCommentsEmptyStateMinimumHeight) private var emptyStateMinimumHeight
    @Environment(\.commentSectionHorizontalPadding) private var configuredHorizontalPadding

    private var horizontalPadding: CGFloat {
        configuredHorizontalPadding ?? style.horizontalPadding
    }

    var body: some View {
        switch state {
        case .loading:
            CommentsSkeletonContent(horizontalPadding: horizontalPadding)
        case .failed(let message):
            CommentsSectionErrorContent(
                message: message,
                horizontalPadding: horizontalPadding,
                retryComments: actions.retryCommentsAction
            )
        case .empty:
            EmptyStateView(title: "暂无评论", systemImage: "bubble.left", message: "评论加载后会显示在这里。")
                .padding(.horizontal, horizontalPadding)
                .frame(minHeight: emptyStateMinimumHeight, alignment: .center)
        case .reloadPrompt:
            CommentsSectionErrorContent(
                message: "评论暂时没有返回内容",
                horizontalPadding: horizontalPadding,
                retryComments: actions.retryCommentsAction
            )
        case .spacer:
            Color.clear
                .frame(height: 1)
        case .loaded:
            CommentsSectionLoadedList(
                store: store,
                style: style,
                horizontalPadding: horizontalPadding,
                maxVisibleComments: maxVisibleComments,
                actions: actions
            )
        }
    }
}

private struct CommentsSectionErrorContent: View {
    let message: String
    let horizontalPadding: CGFloat
    let retryComments: () -> Void

    var body: some View {
        CommentErrorView(message: message, retry: retryComments)
        .padding(.horizontal, horizontalPadding)
    }
}
