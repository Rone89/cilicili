import Combine
import Foundation
import UIKit

struct PlayerPlaybackProgressContext {
    let dependencies: AppDependencies
    let libraryStore: LibraryStore
    let historyVideo: VideoItem?
    let historyCID: Int?
    let historyDuration: TimeInterval?
    let durationHint: TimeInterval?
    let playerDuration: TimeInterval?
}

@MainActor
final class PlayerPlaybackProgressCoordinator: ObservableObject {
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var progressSaveTask: Task<Void, Never>?
    private var backgroundTaskEndTask: Task<Void, Never>?
    private var backgroundTaskGeneration = 0

    func saveProgress(
        _ time: TimeInterval,
        context: PlayerPlaybackProgressContext
    ) {
        guard !context.libraryStore.incognitoModeEnabled else { return }
        guard time.isFinite, time >= 5 else { return }
        guard let aid = context.historyVideo?.aid else { return }
        progressSaveTask?.cancel()
        progressSaveTask = Task {
            try? await context.dependencies.api.reportVideoHistory(
                aid: aid,
                cid: context.historyCID ?? context.historyVideo?.cid,
                progress: time,
                duration: context.historyDuration ?? context.durationHint ?? context.playerDuration
            )
        }
    }

    func saveProgressInBackground(
        currentTime: TimeInterval,
        context: PlayerPlaybackProgressContext
    ) {
        endBackgroundTaskIfNeeded()
        backgroundTaskGeneration += 1
        let generation = backgroundTaskGeneration
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "cc.bili.player.progress") {
            Task { @MainActor [weak self] in
                self?.endBackgroundTaskIfNeeded()
            }
        }
        saveProgress(currentTime, context: context)
        backgroundTaskEndTask?.cancel()
        backgroundTaskEndTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self,
                  !Task.isCancelled,
                  self.backgroundTaskGeneration == generation
            else { return }
            self.endBackgroundTaskIfNeeded()
        }
    }

    func endBackgroundTaskIfNeeded() {
        backgroundTaskEndTask?.cancel()
        backgroundTaskEndTask = nil
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    deinit {
        progressSaveTask?.cancel()
        backgroundTaskEndTask?.cancel()
        if backgroundTaskID != .invalid {
            let backgroundTaskID = backgroundTaskID
            Task { @MainActor in
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
            }
        }
    }
}
