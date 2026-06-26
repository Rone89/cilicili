import SwiftUI

struct VideoDetailContentPageBody: View {
    @ObservedObject var viewModel: VideoDetailViewModel
    let layoutWidth: CGFloat
    let tab: VideoDetailContentTab
    let runtimeSettings: VideoDetailRuntimeSettingsSnapshot
    let onShowNetworkDiagnostics: () -> Void
    let onShowFavoriteFolders: () -> Void
    let onReply: (Comment) -> Void

    var body: some View {
        switch tab {
        case .detail:
            VideoDetailLoadedDetailContentPage(
                viewModel: viewModel,
                layoutWidth: layoutWidth,
                runtimeSettings: runtimeSettings,
                onShowNetworkDiagnostics: onShowNetworkDiagnostics,
                onShowFavoriteFolders: onShowFavoriteFolders
            )

        case .comments:
            VideoDetailLoadedCommentsContentPage(
                viewModel: viewModel,
                onReply: onReply
            )
        }
    }
}
