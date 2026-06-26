import SwiftUI

private struct VideoDetailPlaybackSceneHostModifier: ViewModifier {
    @ObservedObject var viewModel: VideoDetailViewModel
    @ObservedObject var libraryStore: LibraryStore
    let scenePhase: ScenePhase
    let context: VideoDetailPlaybackSceneContext
    let actions: VideoDetailPlaybackSceneActions
    let hostActions: VideoDetailPlaybackSceneHostActions

    func body(content: Content) -> some View {
        content
            .videoDetailChrome(
                viewModel: viewModel,
                state: context.hostState.chrome,
                retryPlaybackLoad: hostActions.retryPlaybackLoad
            )
            .videoDetailPlaybackLoadHost(
                viewModel: viewModel,
                onPlayerIdentityChanged: {
                    actions.fullscreen.recovery.handlePlayerIdentityChanged()
                }
            )
            .videoDetailLifecycle(
                actions: actions.lifecycle.lifecycle,
                supportedOrientations: context.layout.supportedInterfaceOrientations,
                hidesSystemChrome: context.layout.shouldHideSystemChrome
            )
            .videoDetailNavigationPlaybackHost(scenePhase: scenePhase, actions: actions.lifecycle.navigation)
            .videoDetailSheets(
                viewModel: viewModel,
                libraryStore: libraryStore,
                sheetState: context.hostState.sheets
            )
    }
}

extension View {
    func videoDetailPlaybackSceneHosts(
        viewModel: VideoDetailViewModel,
        libraryStore: LibraryStore,
        scenePhase: ScenePhase,
        context: VideoDetailPlaybackSceneContext,
        actions: VideoDetailPlaybackSceneActions
    ) -> some View {
        modifier(
            VideoDetailPlaybackSceneHostModifier(
                viewModel: viewModel,
                libraryStore: libraryStore,
                scenePhase: scenePhase,
                context: context,
                actions: actions,
                hostActions: VideoDetailPlaybackSceneHostActionsBuilder(viewModel: viewModel).actions
            )
        )
    }
}
