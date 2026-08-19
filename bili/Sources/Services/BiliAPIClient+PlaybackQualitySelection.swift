extension BiliAPIClient {
    nonisolated static func requiresAutomaticCodecNegotiation(requestedQuality: Int) -> Bool {
        switch requestedQuality {
        case 125, 126, 129:
            return true
        default:
            return false
        }
    }

    nonisolated static func shouldContinueCodecFallback(
        for data: PlayURLData,
        requestedQuality: Int,
        requestedCodecFamily: VideoCodecFamily? = nil,
        allowsUnavailableQualityFallback: Bool = false
    ) -> Bool {
        if data.hasPlayableMediaQuality(requestedQuality) {
            guard let requestedCodecFamily else { return false }
            return !hasPlayableDASHMedia(
                in: data,
                quality: requestedQuality,
                codecFamily: requestedCodecFamily
            )
        }
        guard allowsUnavailableQualityFallback,
            let requestedCodecFamily,
            data.hasExplicitlyUnavailableQuality(requestedQuality),
            let fallbackQuality = BiliVideoQuality.supportedQualities.first(where: {
                $0 < requestedQuality && data.advertisedQualities.contains($0)
            })
        else { return true }
        return !hasPlayableDASHMedia(
            in: data,
            quality: fallbackQuality,
            codecFamily: requestedCodecFamily
        )
    }

    nonisolated static func startupCandidateQuality(
        in data: PlayURLData,
        requestedQuality: Int
    ) -> Int? {
        data.playVariants
            .filter { variant in
                guard variant.isPlayable, variant.quality <= requestedQuality else {
                    return false
                }
                return variant.quality < requestedQuality
                    || variant.satisfiesPreferredQuality(requestedQuality)
            }
            .map(\.quality)
            .max()
    }

    nonisolated static func nextLowerVideoQuality(after quality: Int) -> Int? {
        BiliVideoQuality.supportedQualities.first { $0 < quality }
    }
}
