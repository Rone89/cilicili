import SwiftUI

struct VideoDetailLoadedDetailContentPage: View {
    @Environment(\.videoDetailStandardHorizontalInset) private var standardHorizontalInset
    let viewModel: VideoDetailViewModel
    let layoutWidth: CGFloat
    let mountsSecondaryContent: Bool
    let runtimeSettings: VideoDetailRuntimeSettingsSnapshot
    let onShowNetworkDiagnostics: () -> Void
    let onShowFavoriteFolders: () -> Void
    let onShowCoinPicker: () -> Void
    var showsSummary = true
    var showsRecommendations = true

    private var horizontalInset: CGFloat {
        PlaybackDetailContentMetrics.horizontalPadding(for: standardHorizontalInset)
    }

    var body: some View {
        let renderPack = renderPack

        if showsSummary {
            if viewModel.detail.isPGCEpisode {
                VideoDetailPgcEpisodeSection(
                    detail: viewModel.detail,
                    selectEpisode: renderPack.actions.selectPgcEpisode
                ) {
                    VideoDetailSummaryCard(
                        viewModel: viewModel,
                        contentWidth: renderPack.contentWidth,
                        showsNetworkDiagnosticsButton: runtimeSettings.showsNetworkDiagnosticsButton,
                        showsVideoInfo: false,
                        onShowNetworkDiagnostics: onShowNetworkDiagnostics,
                        onShowFavoriteFolders: onShowFavoriteFolders,
                        onShowCoinPicker: onShowCoinPicker
                    )
                }
                .padding(.horizontal, horizontalInset)
            } else {
                VideoDetailSummaryCard(
                    viewModel: viewModel,
                    contentWidth: renderPack.contentWidth,
                    showsNetworkDiagnosticsButton: runtimeSettings.showsNetworkDiagnosticsButton,
                    onShowNetworkDiagnostics: onShowNetworkDiagnostics,
                    onShowFavoriteFolders: onShowFavoriteFolders,
                    onShowCoinPicker: onShowCoinPicker
                )
                .padding(.horizontal, horizontalInset)

                VideoDetailPageMenu(
                    store: renderPack.pageSelectorStore,
                    selectPage: renderPack.actions.selectPage
                )
                .padding(.horizontal, horizontalInset)
            }

        }

        if mountsSecondaryContent && showsRecommendations {
            VideoDetailRecommendationsSection(
                detail: viewModel.detail,
                relatedStore: renderPack.relatedStore,
                layoutWidth: layoutWidth,
                runtimeSettings: runtimeSettings,
                retryRelated: renderPack.actions.retryRelated
            )
        }
    }

    private var renderPack: VideoDetailLoadedDetailContentPageRenderPack {
        VideoDetailLoadedDetailContentPageRenderPack(
            viewModel: viewModel,
            layoutWidth: layoutWidth,
            horizontalInset: horizontalInset
        )
    }
}

private struct VideoDetailRecommendationsSection: View {
    let detail: VideoItem
    @ObservedObject var relatedStore: VideoDetailRelatedRenderStore
    let layoutWidth: CGFloat
    let runtimeSettings: VideoDetailRuntimeSettingsSnapshot
    let retryRelated: () async -> Void

    @ViewBuilder
    var body: some View {
        if !detail.isPGCEpisode {
            VideoDetailRelatedSection(
                store: relatedStore,
                layoutWidth: layoutWidth,
                runtimeSettings: runtimeSettings,
                retryRelated: retryRelated
            )
        }
    }
}
