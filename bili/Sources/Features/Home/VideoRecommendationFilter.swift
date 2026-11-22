import Foundation

nonisolated enum VideoRecommendationFilterContext: Sendable {
    case feed
    case related
}

nonisolated struct VideoRecommendationFilterConfiguration: Equatable, Sendable {
    let minimumDurationSeconds: Int
    let minimumViewCount: Int
    let minimumLikeRatioPercent: Int
    let blockedKeywords: [String]
    let appliesToRelatedVideos: Bool
    let blocksChargingVideos: Bool

    init(
        minimumDurationSeconds: Int,
        minimumViewCount: Int,
        minimumLikeRatioPercent: Int,
        blockedKeywords: [String],
        appliesToRelatedVideos: Bool,
        blocksChargingVideos: Bool = false
    ) {
        self.minimumDurationSeconds = minimumDurationSeconds
        self.minimumViewCount = minimumViewCount
        self.minimumLikeRatioPercent = minimumLikeRatioPercent
        self.blockedKeywords = blockedKeywords
        self.appliesToRelatedVideos = appliesToRelatedVideos
        self.blocksChargingVideos = blocksChargingVideos
    }

    var isRecommendRuleActive: Bool {
        minimumDurationSeconds > 0
            || minimumViewCount > 0
            || minimumLikeRatioPercent > 0
            || !blockedKeywords.isEmpty
    }

    var isActive: Bool {
        isRecommendRuleActive || blocksChargingVideos
    }
}

nonisolated enum VideoRecommendationFilter {
    static func filtered(
        _ videos: [VideoItem],
        configuration: VideoRecommendationFilterConfiguration,
        context: VideoRecommendationFilterContext
    ) -> [VideoItem] {
        guard configuration.isActive else { return videos }
        let appliesRecommendRules = configuration.isRecommendRuleActive
            && (context == .feed || configuration.appliesToRelatedVideos)
        guard appliesRecommendRules || configuration.blocksChargingVideos else { return videos }
        return videos.filter { video in
            if configuration.blocksChargingVideos, video.isChargingExclusive {
                return false
            }
            if appliesRecommendRules {
                return includes(video, configuration: configuration)
            }
            return true
        }
    }

    static func includes(
        _ video: VideoItem,
        configuration: VideoRecommendationFilterConfiguration
    ) -> Bool {
        if configuration.blocksChargingVideos, video.isChargingExclusive {
            return false
        }
        if configuration.minimumDurationSeconds > 0,
           let duration = video.duration,
           duration > 0,
           duration < configuration.minimumDurationSeconds {
            return false
        }

        if configuration.minimumViewCount > 0,
           let view = video.stat?.view,
           view >= 0,
           view < configuration.minimumViewCount {
            return false
        }

        if configuration.minimumLikeRatioPercent > 0,
           let like = video.stat?.like,
           let view = video.stat?.view,
           like >= 0,
           view > 0,
           like * 100 < configuration.minimumLikeRatioPercent * view {
            return false
        }

        if !configuration.blockedKeywords.isEmpty {
            let title = normalizedKeywordText(video.title)
            if configuration.blockedKeywords.contains(where: { keyword in
                title.contains(normalizedKeywordText(keyword))
            }) {
                return false
            }
        }

        return true
    }

    private static func normalizedKeywordText(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
    }
}

@MainActor
extension LibraryStore {
    var videoRecommendationFilterConfiguration: VideoRecommendationFilterConfiguration {
        VideoRecommendationFilterConfiguration(
            minimumDurationSeconds: recommendMinimumDurationSeconds,
            minimumViewCount: recommendMinimumViewCount,
            minimumLikeRatioPercent: recommendMinimumLikeRatioPercent,
            blockedKeywords: blockedRecommendKeywords,
            appliesToRelatedVideos: appliesRecommendFiltersToRelatedVideos,
            blocksChargingVideos: blocksChargingVideos
        )
    }
}
