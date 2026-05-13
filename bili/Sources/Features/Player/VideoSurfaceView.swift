import AVKit
import SwiftUI
import UIKit

struct NativePlayerControllerView: UIViewControllerRepresentable {
    @ObservedObject var viewModel: PlayerStateViewModel
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
    @ObservedObject var viewModel: PlayerStateViewModel
    let prefersNativePlaybackControls: Bool
    let manualFullscreenMode: ManualVideoFullscreenMode?
    let onExitManualFullscreen: (() -> Void)?
    let manualFullscreenOverlay: AnyView?
    let isDanmakuEnabled: Bool
    let onToggleDanmaku: (() -> Void)?
    let onShowDanmakuSettings: (() -> Void)?

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
        uiView.detachPlayerSurface()
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
    private var pendingFullscreenMode: ManualVideoFullscreenMode?
    private var onExitFullscreen: (() -> Void)?
    private var manualFullscreenOverlay: AnyView?
    private var manualFullscreenIsDanmakuEnabled = true
    private var onToggleManualFullscreenDanmaku: (() -> Void)?
    private var onShowManualFullscreenDanmakuSettings: (() -> Void)?
    private weak var playerViewModel: PlayerStateViewModel?
    private var lastRequestedOrientationMask: UIInterfaceOrientationMask?

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

    func detachPlayerSurface() {
        playerViewModel?.detachSurface(self)
        setNativePlaybackControllerEnabled(false)
        playerViewModel = nil
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

    func setManualFullscreenMode(
        _ mode: ManualVideoFullscreenMode?,
        onExit: (() -> Void)?,
        animated: Bool
    ) {
        onExitFullscreen = onExit

        guard !isNativePlaybackControllerEnabled else {
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
            pendingFullscreenMode = nil
            return
        }

        guard let sourceWindow = window ?? UIApplication.shared.biliKeyWindow,
              let windowScene = sourceWindow.windowScene
        else { return }
        _ = windowScene

        if fullscreenState == nil {
            superview?.layoutIfNeeded()
            layoutIfNeeded()
            guard let originalSuperview = drawableView.superview else { return }
            isInManualFullscreen = true
            ManualVideoFullscreenSession.begin(retaining: self)

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

            let fullscreenSuperview = sourceWindow.rootViewController?.view ?? sourceWindow
            fullscreenController.view.frame = fullscreenSuperview.bounds
            fullscreenController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            if let parentController = sourceWindow.rootViewController {
                parentController.addChild(fullscreenController)
                fullscreenSuperview.addSubview(fullscreenController.view)
                fullscreenController.didMove(toParent: parentController)
            } else {
                fullscreenSuperview.addSubview(fullscreenController.view)
            }
            fullscreenController.refreshSystemChrome()

            let startFrameInSourceWindow = originalSuperview.convert(originalFrame, to: sourceWindow)
            let startFrame = sourceWindow.convert(startFrameInSourceWindow, to: fullscreenSuperview)
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
            contentView.bounds = CGRect(origin: .zero, size: fullscreenBounds.size)
            contentView.center = CGPoint(x: fullscreenBounds.midX, y: fullscreenBounds.midY)

            fullscreenController.view.addSubview(backdropView)
            fullscreenController.view.addSubview(contentView)
            contentView.addSubview(drawableView)
            drawableView.frame = contentView.bounds
            playerViewModel?.refreshSurfaceLayout()
            fullscreenController.bringPlayerToFront()

            fullscreenState = FullscreenState(
                sourceWindow: sourceWindow,
                fullscreenController: fullscreenController,
                fullscreenSuperview: fullscreenSuperview,
                originalSuperview: originalSuperview,
                originalIndex: originalIndex,
                originalFrame: originalFrame,
                originalWindowFrame: startFrame,
                backdropView: backdropView,
                contentView: contentView,
                mode: mode
            )
            fullscreenController.onExit = { [weak self] in
                self?.handleExitFullscreenButton()
            }
            fullscreenController.onLayout = { [weak self] in
                self?.applyManualFullscreenLayout(animated: false)
            }
            playerViewModel?.setHostFullscreenActive(true, exitTarget: self)
            playerViewModel?.recoverSurfaceAfterHostFullscreenTransition()
            applyManualFullscreenLayout(animated: false)
        }

        if fullscreenState?.mode != mode {
            fullscreenState?.mode = mode
            fullscreenState?.fullscreenController.mode = mode
        }
        playerViewModel?.setHostFullscreenActive(true, exitTarget: self)
        requestGeometry(for: fullscreenState?.sourceWindow ?? sourceWindow, mode: mode)
        applyManualFullscreenLayout(animated: animated)
    }

    private func exitManualFullscreen(animated: Bool) {
        guard let state = fullscreenState else { return }
        requestPortraitGeometry(for: state.sourceWindow)

        let restoreIntoOriginalHierarchy = { [weak self] in
            guard let self else { return }
            let index = min(state.originalIndex, state.originalSuperview.subviews.count)
            state.originalSuperview.insertSubview(self.drawableView, at: index)
            self.drawableView.transform = .identity
            self.drawableView.frame = self.bounds
            state.fullscreenController.onExit = nil
            state.fullscreenController.viewModel = nil
            state.fullscreenController.willMove(toParent: nil)
            state.fullscreenController.view.removeFromSuperview()
            state.fullscreenController.removeFromParent()
            self.fullscreenState = nil
            self.lastRequestedOrientationMask = nil
            self.isInManualFullscreen = false
            ManualVideoFullscreenSession.end(retaining: self)
            self.playerViewModel?.setHostFullscreenActive(false, exitTarget: nil)
            self.playerViewModel?.recoverSurfaceAfterHostFullscreenTransition()
            self.finishManualFullscreenTransition()
        }

        guard animated else {
            restoreIntoOriginalHierarchy()
            return
        }

        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            state.fullscreenController.view.alpha = 0
        } completion: { _ in
            state.fullscreenController.view.alpha = 1
            restoreIntoOriginalHierarchy()
        }
    }

