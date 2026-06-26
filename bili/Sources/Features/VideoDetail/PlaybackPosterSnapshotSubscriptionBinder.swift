import Combine
import Foundation

@MainActor
struct PlaybackPosterSnapshotSubscriptionBinder {
    let playerViewModel: PlayerStateViewModel
    let refresh: () -> Void

    func store(in cancellables: inout Set<AnyCancellable>) {
        playerViewModel.$isCurrentPlaybackSurfaceReadyForDisplay
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)

        playerViewModel.$errorMessage
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)

        playerViewModel.$loadingProgress
            .removeDuplicates { abs($0 - $1) < 0.01 }
            .sink { _ in refresh() }
            .store(in: &cancellables)

        playerViewModel.$isBuffering
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)
    }
}
