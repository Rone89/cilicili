import Foundation

extension VideoDetailViewModel {
    @discardableResult
    func performInteractionMutation(
        _ kind: VideoDetailInteractionMutationKind,
        isCurrent: () -> Bool = { true },
        operation: () async throws -> Void
    ) async -> Bool {
        guard !isPlaybackInvalidatedForNavigation else { return false }
        guard !isInteractionMutationActive(kind) else { return false }
        setInteractionMutationActive(true, for: kind)
        interactionMessage = nil
        defer {
            if !isPlaybackInvalidatedForNavigation {
                setInteractionMutationActive(false, for: kind)
            }
        }

        do {
            try await operation()
            guard !isPlaybackInvalidatedForNavigation,
                  isCurrent()
            else { return false }
            await refreshDetailMetadata()
            return true
        } catch {
            guard !isPlaybackInvalidatedForNavigation,
                  isCurrent()
            else { return false }
            interactionMessage = interactionFailureMessage(error)
            return false
        }
    }

    func recoverLikeStateMismatchIfNeeded(_ error: Error, targetState: Bool) -> Bool {
        guard let biliError = error as? BiliAPIError,
              case .api(let code, _) = biliError,
              code == 65004
        else { return false }

        interactionState.isLiked = targetState
        interactionMessage = nil
        return true
    }
}
