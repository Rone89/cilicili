import Foundation

@MainActor
struct VideoDetailPlaybackContext {
    let playerViewModel: PlayerStateViewModel?
    let decodePath: PlayerEngineDiagnostics.DecodePath?
    let allowsInlineFullscreenRotation: Bool
    let usesPortraitFullscreen: Bool

    init(viewModel: VideoDetailViewModel?, usesSystemNativePlayerUI: Bool) {
        playerViewModel = viewModel?.playerIdentityRenderStore.playerViewModel
        decodePath = playerViewModel?.engineDiagnostics.decodePath
        allowsInlineFullscreenRotation = Self.allowsInlineFullscreenRotation(
            decodePath: decodePath,
            usesSystemNativePlayerUI: usesSystemNativePlayerUI
        )
        usesPortraitFullscreen = viewModel.map(Self.usesPortraitFullscreen(in:)) ?? false
    }

    private static func allowsInlineFullscreenRotation(
        decodePath: PlayerEngineDiagnostics.DecodePath?,
        usesSystemNativePlayerUI: Bool
    ) -> Bool {
        guard let decodePath else { return false }
        return decodePath != .unknown && !usesSystemNativePlayerUI
    }

    private static func usesPortraitFullscreen(in viewModel: VideoDetailViewModel) -> Bool {
        videoAspectRatio(in: viewModel.playbackRenderStore).map { $0 < 0.9 } == true
    }

    private static func videoAspectRatio(in store: VideoDetailPlaybackRenderStore) -> Double? {
        store.selectedPlayVariant?.videoAspectRatio
            ?? selectedPage(in: store.pageSelectorStore)?.dimension?.aspectRatio
            ?? store.qualityMenuItems.compactMap(\.variant.videoAspectRatio).first
    }

    private static func selectedPage(in store: VideoDetailPageSelectorRenderStore) -> VideoPage? {
        guard let selectedCID = store.selectedCID else { return nil }
        return store.pages.first { $0.cid == selectedCID }
    }
}
