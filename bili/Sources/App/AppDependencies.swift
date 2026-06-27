import Foundation
import Combine
import KSPlayer
import UIKit

@MainActor
final class AppDependencies: ObservableObject {
    let sessionStore: SessionStore
    let libraryStore: LibraryStore
    let api: BiliAPIClient
    let sponsorBlockService: SponsorBlockService
    private let networkMetricsRecorder: BiliNetworkMetricsRecorder
    private var sessionCancellables = Set<AnyCancellable>()
    private var hasScheduledDeferredStartupWork = false
    private var hasCompletedDeferredStartupWork = false
    private var deferredStartupWorkTask: Task<Void, Never>?

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
        Self.applyPictureInPicturePreference(libraryStore.pictureInPictureEnabled)
        libraryStore.$pictureInPictureEnabled
            .removeDuplicates()
            .sink { isEnabled in
                Self.applyPictureInPicturePreference(isEnabled)
            }
            .store(in: &sessionCancellables)
        Publishers.CombineLatest(sessionStore.$sessdata, sessionStore.$accessKey)
            .removeDuplicates { lhs, rhs in
                lhs.0 == rhs.0 && lhs.1 == rhs.1
            }
            .dropFirst()
            .sink { [weak self] _ in
                Task {
                    await PlayURLCache.shared.invalidateForLoginStateChange()
                    await VideoPreloadCenter.shared.clearPlayURLCache()
                    await DynamicFeedWarmCache.shared.clear()
                    await self?.api.resetHomeRecommendState()
                    HomeFeedSnapshotCache.clearAll()
                }
            }
            .store(in: &sessionCancellables)
        libraryStore.$playbackStreamSourcePreference
            .removeDuplicates()
            .dropFirst()
            .sink { _ in
                Task {
                    await PlayURLCache.shared.clearMemoryCache()
                    await VideoPreloadCenter.shared.clearPlayURLCache()
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
                    self?.handleAppDidBecomeActive()
                }
            }
            .store(in: &sessionCancellables)
    }

    deinit {
        deferredStartupWorkTask?.cancel()
    }

    func refreshPlaybackCDNProbeIfNeeded() {
        PlaybackCDNProbeCoordinator.shared.refreshIfNeeded(libraryStore: libraryStore)
    }

    func refreshPlaybackCDNProbeOnAppActivationIfNeeded() {
        PlaybackCDNProbeCoordinator.shared.refreshOnAppActivationIfNeeded(libraryStore: libraryStore)
    }

    func scheduleDeferredStartupWorkIfNeeded() {
        guard !hasScheduledDeferredStartupWork else { return }
        hasScheduledDeferredStartupWork = true
        deferredStartupWorkTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, !Task.isCancelled else { return }
            self.runDeferredStartupWork()
        }
    }

    private func handleAppDidBecomeActive() {
        guard hasCompletedDeferredStartupWork else {
            scheduleDeferredStartupWorkIfNeeded()
            return
        }
        refreshPlaybackCDNProbeOnAppActivationIfNeeded()
    }

    private func runDeferredStartupWork() {
        hasCompletedDeferredStartupWork = true
        refreshPlaybackCDNProbeOnAppActivationIfNeeded()
        PlaybackEngineWarmupCenter.warmKSPlayerComponentsIfNeeded()

        let api = api
        Task(priority: .utility) {
            await RemoteImageCache.shared.applyAdaptiveBudget()
            await ResourceCacheCenter.enforceConfiguredLimit()
            async let startupResources: Void = api.prewarmStartupResources()
            async let dynamicFeed: Void = DynamicFeedWarmCache.shared.prewarm(api: api)
            _ = await (startupResources, dynamicFeed)
        }
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

    private static func applyPictureInPicturePreference(_ isEnabled: Bool) {
        KSOptions.canStartPictureInPictureAutomaticallyFromInline = isEnabled
    }
}
