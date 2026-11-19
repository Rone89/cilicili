import AVKit
import Combine
import MediaPlayer
import SwiftUI
import UIKit

@MainActor
final class NativePlayerSurfaceGestureController: NSObject {
    private enum PanMode {
        case undecided
        case seeking(duration: TimeInterval)
        case adjusting(target: PlayerSurfaceVerticalAdjustmentTarget, initialValue: Float)
        case ignored
    }

    var onCustomGestureSuppressionChanged: ((_ isSuppressed: Bool, _ hidesNativeTransportControls: Bool) -> Void)?

    private weak var playerViewController: AVPlayerViewController?
    private weak var viewModel: PlayerStateViewModel?
    private let hudModel = NativePlayerSurfaceGestureHUDModel()
    private let speedBoostModel = PlayerSpeedBoostModel()
    private let systemControlsController = PlayerSystemControlsController()
    private let volumeView = MPVolumeView(frame: .zero)
    private lazy var hostingController: UIHostingController<NativePlayerSurfaceGestureHUD> = {
        let controller = UIHostingController(
            rootView: NativePlayerSurfaceGestureHUD(
                model: hudModel,
                speedBoostModel: speedBoostModel
            )
        )
        controller.overrideUserInterfaceStyle = .dark
        return controller
    }()
    private lazy var doubleTapGesture = UITapGestureRecognizer(
        target: self,
        action: #selector(handleDoubleTap(_:))
    )
    private lazy var panGesture = UIPanGestureRecognizer(
        target: self,
        action: #selector(handlePan(_:))
    )
    private lazy var longPressGesture = UILongPressGestureRecognizer(
        target: self,
        action: #selector(handleLongPress(_:))
    )

    private var panMode = PanMode.undecided
    private var panStartLocation: CGPoint?
    private var lastHorizontalTranslationX: CGFloat = 0
    private var currentSeekProgress: Double?
    private var isSpeedBoostGestureActive = false
    private var isCustomGestureSuppressingControls = false
    private var didGestureHideVisibleNativeControls = false
    private var directRestoredShowsPlaybackControls: Bool?
    private var resignActiveCancellable: AnyCancellable?

    private var isPanInteractionActive: Bool {
        switch panMode {
        case .seeking, .adjusting:
            return true
        case .undecided, .ignored:
            return false
        }
    }

    override init() {
        super.init()
        resignActiveCancellable = NotificationCenter.default
            .publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.cancelActiveInteraction(speedBoostReason: .background)
                }
            }
    }

#if DEBUG
    var debugLongPressGesture: UILongPressGestureRecognizer { longPressGesture }
    var debugDoubleTapGesture: UITapGestureRecognizer { doubleTapGesture }
    var debugPanGesture: UIPanGestureRecognizer { panGesture }
    var debugSpeedBoostPhase: PlayerSpeedBoostPhase { speedBoostModel.phase }
    var debugSpeedBoostDisplayedRate: BiliPlaybackRate { speedBoostModel.displayedRate }
    var debugIsSpeedBoostIndicatorVisible: Bool { speedBoostModel.isIndicatorVisible }
    var debugHostingViewController: UIViewController { hostingController }

    func debugTriggerLongPress(state: UIGestureRecognizer.State) {
        handleLongPressState(state)
    }

    func debugSimulatePanActive(isSeeking: Bool) {
        if isSeeking {
            panMode = .seeking(duration: 100)
            currentSeekProgress = 0.2
            beginCustomGestureControlsSuppressionIfNeeded()
        } else {
            panMode = .undecided
            endCustomGestureControlsSuppressionIfNeeded()
        }
    }

    func debugSimulatePanGesture(
        state: UIGestureRecognizer.State,
        startLocation: CGPoint,
        translation: CGPoint,
        velocity: CGPoint = .zero,
        in size: CGSize
    ) {
        guard let viewModel, !viewModel.isTerminated else {
            cancelActiveInteraction()
            return
        }
        switch state {
        case .began:
            panStartLocation = startLocation
            lastHorizontalTranslationX = 0
            currentSeekProgress = nil
            panMode = isSpeedBoostGestureActive ? .ignored : .undecided
        case .changed:
            guard !isSpeedBoostGestureActive else { return }
            if case .undecided = panMode {
                beginPanInteractionIfNeeded(
                    translation: translation,
                    startLocation: panStartLocation ?? startLocation,
                    size: size,
                    viewModel: viewModel
                )
            }
            updatePanInteraction(
                translation: translation,
                velocity: velocity,
                size: size,
                viewModel: viewModel
            )
        case .ended:
            finishPanInteraction(commitsSeek: !isSpeedBoostGestureActive)
        case .cancelled, .failed:
            finishPanInteraction(commitsSeek: false)
        default:
            break
        }
    }

    func debugShouldBeginLongPress(
        at location: CGPoint,
        in bounds: CGRect,
        safeAreaInsets: UIEdgeInsets = .zero,
        showsPlaybackControls: Bool
    ) -> Bool {
        shouldBeginLongPress(
            at: location,
            in: bounds,
            safeAreaInsets: safeAreaInsets,
            showsPlaybackControls: showsPlaybackControls
        )
    }
