import Foundation
import Combine

@MainActor
final class AppDependencies: ObservableObject {
    let sessionStore: SessionStore
    let libraryStore: LibraryStore
    let api: BiliAPIClient
    let sponsorBlockService: SponsorBlockService

    init() {
        let sessionStore = SessionStore()
        let libraryStore = LibraryStore()
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.urlCache = .shared
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 45
        self.sessionStore = sessionStore
        self.libraryStore = libraryStore
        self.api = BiliAPIClient(
            session: URLSession(configuration: configuration),
            sessionStore: sessionStore,
            libraryStore: libraryStore
        )
        self.sponsorBlockService = SponsorBlockService()
    }
}
