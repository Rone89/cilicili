import Foundation

@MainActor
struct VideoDetailPlaybackSceneActionDependencies {
    let viewModel: VideoDetailViewModel
    let fullscreenCoordinator: VideoDetailFullscreenCoordinator
    let runtimeSettings: VideoDetailRuntimeSettingsStore
    let libraryStore: LibraryStore
    let usesSystemNativePlayerUI: Bool
}
