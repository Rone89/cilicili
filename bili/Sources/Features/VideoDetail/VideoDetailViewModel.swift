import Foundation
import Combine

@MainActor
final class VideoDetailViewModel: ObservableObject {
    @Published var detail: VideoItem
    @Published var playVariants: [PlayVariant] = []
    @Published var selectedPlayVariant: PlayVariant?
    @Published var related: [VideoItem] = []
    @Published var comments: [Comment] = []
    @Published var danmakus: [DanmakuItem] = []
    @Published var uploaderProfile: UploaderProfile?
    @Published var selectedCID: Int?
    @Published var state: LoadingState = .idle
    @Published var commentState: LoadingState = .idle
    @Published var playURLState: LoadingState = .idle
    @Published var interactionState = VideoInteractionState()
    @Published var interactionMessage: String?
    @Published var isMutatingInteraction = false
    @Published private(set) var stablePlayerViewModel: PlayerStateViewModel?
    @Published var selectedCommentSort: CommentSort = .hot
    @Published private var replyThreads: [Int: [Comment]] = [:]
    @Published private var replyThreadStates: [Int: LoadingState] = [:]
    @Published private var replyThreadPages: [Int: Int] = [:]
    @Published private var replyThreadHasMore: [Int: Bool] = [:]
    @Published private var dialogThreads: [String: [Comment]] = [:]
    @Published private var dialogThreadStates: [String: LoadingState] = [:]

    private let api: BiliAPIClient
    private let libraryStore: LibraryStore
    private let sponsorBlockService: SponsorBlockService
    private var commentCursor = ""
    private var commentsEnd = false
    private var backgroundTasks = [Task<Void, Never>]()
    private var pageLoadingTask: Task<Void, Never>?
    private var detailLoadingTask: Task<Void, Never>?
    private var filterCancellable: AnyCancellable?
    private var sponsorBlockCancellable: AnyCancellable?
    private var sponsorBlockTask: Task<Void, Never>?
    private var sponsorBlockSegments: [SponsorBlockSegment] = []
    private var sponsorBlockIdentity: String?
    private var stablePlayerIdentity: String?

    var hasMoreComments: Bool {
        !commentsEnd
    }

    var uploaderFanCount: Int? {
        uploaderProfile?.follower ?? uploaderProfile?.card?.fans
    }

    var supportsPortraitPlayerMode: Bool {
        selectedPlayVariant?.isPortraitVideo == true
            || detail.dimension?.aspectRatio.map { $0 < 0.9 } == true
            || selectedPage?.dimension?.aspectRatio.map { $0 < 0.9 } == true
            || playVariants.contains(where: \.isPortraitVideo)
    }

    var selectedVideoAspectRatio: Double {
        selectedPlayVariant?.videoAspectRatio
            ?? detail.dimension?.aspectRatio
            ?? selectedPage?.dimension?.aspectRatio
            ?? playVariants.first(where: { $0.videoAspectRatio != nil })?.videoAspectRatio
            ?? 16 / 9
    }

    var hasKnownPlaybackOrientation: Bool {
        selectedPlayVariant?.videoAspectRatio != nil
            || detail.dimension?.aspectRatio != nil
            || selectedPage?.dimension?.aspectRatio != nil
            || playVariants.contains(where: { $0.videoAspectRatio != nil })
    }

