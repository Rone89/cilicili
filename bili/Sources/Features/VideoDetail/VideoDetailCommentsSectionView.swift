import SwiftUI

struct CommentsSectionView: View {
    @ObservedObject var store: VideoDetailCommentsRenderStore
    let style: CommentSectionStyle
    let maxVisibleComments: Int?
    let autoLoads: Bool
    let actions: VideoDetailCommentsSectionActions
    let lifecycleActions: CommentsSectionLifecycleActions

    init(
        store: VideoDetailCommentsRenderStore,
        style: CommentSectionStyle,
        maxVisibleComments: Int?,
        autoLoads: Bool = true,
        actions: VideoDetailCommentsSectionActions
    ) {
        self.store = store
        self.style = style
        self.maxVisibleComments = maxVisibleComments
        self.autoLoads = autoLoads
        self.actions = actions
        lifecycleActions = CommentsSectionLifecycleActionsBuilder(
            autoLoads: autoLoads,
            beginInitialCommentsLoad: actions.beginInitialCommentsLoad
        )
        .actions
    }

    private var commentsLoadTaskID: String {
        "\(store.detail?.aid ?? 0)-\(autoLoads)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CommentsSectionHeader(
                store: store,
                style: style,
                selectCommentSort: actions.selectCommentSortAction
            )

            CommentsSectionContent(
                store: store,
                style: style,
                maxVisibleComments: maxVisibleComments,
                shouldShowLoadingPlaceholder: shouldShowLoadingPlaceholder,
                actions: actions
            )
        }
        .padding(.vertical, 9)
        .background(style == .grouped ? VideoDetailTheme.surface : Color.clear)
        .commentsSectionLifecycle(taskID: commentsLoadTaskID, actions: lifecycleActions)
    }

    private var shouldShowLoadingPlaceholder: Bool {
        store.state.isLoading || (autoLoads && store.state == .idle)
    }
}
