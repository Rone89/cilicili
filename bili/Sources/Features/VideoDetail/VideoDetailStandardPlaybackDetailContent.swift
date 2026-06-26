import SwiftUI

struct VideoDetailStandardPlaybackDetailContent: View {
    @ObservedObject var viewModel: VideoDetailViewModel
    let config: VideoDetailStandardPlaybackContainerConfig
    let tab: VideoDetailContentTab
    let actions: VideoDetailStandardPlaybackActions

    var body: some View {
        VideoDetailContentPage(
            viewModel: viewModel,
            layoutWidth: config.screenSize.width,
            tab: tab,
            runtimeSettings: config.runtimeSettings,
            onShowNetworkDiagnostics: actions.onShowNetworkDiagnostics,
            onShowFavoriteFolders: actions.onShowFavoriteFolders,
            onReply: actions.onReply
        )
    }
}
