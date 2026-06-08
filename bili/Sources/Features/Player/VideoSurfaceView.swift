import AVKit
import Combine
import OSLog
import SwiftUI
import UIKit

struct NativePlayerControllerView: UIViewControllerRepresentable {
    let viewModel: PlayerStateViewModel
    let videoGravity: AVLayerVideoGravity

    init(
        viewModel: PlayerStateViewModel,
        videoGravity: AVLayerVideoGravity
    ) {
        self.viewModel = viewModel
        self.videoGravity = videoGravity
    }

    final class Coordinator {
        weak var viewModel: PlayerStateViewModel?
        weak var playerController: AVPlayerViewController?

        init(viewModel: PlayerStateViewModel) {
            self.viewModel = viewModel
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIViewController(context: Context) -> NativePlayerHostViewController {
        let hostController = NativePlayerHostViewController()
        hostController.videoGravity = videoGravity
        context.coordinator.playerController = hostController.playerController
        viewModel.attachNativePlaybackController(hostController.playerController)
        return hostController
    }

    func updateUIViewController(_ hostController: NativePlayerHostViewController, context: Context) {
        context.coordinator.viewModel = viewModel
        context.coordinator.playerController = hostController.playerController
        hostController.videoGravity = videoGravity
        hostController.view.setNeedsLayout()
        hostController.view.layoutIfNeeded()
        viewModel.attachNativePlaybackController(hostController.playerController)
    }

    static func dismantleUIViewController(_ hostController: NativePlayerHostViewController, coordinator: Coordinator) {
        let controller = coordinator.playerController ?? hostController.playerController
        coordinator.viewModel?.detachNativePlaybackController(controller)
        controller.player = nil
    }
}

final class NativePlayerHostViewController: UIViewController {
    let playerController = AVPlayerViewController()
    var videoGravity: AVLayerVideoGravity = .resizeAspect {
        didSet {
            layoutPlayerController()
        }
    }

    override func loadView() {
        let view = UIView()
        view.backgroundColor = .black
        view.isOpaque = true
        view.clipsToBounds = true
        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        playerController.view.backgroundColor = .black
        playerController.view.isOpaque = true
        addChild(playerController)
        view.addSubview(playerController.view)
        playerController.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPlayerController()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        layoutPlayerController()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        layoutPlayerController()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        AVPlayerLayoutCoordinator.shared.transition(to: size, coordinator: coordinator) { [weak self] in
            self?.layoutPlayerController()
        }
    }

    private func layoutPlayerController() {
        AVPlayerLayoutCoordinator.shared.apply(
            playerController: playerController,
            in: view,
            gravity: videoGravity
        )
    }
}

struct VideoSurfaceView: UIViewRepresentable {
    let viewModel: PlayerStateViewModel
    let prefersNativePlaybackControls: Bool
    let manualFullscreenMode: ManualVideoFullscreenMode?
    let onExitManualFullscreen: (() -> Void)?
    let manualFullscreenOverlay: AnyView?
    let isDanmakuEnabled: Bool
    let onToggleDanmaku: (() -> Void)?
    let onShowDanmakuSettings: (() -> Void)?
    let onPrepareForUserSeek: ((Double) -> Void)?

    func makeUIView(context _: Context) -> VideoSurfaceContainerView {
        let view = VideoSurfaceContainerView()
        view.backgroundColor = .black
        view.onBoundsChange = { [weak viewModel] in
            viewModel?.refreshSurfaceLayout()
        }
        view.onFullscreenTransitionEnd = { [weak viewModel] in
            viewModel?.recoverSurfaceAfterHostFullscreenTransition()
        }
        view.setPlayerViewModel(viewModel, prefersNativePlaybackControls: prefersNativePlaybackControls)
        view.setManualFullscreenOverlay(manualFullscreenOverlay)
        view.setManualFullscreenDanmakuControls(
            isEnabled: isDanmakuEnabled,
            onToggle: onToggleDanmaku,
            onShowSettings: onShowDanmakuSettings
        )
        view.setManualFullscreenSeekPreparation(onPrepareForUserSeek)
        viewModel.attachSurface(view, prefersNativePlaybackControls: prefersNativePlaybackControls)
        view.setManualFullscreenMode(
            manualFullscreenMode,
            onExit: onExitManualFullscreen,
            animated: false
        )
        return view
    }

    func updateUIView(_ uiView: VideoSurfaceContainerView, context _: Context) {
        uiView.onBoundsChange = { [weak viewModel] in
            viewModel?.refreshSurfaceLayout()
        }
        uiView.onFullscreenTransitionEnd = { [weak viewModel] in
            viewModel?.recoverSurfaceAfterHostFullscreenTransition()
        }
        uiView.setPlayerViewModel(viewModel, prefersNativePlaybackControls: prefersNativePlaybackControls)
        uiView.setManualFullscreenOverlay(manualFullscreenOverlay)
        uiView.setManualFullscreenDanmakuControls(
            isEnabled: isDanmakuEnabled,
            onToggle: onToggleDanmaku,
            onShowSettings: onShowDanmakuSettings
        )
        uiView.setManualFullscreenSeekPreparation(onPrepareForUserSeek)
        viewModel.attachSurface(uiView, prefersNativePlaybackControls: prefersNativePlaybackControls)
        uiView.setManualFullscreenMode(
            manualFullscreenMode,
            onExit: onExitManualFullscreen,
            animated: true
        )
    }

    static func dismantleUIView(_ uiView: VideoSurfaceContainerView, coordinator _: ()) {
        guard !ManualVideoFullscreenSession.isActive else { return }
        uiView.setManualFullscreenMode(nil, onExit: nil, animated: false)
        uiView.detachPlayerSurfaceAfterCurrentTransitionIfNeeded()
    }
}

enum ManualVideoFullscreenMode: Equatable {
    case landscape(UIDeviceOrientation)
    case portrait

    var isLandscape: Bool {
        if case .landscape = self { return true }
        return false
    }

    var isPortrait: Bool {
        if case .portrait = self { return true }
        return false
    }
}

final class VideoSurfaceContainerView: UIView, PlayerHostFullscreenExitTarget {
    let drawableView = UIView()
    let nativePlayerViewController = AVPlayerViewController()
    var onBoundsChange: (() -> Void)?
    var onFullscreenTransitionEnd: (() -> Void)?
    private(set) var isInManualFullscreen = false
    private(set) var prefersNativePlaybackControls = true
    private var isNativePlaybackControllerEnabled = false
    private var lastReportedBounds = CGRect.null
    private var fullscreenState: FullscreenState?
    private var isExitingManualFullscreen = false
    private var pendingFullscreenMode: ManualVideoFullscreenMode?
    private var onExitFullscreen: (() -> Void)?
    private var manualFullscreenOverlay: AnyView?
    private var manualFullscreenIsDanmakuEnabled = true
    private var onToggleManualFullscreenDanmaku: (() -> Void)?
    private var onShowManualFullscreenDanmakuSettings: (() -> Void)?
    private var onPrepareManualFullscreenSeek: ((Double) -> Void)?
    private weak var playerViewModel: PlayerStateViewModel?
    private var lastRequestedOrientationMask: UIInterfaceOrientationMask?
    private static let manualFullscreenLayoutAnimationDuration: TimeInterval = 0.28
    private static let manualFullscreenPresentationDuration: TimeInterval = 0.32
    private static let manualFullscreenDismissalDuration: TimeInterval = 0.38
    private static let manualFullscreenAspectBridgeAnimationDuration: TimeInterval = 0.34
    private static let manualFullscreenAspectBridgeExitDuration: TimeInterval = 0.44
    private static let manualFullscreenSnapshotFadeDuration: TimeInterval = 0.14
    private static let manualFullscreenAspectAnimationTolerance: CGFloat = 0.10

    func setPlayerViewModel(_ viewModel: PlayerStateViewModel, prefersNativePlaybackControls: Bool) {
        playerViewModel = viewModel
        fullscreenState?.fullscreenController.viewModel = viewModel
        self.prefersNativePlaybackControls = prefersNativePlaybackControls
        fullscreenState?.fullscreenController.usesNativePlaybackControls = isNativePlaybackControllerEnabled
        if !prefersNativePlaybackControls {
            setNativePlaybackControllerEnabled(false)
        }
    }

    func setManualFullscreenOverlay(_ overlay: AnyView?) {
        manualFullscreenOverlay = overlay
        fullscreenState?.fullscreenController.setContentOverlay(overlay)
    }

    func setManualFullscreenDanmakuControls(
        isEnabled: Bool,
        onToggle: (() -> Void)?,
        onShowSettings: (() -> Void)?
    ) {
        manualFullscreenIsDanmakuEnabled = isEnabled
        onToggleManualFullscreenDanmaku = onToggle
        onShowManualFullscreenDanmakuSettings = onShowSettings
        fullscreenState?.fullscreenController.setDanmakuControls(
            isEnabled: isEnabled,
            onToggle: onToggle,
            onShowSettings: onShowSettings
        )
    }

    func setManualFullscreenSeekPreparation(_ handler: ((Double) -> Void)?) {
        onPrepareManualFullscreenSeek = handler
        fullscreenState?.fullscreenController.onPrepareForUserSeek = handler
    }

    func makePlaybackTransitionSnapshotView() -> UIView? {
        layoutIfNeeded()
        let fallbackView: UIView = isNativePlaybackControllerEnabled
            ? nativePlayerViewController.view
            : drawableView
        let sourceView = fullscreenState?.contentView
            ?? fallbackView
        return makeTransitionSnapshotView(from: sourceView)
    }

    func detachPlayerSurface() {
        playerViewModel?.detachSurface(self)
        setNativePlaybackControllerEnabled(false)
        playerViewModel = nil
    }

    func detachPlayerSurfaceAfterCurrentTransitionIfNeeded() {
        guard let coordinator = enclosingNavigationController()?.transitionCoordinator else {
            detachPlayerSurface()
            return
        }

        coordinator.animate(alongsideTransition: nil) { [weak self] context in
            guard let self else { return }
            guard !context.isCancelled else { return }
            self.detachPlayerSurface()
        }
    }

    func setNativePlaybackControllerEnabled(_ isEnabled: Bool) {
        let resolvedIsEnabled = isEnabled && prefersNativePlaybackControls
        guard isNativePlaybackControllerEnabled != resolvedIsEnabled else {
            if resolvedIsEnabled {
                installNativePlayerViewControllerIfPossible()
            }
            fullscreenState?.fullscreenController.usesNativePlaybackControls = resolvedIsEnabled
            return
        }

        isNativePlaybackControllerEnabled = resolvedIsEnabled
        fullscreenState?.fullscreenController.usesNativePlaybackControls = resolvedIsEnabled
        if resolvedIsEnabled {
            configureNativePlayerViewController()
            installNativePlayerViewControllerIfPossible()
        } else {
            removeNativePlayerViewController()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isOpaque = true
        clipsToBounds = true
        drawableView.backgroundColor = .black
        drawableView.isOpaque = true
        drawableView.clipsToBounds = true
        addSubview(drawableView)
        configureNativePlayerViewController()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if fullscreenState == nil {
            drawableView.frame = bounds
        }
        if isNativePlaybackControllerEnabled {
            installNativePlayerViewControllerIfPossible()
            applyNativePlayerLayout()
        }
        guard bounds.width > 1, bounds.height > 1 else { return }
        guard lastReportedBounds.size != bounds.size else { return }
        lastReportedBounds = bounds
        onBoundsChange?()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            removeNativePlayerViewController()
        } else if isNativePlaybackControllerEnabled {
            installNativePlayerViewControllerIfPossible()
        }
        guard let pendingFullscreenMode else { return }
        self.pendingFullscreenMode = nil
        setManualFullscreenMode(pendingFullscreenMode, onExit: onExitFullscreen, animated: false)
    }

    private func enclosingNavigationController() -> UINavigationController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let viewController = current as? UIViewController,
               let navigationController = viewController.navigationController {
                return navigationController
            }
            responder = current.next
        }
        return nil
    }

    func setManualFullscreenMode(
        _ mode: ManualVideoFullscreenMode?,
        onExit: (() -> Void)?,
        animated: Bool
    ) {
        onExitFullscreen = onExit

        guard !isNativePlaybackControllerEnabled else {
            PlayerMetricsLog.logger.error("manualFullscreenSetRejected reason=nativePlaybackControllerEnabled")
            pendingFullscreenMode = nil
            if fullscreenState != nil {
                exitManualFullscreen(animated: animated)
            }
            return
        }

        guard let mode else {
            pendingFullscreenMode = nil
            exitManualFullscreen(animated: animated)
            return
        }

        guard window != nil || UIApplication.shared.biliKeyWindow != nil else {
            PlayerMetricsLog.logger.error("manualFullscreenSetDeferred reason=noWindow")
            pendingFullscreenMode = mode
            return
        }

        enterOrUpdateManualFullscreen(mode: mode, animated: animated)
    }

    @objc private func handleExitFullscreenButton() {
        onExitFullscreen?()
    }

