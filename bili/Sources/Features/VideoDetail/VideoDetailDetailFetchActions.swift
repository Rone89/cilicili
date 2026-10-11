import Foundation

extension VideoDetailViewModel {
    var detailLoadIdentity: VideoDetailLoadIdentity {
        if detail.isPGCEpisode,
           detail.cid == nil,
           let episodeID = detail.pgcEpisodeID,
           episodeID > 0 {
            return .pgcEpisode(episodeID: episodeID, seasonID: detail.pgcSeasonID)
        }
        if detail.bvid.hasPrefix("av"),
           let aid = detail.aid,
           aid > 0 {
            return .aid(aid)
        }
        if !detail.bvid.isEmpty {
            return .bvid(detail.bvid)
        }
        if let aid = detail.aid, aid > 0 {
            return .aid(aid)
        }
        return .bvid(detail.bvid)
    }

    func fetchFullDetail(identity: VideoDetailLoadIdentity, priority: TaskPriority) async throws -> VideoItem {
        switch identity {
        case .bvid(let bvid):
            if !playbackOptions.usesStartupCaches {
                return try await api.fetchVideoDetail(bvid: bvid, bypassesCache: true)
            }
            return try await VideoPreloadCenter.shared.detail(
                for: bvid,
                api: api,
                priority: priority
            )
        case .aid(let aid):
            return try await api.fetchVideoDetail(aid: aid)
        case .pgcEpisode(let episodeID, let seasonID):
            var season = try await api.fetchPgcSeasonInfo(seasonID: seasonID, epID: episodeID)
            try Task.checkCancellation()
            if let seasonID {
                season = season.withFallbackSeasonID(seasonID)
            }
            let route = PgcSeasonRoute(episodeID: episodeID, seasonID: seasonID, title: detail.title, cover: detail.pic)
            guard let video = route.playbackEpisode(in: season)?.videoItem(in: season) else {
                throw PgcEpisodePlaybackError.unavailable
            }
            return video
        }
    }

    func isCurrentDetailLoadIdentity(_ identity: VideoDetailLoadIdentity) -> Bool {
        detailLoadIdentity == identity
    }
}
