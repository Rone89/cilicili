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
        return (selectedVariant, targetVariant)
    }

    func codecUnavailableMessage() -> String {
        libraryStore.videoCodecPreference.forcedUnavailableMessage
            ?? "当前视频没有可硬解的播放地址，可稍后重试或调整播放设置。"
    }

    func clearSupplementalPlayURLState() {
        cancelPlayURLSupplementTask()
        isSupplementingPlayQualities = false
    }
}
