import Combine
import Foundation

@MainActor
final class DynamicCommentsViewModel: ObservableObject {
    private(set) var comments: [Comment] = [] {
        didSet {
            syncCommentItems()
        }
    }
    @Published private(set) var commentItems: [DynamicCommentRowItem] = []
    @Published var state: LoadingState = .idle
    @Published var loadMoreState: LoadingState = .idle
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
        loadMoreState = .idle
        await loadPage(presentsErrors: true)
    }

    func selectSort(_ sort: CommentSort) async {
        guard selectedSort != sort else { return }
        selectedSort = sort
        await reload()
    }

    func loadMore() async {
        guard !state.isLoading, !loadMoreState.isLoading, !commentsEnd else { return }
        await loadPage(presentsErrors: false, emptyPageSkipLimit: 2)
    }

    private var commentOID: String? {
        item.commentOID
    }

    private var commentType: Int? {
        item.commentType
    }

    private func loadPage(presentsErrors: Bool, emptyPageSkipLimit: Int = 0) async {
        guard let oid = commentOID, let type = commentType else {
            state = .failed("这条动态没有返回评论入口")
            commentsEnd = true
            return
        }

        let isInitialPage = comments.isEmpty && cursor.isEmpty
        var remainingEmptyPageSkips = emptyPageSkipLimit
        if isInitialPage {
            state = .loading
            loadMoreState = .idle
        } else {
            loadMoreState = .loading
        }
        while true {
            let previousCount = comments.count
            let previousCursor = cursor
            do {
                let page = try await fetchCommentsWithTimeout(oid: oid, type: type, cursor: cursor, sort: selectedSort)
                let pageComments = comments.isEmpty
                    ? (page.topReplies ?? []) + (page.replies ?? [])
                    : (page.replies ?? [])
                appendUniqueComments(filteredComments(pageComments))
                cursor = page.cursor?.effectiveNext ?? ""
                commentsEnd = page.cursor?.isEnd ?? (comments.count == previousCount && cursor.isEmpty)
                state = .loaded
                loadMoreState = .idle

                let didAppendComments = comments.count > previousCount
                let canSkipEmptyPage = !didAppendComments
                    && !commentsEnd
                    && remainingEmptyPageSkips > 0
                    && !cursor.isEmpty
                    && cursor != previousCursor
                guard canSkipEmptyPage else {
                    if !isInitialPage, !didAppendComments {
                        commentsEnd = true
                    }
                    return
                }
                remainingEmptyPageSkips -= 1
                if isInitialPage {
                    state = .loading
                } else {
                    loadMoreState = .loading
                }
            } catch is CancellationError {
                if isInitialPage, comments.isEmpty {
                    state = .idle
                } else {
                    state = .loaded
                    commentsEnd = true
                }
                loadMoreState = .idle
                return
            } catch {
                if presentsErrors || comments.isEmpty {
                    state = .failed(error.localizedDescription)
                    loadMoreState = .idle
                } else {
                    state = .loaded
                    commentsEnd = true
                    loadMoreState = .idle
                }
                return
            }
        }
    }

    private func appendUniqueComments(_ more: [Comment]) {
        let existing = Set(comments.map(\.id))
        comments.append(contentsOf: more.filter { !existing.contains($0.id) })
    }

    private func fetchCommentsWithTimeout(
        oid: String,
        type: Int,
        cursor: String,
        sort: CommentSort
    ) async throws -> CommentPage {
        try await withThrowingTaskGroup(of: CommentPage.self) { group in
            group.addTask(priority: .userInitiated) {
                try await self.api.fetchComments(oid: oid, type: type, cursor: cursor, sort: sort)
            }
            group.addTask(priority: .utility) {
                try await Task.sleep(nanoseconds: 8_000_000_000)
                throw BiliAPIError.api(code: -1, message: "评论加载超时，请稍后重试")
            }
            guard let page = try await group.next() else {
                group.cancelAll()
                throw BiliAPIError.emptyData
            }
            group.cancelAll()
            return page
        }
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
