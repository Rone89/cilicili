import Foundation

@MainActor
final class PlaybackPosterSnapshotRefreshScheduler {
    private var task: Task<Void, Never>?
    private var generation = 0

    func schedule(action: @escaping @MainActor () -> Void) {
        guard task == nil else { return }
        let generation = advanceGeneration()
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard let self,
                  !Task.isCancelled,
                  self.generation == generation
            else { return }
            self.task = nil
            action()
        }
    }

    func cancel() {
        cancelPendingTask()
    }

    @discardableResult
    private func advanceGeneration() -> Int {
        generation += 1
        return generation
    }

    private func cancelPendingTask() {
        task?.cancel()
        task = nil
        advanceGeneration()
    }

    deinit {
        task?.cancel()
    }
}
