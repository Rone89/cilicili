import Foundation

extension VideoDetailViewModel {
    func startupPlayURLForDefaultQuality(
        bvid: String,
        cid: Int,
        page: Int?
    ) async throws -> PlayURLData {
        let startupData: PlayURLData
        do {
            startupData = try await fetchPlayURLWithTimeout(
                timeout: playURLLoadTimeoutNanoseconds
            ) { [self] in
                try await startupPlayURL(bvid: bvid, cid: cid, page: page)
            }
        } catch {
            if let timeoutError = error as? VideoDetailLoadTimeoutError,
               case .playURL = timeoutError {
                cancelStartupPlayURLTask()
            }
            throw error
        }
        return startupData
    }

    func fetchStartupPlayURL(
        bvid: String,
        cid: Int,
        page: Int?,
        requestLease: StartupPlayURLRequestLease? = nil
    ) async throws -> PlayURLData {
        if detail.isPGCEpisode {
            do {
                return try await api.fetchPgcPlayURL(
                    bvid: bvid,
                    cid: cid,
                    seasonID: detail.pgcSeasonID,
                    epID: detail.pgcEpisodeID,
                    preferredQuality: adaptiveStartupPreferredQuality
                )
            } catch {
                // PGC 播放信息对部分剧集返回 -404，同 bvid/cid 的 UGC 启动路径可用。
                guard !Task.isCancelled else { throw error }
                return try await api.fetchStartupPlayURL(
                    bvid: bvid,
                    cid: cid,
                    page: page,
                    preferredQuality: adaptiveStartupPreferredQuality,
                    requestLease: requestLease,
                    requestSource: .foreground
                )
            }
        }
        return try await api.fetchStartupPlayURL(
            bvid: bvid,
            cid: cid,
            page: page,
            preferredQuality: adaptiveStartupPreferredQuality,
            requestLease: requestLease,
            requestSource: .foreground
        )
    }

}
