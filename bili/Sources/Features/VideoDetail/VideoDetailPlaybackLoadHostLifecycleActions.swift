import Foundation

@MainActor
struct VideoDetailPlaybackLoadHostLifecycleActions {
    let actions: VideoDetailPlaybackLoadHostActions
    let state: VideoDetailPlaybackLoadHostState
    let onPlayerIdentityChanged: @Sendable @MainActor () -> Void

    init(
        actions: VideoDetailPlaybackLoadHostActions,
        state: VideoDetailPlaybackLoadHostState,
        onPlayerIdentityChanged: @escaping @Sendable @MainActor () -> Void
    ) {
        self.actions = actions
        self.state = state
        self.onPlayerIdentityChanged = onPlayerIdentityChanged
    }

    func load() async {
        await actions.load()
    }

    func schedulePlayerIdentityChanged() {
        guard actions.canDeliverPlayerIdentityChange else {
            state.cancelPendingWork()
            return
        }
        state.schedulePlayerIdentityChanged()
    }

    func deliverPlayerIdentityChanged(generation: Int) {
        guard generation > 0 else { return }
        guard actions.canDeliverPlayerIdentityChange else {
            state.cancelPendingWork()
            return
        }
        onPlayerIdentityChanged()
    }

    func cancelPendingWork() {
        state.cancelPendingWork()
    }
}