    private func applyManualFullscreenLayout(animated: Bool) {
        guard let state = fullscreenState else { return }

        let bounds = state.fullscreenController.view.bounds
        let needsLayout = state.lastAppliedBounds.size != bounds.size
            || state.contentView.bounds.size != bounds.size
            || state.backdropView.frame.size != bounds.size

        guard needsLayout else {
            onFullscreenTransitionEnd?()
            return
        }

        let applyLayout = {
            UIView.performWithoutAnimation {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                state.lastAppliedBounds = bounds
                state.backdropView.frame = bounds
                state.contentView.transform = .identity
                state.contentView.bounds = CGRect(origin: .zero, size: bounds.size)
                state.contentView.center = CGPoint(x: bounds.midX, y: bounds.midY)
                self.drawableView.transform = .identity
                self.drawableView.frame = state.contentView.bounds
                self.playerViewModel?.refreshSurfaceLayout()
                state.fullscreenController.view.bringSubviewToFront(state.contentView)
                state.fullscreenController.bringPlayerToFront()
                state.fullscreenController.refreshFullscreenLayout(flush: false)
                state.fullscreenController.refreshSystemChrome()
                CATransaction.commit()
            }
        }

        let finish = { [weak self] in
            self?.finishManualFullscreenTransition()
        }

        guard animated else {
            applyLayout()
            finish()
            return
        }

        UIView.animate(
            withDuration: 0.24,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            applyLayout()
        } completion: { _ in
            finish()
        }
    }

