import Foundation
import Combine

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var videos: [VideoItem] = []
    private(set) var videoCells: [HomeVideoCellModel] = []
    @Published var state: LoadingState = .loading
    @Published var mode: HomeFeedMode = .recommend
    @Published var isRefreshing = false
    @Published var isUserRefreshing = false

    static let userRefreshRecommendationCount = 10
    private let libraryStore: LibraryStore
    var requestRevision = 0
    var lastUserRefreshDate: Date?
    private var recommendContextCancellable: AnyCancellable?
    let pageCoordinator: HomeFeedPageCoordinator
    let snapshotCoordinator: HomeFeedSnapshotCoordinator
    let mediaPreloadCoordinator: HomeFeedMediaPreloadCoordinator
    let exposureRecorder: HomeFeedExposureRecorder
    var cellStore = HomeFeedCellStore()

    init(api: BiliAPIClient, libraryStore: LibraryStore, initialMode: HomeFeedMode = .recommend) {
        self.libraryStore = libraryStore
        pageCoordinator = HomeFeedPageCoordinator(
            api: api,
            libraryStore: libraryStore
        )
        snapshotCoordinator = HomeFeedSnapshotCoordinator(libraryStore: libraryStore)
        mediaPreloadCoordinator = HomeFeedMediaPreloadCoordinator(
            api: api,
            libraryStore: libraryStore
        )
        exposureRecorder = HomeFeedExposureRecorder(pageCoordinator: pageCoordinator)
        mode = initialMode
        recommendContextCancellable = Publishers.CombineLatest(
            libraryStore.$guestModeEnabled,
            libraryStore.$homeRecommendFeedSourcePreference
        )
            .removeDuplicates { lhs, rhs in
                lhs.0 == rhs.0 && lhs.1 == rhs.1
            }
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.reloadForRecommendContextChange() }
            }
    }

    func updateFeed(_ newVideos: [VideoItem]) {
        videoCells = cellStore.update(with: newVideos)
        videos = newVideos
    }

}