    private func enterOrUpdateManualFullscreen(mode: ManualVideoFullscreenMode, animated: Bool) {
        guard fullscreenState != nil || !ManualVideoFullscreenSession.isActive else {
            PlayerMetricsLog.logger.error("manualFullscreenEnterRejected reason=sessionAlreadyActive")
            pendingFullscreenMode = nil
            return
        }

        guard let sourceWindow = window ?? UIApplication.shared.biliKeyWindow,
              sourceWindow.windowScene != nil
        else {
            PlayerMetricsLog.logger.error("manualFullscreenEnterRejected reason=noSourceWindow")
            return
        }
        requestGeometry(for: sourceWindow, mode: mode)

        if fullscreenState == nil {
            superview?.layoutIfNeeded()
            layoutIfNeeded()
            guard let originalSuperview = drawableView.superview else {
                PlayerMetricsLog.logger.error("manualFullscreenEnterRejected reason=noDrawableSuperview")
                return
            }
            isInManualFullscreen = true
            ManualVideoFullscreenSession.begin(retaining: self)
            PlayerMetricsLog.logger.info("manualFullscreenEnterBegin")

            let originalFrame = drawableView.frame
            let originalIndex = originalSuperview.subviews.firstIndex(of: drawableView) ?? originalSuperview.subviews.count
            let fullscreenController = ManualVideoFullscreenViewController()
            fullscreenController.viewModel = playerViewModel
            fullscreenController.usesNativePlaybackControls = isNativePlaybackControllerEnabled
            fullscreenController.mode = mode
            fullscreenController.setContentOverlay(manualFullscreenOverlay)
            fullscreenController.setDanmakuControls(
                isEnabled: manualFullscreenIsDanmakuEnabled,
                onToggle: onToggleManualFullscreenDanmaku,
                onShowSettings: onShowManualFullscreenDanmakuSettings
            )
            fullscreenController.onPrepareForUserSeek = onPrepareManualFullscreenSeek
            fullscreenController.onDismissDragChanged = { [weak self] translationY, progress in
                self?.updateManualFullscreenDismissDrag(translationY: translationY, progress: progress)
            }
            fullscreenController.onDismissDragCancelled = { [weak self] in
                self?.cancelManualFullscreenDismissDrag()
            }

            let fullscreenSuperview = sourceWindow.rootViewController?.view ?? sourceWindow
            fullscreenController.view.frame = fullscreenSuperview.bounds
            fullscreenController.view.translatesAutoresizingMaskIntoConstraints = false
            if let parentController = sourceWindow.rootViewController {
                parentController.addChild(fullscreenController)
                fullscreenSuperview.addSubview(fullscreenController.view)
                NSLayoutConstraint.activate([
                    fullscreenController.view.leadingAnchor.constraint(equalTo: fullscreenSuperview.leadingAnchor),
                    fullscreenController.view.trailingAnchor.constraint(equalTo: fullscreenSuperview.trailingAnchor),
                    fullscreenController.view.topAnchor.constraint(equalTo: fullscreenSuperview.topAnchor),
                    fullscreenController.view.bottomAnchor.constraint(equalTo: fullscreenSuperview.bottomAnchor)
                ])
                fullscreenSuperview.layoutIfNeeded()
                fullscreenController.didMove(toParent: parentController)
            } else {
                fullscreenSuperview.addSubview(fullscreenController.view)
                NSLayoutConstraint.activate([
                    fullscreenController.view.leadingAnchor.constraint(equalTo: fullscreenSuperview.leadingAnchor),
                    fullscreenController.view.trailingAnchor.constraint(equalTo: fullscreenSuperview.trailingAnchor),
                    fullscreenController.view.topAnchor.constraint(equalTo: fullscreenSuperview.topAnchor),
                    fullscreenController.view.bottomAnchor.constraint(equalTo: fullscreenSuperview.bottomAnchor)
                ])
                fullscreenSuperview.layoutIfNeeded()
            }
            fullscreenController.refreshSystemChrome()

            let startFrameInSourceWindow = originalSuperview.convert(originalFrame, to: sourceWindow)
            let startFrame = sourceWindow.convert(startFrameInSourceWindow, to: fullscreenSuperview)
            let entrySnapshotView = makeTransitionSnapshotView(from: drawableView)
            let backdropView = UIView(frame: fullscreenController.view.bounds)
            backdropView.backgroundColor = .black
            backdropView.isUserInteractionEnabled = false
            backdropView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

            let contentView = UIView()
            contentView.backgroundColor = .black
            contentView.isOpaque = true
            contentView.clipsToBounds = true
            contentView.layer.backgroundColor = UIColor.black.cgColor
            let fullscreenBounds = fullscreenController.view.bounds
            let startsFromInlineFrame = animated
                && startFrame.width > 1
                && startFrame.height > 1
            fullscreenController.prepareForEnterAnimation(animated: startsFromInlineFrame)
            if startsFromInlineFrame {
                contentView.frame = startFrame
            } else {
                contentView.bounds = CGRect(origin: .zero, size: fullscreenBounds.size)
                contentView.center = CGPoint(x: fullscreenBounds.midX, y: fullscreenBounds.midY)
            }

            fullscreenController.view.addSubview(backdropView)
            fullscreenController.view.addSubview(contentView)
            contentView.addSubview(drawableView)
            drawableView.frame = contentView.bounds
            playerViewModel?.refreshSurfaceLayout()
            fullscreenController.bringPlayerToFront()

            fullscreenState = FullscreenState(
                sourceWindow: sourceWindow,
                presentingController: nil,
                fullscreenController: fullscreenController,
                fullscreenSuperview: fullscreenSuperview,
                originalSuperview: originalSuperview,
                originalIndex: originalIndex,
                originalFrame: originalFrame,
                originalWindowFrame: startFrame,
                backdropView: backdropView,
                contentView: contentView,
                transitionDriver: nil,
                mode: mode
            )
            fullscreenState?.isAwaitingEntryOverlayTransition = startsFromInlineFrame
            if let fullscreenState {
                installManualFullscreenTransitionSnapshot(entrySnapshotView, in: fullscreenState)
            }
            fullscreenController.onExit = { [weak self] in
                self?.handleExitFullscreenButton()
            }
            fullscreenController.onLayout = { [weak self] in
                self?.applyManualFullscreenLayout(animated: false)
            }
            playerViewModel?.setHostFullscreenActive(true, exitTarget: self)
            playerViewModel?.recoverSurfaceAfterHostFullscreenTransition()
            requestGeometry(for: sourceWindow, mode: mode)
            applyManualFullscreenLayout(animated: startsFromInlineFrame)
            if let fullscreenState {
                scheduleManualFullscreenLayoutStabilization(for: fullscreenState)
            }
        }

        if fullscreenState?.mode != mode {
            requestGeometry(for: fullscreenState?.sourceWindow ?? sourceWindow, mode: mode)
            fullscreenState?.mode = mode
            fullscreenState?.fullscreenController.mode = mode
            if let fullscreenState {
                scheduleManualFullscreenLayoutStabilization(for: fullscreenState)
            }
        }
        playerViewModel?.setHostFullscreenActive(true, exitTarget: self)
        requestGeometry(for: fullscreenState?.sourceWindow ?? sourceWindow, mode: mode)
        applyManualFullscreenLayout(animated: animated)
    }

    private func exitManualFullscreen(animated: Bool) {
        guard let state = fullscreenState else { return }
        guard !isExitingManualFullscreen else { return }
        isExitingManualFullscreen = true
        if !animated {
            requestPortraitGeometry(for: state.sourceWindow)
        }

        let restoreIntoOriginalHierarchy = { [weak self] shouldFinishTransition in
            guard let self else { return }
            let originalSuperview = state.originalSuperview ?? self
            let index = min(state.originalIndex, originalSuperview.subviews.count)
            originalSuperview.insertSubview(self.drawableView, at: index)
            self.drawableView.transform = .identity
            self.drawableView.frame = originalSuperview === self ? self.bounds : state.originalFrame
            state.fullscreenController.view.transform = .identity
            state.fullscreenController.onExit = nil
            state.fullscreenController.onDismissDragChanged = nil
            state.fullscreenController.onDismissDragCancelled = nil
            state.fullscreenController.viewModel = nil
            state.layoutStabilizationTask?.cancel()
            state.layoutStabilizationTask = nil
            if state.fullscreenController.presentingViewController == nil,
               state.fullscreenController.parent != nil || state.fullscreenController.view.superview != nil {
                state.fullscreenController.willMove(toParent: nil)
                state.fullscreenController.view.removeFromSuperview()
                state.fullscreenController.removeFromParent()
            }
            self.fullscreenState = nil
            self.isExitingManualFullscreen = false
            self.lastRequestedOrientationMask = nil
            self.isInManualFullscreen = false
            ManualVideoFullscreenSession.end(retaining: self)
            self.playerViewModel?.setHostFullscreenActive(false, exitTarget: nil)
            self.playerViewModel?.recoverSurfaceAfterHostFullscreenTransition()
            self.requestPortraitGeometry(for: state.sourceWindow)
            if shouldFinishTransition {
                self.finishManualFullscreenTransition()
            }
        }

        guard animated else {
            guard state.fullscreenController.presentingViewController != nil else {
                restoreIntoOriginalHierarchy(true)
                return
            }
            state.fullscreenController.dismiss(animated: false) {
                restoreIntoOriginalHierarchy(true)
            }
            return
        }

        state.fullscreenController.prepareForExitAnimation(animated: true)
        state.fullscreenController.view.isUserInteractionEnabled = false
        state.fullscreenController.view.backgroundColor = .clear

        if state.fullscreenController.presentingViewController != nil,
           let transitionDriver = state.transitionDriver {
            transitionDriver.prepareForDismissal(
                targetFrameProvider: { [weak self, weak state] in
                    guard let self, let state else { return nil }
                    return self.manualFullscreenRestorationWindowFrame(for: state)
                },
                onWillFinish: {
                    restoreIntoOriginalHierarchy(false)
                },
                onFinished: { [weak self] in
                    self?.finishManualFullscreenTransition()
                }
            )
            DispatchQueue.main.async { [weak fullscreenController = state.fullscreenController] in
                fullscreenController?.dismiss(animated: true)
            }
            return
        }

        let animateExit = { [weak self] in
            guard let self, self.fullscreenState === state else { return }
            let targetFrame = self.manualFullscreenRestorationFrame(for: state)
            guard targetFrame.width > 1, targetFrame.height > 1 else {
                restoreIntoOriginalHierarchy(true)
                return
            }

            let currentFrame = state.contentView.layer.presentation()?.frame ?? state.contentView.frame
            let shouldAnimateContentGeometry = Self.aspectRatioDelta(
                currentFrame.size,
                targetFrame.size
            ) <= Self.manualFullscreenAspectAnimationTolerance
            UIView.performWithoutAnimation {
                state.contentView.transform = .identity
                state.contentView.frame = currentFrame
                self.drawableView.frame = state.contentView.bounds
                self.playerViewModel?.refreshSurfaceLayout()
                state.fullscreenController.view.layoutIfNeeded()
            }

            guard shouldAnimateContentGeometry else {
                self.animateManualFullscreenExitWithAspectBridge(
                    state: state,
                    currentFrame: currentFrame,
                    targetFrame: targetFrame,
                    restoreIntoOriginalHierarchy: restoreIntoOriginalHierarchy
                )
                return
            }

            let timing = UISpringTimingParameters(
                mass: 1,
                stiffness: 360,
                damping: 34,
                initialVelocity: .zero
            )
            let animator = UIViewPropertyAnimator(duration: 0.28, timingParameters: timing)
            animator.isInterruptible = true
            animator.scrubsLinearly = false
            animator.addAnimations {
                state.backdropView.alpha = 0
                state.contentView.frame = targetFrame
                self.drawableView.frame = state.contentView.bounds
                self.playerViewModel?.refreshSurfaceLayout()
                state.fullscreenController.view.layoutIfNeeded()
            }
            animator.addCompletion { _ in
                restoreIntoOriginalHierarchy(true)
            }
            animator.startAnimation()
        }

        DispatchQueue.main.async(execute: animateExit)
    }

    private func manualFullscreenRestorationFrame(for state: FullscreenState) -> CGRect {
        guard let originalSuperview = state.originalSuperview else {
            return state.originalWindowFrame
        }
        let fullscreenSuperview = state.fullscreenSuperview
            ?? state.fullscreenController.view.superview
            ?? state.sourceWindow.rootViewController?.view
            ?? state.sourceWindow

        originalSuperview.superview?.setNeedsLayout()
        originalSuperview.superview?.layoutIfNeeded()
        originalSuperview.setNeedsLayout()
        originalSuperview.layoutIfNeeded()
        fullscreenSuperview.setNeedsLayout()
        fullscreenSuperview.layoutIfNeeded()

        let bounds = originalSuperview.bounds
        guard bounds.width > 1, bounds.height > 1 else {
            return state.originalWindowFrame
        }
        return originalSuperview.convert(bounds, to: fullscreenSuperview)
    }

    private func manualFullscreenRestorationWindowFrame(for state: FullscreenState) -> CGRect {
        guard let originalSuperview = state.originalSuperview else {
            return state.originalWindowFrame
        }

        originalSuperview.superview?.setNeedsLayout()
        originalSuperview.superview?.layoutIfNeeded()
        originalSuperview.setNeedsLayout()
        originalSuperview.layoutIfNeeded()
        state.sourceWindow.layoutIfNeeded()

        let bounds = originalSuperview.bounds
        guard bounds.width > 1, bounds.height > 1 else {
            return state.originalWindowFrame
        }
        return originalSuperview.convert(bounds, to: state.sourceWindow)
    }

    private func updateManualFullscreenDismissDrag(translationY: CGFloat, progress: CGFloat) {
        guard let state = fullscreenState else { return }
        let clampedProgress = min(max(progress, 0), 1)
        let scale = 1 - clampedProgress * 0.065
        let transform = CGAffineTransform(translationX: 0, y: translationY)
            .scaledBy(x: scale, y: scale)
        state.contentView.transform = transform
        state.backdropView.alpha = max(0.42, 1 - clampedProgress * 0.52)
        state.fullscreenController.updateDismissTransition(progress: clampedProgress)
    }

