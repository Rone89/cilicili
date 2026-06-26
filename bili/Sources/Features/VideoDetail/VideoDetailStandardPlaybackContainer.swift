import SwiftUI

struct VideoDetailStandardPlaybackContainer: View {
    @ObservedObject var viewModel: VideoDetailViewModel
    let config: VideoDetailStandardPlaybackContainerConfig
    @Binding var selectedContentTab: VideoDetailContentTab
    let actions: VideoDetailStandardPlaybackActions

    var body: some View {
        let renderPack = renderPack

        VideoDetailStandardPlaybackPage(
            config: renderPack.pageConfig,
            viewModel: viewModel,
            playbackStore: renderPack.playbackStore,
            pageSelectorStore: renderPack.pageSelectorStore,
            playerIdentityStore: renderPack.playerIdentityStore,
            selectedContentTab: $selectedContentTab,
            detailContent: { tab in
                VideoDetailStandardPlaybackDetailContent(
                    viewModel: viewModel,
                    config: config,
                    tab: tab,
                    actions: actions
                )
            }
        )
    }

    private var renderPack: VideoDetailStandardPlaybackContainerRenderPack {
        VideoDetailStandardPlaybackContainerRenderPack(
            viewModel: viewModel,
            config: config,
            actions: actions
        )
    }

}
