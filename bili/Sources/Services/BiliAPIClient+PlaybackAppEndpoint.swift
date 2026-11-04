import Foundation
import QuartzCore

extension BiliAPIClient {
    /// WBI / Webpage 全部路由失败后的最终兜底：app 端播放地址接口。
    ///
    /// B 站对 Web 播放地址请求存在间歇性风控：返回 code=0 但 dash/durl/accept_quality
    /// 全空的载荷（设备诊断中表现为 baseResponse=dashV0:dashA0:durl0 的成批失败）。
    /// app 端接口走 access_key + appsec 签名，与 Web 风控体系独立，可作为最后恢复路径。
    /// 仅扫码登录（持有 access_key）的会话可用；无 access_key 时跳过，不改变既有失败行为。
    func appEndpointPlayURLRescue(
        bvid: String,
        cid: Int,
        requestedQuality: Int,
        raceStart: CFTimeInterval,
        lastError: Error?
    ) async -> StartupPlayURLRaceResult? {
        let start = CACurrentMediaTime()
        let context = await playbackAPIRequestContext()
        guard let accessKey = context.appAccessKey, !accessKey.isEmpty else {
            await recordStartupSchedulerMessage(
                "startupAppEndpointRescue skipped reason=noAccessKey bvid=\(bvid)",
                bvid: bvid
            )
            return nil
        }
        do {
            let data = try await fetchAppEndpointPlayURL(
                bvid: bvid,
                cid: cid,
                requestedQuality: requestedQuality,
                accessKey: accessKey
            )
            guard hasAnyPlayableAppPayload(data) else {
                throw BiliAPIError.emptyPlayURL
            }
            await recordStartupSchedulerMessage(
                Self.appEndpointRescueMessage(
                    result: "success",
                    bvid: bvid,
                    requestedQuality: requestedQuality,
                    elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: start),
                    lastError: lastError,
                    data: data
                ),
                bvid: bvid
            )
            logPlayURLStage(
                "startupAppEndpointRescue",
                bvid: bvid,
                cid: cid,
                start: raceStart,
                data: data
            )
            return StartupPlayURLRaceResult(
                data: data,
                isVerifiedUnavailablePreferredFallback: false
            )
        } catch {
            await recordStartupSchedulerMessage(
                Self.appEndpointRescueMessage(
                    result: "failure",
                    bvid: bvid,
                    requestedQuality: requestedQuality,
                    elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: start),
                    lastError: error,
                    data: nil
                ),
                bvid: bvid
            )
            return nil
        }
    }

    func fetchAppEndpointPlayURL(
        bvid: String,
        cid: Int,
        requestedQuality: Int,
        accessKey: String
    ) async throws -> PlayURLData {
        let query = BiliAppSigner.sign(
            [
                "access_key": accessKey,
                "bvid": bvid,
                "cid": String(cid),
                "fnval": "4048",
                "fnver": "0",
                "fourk": "1",
                "qn": String(requestedQuality),
            ],
            profile: .androidLogin
        )
        let response: BiliResponse<PlayURLData> = try await get(
            base: appURL,
            path: "/x/v2/playurl",
            query: query,
            userAgent: BiliAppSigner.Profile.androidLogin.userAgent
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        guard let data = response.payload else {
            throw BiliAPIError.emptyPlayURL
        }
        return data
    }

    private func hasAnyPlayableAppPayload(_ data: PlayURLData) -> Bool {
        if data.dash?.video?.contains(where: { $0.playURL(cdnPreference: .automatic) != nil }) == true {
            return data.dash?.bestAudioStream?.playURL(cdnPreference: .automatic) != nil
        }
        return !(data.durl ?? []).isEmpty
    }

    private nonisolated static func appEndpointRescueMessage(
        result: String,
        bvid: String,
        requestedQuality: Int,
        elapsedMilliseconds: Double?,
        lastError: Error?,
        data: PlayURLData?
    ) -> String {
        var parts = [
            "startupAppEndpointRescue",
            "result=\(result)",
            "target=\(requestedQuality)",
        ]
        if let elapsedMilliseconds {
            parts.append("elapsed=\(Int(elapsedMilliseconds.rounded()))ms")
        }
        if let data {
            parts.append("qualities=\(data.advertisedQualities.sorted().map(String.init).joined(separator: ","))")
        }
        if let lastError {
            parts.append("priorError=\(String(describing: lastError).prefix(160))")
        }
        return parts.joined(separator: " ")
    }
}
