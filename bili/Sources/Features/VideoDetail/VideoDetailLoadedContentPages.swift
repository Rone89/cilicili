import SwiftUI

struct VideoDetailLoadedDetailContentPage: View {
    @Environment(\.videoDetailStandardHorizontalInset) private var standardHorizontalInset
    let viewModel: VideoDetailViewModel
    // A value input lets SwiftUI invalidate this page when an episode seed
    // resolves. The view-model reference itself remains identical.
    let detail: VideoItem
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
            if detail.isPGCEpisode {
                VideoDetailPgcEpisodeSection(
                    detail: detail,
                    api: viewModel.api,
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

        if showsRecommendations {
            if mountsSecondaryContent {
                VideoDetailRecommendationsSection(
                    detail: detail,
                    relatedStore: renderPack.relatedStore,
                    layoutWidth: layoutWidth,
                    runtimeSettings: runtimeSettings,
                    retryRelated: renderPack.actions.retryRelated
                )
            } else if !detail.isPGCEpisode {
                InitialRelatedSection(layoutWidth: layoutWidth)
            }
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
