import Foundation

nonisolated struct DynamicFeedQuery: Hashable {
    let kind: DynamicFeedKind
    let hostMID: Int?

    init(kind: DynamicFeedKind, hostMID: Int? = nil) {
        self.kind = kind
        self.hostMID = kind == .up ? hostMID : nil
    }
}

nonisolated struct DynamicFollowingPage: Decodable {
    let list: [DynamicPortalUpItem]
    let total: Int

    enum CodingKeys: CodingKey { case list, total }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        list = try container.decodeIfPresent([DynamicPortalUpItem].self, forKey: .list) ?? []
        total = container.decodeLossyIntIfPresent(forKey: .total) ?? 0
    }
}
