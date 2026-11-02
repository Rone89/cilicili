import AVFoundation
import QuartzCore

/// AVAudioSession is process-wide: a new player must wait for the old player's
/// deactivation before activating. Only the blocking system call leaves MainActor.
@MainActor
final class PlaybackAudioSession {
    static let shared = PlaybackAudioSession()

    private let deactivateOperation: @Sendable () -> Bool
    private let activateOperation: @MainActor () -> Bool
    private var pendingDeactivation: Task<Void, Never>?

    var isDeactivating: Bool { pendingDeactivation != nil }

    init(
        deactivate: @escaping @Sendable () -> Bool = {
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
                return true
            } catch { return false }
        },
        activate: @escaping @MainActor () -> Bool = {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .moviePlayback, options: [])
                try session.setActive(true)
                return true
            } catch { return false }
        }
    ) {
        deactivateOperation = deactivate
        activateOperation = activate
    }

    func deactivate(completion: @escaping @MainActor (Double, Bool) -> Void) {
        // An already-running deactivation serves another pause too. Do not queue
        // a second old pause that could run after a newer playback activation.
        guard pendingDeactivation == nil else { return }
        let operation = deactivateOperation
        pendingDeactivation = Task {
            let result: (Double, Bool) = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let startedAt = CACurrentMediaTime()
                    let succeeded = operation()
                    continuation.resume(returning: ((CACurrentMediaTime() - startedAt) * 1_000, succeeded))
                }
            }
            pendingDeactivation = nil
            completion(result.0, result.1)
        }
    }

    func activate(
        when isCurrent: @escaping @MainActor () -> Bool,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        if let pendingDeactivation {
            Task {
                await pendingDeactivation.value
                // Recheck both ownership and any newer deactivation after the wait.
                activate(when: isCurrent, completion: completion)
            }
            return
        }
        guard isCurrent() else { return }
        completion(activateOperation())
    }
}