    private func cancelManualFullscreenDismissDrag() {
        guard let state = fullscreenState else { return }
        state.fullscreenController.cancelDismissTransition(animated: true)
        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.82,
            initialSpringVelocity: 0.7,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            state.contentView.transform = .identity
            state.backdropView.alpha = 1
        }
    }

    private func applyManualFullscreenLayout(animated: Bool) {
        guard let state = fullscreenState else { return }
        guard !isExitingManualFullscreen else { return }

        let bounds = resolvedManualFullscreenBounds(for: state)
        applyManualFullscreenViewportIfNeeded(for: state, targetBounds: bounds)
        let needsLayout = state.lastAppliedBounds.size != bounds.size
            || state.contentView.bounds.size != bounds.size
            || state.backdropView.frame.size != bounds.size

        guard needsLayout else {
            guard !state.isRunningAspectBridgeTransition else { return }
            UIView.performWithoutAnimation {
                self.drawableView.transform = .identity
                self.drawableView.frame = state.contentView.bounds
                self.playerViewModel?.refreshSurfaceLayout()
                state.fullscreenController.refreshFullscreenLayout(flush: false)
            }
            if state.isAwaitingEntryOverlayTransition {
                state.isAwaitingEntryOverlayTransition = false
                state.fullscreenController.finishEnterAnimation(animated: animated)
            }
            onFullscreenTransitionEnd?()
            return
        }

        let applyLayout = {
            state.lastAppliedBounds = bounds
            state.backdropView.frame = bounds
            state.contentView.transform = .identity
            state.contentView.bounds = CGRect(origin: .zero, size: bounds.size)
            state.contentView.center = CGPoint(x: bounds.midX, y: bounds.midY)
            self.drawableView.transform = .identity
            self.drawableView.frame = state.contentView.bounds
            state.transitionSnapshotView?.frame = state.contentView.bounds
            self.playerViewModel?.refreshSurfaceLayout()
            state.fullscreenController.view.bringSubviewToFront(state.contentView)
            if let snapshotView = state.transitionSnapshotView {
                state.contentView.bringSubviewToFront(snapshotView)
            }
            state.fullscreenController.bringPlayerToFront()
            state.fullscreenController.refreshFullscreenLayout(flush: false)
            state.fullscreenController.refreshSystemChrome()
        }

        let inheritedAnimationDuration = UIView.inheritedAnimationDuration
        let currentLayoutSize = state.lastAppliedBounds.isNull
            ? state.contentView.bounds.size
            : state.lastAppliedBounds.size
        let changesEstablishedAspectRatio = !state.lastAppliedBounds.isNull
            && Self.aspectRatioDelta(
                currentLayoutSize,
                bounds.size
            ) > Self.manualFullscreenAspectAnimationTolerance
        let shouldAnimate = (animated || inheritedAnimationDuration > 0)
            && !changesEstablishedAspectRatio

        let finish = { [weak self] in
            guard let self else { return }
            self.fadeOutManualFullscreenTransitionSnapshot(for: state)
            if state.isAwaitingEntryOverlayTransition {
                state.isAwaitingEntryOverlayTransition = false
                state.fullscreenController.finishEnterAnimation(animated: shouldAnimate)
            }
            self.finishManualFullscreenTransition()
        }

        if changesEstablishedAspectRatio, state.isRunningAspectBridgeTransition {
            UIView.performWithoutAnimation {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                applyLayout()
                state.fullscreenController.view.layoutIfNeeded()
                CATransaction.commit()
            }
            return
        }

        if changesEstablishedAspectRatio, !state.isRunningAspectBridgeTransition {
            let currentFrame = state.contentView.layer.presentation()?.frame ?? state.contentView.frame
            let duration = inheritedAnimationDuration > 0
                ? inheritedAnimationDuration
                : Self.manualFullscreenAspectBridgeAnimationDuration
            animateManualFullscreenLayoutWithAspectBridge(
                state: state,
                currentFrame: currentFrame,
                targetBounds: bounds,
                duration: duration,
                applyLayout: applyLayout,
                finish: finish
            )
            return
        }

        if shouldAnimate {
            installManualFullscreenTransitionSnapshotIfNeeded(for: state)
        } else if changesEstablishedAspectRatio {
            clearManualFullscreenTransitionSnapshot(for: state)
        }

        if shouldAnimate {
            let duration = inheritedAnimationDuration > 0
                ? inheritedAnimationDuration
                : Self.manualFullscreenLayoutAnimationDuration
            UIView.animate(
                withDuration: duration,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]
            ) {
                applyLayout()
                state.fullscreenController.view.layoutIfNeeded()
            } completion: { _ in
                finish()
            }
        } else {
            UIView.performWithoutAnimation {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                applyLayout()
                state.fullscreenController.view.layoutIfNeeded()
                CATransaction.commit()
            }
            finish()
        }
    }

    private func resolvedManualFullscreenBounds(for state: FullscreenState) -> CGRect {
        let viewBounds = state.fullscreenController.view.bounds
        guard state.mode.isLandscape else { return viewBounds }

        let windowSize = state.sourceWindow.bounds.size
        let rootSize = state.sourceWindow.rootViewController?.view.bounds.size ?? windowSize
        let candidateSizes = [viewBounds.size, windowSize, rootSize]
        let landscapeSize = candidateSizes.first { $0.width > $0.height && $0.width > 1 && $0.height > 1 }
            ?? CGSize(
                width: max(viewBounds.width, viewBounds.height, windowSize.width, windowSize.height),
                height: min(
                    max(min(viewBounds.width, viewBounds.height), 1),
                    max(min(windowSize.width, windowSize.height), 1)
                )
            )
        return CGRect(origin: .zero, size: landscapeSize)
    }

    private func applyManualFullscreenViewportIfNeeded(
        for state: FullscreenState,
        targetBounds: CGRect
    ) {
        guard let superview = state.fullscreenController.view.superview else { return }
        let superviewBounds = superview.bounds
        let shouldCompensatePortraitRoot = state.mode.isLandscape
            && superviewBounds.height > superviewBounds.width
            && targetBounds.width > targetBounds.height

        guard shouldCompensatePortraitRoot else {
            if state.fullscreenController.view.transform != .identity {
                state.fullscreenController.view.transform = .identity
            }
            return
        }

        let angle: CGFloat
        switch state.mode.interfaceOrientation {
        case .landscapeLeft:
            angle = .pi / 2
        case .landscapeRight:
            angle = -.pi / 2
        default:
            angle = 0
        }

        UIView.performWithoutAnimation {
            state.fullscreenController.view.bounds = targetBounds
            state.fullscreenController.view.center = CGPoint(
                x: superviewBounds.midX,
                y: superviewBounds.midY
            )
            state.fullscreenController.view.transform = CGAffineTransform(rotationAngle: angle)
            state.fullscreenController.view.setNeedsLayout()
        }
    }

    private func scheduleManualFullscreenLayoutStabilization(for state: FullscreenState) {
        state.layoutStabilizationTask?.cancel()
        state.layoutStabilizationTask = Task { @MainActor [weak self, weak state] in
            let delays: [UInt64] = [0, 50_000_000, 120_000_000, 240_000_000, 420_000_000]
            for delay in delays {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                } else {
                    await Task.yield()
                }
                guard let self,
                      let state,
                      !Task.isCancelled,
                      self.fullscreenState === state,
                      !self.isExitingManualFullscreen
                else { return }

                state.fullscreenController.view.setNeedsLayout()
                state.fullscreenController.view.layoutIfNeeded()
                state.lastAppliedBounds = .null
                self.applyManualFullscreenLayout(animated: false)
                self.playerViewModel?.recoverSurfaceAfterHostFullscreenTransition()
            }
            state?.layoutStabilizationTask = nil
        }
    }

    private func animateManualFullscreenLayoutWithAspectBridge(
        state: FullscreenState,
        currentFrame: CGRect,
        targetBounds: CGRect,
        duration: TimeInterval,
        applyLayout: @escaping () -> Void,
        finish: @escaping () -> Void
    ) {
        guard let overlaySuperview = state.fullscreenController.view else {
            UIView.performWithoutAnimation {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                applyLayout()
                state.fullscreenController.viewIfLoaded?.layoutIfNeeded()
                CATransaction.commit()
            }
            finish()
            return
        }

        guard currentFrame.width > 1,
              currentFrame.height > 1,
              targetBounds.width > 1,
              targetBounds.height > 1,
              let snapshotView = makeTransitionSnapshotView(
                from: state.contentView,
                layoutMode: .aspectFit
              )
        else {
            UIView.performWithoutAnimation {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                applyLayout()
                overlaySuperview.layoutIfNeeded()
                CATransaction.commit()
            }
            finish()
            return
        }

        state.isRunningAspectBridgeTransition = true
        clearManualFullscreenTransitionSnapshot(for: state)

        let sourceSuperview = state.contentView.superview ?? overlaySuperview
        let startFrame = sourceSuperview.convert(currentFrame, to: overlaySuperview)
        snapshotView.frame = startFrame
        snapshotView.autoresizingMask = []
        snapshotView.isUserInteractionEnabled = false
        snapshotView.alpha = 1
        overlaySuperview.addSubview(snapshotView)
        overlaySuperview.bringSubviewToFront(snapshotView)

        UIView.performWithoutAnimation {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            state.contentView.alpha = 0
            applyLayout()
            overlaySuperview.bringSubviewToFront(snapshotView)
            overlaySuperview.layoutIfNeeded()
            CATransaction.commit()
        }

        let targetFrame = CGRect(origin: .zero, size: targetBounds.size)
        let timing = UICubicTimingParameters(animationCurve: .easeInOut)
        let animator = UIViewPropertyAnimator(duration: duration, timingParameters: timing)
        animator.isInterruptible = false
        animator.addAnimations {
            snapshotView.frame = targetFrame
            snapshotView.layoutIfNeeded()
        }
        animator.addCompletion { [weak state, weak snapshotView] _ in
            guard let state else {
                snapshotView?.removeFromSuperview()
                return
            }
            state.isRunningAspectBridgeTransition = false
            UIView.performWithoutAnimation {
                state.contentView.alpha = 1
            }
            finish()
            guard let snapshotView else { return }
            UIView.animate(
                withDuration: Self.manualFullscreenSnapshotFadeDuration,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]
            ) {
                snapshotView.alpha = 0
            } completion: { _ in
                snapshotView.removeFromSuperview()
            }
        }
        animator.startAnimation()
    }

    private func animateManualFullscreenExitWithAspectBridge(
        state: FullscreenState,
        currentFrame: CGRect,
        targetFrame: CGRect,
        restoreIntoOriginalHierarchy: @escaping (Bool) -> Void
    ) {
        let fallbackFullscreenView = state.fullscreenController.view ?? state.sourceWindow
        let overlaySuperview = state.fullscreenSuperview
            ?? fallbackFullscreenView.superview
            ?? state.sourceWindow.rootViewController?.view
            ?? state.sourceWindow

        guard currentFrame.width > 1,
              currentFrame.height > 1,
              targetFrame.width > 1,
              targetFrame.height > 1,
              let snapshotView = makeTransitionSnapshotView(
                from: state.contentView,
                layoutMode: .softAspectFill(0.78)
              )
        else {
            UIView.animate(
                withDuration: 0.16,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]
            ) {
                state.backdropView.alpha = 0
                state.contentView.alpha = 0
            } completion: { _ in
                restoreIntoOriginalHierarchy(true)
            }
            return
        }

        let sourceSuperview = state.contentView.superview ?? fallbackFullscreenView
        let startFrame = sourceSuperview.convert(currentFrame, to: overlaySuperview)
        let bridgeBackdropView = UIView(frame: overlaySuperview.bounds)
        bridgeBackdropView.backgroundColor = .black
        bridgeBackdropView.alpha = max(0.88, state.backdropView.alpha)
        bridgeBackdropView.isUserInteractionEnabled = false
        bridgeBackdropView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlaySuperview.addSubview(bridgeBackdropView)

        snapshotView.frame = startFrame
        snapshotView.autoresizingMask = []
        snapshotView.isUserInteractionEnabled = false
        snapshotView.alpha = 1
        overlaySuperview.addSubview(snapshotView)
        overlaySuperview.bringSubviewToFront(snapshotView)

        UIView.performWithoutAnimation {
            state.contentView.alpha = 0
            state.backdropView.alpha = 0
        }
        restoreIntoOriginalHierarchy(false)
        overlaySuperview.layoutIfNeeded()
        bridgeBackdropView.frame = overlaySuperview.bounds
        overlaySuperview.bringSubviewToFront(bridgeBackdropView)
        overlaySuperview.bringSubviewToFront(snapshotView)

        let resolvedTargetFrame = Self.resolvedExitTargetFrame(
            fallback: targetFrame,
            originalSuperview: state.originalSuperview,
            overlaySuperview: overlaySuperview
        )
        let timing = UISpringTimingParameters(
            mass: 1,
            stiffness: 190,
            damping: 28,
            initialVelocity: .zero
        )
        let animator = UIViewPropertyAnimator(
            duration: Self.manualFullscreenAspectBridgeExitDuration,
            timingParameters: timing
        )
        animator.isInterruptible = false
        animator.scrubsLinearly = false
        animator.addAnimations {
            bridgeBackdropView.alpha = 0
            snapshotView.frame = resolvedTargetFrame
            snapshotView.layoutIfNeeded()
        }
        animator.addCompletion { [weak self, weak snapshotView, weak bridgeBackdropView] _ in
            guard let self else {
                snapshotView?.removeFromSuperview()
                bridgeBackdropView?.removeFromSuperview()
                return
            }
            guard let snapshotView else {
                bridgeBackdropView?.removeFromSuperview()
                self.finishManualFullscreenTransition()
                return
            }
            UIView.animate(
                withDuration: Self.manualFullscreenSnapshotFadeDuration,
                delay: 0.02,
                options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]
            ) {
                snapshotView.alpha = 0
                bridgeBackdropView?.alpha = 0
            } completion: { _ in
                snapshotView.removeFromSuperview()
                bridgeBackdropView?.removeFromSuperview()
                self.finishManualFullscreenTransition()
            }
        }
        animator.startAnimation()
    }

    private static func resolvedExitTargetFrame(
        fallback: CGRect,
        originalSuperview: UIView?,
        overlaySuperview: UIView
    ) -> CGRect {
        guard let originalSuperview else { return fallback }
        originalSuperview.superview?.layoutIfNeeded()
        originalSuperview.layoutIfNeeded()
        let bounds = originalSuperview.bounds
        guard bounds.width > 1, bounds.height > 1 else { return fallback }
        return originalSuperview.convert(bounds, to: overlaySuperview)
    }

    private func makeTransitionSnapshotView(
        from sourceView: UIView,
        layoutMode: AspectPreservingTransitionSnapshotView.LayoutMode = .aspectFit
    ) -> UIView? {
        sourceView.layoutIfNeeded()

        let sourceBounds = sourceView.bounds
        guard sourceBounds.width > 1, sourceBounds.height > 1 else { return nil }
        let snapshotContentView: UIView
        if let snapshotView = sourceView.snapshotView(afterScreenUpdates: false) {
            snapshotContentView = snapshotView
        } else {
            let format = UIGraphicsImageRendererFormat()
            format.scale = max(sourceView.window?.screen.scale ?? sourceView.traitCollection.displayScale, 1)
            format.opaque = true
            let image = UIGraphicsImageRenderer(size: sourceBounds.size, format: format).image { _ in
                sourceView.drawHierarchy(in: sourceBounds, afterScreenUpdates: false)
            }
            guard image.size.width > 1, image.size.height > 1 else { return nil }
            let imageView = UIImageView(image: image)
            imageView.backgroundColor = .black
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            snapshotContentView = imageView
        }
        snapshotContentView.frame = CGRect(origin: .zero, size: sourceBounds.size)
        snapshotContentView.autoresizingMask = []

        let container = AspectPreservingTransitionSnapshotView(
            sourceSize: sourceBounds.size,
            layoutMode: layoutMode,
            contentView: snapshotContentView
        )
        return container
    }

    private static func aspectRatioDelta(_ lhs: CGSize, _ rhs: CGSize) -> CGFloat {
        guard lhs.width > 1, lhs.height > 1, rhs.width > 1, rhs.height > 1 else {
            return 0
        }
        return abs((lhs.width / lhs.height) - (rhs.width / rhs.height))
    }

    private func installManualFullscreenTransitionSnapshotIfNeeded(for state: FullscreenState) {
        guard state.transitionSnapshotView == nil else { return }
        installManualFullscreenTransitionSnapshot(
            makeTransitionSnapshotView(from: state.contentView),
            in: state
        )
    }

    private func installManualFullscreenTransitionSnapshot(_ snapshotView: UIView?, in state: FullscreenState) {
        guard let snapshotView else { return }
        snapshotView.frame = state.contentView.bounds
        snapshotView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        snapshotView.isUserInteractionEnabled = false
        snapshotView.alpha = 1
        state.transitionSnapshotView?.removeFromSuperview()
        state.transitionSnapshotView = snapshotView
        state.contentView.addSubview(snapshotView)
    }

    private func fadeOutManualFullscreenTransitionSnapshot(for state: FullscreenState) {
        guard let snapshotView = state.transitionSnapshotView else { return }
        UIView.animate(
            withDuration: Self.manualFullscreenSnapshotFadeDuration,
            delay: 0.03,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]
        ) {
            snapshotView.alpha = 0
        } completion: { [weak state] _ in
            guard let state, state.transitionSnapshotView === snapshotView else { return }
            snapshotView.removeFromSuperview()
            state.transitionSnapshotView = nil
        }
    }

    private func clearManualFullscreenTransitionSnapshot(for state: FullscreenState) {
        state.transitionSnapshotView?.removeFromSuperview()
        state.transitionSnapshotView = nil
    }

    private func requestPortraitGeometry(for window: UIWindow) {
        guard let windowScene = window.windowScene else { return }
        guard lastRequestedOrientationMask != .portrait else { return }
        lastRequestedOrientationMask = .portrait
        AppOrientationLock.update(to: .portrait, in: windowScene)
        windowScene.requestGeometryUpdate(
            UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .portrait)
        ) { error in
            PlayerMetricsLog.logger.error("manualFullscreenGeometryRequestFailed mode=portrait error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private func requestGeometry(for window: UIWindow, mode: ManualVideoFullscreenMode) {
        guard let windowScene = window.windowScene else { return }
        let mask = mode.interfaceOrientationMask
        guard lastRequestedOrientationMask != mask else { return }
        lastRequestedOrientationMask = mask
        AppOrientationLock.update(to: mask, in: windowScene)
        windowScene.requestGeometryUpdate(
            UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)
        ) { error in
            PlayerMetricsLog.logger.error("manualFullscreenGeometryRequestFailed mode=\(String(describing: mode), privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        }
    }

    func exitHostFullscreen() {
        onExitFullscreen?()
    }

    private func finishManualFullscreenTransition() {
        onFullscreenTransitionEnd?()
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.playerViewModel?.recoverSurfaceAfterHostFullscreenTransition()
        }
    }

    private func configureNativePlayerViewController() {
        nativePlayerViewController.showsPlaybackControls = true
        nativePlayerViewController.videoGravity = .resizeAspect
        nativePlayerViewController.allowsPictureInPicturePlayback = true
        nativePlayerViewController.canStartPictureInPictureAutomaticallyFromInline = true
        nativePlayerViewController.requiresLinearPlayback = false
        nativePlayerViewController.updatesNowPlayingInfoCenter = false
        nativePlayerViewController.view.backgroundColor = .black
        nativePlayerViewController.view.isOpaque = true
    }

    private func installNativePlayerViewControllerIfPossible() {
        guard isNativePlaybackControllerEnabled else { return }
        guard let parentController = nearestViewController else { return }

        if nativePlayerViewController.parent !== parentController {
            removeNativePlayerViewController()
            parentController.addChild(nativePlayerViewController)
            drawableView.insertSubview(nativePlayerViewController.view, at: 0)
            nativePlayerViewController.didMove(toParent: parentController)
        } else if nativePlayerViewController.view.superview !== drawableView {
            nativePlayerViewController.view.removeFromSuperview()
            drawableView.insertSubview(nativePlayerViewController.view, at: 0)
        }

        applyNativePlayerLayout()
        nativePlayerViewController.view.isHidden = false
    }

    private func applyNativePlayerLayout() {
        AVPlayerLayoutCoordinator.shared.apply(
            playerController: nativePlayerViewController,
            in: drawableView,
            gravity: nativePlayerViewController.videoGravity
        )
    }

    private func removeNativePlayerViewController() {
        guard nativePlayerViewController.parent != nil || nativePlayerViewController.view.superview != nil else { return }
        nativePlayerViewController.willMove(toParent: nil)
        nativePlayerViewController.view.removeFromSuperview()
        nativePlayerViewController.removeFromParent()
    }

    private final class FullscreenState {
        let sourceWindow: UIWindow
        weak var presentingController: UIViewController?
        let fullscreenController: ManualVideoFullscreenViewController
        weak var fullscreenSuperview: UIView?
        weak var originalSuperview: UIView?
        let originalIndex: Int
        let originalFrame: CGRect
        let originalWindowFrame: CGRect
        let backdropView: UIView
        let contentView: UIView
        let transitionDriver: ManualVideoFullscreenTransitioningDelegate?
        var mode: ManualVideoFullscreenMode
        var lastAppliedBounds = CGRect.null
        var transitionSnapshotView: UIView?
        var isRunningAspectBridgeTransition = false
        var isAwaitingEntryOverlayTransition = false
        var layoutStabilizationTask: Task<Void, Never>?

        init(
            sourceWindow: UIWindow,
            presentingController: UIViewController?,
            fullscreenController: ManualVideoFullscreenViewController,
            fullscreenSuperview: UIView,
            originalSuperview: UIView,
            originalIndex: Int,
            originalFrame: CGRect,
            originalWindowFrame: CGRect,
            backdropView: UIView,
            contentView: UIView,
            transitionDriver: ManualVideoFullscreenTransitioningDelegate?,
            mode: ManualVideoFullscreenMode
        ) {
            self.sourceWindow = sourceWindow
            self.presentingController = presentingController
            self.fullscreenController = fullscreenController
            self.fullscreenSuperview = fullscreenSuperview
            self.originalSuperview = originalSuperview
            self.originalIndex = originalIndex
            self.originalFrame = originalFrame
            self.originalWindowFrame = originalWindowFrame
            self.backdropView = backdropView
            self.contentView = contentView
            self.transitionDriver = transitionDriver
            self.mode = mode
        }
    }
}

