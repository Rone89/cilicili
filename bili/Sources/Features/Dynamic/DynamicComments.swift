import SwiftUI
import Combine

struct DynamicCommentsSheet: View {
    let item: DynamicFeedItem
    @EnvironmentObject private var dependencies: AppDependencies
    @StateObject private var viewModel: DynamicCommentsViewModel
    @StateObject private var runtimeSettings = DynamicCommentsRuntimeSettingsStore()
    @State private var replySheetComment: Comment?

    init(item: DynamicFeedItem, api: BiliAPIClient) {
        self.item = item
        _viewModel = StateObject(wrappedValue: DynamicCommentsViewModel(item: item, api: api))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    commentsHeader
                        .padding(.horizontal, 14)
                        .padding(.top, 4)
                        .padding(.bottom, 6)

                    commentsContent
                }
            }
            .hiddenInlineNavigationTitle()
            .nativeTopScrollEdgeEffect()
            .task {
                runtimeSettings.bind(dependencies.libraryStore)
                viewModel.setBlocksGoodsComments(runtimeSettings.blocksGoodsComments)
                await viewModel.loadInitial()
            }
        }
        .onChange(of: runtimeSettings.blocksGoodsComments) { _, isEnabled in
            viewModel.setBlocksGoodsComments(isEnabled)
        }
        .presentationDetents([.fraction(0.7)])
        .presentationDragIndicator(.visible)
        .sheet(item: $replySheetComment) { comment in
            DynamicCommentRepliesSheet(rootComment: comment, replyStore: viewModel.replyStore)
        }
    }

    private var commentsHeader: some View {
        HStack(spacing: 8) {
            Text("全部评论")
                .font(.headline.weight(.semibold))

            if let count = item.replyCount, count > 0 {
                Text(BiliFormatters.compactCount(count))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker(
                "评论排序",
                selection: Binding(
                    get: { viewModel.selectedSort },
                    set: { sort in
                        Task { await viewModel.selectSort(sort) }
                    }
                )
            ) {
                ForEach(CommentSort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 124)
            .controlSize(.small)
            .accessibilityLabel("评论排序")
        }
    }

    @ViewBuilder
    private var commentsContent: some View {
        if !viewModel.canLoadComments {
            EmptyStateView(title: "暂不支持评论", systemImage: "bubble.left", message: "这条动态没有返回评论入口。")
                .padding(16)
        } else if viewModel.comments.isEmpty && viewModel.state.isLoading {
            CommentLoadingSkeletonList(count: 4)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
        } else if viewModel.comments.isEmpty, case .failed(let message) = viewModel.state {
            DynamicCommentErrorView(message: message) {
                Task { await viewModel.reload() }
            }
            .padding(14)
        } else if viewModel.comments.isEmpty {
            DynamicCommentPlainEmptyStateView(
                title: "暂无评论",
                systemImage: "bubble.left",
                message: "这里还没有可展示的评论。"
            )
                .padding(14)
        } else {
            let commentItems = viewModel.commentItems
            let lastCommentID = commentItems.last?.id
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(commentItems) { item in
                    DynamicCommentRow(item: item) {
                        replySheetComment = item.comment
                    }
                    .padding(.horizontal, 14)
                    .dynamicLoadMoreTask(if: item.id == lastCommentID, id: item.id) {
                        await viewModel.loadMoreIfNeeded(current: item.comment)
                    }

                    Divider()
                        .padding(.leading, 62)
                }

                commentsFooter
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
    }

    @ViewBuilder
    private var commentsFooter: some View {
        if viewModel.state.isLoading {
            CommentLoadingSkeletonRow()
                .padding(.vertical, 10)
        } else if case .failed(let message) = viewModel.state {
            DynamicCommentErrorView(message: message) {
                Task { await viewModel.loadMore() }
            }
        } else if viewModel.hasMoreComments {
            Button {
                Task { await viewModel.loadMore() }
            } label: {
                Label("加载更多评论", systemImage: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .dynamicCommentGlassButtonStyle()
            .controlSize(.small)
            .tint(.pink)
        } else {
            Text("没有更多评论了")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
    }
}

private struct DynamicCommentPlainEmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    func dynamicCommentGlassButtonStyle(prominent: Bool = false) -> some View {
        biliGlassButtonStyle(prominent: prominent)
    }

    @ViewBuilder
    func dynamicCommentGlassCard() -> some View {
        clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .biliGlassEffect(
                tint: Color(.secondarySystemBackground).opacity(0.18),
                interactive: false,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
    }
}

@MainActor
private final class DynamicCommentsViewModel: ObservableObject {
    private(set) var comments: [Comment] = [] {
        didSet {
            syncCommentItems()
        }
    }
    @Published private(set) var commentItems: [DynamicCommentRowItem] = []
    @Published var state: LoadingState = .idle
    @Published var selectedSort: CommentSort = .hot
    let replyStore: DynamicCommentReplyStore

    private let item: DynamicFeedItem
    private let api: BiliAPIClient
    private var blocksGoodsComments = true
    private var cursor = ""
    private var commentsEnd = false
    private var commentItemsSignature = DynamicCommentListSignature([])

    var canLoadComments: Bool {
        commentOID != nil && commentType != nil
    }

    var hasMoreComments: Bool {
        !commentsEnd
    }

    init(item: DynamicFeedItem, api: BiliAPIClient) {
        self.item = item
        self.api = api
        self.replyStore = DynamicCommentReplyStore(item: item, api: api, blocksGoodsComments: blocksGoodsComments)
    }

    func setBlocksGoodsComments(_ isEnabled: Bool) {
        guard blocksGoodsComments != isEnabled else { return }
        blocksGoodsComments = isEnabled
        replyStore.setBlocksGoodsComments(isEnabled)
        refilterLoadedComments()
    }

    func loadInitial() async {
        guard comments.isEmpty, state != .loading else { return }
        await reload()
    }

    func reload() async {
        cursor = ""
        commentsEnd = false
        comments = []
        await loadPage()
    }

    func selectSort(_ sort: CommentSort) async {
        guard selectedSort != sort else { return }
        selectedSort = sort
        await reload()
    }

    func loadMoreIfNeeded(current comment: Comment?) async {
        guard let comment, comments.last?.id == comment.id else { return }
        await loadMore()
    }

    func loadMore() async {
        guard !state.isLoading, !commentsEnd else { return }
        await loadPage()
    }

    private var commentOID: String? {
        item.commentOID
    }

    private var commentType: Int? {
        item.commentType
    }

    private func loadPage() async {
        guard let oid = commentOID, let type = commentType else {
            state = .failed("这条动态没有返回评论入口")
            commentsEnd = true
            return
        }

        state = .loading
        do {
            let page = try await api.fetchComments(oid: oid, type: type, cursor: cursor, sort: selectedSort)
            let pageComments = comments.isEmpty
                ? (page.topReplies ?? []) + (page.replies ?? [])
                : (page.replies ?? [])
            appendUniqueComments(filteredComments(pageComments))
            cursor = page.cursor?.next ?? ""
            commentsEnd = page.cursor?.isEnd ?? true
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func appendUniqueComments(_ more: [Comment]) {
        let existing = Set(comments.map(\.id))
        comments.append(contentsOf: more.filter { !existing.contains($0.id) })
    }

    private func syncCommentItems() {
        let nextSignature = DynamicCommentListSignature(comments)
        guard nextSignature != commentItemsSignature else { return }
        commentItemsSignature = nextSignature
        commentItems = comments.map(DynamicCommentRowItem.init)
    }

    private func filteredComments(_ values: [Comment]) -> [Comment] {
        guard blocksGoodsComments else { return values }
        return values.filter { !$0.containsGoodsPromotion }
    }

    func refilterLoadedComments() {
        guard !comments.isEmpty else { return }
        if blocksGoodsComments {
            comments = filteredComments(comments)
        } else {
            Task { await reload() }
        }
    }
}

private struct DynamicCommentRow: View {
    let item: DynamicCommentRowItem
    let showReplies: () -> Void

    private var comment: Comment {
        item.comment
    }

    private var display: DynamicCommentRowDisplayModel {
        item.display
    }

    init(item: DynamicCommentRowItem, showReplies: @escaping () -> Void) {
        self.item = item
        self.showReplies = showReplies
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            DynamicCommentAvatar(urlString: display.avatarURLString, size: 38)

            VStack(alignment: .leading, spacing: 6) {
                header

                DynamicCommentText(
                    content: comment.content,
                    font: .subheadline,
                    textColor: .primary,
                    emoteSize: 21,
                    lineSpacing: 1
                )

                DynamicCommentImageGrid(images: display.pictures)

                if !display.replyPreviews.isEmpty {
                    Button(action: showReplies) {
                        DynamicCommentReplyPreviewContainer {
                            ForEach(display.replyPreviews) { reply in
                                DynamicReplyPreviewRow(reply: reply)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                if display.visibleReplyCount > 0 {
                    DynamicCommentInlineActionPill(
                        title: "\(display.visibleReplyCount) 条回复",
                        systemImage: "bubble.left.and.bubble.right",
                        action: showReplies
                    )
                    .padding(.top, 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
        .padding(.vertical, 10)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(display.authorName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if !display.timeText.isEmpty {
                Text(display.timeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            DynamicCommentMetricBadge(
                text: display.likeText,
                systemImage: display.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
                isHighlighted: display.isLiked
            )
        }
    }
}

private struct DynamicCommentRowItem: Identifiable, Equatable {
    let id: Int
    let comment: Comment
    let display: DynamicCommentRowDisplayModel

    init(comment: Comment) {
        id = comment.id
        self.comment = comment
        display = DynamicCommentRowDisplayModel(comment: comment)
    }
}

private struct DynamicCommentRowDisplayModel: Equatable {
    let authorName: String
    let avatarURLString: String?
    let timeText: String
    let likeText: String
    let isLiked: Bool
    let replyPreviews: [Comment]
    let visibleReplyCount: Int
    let pictures: [DynamicImageItem]

    init(comment: Comment) {
        authorName = Self.displayName(comment.member?.uname)
        avatarURLString = comment.member?.avatar
        timeText = BiliFormatters.relativeTime(comment.ctime)
        likeText = BiliFormatters.compactCount(comment.like)
        isLiked = comment.likeState == 1
        replyPreviews = Array((comment.replies ?? []).prefix(2))
        visibleReplyCount = comment.replyCount ?? comment.replies?.count ?? 0
        pictures = comment.content?.pictures ?? []
    }

    private static func displayName(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Unknown" : trimmed
    }
}

nonisolated private struct DynamicCommentListSignature: Equatable {
    let items: [DynamicCommentSignature]

    init(_ comments: [Comment]) {
        items = comments.map(DynamicCommentSignature.init)
    }
}

nonisolated private struct DynamicCommentSignature: Equatable {
    let id: Int
    let parentID: Int?
    let dialogID: Int?
    let authorName: String?
    let avatar: String?
    let message: String?
    let like: Int?
    let ctime: Int?
    let replyCount: Int?
    let likeState: Int?
    let pictureURLs: [String]
    let replyPreviews: [DynamicCommentReplyPreviewSignature]

    init(_ comment: Comment) {
        id = comment.id
        parentID = comment.parentID
        dialogID = comment.dialogID
        authorName = comment.member?.uname
        avatar = comment.member?.avatar
        message = comment.content?.message
        like = comment.like
        ctime = comment.ctime
        replyCount = comment.replyCount
        likeState = comment.likeState
        pictureURLs = (comment.content?.pictures ?? []).map(\.url)
        replyPreviews = (comment.replies ?? [])
            .prefix(2)
            .map(DynamicCommentReplyPreviewSignature.init)
    }
}

nonisolated private struct DynamicCommentReplyPreviewSignature: Equatable {
    let id: Int
    let authorName: String?
    let message: String?

    init(_ comment: Comment) {
        id = comment.id
        authorName = comment.member?.uname
        message = comment.content?.message
    }
}

private struct DynamicReplyPreviewRow: View {
    let reply: Comment

    var body: some View {
        DynamicCommentText(
            content: reply.content,
            font: .caption,
            textColor: .primary,
            emoteSize: 18,
            leadingName: reply.member?.uname ?? "Unknown",
            leadingNameColor: .secondary
        )
        .lineLimit(2)
    }
}

private struct DynamicCommentReplyPreviewContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.pink.opacity(0.42))
                .frame(width: 3)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 5) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct DynamicCommentMetricBadge: View {
    let text: String
    let systemImage: String
    let isHighlighted: Bool

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .foregroundStyle(isHighlighted ? .pink : .secondary)
            .frame(height: 24)
    }
}

private struct DynamicCommentInlineActionPill: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, 9)
                .frame(height: 26)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.pink)
    }
}

private struct DynamicCommentRepliesSheet: View {
    let rootComment: Comment
    let replyStore: DynamicCommentReplyStore
    @State private var dialogReply: Comment?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DynamicCommentReplyRootView(comment: rootComment)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                    Divider()

                    DynamicCommentRepliesContent(rootComment: rootComment, replyStore: replyStore) { reply in
                        dialogReply = reply
                    }
                }
            }
            .hiddenInlineNavigationTitle()
            .nativeTopScrollEdgeEffect()
            .task {
                await replyStore.loadReplies(for: rootComment)
            }
        }
        .presentationDetents([.fraction(0.7)])
        .presentationDragIndicator(.visible)
        .sheet(item: $dialogReply) { reply in
            DynamicCommentDialogSheet(rootComment: rootComment, focusReply: reply, replyStore: replyStore)
        }
    }
}

private struct DynamicCommentRepliesContent: View {
    let rootComment: Comment
    @ObservedObject var replyStore: DynamicCommentReplyStore
    let showDialog: (Comment) -> Void

    @ViewBuilder
    var body: some View {
        let snapshot = replyStore.repliesSnapshot(for: rootComment)

        if snapshot.replies.isEmpty && snapshot.state.isLoading {
            CommentLoadingSkeletonList(count: 3)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        } else if snapshot.replies.isEmpty, case .failed(let message) = snapshot.state {
            DynamicCommentErrorView(message: message) {
                Task { await replyStore.reloadReplies(for: rootComment) }
            }
            .padding(16)
        } else if snapshot.replies.isEmpty {
            EmptyStateView(title: "暂无回复", systemImage: "bubble.left.and.bubble.right", message: "这条评论还没有可展示的回复。")
                .padding(16)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(snapshot.replyItems) { replyItem in
                    DynamicCommentReplyDetailRow(
                        item: replyItem,
                        showDialog: replyItem.canShowDialog ? {
                            showDialog(replyItem.reply)
                        } : nil
                    )
                    .padding(.horizontal, 16)

                    Divider()
                        .padding(.leading, 66)
                }

                repliesFooter(snapshot: snapshot)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
    }

    @ViewBuilder
    private func repliesFooter(snapshot: DynamicCommentRepliesSnapshot) -> some View {
        if snapshot.hasLoadedReplies, snapshot.state.isLoading {
            CommentLoadingSkeletonRow()
        } else if case .failed(let message) = snapshot.state {
            DynamicCommentErrorView(message: message) {
                Task { await replyStore.loadMoreReplies(for: rootComment) }
            }
        } else if snapshot.hasMoreReplies {
            Button {
                Task { await replyStore.loadMoreReplies(for: rootComment) }
            } label: {
                Label("查看更多回复", systemImage: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.pink)
        }
    }
}

@MainActor
private final class DynamicCommentReplyStore: ObservableObject {
    @Published private var snapshot = DynamicCommentReplyStoreSnapshot()
    private var replyItemCache: [Int: DynamicCommentReplyItemCacheEntry] = [:]
    private var dialogItemCache: [String: DynamicCommentDialogItemCacheEntry] = [:]

    private let item: DynamicFeedItem
    private let api: BiliAPIClient
    private var blocksGoodsComments: Bool

    init(item: DynamicFeedItem, api: BiliAPIClient, blocksGoodsComments: Bool) {
        self.item = item
        self.api = api
        self.blocksGoodsComments = blocksGoodsComments
    }

    private func updateSnapshot(_ transform: (inout DynamicCommentReplyStoreSnapshot) -> Void) {
        var next = snapshot
        transform(&next)
        setSnapshot(next)
    }

    private func setSnapshot(_ next: DynamicCommentReplyStoreSnapshot) {
        guard next.changeSignature != snapshot.changeSignature else { return }
        snapshot = next
    }

    func setBlocksGoodsComments(_ isEnabled: Bool) {
        guard blocksGoodsComments != isEnabled else { return }
        blocksGoodsComments = isEnabled
        updateSnapshot { snapshot in
            if isEnabled {
                snapshot.replyThreads = snapshot.replyThreads.mapValues(filteredComments)
                snapshot.dialogThreads = snapshot.dialogThreads.mapValues(filteredComments)
            } else {
                snapshot.replyThreads = [:]
                snapshot.dialogThreads = [:]
                snapshot.replyPages = [:]
                snapshot.replyHasMore = [:]
            }
        }
        replyItemCache.removeAll()
        dialogItemCache.removeAll()
    }

    func replies(for comment: Comment) -> [Comment] {
        snapshot.replyThreads[comment.id] ?? comment.replies ?? []
    }

    func repliesSnapshot(for comment: Comment) -> DynamicCommentRepliesSnapshot {
        let replies = replies(for: comment)
        return DynamicCommentRepliesSnapshot(
            state: snapshot.replyStates[comment.id] ?? .idle,
            replies: replies,
            replyItems: replyItems(for: comment, replies: replies),
            hasMoreReplies: hasMoreReplies(for: comment, loadedCount: replies.count)
        )
    }

    func replyItems(for comment: Comment) -> [DynamicCommentReplyItem] {
        replyItems(for: comment, replies: replies(for: comment))
    }

    private func replyItems(for comment: Comment, replies: [Comment]) -> [DynamicCommentReplyItem] {
        let signature = DynamicCommentReplyItemSignature(rootComment: comment, replies: replies)
        if let cached = replyItemCache[comment.id], cached.signature == signature {
            return cached.items
        }

        let items = replies.map { DynamicCommentReplyItem(reply: $0, rootComment: comment) }
        replyItemCache[comment.id] = DynamicCommentReplyItemCacheEntry(signature: signature, items: items)
        return items
    }

    func hasMoreReplies(for comment: Comment) -> Bool {
        if let hasMore = snapshot.replyHasMore[comment.id] {
            return hasMore
        }
        let loadedCount = replies(for: comment).count
        return hasMoreReplies(for: comment, loadedCount: loadedCount)
    }

    private func hasMoreReplies(for comment: Comment, loadedCount: Int) -> Bool {
        if let hasMore = snapshot.replyHasMore[comment.id] {
            return hasMore
        }
        let totalCount = comment.replyCount ?? comment.replies?.count ?? loadedCount
        return loadedCount < totalCount
    }

    func replyState(for comment: Comment) -> LoadingState {
        snapshot.replyStates[comment.id] ?? .idle
    }

    func loadReplies(for comment: Comment) async {
        guard snapshot.replyThreads[comment.id] == nil else { return }
        updateSnapshot {
            $0.replyPages[comment.id] = 0
            $0.replyHasMore[comment.id] = true
        }
        await loadReplyPage(for: comment, reset: true)
    }

    func reloadReplies(for comment: Comment) async {
        updateSnapshot {
            $0.replyThreads[comment.id] = nil
            $0.replyPages[comment.id] = 0
            $0.replyHasMore[comment.id] = true
        }
        replyItemCache[comment.id] = nil
        await loadReplyPage(for: comment, reset: true)
    }

    func loadMoreReplies(for comment: Comment) async {
        guard snapshot.replyHasMore[comment.id] != false,
              !(snapshot.replyStates[comment.id]?.isLoading ?? false)
        else { return }
        await loadReplyPage(for: comment, reset: false)
    }

    func dialogItems(for root: Comment, reply: Comment) -> [DynamicCommentDialogItem] {
        let key = dialogKey(root: root, reply: reply)
        let replies = dialogReplies(for: root, reply: reply)
        return dialogItems(for: root, key: key, replies: replies)
    }

    private func dialogItems(for root: Comment, key: String, replies: [Comment]) -> [DynamicCommentDialogItem] {
        let signature = DynamicCommentReplyItemSignature(rootComment: root, replies: replies)
        if let cached = dialogItemCache[key], cached.signature == signature {
            return cached.items
        }

        let items = replies.map(DynamicCommentDialogItem.init)
        dialogItemCache[key] = DynamicCommentDialogItemCacheEntry(signature: signature, items: items)
        return items
    }

    func dialogState(for root: Comment, reply: Comment) -> LoadingState {
        snapshot.dialogStates[dialogKey(root: root, reply: reply)] ?? .idle
    }

    func dialogSnapshot(for root: Comment, reply: Comment) -> DynamicCommentDialogSnapshot {
        let key = dialogKey(root: root, reply: reply)
        let replies = dialogReplies(for: root, reply: reply)
        return DynamicCommentDialogSnapshot(
            state: snapshot.dialogStates[key] ?? .idle,
            items: dialogItems(for: root, key: key, replies: replies)
        )
    }

    func loadDialog(for root: Comment, reply: Comment) async {
        let key = dialogKey(root: root, reply: reply)
        guard snapshot.dialogThreads[key] == nil else { return }
        await loadDialogPage(for: root, reply: reply)
    }

    func reloadDialog(for root: Comment, reply: Comment) async {
        let key = dialogKey(root: root, reply: reply)
        updateSnapshot { $0.dialogThreads[key] = nil }
        dialogItemCache[key] = nil
        await loadDialogPage(for: root, reply: reply)
    }

    private var commentOID: String? {
        item.commentOID
    }

    private var commentType: Int? {
        item.commentType
    }

    private func loadReplyPage(for comment: Comment, reset: Bool) async {
        guard let oid = commentOID, let type = commentType else {
            updateSnapshot { $0.replyStates[comment.id] = .failed("这条动态没有返回评论入口") }
            return
        }

        updateSnapshot { $0.replyStates[comment.id] = .loading }
        do {
            let nextPage = reset ? 1 : (snapshot.replyPages[comment.id] ?? 1) + 1
            let page = try await api.fetchCommentReplies(oid: oid, type: type, root: comment.rpid, page: nextPage)
            let fetchedReplies = filteredComments(page.replies ?? [])
            let existingReplies = reset
                ? filteredComments(comment.replies ?? [])
                : filteredComments(snapshot.replyThreads[comment.id] ?? comment.replies ?? [])
            let replies = uniqueComments(existingReplies + fetchedReplies)
            let totalCount = comment.replyCount ?? Int.max
            updateSnapshot {
                $0.replyThreads[comment.id] = replies
                $0.replyPages[comment.id] = nextPage
                $0.replyHasMore[comment.id] = !fetchedReplies.isEmpty && replies.count < totalCount
                $0.replyStates[comment.id] = .loaded
            }
        } catch {
            updateSnapshot {
                if reset {
                    $0.replyThreads[comment.id] = filteredComments(comment.replies ?? [])
                }
                $0.replyStates[comment.id] = .failed(error.localizedDescription)
            }
        }
    }

    private func loadDialogPage(for root: Comment, reply: Comment) async {
        let key = dialogKey(root: root, reply: reply)
        guard let oid = commentOID, let type = commentType else {
            updateSnapshot { $0.dialogStates[key] = .failed("这条动态没有返回评论入口") }
            return
        }

        let fallbackReplies = filteredComments(localDialogReplies(root: root, reply: reply))

        guard let dialogID = reply.dialogID, dialogID > 0 else {
            updateSnapshot {
                $0.dialogThreads[key] = fallbackReplies
                $0.dialogStates[key] = .loaded
            }
            return
        }

        updateSnapshot { $0.dialogStates[key] = .loading }
        do {
            let page = try await api.fetchCommentDialog(oid: oid, type: type, root: root.rpid, dialog: dialogID)
            let replies = uniqueComments(filteredComments(page.replies ?? []) + fallbackReplies)
            updateSnapshot {
                $0.dialogThreads[key] = replies.isEmpty ? fallbackReplies : replies
                $0.dialogStates[key] = .loaded
            }
        } catch {
            updateSnapshot {
                $0.dialogThreads[key] = fallbackReplies
                $0.dialogStates[key] = .failed(error.localizedDescription)
            }
        }
    }

    private func dialogReplies(for root: Comment, reply: Comment) -> [Comment] {
        let key = dialogKey(root: root, reply: reply)
        return snapshot.dialogThreads[key] ?? localDialogReplies(root: root, reply: reply)
    }

    private func dialogKey(root: Comment, reply: Comment) -> String {
        let dialogID = reply.dialogID ?? 0
        if dialogID > 0 {
            return "\(root.id)-\(dialogID)"
        }
        let parentID = reply.parentID ?? 0
        if parentID > 0 {
            return "\(root.id)-p-\(parentID)-\(reply.id)"
        }
        return "\(root.id)-r-\(reply.id)"
    }

    private func localDialogReplies(root: Comment, reply: Comment) -> [Comment] {
        let siblings = replies(for: root)
        let dialogID = reply.dialogID ?? 0
        if dialogID > 0 {
            let matches = siblings.filter {
                $0.dialogID == dialogID || $0.id == dialogID || $0.parentID == dialogID
            }
            let merged = uniqueComments([reply] + matches)
            if merged.count > 1 {
                return merged
            }
        }

        let parentID = reply.parentID ?? 0
        if parentID > 0 {
            let matches = siblings.filter {
                $0.parentID == parentID || $0.id == parentID || $0.id == reply.id
            }
            let merged = uniqueComments([reply] + matches)
            if merged.count > 1 {
                return merged
            }
        }

        return [reply]
    }

    private func filteredComments(_ values: [Comment]) -> [Comment] {
        guard blocksGoodsComments else { return values }
        return values.filter { !$0.containsGoodsPromotion }
    }

    private func uniqueComments(_ comments: [Comment]) -> [Comment] {
        var seen = Set<Int>()
        return comments.filter { seen.insert($0.id).inserted }
    }
}

private struct DynamicCommentRepliesSnapshot: Equatable {
    let state: LoadingState
    let replies: [Comment]
    let replyItems: [DynamicCommentReplyItem]
    let hasMoreReplies: Bool

    var hasLoadedReplies: Bool {
        !replies.isEmpty
    }
}

private struct DynamicCommentDialogSnapshot: Equatable {
    let state: LoadingState
    let items: [DynamicCommentDialogItem]
}

private struct DynamicCommentReplyStoreSnapshot {
    var replyThreads: [Int: [Comment]] = [:]
    var replyStates: [Int: LoadingState] = [:]
    var replyPages: [Int: Int] = [:]
    var replyHasMore: [Int: Bool] = [:]
    var dialogThreads: [String: [Comment]] = [:]
    var dialogStates: [String: LoadingState] = [:]

    var changeSignature: DynamicCommentReplyStoreChangeSignature {
        DynamicCommentReplyStoreChangeSignature(
            replyThreadSignatures: replyThreads.mapValues(DynamicCommentListSignature.init),
            replyStates: replyStates,
            replyPages: replyPages,
            replyHasMore: replyHasMore,
            dialogThreadSignatures: dialogThreads.mapValues(DynamicCommentListSignature.init),
            dialogStates: dialogStates
        )
    }
}

nonisolated private struct DynamicCommentReplyStoreChangeSignature: Equatable {
    let replyThreadSignatures: [Int: DynamicCommentListSignature]
    let replyStates: [Int: LoadingState]
    let replyPages: [Int: Int]
    let replyHasMore: [Int: Bool]
    let dialogThreadSignatures: [String: DynamicCommentListSignature]
    let dialogStates: [String: LoadingState]
}

private struct DynamicCommentReplyItem: Identifiable, Equatable {
    let id: Int
    let reply: Comment
    let display: DynamicCommentRowDisplayModel
    let canShowDialog: Bool

    init(reply: Comment, rootComment: Comment) {
        id = reply.id
        self.reply = reply
        display = DynamicCommentRowDisplayModel(comment: reply)
        canShowDialog = Self.canShowDialog(for: reply, rootComment: rootComment)
    }

    private static func canShowDialog(for reply: Comment, rootComment: Comment) -> Bool {
        guard reply.id != rootComment.id else { return false }
        if let dialogID = reply.dialogID, dialogID > 0 {
            return true
        }
        if let parentID = reply.parentID, parentID > 0, parentID != rootComment.rpid {
            return true
        }
        return DynamicCommentTextBuilder.hasReplyTarget(in: reply.content?.message)
    }
}

private struct DynamicCommentDialogItem: Identifiable, Equatable {
    let id: Int
    let reply: Comment
    let display: DynamicCommentRowDisplayModel

    init(reply: Comment) {
        id = reply.id
        self.reply = reply
        display = DynamicCommentRowDisplayModel(comment: reply)
    }
}

nonisolated private struct DynamicCommentReplyItemSignature: Equatable {
    let rootID: Int
    let replies: [Reply]

    init(rootComment: Comment, replies: [Comment]) {
        rootID = rootComment.id
        self.replies = replies.map(Reply.init)
    }

    struct Reply: Equatable {
        let id: Int
        let parentID: Int?
        let dialogID: Int?
        let message: String?

        init(_ reply: Comment) {
            id = reply.id
            parentID = reply.parentID
            dialogID = reply.dialogID
            message = reply.content?.message
        }
    }
}

private struct DynamicCommentReplyItemCacheEntry {
    let signature: DynamicCommentReplyItemSignature
    let items: [DynamicCommentReplyItem]
}

private struct DynamicCommentDialogItemCacheEntry {
    let signature: DynamicCommentReplyItemSignature
    let items: [DynamicCommentDialogItem]
}

private struct DynamicCommentReplyRootView: View {
    let comment: Comment
    private let display: DynamicCommentRowDisplayModel

    init(comment: Comment) {
        self.comment = comment
        self.display = DynamicCommentRowDisplayModel(comment: comment)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            DynamicCommentAvatar(urlString: display.avatarURLString, size: 40)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(display.authorName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if !display.timeText.isEmpty {
                        Text(display.timeText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicCommentText(
                    content: comment.content,
                    font: .subheadline,
                    textColor: .primary,
                    emoteSize: 22,
                    lineSpacing: 2
                )

                DynamicCommentImageGrid(images: display.pictures)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
    }
}

private struct DynamicCommentReplyDetailRow: View {
    let item: DynamicCommentReplyItem
    let showDialog: (() -> Void)?

    private var reply: Comment {
        item.reply
    }

    private var display: DynamicCommentRowDisplayModel {
        item.display
    }

    init(item: DynamicCommentReplyItem, showDialog: (() -> Void)?) {
        self.item = item
        self.showDialog = showDialog
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            DynamicCommentAvatar(urlString: display.avatarURLString, size: 36)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(display.authorName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if !display.timeText.isEmpty {
                        Text(display.timeText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Label(display.likeText, systemImage: display.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(.caption)
                        .foregroundStyle(display.isLiked ? .pink : .secondary)
                        .labelStyle(.titleAndIcon)
                }

                DynamicCommentText(
                    content: reply.content,
                    font: .subheadline,
                    textColor: .primary,
                    emoteSize: 22,
                    lineSpacing: 2
                )

                DynamicCommentImageGrid(images: display.pictures)

                if let showDialog {
                    Button(action: showDialog) {
                        Label("查看对话", systemImage: "text.bubble")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.pink)
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
        .padding(.vertical, 12)
    }
}

private struct DynamicCommentDialogSheet: View {
    let rootComment: Comment
    let focusReply: Comment
    let replyStore: DynamicCommentReplyStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DynamicCommentReplyRootView(comment: rootComment)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                    Divider()

                    DynamicCommentDialogContent(rootComment: rootComment, focusReply: focusReply, replyStore: replyStore)
                }
            }
            .hiddenInlineNavigationTitle()
            .nativeTopScrollEdgeEffect()
            .task {
                await replyStore.loadDialog(for: rootComment, reply: focusReply)
            }
        }
        .presentationDetents([.fraction(0.7)])
        .presentationDragIndicator(.visible)
    }
}

private struct DynamicCommentDialogContent: View {
    let rootComment: Comment
    let focusReply: Comment
    @ObservedObject var replyStore: DynamicCommentReplyStore

    @ViewBuilder
    var body: some View {
        let snapshot = replyStore.dialogSnapshot(for: rootComment, reply: focusReply)

        if snapshot.items.isEmpty && snapshot.state.isLoading {
            CommentLoadingSkeletonList(count: 3)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        } else if snapshot.items.isEmpty, case .failed(let message) = snapshot.state {
            DynamicCommentErrorView(message: message) {
                Task { await replyStore.reloadDialog(for: rootComment, reply: focusReply) }
            }
            .padding(16)
        } else if snapshot.items.isEmpty {
            EmptyStateView(title: "暂无对话", systemImage: "text.bubble", message: "暂时没有找到这条回复的上下文。")
                .padding(16)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(snapshot.items) { item in
                    DynamicCommentDialogRow(item: item, isFocused: item.id == focusReply.id)
                        .padding(.horizontal, 16)

                    Divider()
                        .padding(.leading, 66)
                }

                if case .failed(let message) = snapshot.state {
                    DynamicCommentErrorView(message: message) {
                        Task { await replyStore.reloadDialog(for: rootComment, reply: focusReply) }
                    }
                    .padding(16)
                }
            }
        }
    }
}

private struct DynamicCommentDialogRow: View {
    let item: DynamicCommentDialogItem
    let isFocused: Bool

    private var reply: Comment {
        item.reply
    }

    private var display: DynamicCommentRowDisplayModel {
        item.display
    }

    init(item: DynamicCommentDialogItem, isFocused: Bool) {
        self.item = item
        self.isFocused = isFocused
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            DynamicCommentAvatar(urlString: display.avatarURLString, size: 36)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(display.authorName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if !display.timeText.isEmpty {
                        Text(display.timeText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Label(display.likeText, systemImage: display.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(.caption)
                        .foregroundStyle(display.isLiked ? .pink : .secondary)
                        .labelStyle(.titleAndIcon)
                }

                DynamicCommentText(
                    content: reply.content,
                    font: .subheadline,
                    textColor: .primary,
                    emoteSize: 22,
                    lineSpacing: 2
                )

                DynamicCommentImageGrid(images: display.pictures)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, isFocused ? 10 : 0)
        .background(isFocused ? Color.pink.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DynamicCommentAvatar: View {
    let urlString: String?
    let size: CGFloat

    var body: some View {
        let pixelSize = Int(size * 3)
        AvatarRemoteImage(urlString: urlString, pixelSize: pixelSize) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: size * 0.9))
                .foregroundStyle(.tertiary)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

private struct DynamicCommentImageGrid: View {
    let images: [DynamicImageItem]

    var body: some View {
        CompactDynamicImageMosaicGrid(
            images: images,
            accessibilityName: "评论图片",
            placeholderFill: Color(.secondarySystemGroupedBackground)
        )
        .padding(.top, 2)
    }
}

private struct DynamicCommentErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                Text("评论加载失败")
                    .font(.subheadline.weight(.semibold))
            }

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Button(action: retry) {
                Label("重试", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
            }
            .dynamicCommentGlassButtonStyle()
            .controlSize(.small)
            .buttonBorderShape(.capsule)
            .tint(.pink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .dynamicCommentGlassCard()
    }
}
