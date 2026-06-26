import Foundation

extension VideoDetailViewModel {
    func waitForSupplementalPlayURLStart(
        cid: Int,
        waitsForFirstFrame: Bool,
        startDelay: TimeInterval
    ) async -> Bool {
        if waitsForFirstFrame {
            let didPresentPlayback = await waitForFirstFrameOrFailure()
            guard !Task.isCancelled, !isPlaybackInvalidatedForNavigation, selectedCID == cid else { return false }
            guard didPresentPlayback else { return false }
        }
        if startDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(startDelay * 1_000_000_000))
            guard !Task.isCancelled, !isPlaybackInvalidatedForNavigation, selectedCID == cid else { return false }
        }
        return true
    }

    func fetchSupplementalPlayURLData(
        bvid: String,
        cid: Int,
        page: Int?,
        preferredQuality: Int?
    ) async throws -> PlayURLData {
        try await api.fetchPlayURL(
            bvid: bvid,
            cid: cid,
            page: page,
            preferredQuality: preferredQuality,
            supplementsQualities: true
        )
    }

    func storeSupplementalPlayURLData(_ data: PlayURLData, bvid: String, cid: Int, page: Int?) async {
        await VideoPreloadCenter.shared.store(
            data,
            bvid: bvid,
            cid: cid,
            page: page,
            preferredQuality: targetPlaybackPreferredQuality,
            targetPreferredQuality: targetPlaybackPreferredQuality,
            cdnPreference: libraryStore.effectivePlaybackCDNPreference,
            warmsMedia: false,
            mediaWarmupDelay: 0
        )
    }
}