#endif

    func attach(to playerViewController: AVPlayerViewController, viewModel: PlayerStateViewModel) {
        if self.viewModel !== viewModel {
            cancelActiveInteraction(speedBoostReason: .playerChanged)
            self.viewModel = viewModel
        }

        guard let containerView = playerViewController.contentOverlayView else { return }
        if self.playerViewController === playerViewController,
           hostingController.view.superview === containerView {
            containerView.isUserInteractionEnabled = true
            hostingController.overrideUserInterfaceStyle = .dark
            hostingController.view.overrideUserInterfaceStyle = .dark
            hostingController.view.isUserInteractionEnabled = true
            refreshSystemControlsAttachment()
            return
        }

        removeHostedViews()
        self.playerViewController = playerViewController
        containerView.backgroundColor = .clear
        containerView.isOpaque = false
        containerView.isUserInteractionEnabled = true

        configureGestureRecognizersIfNeeded()
        let hostedView = hostingController.view!
        hostingController.overrideUserInterfaceStyle = .dark
        hostedView.overrideUserInterfaceStyle = .dark
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        hostedView.backgroundColor = .clear
        hostedView.isOpaque = false
        hostedView.isUserInteractionEnabled = true

        // Do not call `playerViewController.addChild(hostingController)`:
        // AVKit moves `contentOverlayView` into a separate `AVFullScreenViewController`
        // during native fullscreen presentation (`-[AVFullScreenViewController attachContentView]`),
        // which triggers `UIViewControllerHierarchyInconsistency` if a child VCinside
        // `contentOverlayView` still points to `playerViewController` as its parent.
        containerView.addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        volumeView.translatesAutoresizingMaskIntoConstraints = false
        volumeView.showsVolumeSlider = true
        volumeView.isUserInteractionEnabled = false
        volumeView.alpha = 0.01
        containerView.addSubview(volumeView)
        NSLayoutConstraint.activate([
            volumeView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            volumeView.topAnchor.constraint(equalTo: containerView.topAnchor),
            volumeView.widthAnchor.constraint(equalToConstant: 1),
            volumeView.heightAnchor.constraint(equalToConstant: 1),
        ])
        refreshSystemControlsAttachment()
    }

    func detach() {
        cancelActiveInteraction(speedBoostReason: .disappear)
        endCustomGestureControlsSuppressionIfNeeded()
        removeHostedViews()
        playerViewController = nil
        viewModel = nil
    }

    private func configureGestureRecognizersIfNeeded() {
        let hostedView = hostingController.view!
        if doubleTapGesture.view == nil {
            doubleTapGesture.numberOfTapsRequired = 2
            doubleTapGesture.cancelsTouchesInView = false
            doubleTapGesture.delaysTouchesBegan = false
            doubleTapGesture.delegate = self
            hostedView.addGestureRecognizer(doubleTapGesture)
        }

        if panGesture.view == nil {
            panGesture.maximumNumberOfTouches = 1
            panGesture.cancelsTouchesInView = true
            panGesture.delaysTouchesBegan = false
            panGesture.delaysTouchesEnded = false
            panGesture.delegate = self
            hostedView.addGestureRecognizer(panGesture)
        }

        if longPressGesture.view == nil {
            longPressGesture.minimumPressDuration = 0.28
            longPressGesture.allowableMovement = 24
            longPressGesture.cancelsTouchesInView = true
            longPressGesture.delaysTouchesBegan = false
            longPressGesture.delaysTouchesEnded = true
            longPressGesture.delegate = self
            hostedView.addGestureRecognizer(longPressGesture)
        }
    }

    private func refreshSystemControlsAttachment() {
        let screen = hostingController.view.window?.windowScene?.screen
        systemControlsController.attach(volumeView: volumeView, screen: screen)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended,
              let view = gesture.view,
              let viewModel,
              !viewModel.isTerminated
        else { return }
        let location = gesture.location(in: view)
        guard PlayerDoubleTapGesturePolicy.shouldTogglePlayback(
            locationX: location.x,
            width: view.bounds.width
        ) else { return }
        viewModel.togglePlayback()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view = gesture.view,
              let viewModel,
              !viewModel.isTerminated
        else {
            cancelActiveInteraction()
            return
        }

        switch gesture.state {
        case .began:
            panStartLocation = gesture.location(in: view)
            lastHorizontalTranslationX = 0
            currentSeekProgress = nil
            panMode = isSpeedBoostGestureActive ? .ignored : .undecided
        case .changed:
            guard !isSpeedBoostGestureActive else { return }
            let translation = gesture.translation(in: view)
            let velocity = gesture.velocity(in: view)
            if case .undecided = panMode {
                beginPanInteractionIfNeeded(
                    translation: translation,
                    startLocation: panStartLocation ?? gesture.location(in: view),
                    size: view.bounds.size,
                    viewModel: viewModel
                )
            }
            updatePanInteraction(
                translation: translation,
                velocity: velocity,
                size: view.bounds.size,
                viewModel: viewModel
            )
        case .ended:
            finishPanInteraction(commitsSeek: !isSpeedBoostGestureActive)
        case .cancelled, .failed:
            finishPanInteraction(commitsSeek: false)
        default:
            break
        }
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        handleLongPressState(gesture.state)
    }

    private func handleLongPressState(_ state: UIGestureRecognizer.State) {
        guard let viewModel, !viewModel.isTerminated else {
            cancelActiveInteraction(speedBoostReason: .terminated)
            return
        }

        switch state {
        case .began:
            guard !isSpeedBoostGestureActive, !isPanInteractionActive else { return }
            let isSurfacePlaying = viewModel.isPlaying || (playerViewController?.player?.rate ?? 0) > 0
            let didBegin = speedBoostModel.beginIfNeeded(
                playerViewModel: viewModel,
                isSurfacePlaying: isSurfacePlaying,
                hidePlaybackControls: { [weak self] in
                    self?.beginCustomGestureControlsSuppressionIfNeeded()
                }
            )
            isSpeedBoostGestureActive = didBegin
            if didBegin {
                beginCustomGestureControlsSuppressionIfNeeded()
                if case .undecided = panMode {
                    panMode = .ignored
                }
            }
        case .ended:
            endSpeedBoostIfActive(reason: .gestureEnded)
        case .cancelled, .failed:
            endSpeedBoostIfActive(reason: .systemInterrupted)
        default:
            break
        }
    }

    private func beginPanInteractionIfNeeded(
        translation: CGPoint,
        startLocation: CGPoint,
        size: CGSize,
        viewModel: PlayerStateViewModel
    ) {
        guard let axis = PlayerSurfaceGestureAxisPolicy.axis(
            translation: CGSize(width: translation.x, height: translation.y),
            activationDistance: 8,
            dominanceRatio: 3
        ) else { return }

        switch axis {
        case .horizontal:
            guard viewModel.canSeek,
                  let duration = resolvedDuration(for: viewModel),
                  duration > 0,
                  size.width > 0
            else {
                panMode = .ignored
                return
            }
            let startProgress = min(
                max(viewModel.playbackClock.currentTime / duration, 0),
                1
            )
            panMode = .seeking(duration: duration)
            lastHorizontalTranslationX = 0
            currentSeekProgress = startProgress
            beginCustomGestureControlsSuppressionIfNeeded()
            viewModel.playbackClock.updateSeekPreview(progress: startProgress, force: true)
            viewModel.beginUserScrubInteraction(source: .surfaceGesture)
        case .vertical:
            guard let target = PlayerSurfaceVerticalAdjustmentPolicy.target(
                startLocationX: startLocation.x,
                width: size.width
            ) else {
                panMode = .ignored
                return
            }
            refreshSystemControlsAttachment()
            guard let initialValue = systemValue(for: target) else {
                panMode = .ignored
                return
            }
            panMode = .adjusting(target: target, initialValue: initialValue)
            beginCustomGestureControlsSuppressionIfNeeded()
        }
    }

    private func updatePanInteraction(
        translation: CGPoint,
        velocity: CGPoint,
        size: CGSize,
        viewModel: PlayerStateViewModel
    ) {
        switch panMode {
        case let .seeking(duration):
            guard size.width > 0 else { return }
            let stepDX = translation.x - lastHorizontalTranslationX
            lastHorizontalTranslationX = translation.x
            let baseProgress = currentSeekProgress ?? viewModel.playbackClock.progress
            let secondsPerWidth = PlayerHorizontalSeekSensitivity.effectiveSecondsPerFullWidth(
                duration: duration,
                horizontalVelocity: velocity.x
            )
            let progressDelta = Double(stepDX / size.width) * secondsPerWidth / duration
            let progress = min(max(baseProgress + progressDelta, 0), 1)
            currentSeekProgress = progress
            viewModel.playbackClock.updateSeekPreview(progress: progress)
            hudModel.presentation = .seek(progress: progress, duration: duration)
        case let .adjusting(target, initialValue):
            let value = PlayerSurfaceVerticalAdjustmentPolicy.adjustedValue(
                initialValue: initialValue,
                verticalTranslation: translation.y,
                height: size.height
            )
            applySystemValue(value, for: target)
            hudModel.presentation = .adjustment(target: target, value: value)
        case .undecided, .ignored:
            break
        }
    }

    private func finishPanInteraction(commitsSeek: Bool) {
        if case .seeking = panMode {
            if commitsSeek, let currentSeekProgress {
                viewModel?.seekAfterSliderCommit(to: currentSeekProgress)
            } else {
                viewModel?.cancelUserScrubInteraction()
            }
            viewModel?.playbackClock.clearSeekPreview()
        }
        panMode = .undecided
        panStartLocation = nil
        lastHorizontalTranslationX = 0
        currentSeekProgress = nil
        hudModel.presentation = nil
        if !isSpeedBoostGestureActive && speedBoostModel.phase != .boosting {
            endCustomGestureControlsSuppressionIfNeeded()
        }
    }

    private func cancelActiveInteraction(
        speedBoostReason: PlayerSpeedBoostEndReason = .systemInterrupted
    ) {
        finishPanInteraction(commitsSeek: false)
        endSpeedBoostIfActive(reason: speedBoostReason)
        endCustomGestureControlsSuppressionIfNeeded()
    }

    private func endSpeedBoostIfActive(reason: PlayerSpeedBoostEndReason) {
        guard isSpeedBoostGestureActive || speedBoostModel.phase == .boosting else {
            isSpeedBoostGestureActive = false
            if !isPanInteractionActive {
                endCustomGestureControlsSuppressionIfNeeded()
            }
            return
        }
        isSpeedBoostGestureActive = false
        guard let viewModel else {
            if !isPanInteractionActive {
                endCustomGestureControlsSuppressionIfNeeded()
            }
            return
        }
        speedBoostModel.end(
            reason: reason,
            playerViewModel: viewModel,
            showPlaybackControls: {}
        )
        if !isPanInteractionActive {
            endCustomGestureControlsSuppressionIfNeeded()
        }
    }

    private func beginCustomGestureControlsSuppressionIfNeeded() {
        let wereNativeControlsVisible = Self.areNativeControlsCurrentlyVisible(in: playerViewController)
        if wereNativeControlsVisible {
            didGestureHideVisibleNativeControls = true
        }
        isCustomGestureSuppressingControls = true
        if let onCustomGestureSuppressionChanged {
            onCustomGestureSuppressionChanged(true, didGestureHideVisibleNativeControls)
        } else if didGestureHideVisibleNativeControls,
                  let playerViewController,
                  playerViewController.showsPlaybackControls {
            directRestoredShowsPlaybackControls = true
            playerViewController.showsPlaybackControls = false
        }
    }

    private func endCustomGestureControlsSuppressionIfNeeded() {
        guard isCustomGestureSuppressingControls || directRestoredShowsPlaybackControls != nil else { return }
        isCustomGestureSuppressingControls = false
        didGestureHideVisibleNativeControls = false
        if let onCustomGestureSuppressionChanged {
            onCustomGestureSuppressionChanged(false, false)
        }
        if let restored = directRestoredShowsPlaybackControls {
            directRestoredShowsPlaybackControls = nil
            playerViewController?.showsPlaybackControls = restored
        }
    }

    static func areNativeControlsCurrentlyVisible(in playerViewController: AVPlayerViewController?) -> Bool {
        guard let playerViewController,
              playerViewController.showsPlaybackControls,
              let rootView = playerViewController.viewIfLoaded
        else { return false }
        let overlay = playerViewController.contentOverlayView
        var queue: [UIView] = rootView.subviews.filter { $0 !== overlay }
        var controlsRoot: UIView?
        var animatedViews: [UIView] = []
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if view === overlay { continue }
            let className = NSStringFromClass(type(of: view))
            if controlsRoot == nil,
               className.contains("MobileGlassControls") || className.contains("ChromelessControls") {
                controlsRoot = view
            } else if className.contains("DisplayModeControls")
                || className.contains("TimelineView")
                || className.contains("AuxiliaryControls")
                || className.contains("PlaybackControls") {
                animatedViews.append(view)
            }
            queue.append(contentsOf: view.subviews)
        }
        if let controlsRoot, controlsRoot.isHidden || controlsRoot.alpha <= 0.05 {
            return false
        }
        if !animatedViews.isEmpty {
            return animatedViews.contains { !$0.isHidden && $0.window != nil && $0.alpha > 0.05 }
        }
        return true
    }

    private func shouldBeginSurfaceGesture(
        at location: CGPoint,
        in bounds: CGRect,
        safeAreaInsets: UIEdgeInsets,
        showsPlaybackControls: Bool
    ) -> Bool {
        let leftInset = max(safeAreaInsets.left, 24)
        let rightInset = max(safeAreaInsets.right, 24)
        guard location.x > leftInset && location.x < bounds.width - rightInset else {
            return false
        }
        if showsPlaybackControls {
            let bottomExclusionStart = bounds.height - safeAreaInsets.bottom - 52
            if location.y > bottomExclusionStart {
                return false
            }
        }
        return true
    }

    private func shouldBeginLongPress(
        at location: CGPoint,
        in bounds: CGRect,
        safeAreaInsets: UIEdgeInsets,
        showsPlaybackControls: Bool
    ) -> Bool {
        guard shouldBeginSurfaceGesture(
            at: location,
            in: bounds,
            safeAreaInsets: safeAreaInsets,
            showsPlaybackControls: showsPlaybackControls
        ) else {
            return false
        }
        return !isPanInteractionActive
    }

    private func resolvedDuration(for viewModel: PlayerStateViewModel) -> TimeInterval? {
        viewModel.playbackClock.duration ?? viewModel.displayDuration
    }

    private func systemValue(for target: PlayerSurfaceVerticalAdjustmentTarget) -> Float? {
        switch target {
        case .brightness:
            return systemControlsController.displayBrightness
        case .volume:
            return systemControlsController.outputVolume
        }
    }

    private func applySystemValue(_ value: Float, for target: PlayerSurfaceVerticalAdjustmentTarget) {
        switch target {
        case .brightness:
            systemControlsController.setDisplayBrightness(value)
        case .volume:
            systemControlsController.setOutputVolume(value)
        }
    }

    private func removeHostedViews() {
        volumeView.removeFromSuperview()
        guard hostingController.parent != nil || hostingController.view.superview != nil else { return }
        if hostingController.parent != nil {
            hostingController.willMove(toParent: nil)
        }
        hostingController.view.removeFromSuperview()
        if hostingController.parent != nil {
            hostingController.removeFromParent()
        }
    }
}

