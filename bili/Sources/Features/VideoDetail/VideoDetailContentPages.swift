import SwiftUI

struct VideoDetailContentPage: View {
    @ObservedObject var viewModel: VideoDetailViewModel
    let layoutWidth: CGFloat
    let tab: VideoDetailContentTab
    let runtimeSettings: VideoDetailRuntimeSettingsSnapshot
    let onShowNetworkDiagnostics: () -> Void
    let onShowFavoriteFolders: () -> Void
    let onReply: (Comment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VideoDetailContentPageMetrics.spacing) {
            VideoDetailContentPageBody(
                viewModel: viewModel,
                layoutWidth: layoutWidth,
                tab: tab,
                runtimeSettings: runtimeSettings,
                onShowNetworkDiagnostics: onShowNetworkDiagnostics,
                onShowFavoriteFolders: onShowFavoriteFolders,
                onReply: onReply
            )
        }
        .padding(.top, VideoDetailContentPageMetrics.topPadding)
        .frame(width: layoutWidth, alignment: .top)
        .background(VideoDetailTheme.background)
    }
}
