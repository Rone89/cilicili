import Foundation
import Combine

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var videos: [VideoItem] = []
    private(set) var videoCells: [HomeVideoCellModel] = []
    @Published private(set) var lastSeenMarkerIndex: Int?
    @Published var state: LoadingState = .loading
    @Published var mode: HomeFeedMode = .recommend
    @Published var isRefreshing = false
    @Published var isUserRefreshing = false
    @Published var recommendationFeedbackNotice: HomeRecommendationFeedbackNotice?
    @Published private(set) var isSubmittingRecommendationFeedback = false
    var hiddenRecommendationIDs = Set<String>()
    private var recommendationFilterCancellable: AnyCancellable?

    static let userRefreshRecommendationCount = 10
    let libraryStore: LibraryStore
    let sessionStore: SessionStore
    var requestRevision = 0
    var lastUserRefreshDate: Date?
    var modeSwitchRefreshPending = false
    var retainedRecommendVideos = [VideoItem]()
    var retainedRecommendLastSeenMarkerIndex: Int?
    private var recommendContextCancellable: AnyCancellable?
    let pageCoordinator: HomeFeedPageCoordinator
    let snapshotCoordinator: HomeFeedSnapshotCoordinator
    let mediaPreloadCoordinator: HomeFeedMediaPreloadCoordinator
    let exposureRecorder: HomeFeedExposureRecorder
    var cellStore = HomeFeedCellStore()
    var recommendMetadataHydrationTasks: [String: Task<Void, Never>] = [:]

    init(
        api: BiliAPIClient,
        libraryStore: LibraryStore,
        sessionStore: SessionStore,
        initialMode: HomeFeedMode = .recommend
    ) {
        self.libraryStore = libraryStore
        self.sessionStore = sessionStore
        pageCoordinator = HomeFeedPageCoordinator(
            api: api,
            libraryStore: libraryStore
        )
        snapshotCoordinator = HomeFeedSnapshotCoordinator(
            libraryStore: libraryStore,
            sessionStore: sessionStore
        )
        mediaPreloadCoordinator = HomeFeedMediaPreloadCoordinator(
            api: api,
            libraryStore: libraryStore
        )
        exposureRecorder = HomeFeedExposureRecorder(pageCoordinator: pageCoordinator)
        mode = initialMode
        recommendContextCancellable = Publishers.CombineLatest4(
            libraryStore.$guestModeEnabled,
            libraryStore.$homeRecommendFeedSourcePreference,
            sessionStore.$sessdata,
            sessionStore.$accessKey
        )
            .removeDuplicates { lhs, rhs in
                lhs.0 == rhs.0 && lhs.1 == rhs.1 && lhs.2 == rhs.2 && lhs.3 == rhs.3
            }
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.reloadForRecommendContextChange() }
            }
        recommendationFilterCancellable = Publishers.CombineLatest(
            libraryStore.$homeRecommendationFeedbackContextMenuExperimentEnabled,
            libraryStore.$blockedHomeRecommendationUPMIDs
        )
        .dropFirst()
        .sink { [weak self] enabled, blocked in
            guard let self, enabled else { return }
            self.retainedRecommendLastSeenMarkerIndex = self.retainedRecommendLastSeenMarkerIndex.map { index in
                HomeRecommendationFeedbackPolicy.filtered(
                    Array(self.retainedRecommendVideos.prefix(index)), blockedMIDs: blocked, enabled: enabled
                ).count
            }
            self.retainedRecommendVideos = HomeRecommendationFeedbackPolicy.filtered(
                self.retainedRecommendVideos, blockedMIDs: blocked, enabled: enabled
            )
            guard self.mode == .recommend else { return }
            self.pruneRecommendationFeed {
                HomeRecommendationFeedbackPolicy.filtered([$0], blockedMIDs: blocked, enabled: enabled).isEmpty
            }
        }

    }

    deinit {
        recommendMetadataHydrationTasks.values.forEach { $0.cancel() }
    }

    func updateFeed(_ incomingVideos: [VideoItem]) {
        let newVideos: [VideoItem]
        if mode == .recommend, libraryStore.homeRecommendationFeedbackContextMenuExperimentEnabled {
            newVideos = HomeRecommendationFeedbackPolicy.filtered(
                incomingVideos, blockedMIDs: libraryStore.blockedHomeRecommendationUPMIDs, enabled: true
            ).filter { !hiddenRecommendationIDs.contains($0.id) }
        } else {
            newVideos = incomingVideos
        }
        videoCells = cellStore.update(with: newVideos)
        videos = newVideos
        if !newVideos.isEmpty {
            StageOneBaselineMetricsStore.shared.markHomeFirstData()
        }
    }

    func performRecommendationFeedback(
        video: VideoItem, kind: RecommendationFeedbackKind, reason: RecommendationFeedbackReason
    ) async {
        guard mode == .recommend, libraryStore.homeRecommendationFeedbackContextMenuExperimentEnabled,
              !isSubmittingRecommendationFeedback, let metadata = video.recommendationFeedback
        else { return }
        isSubmittingRecommendationFeedback = true
        defer { isSubmittingRecommendationFeedback = false }
        let accountIdentity = sessionStore.recommendCacheIdentityKey(guestModeEnabled: libraryStore.guestModeEnabled)
        do {
            try await pageCoordinator.api.submitRecommendationFeedback(metadata: metadata, kind: kind, reason: reason)
            guard accountIdentity == sessionStore.recommendCacheIdentityKey(guestModeEnabled: libraryStore.guestModeEnabled) else { return }
            hiddenRecommendationIDs.insert(video.id)
            retainedRecommendLastSeenMarkerIndex = retainedRecommendLastSeenMarkerIndex.map { index in
                retainedRecommendVideos.prefix(index).filter { $0.id != video.id }.count
            }
            retainedRecommendVideos.removeAll { $0.id == video.id }
            if mode == .recommend { pruneRecommendationFeed { $0.id == video.id } }
            recommendationFeedbackNotice = .success(reason.toast?.isEmpty == false ? reason.toast! : "已提交推荐反馈")
        } catch {
            recommendationFeedbackNotice = .failure("推荐反馈失败：\(error.localizedDescription)")
        }
    }

    func blockRecommendationUP(_ owner: VideoOwner, synchronize: Bool) async {
        guard mode == .recommend, owner.mid > 0, libraryStore.homeRecommendationFeedbackContextMenuExperimentEnabled,
              !isSubmittingRecommendationFeedback else { return }
        isSubmittingRecommendationFeedback = true
        defer { isSubmittingRecommendationFeedback = false }
        do {
            if synchronize { try await pageCoordinator.api.blockUploader(mid: owner.mid) }
            libraryStore.blockHomeRecommendationUP(mid: Int64(owner.mid))
            // The publisher prunes current/retained recommendation rows immediately.
            recommendationFeedbackNotice = .success(synchronize ? "已拉黑并屏蔽该 UP 的推荐" : "已在本机屏蔽该 UP 的推荐")
        } catch {
            recommendationFeedbackNotice = .failure("拉黑失败：\(error.localizedDescription)")
        }
    }

    func pruneRecommendationFeed(where shouldRemove: (VideoItem) -> Bool) {
        guard mode == .recommend else { return }
        let marker = lastSeenMarkerIndex.map { index in videos.prefix(index).filter { !shouldRemove($0) }.count }
        updateFeed(videos.filter { !shouldRemove($0) })
        updateLastSeenMarkerIndex(marker)
    }

    var canSubmitRecommendationFeedback: Bool {
        !libraryStore.guestModeEnabled && sessionStore.accessKey?.isEmpty == false
    }

    var canSynchronizeRecommendationBlock: Bool {
        let account = sessionStore.credentialSnapshot(for: .main, multiAccountEnabled: libraryStore.multiAccountEnabled)
        return (account.isLoggedIn && account.csrfToken?.isEmpty == false) || account.accessKey?.isEmpty == false
    }

    func updateLastSeenMarkerIndex(_ index: Int?) {
        guard let index, index > 0, index < videos.count else {
            lastSeenMarkerIndex = nil
            return
        }
        lastSeenMarkerIndex = index
    }

    func recordRecommendExposure(_ video: VideoItem, index: Int) {
        guard mode == .recommend else { return }
        HomeRecommendFeedbackCenter.shared.recordExposure(
            video: video,
            index: index,
            source: libraryStore.homeRecommendFeedSourcePreference
        )
    }

    func updateImagePrefetchProfile(_ profile: HomeFeedCoverPrefetchProfile) {
        mediaPreloadCoordinator.updateImagePrefetchProfile(profile)
        mediaPreloadCoordinator.scheduleImagePrefetch(for: videos)
    }

    func scheduleImageLookahead(visibleIndex: Int) {
        mediaPreloadCoordinator.scheduleImageLookahead(for: videos, visibleIndex: visibleIndex)
    }

    func recordRecommendClick(_ video: VideoItem) {
        guard mode == .recommend else { return }
        HomeRecommendFeedbackCenter.shared.recordClick(
            video: video,
            source: libraryStore.homeRecommendFeedSourcePreference
        )
    }

}
