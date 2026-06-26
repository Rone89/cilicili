import Foundation

extension VideoDetailViewModel {
    func playerIdentity(for variant: PlayVariant) -> String {
        "\(selectedCID ?? 0)-\(variant.id)"
    }

    var selectedPageNumber: Int? {
        guard let selectedCID else { return nil }
        guard let page = detail.pages?.first(where: { $0.cid == selectedCID })?.page,
              page > 1
        else { return nil }
        return page
    }

    var selectedPage: VideoPage? {
        guard let selectedCID else { return detail.pages?.first }
        return detail.pages?.first(where: { $0.cid == selectedCID }) ?? detail.pages?.first
    }

    var playbackAdaptationProfile: PlayerPlaybackAdaptationProfile {
        PlayerPerformanceStore.shared.playbackAdaptationProfile(
            for: detail.bvid,
            isEnabled: libraryStore.isPlaybackAutoOptimizationEnabled
        )
    }

    var targetPlaybackPreferredQuality: Int? {
        libraryStore.preferredVideoQuality ?? LibraryStore.defaultPreferredVideoQuality
    }

    var adaptiveStartupPreferredQuality: Int? {
        targetPlaybackPreferredQuality
    }

    var adaptiveStartupQualityCeiling: Int? {
        nil
    }
}
