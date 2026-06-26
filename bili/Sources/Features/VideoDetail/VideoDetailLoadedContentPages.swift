import SwiftUI

struct VideoDetailLoadedDetailContentPage: View {
    @ObservedObject var viewModel: VideoDetailViewModel
    let layoutWidth: CGFloat
    let runtimeSettings: VideoDetailRuntimeSettingsSnapshot
    let onShowNetworkDiagnostics: () -> Void
    let onShowFavoriteFolders: () -> Void

    var body: some View {
        let renderPack = renderPack

        VideoDetailSummaryCard(
            viewModel: viewModel,
            contentWidth: renderPack.contentWidth,
            showsNetworkDiagnosticsButton: runtimeSettings.showsNetworkDiagnosticsButton,
            onShowNetworkDiagnostics: onShowNetworkDiagnostics,
            onShowFavoriteFolders: onShowFavoriteFolders
        )
        .padding(.horizontal, VideoDetailContentPageMetrics.horizontalPadding)

        VideoDetailPageMenu(
            store: renderPack.pageSelectorStore,
            selectPage: renderPack.actions.selectPage
        )
        .padding(.horizontal, VideoDetailContentPageMetrics.horizontalPadding)

        VideoDetailRelatedSection(
            store: renderPack.relatedStore,
            layoutWidth: layoutWidth,
            runtimeSettings: runtimeSettings,
            retryRelated: renderPack.actions.retryRelated
        )
    }

    private var renderPack: VideoDetailLoadedDetailContentPageRenderPack {
        VideoDetailLoadedDetailContentPageRenderPack(
            viewModel: viewModel,
            layoutWidth: layoutWidth
        )
    }
}
