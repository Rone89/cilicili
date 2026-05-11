import Foundation

@MainActor
final class ActivePlaybackCoordinator {
    static let shared = ActivePlaybackCoordinator()

    private weak var activePlayer: PlayerStateViewModel?
    private var activeGeneration = UUID()

    private init() {}

    @discardableResult
    func activate(_ player: PlayerStateViewModel) -> UUID {
        if let activePlayer, activePlayer !== player {
            activePlayer.stop(reason: .replacedByAnotherPlayer)
        }
        activePlayer = player
        activeGeneration = UUID()
        return activeGeneration
    }

    func deactivate(_ player: PlayerStateViewModel) {
        guard activePlayer === player else { return }
        activePlayer = nil
        activeGeneration = UUID()
    }

    func stopActivePlayback() {
        guard let player = activePlayer else { return }
        activePlayer = nil
        activeGeneration = UUID()
        player.stop(reason: .navigation)
    }

    func isActive(_ player: PlayerStateViewModel) -> Bool {
        activePlayer === player
    }
}

enum PlayerStopReason {
    case navigation
    case replacedByAnotherPlayer
    case deallocated
}
