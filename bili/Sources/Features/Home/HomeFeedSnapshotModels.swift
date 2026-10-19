import Foundation

nonisolated struct HomeFeedSnapshot: Codable, Sendable {
    let savedAt: Date
    let lastSeenMarkerIndex: Int?
    let videos: [HomeFeedCachedVideo]
}

nonisolated struct HomeFeedSnapshotRestore: Sendable {
    let videos: [VideoItem]
    let lastSeenMarkerIndex: Int?
}

nonisolated struct HomeFeedCachedVideo: Codable, Sendable {
    let bvid: String
    let aid: Int?
    let title: String
    let pic: String?
    let desc: String?
    let duration: Int?
    let pubdate: Int?
    let owner: HomeFeedCachedOwner?
    let stat: HomeFeedCachedStat?
    let cid: Int?
    let recommendReason: String?
    let recommendationFeedback: HomeRecommendationFeedbackMetadata?
}

nonisolated struct HomeFeedCachedOwner: Codable, Sendable {
    let mid: Int
    let name: String
    let face: String?
}

nonisolated struct HomeFeedCachedStat: Codable, Sendable {
    let view: Int?
    let reply: Int?
    let like: Int?
    let coin: Int?
    let favorite: Int?
}