    init(
        seedVideo: VideoItem,
        api: BiliAPIClient,
        libraryStore: LibraryStore,
        sponsorBlockService: SponsorBlockService
    ) {
        self.detail = seedVideo
        self.selectedCID = seedVideo.cid ?? seedVideo.pages?.first?.cid
        self.api = api
        self.libraryStore = libraryStore
        self.sponsorBlockService = sponsorBlockService
        filterCancellable = libraryStore.$blocksGoodsComments
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.refilterLoadedComments()
            }
        sponsorBlockCancellable = libraryStore.$sponsorBlockEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                self?.stablePlayerViewModel?.setSponsorBlockEnabled(isEnabled)
                if isEnabled {
                    Task { [weak self] in await self?.loadSponsorBlockSegmentsIfNeeded() }
                }
            }
    }

    deinit {
        backgroundTasks.forEach { $0.cancel() }
        pageLoadingTask?.cancel()
        detailLoadingTask?.cancel()
        sponsorBlockTask?.cancel()
    }

    func load() async {
        guard state != .loading, state != .loaded else { return }

        if canBootstrapPlaybackFromSeed {
            state = .loading
            detailLoadingTask?.cancel()
            cancelSupplementalWork()
            backgroundTasks = [
                Task { [weak self] in await self?.loadPlayURL() },
                Task { [weak self] in await self?.loadDanmaku() }
            ]
            detailLoadingTask = Task { [weak self] in
                await self?.loadFullDetailAndMetadata()
            }
            return
        }

        await loadFullDetailAndMetadata()
    }

    func cancelBackgroundWork() {
        cancelSupplementalWork()
        detailLoadingTask?.cancel()
        detailLoadingTask = nil
    }

    func suspendPlaybackForNavigation() {
        stablePlayerViewModel?.suspendForNavigation()
    }

    private func cancelSupplementalWork() {
        backgroundTasks.forEach { $0.cancel() }
        backgroundTasks = []
        pageLoadingTask?.cancel()
        pageLoadingTask = nil
    }

    private var canBootstrapPlaybackFromSeed: Bool {
        selectedCID != nil && selectedPlayVariant == nil && !playURLState.isLoading
    }

    private func loadFullDetailAndMetadata() async {
        let isCurrentDetailTask = detailLoadingTask != nil
        if state != .loaded {
            state = .loading
        }
        do {
            let fullDetail = try await api.fetchVideoDetail(bvid: detail.bvid)
            guard !Task.isCancelled else { return }
            detail = detail.mergingFilledValues(from: fullDetail)
            selectedCID = selectedCID ?? fullDetail.pages?.first?.cid ?? fullDetail.cid

            state = .loaded
            if isCurrentDetailTask {
                detailLoadingTask = nil
            }

            backgroundTasks += [
                Task { [weak self] in await self?.loadUploaderAndInteraction() },
                Task { [weak self] in await self?.loadPlayURLIfNeeded() },
                Task { [weak self] in await self?.loadRelated() },
                Task { [weak self] in await self?.loadInitialComments() },
                Task { [weak self] in await self?.loadDanmakuIfNeeded() }
            ]
        } catch {
            guard !Task.isCancelled else { return }
            if isCurrentDetailTask {
                detailLoadingTask = nil
            }
            state = .failed(error.localizedDescription)
        }
    }

    func selectPage(_ page: VideoPage) {
        selectedCID = page.cid
        playVariants = []
        selectedPlayVariant = nil
        stablePlayerViewModel?.stop()
        stablePlayerViewModel = nil
        stablePlayerIdentity = nil
        sponsorBlockTask?.cancel()
        sponsorBlockTask = nil
        sponsorBlockSegments = []
        sponsorBlockIdentity = nil
        playURLState = .idle
        danmakus = []
        pageLoadingTask?.cancel()
        pageLoadingTask = Task { [weak self] in
            await self?.loadPlayURL()
            await self?.loadDanmaku()
        }
    }

    func loadMoreCommentsIfNeeded(current comment: Comment?) async {
        guard let comment, comments.last?.id == comment.id, !commentState.isLoading, !commentsEnd else { return }
        await loadCommentsPage()
    }

    func loadMoreComments() async {
        guard !commentState.isLoading, !commentsEnd else { return }
        await loadCommentsPage()
    }

    func retryComments() async {
        await loadInitialComments()
    }

    func replies(for comment: Comment) -> [Comment] {
        replyThreads[comment.id] ?? comment.replies ?? []
    }

    func hasMoreReplies(for comment: Comment) -> Bool {
        if let hasMore = replyThreadHasMore[comment.id] {
            return hasMore
        }
        let loadedCount = replies(for: comment).count
        let totalCount = comment.replyCount ?? comment.replies?.count ?? loadedCount
        return loadedCount < totalCount
    }

    func replyState(for comment: Comment) -> LoadingState {
        replyThreadStates[comment.id] ?? .idle
    }

    func loadReplies(for comment: Comment) async {
        guard replyThreads[comment.id] == nil else { return }
        replyThreadPages[comment.id] = 0
        replyThreadHasMore[comment.id] = true
        await loadReplyPage(for: comment, reset: true)
    }

    func reloadReplies(for comment: Comment) async {
        replyThreads[comment.id] = nil
        replyThreadPages[comment.id] = 0
        replyThreadHasMore[comment.id] = true
        await loadReplyPage(for: comment, reset: true)
    }

    func loadMoreReplies(for comment: Comment) async {
        guard replyThreadHasMore[comment.id] != false,
              !(replyThreadStates[comment.id]?.isLoading ?? false) else { return }
        await loadReplyPage(for: comment, reset: false)
    }

    func dialogReplies(for root: Comment, reply: Comment) -> [Comment] {
        let key = dialogKey(root: root, reply: reply)
        return dialogThreads[key] ?? localDialogReplies(root: root, reply: reply)
    }

    func dialogState(for root: Comment, reply: Comment) -> LoadingState {
        dialogThreadStates[dialogKey(root: root, reply: reply)] ?? .idle
    }

    func loadDialog(for root: Comment, reply: Comment) async {
        let key = dialogKey(root: root, reply: reply)
        guard dialogThreads[key] == nil else { return }
        await loadDialogPage(for: root, reply: reply)
    }

    func reloadDialog(for root: Comment, reply: Comment) async {
        let key = dialogKey(root: root, reply: reply)
        dialogThreads[key] = nil
        await loadDialogPage(for: root, reply: reply)
    }

    func selectCommentSort(_ sort: CommentSort) async {
        guard selectedCommentSort != sort else { return }
        selectedCommentSort = sort
        await loadInitialComments()
    }

    func retryPlayURL() async {
        await loadPlayURL()
    }

    func selectPlayVariant(_ variant: PlayVariant) {
        guard variant.isPlayable else { return }
        selectedPlayVariant = variant
        updateStablePlayerViewModelIfNeeded()
    }

    func toggleLike() async {
        guard let aid = detail.aid else {
            interactionMessage = "没有找到视频 AV 号，无法点赞"
            return
        }
        let targetState = !interactionState.isLiked
        await performInteractionMutation {
            try await api.toggleVideoLike(aid: aid, liked: targetState)
            interactionState.isLiked = targetState
        }
    }

    func addCoin() async {
        guard let aid = detail.aid else {
            interactionMessage = "没有找到视频 AV 号，无法投币"
            return
        }
        guard interactionState.coinCount < 2 else {
            interactionMessage = "这个视频已经投过 2 枚币了"
            return
        }
        await performInteractionMutation {
            try await api.addVideoCoin(aid: aid, selectLike: interactionState.isLiked)
            interactionState.coinCount += 1
        }
    }

    func toggleFavorite() async {
        guard let aid = detail.aid else {
            interactionMessage = "没有找到视频 AV 号，无法收藏"
            return
        }
        let targetState = !interactionState.isFavorited
        await performInteractionMutation {
            try await api.setVideoFavorite(aid: aid, favorited: targetState)
            interactionState.isFavorited = targetState
        }
    }

    func toggleFollow() async {
        guard let mid = detail.owner?.mid, mid > 0 else {
            interactionMessage = "没有找到 UP 主 UID，无法关注"
            return
        }
        let targetState = !interactionState.isFollowing
        await performInteractionMutation {
            try await api.setUploaderFollowing(mid: mid, following: targetState)
            interactionState.isFollowing = targetState
        }
    }

    private func loadUploaderAndInteraction() async {
        await loadUploaderProfile()
        guard !Task.isCancelled else { return }
        await loadInteractionState()
    }

    private func loadPlayURLIfNeeded() async {
        guard selectedPlayVariant == nil, !playURLState.isLoading else { return }
        await loadPlayURL()
    }

    private func loadPlayURL() async {
        playURLState = .loading
        guard let cid = selectedCID else {
            playVariants = []
            selectedPlayVariant = nil
            playURLState = .failed("没有找到视频 CID，无法请求播放地址")
            return
        }
        do {
            let data = try await api.fetchPlayURL(bvid: detail.bvid, cid: cid, page: selectedPageNumber)
            guard !Task.isCancelled else { return }
            let variants = data.playVariants
            playVariants = variants
            selectedPlayVariant = preferredDefaultVariant(in: variants)
            updateStablePlayerViewModelIfNeeded()
            playURLState = variants.isEmpty ? .failed("播放接口没有返回清晰度或播放地址") : .loaded
        } catch {
            guard !Task.isCancelled else { return }
            playVariants = []
            selectedPlayVariant = nil
            playURLState = .failed(error.localizedDescription)
        }
    }

    func updateStablePlayerViewModelIfNeeded() {
        guard let variant = selectedPlayVariant, variant.isPlayable else {
            stablePlayerViewModel?.stop()
            stablePlayerViewModel = nil
            stablePlayerIdentity = nil
            return
        }

        let identity = playerIdentity(for: variant)
        guard stablePlayerIdentity != identity else { return }

        let resumeTime = stablePlayerViewModel?.currentTime ?? 0
        stablePlayerViewModel?.stop()
        stablePlayerIdentity = identity
        stablePlayerViewModel = PlayerStateViewModel(
            videoURL: variant.videoURL,
            audioURL: variant.audioURL,
            videoStream: variant.videoStream,
            audioStream: variant.audioStream,
            title: detail.title,
            danmakus: danmakus,
            referer: "https://www.bilibili.com",
            durationHint: detail.duration.map(TimeInterval.init),
            resumeTime: resumeTime
        )
        applySponsorBlockSegmentsToPlayer()
        Task { await loadSponsorBlockSegmentsIfNeeded() }
    }

    private func playerIdentity(for variant: PlayVariant) -> String {
        "\(selectedCID ?? 0)-\(variant.id)"
    }

    private func sponsorBlockIdentity(for bvid: String, cid: Int) -> String {
        "\(bvid)-\(cid)"
    }

    private var selectedPageNumber: Int? {
        guard let selectedCID else { return nil }
        return detail.pages?.first(where: { $0.cid == selectedCID })?.page
    }

    private var selectedPage: VideoPage? {
        guard let selectedCID else { return detail.pages?.first }
        return detail.pages?.first(where: { $0.cid == selectedCID }) ?? detail.pages?.first
    }

    private func preferredDefaultVariant(in variants: [PlayVariant]) -> PlayVariant? {
        let playableVariants = variants.filter(\.isPlayable)
        let preferredQualities = [116, 112, 80]

        for quality in preferredQualities {
            if let variant = playableVariants.first(where: { $0.quality == quality }) {
                return variant
            }
        }

        return playableVariants.first ?? variants.first
    }

    private func loadUploaderProfile() async {
        guard let mid = detail.owner?.mid, mid > 0 else {
            uploaderProfile = nil
            interactionState.isFollowing = false
            return
        }

        do {
            let profile = try await api.fetchUploaderProfile(mid: mid)
            uploaderProfile = profile
            interactionState.isFollowing = profile.following == true
        } catch {
            uploaderProfile = nil
            interactionState.isFollowing = false
        }
    }

    private func loadInteractionState() async {
        guard let aid = detail.aid else { return }
        do {
            var state = try await api.fetchVideoInteractionState(aid: aid)
            state.isFollowing = uploaderProfile?.following == true
            interactionState = state
            interactionMessage = nil
        } catch BiliAPIError.missingSESSDATA {
            interactionState.isFollowing = uploaderProfile?.following == true
        } catch {
            interactionMessage = "互动状态同步失败：\(error.localizedDescription)"
        }
    }

    private func loadRelated() async {
        do {
            related = Array(try await api.fetchVideoRelated(bvid: detail.bvid).prefix(5))
        } catch {
            guard !Task.isCancelled else { return }
            related = []
        }
    }

    private func loadInitialComments() async {
        commentCursor = ""
        commentsEnd = false
        comments = []
        await loadCommentsPage()
    }

    private func loadCommentsPage() async {
        guard let aid = detail.aid else {
            commentState = .failed("没有找到视频 AV 号，无法加载评论")
            return
        }
        commentState = .loading
        do {
            let page = try await api.fetchComments(aid: aid, cursor: commentCursor, sort: selectedCommentSort)
            let pageComments = comments.isEmpty
                ? (page.topReplies ?? []) + (page.replies ?? [])
                : (page.replies ?? [])
            appendUniqueComments(filteredComments(pageComments))
            commentCursor = page.cursor?.next ?? ""
            commentsEnd = page.cursor?.isEnd ?? true
            commentState = .loaded
        } catch {
            commentState = .failed(error.localizedDescription)
        }
    }

    private func loadReplyPage(for comment: Comment, reset: Bool) async {
        guard let aid = detail.aid else {
            replyThreadStates[comment.id] = .failed("没有找到视频 AV 号，无法加载回复")
            return
        }
        replyThreadStates[comment.id] = .loading
        do {
            let nextPage = reset ? 1 : (replyThreadPages[comment.id] ?? 1) + 1
            let page = try await api.fetchCommentReplies(aid: aid, root: comment.rpid, page: nextPage)
            let fetchedReplies = filteredComments(page.replies ?? [])
            let existingReplies = reset
                ? filteredComments(comment.replies ?? [])
                : filteredComments(replyThreads[comment.id] ?? comment.replies ?? [])
            let replies = uniqueComments(existingReplies + fetchedReplies)
            replyThreads[comment.id] = replies
            replyThreadPages[comment.id] = nextPage
            let totalCount = comment.replyCount ?? Int.max
            replyThreadHasMore[comment.id] = !fetchedReplies.isEmpty && replies.count < totalCount
            replyThreadStates[comment.id] = .loaded
        } catch {
            if reset {
                replyThreads[comment.id] = filteredComments(comment.replies ?? [])
            }
            replyThreadStates[comment.id] = .failed(error.localizedDescription)
        }
    }

    private func loadDialogPage(for root: Comment, reply: Comment) async {
        guard let aid = detail.aid else {
            dialogThreadStates[dialogKey(root: root, reply: reply)] = .failed("没有找到视频 AV 号，无法加载对话")
            return
        }

        let key = dialogKey(root: root, reply: reply)
        let fallbackReplies = filteredComments(localDialogReplies(root: root, reply: reply))

        guard let dialogID = reply.dialogID, dialogID > 0 else {
            dialogThreads[key] = fallbackReplies
            dialogThreadStates[key] = .loaded
            return
        }

        dialogThreadStates[key] = .loading
        do {
            let page = try await api.fetchCommentDialog(aid: aid, root: root.rpid, dialog: dialogID)
            let replies = uniqueComments(filteredComments(page.replies ?? []) + fallbackReplies)
            dialogThreads[key] = replies.isEmpty ? fallbackReplies : replies
            dialogThreadStates[key] = .loaded
        } catch {
            dialogThreads[key] = fallbackReplies
            dialogThreadStates[key] = .failed(error.localizedDescription)
        }
    }

    private func loadDanmaku() async {
        guard let cid = selectedCID else { return }
        do {
            let xml = try await api.fetchDanmakuXML(cid: cid)
            guard !Task.isCancelled else { return }
            danmakus = DanmakuParser.parse(xml: xml)
            updateStablePlayerViewModelIfNeeded()
        } catch {
            guard !Task.isCancelled else { return }
            danmakus = []
        }
    }

    private func loadDanmakuIfNeeded() async {
        guard danmakus.isEmpty else { return }
        await loadDanmaku()
    }

    private func loadSponsorBlockSegmentsIfNeeded() async {
        guard libraryStore.sponsorBlockEnabled, let cid = selectedCID else {
            sponsorBlockTask?.cancel()
            sponsorBlockTask = nil
            sponsorBlockSegments = []
            sponsorBlockIdentity = nil
            stablePlayerViewModel?.setSponsorBlockSegments([], isEnabled: false)
            return
        }

        let identity = sponsorBlockIdentity(for: detail.bvid, cid: cid)
        if sponsorBlockIdentity == identity {
            applySponsorBlockSegmentsToPlayer()
            return
        }

        sponsorBlockTask?.cancel()
        sponsorBlockTask = Task { [weak self] in
            guard let self else { return }
            do {
                let segments = try await self.sponsorBlockService.fetchSkipSegments(bvid: self.detail.bvid, cid: cid)
                guard !Task.isCancelled else { return }
                self.sponsorBlockIdentity = identity
                self.sponsorBlockSegments = segments
                self.applySponsorBlockSegmentsToPlayer()
            } catch {
                guard !Task.isCancelled else { return }
                self.sponsorBlockIdentity = identity
                self.sponsorBlockSegments = []
                self.applySponsorBlockSegmentsToPlayer()
            }
            self.sponsorBlockTask = nil
        }
        await sponsorBlockTask?.value
    }

    private func applySponsorBlockSegmentsToPlayer() {
        stablePlayerViewModel?.setSponsorBlockSegments(
            sponsorBlockSegments,
            isEnabled: libraryStore.sponsorBlockEnabled
        ) { [sponsorBlockService] event in
            await sponsorBlockService.reportViewed(uuid: event.segment.uuid)
        }
    }

    private func appendUniqueComments(_ more: [Comment]) {
        let existing = Set(comments.map(\.id))
        comments.append(contentsOf: more.filter { !existing.contains($0.id) })
    }

    private func filteredComments(_ values: [Comment]) -> [Comment] {
        guard libraryStore.blocksGoodsComments else { return values }
        return values.filter { !$0.containsGoodsPromotion }
    }

    private func refilterLoadedComments() {
        if libraryStore.blocksGoodsComments {
            comments = filteredComments(comments)
            replyThreads = replyThreads.mapValues(filteredComments)
            dialogThreads = dialogThreads.mapValues(filteredComments)
        } else {
            Task { await reloadCommentRelatedData() }
        }
    }

    private func reloadCommentRelatedData() async {
        await loadInitialComments()
        for root in Array(replyThreads.keys) {
            replyThreads[root] = nil
            replyThreadPages[root] = 0
            replyThreadHasMore[root] = true
        }
        dialogThreads.removeAll()
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

    private func uniqueComments(_ comments: [Comment]) -> [Comment] {
        var seen = Set<Int>()
        return comments.filter { seen.insert($0.id).inserted }
    }

    private func performInteractionMutation(_ operation: () async throws -> Void) async {
        guard !isMutatingInteraction else { return }
        isMutatingInteraction = true
        interactionMessage = nil
        defer { isMutatingInteraction = false }

        do {
            try await operation()
            await refreshDetailMetadata()
        } catch {
            interactionMessage = interactionFailureMessage(error)
        }
    }

    private func refreshDetailMetadata() async {
        do {
            let updated = try await api.fetchVideoDetail(bvid: detail.bvid)
            detail = updated
            if selectedCID == nil {
                selectedCID = updated.pages?.first?.cid ?? updated.cid
            }
        } catch {
            // The interaction already succeeded, so stale stat counts should not block the UI state update.
        }

        await loadUploaderProfile()
        await loadInteractionState()
    }

    private func interactionFailureMessage(_ error: Error) -> String {
        if case BiliAPIError.missingSESSDATA = error {
            return "请先登录后再进行互动操作"
        }
        return error.localizedDescription
    }
}