private extension UIView {
    var nearestViewController: UIViewController? {
        var responder: UIResponder? = self
        while let currentResponder = responder {
            if let viewController = currentResponder as? UIViewController {
                return viewController
            }
            responder = currentResponder.next
        }
        return nil
    }
}

@MainActor
private final class AspectPreservingTransitionSnapshotView: UIView {
    enum LayoutMode: Equatable {
        case aspectFit
        case aspectFill
        case softAspectFill(CGFloat)
    }

    private let sourceSize: CGSize
    private let layoutMode: LayoutMode
    private let contentView: UIView

    init(sourceSize: CGSize, layoutMode: LayoutMode, contentView: UIView) {
        self.sourceSize = sourceSize
        self.layoutMode = layoutMode
        self.contentView = contentView
        super.init(frame: CGRect(origin: .zero, size: sourceSize))
        backgroundColor = .black
        isOpaque = true
        clipsToBounds = true
        addSubview(contentView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.frame = Self.aspectPreservingFrame(
            sourceSize: sourceSize,
            bounds: bounds,
            layoutMode: layoutMode,
            scale: max(window?.screen.scale ?? traitCollection.displayScale, 1)
        )
    }

    private static func aspectPreservingFrame(
        sourceSize: CGSize,
        bounds: CGRect,
        layoutMode: LayoutMode,
        scale: CGFloat
    ) -> CGRect {
        guard sourceSize.width > 1,
              sourceSize.height > 1,
              bounds.width > 1,
              bounds.height > 1
        else {
            return bounds
        }

        let widthScale = bounds.width / sourceSize.width
        let heightScale = bounds.height / sourceSize.height
        let minScale = min(widthScale, heightScale)
        let maxScale = max(widthScale, heightScale)
        let fittedScale: CGFloat
        switch layoutMode {
        case .aspectFit:
            fittedScale = minScale
        case .aspectFill:
            fittedScale = maxScale
        case .softAspectFill(let bias):
            let clampedBias = min(max(bias, 0), 1)
            fittedScale = minScale + (maxScale - minScale) * clampedBias
        }
        let fittedSize = CGSize(
            width: sourceSize.width * fittedScale,
            height: sourceSize.height * fittedScale
        )
        let rawFrame = CGRect(
            x: bounds.midX - fittedSize.width / 2,
            y: bounds.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
        guard scale > 0 else { return rawFrame }
        return CGRect(
            x: (rawFrame.origin.x * scale).rounded() / scale,
            y: (rawFrame.origin.y * scale).rounded() / scale,
            width: (rawFrame.size.width * scale).rounded() / scale,
            height: (rawFrame.size.height * scale).rounded() / scale
        )
    }
}

private final class ManualVideoFullscreenTransitioningDelegate: NSObject, UIViewControllerTransitioningDelegate {
    private weak var sourceWindow: UIWindow?
    private weak var contentView: UIView?
    private weak var backdropView: UIView?
    private weak var drawableView: UIView?
    private let presentationStartFrameInWindow: CGRect
    private let presentationDuration: TimeInterval
    private let dismissalDuration: TimeInterval
    private var dismissalTargetFrameProvider: (() -> CGRect?)?
    private var onDismissalAnimationWillFinish: (() -> Void)?
    private var onDismissalAnimationFinished: (() -> Void)?

    init(
        sourceWindow: UIWindow,
        contentView: UIView,
        backdropView: UIView,
        drawableView: UIView,
        presentationStartFrameInWindow: CGRect,
        presentationDuration: TimeInterval,
        dismissalDuration: TimeInterval
    ) {
        self.sourceWindow = sourceWindow
        self.contentView = contentView
        self.backdropView = backdropView
        self.drawableView = drawableView
        self.presentationStartFrameInWindow = presentationStartFrameInWindow
        self.presentationDuration = presentationDuration
        self.dismissalDuration = dismissalDuration
        super.init()
    }

    func prepareForDismissal(
        targetFrameProvider: @escaping () -> CGRect?,
        onWillFinish: @escaping () -> Void,
        onFinished: @escaping () -> Void
    ) {
        dismissalTargetFrameProvider = targetFrameProvider
        onDismissalAnimationWillFinish = onWillFinish
        onDismissalAnimationFinished = onFinished
    }

    func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        ManualVideoFullscreenTransitionAnimator(operation: .present, driver: self)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        ManualVideoFullscreenTransitionAnimator(operation: .dismiss, driver: self)
    }

    fileprivate func transitionDuration(for operation: ManualVideoFullscreenTransitionAnimator.Operation) -> TimeInterval {
        switch operation {
        case .present:
            return presentationDuration
        case .dismiss:
            return dismissalDuration
        }
    }

    fileprivate func preparePresentation(in presentedView: UIView) {
        guard let contentView,
              let backdropView,
              let drawableView
        else { return }

        let startFrame = convertedPresentationStartFrame(in: presentedView)
        backdropView.frame = presentedView.bounds
        backdropView.alpha = 0
        contentView.transform = .identity
        contentView.frame = startFrame
        drawableView.transform = .identity
        drawableView.frame = contentView.bounds
        presentedView.layoutIfNeeded()
    }

    fileprivate func animatePresentation(in presentedView: UIView) {
        guard let contentView,
              let backdropView,
              let drawableView
        else { return }

        backdropView.alpha = 1
        contentView.transform = .identity
        contentView.frame = presentedView.bounds
        drawableView.transform = .identity
        drawableView.frame = contentView.bounds
        presentedView.layoutIfNeeded()
    }

    fileprivate func prepareDismissal(in dismissedView: UIView) {
        guard let contentView,
              let drawableView
        else { return }

        let currentFrame = contentView.layer.presentation()?.frame ?? contentView.frame
        contentView.transform = .identity
        contentView.frame = currentFrame
        drawableView.transform = .identity
        drawableView.frame = contentView.bounds
        dismissedView.layoutIfNeeded()
    }

    fileprivate func animateDismissal(in dismissedView: UIView) {
        guard let contentView,
              let backdropView,
              let drawableView
        else { return }

        backdropView.alpha = 0
        contentView.transform = .identity
        contentView.frame = convertedDismissalTargetFrame(in: dismissedView) ?? contentView.frame
        drawableView.transform = .identity
        drawableView.frame = contentView.bounds
        dismissedView.layoutIfNeeded()
    }

    fileprivate func restoreContentBeforeDismissalCompletion() {
        onDismissalAnimationWillFinish?()
    }

    fileprivate func finishDismissalAnimation() {
        onDismissalAnimationFinished?()
        dismissalTargetFrameProvider = nil
        onDismissalAnimationWillFinish = nil
        onDismissalAnimationFinished = nil
    }

    fileprivate func cancelDismissalAnimation() {
        dismissalTargetFrameProvider = nil
        onDismissalAnimationWillFinish = nil
        onDismissalAnimationFinished = nil
    }

    private func convertedPresentationStartFrame(in view: UIView) -> CGRect {
        guard let sourceWindow else { return presentationStartFrameInWindow }
        return view.convert(presentationStartFrameInWindow, from: sourceWindow)
    }

    private func convertedDismissalTargetFrame(in view: UIView) -> CGRect? {
        guard let targetFrame = dismissalTargetFrameProvider?() else { return nil }
        guard let sourceWindow else { return targetFrame }
        return view.convert(targetFrame, from: sourceWindow)
    }
}

private final class ManualVideoFullscreenTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    enum Operation {
        case present
        case dismiss
    }

    private let operation: Operation
    private let driver: ManualVideoFullscreenTransitioningDelegate

    init(operation: Operation, driver: ManualVideoFullscreenTransitioningDelegate) {
        self.operation = operation
        self.driver = driver
        super.init()
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        driver.transitionDuration(for: operation)
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        switch operation {
        case .present:
            animatePresentation(using: transitionContext)
        case .dismiss:
            animateDismissal(using: transitionContext)
        }
    }

    private func animatePresentation(using transitionContext: UIViewControllerContextTransitioning) {
        guard let toController = transitionContext.viewController(forKey: .to),
              let toView = transitionContext.view(forKey: .to)
        else {
            transitionContext.completeTransition(false)
            return
        }

        let containerView = transitionContext.containerView
        toView.frame = transitionContext.finalFrame(for: toController)
        containerView.addSubview(toView)
        driver.preparePresentation(in: toView)

        let timing = UISpringTimingParameters(
            mass: 1,
            stiffness: 320,
            damping: 34,
            initialVelocity: .zero
        )
        let animator = UIViewPropertyAnimator(
            duration: transitionDuration(using: transitionContext),
            timingParameters: timing
        )
        animator.isInterruptible = true
        animator.scrubsLinearly = false
        animator.addAnimations {
            self.driver.animatePresentation(in: toView)
        }
        animator.addCompletion { _ in
            let completed = !transitionContext.transitionWasCancelled
            transitionContext.completeTransition(completed)
        }
        animator.startAnimation()
    }

    private func animateDismissal(using transitionContext: UIViewControllerContextTransitioning) {
        guard let fromView = transitionContext.view(forKey: .from) else {
            transitionContext.completeTransition(false)
            return
        }

        driver.prepareDismissal(in: fromView)
        let timing = UISpringTimingParameters(
            mass: 1,
            stiffness: 210,
            damping: 30,
            initialVelocity: .zero
        )
        let animator = UIViewPropertyAnimator(
            duration: transitionDuration(using: transitionContext),
            timingParameters: timing
        )
        animator.isInterruptible = true
        animator.scrubsLinearly = false
        animator.addAnimations {
            self.driver.animateDismissal(in: fromView)
        }
        animator.addCompletion { _ in
            let completed = !transitionContext.transitionWasCancelled
            if completed {
                self.driver.restoreContentBeforeDismissalCompletion()
            } else {
                self.driver.cancelDismissalAnimation()
            }
            transitionContext.completeTransition(completed)
            if completed {
                self.driver.finishDismissalAnimation()
            }
        }
        animator.startAnimation()
    }
}

