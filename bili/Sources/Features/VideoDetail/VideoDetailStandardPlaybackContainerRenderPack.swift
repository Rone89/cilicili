import Foundation

@MainActor
struct VideoDetailStandardPlaybackContainerRenderPack {
    let pageConfig: VideoDetailStandardPlaybackPageConfig
    let playbackStore: VideoDetailPlaybackRenderStore
    let pageSelectorStore: VideoDetailPageSelectorRenderStore
    let playerIdentityStore: VideoDetailPlayerIdentityRenderStore

    init(
        viewModel: VideoDetailViewModel,
        config: VideoDetailStandardPlaybackContainerConfig,
        actions: VideoDetailStandardPlaybackActions
    ) {
        pageConfig = Self.makePageConfig(config: config, actions: actions)
        playbackStore = viewModel.playbackRenderStore
        pageSelectorStore = viewModel.playbackRenderStore.pageSelectorStore
        playerIdentityStore = viewModel.playerIdentityRenderStore
    }

    private static func makePageConfig(
        config: VideoDetailStandardPlaybackContainerConfig,
        actions: VideoDetailStandardPlaybackActions
    ) -> VideoDetailStandardPlaybackPageConfig {
        VideoDetailStandardPlaybackConfigurationBuilder(
            screenSize: config.screenSize,
            isLandscape: config.isLandscape,
            usesFullscreenLayout: config.usesFullscreenLayout,
            activeFullscreenMode: config.activeFullscreenMode,
            targetFullscreenMode: config.targetFullscreenMode,
            isCompletingFullscreenExit: config.isCompletingFullscreenExit,
            isSystemRotationLayoutTransitioning: config.isSystemRotationLayoutTransitioning,
            isDanmakuSettingsPresented: config.isDanmakuSettingsPresented,
            runtimeSettings: config.runtimeSettings,
            actions: actions
        ).pageConfig
    }
}
