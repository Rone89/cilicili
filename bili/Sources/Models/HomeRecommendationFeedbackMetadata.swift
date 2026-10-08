import Foundation

nonisolated enum RecommendationFeedbackKind: String, Codable, Sendable {
    case dislike
    case feedback

    var requestKey: String { self == .dislike ? "reason_id" : "feedback_id" }
}

nonisolated struct RecommendationFeedbackReason: Codable, Hashable, Sendable, Identifiable {
    let id: Int?
    let name: String?
    let toast: String?

    var isValid: Bool { id != nil && name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }

    enum CodingKeys: String, CodingKey { case id, name, toast }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = values.decodeLossyIntIfPresent(forKey: .id)
        name = try values.decodeIfPresent(String.self, forKey: .name)
        toast = try values.decodeIfPresent(String.self, forKey: .toast)
    }
}

nonisolated struct RecommendationThreePoint: Codable, Hashable, Sendable {
    let type: String?
    let reasons: [RecommendationFeedbackReason]?
}

nonisolated struct HomeRecommendationFeedbackMetadata: Codable, Hashable, Sendable {
    let goto: String
    let targetID: Int
    let threePointV2: [RecommendationThreePoint]

    func reasons(for kind: RecommendationFeedbackKind) -> [RecommendationFeedbackReason] {
        var seen = Set<Int>()
        return threePointV2.filter { $0.type == kind.rawValue }
            .flatMap { $0.reasons ?? [] }
            .filter { $0.isValid && seen.insert($0.id!).inserted }
    }

    var hasReasons: Bool {
        !reasons(for: .dislike).isEmpty || !reasons(for: .feedback).isEmpty
    }
}

nonisolated enum HomeRecommendationFeedbackPolicy {
    static func isAvailable(experimentEnabled: Bool, mode: HomeFeedMode) -> Bool {
        experimentEnabled && mode == .recommend
    }

    static func filtered(_ videos: [VideoItem], blockedMIDs: Set<Int64>, enabled: Bool) -> [VideoItem] {
        guard enabled, !blockedMIDs.isEmpty else { return videos }
        return videos.filter { video in
            guard let mid = video.owner?.mid else { return true }
            return !blockedMIDs.contains(Int64(mid))
        }
    }
}