private final class ManualVideoFullscreenViewController: UIViewController {
    var onExit: (() -> Void)? {
        didSet {
            controlsOverlay.onExit = onExit
        }
    }
    var onDismissDragChanged: ((CGFloat, CGFloat) -> Void)? {
        didSet {
            controlsOverlay.onDismissDragChanged = onDismissDragChanged
        }
    }
    var onDismissDragCancelled: (() -> Void)? {
        didSet {
            controlsOverlay.onDismissDragCancelled = onDismissDragCancelled
        }
    }
    var onPrepareForUserSeek: ((Double) -> Void)? {
        didSet {
            controlsOverlay.onPrepareForUserSeek = onPrepareForUserSeek
        }
    }
    var onLayout: (() -> Void)?
    weak var viewModel: PlayerStateViewModel? {
        didSet {
            controlsOverlay.viewModel = viewModel
            refreshControlsOverlayVisibility()
        }
    }
    var usesNativePlaybackControls = false {
        didSet {
            guard oldValue != usesNativePlaybackControls else { return }
            refreshControlsOverlayVisibility()
        }
    }
    var mode: ManualVideoFullscreenMode = .landscape(.landscapeLeft) {
        didSet {
            controlsOverlay.mode = mode
            setNeedsUpdateOfSupportedInterfaceOrientations()
            view.setNeedsLayout()
            refreshFullscreenLayout()
        }
    }
    private let controlsOverlay = ManualFullscreenPlaybackControlsView()
    private var contentOverlayHostingController: UIHostingController<AnyView>?
    private var pendingContentOverlay: AnyView?
    private var isFlushingLayout = false
    private var contentOverlayTargetAlpha: CGFloat = 1
    private var contentOverlayTargetTransform = CGAffineTransform.identity

    override func loadView() {
        let view = UIView()
        view.backgroundColor = .black
        view.isOpaque = true
        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        controlsOverlay.translatesAutoresizingMaskIntoConstraints = false
        controlsOverlay.viewModel = viewModel
        controlsOverlay.onExit = onExit
        controlsOverlay.onDismissDragChanged = onDismissDragChanged
        controlsOverlay.onDismissDragCancelled = onDismissDragCancelled
        controlsOverlay.onPrepareForUserSeek = onPrepareForUserSeek
        controlsOverlay.mode = mode
        view.addSubview(controlsOverlay)
        NSLayoutConstraint.activate([
            controlsOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlsOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlsOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            controlsOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        refreshControlsOverlayVisibility()
        installPendingContentOverlayIfNeeded()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    override var prefersStatusBarHidden: Bool {
        true
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        true
    }

    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        .all
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        mode.interfaceOrientationMask
    }

    override var shouldAutorotate: Bool {
        true
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        mode.interfaceOrientation
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshSystemChrome()
        refreshFullscreenLayout()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        controlsOverlay.refreshFullscreenLayout()
        onLayout?()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        refreshFullscreenLayout()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        view.superview?.setNeedsLayout()
        view.setNeedsLayout()
        coordinator.animate { [weak self] _ in
            guard let self else { return }
            self.view.setNeedsLayout()
            self.onLayout?()
        } completion: { [weak self] _ in
            self?.refreshFullscreenLayout(flush: true)
            self?.onLayout?()
        }
    }

    func refreshSystemChrome() {
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
    }

    func refreshFullscreenLayout(flush: Bool = false) {
        guard isViewLoaded else { return }
        controlsOverlay.refreshFullscreenLayout()
        guard flush, !isFlushingLayout else { return }
        isFlushingLayout = true
        view.setNeedsLayout()
        UIView.performWithoutAnimation {
            view.layoutIfNeeded()
            controlsOverlay.layoutIfNeeded()
        }
        isFlushingLayout = false
    }

    func bringPlayerToFront() {
        guard isViewLoaded else { return }
        refreshControlsOverlayVisibility()
    }

    func prepareForEnterAnimation(animated: Bool) {
        guard animated, isViewLoaded else { return }
        contentOverlayTargetAlpha = 0
        contentOverlayTargetTransform = CGAffineTransform(scaleX: 0.985, y: 0.985)
        applyContentOverlayTransition(animated: false)
        controlsOverlay.prepareForEnterAnimation(animated: animated)
    }

    func finishEnterAnimation(animated: Bool) {
        guard isViewLoaded else { return }
        contentOverlayTargetAlpha = 1
        contentOverlayTargetTransform = .identity
        applyContentOverlayTransition(animated: animated, duration: 0.22, delay: 0.03)
        controlsOverlay.finishEnterAnimation(animated: animated)
    }

    func prepareForExitAnimation(animated: Bool) {
        contentOverlayTargetAlpha = 0
        contentOverlayTargetTransform = CGAffineTransform(scaleX: 0.985, y: 0.985)
        applyContentOverlayTransition(animated: animated, duration: 0.18)
        controlsOverlay.prepareForExitAnimation(animated: animated)
    }

    func updateDismissTransition(progress: CGFloat) {
        guard isViewLoaded else { return }
        let clampedProgress = min(max(progress, 0), 1)
        contentOverlayTargetAlpha = max(0.18, 1 - clampedProgress * 0.78)
        let scale = 1 - clampedProgress * 0.015
        contentOverlayTargetTransform = CGAffineTransform(scaleX: scale, y: scale)
        applyContentOverlayTransition(animated: false)
    }

    func cancelDismissTransition(animated: Bool) {
        guard isViewLoaded else { return }
        contentOverlayTargetAlpha = 1
        contentOverlayTargetTransform = .identity
        applyContentOverlayTransition(animated: animated, duration: 0.20)
    }

    func setContentOverlay(_ overlay: AnyView?) {
        pendingContentOverlay = overlay
        guard isViewLoaded else { return }

        guard let overlay else {
            if let contentOverlayHostingController {
                contentOverlayHostingController.willMove(toParent: nil)
                contentOverlayHostingController.view.removeFromSuperview()
                contentOverlayHostingController.removeFromParent()
                self.contentOverlayHostingController = nil
            }
            refreshControlsOverlayVisibility()
            return
        }

        if let contentOverlayHostingController {
            contentOverlayHostingController.rootView = overlay
        } else {
            let hostingController = UIHostingController(rootView: overlay)
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            hostingController.view.backgroundColor = .clear
            hostingController.view.isOpaque = false
            hostingController.view.isUserInteractionEnabled = false
            addChild(hostingController)
            view.addSubview(hostingController.view)
            NSLayoutConstraint.activate([
                hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            hostingController.didMove(toParent: self)
            contentOverlayHostingController = hostingController
        }
        applyContentOverlayTransition(animated: false)
        refreshControlsOverlayVisibility()
    }

    func setDanmakuControls(
        isEnabled: Bool,
        onToggle: (() -> Void)?,
        onShowSettings: (() -> Void)?
    ) {
        controlsOverlay.setDanmakuControls(
            isEnabled: isEnabled,
            onToggle: onToggle,
            onShowSettings: onShowSettings
        )
    }

    private func refreshControlsOverlayVisibility() {
        controlsOverlay.isHidden = false
        controlsOverlay.suppressesPlaybackChrome = usesNativePlaybackControls
        controlsOverlay.isUserInteractionEnabled = !usesNativePlaybackControls
        if let overlayView = contentOverlayHostingController?.view {
            view.bringSubviewToFront(overlayView)
        }
        view.bringSubviewToFront(controlsOverlay)
    }

    private func applyContentOverlayTransition(
        animated: Bool,
        duration: TimeInterval = 0.18,
        delay: TimeInterval = 0
    ) {
        guard let overlayView = contentOverlayHostingController?.view else { return }
        let changes = {
            overlayView.alpha = self.contentOverlayTargetAlpha
            overlayView.transform = self.contentOverlayTargetTransform
        }
        guard animated else {
            changes()
            return
        }
        UIView.animate(
            withDuration: duration,
            delay: delay,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut],
            animations: changes
        )
    }

    private func installPendingContentOverlayIfNeeded() {
        guard let pendingContentOverlay else { return }
        setContentOverlay(pendingContentOverlay)
    }
}

@MainActor
private enum ManualFullscreenTapRegion {
    case leading
    case center
    case trailing

    init(locationX: CGFloat, width: CGFloat) {
        guard width > 0 else {
            self = .center
            return
        }
        let ratio = locationX / width
        if ratio < 0.38 {
            self = .leading
        } else if ratio > 0.62 {
            self = .trailing
        } else {
            self = .center
        }
    }
}

@MainActor
private final class ManualFullscreenPlaybackControlsView: UIView, UIGestureRecognizerDelegate {
    weak var viewModel: PlayerStateViewModel? {
        willSet {
            if viewModel !== newValue {
                restoreLongPressPlaybackRateIfNeeded()
                viewModelCancellables.removeAll()
                timelineRefreshTask?.cancel()
                timelineRefreshTask = nil
            }
        }
        didSet {
            bindViewModelIfNeeded()
            lastKnownPlayingState = viewModel?.isPlaying ?? false
            refreshFromViewModel()
            scheduleAutoHideIfNeeded()
        }
    }
    var onExit: (() -> Void)?
    var onDismissDragChanged: ((CGFloat, CGFloat) -> Void)?
    var onDismissDragCancelled: (() -> Void)?
    var onPrepareForUserSeek: ((Double) -> Void)?
    var mode: ManualVideoFullscreenMode = .landscape(.landscapeLeft) {
        didSet {
            guard oldValue != mode else { return }
            refreshFullscreenLayout()
        }
    }
    var suppressesPlaybackChrome = false {
        didSet {
            guard oldValue != suppressesPlaybackChrome else { return }
            setControlsVisible(isControlsVisible, animated: false)
        }
    }

    private let topChrome = FullscreenControlsScrimView(direction: .top)
    private let bottomChrome = FullscreenControlsScrimView(direction: .bottom)
    private let exitButton = UIButton(type: .system)
    private let danmakuButton = UIButton(type: .system)
    private let danmakuSettingsButton = UIButton(type: .system)
    private let rewindButton = UIButton(type: .system)
    private let playPauseButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let currentTimeLabel = UILabel()
    private let durationLabel = UILabel()
    private let progressSlider = UISlider()
    private let topActionsStack = UIStackView()
    private let transportStack = UIStackView()
    private let controlsStack = UIStackView()
    private let feedbackView = UIView()
    private let feedbackImageView = UIImageView()
    private let feedbackLabel = UILabel()
    private let speedFeedbackView = UIView()
    private let speedFeedbackImageView = UIImageView()
    private let speedFeedbackLabel = UILabel()
    private var isControlsVisible = true
    private var isScrubbing = false
    private var longPressRateRestoreValue: BiliPlaybackRate?
    private var longPressBoostProfile: PlayerLongPressSpeedBoost.Profile?
    private var lastKnownPlayingState = false
    private var lastFeedbackRegion: ManualFullscreenTapRegion = .center
    private var viewModelCancellables = Set<AnyCancellable>()
    private var autoHideControlsTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    private var longPressSpeedBoostTask: Task<Void, Never>?
    private var timelineRefreshTask: Task<Void, Never>?
    private var isDanmakuEnabled = true
    private var onToggleDanmaku: (() -> Void)?
    private var onShowDanmakuSettings: (() -> Void)?
    private var isDraggingToDismiss = false
    private var dismissPanStartedWithControlsVisible = true
    private var lastFullscreenLayoutSize: CGSize = .zero
    private var lastDisplayedCurrentSecond: Int?
    private var lastDisplayedDurationSecond: Int?
    private var lastDisplayedProgress: Float?
    private var lastPreparedSeekProgress: Double = -1
    private var exitButtonTopConstraint: NSLayoutConstraint?
    private var topChromeHeightConstraint: NSLayoutConstraint?
    private var controlsStackBottomConstraint: NSLayoutConstraint?
    private var bottomChromeHeightConstraint: NSLayoutConstraint?
    private var feedbackCenterXConstraint: NSLayoutConstraint?
    private var feedbackImageCenterYConstraint: NSLayoutConstraint?

    private lazy var singleTapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        gesture.numberOfTapsRequired = 1
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()

    private lazy var doubleTapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        gesture.numberOfTapsRequired = 2
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()

    private lazy var longPressGesture: UILongPressGestureRecognizer = {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        gesture.minimumPressDuration = 0.28
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()

    private lazy var dismissPanGesture: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
        gesture.minimumNumberOfTouches = 1
        gesture.maximumNumberOfTouches = 1
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
        configureGestures()
        configureControls()
        refreshFromViewModel()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        autoHideControlsTask?.cancel()
        feedbackTask?.cancel()
        longPressSpeedBoostTask?.cancel()
        timelineRefreshTask?.cancel()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            autoHideControlsTask?.cancel()
            feedbackTask?.cancel()
            longPressSpeedBoostTask?.cancel()
            timelineRefreshTask?.cancel()
            longPressSpeedBoostTask = nil
            timelineRefreshTask = nil
            speedFeedbackView.alpha = 0
            restoreLongPressPlaybackRateIfNeeded()
        } else {
            refreshFromViewModel()
            setControlsVisible(true, animated: false)
            scheduleAutoHideIfNeeded()
        }
    }

    private func configureView() {
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = true

        [topChrome, bottomChrome, controlsStack, exitButton, topActionsStack, feedbackView, speedFeedbackView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        let exitButtonTopConstraint = exitButton.topAnchor.constraint(equalTo: topAnchor, constant: 10)
        let controlsStackBottomConstraint = controlsStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        let topChromeHeightConstraint = topChrome.heightAnchor.constraint(equalToConstant: 106)
        let bottomChromeHeightConstraint = bottomChrome.heightAnchor.constraint(equalToConstant: 132)
        let feedbackCenterXConstraint = feedbackView.centerXAnchor.constraint(equalTo: centerXAnchor)
        self.exitButtonTopConstraint = exitButtonTopConstraint
        self.topChromeHeightConstraint = topChromeHeightConstraint
        self.controlsStackBottomConstraint = controlsStackBottomConstraint
        self.bottomChromeHeightConstraint = bottomChromeHeightConstraint
        self.feedbackCenterXConstraint = feedbackCenterXConstraint

        NSLayoutConstraint.activate([
            topChrome.leadingAnchor.constraint(equalTo: leadingAnchor),
            topChrome.trailingAnchor.constraint(equalTo: trailingAnchor),
            topChrome.topAnchor.constraint(equalTo: topAnchor),
            topChromeHeightConstraint,

            bottomChrome.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomChrome.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomChrome.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomChromeHeightConstraint,

            exitButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 14),
            exitButtonTopConstraint,

            topActionsStack.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -14),
            topActionsStack.centerYAnchor.constraint(equalTo: exitButton.centerYAnchor),

            controlsStack.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 14),
            controlsStack.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -14),
            controlsStackBottomConstraint,

            feedbackCenterXConstraint,
            feedbackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            feedbackView.widthAnchor.constraint(equalToConstant: 92),
            feedbackView.heightAnchor.constraint(equalToConstant: 78),

            speedFeedbackView.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),
            speedFeedbackView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 10),
            speedFeedbackView.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    private func bindViewModelIfNeeded() {
        guard let viewModel else { return }
        viewModelCancellables.removeAll()
        let refreshControls: () -> Void = { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshFromViewModel()
            }
        }

