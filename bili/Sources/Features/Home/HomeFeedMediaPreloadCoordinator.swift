import Foundation

@MainActor
final class HomeFeedMediaPreloadCoordinator {
    let api: BiliAPIClient
    let libraryStore: LibraryStore
    var imagePrefetchTask: Task<Void, Never>?
    var playbackPreloadTask: Task<Void, Never>?

    init(api: BiliAPIClient, libraryStore: LibraryStore) {
        self.api = api
        self.libraryStore = libraryStore
    }

    deinit {
        imagePrefetchTask?.cancel()
        playbackPreloadTask?.cancel()
    }
}
