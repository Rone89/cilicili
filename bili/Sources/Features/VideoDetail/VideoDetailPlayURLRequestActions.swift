import Foundation

extension VideoDetailViewModel {
    func startupPlayURLForDefaultQuality(
        bvid: String,
        cid: Int,
        page: Int?
    ) async throws -> PlayURLData {
        let startupData = try await fetchPlayURLWithTimeout(
            timeout: playURLLoadTimeoutNanoseconds
        ) { [self] in
            try await startupPlayURL(bvid: bvid, cid: cid, page: page)
        }
        return await supplementInitialTargetQualityIfNeeded(
            startupData,
            bvid: bvid,
            cid: cid,
            page: page
        )
    }

    func fetchStartupPlayURL(
        bvid: String,
        cid: Int,
        page: Int?
    ) async throws -> PlayURLData {
        try await api.fetchStartupPlayURL(
            bvid: bvid,
            cid: cid,
            page: page,
            preferredQuality: adaptiveStartupPreferredQuality,
            startupQualityCeiling: adaptiveStartupQualityCeiling
        )
    }

    private func supplementInitialTargetQualityIfNeeded(
        _ data: PlayURLData,
        bvid: String,
        cid: Int,
        page: Int?
    ) async -> PlayURLData {
        guard shouldRefetchForPreferredQuality(data),
              let preferredQuality = targetPlaybackPreferredQuality
        else { return data }

        do {
            let supplemented = try await fetchPlayURLWithTimeout(
                timeout: initialTargetQualitySupplementTimeoutNanoseconds
            ) { [self] in
                try await api.fetchPlayURL(
                    bvid: bvid,
                    cid: cid,
                    page: page,
                    preferredQuality: preferredQuality,
                    supplementsQualities: true,
                    preferProgressiveFastStart: false
                )
            }
            guard isCurrentPlaybackContext(bvid: bvid, cid: cid, page: page) else { return data }
            guard !shouldRefetchForPreferredQuality(supplemented) else { return data }
            PlayerMetricsLog.record(
                .qualitySupplement,
                metricsID: detail.bvid,
                title: detail.title,
                message: "initialTargetSupplement q\(data.highestPlayableQuality)->q\(supplemented.highestPlayableQuality) preferred=\(preferredQuality)"
            )
            return supplemented
        } catch {
            PlayerMetricsLog.record(
                .qualitySupplement,
                metricsID: detail.bvid,
                title: detail.title,
                message: "initialTargetSupplement failed preferred=\(preferredQuality) error=\(error.localizedDescription)"
            )
            return data
        }
    }
}
