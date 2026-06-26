import Combine
import Foundation

@MainActor
final class VideoDetailPlaybackLoadHostState: ObservableObject {
    @Published private(set) var deliveredPlayerIdentityChangeGeneration = 0
    private var playerIdentityChangeTask: Task<Void, Never>?
    private var playerIdentityChangeGeneration = 0

    func schedulePlayerIdentityChanged() {
        cancelPlayerIdentityChangeTask(advancesGeneration: false)
        let generation = advancePlayerIdentityChangeGeneration()
        playerIdentityChangeTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                  !Task.isCancelled,
                  self.playerIdentityChangeGeneration == generation
            else { return }
            self.deliveredPlayerIdentityChangeGeneration = generation
            self.clearPlayerIdentityChangeTaskIfCurrent(generation: generation)
        }
    }

    func cancelPendingWork() {
        cancelPlayerIdentityChangeTask()
    }

    @discardableResult
    private func advancePlayerIdentityChangeGeneration() -> Int {
        playerIdentityChangeGeneration += 1
        return playerIdentityChangeGeneration
    }

    private func cancelPlayerIdentityChangeTask(advancesGeneration: Bool = true) {
        playerIdentityChangeTask?.cancel()
        playerIdentityChangeTask = nil
        if advancesGeneration {
            advancePlayerIdentityChangeGeneration()
        }
    }

    private func clearPlayerIdentityChangeTaskIfCurrent(generation: Int) {
        guard playerIdentityChangeGeneration == generation else { return }
        playerIdentityChangeTask = nil
    }

    deinit {
        playerIdentityChangeTask?.cancel()
    }
}
