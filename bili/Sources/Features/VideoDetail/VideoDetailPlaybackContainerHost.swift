import SwiftUI

struct VideoDetailPlaybackContainerHost: View {
    @ObservedObject var viewModel: VideoDetailViewModel
    let layout: VideoDetailPlaybackSceneLayout
    let standardPlaybackConfig: VideoDetailStandardPlaybackContainerConfig
    @Binding var selectedContentTab: VideoDetailContentTab
    let actions: VideoDetailStandardPlaybackActions

    var body: some View {
        VideoDetailStandardPlaybackContainer(
            viewModel: viewModel,
            config: standardPlaybackConfig,
            selectedContentTab: $selectedContentTab,
            actions: actions
        )
        .frame(width: layout.playbackSize.width, height: layout.playbackSize.height)
        .offset(x: layout.fullscreenOffset.width, y: layout.fullscreenOffset.height)
    }
}