extension NativePlayerSurfaceGestureController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let view = gestureRecognizer.view else { return true }
        let location = gestureRecognizer.location(in: view)
        let nativeControlsVisible = Self.areNativeControlsCurrentlyVisible(in: playerViewController)
        if gestureRecognizer === panGesture {
            guard !isSpeedBoostGestureActive else { return false }
            return shouldBeginSurfaceGesture(
                at: location,
                in: view.bounds,
                safeAreaInsets: view.safeAreaInsets,
                showsPlaybackControls: nativeControlsVisible
            )
        }
        if gestureRecognizer === longPressGesture {
            return shouldBeginLongPress(
                at: location,
                in: view.bounds,
                safeAreaInsets: view.safeAreaInsets,
                showsPlaybackControls: nativeControlsVisible
            )
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        let isOwnGesture = gestureRecognizer === panGesture
            || gestureRecognizer === longPressGesture
            || gestureRecognizer === doubleTapGesture
        let isOtherOwnGesture = otherGestureRecognizer === panGesture
            || otherGestureRecognizer === longPressGesture
            || otherGestureRecognizer === doubleTapGesture
        if isOwnGesture && isOtherOwnGesture {
            return gestureRecognizer !== doubleTapGesture && otherGestureRecognizer !== doubleTapGesture
        }
        if gestureRecognizer === doubleTapGesture {
            return true
        }
        return false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var touchedView = touch.view
        while let currentView = touchedView, currentView !== gestureRecognizer.view {
            if currentView is UIControl { return false }
            touchedView = currentView.superview
        }
        return true
    }
}

