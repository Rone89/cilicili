import Foundation
import Combine

@MainActor
final class AppDependencies: ObservableObject {
    let sessionStore: SessionStore
    let libraryStore: LibraryStore
    let api: BiliAPIClient
    let sponsorBlockService: SponsorBlockService
    private let networkMetricsRecorder: BiliNetworkMetricsRecorder

    init() {
        let sessionStore = SessionStore()
        let libraryStore = LibraryStore()
        let networkMetricsRecorder = BiliNetworkMetricsRecorder()
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.urlCache = .shared
        configuration.httpMaximumConnectionsPerHost = 8
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 40
        self.sessionStore = sessionStore
        self.libraryStore = libraryStore
        self.networkMetricsRecorder = networkMetricsRecorder
        self.api = BiliAPIClient(
            session: URLSession(
                configuration: configuration,
                delegate: networkMetricsRecorder,
                delegateQueue: nil
            ),
            sessionStore: sessionStore,
            libraryStore: libraryStore
        )
        self.sponsorBlockService = SponsorBlockService()
    }
}
