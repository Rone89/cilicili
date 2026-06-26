import AVFoundation
import SwiftUI

struct BiliPlayerViewRuntimeContext {
    let lifecycleActions: BiliPlayerLifecycleActions
    let renderContext: BiliPlayerViewRenderContext
}

struct BiliPlayerViewRuntimeContextBuilder {
    let dependencies: AppDependencies
    let libraryStore: LibraryStore
    let viewModel: PlayerStateViewModel
    let surfaceState: PlayerSurfaceStateModel
    let playbackControlsVisibility: PlayerPlaybackControlsVisibilityModel
    let rotationTransitionSnapshotModel: PlayerRotationTransitionSnapshotModel
    let speedBoostModel: PlayerSpeedBoostModel
    let playbackProgressCoordinator: PlayerPlaybackProgressCoordinator
    let progressReporter: PlayerPlaybackProgressReporter
    let historyVideo: VideoItem?
    let historyCID: Int?
    let historyDuration: TimeInterval?
    let configuration: BiliPlayerViewConfiguration
    let videoGravity: AVLayerVideoGravity
    let prepareUserSeekWarmup: (Double, Bool) -> Void
    let resetPreparedScrubProgress: () -> Void

    var context: BiliPlayerViewRuntimeContext {
        BiliPlayerViewRuntimeContext(
            lifecycleActions: lifecycleActions,
            renderContext: renderContext
        )
    }

    private var progressContext: PlayerPlaybackProgressContext {
        PlayerPlaybackProgressContext(
            dependencies: dependencies,
            libraryStore: libraryStore,
            historyVideo: historyVideo,
            historyCID: historyCID,
            historyDuration: historyDuration,
            durationHint: configuration.durationHint,
            playerDuration: viewModel.duration
        )
    }

    private var lifecycleActions: BiliPlayerLifecycleActions {
        BiliPlayerLifecycleActionBuilder(
            viewModel: viewModel,
            surfaceState: surfaceState,
            playbackControlsVisibility: playbackControlsVisibility,
            rotationTransitionSnapshotModel: rotationTransitionSnapshotModel,
            speedBoostModel: speedBoostModel,
            playbackProgressCoordinator: playbackProgressCoordinator,
            progressReporter: progressReporter,
            progressContext: progressContext,
            configuration: configuration,
            defaultPlaybackRate: libraryStore.defaultPlaybackRate,
            videoGravity: videoGravity
        ).actions
    }

    private var renderContext: BiliPlayerViewRenderContext {
        BiliPlayerViewRenderContext(
            viewModel: viewModel,
            surfaceState: surfaceState,
            playbackControlsVisibility: playbackControlsVisibility,
            rotationTransitionSnapshotModel: rotationTransitionSnapshotModel,
            rotationFallbackCoverURL: rotationFallbackCoverURL,
            speedBoostModel: speedBoostModel,
            configuration: configuration,
            prepareUserSeekWarmup: prepareUserSeekWarmup,
            resetPreparedScrubProgress: resetPreparedScrubProgress
        )
    }

    private var rotationFallbackCoverURL: URL? {
        guard let cover = historyVideo?.pic?.normalizedBiliURL() else { return nil }
        let width = PlaybackEnvironment.current.shouldPreferConservativePlayback ? 480 : 720
        let height = Int((Double(width) * 9.0 / 16.0).rounded())
        return URL(string: cover.biliCoverThumbnailURL(width: width, height: height))
            ?? URL(string: cover)
    }
}
