import SwiftUI

@MainActor
struct VideoDetailViewActionsBuilder {
    let seedVideo: VideoItem
    let dependencies: AppDependencies
    let holder: VideoDetailViewModelHolder
    let fullscreenCoordinator: VideoDetailFullscreenCoordinator
    let dismiss: DismissAction
    let onRequestClose: (() -> Void)?
    let onPopOne: (() -> Void)?

    var actions: VideoDetailViewActions {
        VideoDetailViewActions(
            configuration: configurationActions,
            close: closeActions
        )
    }

    private var configurationActions: VideoDetailViewConfigurationActions {
        VideoDetailViewConfigurationActions(
            seedVideo: seedVideo,
            dependencies: dependencies,
            holder: holder
        )
    }

    private var closeActions: VideoDetailViewCloseActions {
        VideoDetailViewCloseActions(
            holder: holder,
            fullscreenCoordinator: fullscreenCoordinator,
            dismiss: dismiss,
            onRequestClose: onRequestClose,
            onPopOne: onPopOne
        )
    }
}