        Publishers.MergeMany(
            viewModel.$duration
                .removeDuplicates()
                .map { _ in () }
                .eraseToAnyPublisher(),
            viewModel.$isPlaying
                .removeDuplicates()
                .map { _ in () }
                .eraseToAnyPublisher(),
            viewModel.$isSeekable
                .removeDuplicates()
                .map { _ in () }
                .eraseToAnyPublisher(),
            viewModel.$isBuffering
                .removeDuplicates()
                .map { _ in () }
                .eraseToAnyPublisher(),
            viewModel.$errorMessage
                .removeDuplicates()
                .map { _ in () }
                .eraseToAnyPublisher(),
            viewModel.$isPlaybackSurfaceReady
                .removeDuplicates()
                .map { _ in () }
                .eraseToAnyPublisher(),
            viewModel.$playbackRate
                .removeDuplicates()
                .map { _ in () }
                .eraseToAnyPublisher()
        )
            .sink { [weak self] _ in
                guard self != nil else { return }
                refreshControls()
            }
            .store(in: &viewModelCancellables)
        viewModel.playbackClock.$currentTime
            .combineLatest(viewModel.playbackClock.$duration)
            .removeDuplicates { previous, next in
                let previousDuration = previous.1 ?? -1
                let nextDuration = next.1 ?? -1
                return abs(previous.0 - next.0) < 0.18
                    && abs(previousDuration - nextDuration) < 0.4
            }
            .sink { [weak self] _ in
                self?.scheduleTimelineRefresh()
            }
            .store(in: &viewModelCancellables)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshFullscreenLayout()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        refreshFullscreenLayout()
    }

    func refreshFullscreenLayout() {
        let isPortraitFullscreen = mode.isPortrait || (bounds.height > bounds.width * 1.08 && !mode.isLandscape)
        let minimumTopInset: CGFloat = isPortraitFullscreen ? 54 : 0
        let minimumBottomInset: CGFloat = isPortraitFullscreen ? 20 : 0
        let topInset = isPortraitFullscreen ? max(safeAreaInsets.top, minimumTopInset) : max(min(max(safeAreaInsets.top, 0), 18), 10)
        let bottomInset = isPortraitFullscreen ? max(safeAreaInsets.bottom, minimumBottomInset) : min(max(safeAreaInsets.bottom, 0), 18)
        exitButtonTopConstraint?.constant = topInset + (isPortraitFullscreen ? 8 : 10)
        controlsStackBottomConstraint?.constant = -(bottomInset + (isPortraitFullscreen ? 14 : 12))
        topChromeHeightConstraint?.constant = isPortraitFullscreen ? 126 : 106
        bottomChromeHeightConstraint?.constant = isPortraitFullscreen
            ? 156
            : 132
        topChrome.setNeedsLayout()
        bottomChrome.setNeedsLayout()
        let roundedSize = CGSize(width: bounds.width.rounded(), height: bounds.height.rounded())
        guard roundedSize != lastFullscreenLayoutSize else { return }
        lastFullscreenLayoutSize = roundedSize
        if feedbackView.alpha > 0 {
            positionFeedbackView(for: lastFeedbackRegion)
        }
    }

    private func configureGestures() {
        singleTapGesture.require(toFail: doubleTapGesture)
        addGestureRecognizer(singleTapGesture)
        addGestureRecognizer(doubleTapGesture)
        addGestureRecognizer(longPressGesture)
        addGestureRecognizer(dismissPanGesture)
    }

    private func configureControls() {
        configureTopButton(exitButton, systemName: "xmark")
        configureTopButton(danmakuButton, systemName: "text.bubble.fill", pointSize: 14)
        configureTopButton(danmakuSettingsButton, systemName: "slider.horizontal.3", pointSize: 14)
        exitButton.accessibilityLabel = "退出全屏"
        danmakuButton.accessibilityLabel = "弹幕"
        danmakuSettingsButton.accessibilityLabel = "弹幕设置"

        exitButton.addTarget(self, action: #selector(handleExitButton), for: .touchUpInside)
        danmakuButton.addTarget(self, action: #selector(handleDanmakuButton), for: .touchUpInside)
        danmakuSettingsButton.addTarget(self, action: #selector(handleDanmakuSettingsButton), for: .touchUpInside)

        [currentTimeLabel, durationLabel].forEach { label in
            label.textColor = .white.withAlphaComponent(0.92)
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            label.textAlignment = label === currentTimeLabel ? .left : .right
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
            label.widthAnchor.constraint(equalToConstant: 44).isActive = true
        }

        progressSlider.minimumValue = 0
        progressSlider.maximumValue = 1
        let progressColor = UIColor(red: 1.0, green: 0.25, blue: 0.50, alpha: 1)
        progressSlider.minimumTrackTintColor = progressColor
        progressSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.22)
        progressSlider.setMinimumTrackImage(Self.sliderTrackImage(height: 3, color: progressColor), for: .normal)
        progressSlider.setMaximumTrackImage(Self.sliderTrackImage(height: 3, color: UIColor.white.withAlphaComponent(0.22)), for: .normal)
        progressSlider.setThumbImage(Self.sliderThumbImage(visualDiameter: 8, canvasDiameter: 21, color: progressColor), for: .normal)
        progressSlider.setThumbImage(Self.sliderThumbImage(visualDiameter: 13, canvasDiameter: 25, color: progressColor), for: .highlighted)
        progressSlider.addTarget(self, action: #selector(handleSliderTouchDown), for: .touchDown)
        progressSlider.addTarget(self, action: #selector(handleSliderValueChanged), for: .valueChanged)
        progressSlider.addTarget(self, action: #selector(handleSliderTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        transportStack.axis = .horizontal
        transportStack.alignment = .center
        transportStack.spacing = 26
        transportStack.isHidden = true
        transportStack.isUserInteractionEnabled = false
        transportStack.accessibilityElementsHidden = true

        topActionsStack.axis = .horizontal
        topActionsStack.alignment = .center
        topActionsStack.spacing = 8
        topActionsStack.addArrangedSubview(danmakuButton)
        topActionsStack.addArrangedSubview(danmakuSettingsButton)

        let progressRow = UIStackView(arrangedSubviews: [
            currentTimeLabel,
            progressSlider,
            durationLabel
        ])
        progressRow.axis = .horizontal
        progressRow.alignment = .center
        progressRow.spacing = 10

        controlsStack.axis = .vertical
        controlsStack.alignment = .fill
        controlsStack.spacing = 0
        controlsStack.addArrangedSubview(progressRow)
        controlsStack.layoutMargins = UIEdgeInsets(top: 7, left: 0, bottom: 7, right: 0)
        controlsStack.isLayoutMarginsRelativeArrangement = true

        feedbackView.backgroundColor = UIColor.black.withAlphaComponent(0.52)
        feedbackView.layer.cornerRadius = 22
        feedbackView.layer.cornerCurve = .continuous
        feedbackView.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor
        feedbackView.layer.borderWidth = 0.5
        feedbackView.clipsToBounds = true
        feedbackView.alpha = 0
        feedbackView.isUserInteractionEnabled = false
        feedbackImageView.translatesAutoresizingMaskIntoConstraints = false
        feedbackImageView.tintColor = .white
        feedbackImageView.contentMode = .scaleAspectFit
        feedbackLabel.translatesAutoresizingMaskIntoConstraints = false
        feedbackLabel.textColor = .white
        feedbackLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        feedbackLabel.textAlignment = .center
        feedbackLabel.isHidden = true
        feedbackView.addSubview(feedbackImageView)
        feedbackView.addSubview(feedbackLabel)
        configureSpeedFeedbackView()
        let feedbackImageCenterYConstraint = feedbackImageView.centerYAnchor.constraint(equalTo: feedbackView.centerYAnchor)
        self.feedbackImageCenterYConstraint = feedbackImageCenterYConstraint
        NSLayoutConstraint.activate([
            feedbackImageView.centerXAnchor.constraint(equalTo: feedbackView.centerXAnchor),
            feedbackImageCenterYConstraint,
            feedbackImageView.widthAnchor.constraint(equalToConstant: 32),
            feedbackImageView.heightAnchor.constraint(equalToConstant: 32),
            feedbackLabel.topAnchor.constraint(equalTo: feedbackImageView.bottomAnchor, constant: 3),
            feedbackLabel.leadingAnchor.constraint(equalTo: feedbackView.leadingAnchor, constant: 8),
            feedbackLabel.trailingAnchor.constraint(equalTo: feedbackView.trailingAnchor, constant: -8)
        ])
        refreshDanmakuControls()
    }

    private func configureSpeedFeedbackView() {
        speedFeedbackView.backgroundColor = UIColor.black.withAlphaComponent(0.40)
        speedFeedbackView.layer.cornerRadius = 14
        speedFeedbackView.layer.cornerCurve = .continuous
        speedFeedbackView.alpha = 0
        speedFeedbackView.isUserInteractionEnabled = false
        speedFeedbackView.clipsToBounds = true

        speedFeedbackImageView.translatesAutoresizingMaskIntoConstraints = false
        speedFeedbackImageView.image = UIImage(systemName: "forward.fill")
        speedFeedbackImageView.tintColor = .white
        speedFeedbackImageView.contentMode = .scaleAspectFit

        speedFeedbackLabel.translatesAutoresizingMaskIntoConstraints = false
        speedFeedbackLabel.textColor = .white
        speedFeedbackLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        speedFeedbackLabel.textAlignment = .center
        speedFeedbackLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        speedFeedbackView.addSubview(speedFeedbackImageView)
        speedFeedbackView.addSubview(speedFeedbackLabel)
        NSLayoutConstraint.activate([
            speedFeedbackImageView.leadingAnchor.constraint(equalTo: speedFeedbackView.leadingAnchor, constant: 8),
            speedFeedbackImageView.centerYAnchor.constraint(equalTo: speedFeedbackView.centerYAnchor),
            speedFeedbackImageView.widthAnchor.constraint(equalToConstant: 12),
            speedFeedbackImageView.heightAnchor.constraint(equalToConstant: 12),
            speedFeedbackLabel.leadingAnchor.constraint(equalTo: speedFeedbackImageView.trailingAnchor, constant: 5),
            speedFeedbackLabel.trailingAnchor.constraint(equalTo: speedFeedbackView.trailingAnchor, constant: -9),
            speedFeedbackLabel.centerYAnchor.constraint(equalTo: speedFeedbackView.centerYAnchor)
        ])
    }

    func setDanmakuControls(
        isEnabled: Bool,
        onToggle: (() -> Void)?,
        onShowSettings: (() -> Void)?
    ) {
        isDanmakuEnabled = isEnabled
        onToggleDanmaku = onToggle
        onShowDanmakuSettings = onShowSettings
        refreshDanmakuControls()
    }

    private func refreshDanmakuControls() {
        let hasDanmakuActions = onToggleDanmaku != nil || onShowDanmakuSettings != nil
        topActionsStack.isHidden = !hasDanmakuActions
        danmakuButton.isHidden = onToggleDanmaku == nil
        danmakuSettingsButton.isHidden = onShowDanmakuSettings == nil
        applyTopButtonConfiguration(
            danmakuButton,
            systemName: isDanmakuEnabled ? "text.bubble.fill" : "text.bubble",
            pointSize: 14,
            isProminent: isDanmakuEnabled
        )
        danmakuButton.alpha = isDanmakuEnabled ? 1 : 0.62
        danmakuButton.accessibilityLabel = isDanmakuEnabled ? "关闭弹幕" : "开启弹幕"
    }

    private func applyTopButtonConfiguration(
        _ button: UIButton,
        systemName: String,
        pointSize: CGFloat = 15,
        isProminent: Bool = false
    ) {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: systemName)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        configuration.background.backgroundColor = UIColor.black.withAlphaComponent(isProminent ? 0.54 : 0.38)
        button.configuration = configuration
    }

    private func configureTopButton(_ button: UIButton, systemName: String, pointSize: CGFloat = 15) {
        applyTopButtonConfiguration(button, systemName: systemName, pointSize: pointSize)
        button.backgroundColor = .clear
        button.tintColor = .white
        button.overrideUserInterfaceStyle = .dark
        button.clipsToBounds = true
        button.layer.cornerRadius = 20
        button.layer.cornerCurve = .continuous
        button.widthAnchor.constraint(equalToConstant: 40).isActive = true
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
    }

    private func configureTransportButton(
        _ button: UIButton,
        systemName: String,
        size: CGFloat,
        pointSize: CGFloat? = nil,
        isPrimary: Bool = false
    ) {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: systemName)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: pointSize ?? (size * 0.29),
            weight: .bold
        )
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .capsule
        let leadingInset: CGFloat = systemName == "play.fill" ? 4 : 0
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: leadingInset, bottom: 0, trailing: 0)
        configuration.imagePadding = 0
        configuration.background.backgroundColor = UIColor.black.withAlphaComponent(isPrimary ? 0.54 : 0.38)
        button.configuration = configuration
        button.backgroundColor = .clear
        button.tintColor = .white
        button.overrideUserInterfaceStyle = .dark
        button.clipsToBounds = true
        button.layer.cornerRadius = size / 2
        button.layer.cornerCurve = .continuous
        button.widthAnchor.constraint(equalToConstant: size).isActive = true
        button.heightAnchor.constraint(equalToConstant: size).isActive = true
    }

    private func refreshFromViewModel() {
        guard let viewModel else {
            updateTimelineDisplay(currentSecond: 0, durationSecond: 0, progress: 0, force: true)
            setTransportEnabled(false)
            return
        }

        refreshTimelineFromViewModel()
        let canSeek = viewModel.canSeek && (viewModel.playbackClock.duration ?? viewModel.displayDuration ?? 0) > 0
        setTransportEnabled(canSeek)
        if viewModel.isBuffering {
            restoreLongPressPlaybackRateForPressureIfNeeded()
        }
        let playSymbol = viewModel.isPlaying ? "pause.fill" : "play.fill"
        playPauseButton.configuration?.image = UIImage(systemName: playSymbol)
        playPauseButton.configuration?.contentInsets = NSDirectionalEdgeInsets(
            top: 0,
            leading: viewModel.isPlaying ? 0 : 4,
            bottom: 0,
            trailing: 0
        )
        playPauseButton.accessibilityLabel = viewModel.isPlaying ? "暂停" : "播放"

        if lastKnownPlayingState != viewModel.isPlaying {
            lastKnownPlayingState = viewModel.isPlaying
            if viewModel.isPlaying {
                scheduleAutoHideIfNeeded()
            } else {
                restoreLongPressPlaybackRateIfNeeded()
                setControlsVisible(true, animated: true)
            }
        }
    }

    private func setTransportEnabled(_ isEnabled: Bool) {
        rewindButton.isEnabled = isEnabled
        forwardButton.isEnabled = isEnabled
        playPauseButton.isEnabled = viewModel != nil
        progressSlider.isEnabled = isEnabled
        let alpha: CGFloat = isEnabled ? 1 : 0.45
        rewindButton.alpha = alpha
        forwardButton.alpha = alpha
        playPauseButton.alpha = viewModel == nil ? 0.45 : 1
        progressSlider.alpha = alpha
    }

    func prepareForExitAnimation(animated: Bool) {
        autoHideControlsTask?.cancel()
        autoHideControlsTask = nil
        feedbackTask?.cancel()
        feedbackTask = nil
        longPressSpeedBoostTask?.cancel()
        longPressSpeedBoostTask = nil
        restoreLongPressPlaybackRateIfNeeded()
        isDraggingToDismiss = false

        let changes = {
            self.topChrome.alpha = 0
            self.bottomChrome.alpha = 0
            self.exitButton.alpha = 0
            self.topActionsStack.alpha = 0
            self.transportStack.alpha = 0
            self.transportStack.isHidden = true
            self.controlsStack.alpha = 0
            self.feedbackView.alpha = 0
            self.speedFeedbackView.alpha = 0
            self.topChrome.transform = CGAffineTransform(translationX: 0, y: -8)
            self.exitButton.transform = CGAffineTransform(translationX: 0, y: -8)
            self.topActionsStack.transform = CGAffineTransform(translationX: 0, y: -8)
            self.bottomChrome.transform = CGAffineTransform(translationX: 0, y: 10)
            self.controlsStack.transform = CGAffineTransform(translationX: 0, y: 10)
            self.transportStack.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        }
        let completion = {
            self.exitButton.isUserInteractionEnabled = false
            self.topActionsStack.isUserInteractionEnabled = false
            self.transportStack.isUserInteractionEnabled = false
            self.transportStack.accessibilityElementsHidden = true
            self.controlsStack.isUserInteractionEnabled = false
        }

        guard animated else {
            changes()
            completion()
            return
        }

        let animator = UIViewPropertyAnimator(
            duration: 0.20,
            timingParameters: UICubicTimingParameters(animationCurve: .easeOut)
        )
        animator.isInterruptible = true
        animator.addAnimations {
            changes()
        }
        animator.addCompletion { _ in
            completion()
        }
        animator.startAnimation()
    }

    func prepareForEnterAnimation(animated: Bool) {
        guard animated else { return }
        autoHideControlsTask?.cancel()
        autoHideControlsTask = nil
        feedbackTask?.cancel()
        feedbackTask = nil
        longPressSpeedBoostTask?.cancel()
        longPressSpeedBoostTask = nil
        restoreLongPressPlaybackRateIfNeeded()
        let changes = {
            self.topChrome.alpha = 0
            self.bottomChrome.alpha = 0
            self.exitButton.alpha = 0
            self.topActionsStack.alpha = 0
            self.transportStack.alpha = 0
            self.transportStack.isHidden = true
            self.controlsStack.alpha = 0
            self.feedbackView.alpha = 0
            self.speedFeedbackView.alpha = 0
            self.topChrome.transform = CGAffineTransform(translationX: 0, y: -8)
            self.exitButton.transform = CGAffineTransform(translationX: 0, y: -8)
            self.topActionsStack.transform = CGAffineTransform(translationX: 0, y: -8)
            self.bottomChrome.transform = CGAffineTransform(translationX: 0, y: 10)
            self.controlsStack.transform = CGAffineTransform(translationX: 0, y: 10)
            self.transportStack.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        }
        changes()
        exitButton.isUserInteractionEnabled = false
        topActionsStack.isUserInteractionEnabled = false
        transportStack.isUserInteractionEnabled = false
        transportStack.accessibilityElementsHidden = true
        controlsStack.isUserInteractionEnabled = false
    }

    func finishEnterAnimation(animated: Bool) {
        let chromeVisible = isControlsVisible && !suppressesPlaybackChrome
        let alpha: CGFloat = chromeVisible ? 1 : 0
        let changes = {
            self.topChrome.alpha = alpha
            self.bottomChrome.alpha = alpha
            self.exitButton.alpha = alpha
            self.topActionsStack.alpha = alpha
            self.transportStack.alpha = 0
            self.transportStack.isHidden = true
            self.controlsStack.alpha = alpha
            self.feedbackView.alpha = 0
            self.speedFeedbackView.alpha = 0
            self.topChrome.transform = .identity
            self.exitButton.transform = .identity
            self.topActionsStack.transform = .identity
            self.bottomChrome.transform = .identity
            self.controlsStack.transform = .identity
            self.transportStack.transform = .identity
        }
        let completion = {
            self.exitButton.isUserInteractionEnabled = chromeVisible
            self.topActionsStack.isUserInteractionEnabled = chromeVisible
            self.transportStack.isUserInteractionEnabled = false
            self.transportStack.accessibilityElementsHidden = true
            self.controlsStack.isUserInteractionEnabled = chromeVisible
        }

        guard animated else {
            changes()
            completion()
            if chromeVisible {
                refreshTimelineFromViewModel(force: true)
                scheduleAutoHideIfNeeded()
            }
            return
        }

        UIView.animate(
            withDuration: 0.22,
            delay: 0.03,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]
        ) {
            changes()
        } completion: { _ in
            completion()
            if chromeVisible {
                self.refreshTimelineFromViewModel(force: true)
                self.scheduleAutoHideIfNeeded()
            }
        }
    }

    private func setControlsVisible(_ visible: Bool, animated: Bool) {
        isControlsVisible = visible
        let chromeVisible = visible && !suppressesPlaybackChrome
        let alpha: CGFloat = chromeVisible ? 1 : 0
        let changes = {
            self.topChrome.alpha = alpha
            self.bottomChrome.alpha = alpha
            self.exitButton.alpha = alpha
            self.topActionsStack.alpha = alpha
            self.transportStack.alpha = 0
            self.transportStack.isHidden = true
            self.controlsStack.alpha = alpha
            self.topChrome.transform = .identity
            self.exitButton.transform = .identity
            self.topActionsStack.transform = .identity
            self.bottomChrome.transform = .identity
            self.controlsStack.transform = .identity
            self.transportStack.transform = chromeVisible
                ? .identity
                : CGAffineTransform(scaleX: 0.88, y: 0.88)
        }
        let completion = {
            self.exitButton.isUserInteractionEnabled = chromeVisible
            self.topActionsStack.isUserInteractionEnabled = chromeVisible
            self.transportStack.isUserInteractionEnabled = false
            self.transportStack.accessibilityElementsHidden = true
            self.controlsStack.isUserInteractionEnabled = chromeVisible
        }

        if chromeVisible {
            exitButton.isUserInteractionEnabled = true
            topActionsStack.isUserInteractionEnabled = true
            transportStack.isHidden = true
            transportStack.isUserInteractionEnabled = false
            transportStack.accessibilityElementsHidden = true
            controlsStack.isUserInteractionEnabled = true
            if animated {
                transportStack.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
            }
        }

        if animated {
            UIView.animate(
                withDuration: 0.18,
                delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState]
            ) {
                changes()
            } completion: { _ in
                completion()
            }
        } else {
            changes()
            completion()
        }

        if chromeVisible {
            refreshTimelineFromViewModel(force: true)
            scheduleAutoHideIfNeeded()
        } else {
            autoHideControlsTask?.cancel()
            autoHideControlsTask = nil
        }
    }

    private func scheduleAutoHideIfNeeded() {
        autoHideControlsTask?.cancel()
        guard !suppressesPlaybackChrome else { return }
        guard isControlsVisible, viewModel?.isPlaying == true, !isScrubbing else { return }
        autoHideControlsTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard let self, !Task.isCancelled, self.viewModel?.isPlaying == true, !self.isScrubbing else { return }
            self.setControlsVisible(false, animated: true)
        }
    }

    @objc private func handleSingleTap() {
        Haptics.light()
        setControlsVisible(!isControlsVisible, animated: true)
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard let viewModel else { return }
        Haptics.medium()
        let region = ManualFullscreenTapRegion(locationX: recognizer.location(in: self).x, width: bounds.width)
        switch region {
        case .leading:
            guard viewModel.canSeek else { return }
            viewModel.seek(by: -10)
            refreshFromViewModel()
            if isControlsVisible {
                scheduleAutoHideIfNeeded()
            }
            showFeedback(systemName: "gobackward.10", title: "-10s", region: .leading)
        case .trailing:
            guard viewModel.canSeek else { return }
            viewModel.seek(by: 10)
            refreshFromViewModel()
            if isControlsVisible {
                scheduleAutoHideIfNeeded()
            }
            showFeedback(systemName: "goforward.10", title: "+10s", region: .trailing)
        case .center:
            let isNowPlaying = viewModel.togglePlayback()
            refreshFromViewModel()
            setControlsVisible(true, animated: true)
            showFeedback(systemName: isNowPlaying ? "play.fill" : "pause.fill", region: .center)
        }
    }

    private func scheduleTimelineRefresh() {
        guard isControlsVisible, !suppressesPlaybackChrome, !isScrubbing else { return }
        guard timelineRefreshTask == nil else { return }
        timelineRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard let self, !Task.isCancelled else { return }
            self.timelineRefreshTask = nil
            self.refreshTimelineFromViewModel()
        }
    }

    private func refreshTimelineFromViewModel(force: Bool = false) {
        guard let viewModel else {
            updateTimelineDisplay(currentSecond: 0, durationSecond: 0, progress: 0, force: true)
            return
        }
        guard !isScrubbing else { return }
        guard force || (isControlsVisible && !suppressesPlaybackChrome) else { return }

        let clock = viewModel.playbackClock
        let duration = max(clock.duration ?? viewModel.displayDuration ?? 0, 0)
        let currentTime = max(clock.currentTime, 0)
        let progress = duration > 0 ? min(max(currentTime / duration, 0), 1) : 0
        updateTimelineDisplay(
            currentSecond: Int(currentTime.rounded()),
            durationSecond: duration > 0 ? Int(duration.rounded()) : 0,
            progress: Float(progress),
            force: force
        )
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            guard !isDraggingToDismiss else { return }
            beginLongPressSpeedBoost()
        case .ended, .cancelled, .failed:
            endLongPressSpeedBoost()
        default:
            break
        }
    }

    @objc private func handleDismissPan(_ recognizer: UIPanGestureRecognizer) {
        let rawTranslationY = recognizer.translation(in: self).y
        let velocityY = recognizer.velocity(in: self).y
        let minimumTravel = max(min(bounds.height, bounds.width) * 0.22, 96)
        let translationY: CGFloat = mode.isPortrait
            ? max(0, rawTranslationY)
            : rawTranslationY
        let progress = min(abs(translationY) / minimumTravel, 1)

        switch recognizer.state {
        case .began:
            isDraggingToDismiss = true
            dismissPanStartedWithControlsVisible = isControlsVisible
            restoreLongPressPlaybackRateIfNeeded()
            autoHideControlsTask?.cancel()
            autoHideControlsTask = nil
            setControlsVisible(false, animated: true)
        case .changed:
            guard isDraggingToDismiss else { return }
            onDismissDragChanged?(translationY, progress)
        case .ended:
            guard isDraggingToDismiss else { return }
            isDraggingToDismiss = false
            let hasDismissVelocity = mode.isPortrait
                ? velocityY > 980
                : abs(velocityY) > 980
            let shouldExit = abs(translationY) > minimumTravel || hasDismissVelocity
            if shouldExit {
                Haptics.light()
                onExit?()
            } else {
                onDismissDragCancelled?()
                setControlsVisible(dismissPanStartedWithControlsVisible, animated: true)
                scheduleAutoHideIfNeeded()
            }
        case .cancelled, .failed:
            guard isDraggingToDismiss else { return }
            isDraggingToDismiss = false
            onDismissDragCancelled?()
            setControlsVisible(dismissPanStartedWithControlsVisible, animated: true)
            scheduleAutoHideIfNeeded()
        default:
            break
        }
    }

    @objc private func handleExitButton() {
        Haptics.light()
        prepareForExitAnimation(animated: true)
        onExit?()
    }

    @objc private func handleDanmakuButton() {
        Haptics.light()
        onToggleDanmaku?()
        isDanmakuEnabled.toggle()
        refreshDanmakuControls()
        setControlsVisible(true, animated: true)
    }

    @objc private func handleDanmakuSettingsButton() {
        Haptics.light()
        onShowDanmakuSettings?()
        setControlsVisible(true, animated: true)
    }

    @objc private func handleRewindButton() {
        Haptics.light()
        viewModel?.seek(by: -10)
        refreshFromViewModel()
        setControlsVisible(true, animated: true)
        animateTransportButton(rewindButton)
        showFeedback(systemName: "gobackward.10", title: "-10s", region: .center)
    }

    @objc private func handlePlayPauseButton() {
        Haptics.light()
        _ = viewModel?.togglePlayback()
        refreshFromViewModel()
        setControlsVisible(true, animated: true)
        animateTransportButton(playPauseButton)
    }

    @objc private func handleForwardButton() {
        Haptics.light()
        viewModel?.seek(by: 10)
        refreshFromViewModel()
        setControlsVisible(true, animated: true)
        animateTransportButton(forwardButton)
        showFeedback(systemName: "goforward.10", title: "+10s", region: .center)
    }

    private func beginLongPressSpeedBoost() {
        guard let viewModel, viewModel.isPlaying, !viewModel.isBuffering, longPressRateRestoreValue == nil else { return }
        let boostProfile = PlayerLongPressSpeedBoost.profile(for: viewModel.engineDiagnostics)
        let startupRate = boostProfile.startupRate
        longPressRateRestoreValue = viewModel.playbackRate
        longPressBoostProfile = boostProfile
        Haptics.medium()
        viewModel.setPlaybackRate(startupRate)
        viewModel.recordSpeedBoostMetric(
            "manual start rate=\(boostProfile.startupFeedbackTitle) target=\(boostProfile.feedbackTitle) guarded=\(boostProfile.isGuarded)"
        )
        autoHideControlsTask?.cancel()
        autoHideControlsTask = nil
        setControlsVisible(false, animated: true)
        showSpeedBoostFeedback(title: boostProfile.startupFeedbackTitle)
        scheduleLongPressSpeedBoostTimeout(boostProfile)
    }

    private func endLongPressSpeedBoost() {
        restoreLongPressPlaybackRateIfNeeded()
        scheduleAutoHideIfNeeded()
    }

    private func restoreLongPressPlaybackRateIfNeeded() {
        restoreLongPressPlaybackRate(to: longPressRateRestoreValue)
    }

    private func restoreLongPressPlaybackRateForPressureIfNeeded() {
        guard let restoreRate = longPressRateRestoreValue else { return }
        let boostProfile = longPressBoostProfile
            ?? viewModel.map { PlayerLongPressSpeedBoost.profile(for: $0.engineDiagnostics) }
        let fallbackRate: BiliPlaybackRate
        if let boostProfile, restoreRate.rawValue >= boostProfile.rate.rawValue {
            fallbackRate = .x10
        } else {
            fallbackRate = restoreRate
        }
        viewModel?.recordSpeedBoostMetric("manual pressureRestore interrupted=true restore=\(fallbackRate.title)")
        restoreLongPressPlaybackRate(to: fallbackRate)
    }

    private func restoreLongPressPlaybackRate(to restoreRate: BiliPlaybackRate?) {
        guard let restoreRate else { return }
        let boostProfile = longPressBoostProfile
        longPressSpeedBoostTask?.cancel()
        longPressSpeedBoostTask = nil
        longPressRateRestoreValue = nil
        longPressBoostProfile = nil
        viewModel?.setPlaybackRate(restoreRate)
        viewModel?.stabilizePlaybackAfterSpeedBoost(restoredRate: restoreRate, reason: "manualFullscreenRestore")
        hideSpeedBoostFeedback()
        if feedbackLabel.text == boostProfile?.feedbackTitle
            || feedbackLabel.text == boostProfile?.sustainedFeedbackTitle {
            feedbackTask?.cancel()
            UIView.animate(
                withDuration: 0.16,
                delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState]
            ) {
                self.feedbackView.alpha = 0
            }
        }
    }

    private func scheduleLongPressSpeedBoostTimeout(_ boostProfile: PlayerLongPressSpeedBoost.Profile) {
        longPressSpeedBoostTask?.cancel()
        longPressSpeedBoostTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let startedAt = CACurrentMediaTime()
            let sustainAfter = TimeInterval(boostProfile.sustainAfterNanoseconds) / 1_000_000_000
            let peakRampAfter = TimeInterval(boostProfile.peakRampAfterNanoseconds) / 1_000_000_000
            let maximumDuration = TimeInterval(boostProfile.maximumDurationNanoseconds) / 1_000_000_000
            var didApplyPeakRate = !boostProfile.usesPeakRampUp
            var didApplySustainedRate = false
            var lastSampleWallTime = startedAt
            var lastPlaybackTime = self.currentLongPressPlaybackTime
            var slowProgressSamples = 0

            while !Task.isCancelled, self.longPressRateRestoreValue != nil {
                let elapsedBeforeSleep = CACurrentMediaTime() - startedAt
                if boostProfile.usesPeakRampUp,
                   !didApplyPeakRate,
                   elapsedBeforeSleep >= peakRampAfter {
                    self.viewModel?.setPlaybackRate(boostProfile.rate)
                    self.viewModel?.recordSpeedBoostMetric(
                        "manual peak rate=\(boostProfile.feedbackTitle) guarded=\(boostProfile.isGuarded)"
                    )
                    self.showSpeedBoostFeedback(title: boostProfile.feedbackTitle)
                    didApplyPeakRate = true
                    lastSampleWallTime = CACurrentMediaTime()
                    lastPlaybackTime = self.currentLongPressPlaybackTime
                }

                if boostProfile.usesSustainedStepDown,
                   didApplyPeakRate,
                   !didApplySustainedRate,
                   elapsedBeforeSleep >= sustainAfter {
                    self.viewModel?.setPlaybackRate(boostProfile.sustainedRate)
                    self.viewModel?.recordSpeedBoostMetric(
                        "manual sustain rate=\(boostProfile.sustainedFeedbackTitle) guarded=\(boostProfile.isGuarded)"
                    )
                    self.showSpeedBoostFeedback(title: boostProfile.sustainedFeedbackTitle)
                    didApplySustainedRate = true
                    lastSampleWallTime = CACurrentMediaTime()
                    lastPlaybackTime = self.currentLongPressPlaybackTime
                }

                let sleepNanoseconds: UInt64 = (!didApplyPeakRate && boostProfile.usesPeakRampUp)
                    ? 220_000_000
                    : 700_000_000
                try? await Task.sleep(nanoseconds: sleepNanoseconds)
                guard !Task.isCancelled, self.longPressRateRestoreValue != nil else { return }

                let now = CACurrentMediaTime()
                if now - startedAt >= maximumDuration {
                    self.viewModel?.recordSpeedBoostMetric("manual timeout interrupted=false restore=\(self.longPressRateRestoreValue?.title ?? "-")")
                    self.restoreLongPressPlaybackRateIfNeeded()
                    self.scheduleAutoHideIfNeeded()
                    return
                }

                guard now - startedAt >= 2.4 else { continue }
                let sampleInterval = now - lastSampleWallTime
                guard sampleInterval >= 1.15 else { continue }
                let playbackTime = self.currentLongPressPlaybackTime
                let playbackDelta = max(playbackTime - lastPlaybackTime, 0)
                let slowProgressThreshold = max(0.30, sampleInterval * 0.14)
                if playbackDelta < slowProgressThreshold {
                    slowProgressSamples += 1
                } else {
                    slowProgressSamples = 0
                }
                lastSampleWallTime = now
                lastPlaybackTime = playbackTime

                guard slowProgressSamples >= 2 else { continue }
                self.viewModel?.recordSpeedBoostMetric("manual pressureRestore interrupted=true restore=\(self.longPressRateRestoreValue?.title ?? "-") reason=slowProgress")
                self.restoreLongPressPlaybackRateForPressureIfNeeded()
                self.scheduleAutoHideIfNeeded()
                return
            }
        }
    }

    private var currentLongPressPlaybackTime: TimeInterval {
        guard let viewModel else { return 0 }
        let snapshotTime = viewModel.playbackSnapshot().currentTime ?? 0
        let time = max(snapshotTime, viewModel.currentTime, viewModel.playbackClock.currentTime)
        guard time.isFinite else { return 0 }
        return max(time, 0)
    }

    private func animateTransportButton(_ button: UIButton) {
        guard isControlsVisible else { return }
        UIView.animate(
            withDuration: 0.09,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            button.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        } completion: { _ in
            UIView.animate(
                withDuration: 0.22,
                delay: 0,
                usingSpringWithDamping: 0.58,
                initialSpringVelocity: 0.7,
                options: [.beginFromCurrentState]
            ) {
                button.transform = .identity
            }
        }
    }

    @objc private func handleSliderTouchDown() {
        isScrubbing = true
        restoreLongPressPlaybackRateIfNeeded()
        prepareSeekWarmupIfNeeded(Double(progressSlider.value), force: true)
        autoHideControlsTask?.cancel()
    }

    @objc private func handleSliderValueChanged() {
        let duration = max(viewModel?.displayDuration ?? 0, 0)
        let targetTime = TimeInterval(progressSlider.value) * duration
        updateCurrentTimeLabel(second: Int(targetTime.rounded()), force: false)
        lastDisplayedProgress = progressSlider.value
        prepareSeekWarmupIfNeeded(Double(progressSlider.value))
    }

    @objc private func handleSliderTouchUp() {
        let targetProgress = Double(progressSlider.value)
        isScrubbing = false
        Haptics.light()
        prepareSeekWarmupIfNeeded(targetProgress, force: true)
        viewModel?.seekAfterUserScrub(to: targetProgress)
        lastPreparedSeekProgress = -1
        refreshFromViewModel()
        scheduleAutoHideIfNeeded()
    }

    private func prepareSeekWarmupIfNeeded(_ progress: Double, force: Bool = false) {
        let clampedProgress = min(max(progress, 0), 1)
        guard force || abs(clampedProgress - lastPreparedSeekProgress) >= 0.015 else { return }
        lastPreparedSeekProgress = clampedProgress
        onPrepareForUserSeek?(clampedProgress)
    }

    private func showFeedback(
        systemName: String,
        title: String? = nil,
        region: ManualFullscreenTapRegion,
        persists: Bool = false
    ) {
        feedbackTask?.cancel()
        hideSpeedBoostFeedback(animated: false)
        lastFeedbackRegion = region
        feedbackImageView.image = UIImage(systemName: systemName)
        feedbackLabel.text = title
        feedbackLabel.isHidden = title == nil
        feedbackImageCenterYConstraint?.constant = title == nil ? 0 : -7
        positionFeedbackView(for: region)
        feedbackView.transform = CGAffineTransform(scaleX: 0.82, y: 0.82)
        UIView.animate(
            withDuration: 0.16,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            self.feedbackView.alpha = 1
            self.feedbackView.transform = .identity
        }
        guard !persists else { return }
        feedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 620_000_000)
            guard let self, !Task.isCancelled else { return }
            UIView.animate(
                withDuration: 0.16,
                delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState]
            ) {
                self.feedbackView.alpha = 0
            }
        }
    }

    private func showSpeedBoostFeedback(title: String) {
        feedbackTask?.cancel()
        feedbackView.alpha = 0
        speedFeedbackLabel.text = title
        speedFeedbackView.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
        UIView.animate(
            withDuration: 0.16,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            self.speedFeedbackView.alpha = 1
            self.speedFeedbackView.transform = .identity
        }
    }

    private func hideSpeedBoostFeedback(animated: Bool = true) {
        let updates = {
            self.speedFeedbackView.alpha = 0
        }
        guard animated else {
            updates()
            speedFeedbackView.transform = .identity
            return
        }
        UIView.animate(
            withDuration: 0.16,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState],
            animations: updates
        )
    }

    private func positionFeedbackView(for region: ManualFullscreenTapRegion) {
        let horizontalInset = max(safeAreaInsets.left, safeAreaInsets.right) + 74
        let centerX: CGFloat
        switch region {
        case .leading:
            centerX = min(max(horizontalInset, bounds.minX + 46), bounds.midX)
        case .trailing:
            centerX = max(min(bounds.width - horizontalInset, bounds.maxX - 46), bounds.midX)
        case .center:
            centerX = bounds.midX
        }
        feedbackCenterXConstraint?.constant = centerX - bounds.midX
        layoutIfNeeded()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let touchedView = touch.view else { return true }
        if touchedView.isDescendant(of: controlsStack)
            || touchedView.isDescendant(of: exitButton)
            || touchedView.isDescendant(of: topActionsStack) {
            return false
        }
        if touchedView.isDescendant(of: transportStack) {
            return false
        }
        return true
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === dismissPanGesture else { return true }
        guard !isScrubbing else { return false }
        let velocity = dismissPanGesture.velocity(in: self)
        let verticalSpeed = abs(velocity.y)
        let horizontalSpeed = abs(velocity.x)
        guard verticalSpeed > 120, verticalSpeed > horizontalSpeed * 1.12 else { return false }
        if mode.isPortrait {
            return velocity.y > 120
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === dismissPanGesture || otherGestureRecognizer === dismissPanGesture {
            return false
        }
        return false
    }

    private static func sliderTrackImage(height: CGFloat, color: UIColor) -> UIImage {
        let size = CGSize(width: 12, height: height)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            color.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: height / 2).fill()
        }
        let cap = max(1, height / 2)
        return image.resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: cap, bottom: 0, right: cap), resizingMode: .stretch)
    }

    private static func sliderThumbImage(visualDiameter: CGFloat, canvasDiameter: CGFloat, color: UIColor) -> UIImage {
        let size = CGSize(width: canvasDiameter, height: canvasDiameter)
        return UIGraphicsImageRenderer(size: size).image { context in
            let rect = CGRect(
                x: (canvasDiameter - visualDiameter) / 2,
                y: (canvasDiameter - visualDiameter) / 2,
                width: visualDiameter,
                height: visualDiameter
            )
            context.cgContext.setShadow(
                offset: CGSize(width: 0, height: 1),
                blur: 4,
                color: UIColor.black.withAlphaComponent(0.24).cgColor
            )
            color.setFill()
            context.cgContext.fillEllipse(in: rect)
        }
    }

    private func updateTimelineDisplay(
        currentSecond: Int,
        durationSecond: Int,
        progress: Float,
        force: Bool
    ) {
        updateCurrentTimeLabel(second: currentSecond, force: force)
        updateDurationLabel(second: durationSecond, force: force)
        updateProgressSliderValue(progress, force: force)
    }

    private func updateCurrentTimeLabel(second: Int, force: Bool) {
        if force || lastDisplayedCurrentSecond != second {
            currentTimeLabel.text = BiliFormatters.duration(second)
            lastDisplayedCurrentSecond = second
        }
    }

    private func updateDurationLabel(second: Int, force: Bool) {
        if force || lastDisplayedDurationSecond != second {
            durationLabel.text = BiliFormatters.duration(second)
            lastDisplayedDurationSecond = second
        }
    }

    private func updateProgressSliderValue(_ progress: Float, force: Bool) {
        if force || lastDisplayedProgress == nil || abs(lastDisplayedProgress! - progress) > 0.001 {
            progressSlider.value = progress
            lastDisplayedProgress = progress
        }
    }
}

