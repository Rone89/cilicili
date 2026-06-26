import Foundation

@MainActor
final class HomeFeedPageCoordinator {
    let api: BiliAPIClient
    let libraryStore: LibraryStore
    var freshIndex = 0
    var popularPage = 1

    init(api: BiliAPIClient, libraryStore: LibraryStore) {
        self.api = api
        self.libraryStore = libraryStore
    }

    func usesGuestRecommendDiversity(for mode: HomeFeedMode) -> Bool {
        mode == .recommend && libraryStore.guestModeEnabled
    }
}
