import AVFoundation
import AVKit
import UIKit

/// Keeps the video surface entirely in UIKit.
/// SwiftUI continues to own playback controls and danmaku in the overlay host.
@MainActor
final class DirectUIKitPlayerSurfaceHostView: UIView {
    private var viewModel: PlayerStateViewModel
    private var isPictureInPictureEnabled: Bool
    private var prefersNativePlaybackSurface: Bool
    private var showsNativePlaybackControls: Bool
    private var showsNativePlaybackSpeeds: Bool
    private var enablesNativeSurfaceGestures: Bool
    private var nativeAllowsPictureInPicturePlayback: Bool?
    private let surfaceView = VideoSurfaceContainerView()
    private var isTornDown = false

    var nativePlayerViewController: NativeFullScreenPlayerViewController {
        surfaceView.nativePlayerViewController
    }

    init(
        viewModel: PlayerStateViewModel,
        isPictureInPictureEnabled: Bool,
        prefersNativePlaybackSurface: Bool = NativePlaybackControlsExperiment.stored(),
        showsNativePlaybackControls: Bool = NativePlaybackControlsExperiment.usesSystemPlaybackControlsUI(),
        showsNativePlaybackSpeeds: Bool = NativePlaybackControlsExperiment.storedSpeedsEnabled(),
        enablesNativeSurfaceGestures: Bool = NativePlaybackControlsExperiment.usesNativeSurfaceGestureController(),
        nativeAllowsPictureInPicturePlayback: Bool? = nil
    ) {
        self.viewModel = viewModel
        self.isPictureInPictureEnabled = isPictureInPictureEnabled
        self.prefersNativePlaybackSurface = prefersNativePlaybackSurface
        self.showsNativePlaybackControls = showsNativePlaybackControls
        self.showsNativePlaybackSpeeds = showsNativePlaybackSpeeds
        self.enablesNativeSurfaceGestures = enablesNativeSurfaceGestures
        self.nativeAllowsPictureInPicturePlayback = nativeAllowsPictureInPicturePlayback
        super.init(frame: .zero)

        overrideUserInterfaceStyle = .dark
        backgroundColor = .black
        isUserInteractionEnabled = false
        surfaceView.overrideUserInterfaceStyle = .dark
        surfaceView.backgroundColor = .black
        surfaceView.disablesImplicitLayoutAnimations = true
        surfaceView.configureSurfaceHandoff(
            usesLiveSurfaceDuringLayoutTransition: true,
            isLayoutTransitioning: true
        )
        surfaceView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surfaceView)
        NSLayoutConstraint.activate([
            surfaceView.leadingAnchor.constraint(equalTo: leadingAnchor),
            surfaceView.trailingAnchor.constraint(equalTo: trailingAnchor),
            surfaceView.topAnchor.constraint(equalTo: topAnchor),
            surfaceView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        bindSurface(to: viewModel, startsPlayback: false)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setPlayerViewModel(_ playerViewModel: PlayerStateViewModel) {
        guard !isTornDown else { return }
        guard viewModel !== playerViewModel else { return }
        viewModel.detachSurface(
            surfaceView,
            preservesReadinessDuringSurfaceHandoff: viewModel.hasPresentedPlayback
        )
        viewModel = playerViewModel
        bindSurface(to: playerViewModel, startsPlayback: playerViewModel.wantsAutoplay)
    }

    func setPictureInPictureEnabled(
        _ isEnabled: Bool,
        allowsAutomaticInline: Bool? = nil
    ) {
        guard !isTornDown else { return }
        isPictureInPictureEnabled = isEnabled
        surfaceView.setPictureInPictureEnabled(isEnabled)
        if let allowsAutomaticInline {
            viewModel.setAutomaticPictureInPictureFromInlineAllowed(allowsAutomaticInline)
        }
        viewModel.setPictureInPictureEnabled(isEnabled)
    }

    func setNativePlaybackControlsOptions(
        prefersNativePlaybackSurface: Bool = NativePlaybackControlsExperiment.stored(),
        showsPlaybackControls: Bool,
        showsPlaybackSpeeds: Bool,
        enablesNativeSurfaceGestures: Bool,
        allowsPictureInPicturePlayback: Bool?
    ) {
        guard !isTornDown else { return }
        let surfacePreferenceChanged = self.prefersNativePlaybackSurface != prefersNativePlaybackSurface
            || surfaceView.prefersNativePlaybackControls != prefersNativePlaybackSurface
        self.prefersNativePlaybackSurface = prefersNativePlaybackSurface
        showsNativePlaybackControls = showsPlaybackControls
        showsNativePlaybackSpeeds = showsPlaybackSpeeds
        self.enablesNativeSurfaceGestures = enablesNativeSurfaceGestures
        nativeAllowsPictureInPicturePlayback = allowsPictureInPicturePlayback
        surfaceView.setNativeAllowsPictureInPicturePlayback(
            prefersNativePlaybackSurface ? allowsPictureInPicturePlayback : nil
        )
        surfaceView.setEnablesNativeSurfaceGestures(
            prefersNativePlaybackSurface && enablesNativeSurfaceGestures
        )
        surfaceView.setShowsSystemPlaybackControls(
            prefersNativePlaybackSurface && showsPlaybackControls
        )
        surfaceView.setShowsSystemPlaybackSpeeds(
            prefersNativePlaybackSurface && showsPlaybackControls && showsPlaybackSpeeds
        )
        if surfacePreferenceChanged {
            surfaceView.setPlayerViewModel(
                viewModel,
                prefersNativePlaybackControls: prefersNativePlaybackSurface
            )
            viewModel.attachSurface(
                surfaceView,
                prefersNativePlaybackControls: prefersNativePlaybackSurface,
                preservesReadinessDuringSurfaceHandoff: true
            )
            surfaceView.setNeedsLayout()
            surfaceView.invalidateVideoLayout()
        }
        viewModel.setPictureInPictureEnabled(isPictureInPictureEnabled)
    }

    func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        guard !isTornDown else { return }
        viewModel.setVideoGravity(gravity)
    }

    func refreshLayoutImmediately() {
        guard !isTornDown else { return }
        UIView.performWithoutAnimation {
            setNeedsLayout()
            layoutIfNeeded()
            surfaceView.configureBoundsRefresh(for: viewModel, synchronously: true)
            surfaceView.invalidateVideoLayout()
            viewModel.refreshSurfaceLayout()
#if DEBUG
            surfaceView.reportVideoDetailGeometryIfCorrect()
#endif
        }
    }

    func tearDown() {
        guard !isTornDown else { return }
        isTornDown = true
        surfaceView.detachPlayerSurface()
        surfaceView.removeFromSuperview()
    }

    private func bindSurface(to playerViewModel: PlayerStateViewModel, startsPlayback: Bool) {
        let prefersNativeControls = prefersNativePlaybackSurface
        surfaceView.configureBoundsRefresh(for: playerViewModel, synchronously: true)
        surfaceView.setPictureInPictureEnabled(isPictureInPictureEnabled)
        surfaceView.setNativeAllowsPictureInPicturePlayback(
            prefersNativeControls ? nativeAllowsPictureInPicturePlayback : nil
        )
        surfaceView.setEnablesNativeSurfaceGestures(
            prefersNativeControls && enablesNativeSurfaceGestures
        )
        surfaceView.setShowsSystemPlaybackControls(prefersNativeControls && showsNativePlaybackControls)
        surfaceView.setShowsSystemPlaybackSpeeds(
            prefersNativeControls && showsNativePlaybackControls && showsNativePlaybackSpeeds
        )
        surfaceView.setPlayerViewModel(playerViewModel, prefersNativePlaybackControls: prefersNativeControls)
        playerViewModel.setPictureInPictureEnabled(isPictureInPictureEnabled)
        playerViewModel.attachSurface(
            surfaceView,
            prefersNativePlaybackControls: prefersNativeControls,
            preservesReadinessDuringSurfaceHandoff: surfaceView.isLiveSurfaceHandoffActive
        )
        playerViewModel.endSurfaceMigrationHold()
        surfaceView.setNeedsLayout()
        surfaceView.invalidateVideoLayout()
        if startsPlayback {
            playerViewModel.play()
        }
    }

}
