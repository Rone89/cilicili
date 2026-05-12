import Foundation
import Combine
import OSLog

@MainActor
final class VideoDetailViewModel: ObservableObject {
    @Published var detail: VideoItem
    @Published var playVariants: [PlayVariant] = []
    @Published var selectedPlayVariant: PlayVariant?
    @Published var related: [VideoItem] = []
    @Published var relatedState: LoadingState = .idle
    @Published var comments: [Comment] = []
    @Published var uploaderProfile: UploaderProfile?
    @Published var selectedCID: Int?
    @Published var state: LoadingState = .idle
    @Published var commentState: LoadingState = .idle
    @Published var playURLState: LoadingState = .idle
    @Published var isSupplementingPlayQualities = false
    @Published private(set) var isSwitchingPlayQuality = false
    @Published private(set) var pendingPlayVariantID: String?
    @Published var interactionState = VideoInteractionState()
    @Published var interactionMessage: String?
    @Published var isMutatingInteraction = false
    @Published private(set) var didCompleteInitialCommentLoad = false
    @Published private(set) var stablePlayerViewModel: PlayerStateViewModel?
    @Published var selectedCommentSort: CommentSort = .hot
    @Published var playbackFallbackMessage: String?
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
    private var playURLSupplementTask: Task<Void, Never>?
    private var playVariantSwitchTask: Task<Void, Never>?
    private var commentsLoadingTask: Task<Void, Never>?
    private var commentsLoadingToken: UUID?
    private var startupPlayURLTask: Task<PlayURLData, Error>?
    private var startupPlayURLTaskKey: String?
    private var relatedPreloadTask: Task<Void, Never>?
    private var filterCancellable: AnyCancellable?
    private var sponsorBlockCancellable: AnyCancellable?
    private var sponsorBlockTask: Task<Void, Never>?
    private var sponsorBlockSegments: [SponsorBlockSegment] = []
    private var sponsorBlockIdentity: String?
    private var stablePlayerIdentity: String?
    private var stablePlayerErrorCancellable: AnyCancellable?
    private var didSelectPlayVariantManually = false
    private var isPlaybackInvalidatedForNavigation = false
    private var playVariantSwitchToken: UUID?

    var hasMoreComments: Bool {
        !commentsEnd
    }

    var shouldShowRelatedSectionShell: Bool {
        state != .idle || playURLState != .idle || relatedState != .idle || !related.isEmpty
    }

    var shouldShowEmptyCommentsState: Bool {
        guard didCompleteInitialCommentLoad,
              comments.isEmpty,
              commentState == .loaded
        else { return false }
        if let replyCount = detail.stat?.reply {
            return replyCount == 0 && commentsEnd
        }
        return commentsEnd
    }

    var shouldShowCommentReloadPrompt: Bool {
        didCompleteInitialCommentLoad
            && comments.isEmpty
            && commentState == .loaded
            && !shouldShowEmptyCommentsState
    }

