import Foundation

extension BiliAPIClient {
    func submitRecommendationFeedback(
        metadata: HomeRecommendationFeedbackMetadata,
        kind: RecommendationFeedbackKind,
        reason: RecommendationFeedbackReason,
        cancel: Bool = false
    ) async throws {
        guard metadata.targetID > 0, !metadata.goto.isEmpty,
              let reasonID = reason.id, metadata.reasons(for: kind).contains(reason)
        else { throw BiliAPIError.missingPayload }
        // Recommendation feedback uses the recommendation account, not the separately
        // configurable video-interaction account. Guest recommendations stay anonymous.
        let context = await homeRecommendRequestContext()
        guard !context.guestModeEnabled, let accessKey = context.appAccessKey, !accessKey.isEmpty else {
            throw BiliAPIError.api(code: -101, message: "推荐反馈需要 APP 登录凭据，请重新登录或选择仅本机屏蔽")
        }
        let response: BiliResponse<EmptyBiliPayload> = try await get(
            base: appURL,
            path: cancel ? "/x/feed/dislike/cancel" : "/x/feed/dislike",
            query: BiliAppSigner.sign([
                "goto": metadata.goto,
                "id": String(metadata.targetID),
                kind.requestKey: String(reasonID),
                "access_key": accessKey,
                "build": "1",
                "mobi_app": "android",
            ], profile: .androidHD),
            userAgent: BiliAppSigner.Profile.androidHD.userAgent,
            cookieHeader: context.cookieHeader,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
    }
}
