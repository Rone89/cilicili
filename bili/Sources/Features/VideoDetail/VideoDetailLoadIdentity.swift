import Foundation

enum VideoDetailLoadIdentity: Equatable {
    case bvid(String)
    case aid(Int)
    case pgcEpisode(episodeID: Int, seasonID: Int?)

    var metricsMessage: String {
        switch self {
        case .bvid(let bvid):
            return "bvid=\(bvid)"
        case .aid(let aid):
            return "aid=\(aid)"
        case .pgcEpisode(let episodeID, let seasonID):
            return "ep_id=\(episodeID),season_id=\(seasonID ?? 0)"
        }
    }
}
