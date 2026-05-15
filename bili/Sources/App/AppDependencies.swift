import Foundation
import Combine

@MainActor
final class AppDependencies: ObservableObject {
    let sessionStore: SessionStore
    let libraryStore: LibraryStore
    let api: BiliAPIClient
    let sponsorBlockService: SponsorBlockService
    private let networkMetricsRecorder: BiliNetworkMetricsRecorder
    private var playbackCDNProbeRefreshTask: Task<Void, Never>?
    private var lastPlaybackCDNAdaptiveRefreshAt: Date?

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

    func refreshPlaybackCDNProbeIfNeeded() {
        guard playbackCDNProbeRefreshTask == nil else { return }
        guard shouldRefreshPlaybackCDNProbe else { return }
        playbackCDNProbeRefreshTask = Task {
            let addressFamilyPreference = await MainActor.run {
                self.libraryStore.playbackNetworkAddressFamilyPreference
            }
            let snapshot = await PlaybackCDNProbeService.recommendedSnapshot(
                addressFamilyPreference: addressFamilyPreference
            )
            await MainActor.run {
                if !Task.isCancelled {
                    self.libraryStore.setPlaybackCDNProbeSnapshot(snapshot)
                    if !self.libraryStore.needsPlaybackCDNProbeRefresh {
                        self.lastPlaybackCDNAdaptiveRefreshAt = Date()
                    }
                }
                self.playbackCDNProbeRefreshTask = nil
            }
        }
    }

    private var shouldRefreshPlaybackCDNProbe: Bool {
        guard libraryStore.playbackCDNPreference == .automatic else { return false }
        if libraryStore.needsPlaybackCDNProbeRefresh {
            return true
        }
        guard PlayerPerformanceStore.shared.shouldRefreshPlaybackCDNProbe(
            isEnabled: libraryStore.isPlaybackAutoOptimizationEnabled
        ) else {
            return false
        }
        guard let snapshot = libraryStore.playbackCDNProbeSnapshot else {
            return true
        }
        if snapshot.isExpired(freshnessInterval: 2 * 60 * 60) {
            return true
        }
        guard let lastPlaybackCDNAdaptiveRefreshAt else {
            return true
        }
        return Date().timeIntervalSince(lastPlaybackCDNAdaptiveRefreshAt) >= 2 * 60 * 60
    }
}
