import Combine
import Foundation

@MainActor
final class PlaybackPosterOverlayState: ObservableObject {
    @Published private(set) var snapshot: PlaybackPosterSnapshot
    private weak var playerViewModel: PlayerStateViewModel?
    private var cancellables = Set<AnyCancellable>()
    private let snapshotRefreshScheduler = PlaybackPosterSnapshotRefreshScheduler()
    private var posterReleaseTask: Task<Void, Never>?
    private var posterReleaseGeneration = 0
    private var isPosterReleaseReady = false

    init(playerViewModel: PlayerStateViewModel? = nil) {
        snapshot = PlaybackPosterSnapshot(playerViewModel: playerViewModel)
    }

    func bind(playerViewModel: PlayerStateViewModel) {
        guard !playerViewModel.isTerminated else {
            unbind()
            return
        }
        guard self.playerViewModel !== playerViewModel else {
            refreshSnapshot(from: playerViewModel)
            return
        }
        cancellables.removeAll()
        cancelPosterRelease()
        self.playerViewModel = playerViewModel
        isPosterReleaseReady = playerViewModel.isCurrentPlaybackSurfaceReadyForDisplay
        refreshSnapshot(from: playerViewModel)

        PlaybackPosterSnapshotSubscriptionBinder(
            playerViewModel: playerViewModel,
            refresh: scheduleSnapshotRefresh
        ).store(in: &cancellables)
    }

    func unbind() {
        cancellables.removeAll()
        playerViewModel = nil
        snapshotRefreshScheduler.cancel()
        cancelPosterRelease()
    }

    private func refreshSnapshot(from playerViewModel: PlayerStateViewModel) {
        guard !playerViewModel.isTerminated else {
            unbind()
            return
        }
        updatePosterReleaseState(for: playerViewModel)
        var nextSnapshot = PlaybackPosterSnapshot(playerViewModel: playerViewModel)
        nextSnapshot.isPlaybackSurfaceReady = nextSnapshot.isPlaybackSurfaceReady && isPosterReleaseReady
        guard nextSnapshot != snapshot else { return }
        snapshot = nextSnapshot
    }

    private func scheduleSnapshotRefresh() {
        snapshotRefreshScheduler.schedule { [weak self] in
            guard let self,
                  let playerViewModel = self.playerViewModel,
                  !playerViewModel.isTerminated
            else {
                self?.unbind()
                return
            }
            self.refreshSnapshot(from: playerViewModel)
        }
    }

    private func updatePosterReleaseState(for playerViewModel: PlayerStateViewModel) {
        guard playerViewModel.isCurrentPlaybackSurfaceReadyForDisplay else {
            cancelPosterRelease()
            return
        }
        guard !isPosterReleaseReady else { return }
        guard posterReleaseTask == nil else { return }

        let generation = advancePosterReleaseGeneration()
        posterReleaseTask = Task { @MainActor [weak self, weak playerViewModel] in
            try? await Task.sleep(nanoseconds: Self.posterReleaseDelayNanoseconds)
            guard let self,
                  let playerViewModel,
                  !Task.isCancelled,
                  self.posterReleaseGeneration == generation,
                  self.playerViewModel === playerViewModel,
                  playerViewModel.isCurrentPlaybackSurfaceReadyForDisplay,
                  !playerViewModel.isTerminated
            else { return }
            self.posterReleaseTask = nil
            self.isPosterReleaseReady = true
            self.refreshSnapshot(from: playerViewModel)
        }
    }

    private func cancelPosterRelease() {
        posterReleaseTask?.cancel()
        posterReleaseTask = nil
        isPosterReleaseReady = false
        advancePosterReleaseGeneration()
    }

    @discardableResult
    private func advancePosterReleaseGeneration() -> Int {
        posterReleaseGeneration += 1
        return posterReleaseGeneration
    }

    private static let posterReleaseDelayNanoseconds: UInt64 = 35_000_000

    deinit {
        posterReleaseTask?.cancel()
    }
}
