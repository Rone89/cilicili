import SwiftUI
import UIKit

struct VideoSurfaceView: UIViewRepresentable {
    @ObservedObject var viewModel: PlayerStateViewModel
    let manualFullscreenMode: ManualVideoFullscreenMode?
    let onExitManualFullscreen: (() -> Void)?

    func makeUIView(context _: Context) -> VideoSurfaceContainerView {
        let view = VideoSurfaceContainerView()
        view.backgroundColor = .black
        view.onBoundsChange = { [weak viewModel] in
            viewModel?.refreshSurfaceLayout()
        }
        view.onFullscreenTransitionEnd = { [weak viewModel] in
            viewModel?.recoverSurfaceAfterHostFullscreenTransition()
        }
        view.setPlayerViewModel(viewModel)
        view.setManualFullscreenMode(
            manualFullscreenMode,
            onExit: onExitManualFullscreen,
            animated: false
        )
        viewModel.attachSurface(view)
        return view
    }

    func updateUIView(_ uiView: VideoSurfaceContainerView, context _: Context) {
        uiView.onBoundsChange = { [weak viewModel] in
            viewModel?.refreshSurfaceLayout()
        }
        uiView.onFullscreenTransitionEnd = { [weak viewModel] in
            viewModel?.recoverSurfaceAfterHostFullscreenTransition()
        }
        uiView.setPlayerViewModel(viewModel)
        viewModel.attachSurface(uiView)
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
    var onBoundsChange: (() -> Void)?
    var onFullscreenTransitionEnd: (() -> Void)?
    private(set) var isInManualFullscreen = false
    private var lastReportedBounds = CGRect.null
    private var fullscreenState: FullscreenState?
    private var pendingFullscreenMode: ManualVideoFullscreenMode?
    private var onExitFullscreen: (() -> Void)?
    private weak var playerViewModel: PlayerStateViewModel?
    private var lastRequestedOrientationMask: UIInterfaceOrientationMask?

    func setPlayerViewModel(_ viewModel: PlayerStateViewModel) {
        playerViewModel = viewModel
        fullscreenState?.fullscreenController.viewModel = viewModel
    }

    func detachPlayerSurface() {
        playerViewModel?.detachSurface(self)
        playerViewModel = nil
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
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if fullscreenState == nil {
            drawableView.frame = bounds
        }
        guard bounds.width > 1, bounds.height > 1 else { return }
        guard lastReportedBounds.size != bounds.size else { return }
        lastReportedBounds = bounds
        onBoundsChange?()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
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
            fullscreenController.mode = mode
            fullscreenController.onExit = { [weak self] in
                self?.handleExitFullscreenButton()
            }
            fullscreenController.onLayout = { [weak self] in
                self?.applyManualFullscreenLayout(animated: false)
            }

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
            contentView.clipsToBounds = true
            let fullscreenBounds = fullscreenController.view.bounds
            contentView.bounds = CGRect(origin: .zero, size: fullscreenBounds.size)
            contentView.center = CGPoint(x: fullscreenBounds.midX, y: fullscreenBounds.midY)

            fullscreenController.view.addSubview(backdropView)
            fullscreenController.view.addSubview(contentView)
            contentView.addSubview(drawableView)
            drawableView.frame = contentView.bounds
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
            state.lastAppliedBounds = bounds
            state.backdropView.frame = bounds
            state.contentView.transform = .identity
            state.contentView.bounds = CGRect(origin: .zero, size: bounds.size)
            state.contentView.center = CGPoint(x: bounds.midX, y: bounds.midY)
            self.drawableView.transform = .identity
            self.drawableView.frame = state.contentView.bounds
            state.fullscreenController.view.bringSubviewToFront(state.contentView)
            state.fullscreenController.bringPlayerToFront()
            state.fullscreenController.refreshFullscreenLayout(flush: false)
            state.fullscreenController.refreshSystemChrome()
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
    var mode: ManualVideoFullscreenMode = .landscape(.landscapeLeft) {
        didSet {
            controlsOverlay.mode = mode
            setNeedsUpdateOfSupportedInterfaceOrientations()
            view.setNeedsLayout()
            refreshFullscreenLayout()
        }
    }
    private let controlsOverlay = ManualFullscreenPlaybackControlsView()
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

    private func refreshControlsOverlayVisibility() {
        let usesNativeControls = viewModel?.usesNativePlaybackControls == true
        controlsOverlay.isHidden = false
        controlsOverlay.suppressesPlaybackChrome = usesNativeControls
        controlsOverlay.isUserInteractionEnabled = !usesNativeControls
        view.bringSubviewToFront(controlsOverlay)
    }
}

@MainActor
private final class ManualFullscreenPlaybackControlsView: UIView, UIGestureRecognizerDelegate {
    weak var viewModel: PlayerStateViewModel? {
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

    private let topChrome = FullscreenControlsGlassView(direction: .top)
    private let bottomChrome = FullscreenControlsGlassView(direction: .bottom)
    private let exitButton = UIButton(type: .system)
    private let rewindButton = UIButton(type: .system)
    private let playPauseButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let currentTimeLabel = UILabel()
    private let durationLabel = UILabel()
    private let progressSlider = UISlider()
    private let controlsStack = UIStackView()
    private let feedbackView = UIView()
    private let feedbackImageView = UIImageView()
    private var isControlsVisible = true
    private var isScrubbing = false
    private var lastKnownPlayingState = false
    private var refreshTimer: Timer?
    private var autoHideControlsTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    private var lastFullscreenLayoutSize: CGSize = .zero
    private var exitButtonTopConstraint: NSLayoutConstraint?
    private var controlsStackBottomConstraint: NSLayoutConstraint?
    private var topChromeHeightConstraint: NSLayoutConstraint?
    private var bottomChromeHeightConstraint: NSLayoutConstraint?

    private lazy var singleTapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        gesture.numberOfTapsRequired = 1
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()

    private lazy var doubleTapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        gesture.numberOfTapsRequired = 2
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

        [topChrome, bottomChrome, controlsStack, exitButton, feedbackView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        let exitButtonTopConstraint = exitButton.topAnchor.constraint(equalTo: topAnchor, constant: 10)
        let controlsStackBottomConstraint = controlsStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        let topChromeHeightConstraint = topChrome.heightAnchor.constraint(equalToConstant: 92)
        let bottomChromeHeightConstraint = bottomChrome.heightAnchor.constraint(equalToConstant: 138)
        self.exitButtonTopConstraint = exitButtonTopConstraint
        self.controlsStackBottomConstraint = controlsStackBottomConstraint
        self.topChromeHeightConstraint = topChromeHeightConstraint
        self.bottomChromeHeightConstraint = bottomChromeHeightConstraint

        NSLayoutConstraint.activate([
            topChrome.leadingAnchor.constraint(equalTo: leadingAnchor),
            topChrome.trailingAnchor.constraint(equalTo: trailingAnchor),
            topChrome.topAnchor.constraint(equalTo: topAnchor),
            topChromeHeightConstraint,

            bottomChrome.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomChrome.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomChrome.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomChromeHeightConstraint,

            exitButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 18),
            exitButtonTopConstraint,

            controlsStack.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 18),
            controlsStack.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -18),
            controlsStackBottomConstraint,

            feedbackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            feedbackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            feedbackView.widthAnchor.constraint(equalToConstant: 88),
            feedbackView.heightAnchor.constraint(equalToConstant: 88)
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
        let topInset = max(safeAreaInsets.top, minimumTopInset)
        let bottomInset = max(safeAreaInsets.bottom, minimumBottomInset)
        exitButtonTopConstraint?.constant = topInset + (isPortraitFullscreen ? 10 : 8)
        controlsStackBottomConstraint?.constant = -(bottomInset + (isPortraitFullscreen ? 18 : 16))
        topChromeHeightConstraint?.constant = topInset + (isPortraitFullscreen ? 84 : 92)
        bottomChromeHeightConstraint?.constant = bottomInset + (isPortraitFullscreen ? 148 : 138)
        bottomChrome.setNeedsLayout()
        topChrome.setNeedsLayout()
        let roundedSize = CGSize(width: bounds.width.rounded(), height: bounds.height.rounded())
        guard roundedSize != lastFullscreenLayoutSize else { return }
        lastFullscreenLayoutSize = roundedSize
    }

    private func configureGestures() {
        singleTapGesture.require(toFail: doubleTapGesture)
        addGestureRecognizer(singleTapGesture)
        addGestureRecognizer(doubleTapGesture)
    }

    private func configureControls() {
        configureIconButton(exitButton, systemName: "xmark")
        configureIconButton(rewindButton, systemName: "gobackward.10")
        configureIconButton(playPauseButton, systemName: "play.fill", pointSize: 20, isPrimary: true)
        configureIconButton(forwardButton, systemName: "goforward.10")

        exitButton.addTarget(self, action: #selector(handleExitButton), for: .touchUpInside)
        rewindButton.addTarget(self, action: #selector(handleRewindButton), for: .touchUpInside)
        playPauseButton.addTarget(self, action: #selector(handlePlayPauseButton), for: .touchUpInside)
        forwardButton.addTarget(self, action: #selector(handleForwardButton), for: .touchUpInside)

        [currentTimeLabel, durationLabel].forEach { label in
            label.textColor = .white.withAlphaComponent(0.92)
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            label.textAlignment = label === currentTimeLabel ? .left : .right
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
            label.widthAnchor.constraint(equalToConstant: 48).isActive = true
        }

        progressSlider.minimumValue = 0
        progressSlider.maximumValue = 1
        let progressColor = UIColor(red: 1.0, green: 0.25, blue: 0.50, alpha: 1)
        progressSlider.minimumTrackTintColor = progressColor
        progressSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.22)
        progressSlider.setMinimumTrackImage(Self.sliderTrackImage(height: 3.4, color: progressColor), for: .normal)
        progressSlider.setMaximumTrackImage(Self.sliderTrackImage(height: 3.4, color: UIColor.white.withAlphaComponent(0.22)), for: .normal)
        progressSlider.setThumbImage(Self.sliderThumbImage(visualDiameter: 9, canvasDiameter: 23, color: progressColor), for: .normal)
        progressSlider.setThumbImage(Self.sliderThumbImage(visualDiameter: 15, canvasDiameter: 27, color: progressColor), for: .highlighted)
        progressSlider.addTarget(self, action: #selector(handleSliderTouchDown), for: .touchDown)
        progressSlider.addTarget(self, action: #selector(handleSliderValueChanged), for: .valueChanged)
        progressSlider.addTarget(self, action: #selector(handleSliderTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        let buttonRow = UIStackView(arrangedSubviews: [
            rewindButton,
            playPauseButton,
            forwardButton,
            UIView()
        ])
        buttonRow.axis = .horizontal
        buttonRow.alignment = .center
        buttonRow.spacing = 10

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
        controlsStack.spacing = 13
        controlsStack.addArrangedSubview(buttonRow)
        controlsStack.addArrangedSubview(progressRow)

        feedbackView.backgroundColor = UIColor.black.withAlphaComponent(0.46)
        feedbackView.layer.cornerRadius = 44
        feedbackView.alpha = 0
        feedbackView.isUserInteractionEnabled = false
        feedbackImageView.translatesAutoresizingMaskIntoConstraints = false
        feedbackImageView.tintColor = .white
        feedbackImageView.contentMode = .scaleAspectFit
        feedbackView.addSubview(feedbackImageView)
        NSLayoutConstraint.activate([
            feedbackImageView.centerXAnchor.constraint(equalTo: feedbackView.centerXAnchor),
            feedbackImageView.centerYAnchor.constraint(equalTo: feedbackView.centerYAnchor),
            feedbackImageView.widthAnchor.constraint(equalToConstant: 34),
            feedbackImageView.heightAnchor.constraint(equalToConstant: 34)
        ])
    }

    private func configureIconButton(_ button: UIButton, systemName: String, pointSize: CGFloat = 17, isPrimary: Bool = false) {
        var configuration = isPrimary ? UIButton.Configuration.prominentGlass() : UIButton.Configuration.glass()
        configuration.image = UIImage(systemName: systemName)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = isPrimary
            ? UIColor(red: 1.0, green: 0.25, blue: 0.50, alpha: 1)
            : UIColor.white.withAlphaComponent(0.16)
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        button.configuration = configuration
        button.backgroundColor = .clear
        button.tintColor = .white
        button.layer.cornerRadius = 22
        button.layer.borderWidth = 0
        button.layer.shadowColor = UIColor.black.withAlphaComponent(0.24).cgColor
        button.layer.shadowOpacity = isPrimary ? 0.9 : 0.55
        button.layer.shadowRadius = isPrimary ? 10 : 6
        button.layer.shadowOffset = CGSize(width: 0, height: isPrimary ? 5 : 3)
        button.clipsToBounds = false
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
    }

    private func startRefreshTimerIfNeeded() {
        guard refreshTimer == nil else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
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
        progressSlider.isEnabled = isEnabled
        let alpha: CGFloat = isEnabled ? 1 : 0.45
        rewindButton.alpha = alpha
        forwardButton.alpha = alpha
        progressSlider.alpha = alpha
    }

    private func setControlsVisible(_ visible: Bool, animated: Bool) {
        isControlsVisible = visible
        let chromeVisible = visible && !suppressesPlaybackChrome
        let alpha: CGFloat = chromeVisible ? 1 : 0
        let changes = {
            self.topChrome.alpha = alpha
            self.bottomChrome.alpha = alpha
            self.exitButton.alpha = alpha
            self.controlsStack.alpha = alpha
        }
        let completion = {
            self.exitButton.isUserInteractionEnabled = chromeVisible
            self.controlsStack.isUserInteractionEnabled = chromeVisible
        }

        if chromeVisible {
            exitButton.isUserInteractionEnabled = true
            controlsStack.isUserInteractionEnabled = true
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

    @objc private func handleDoubleTap() {
        guard let viewModel else { return }
        Haptics.medium()
        viewModel.togglePlayback()
        refreshFromViewModel()
        setControlsVisible(true, animated: true)
        showFeedback(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
    }

    @objc private func handleExitButton() {
        Haptics.light()
        onExit?()
    }

    @objc private func handleRewindButton() {
        Haptics.light()
        viewModel?.seek(by: -10)
        refreshFromViewModel()
        setControlsVisible(true, animated: true)
        showFeedback(systemName: "gobackward.10")
    }

    @objc private func handlePlayPauseButton() {
        Haptics.light()
        viewModel?.togglePlayback()
        refreshFromViewModel()
        setControlsVisible(true, animated: true)
    }

    @objc private func handleForwardButton() {
        Haptics.light()
        viewModel?.seek(by: 10)
        refreshFromViewModel()
        setControlsVisible(true, animated: true)
        showFeedback(systemName: "goforward.10")
    }

    @objc private func handleSliderTouchDown() {
        isScrubbing = true
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

    private func showFeedback(systemName: String) {
        feedbackTask?.cancel()
        feedbackImageView.image = UIImage(systemName: systemName)
        feedbackView.transform = CGAffineTransform(scaleX: 0.82, y: 0.82)
        UIView.animate(
            withDuration: 0.16,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            self.feedbackView.alpha = 1
            self.feedbackView.transform = .identity
        }
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

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let touchedView = touch.view else { return true }
        if touchedView.isDescendant(of: controlsStack) || touchedView.isDescendant(of: exitButton) {
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
        glass.tintColor = UIColor.black.withAlphaComponent(direction == .top ? 0.16 : 0.24)
        glass.isInteractive = false
        super.init(effect: glass)
        isUserInteractionEnabled = false
        backgroundColor = .clear
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