@MainActor
private final class NativePlayerSurfaceGestureHUDModel: ObservableObject {
    enum Presentation {
        case seek(progress: Double, duration: TimeInterval)
        case adjustment(target: PlayerSurfaceVerticalAdjustmentTarget, value: Float)
    }

    @Published var presentation: Presentation?
}

private struct NativePlayerSurfaceGestureHUD: View {
    @ObservedObject var model: NativePlayerSurfaceGestureHUDModel
    @ObservedObject var speedBoostModel: PlayerSpeedBoostModel

    var body: some View {
        ZStack {
            switch model.presentation {
            case let .seek(progress, duration):
                PlayerSeekPreviewOverlay(
                    presentation: PlayerSeekPreviewPresentation(
                        progress: progress,
                        duration: duration,
                        image: nil,
                        imageAspectRatio: nil,
                        isLoading: false,
                        isCancelPending: false
                    )
                )
            case let .adjustment(target, value):
                PlayerSurfaceVerticalAdjustmentIndicator(target: target, value: value)
            case nil:
                EmptyView()
            }

            if speedBoostModel.isIndicatorVisible {
                PlayerSpeedBoostIndicator(
                    phase: speedBoostModel.phase,
                    displayedRate: speedBoostModel.displayedRate
                )
                .padding(.top, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .accessibilityIdentifier("ui.player.nativeSpeedBoostIndicator")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(false)
    }
}