private final class FullscreenControlsScrimView: UIView {
    enum Direction {
        case top
        case bottom
    }

    private let direction: Direction
    private let gradientLayer = CAGradientLayer()

    init(direction: Direction) {
        self.direction = direction
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        isOpaque = false
        layer.addSublayer(gradientLayer)
        updateGradient()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }

    private func updateGradient() {
        let opacity: CGFloat = direction == .top ? 0.70 : 0.84
        gradientLayer.colors = [
            UIColor.black.withAlphaComponent(opacity).cgColor,
            UIColor.black.withAlphaComponent(opacity * 0.58).cgColor,
            UIColor.black.withAlphaComponent(0).cgColor
        ]
        gradientLayer.locations = [0, 0.48, 1]
        switch direction {
        case .top:
            gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
            gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        case .bottom:
            gradientLayer.startPoint = CGPoint(x: 0.5, y: 1)
            gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
        }
    }
}

private extension UIApplication {
    var biliKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}

private extension ManualVideoFullscreenMode {
    var interfaceOrientationMask: UIInterfaceOrientationMask {
        switch self {
        case .portrait:
            return .portrait
        case .landscape(let orientation):
            return orientation.landscapeInterfaceOrientationMask
        }
    }

    var interfaceOrientation: UIInterfaceOrientation {
        switch self {
        case .portrait:
            return .portrait
        case .landscape(let orientation):
            return orientation.landscapeInterfaceOrientation
        }
    }
}

private extension UIDeviceOrientation {
    var landscapeInterfaceOrientationMask: UIInterfaceOrientationMask {
        switch self {
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        default:
            return .landscapeRight
        }
    }

    var landscapeInterfaceOrientation: UIInterfaceOrientation {
        switch self {
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        default:
            return .landscapeRight
        }
    }
}
