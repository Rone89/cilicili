import Foundation

actor LiveFeedWarmCache {
    static let shared = LiveFeedWarmCache()

    private let freshnessInterval: TimeInterval = 90
    private var cachedRooms = [LiveRoom]()
    private var cachedAt: Date?

    func rooms() -> [LiveRoom]? {
        guard let cachedAt,
              Date().timeIntervalSince(cachedAt) < freshnessInterval,
              !cachedRooms.isEmpty
        else { return nil }
        return cachedRooms
    }

    func store(_ rooms: [LiveRoom]) {
        cachedRooms = rooms
        cachedAt = Date()
    }
}