    var uploaderFanCount: Int? {
        uploaderProfile?.follower ?? uploaderProfile?.card?.fans
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
                    self?.scheduleSponsorBlockSegmentsAfterFirstFrame()
                } else {
                    self?.resetSponsorBlockSegments()
                }
            }
    }

    deinit {
        backgroundTasks.forEach { $0.cancel() }
        pageLoadingTask?.cancel()
        detailLoadingTask?.cancel()
        playURLSupplementTask?.cancel()
        playVariantSwitchTask?.cancel()
        commentsLoadingTask?.cancel()
        commentsLoadingToken = nil
        startupPlayURLTask?.cancel()
        relatedPreloadTask?.cancel()
        sponsorBlockTask?.cancel()
    }

    func load() async {
        isPlaybackInvalidatedForNavigation = false
        if state == .loading {
            return
        }
        if state == .loaded {
            if stablePlayerViewModel == nil {
                if selectedPlayVariant?.isPlayable == true {
                    updateStablePlayerViewModelIfNeeded()
                } else {
                    await loadPlayURLIfNeeded()
                }
            }
            return
        }
        PlayerMetricsLog.record(.detailLoadStart, metricsID: detail.bvid, title: detail.title)

        if canBootstrapPlaybackFromSeed {
            state = .loading
            detailLoadingTask?.cancel()
            cancelSupplementalWork()
            backgroundTasks = [
                Task(priority: .userInitiated) { [weak self] in await self?.loadPlayURL() }
            ]
            detailLoadingTask = Task(priority: .utility) { [weak self] in
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

    func stopPlaybackForNavigation() {
        isPlaybackInvalidatedForNavigation = true
        cancelSupplementalWork()
        commentsLoadingTask?.cancel()
        commentsLoadingTask = nil
        commentsLoadingToken = nil
        detailLoadingTask?.cancel()
        detailLoadingTask = nil
        sponsorBlockTask?.cancel()
        sponsorBlockTask = nil
        sponsorBlockSegments = []
        sponsorBlockIdentity = nil
        selectedPlayVariant = nil
        if state.isLoading {
            state = .idle
        }
        playURLState = .idle
        stablePlayerViewModel?.stop()
        stablePlayerViewModel = nil
        stablePlayerIdentity = nil
        stablePlayerErrorCancellable = nil
        playbackFallbackMessage = nil
    }

    private func cancelSupplementalWork() {
        backgroundTasks.forEach { $0.cancel() }
        backgroundTasks = []
        pageLoadingTask?.cancel()
        pageLoadingTask = nil
        playURLSupplementTask?.cancel()
        playURLSupplementTask = nil
        startupPlayURLTask?.cancel()
        startupPlayURLTask = nil
        startupPlayURLTaskKey = nil
        isSupplementingPlayQualities = false
        isSwitchingPlayQuality = false
        pendingPlayVariantID = nil
        playVariantSwitchToken = nil
        relatedPreloadTask?.cancel()
        relatedPreloadTask = nil
    }

    private var canBootstrapPlaybackFromSeed: Bool {
        selectedCID != nil && selectedPlayVariant == nil && !playURLState.isLoading
    }

    private func loadFullDetailAndMetadata() async {
        guard !isPlaybackInvalidatedForNavigation else { return }
        let isCurrentDetailTask = detailLoadingTask != nil
        if state != .loaded {
            state = .loading
        }
        do {
            let fullDetail = try await VideoPreloadCenter.shared.detail(
                for: detail.bvid,
                api: api,
                priority: .userInitiated
            )
            guard !Task.isCancelled, !isPlaybackInvalidatedForNavigation else { return }
            detail = detail.mergingFilledValues(from: fullDetail)
            selectedCID = selectedCID ?? fullDetail.pages?.first?.cid ?? fullDetail.cid

            state = .loaded
            PlayerMetricsLog.record(.detailLoaded, metricsID: detail.bvid, title: detail.title)
            if isCurrentDetailTask {
                detailLoadingTask = nil
            }

            backgroundTasks += [
                Task(priority: .userInitiated) { [weak self] in await self?.loadPlayURLIfNeeded() },
                Task(priority: .utility) { [weak self] in await self?.loadUploaderAndInteractionAfterFirstFrame() },
                Task(priority: .utility) { [weak self] in await self?.loadRelatedAfterFirstFrame() }
            ]
        } catch {
            guard !Task.isCancelled else { return }
            guard !isPlaybackInvalidatedForNavigation else { return }
            if isCurrentDetailTask {
                detailLoadingTask = nil
            }
            state = .failed(error.localizedDescription)
        }
    }

    func selectPage(_ page: VideoPage) {
        isPlaybackInvalidatedForNavigation = false
        selectedCID = page.cid
        playVariants = []
        selectedPlayVariant = nil
        didSelectPlayVariantManually = false
        stablePlayerViewModel?.stop()
        stablePlayerViewModel = nil
        stablePlayerIdentity = nil
        stablePlayerErrorCancellable = nil
        playbackFallbackMessage = nil
        playURLSupplementTask?.cancel()
        playURLSupplementTask = nil
        playVariantSwitchTask?.cancel()
        playVariantSwitchTask = nil
        commentsLoadingTask?.cancel()
        commentsLoadingTask = nil
        commentsLoadingToken = nil
        startupPlayURLTask?.cancel()
        startupPlayURLTask = nil
        startupPlayURLTaskKey = nil
        isSupplementingPlayQualities = false
        isSwitchingPlayQuality = false
        pendingPlayVariantID = nil
        playVariantSwitchToken = nil
        sponsorBlockTask?.cancel()
        sponsorBlockTask = nil
        sponsorBlockSegments = []
        sponsorBlockIdentity = nil
        playURLState = .idle
        pageLoadingTask?.cancel()
        pageLoadingTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.loadPlayURL()
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
        commentsLoadingTask?.cancel()
        commentsLoadingTask = nil
        commentsLoadingToken = nil
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
        commentsLoadingTask?.cancel()
        commentsLoadingTask = nil
        commentsLoadingToken = nil
        await loadInitialComments()
    }

    func loadInitialCommentsIfNeeded() async {
        guard comments.isEmpty, !commentState.isLoading else { return }
        await loadInitialComments()
    }

    func beginInitialCommentsLoadIfNeeded() {
        if commentState.isLoading, commentsLoadingTask == nil {
            commentState = comments.isEmpty ? .idle : .loaded
        }
        guard comments.isEmpty, !commentState.isLoading else { return }
        commentsLoadingTask?.cancel()
        let token = UUID()
        commentsLoadingToken = token
        commentsLoadingTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.loadInitialComments()
            guard self.commentsLoadingToken == token else { return }
            self.commentsLoadingTask = nil
            self.commentsLoadingToken = nil
        }
    }

    func retryPlayURL() async {
        isPlaybackInvalidatedForNavigation = false
        await loadPlayURL()
    }

    func selectPlayVariant(_ variant: PlayVariant) {
        guard !isPlaybackInvalidatedForNavigation, variant.isPlayable else { return }
        guard selectedPlayVariant?.id != variant.id else { return }
        let initialResumeTime = currentPlaybackResumeTime()
        let initialShouldResumePlayback = currentPlaybackIntent()
        let initialPlaybackRate = stablePlayerViewModel?.playbackRate ?? .x10
        let cid = selectedCID
        let token = UUID()
        didSelectPlayVariantManually = true
        libraryStore.setPreferredVideoQuality(variant.quality)
        Task { [quality = variant.quality] in
            await VideoPreloadCenter.shared.updatePlaybackPreferences(preferredQuality: quality)
        }
        playVariantSwitchTask?.cancel()
        playVariantSwitchToken = token
        isSwitchingPlayQuality = true
        pendingPlayVariantID = variant.id
        playVariantSwitchTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await VideoPreloadCenter.shared.warmVariantAndWait(
                variant,
                bvid: self.detail.bvid,
                timeout: 1.15
            )
            guard !Task.isCancelled,
                  !self.isPlaybackInvalidatedForNavigation,
                  self.selectedCID == cid,
                  self.playVariantSwitchToken == token
            else { return }

            let resumeTime = max(initialResumeTime, self.currentPlaybackResumeTime())
            let shouldResumePlayback = initialShouldResumePlayback || self.currentPlaybackIntent()
            let playbackRate = self.stablePlayerViewModel?.playbackRate ?? initialPlaybackRate
            self.selectedPlayVariant = variant
            self.playbackFallbackMessage = nil
            self.updateStablePlayerViewModelIfNeeded(
                resumeTimeOverride: resumeTime,
                shouldResumePlayback: shouldResumePlayback,
                playbackRateOverride: playbackRate
            )
            self.clearPlayVariantSwitchIfCurrent(token)
        }
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
        async let uploader: Void = loadUploaderProfile()
        async let interaction: Void = loadInteractionState()
        _ = await (uploader, interaction)
    }

    private func loadUploaderAndInteractionAfterFirstFrame() async {
        let didPresentPlayback = await waitForFirstFrameOrTimeout(2.4)
        guard !Task.isCancelled, !isPlaybackInvalidatedForNavigation else { return }
        if didPresentPlayback {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, !isPlaybackInvalidatedForNavigation else { return }
        }
        await loadUploaderAndInteraction()
    }

    private func loadPlayURLIfNeeded() async {
        guard !isPlaybackInvalidatedForNavigation, selectedPlayVariant == nil, !playURLState.isLoading else { return }
        await loadPlayURL()
    }

    private func loadPlayURL() async {
        guard !isPlaybackInvalidatedForNavigation else { return }
        playURLState = .loading
        isSupplementingPlayQualities = false
        PlayerMetricsLog.record(.playURLStart, metricsID: detail.bvid, title: detail.title)
        guard let cid = selectedCID else {
            playVariants = []
            selectedPlayVariant = nil
            playURLState = .failed("没有找到视频 CID，无法请求播放地址")
            return
        }
        do {
            let pageNumber = selectedPageNumber
            if let cachedPlayableData = await VideoPreloadCenter.shared.cachedPlayablePlayURL(
                for: detail.bvid,
                cid: cid,
                page: pageNumber,
                preferredQuality: libraryStore.preferredVideoQuality
            ) {
                guard !isPlaybackInvalidatedForNavigation else { return }
                applyPlayURLData(
                    cachedPlayableData,
                    cid: cid,
                    page: pageNumber,
                    source: shouldRefetchForPreferredQuality(cachedPlayableData) ? "playableCacheStaleWhileRefresh" : "playableCache"
                )
                PlayerMetricsLog.record(.playURLLoaded, metricsID: detail.bvid, title: detail.title, message: "\(cachedPlayableData.playVariants.filter(\.isPlayable).count) 个缓存档位")
                return
            }
            if let cachedData = await VideoPreloadCenter.shared.cachedOrPendingPlayURL(
                for: detail.bvid,
                cid: cid,
                page: pageNumber,
                waitsForPending: false,
                preferredQuality: libraryStore.preferredVideoQuality
            ) {
                guard !isPlaybackInvalidatedForNavigation else { return }
                if !shouldRefetchForPreferredQuality(cachedData) {
                    applyPlayURLData(cachedData, cid: cid, page: pageNumber, source: "cache")
                    PlayerMetricsLog.record(.playURLLoaded, metricsID: detail.bvid, title: detail.title, message: "\(cachedData.playVariants.filter(\.isPlayable).count) 个可播放档位")
                    return
                }
                PlayerMetricsLog.logger.info(
                    "playURLCacheBypass bvid=\(self.detail.bvid, privacy: .public) preferred=\(self.libraryStore.preferredVideoQuality ?? 0, privacy: .public) cachedQualities=\(Self.qualitySummary(cachedData.playVariants), privacy: .public)"
                )
            }
            if let pendingData = await VideoPreloadCenter.shared.cachedOrPendingPlayURL(
                for: detail.bvid,
                cid: cid,
                page: pageNumber,
                waitsForPending: true,
                preferredQuality: libraryStore.preferredVideoQuality,
                maximumPendingWait: PlaybackEnvironment.current.preferredPlayURLStartupGrace
            ) {
                guard !isPlaybackInvalidatedForNavigation else { return }
                applyPlayURLData(
                    pendingData,
                    cid: cid,
                    page: pageNumber,
                    source: shouldRefetchForPreferredQuality(pendingData) ? "pendingCacheStaleWhileRefresh" : "pendingCache"
                )
                PlayerMetricsLog.record(.playURLLoaded, metricsID: detail.bvid, title: detail.title, message: "\(pendingData.playVariants.filter(\.isPlayable).count) pending cache variants")
                return
            }
            let data = try await startupPlayURL(
                bvid: detail.bvid,
                cid: cid,
                page: pageNumber
            )
            guard !Task.isCancelled else { return }
            await VideoPreloadCenter.shared.store(
                data,
                bvid: detail.bvid,
                cid: cid,
                page: pageNumber,
                preferredQuality: libraryStore.preferredVideoQuality,
                warmsMedia: false,
                mediaWarmupDelay: 0
            )
            guard !isPlaybackInvalidatedForNavigation else { return }
            applyPlayURLData(data, cid: cid, page: pageNumber, source: "network")
            PlayerMetricsLog.record(.playURLLoaded, metricsID: detail.bvid, title: detail.title, message: "\(data.playVariants.filter(\.isPlayable).count) 个可播放档位")
        } catch {
            guard !Task.isCancelled else { return }
            guard !isPlaybackInvalidatedForNavigation else { return }
            playVariants = []
            selectedPlayVariant = nil
            isSupplementingPlayQualities = false
            playURLState = .failed(error.localizedDescription)
        }
    }

    private func clearPlayVariantSwitchIfCurrent(_ token: UUID) {
        guard playVariantSwitchToken == token else { return }
        playVariantSwitchTask = nil
        playVariantSwitchToken = nil
        pendingPlayVariantID = nil
        isSwitchingPlayQuality = false
    }

    private func fetchStartupPlayURL(
        bvid: String,
        cid: Int,
        page: Int?
    ) async throws -> PlayURLData {
        try await api.fetchStartupPlayURL(
            bvid: bvid,
            cid: cid,
            page: page,
            preferredQuality: libraryStore.preferredVideoQuality
        )
    }

    private func startupPlayURL(
        bvid: String,
        cid: Int,
        page: Int?
    ) async throws -> PlayURLData {
        let key = [bvid, String(cid), page.map(String.init) ?? "-"].joined(separator: "|")
        if startupPlayURLTaskKey == key, let startupPlayURLTask {
            return try await startupPlayURLTask.value
        }

        let task = Task(priority: .userInitiated) { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.fetchStartupPlayURL(bvid: bvid, cid: cid, page: page)
        }
        startupPlayURLTask = task
        startupPlayURLTaskKey = key
        defer {
            if startupPlayURLTaskKey == key {
                startupPlayURLTask = nil
                startupPlayURLTaskKey = nil
            }
        }

        return try await task.value
    }

    private func applyPlayURLData(
        _ data: PlayURLData,
        cid: Int?,
        page: Int?,
        source: String = "unknown",
        schedulesSupplementalLoad: Bool = true
    ) {
        guard !isPlaybackInvalidatedForNavigation else { return }
        if let cid {
            guard selectedCID == cid else { return }
        }
        let variants = sortedPlayVariants(data.playVariants)
        playVariants = variants
        let preferredVariant = preferredDefaultVariant(in: variants)
        selectedPlayVariant = preferredVariant
        logSelectedPlayVariant(preferredVariant, availableVariants: variants, source: source)
        warmPlayVariantForStartupIfNeeded(preferredVariant, cid: cid, page: page)
        updateStablePlayerViewModelIfNeeded()
        playURLState = variants.isEmpty ? .failed("播放接口没有返回清晰度或播放地址") : .loaded
        if schedulesSupplementalLoad,
           shouldSupplementPlayQualities(for: variants),
           let cid {
            scheduleSupplementalPlayURLLoad(
                cid: cid,
                page: page,
                waitsForFirstFrame: true,
                startDelay: 1.2
            )
        }
    }

    private func shouldSupplementPlayQualities(for variants: [PlayVariant]) -> Bool {
        let playableQualities = Set(variants.filter(\.isPlayable).map(\.quality))
        guard !playableQualities.isEmpty else { return false }
        if playableQualities.count < 3 {
            return true
        }
        if playableQualities.contains(112),
           playableQualities.contains(80),
           playableQualities.contains(64),
           playableQualities.count >= 5 {
            return false
        }
        if let preferredQuality = libraryStore.preferredVideoQuality,
           !playableQualities.contains(preferredQuality) {
            return true
        }
        return !playableQualities.contains(112) && !playableQualities.contains(80)
    }

    private func scheduleSupplementalPlayURLLoad(
        cid: Int,
        page: Int?,
        waitsForFirstFrame: Bool = false,
        startDelay: TimeInterval = 0
    ) {
        playURLSupplementTask?.cancel()
        isSupplementingPlayQualities = false
        playURLSupplementTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            guard !self.isPlaybackInvalidatedForNavigation else { return }
            defer {
                if !Task.isCancelled, !self.isPlaybackInvalidatedForNavigation, self.selectedCID == cid {
                    self.isSupplementingPlayQualities = false
                }
            }
            do {
                if waitsForFirstFrame {
                    let didPresentPlayback = await self.waitForFirstFrameOrFailure()
                    guard !Task.isCancelled, !self.isPlaybackInvalidatedForNavigation, self.selectedCID == cid else { return }
                    guard didPresentPlayback else { return }
                }
                if startDelay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(startDelay * 1_000_000_000))
                    guard !Task.isCancelled, !self.isPlaybackInvalidatedForNavigation, self.selectedCID == cid else { return }
                }
                guard !self.isPlaybackInvalidatedForNavigation else { return }
                self.isSupplementingPlayQualities = true
                let data = try await self.api.fetchPlayURL(
                    bvid: self.detail.bvid,
                    cid: cid,
                    page: page,
                    preferredQuality: self.libraryStore.preferredVideoQuality,
                    supplementsQualities: true
                )
                guard !Task.isCancelled, !self.isPlaybackInvalidatedForNavigation, self.selectedCID == cid else { return }
                await VideoPreloadCenter.shared.store(
                    data,
                    bvid: self.detail.bvid,
                    cid: cid,
                    page: page,
                    preferredQuality: self.libraryStore.preferredVideoQuality,
                    warmsMedia: false
                )
                guard !self.isPlaybackInvalidatedForNavigation else { return }
                let variants = data.playVariants
                guard !variants.isEmpty else { return }
                let currentVariant = self.selectedPlayVariant
                let currentID = currentVariant?.id
                self.playVariants = self.mergedSupplementalVariants(
                    variants,
                    preserving: currentVariant
                )
                if let currentID,
                   let matchingVariant = self.playVariants.first(where: { $0.id == currentID }) {
                    self.selectedPlayVariant = matchingVariant
                } else if self.stablePlayerViewModel != nil,
                          let currentVariant,
                          currentVariant.isPlayable {
                    self.selectedPlayVariant = currentVariant
                } else if self.selectedPlayVariant == nil {
                    self.selectedPlayVariant = self.preferredDefaultVariant(in: self.playVariants)
                    self.updateStablePlayerViewModelIfNeeded()
                }
                self.warmLikelySupplementalVariantAfterFirstFrame(cid: cid, page: page)
            } catch {
                guard !Task.isCancelled else { return }
            }
            self.playURLSupplementTask = nil
        }
    }

    private func mergedSupplementalVariants(
        _ variants: [PlayVariant],
        preserving currentVariant: PlayVariant?
    ) -> [PlayVariant] {
        let sortedVariants = sortedPlayVariants(variants)
        guard let currentVariant,
              currentVariant.isPlayable,
              !sortedVariants.contains(where: { $0.id == currentVariant.id })
        else {
            return sortedVariants
        }
        return [currentVariant] + sortedVariants
    }

    func updateStablePlayerViewModelIfNeeded(
        resumeTimeOverride: TimeInterval? = nil,
        shouldResumePlayback: Bool? = nil,
        playbackRateOverride: BiliPlaybackRate? = nil
    ) {
        guard !isPlaybackInvalidatedForNavigation else { return }
        guard let variant = selectedPlayVariant, variant.isPlayable else {
            stablePlayerViewModel?.stop()
            stablePlayerViewModel = nil
            stablePlayerIdentity = nil
            stablePlayerErrorCancellable = nil
            return
        }

        let identity = playerIdentity(for: variant)
        guard stablePlayerIdentity != identity else { return }

        let previousPlayer = stablePlayerViewModel
        let resumeTime = resumeTimeOverride ?? currentPlaybackResumeTime()
        let shouldAutoplay = shouldResumePlayback ?? currentPlaybackIntent()
        let playbackRate = playbackRateOverride ?? previousPlayer?.playbackRate ?? .x10
        stablePlayerViewModel?.stop()
        stablePlayerIdentity = identity
        stablePlayerErrorCancellable = nil
        let playerViewModel = PlayerStateViewModel(
            videoURL: variant.videoURL,
            audioURL: variant.audioURL,
            videoStream: variant.videoStream,
            audioStream: variant.audioStream,
            title: detail.title,
            referer: "https://www.bilibili.com/video/\(detail.bvid)",
            durationHint: detail.duration.map(TimeInterval.init),
            resumeTime: resumeTime,
            startupResumePolicy: resumeTimeOverride == nil ? .deferred : .immediate,
            dynamicRange: variant.dynamicRange,
            metricsID: detail.bvid
        )
        playerViewModel.setPlaybackRate(playbackRate)
        playerViewModel.setPlaybackIntent(shouldAutoplay)
        stablePlayerViewModel = playerViewModel
        PlayerMetricsLog.record(.playerCreated, metricsID: detail.bvid, title: detail.title, message: variant.title)
        observePlaybackErrors(playerViewModel, variant: variant)
        applySponsorBlockSegmentsToPlayer()
        scheduleSponsorBlockSegmentsAfterFirstFrame()
        if shouldAutoplay {
            playerViewModel.play()
        }
    }

    private func currentPlaybackResumeTime() -> TimeInterval {
        guard let player = stablePlayerViewModel else { return 0 }
        let snapshotTime = player.playbackSnapshot().currentTime
        let bestTime = max(snapshotTime ?? 0, player.currentTime)
        guard bestTime.isFinite else { return 0 }
        return max(bestTime, 0)
    }

    private func currentPlaybackIntent() -> Bool {
        guard let player = stablePlayerViewModel else { return true }
        let snapshot = player.playbackSnapshot()
        return player.wantsAutoplay || player.isPlaying || snapshot.isPlaying
    }

    private func observePlaybackErrors(_ playerViewModel: PlayerStateViewModel, variant: PlayVariant) {
        stablePlayerErrorCancellable = playerViewModel.$errorMessage
            .compactMap { $0 }
            .removeDuplicates()
            .sink { [weak self, weak playerViewModel] message in
                guard let self,
                      self.stablePlayerViewModel === playerViewModel
                else { return }
                self.handlePlaybackError(message, for: variant)
            }
    }

    private func handlePlaybackError(_ message: String, for failedVariant: PlayVariant) {
        guard failedVariant.dynamicRange == .dolbyVision,
              selectedPlayVariant?.id == failedVariant.id,
              let fallbackVariant = dolbyPlaybackFallbackVariant(excluding: failedVariant)
        else { return }

        PlayerMetricsLog.logger.error(
            "dolbyPlaybackFallback from=\(failedVariant.quality, privacy: .public) to=\(fallbackVariant.quality, privacy: .public) error=\(message, privacy: .public)"
        )
        playbackFallbackMessage = "杜比视界当前不可播放，已切换到 \(fallbackVariant.title)"
        selectedPlayVariant = fallbackVariant
        updateStablePlayerViewModelIfNeeded()
    }

    private func dolbyPlaybackFallbackVariant(excluding failedVariant: PlayVariant) -> PlayVariant? {
        let candidates = sortedPlayVariants(playVariants)
            .filter {
                $0.isPlayable
                    && $0.id != failedVariant.id
                    && $0.dynamicRange != .dolbyVision
                    && !$0.isProgressiveFastStart
            }
        let preferredFallbackQualities = [112, 116, 120, 80, 74, 64, 32]
        for quality in preferredFallbackQualities {
            if let variant = candidates.first(where: { $0.quality == quality }) {
                return variant
            }
        }
        return candidates.first
            ?? sortedPlayVariants(playVariants).first {
                $0.isPlayable
                    && $0.id != failedVariant.id
                    && $0.dynamicRange != .dolbyVision
            }
    }

    private func playerIdentity(for variant: PlayVariant) -> String {
        "\(selectedCID ?? 0)-\(variant.id)"
    }

    private func sponsorBlockIdentity(for bvid: String, cid: Int) -> String {
        "\(bvid)-\(cid)"
    }

    private var selectedPageNumber: Int? {
        guard let selectedCID else { return nil }
        guard let page = detail.pages?.first(where: { $0.cid == selectedCID })?.page,
              page > 1
        else { return nil }
        return page
    }

    private var selectedPage: VideoPage? {
        guard let selectedCID else { return detail.pages?.first }
        return detail.pages?.first(where: { $0.cid == selectedCID }) ?? detail.pages?.first
    }

    private func preferredDefaultVariant(in variants: [PlayVariant]) -> PlayVariant? {
        let playableVariants = sortedPlayVariants(variants).filter(\.isPlayable)
        let playbackEnvironment = PlaybackEnvironment.current

        if let preferredVariant = storedPreferredVariant(in: playableVariants) {
            return preferredVariant
        }

        let preferredQualities = playbackEnvironment.preferredQualityLadder

        for quality in preferredQualities {
            if let variant = playableVariants.first(where: { $0.quality == quality }) {
                return variant
            }
        }

        return playableVariants.first ?? variants.first
    }

    private func shouldRefetchForPreferredQuality(_ data: PlayURLData) -> Bool {
        guard let preferredQuality = libraryStore.preferredVideoQuality else { return false }
        return data.shouldRefetchForPreferredQuality(preferredQuality)
    }

    private func logSelectedPlayVariant(
        _ variant: PlayVariant?,
        availableVariants: [PlayVariant],
        source: String
    ) {
        let environment = PlaybackEnvironment.current
        let selectedFPS = variant.flatMap { DASHStream.displayFrameRate(from: $0.frameRate) } ?? "-"
        PlayerMetricsLog.logger.info(
            "selectedVariant source=\(source, privacy: .public) bvid=\(self.detail.bvid, privacy: .public) preferred=\(self.libraryStore.preferredVideoQuality ?? 0, privacy: .public) selectedQ=\(variant?.quality ?? 0, privacy: .public) selectedTitle=\(variant?.title ?? "-", privacy: .public) codec=\(variant?.codec ?? "-", privacy: .public) fps=\(selectedFPS, privacy: .public) bandwidth=\(variant?.bandwidth ?? 0, privacy: .public) progressive=\((variant?.isProgressiveFastStart ?? false), privacy: .public) conservative=\(environment.shouldPreferConservativePlayback, privacy: .public) available=\(Self.qualitySummary(availableVariants), privacy: .public)"
        )
    }

    private nonisolated static func qualitySummary(_ variants: [PlayVariant]) -> String {
        let summary = variants
            .filter(\.isPlayable)
            .map { variant in
                let kind = variant.isProgressiveFastStart ? "p" : "d"
                return "\(variant.quality)\(kind)"
            }
            .joined(separator: ",")
        return summary.isEmpty ? "-" : summary
    }

    private func storedPreferredVariant(in playableVariants: [PlayVariant]) -> PlayVariant? {
        guard let preferredQuality = libraryStore.preferredVideoQuality else { return nil }
        let sortedVariants = sortedPlayVariants(playableVariants)
        if let exactVariant = sortedVariants.first(where: { $0.quality == preferredQuality }) {
            return exactVariant
        }

        guard let preferredIndex = LibraryStore.supportedVideoQualities.firstIndex(of: preferredQuality) else {
            return nil
        }
        let fallbackQualities = LibraryStore.supportedVideoQualities.dropFirst(preferredIndex + 1)
        for quality in fallbackQualities {
            if let variant = sortedVariants.first(where: { $0.quality == quality }) {
                return variant
            }
        }
        return nil
    }

    private func sortedPlayVariants(_ variants: [PlayVariant]) -> [PlayVariant] {
        variants.sorted { lhs, rhs in
            if lhs.isPlayable != rhs.isPlayable {
                return lhs.isPlayable && !rhs.isPlayable
            }
            if lhs.isProgressiveFastStart != rhs.isProgressiveFastStart {
                return !lhs.isProgressiveFastStart && rhs.isProgressiveFastStart
            }
            if lhs.quality != rhs.quality {
                return lhs.quality > rhs.quality
            }
            return (lhs.bandwidth ?? 0) > (rhs.bandwidth ?? 0)
        }
    }

    private func warmPlayVariantForStartupIfNeeded(_ variant: PlayVariant?, cid: Int?, page: Int?) {
        guard !isPlaybackInvalidatedForNavigation,
              let cid,
              let variant,
              !variant.isProgressiveFastStart
        else { return }
        Task(priority: .userInitiated) { [detailBVID = detail.bvid, variant] in
            await VideoPreloadCenter.shared.warmVariant(
                variant,
                bvid: detailBVID,
                cid: cid,
                page: page,
                delay: 0
            )
        }
    }

    private func warmLikelySupplementalVariantAfterFirstFrame(cid: Int, page: Int?) {
        guard !isPlaybackInvalidatedForNavigation else { return }
        let variants = supplementalWarmupVariants()
        guard !variants.isEmpty else { return }
        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            let didPresentPlayback = await self.waitForFirstFrameOrFailure()
            guard !self.isPlaybackInvalidatedForNavigation else { return }
            guard didPresentPlayback else { return }
            for (index, variant) in variants.enumerated() {
                guard !self.isPlaybackInvalidatedForNavigation else { return }
                await VideoPreloadCenter.shared.warmVariant(
                    variant,
                    bvid: self.detail.bvid,
                    cid: cid,
                    page: page,
                    delay: index == 0 ? 0 : 0.45
                )
            }
        }
    }

    private func supplementalWarmupVariants() -> [PlayVariant] {
        let selectedVariantID = selectedPlayVariant?.id
        var result = [PlayVariant]()

        func append(_ variant: PlayVariant?) {
            guard let variant,
                  variant.id != selectedVariantID,
                  !result.contains(where: { $0.id == variant.id })
            else { return }
            result.append(variant)
        }

        append(likelySupplementalWarmupVariant())
        append(dolbyVisionWarmupVariant())
        return result
    }

    private func likelySupplementalWarmupVariant() -> PlayVariant? {
        let playableVariants = playVariants.filter(\.isPlayable)
        var preferredWarmupQualities = [Int]()
        if let preferredQuality = libraryStore.preferredVideoQuality {
            preferredWarmupQualities.append(preferredQuality)
        }
        preferredWarmupQualities += [116, 112, 120, 80, 74]
        for quality in preferredWarmupQualities {
            if let variant = playableVariants.first(where: { $0.quality == quality && !$0.isProgressiveFastStart }) {
                return variant
            }
        }
        return playableVariants
            .filter { !$0.isProgressiveFastStart }
            .max(by: { $0.quality < $1.quality })
    }

    private func dolbyVisionWarmupVariant() -> PlayVariant? {
        sortedPlayVariants(playVariants)
            .first {
                $0.isPlayable
                    && !$0.isProgressiveFastStart
                    && $0.dynamicRange == .dolbyVision
            }
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
        guard related.isEmpty, !relatedState.isLoading else { return }
        relatedState = .loading
        do {
            let videos = Array(try await api.fetchVideoRelated(bvid: detail.bvid).prefix(5))
            related = videos
            relatedState = .loaded
            scheduleRelatedPlaybackPreload(for: videos)
        } catch {
            guard !Task.isCancelled else { return }
            related = []
            relatedState = .failed(error.localizedDescription)
        }
    }

    private func loadRelatedAfterFirstFrame() async {
        let didPresentPlayback = await waitForFirstFrameOrFailure()
        guard !Task.isCancelled, !isPlaybackInvalidatedForNavigation else { return }
        guard didPresentPlayback else { return }
        try? await Task.sleep(nanoseconds: 900_000_000)
        guard !Task.isCancelled, !isPlaybackInvalidatedForNavigation else { return }
        await loadRelated()
    }

    @discardableResult
    private func waitForFirstFrameOrTimeout(_ timeout: TimeInterval = 3.0) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while stablePlayerViewModel?.hasPresentedPlayback != true && Date() < deadline {
            guard !Task.isCancelled, !isPlaybackInvalidatedForNavigation else { return false }
            try? await Task.sleep(nanoseconds: 160_000_000)
        }
        return stablePlayerViewModel?.hasPresentedPlayback == true
    }

    private func waitForFirstFrameOrFailure() async -> Bool {
        while stablePlayerViewModel?.hasPresentedPlayback != true {
            guard !Task.isCancelled, !isPlaybackInvalidatedForNavigation else { return false }
            if stablePlayerViewModel?.errorMessage != nil {
                return false
            }
            if case .failed = playURLState {
                return false
            }
            try? await Task.sleep(nanoseconds: 160_000_000)
        }
        return true
    }

    private func scheduleRelatedPlaybackPreload(for videos: [VideoItem]) {
        relatedPreloadTask?.cancel()
        guard !PlaybackEnvironment.current.shouldPreferConservativePlayback else {
            relatedPreloadTask = nil
            return
        }
        let candidates = Array(videos
            .filter { $0.cid != nil && $0.bvid != detail.bvid }
            .prefix(1))
        guard !candidates.isEmpty else {
            relatedPreloadTask = nil
            return
        }
        relatedPreloadTask = Task(priority: .utility) { [api] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            for video in candidates {
                guard !Task.isCancelled else { return }
                await VideoPreloadCenter.shared.preloadPlayInfo(
                    video,
                    api: api,
                    preferredQuality: self.libraryStore.preferredVideoQuality
                )
            }
        }
    }

    private func loadInitialComments() async {
        commentCursor = ""
        commentsEnd = false
        comments = []
        didCompleteInitialCommentLoad = false
        await loadCommentsPage()
    }

    private func loadCommentsPage() async {
        guard let aid = detail.aid else {
            commentState = .failed("没有找到视频 AV 号，无法加载评论")
            return
        }
        let isInitialPage = comments.isEmpty && commentCursor.isEmpty
        commentState = .loading
        do {
            let page = try await fetchCommentsWithTimeout(aid: aid, cursor: commentCursor, sort: selectedCommentSort)
            guard !Task.isCancelled else {
                resetCommentStateAfterCancellation(isInitialPage: isInitialPage)
                return
            }
            let pageComments = comments.isEmpty
                ? (page.topReplies ?? []) + (page.replies ?? [])
                : (page.replies ?? [])
            appendUniqueComments(filteredComments(pageComments))
            commentCursor = page.cursor?.next ?? ""
            commentsEnd = page.cursor?.isEnd ?? true
            if isInitialPage {
                didCompleteInitialCommentLoad = true
            }
            commentState = .loaded
        } catch is CancellationError {
            resetCommentStateAfterCancellation(isInitialPage: isInitialPage)
        } catch {
            guard !Task.isCancelled else { return }
            commentState = .failed(error.localizedDescription)
        }
    }

    private func resetCommentStateAfterCancellation(isInitialPage: Bool) {
        if comments.isEmpty, isInitialPage, !didCompleteInitialCommentLoad {
            commentState = .idle
        } else {
            commentState = .loaded
        }
    }

    private func fetchCommentsWithTimeout(aid: Int, cursor: String, sort: CommentSort) async throws -> CommentPage {
        try await withThrowingTaskGroup(of: CommentPage.self) { group in
            group.addTask(priority: .userInitiated) {
                try await self.api.fetchComments(aid: aid, cursor: cursor, sort: sort)
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

    private func scheduleSponsorBlockSegmentsAfterFirstFrame() {
        guard !isPlaybackInvalidatedForNavigation else { return }
        guard libraryStore.sponsorBlockEnabled, let cid = selectedCID else {
            resetSponsorBlockSegments()
            return
        }

        let identity = sponsorBlockIdentity(for: detail.bvid, cid: cid)
        if sponsorBlockIdentity == identity {
            applySponsorBlockSegmentsToPlayer()
            return
        }

        sponsorBlockTask?.cancel()
        sponsorBlockTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            guard !self.isPlaybackInvalidatedForNavigation else { return }
            await self.waitForFirstFrameOrTimeout()
            guard !Task.isCancelled, !self.isPlaybackInvalidatedForNavigation else { return }
            do {
                let segments = try await self.sponsorBlockService.fetchSkipSegments(bvid: self.detail.bvid, cid: cid)
                guard !Task.isCancelled, !self.isPlaybackInvalidatedForNavigation else { return }
                self.sponsorBlockIdentity = identity
                self.sponsorBlockSegments = segments
                self.applySponsorBlockSegmentsToPlayer()
            } catch {
                guard !Task.isCancelled, !self.isPlaybackInvalidatedForNavigation else { return }
                self.sponsorBlockIdentity = identity
                self.sponsorBlockSegments = []
                self.applySponsorBlockSegmentsToPlayer()
            }
            self.sponsorBlockTask = nil
        }
    }

    private func resetSponsorBlockSegments() {
        sponsorBlockTask?.cancel()
        sponsorBlockTask = nil
        sponsorBlockSegments = []
        sponsorBlockIdentity = nil
        stablePlayerViewModel?.setSponsorBlockSegments([], isEnabled: false)
    }

    private func applySponsorBlockSegmentsToPlayer() {
        guard !isPlaybackInvalidatedForNavigation else { return }
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