    private func requestPortraitGeometry(for window: UIWindow) {
        guard let windowScene = window.windowScene else { return }
        guard lastRequestedOrientationMask != .portrait else { return }
        lastRequestedOrientationMask = .portrait
        AppOrientationLock.update(to: .portrait, in: windowScene)
        windowScene.requestGeometryUpdate(
            UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .portrait)
        ) { _ in }
    }

    private func requestGeometry(for window: UIWindow, mode: ManualVideoFullscreenMode) {
        guard let windowScene = window.windowScene else { return }
        let mask = mode.interfaceOrientationMask
        guard lastRequestedOrientationMask != mask else { return }
        lastRequestedOrientationMask = mask
        AppOrientationLock.update(to: mask, in: windowScene)
        windowScene.requestGeometryUpdate(
            UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)
        ) { _ in }
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
        let fullscreenController: ManualVideoFullscreenViewController
        weak var fullscreenSuperview: UIView?
        weak var originalSuperview: UIView!
        let originalIndex: Int
        let originalFrame: CGRect
        let originalWindowFrame: CGRect
        let backdropView: UIView
        let contentView: UIView
        var mode: ManualVideoFullscreenMode
        var lastAppliedBounds = CGRect.null

        init(
            sourceWindow: UIWindow,
            fullscreenController: ManualVideoFullscreenViewController,
            fullscreenSuperview: UIView,
            originalSuperview: UIView,
            originalIndex: Int,
            originalFrame: CGRect,
            originalWindowFrame: CGRect,
            backdropView: UIView,
            contentView: UIView,
            mode: ManualVideoFullscreenMode
        ) {
            self.sourceWindow = sourceWindow
            self.fullscreenController = fullscreenController
            self.fullscreenSuperview = fullscreenSuperview
            self.originalSuperview = originalSuperview
            self.originalIndex = originalIndex
            self.originalFrame = originalFrame
            self.originalWindowFrame = originalWindowFrame
            self.backdropView = backdropView
            self.contentView = contentView
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

private final class ManualVideoFullscreenViewController: UIViewController {
    var onExit: (() -> Void)? {
        didSet {
            controlsOverlay.onExit = onExit
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
        coordinator.animate { [weak self] _ in
            guard let self else { return }
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
            self.controlsOverlay.refreshFullscreenLayout()
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
            }
        }
        didSet {
            lastKnownPlayingState = viewModel?.isPlaying ?? false
            refreshFromViewModel()
            scheduleAutoHideIfNeeded()
        }
    }
    var onExit: (() -> Void)?
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

    private let bottomChrome = FullscreenControlsGlassView(direction: .bottom)
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
    private var isControlsVisible = true
    private var isScrubbing = false
    private var longPressRateRestoreValue: BiliPlaybackRate?
    private var lastKnownPlayingState = false
    private var lastFeedbackRegion: ManualFullscreenTapRegion = .center
    private var refreshTimer: Timer?
    private var autoHideControlsTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    private var isDanmakuEnabled = true
    private var onToggleDanmaku: (() -> Void)?
    private var onShowDanmakuSettings: (() -> Void)?
    private var lastFullscreenLayoutSize: CGSize = .zero
    private var exitButtonTopConstraint: NSLayoutConstraint?
    private var transportCenterYConstraint: NSLayoutConstraint?
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
        refreshTimer?.invalidate()
        autoHideControlsTask?.cancel()
        feedbackTask?.cancel()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            refreshTimer?.invalidate()
            refreshTimer = nil
            autoHideControlsTask?.cancel()
            feedbackTask?.cancel()
            restoreLongPressPlaybackRateIfNeeded()
        } else {
            startRefreshTimerIfNeeded()
            setControlsVisible(true, animated: false)
            scheduleAutoHideIfNeeded()
        }
    }

    private func configureView() {
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = true

        [bottomChrome, controlsStack, transportStack, exitButton, topActionsStack, feedbackView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        let exitButtonTopConstraint = exitButton.topAnchor.constraint(equalTo: topAnchor, constant: 10)
        let transportCenterYConstraint = transportStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        let controlsStackBottomConstraint = controlsStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        let bottomChromeHeightConstraint = bottomChrome.heightAnchor.constraint(equalToConstant: 62)
        let feedbackCenterXConstraint = feedbackView.centerXAnchor.constraint(equalTo: centerXAnchor)
        self.exitButtonTopConstraint = exitButtonTopConstraint
        self.transportCenterYConstraint = transportCenterYConstraint
        self.controlsStackBottomConstraint = controlsStackBottomConstraint
        self.bottomChromeHeightConstraint = bottomChromeHeightConstraint
        self.feedbackCenterXConstraint = feedbackCenterXConstraint

        NSLayoutConstraint.activate([
            bottomChrome.leadingAnchor.constraint(equalTo: controlsStack.leadingAnchor, constant: -12),
            bottomChrome.trailingAnchor.constraint(equalTo: controlsStack.trailingAnchor, constant: 12),
            bottomChrome.bottomAnchor.constraint(equalTo: controlsStack.bottomAnchor, constant: 12),
            bottomChromeHeightConstraint,

            exitButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 14),
            exitButtonTopConstraint,

            topActionsStack.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -14),
            topActionsStack.centerYAnchor.constraint(equalTo: exitButton.centerYAnchor),

            controlsStack.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 14),
            controlsStack.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -14),
            controlsStackBottomConstraint,

            transportStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            transportCenterYConstraint,

            feedbackCenterXConstraint,
            feedbackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            feedbackView.widthAnchor.constraint(equalToConstant: 92),
            feedbackView.heightAnchor.constraint(equalToConstant: 78)
        ])
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
        transportCenterYConstraint?.constant = isPortraitFullscreen ? -12 : 0
        bottomChromeHeightConstraint?.constant = isPortraitFullscreen
            ? 70
            : 62
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
    }

    private func configureControls() {
        configureTopButton(exitButton, systemName: "xmark")
        configureTopButton(danmakuButton, systemName: "text.bubble.fill", pointSize: 14)
        configureTopButton(danmakuSettingsButton, systemName: "slider.horizontal.3", pointSize: 14)
        configureTransportButton(rewindButton, systemName: "gobackward.10", size: 54)
        configureTransportButton(playPauseButton, systemName: "play.fill", size: 78, pointSize: 28, isPrimary: true)
        configureTransportButton(forwardButton, systemName: "goforward.10", size: 54)
        exitButton.accessibilityLabel = "退出全屏"
        danmakuButton.accessibilityLabel = "弹幕"
        danmakuSettingsButton.accessibilityLabel = "弹幕设置"
        rewindButton.accessibilityLabel = "后退 10 秒"
        playPauseButton.accessibilityLabel = "播放"
        forwardButton.accessibilityLabel = "前进 10 秒"

        exitButton.addTarget(self, action: #selector(handleExitButton), for: .touchUpInside)
        danmakuButton.addTarget(self, action: #selector(handleDanmakuButton), for: .touchUpInside)
        danmakuSettingsButton.addTarget(self, action: #selector(handleDanmakuSettingsButton), for: .touchUpInside)
        rewindButton.addTarget(self, action: #selector(handleRewindButton), for: .touchUpInside)
        playPauseButton.addTarget(self, action: #selector(handlePlayPauseButton), for: .touchUpInside)
        forwardButton.addTarget(self, action: #selector(handleForwardButton), for: .touchUpInside)

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
        transportStack.addArrangedSubview(rewindButton)
        transportStack.addArrangedSubview(playPauseButton)
        transportStack.addArrangedSubview(forwardButton)

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

        feedbackView.backgroundColor = .clear
        feedbackView.layer.cornerRadius = 39
        feedbackView.layer.cornerCurve = .continuous
        let feedbackGlass = UIGlassEffect(style: .regular)
        feedbackGlass.tintColor = UIColor.black.withAlphaComponent(0.18)
        feedbackGlass.isInteractive = false
        let feedbackGlassView = UIVisualEffectView(effect: feedbackGlass)
        feedbackGlassView.translatesAutoresizingMaskIntoConstraints = false
        feedbackGlassView.clipsToBounds = true
        feedbackGlassView.layer.cornerRadius = 39
        feedbackGlassView.layer.cornerCurve = .continuous
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
        feedbackView.addSubview(feedbackGlassView)
        feedbackView.addSubview(feedbackImageView)
        feedbackView.addSubview(feedbackLabel)
        let feedbackImageCenterYConstraint = feedbackImageView.centerYAnchor.constraint(equalTo: feedbackView.centerYAnchor)
        self.feedbackImageCenterYConstraint = feedbackImageCenterYConstraint
        NSLayoutConstraint.activate([
            feedbackGlassView.leadingAnchor.constraint(equalTo: feedbackView.leadingAnchor),
            feedbackGlassView.trailingAnchor.constraint(equalTo: feedbackView.trailingAnchor),
            feedbackGlassView.topAnchor.constraint(equalTo: feedbackView.topAnchor),
            feedbackGlassView.bottomAnchor.constraint(equalTo: feedbackView.bottomAnchor),
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
        danmakuButton.configuration?.image = UIImage(systemName: isDanmakuEnabled ? "text.bubble.fill" : "text.bubble")
        danmakuButton.alpha = isDanmakuEnabled ? 1 : 0.62
        danmakuButton.accessibilityLabel = isDanmakuEnabled ? "关闭弹幕" : "开启弹幕"
    }

    private func configureTopButton(_ button: UIButton, systemName: String, pointSize: CGFloat = 15) {
        var configuration = UIButton.Configuration.glass()
        configuration.image = UIImage(systemName: systemName)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.10)
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        button.configuration = configuration
        button.backgroundColor = .clear
        button.tintColor = .white
        button.overrideUserInterfaceStyle = .dark
        button.layer.cornerRadius = 20
        button.layer.borderWidth = 0.7
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.22).cgColor
        button.layer.shadowColor = UIColor.black.withAlphaComponent(0.24).cgColor
        button.layer.shadowOpacity = 0.42
        button.layer.shadowRadius = 8
        button.layer.shadowOffset = CGSize(width: 0, height: 4)
        button.clipsToBounds = false
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
        var configuration = UIButton.Configuration.glass()
        configuration.image = UIImage(systemName: systemName)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: pointSize ?? (size * 0.29),
            weight: .bold
        )
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = isPrimary
            ? UIColor.black.withAlphaComponent(0.22)
            : UIColor.black.withAlphaComponent(0.14)
        configuration.cornerStyle = .capsule
        let leadingInset: CGFloat = systemName == "play.fill" ? 4 : 0
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: leadingInset, bottom: 0, trailing: 0)
        configuration.imagePadding = 0
        button.configuration = configuration
        button.backgroundColor = .clear
        button.tintColor = .white
        button.overrideUserInterfaceStyle = .dark
        button.layer.cornerRadius = size / 2
        button.layer.borderWidth = 0.8
        button.layer.borderColor = UIColor.white.withAlphaComponent(isPrimary ? 0.18 : 0.16).cgColor
        button.layer.shadowColor = UIColor.black.withAlphaComponent(0.30).cgColor
        button.layer.shadowOpacity = isPrimary ? 0.72 : 0.48
        button.layer.shadowRadius = isPrimary ? 18 : 12
        button.layer.shadowOffset = CGSize(width: 0, height: isPrimary ? 8 : 5)
        button.clipsToBounds = false
        button.widthAnchor.constraint(equalToConstant: size).isActive = true
        button.heightAnchor.constraint(equalToConstant: size).isActive = true
    }

    private func startRefreshTimerIfNeeded() {
        guard refreshTimer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshFromViewModel()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func refreshFromViewModel() {
        guard let viewModel else {
            currentTimeLabel.text = BiliFormatters.duration(0)
            durationLabel.text = BiliFormatters.duration(0)
            progressSlider.value = 0
            setTransportEnabled(false)
            return
        }

        let duration = max(viewModel.displayDuration ?? 0, 0)
        let currentTime = max(viewModel.currentTime, 0)
        let progress = duration > 0 ? min(max(currentTime / duration, 0), 1) : 0
        let canSeek = viewModel.canSeek && duration > 0

        if !isScrubbing {
            currentTimeLabel.text = BiliFormatters.duration(Int(currentTime.rounded()))
            durationLabel.text = duration > 0 ? BiliFormatters.duration(Int(duration.rounded())) : BiliFormatters.duration(0)
            progressSlider.value = Float(progress)
        }

        setTransportEnabled(canSeek)
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

    private func setControlsVisible(_ visible: Bool, animated: Bool) {
        isControlsVisible = visible
        let chromeVisible = visible && !suppressesPlaybackChrome
        let alpha: CGFloat = chromeVisible ? 1 : 0
        let changes = {
            self.bottomChrome.alpha = alpha
            self.exitButton.alpha = alpha
            self.topActionsStack.alpha = alpha
            self.transportStack.alpha = alpha
            self.controlsStack.alpha = alpha
            self.transportStack.transform = chromeVisible
                ? .identity
                : CGAffineTransform(scaleX: 0.88, y: 0.88)
        }
        let completion = {
            self.exitButton.isUserInteractionEnabled = chromeVisible
            self.topActionsStack.isUserInteractionEnabled = chromeVisible
            self.transportStack.isUserInteractionEnabled = chromeVisible
            self.controlsStack.isUserInteractionEnabled = chromeVisible
        }

        if chromeVisible {
            exitButton.isUserInteractionEnabled = true
            topActionsStack.isUserInteractionEnabled = true
            transportStack.isUserInteractionEnabled = true
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
            animateTransportButton(rewindButton)
            showFeedback(systemName: "gobackward.10", title: "-10s", region: .leading)
        case .trailing:
            guard viewModel.canSeek else { return }
            viewModel.seek(by: 10)
            refreshFromViewModel()
            if isControlsVisible {
                scheduleAutoHideIfNeeded()
            }
            animateTransportButton(forwardButton)
            showFeedback(systemName: "goforward.10", title: "+10s", region: .trailing)
        case .center:
            viewModel.togglePlayback()
            refreshFromViewModel()
            setControlsVisible(true, animated: true)
            animateTransportButton(playPauseButton)
            showFeedback(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill", region: .center)
        }
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            beginLongPressSpeedBoost()
        case .ended, .cancelled, .failed:
            endLongPressSpeedBoost()
        default:
            break
        }
    }

    @objc private func handleExitButton() {
        Haptics.light()
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
        viewModel?.togglePlayback()
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
        guard let viewModel, viewModel.isPlaying, longPressRateRestoreValue == nil else { return }
        longPressRateRestoreValue = viewModel.playbackRate
        Haptics.medium()
        viewModel.setPlaybackRate(.x20)
        autoHideControlsTask?.cancel()
        autoHideControlsTask = nil
        setControlsVisible(false, animated: true)
        showFeedback(systemName: "forward.fill", title: "2.0x", region: .center, persists: true)
    }

    private func endLongPressSpeedBoost() {
        restoreLongPressPlaybackRateIfNeeded()
        scheduleAutoHideIfNeeded()
    }

    private func restoreLongPressPlaybackRateIfNeeded() {
        guard let restoreRate = longPressRateRestoreValue else { return }
        longPressRateRestoreValue = nil
        viewModel?.setPlaybackRate(restoreRate)
        if feedbackLabel.text == "2.0x" {
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
        autoHideControlsTask?.cancel()
    }

    @objc private func handleSliderValueChanged() {
        let duration = max(viewModel?.displayDuration ?? 0, 0)
        let targetTime = TimeInterval(progressSlider.value) * duration
        currentTimeLabel.text = BiliFormatters.duration(Int(targetTime.rounded()))
    }

    @objc private func handleSliderTouchUp() {
        let targetProgress = Double(progressSlider.value)
        isScrubbing = false
        Haptics.light()
        viewModel?.seekAfterUserScrub(to: targetProgress)
        refreshFromViewModel()
        scheduleAutoHideIfNeeded()
    }

    private func showFeedback(
        systemName: String,
        title: String? = nil,
        region: ManualFullscreenTapRegion,
        persists: Bool = false
    ) {
        feedbackTask?.cancel()
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
}

private final class FullscreenControlsGlassView: UIVisualEffectView {
    enum Direction {
        case top
        case bottom
    }

    init(direction: Direction) {
        let glass = UIGlassEffect(style: .regular)
        glass.tintColor = UIColor.black.withAlphaComponent(direction == .top ? 0.14 : 0.16)
        glass.isInteractive = false
        super.init(effect: glass)
        isUserInteractionEnabled = false
        overrideUserInterfaceStyle = .dark
        backgroundColor = .clear
        clipsToBounds = true
        layer.cornerCurve = .continuous
        layer.cornerRadius = direction == .top ? 29 : 26
        layer.borderWidth = 0.7
        layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
