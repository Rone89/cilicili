import Foundation

extension BiliAPIClient {
    struct TargetQualityUnavailableError: LocalizedError, Sendable {
        let requestedQuality: Int
        let fallbackQuality: Int?
        let fallbackData: PlayURLData?

        init(
            requestedQuality: Int,
            fallbackQuality: Int?,
            fallbackData: PlayURLData? = nil
        ) {
            self.requestedQuality = requestedQuality
            self.fallbackQuality = fallbackQuality
            self.fallbackData = fallbackData
        }

        var playableFallbackData: PlayURLData? {
            guard let fallbackData,
                BiliAPIClient.canUseUnavailablePreferredStartupFallback(
                    fallbackData,
                    requestedQuality: requestedQuality,
                    isAuthoritativeSource: true
                )
            else { return nil }
            return fallbackData
        }

        var errorDescription: String? {
            "目标清晰度 \(requestedQuality) 明确不可用"
        }
    }
}
