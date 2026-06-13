import Foundation

actor DynamicFeedWarmCache {
    static let shared = DynamicFeedWarmCache()

    private let freshnessInterval: TimeInterval = 90
    private var cachedPage: DynamicFeedData?
    private var cachedAt: Date?
    private var warmTask: Task<DynamicFeedData, Error>?

    func page(api: BiliAPIClient) async throws -> DynamicFeedData {
        if let cachedPage = freshCachedPage() {
            return cachedPage
        }
        if let warmTask {
            return try await warmTask.value
        }

        let task = Task(priority: .utility) {
            try await api.fetchDynamicFeed()
        }
        warmTask = task
        do {
            let page = try await task.value
            store(page)
            warmTask = nil
            return page
        } catch {
            warmTask = nil
            throw error
        }
    }

    func prewarm(api: BiliAPIClient) async {
        guard freshCachedPage() == nil else { return }
        _ = try? await page(api: api)
    }

    func store(_ page: DynamicFeedData) {
        cachedPage = page
        cachedAt = Date()
    }

    func clear() {
        warmTask?.cancel()
        warmTask = nil
        cachedPage = nil
        cachedAt = nil
    }

    private func freshCachedPage() -> DynamicFeedData? {
        guard let cachedPage,
              let cachedAt,
              Date().timeIntervalSince(cachedAt) < freshnessInterval
        else { return nil }
        return cachedPage
    }
}
