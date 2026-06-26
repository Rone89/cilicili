import SwiftUI

struct VideoDetailPlayerActivityBridge: View {
    @ObservedObject var playerViewModel: PlayerStateViewModel
    let actions: VideoDetailPlayerActivityBridgeActions

    init(
        playerViewModel: PlayerStateViewModel,
        onChange: @escaping (Bool) -> Void
    ) {
        self.playerViewModel = playerViewModel
        actions = VideoDetailPlayerActivityBridgeActions(
            playerViewModel: playerViewModel,
            onChange: onChange
        )
    }

    var body: some View {
        Color.clear
            .onAppear(perform: actions.notify)
            .onChange(of: playerViewModel.isPlaying) { _, _ in
                actions.notify()
            }
            .onChange(of: playerViewModel.isBuffering) { _, _ in
                actions.notify()
            }
            .onChange(of: playerViewModel.playbackPhase) { _, _ in
                actions.notify()
            }
            .onDisappear(perform: actions.notifyInactive)
    }
}
