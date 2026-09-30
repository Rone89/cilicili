import Foundation

extension VideoDetailViewModel {
    func applyPlayableVariantState(
        variants: [PlayVariant],
        source: String
    ) -> (selectedVariant: PlayVariant?, targetVariant: PlayVariant?)? {
        lastPlayURLSource = source
        playURLElapsedMilliseconds = elapsedMilliseconds(since: playURLLoadStartTime)
        failedPlayVariantIDs.removeAll()

        guard !variants.isEmpty else {
            currentPlayURLData = nil
            clearVideoListenAudioVariants()
            playVariants = []
            selectedPlayVariant = nil
            playURLState = .failed(codecUnavailableMessage())
            return nil
        }

        let selectedVariant = preferredDefaultVariant(in: variants)
        let targetVariant = selectedVariant
        playVariants = variants
        selectedPlayVariant = selectedVariant
        logSelectedPlayVariant(selectedVariant, availableVariants: variants, source: source)
        #if DEBUG
        PlayerMetricsLog.record(
            .startupScheduler,
            metricsID: detail.bvid,
            title: detail.title,
            message: [
                "qualitySelection",
                "source=\(source)",
                "requestedQ=\(adaptiveStartupPreferredQuality ?? 0)",
                "targetQ=\(targetPlaybackPreferredQuality ?? 0)",
                "finalQ=\(selectedVariant?.quality ?? 0)",
                "codec=\(selectedVariant?.codec ?? "-")",
            ].joined(separator: " ")
        )
        #endif
        return (selectedVariant, targetVariant)
    }

    func codecUnavailableMessage() -> String {
        if libraryStore.forceHardwareDecodeEnabled {
            return "当前视频没有可播放的硬解或单流播放地址，可切换编码后重试。"
        }
        return libraryStore.videoCodecPreference.forcedUnavailableMessage
            ?? "当前视频没有可硬解的播放地址，可稍后重试或调整播放设置。"
    }
}
