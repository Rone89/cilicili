import Foundation

extension VideoDetailViewModel {
    func cancelStartupPlayURLTask() {
        startupPlayURLTask?.cancel()
        startupPlayURLTask = nil
        startupPlayURLTaskKey = nil
        advanceStartupPlayURLGeneration()
    }

    func startupPlayURL(
        bvid: String,
        cid: Int,
        page: Int?
    ) async throws -> PlayURLData {
        let adaptiveQuality = adaptiveStartupPreferredQuality
        let adaptiveCeiling = adaptiveStartupQualityCeiling
        let streamSource = libraryStore.playbackStreamSourcePreference
        let key = [
            bvid,
            String(cid),
            page.map(String.init) ?? "-",
            "q\(adaptiveQuality ?? 0)",
            "ceiling\(adaptiveCeiling ?? 0)",
            streamSource.cachePlatform
        ].joined(separator: "|")
        if startupPlayURLTaskKey == key, let startupPlayURLTask {
            let data = try await startupPlayURLTask.value
            guard isCurrentPlaybackContext(bvid: bvid, cid: cid, page: page)
            else { throw CancellationError() }
            return data
        }

        startupPlayURLTask?.cancel()
        let startupGeneration = advanceStartupPlayURLGeneration()
        let task = Task(priority: .userInitiated) { [weak self] in
            guard let self else { throw CancellationError() }
            guard self.isCurrentPlaybackContext(bvid: bvid, cid: cid, page: page),
                  self.startupPlayURLGeneration == startupGeneration
            else { throw CancellationError() }
            return try await self.fetchStartupPlayURL(bvid: bvid, cid: cid, page: page)
        }
        startupPlayURLTask = task
        startupPlayURLTaskKey = key
        defer {
            clearStartupPlayURLTaskIfCurrent(key: key, generation: startupGeneration)
        }

        let data = try await task.value
        guard isCurrentPlaybackContext(bvid: bvid, cid: cid, page: page)
        else { throw CancellationError() }
        return data
    }
}
