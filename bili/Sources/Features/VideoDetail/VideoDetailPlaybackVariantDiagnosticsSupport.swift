import Foundation
import OSLog

extension VideoDetailViewModel {
    func shouldRefetchForPreferredQuality(_ data: PlayURLData) -> Bool {
        guard let preferredQuality = targetPlaybackPreferredQuality else { return false }
        if [116, 74].contains(preferredQuality) {
            let variants = data.playVariants(cdnPreference: libraryStore.effectivePlaybackCDNPreference)
            if variants.contains(where: {
                $0.isPlayable
                    && $0.quality == preferredQuality
                    && variantFrameRate($0) >= 50
            }) {
                return false
            }
            let advertisesPreferredQuality = data.acceptQuality?.contains(preferredQuality) == true
                || data.supportFormats?.contains(where: { $0.quality == preferredQuality }) == true
                || data.dash?.video?.contains(where: { $0.id == preferredQuality }) == true
                || data.quality == preferredQuality
            if advertisesPreferredQuality {
                return true
            }
        }
        return data.shouldRefetchForPreferredQuality(preferredQuality)
    }

    func shouldRefetchForStartupQuality(_ data: PlayURLData) -> Bool {
        !data.playVariants(cdnPreference: libraryStore.effectivePlaybackCDNPreference)
            .contains(where: \.isPlayable)
    }

    func logSelectedPlayVariant(
        _ variant: PlayVariant?,
        availableVariants: [PlayVariant],
        source: String
    ) {
        let environment = PlaybackEnvironment.current
        let selectedFPS = variant.flatMap { DASHStream.displayFrameRate(from: $0.frameRate) } ?? "-"
        PlayerMetricsLog.logger.info(
            "selectedVariant source=\(source, privacy: .public) bvid=\(self.detail.bvid, privacy: .public) preferred=\(self.libraryStore.preferredVideoQuality ?? 0, privacy: .public) selectedQ=\(variant?.quality ?? 0, privacy: .public) selectedTitle=\(variant?.title ?? "-", privacy: .public) codec=\(variant?.codec ?? "-", privacy: .public) fps=\(selectedFPS, privacy: .public) bandwidth=\(variant?.bandwidth ?? 0, privacy: .public) progressive=\((variant?.isProgressiveFastStart ?? false), privacy: .public) conservative=\(environment.shouldPreferConservativePlayback, privacy: .public) available=\(Self.qualitySummary(availableVariants), privacy: .public)"
        )
    }
}
