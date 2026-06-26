import SwiftUI

struct VideoDetailSummaryCard: View {
    @ObservedObject var viewModel: VideoDetailViewModel
    let contentWidth: CGFloat
    let showsNetworkDiagnosticsButton: Bool
    let onShowNetworkDiagnostics: () -> Void
    let renderPack: VideoDetailSummaryCardRenderPack

    init(
        viewModel: VideoDetailViewModel,
        contentWidth: CGFloat,
        showsNetworkDiagnosticsButton: Bool,
        onShowNetworkDiagnostics: @escaping () -> Void,
        onShowFavoriteFolders: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.contentWidth = contentWidth
        self.showsNetworkDiagnosticsButton = showsNetworkDiagnosticsButton
        self.onShowNetworkDiagnostics = onShowNetworkDiagnostics
        renderPack = VideoDetailSummaryCardRenderPack(
            viewModel: viewModel,
            showFavoriteFolders: onShowFavoriteFolders
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VideoDetailInfoBlock(
                store: renderPack.descriptionStore
            )

            VideoDetailActionStripContainer(
                descriptionStore: renderPack.descriptionStore,
                store: renderPack.interactionStore,
                contentWidth: contentWidth,
                onFollow: renderPack.actions.follow,
                onLike: renderPack.actions.like,
                onCoin: renderPack.actions.coin,
                onFavorite: renderPack.actions.favorite,
                onShareTap: renderPack.actions.share
            )

            if showsNetworkDiagnosticsButton {
                VideoDetailNetworkDiagnosticsButton(action: onShowNetworkDiagnostics)
            }

            VideoDetailInteractionNotice(store: renderPack.interactionStore)
            VideoDetailPlayURLNotice(
                placeholderStore: renderPack.placeholderStore,
                retry: renderPack.actions.retryPlayURL
            )
        }
        .frame(width: contentWidth, alignment: .leading)
    }
}
