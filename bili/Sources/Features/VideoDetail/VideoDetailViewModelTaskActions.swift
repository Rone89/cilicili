import Foundation

extension VideoDetailViewModel {
    func trackBackgroundTask(_ task: Task<Void, Never>) {
        let id = UUID()
        backgroundTasks[id] = task
        Task(priority: .utility) { [weak self, task] in
            _ = await task.value
            await MainActor.run {
                guard let self,
                      self.backgroundTasks[id] != nil
                else { return }
                self.backgroundTasks[id] = nil
            }
        }
    }

    func clearDetailLoadingTaskIfCurrent(_ token: UUID) {
        guard detailLoadingToken == token else { return }
        detailLoadingTask = nil
        detailLoadingToken = nil
    }

    func clearPageLoadingTaskIfCurrent(_ token: UUID) {
        guard pageLoadingToken == token else { return }
        pageLoadingTask = nil
        pageLoadingToken = nil
    }

    func clearCommentsLoadingTaskIfCurrent(_ token: UUID) {
        guard commentsLoadingToken == token else { return }
        commentsLoadingTask = nil
        commentsLoadingToken = nil
    }

    @discardableResult
    func advanceCommentPageLoadGeneration() -> Int {
        commentPageLoadGeneration += 1
        return commentPageLoadGeneration
    }

    func isCurrentCommentPageLoad(
        aid: Int,
        bvid: String,
        sort: CommentSort,
        generation: Int
    ) -> Bool {
        commentPageLoadGeneration == generation
            && selectedCommentSort == sort
            && isCurrentVideoContext(aid: aid, bvid: bvid)
    }

    func clearDanmakuStartupLoadTaskIfCurrent(_ token: UUID) {
        guard danmakuStartupLoadToken == token else { return }
        danmakuStartupLoadTask = nil
        danmakuStartupLoadToken = nil
    }

    func cancelPlayURLSupplementTask(advancesGeneration: Bool = true) {
        playURLSupplementTask?.cancel()
        playURLSupplementTask = nil
        if advancesGeneration {
            advancePlayURLSupplementGeneration()
        }
    }

    @discardableResult
    func advancePlayURLSupplementGeneration() -> Int {
        playURLSupplementGeneration += 1
        return playURLSupplementGeneration
    }

    func clearPlayURLSupplementTaskIfCurrent(generation: Int) {
        guard playURLSupplementGeneration == generation else { return }
        playURLSupplementTask = nil
    }

    @discardableResult
    func advanceStartupPlayURLGeneration() -> Int {
        startupPlayURLGeneration += 1
        return startupPlayURLGeneration
    }

    func clearStartupPlayURLTaskIfCurrent(key: String, generation: Int) {
        guard startupPlayURLTaskKey == key,
              startupPlayURLGeneration == generation
        else { return }
        startupPlayURLTask = nil
        startupPlayURLTaskKey = nil
    }

    func cancelBackgroundTasks() {
        backgroundTasks.values.forEach { $0.cancel() }
        backgroundTasks.removeAll()
    }
}
