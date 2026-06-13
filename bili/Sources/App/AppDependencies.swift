import Foundation
import Combine
import UIKit

@MainActor
final class AppDependencies: ObservableObject {
    let sessionStore: SessionStore
    let libraryStore: LibraryStore
    let api: BiliAPIClient
    let sponsorBlockService: SponsorBlockService
    private let networkMetricsRecorder: BiliNetworkMetricsRecorder
    private var sessionCancellables = Set<AnyCancellable>()

    init() {
        let sessionStore = SessionStore()
        let libraryStore = LibraryStore()
        let networkMetricsRecorder = BiliNetworkMetricsRecorder()
        self.sessionStore = sessionStore
        self.libraryStore = libraryStore
        self.networkMetricsRecorder = networkMetricsRecorder
        self.api = BiliAPIClient(
            session: BiliURLSessionFactory.makeAPISession(delegate: networkMetricsRecorder),
            sessionStore: sessionStore,
            libraryStore: libraryStore
        )
        self.sponsorBlockService = SponsorBlockService()
        sessionStore.$sessdata
            .removeDuplicates()
            .dropFirst()
            .sink { _ in
                Task {
                    await PlayURLCache.shared.invalidateForLoginStateChange()
                    await VideoPreloadCenter.shared.clearPlayURLCache()
                    await DynamicFeedWarmCache.shared.clear()
                }
            }
            .store(in: &sessionCancellables)
        NotificationCenter.default.publisher(for: .biliPlaybackNetworkClassDidChange)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handlePlaybackNetworkClassChange()
                }
            }
            .store(in: &sessionCancellables)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshPlaybackCDNProbeOnAppActivationIfNeeded()
                }
            }
            .store(in: &sessionCancellables)
        Task(priority: .utility) { [api] in
            await RemoteImageCache.shared.applyAdaptiveBudget()
            async let startupResources: Void = api.prewarmStartupResources()
            async let dynamicFeed: Void = DynamicFeedWarmCache.shared.prewarm(api: api)
            _ = await (startupResources, dynamicFeed)
        }
        Task { @MainActor [weak self] in
            self?.refreshPlaybackCDNProbeOnAppActivationIfNeeded()
        }
    }

    func refreshPlaybackCDNProbeIfNeeded() {
        PlaybackCDNProbeCoordinator.shared.refreshIfNeeded(libraryStore: libraryStore)
    }

    func refreshPlaybackCDNProbeOnAppActivationIfNeeded() {
        PlaybackCDNProbeCoordinator.shared.refreshOnAppActivationIfNeeded(libraryStore: libraryStore)
    }

    private func handlePlaybackNetworkClassChange() {
        libraryStore.syncPlaybackCDNProbeSnapshotForCurrentContext()
        Task(priority: .utility) { [libraryStore] in
            await RemoteImageCache.shared.refreshNetworkSessionForPathChange()
            BiliPlaybackNetworkSessionPool.shared.refreshForNetworkPathChange()
            PlaybackRangeStreamingSessionCoordinator.refreshForNetworkPathChange()
            PlaybackCDNProbeCoordinator.shared.refreshIfNeeded(libraryStore: libraryStore)
        }
    }
}
