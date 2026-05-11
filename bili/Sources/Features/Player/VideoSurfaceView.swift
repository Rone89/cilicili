import SwiftUI
import UIKit

struct VideoSurfaceView: UIViewRepresentable {
    @ObservedObject var viewModel: PlayerStateViewModel
    let manualFullscreenOrientation: UIDeviceOrientation?
    let onExitManualFullscreen: (() -> Void)?

    func makeUIView(context _: Context) -> VideoSurfaceContainerView {
        let view = VideoSurfaceContainerView()
        view.backgroundColor = .black
        view.onBoundsChange = { [weak viewModel] in
            viewModel?.refreshSurfaceLayout()
        }
        view.onFullscreenTransitionEnd = { [weak viewModel] in
            viewModel?.refreshSurfaceLayout()
        }
        view.setPlayerViewModel(viewModel)
        view.setManualFullscreenOrientation(
            manualFullscreenOrientation,
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
            viewModel?.refreshSurfaceLayout()
        }
        uiView.setPlayerViewModel(viewModel)
        viewModel.attachSurface(uiView)
        uiView.setManualFullscreenOrientation(
            manualFullscreenOrientation,
            onExit: onExitManualFullscreen,
            animated: true
        )
    }

    static func dismantleUIView(_ uiView: VideoSurfaceContainerView, coordinator _: ()) {
        guard !ManualVideoFullscreenSession.isActive else { return }
        uiView.setManualFullscreenOrientation(nil, onExit: nil, animated: false)
        uiView.detachPlayerSurface()
    }
}

final class VideoSurfaceContainerView: UIView {
    let drawableView = UIView()
    var onBoundsChange: (() -> Void)?
    var onFullscreenTransitionEnd: (() -> Void)?
    private var lastReportedBounds = CGRect.null
    private var fullscreenState: FullscreenState?
    private var pendingFullscreenOrientation: UIDeviceOrientation?
    private var onExitFullscreen: (() -> Void)?
    private weak var playerViewModel: PlayerStateViewModel?

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
        guard let pendingFullscreenOrientation else { return }
        self.pendingFullscreenOrientation = nil
        setManualFullscreenOrientation(pendingFullscreenOrientation, onExit: onExitFullscreen, animated: false)
    }

    func setManualFullscreenOrientation(
        _ orientation: UIDeviceOrientation?,
        onExit: (() -> Void)?,
        animated: Bool
    ) {
        onExitFullscreen = onExit

        guard let orientation, orientation.isLandscape else {
            pendingFullscreenOrientation = nil
            exitManualFullscreen(animated: animated)
            return
        }

        guard window != nil || UIApplication.shared.biliKeyWindow != nil else {
            pendingFullscreenOrientation = orientation
            return
        }

        enterOrUpdateManualFullscreen(orientation: orientation, animated: animated)
    }

    @objc private func handleExitFullscreenButton() {
        onExitFullscreen?()
    }

    private func enterOrUpdateManualFullscreen(orientation: UIDeviceOrientation, animated: Bool) {
        guard let sourceWindow = window ?? UIApplication.shared.biliKeyWindow,
              let windowScene = sourceWindow.windowScene
        else { return }
        _ = windowScene

        if fullscreenState == nil {
            superview?.layoutIfNeeded()
            layoutIfNeeded()
            guard let originalSuperview = drawableView.superview else { return }
            ManualVideoFullscreenSession.begin()

            let originalFrame = drawableView.frame
            let originalIndex = originalSuperview.subviews.firstIndex(of: drawableView) ?? originalSuperview.subviews.count
            let previousKeyWindow = UIApplication.shared.biliKeyWindow
            let fullscreenController = ManualVideoFullscreenViewController()
            fullscreenController.viewModel = playerViewModel
            fullscreenController.orientation = orientation
            fullscreenController.onExit = { [weak self] in
                self?.handleExitFullscreenButton()
            }
            fullscreenController.onLayout = { [weak self] in
                self?.applyManualFullscreenLayout(animated: false)
            }

            let overlayWindow = UIWindow(windowScene: windowScene)
            overlayWindow.windowLevel = .statusBar + 1
            overlayWindow.backgroundColor = .black
            overlayWindow.rootViewController = fullscreenController
            overlayWindow.isHidden = false
            overlayWindow.makeKeyAndVisible()
            fullscreenController.refreshSystemChrome()

            let startFrameInSourceWindow = originalSuperview.convert(originalFrame, to: sourceWindow)
            let startFrame = sourceWindow.convert(startFrameInSourceWindow, to: overlayWindow)
            let backdropView = UIView(frame: fullscreenController.view.bounds)
            backdropView.backgroundColor = .black
            backdropView.isUserInteractionEnabled = false
            backdropView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

            let contentView = UIView()
            contentView.backgroundColor = .black
            contentView.clipsToBounds = true
            contentView.bounds = CGRect(origin: .zero, size: startFrame.size)
            contentView.center = CGPoint(x: startFrame.midX, y: startFrame.midY)

            fullscreenController.view.addSubview(backdropView)
            backdropView.addSubview(contentView)
            contentView.addSubview(drawableView)
            drawableView.frame = contentView.bounds
            fullscreenController.bringControlsToFront()

            fullscreenState = FullscreenState(
                overlayWindow: overlayWindow,
                fullscreenController: fullscreenController,
                previousKeyWindow: previousKeyWindow,
                originalSuperview: originalSuperview,
                originalIndex: originalIndex,
                originalFrame: originalFrame,
                originalWindowFrame: startFrame,
                backdropView: backdropView,
                contentView: contentView,
                orientation: orientation
            )
        }

        fullscreenState?.orientation = orientation
        fullscreenState?.fullscreenController.orientation = orientation
        if let overlayWindow = fullscreenState?.overlayWindow {
            requestLandscapeGeometry(for: overlayWindow, orientation: orientation)
        } else {
            requestLandscapeGeometry(for: sourceWindow, orientation: orientation)
        }
        applyManualFullscreenLayout(animated: animated)
    }

    private func exitManualFullscreen(animated: Bool) {
        guard let state = fullscreenState else { return }
        requestPortraitGeometry(for: state.overlayWindow)

        let restoreIntoOriginalHierarchy = { [weak self] in
            guard let self else { return }
            let index = min(state.originalIndex, state.originalSuperview.subviews.count)
            state.originalSuperview.insertSubview(self.drawableView, at: index)
            self.drawableView.transform = .identity
            self.drawableView.frame = self.bounds
            state.fullscreenController.onExit = nil
            state.fullscreenController.viewModel = nil
            state.overlayWindow.isHidden = true
            state.overlayWindow.rootViewController = nil
            state.previousKeyWindow?.makeKey()
            self.fullscreenState = nil
            ManualVideoFullscreenSession.end()
            self.onFullscreenTransitionEnd?()
        }

        guard animated else {
            restoreIntoOriginalHierarchy()
            return
        }

        let targetFrame = state.originalSuperview.window != nil
            ? state.originalSuperview.convert(state.originalFrame, to: state.overlayWindow)
            : state.originalWindowFrame
        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            state.contentView.transform = .identity
            state.contentView.bounds = CGRect(origin: .zero, size: targetFrame.size)
            state.contentView.center = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
            self.drawableView.frame = state.contentView.bounds
        } completion: { _ in
            restoreIntoOriginalHierarchy()
        }
    }

    private func applyManualFullscreenLayout(animated: Bool) {
        guard let state = fullscreenState else { return }

        let bounds = state.fullscreenController.view.bounds

        let applyLayout = {
            state.backdropView.frame = bounds
            state.contentView.transform = .identity
            state.contentView.bounds = CGRect(origin: .zero, size: bounds.size)
            state.contentView.center = CGPoint(x: bounds.midX, y: bounds.midY)
            self.drawableView.transform = .identity
            self.drawableView.frame = state.contentView.bounds
            state.fullscreenController.view.bringSubviewToFront(state.backdropView)
            state.fullscreenController.bringControlsToFront()
            state.fullscreenController.refreshSystemChrome()
        }

        let finish = { [weak self] in
            self?.onFullscreenTransitionEnd?()
        }

        guard animated else {
            applyLayout()
            finish()
            return
        }

        UIView.animate(
            withDuration: 0.28,
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
        AppOrientationLock.update(to: .portrait, in: windowScene)
        if #available(iOS 16.0, *) {
            windowScene.requestGeometryUpdate(
                UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .portrait)
            ) { _ in }
        }
    }

    private func requestLandscapeGeometry(for window: UIWindow, orientation: UIDeviceOrientation) {
        guard let windowScene = window.windowScene else { return }
        let mask = orientation.landscapeInterfaceOrientationMask
        AppOrientationLock.update(to: mask, in: windowScene)
        if #available(iOS 16.0, *) {
            windowScene.requestGeometryUpdate(
                UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)
            ) { _ in }
        }
    }

    private final class FullscreenState {
        let overlayWindow: UIWindow
        let fullscreenController: ManualVideoFullscreenViewController
        weak var previousKeyWindow: UIWindow?
        weak var originalSuperview: UIView!
        let originalIndex: Int
        let originalFrame: CGRect
        let originalWindowFrame: CGRect
        let backdropView: UIView
        let contentView: UIView
        var orientation: UIDeviceOrientation

        init(
            overlayWindow: UIWindow,
            fullscreenController: ManualVideoFullscreenViewController,
            previousKeyWindow: UIWindow?,
            originalSuperview: UIView,
            originalIndex: Int,
            originalFrame: CGRect,
            originalWindowFrame: CGRect,
            backdropView: UIView,
            contentView: UIView,
            orientation: UIDeviceOrientation
        ) {
            self.overlayWindow = overlayWindow
            self.fullscreenController = fullscreenController
            self.previousKeyWindow = previousKeyWindow
            self.originalSuperview = originalSuperview
            self.originalIndex = originalIndex
            self.originalFrame = originalFrame
            self.originalWindowFrame = originalWindowFrame
            self.backdropView = backdropView
            self.contentView = contentView
            self.orientation = orientation
        }
    }
}

private final class ManualVideoFullscreenViewController: UIViewController {
    var onExit: (() -> Void)?
    var onLayout: (() -> Void)?
    weak var viewModel: PlayerStateViewModel? {
        didSet {
            refreshControls()
        }
    }
    var orientation: UIDeviceOrientation = .landscapeLeft {
        didSet {
            setNeedsUpdateOfSupportedInterfaceOrientations()
            view.setNeedsLayout()
        }
    }

    private let controlsHostView = UIView()
    private let controlsContainer = UIView()
    private let playButton = UIButton(type: .system)
    private let rewindButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let currentTimeLabel = UILabel()
    private let durationLabel = UILabel()
    private let progressSlider = UISlider()
    private let progressStack = UIStackView()
    private let buttonStack = UIStackView()
    private var controlsVisible = true
    private var autoHideTask: Task<Void, Never>?
    private var refreshTimer: Timer?
    private var isScrubbing = false

    override func loadView() {
        let view = UIView()
        view.backgroundColor = .black
        view.isOpaque = true
        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureGestures()
        configureControls()
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
        orientation.landscapeInterfaceOrientationMask
    }

    override var shouldAutorotate: Bool {
        true
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        orientation.landscapeInterfaceOrientation
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshSystemChrome()
        controlsVisible = true
        updateControlsVisibility(animated: false)
        scheduleAutoHide()
        startRefreshTimer()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        autoHideTask?.cancel()
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutControls()
        onLayout?()
    }

    func refreshSystemChrome() {
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
    }

    func bringControlsToFront() {
        guard isViewLoaded else { return }
        view.bringSubviewToFront(controlsHostView)
    }

    private func configureGestures() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleFullscreenTap))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }

    private func configureControls() {
        controlsHostView.backgroundColor = .clear
        controlsHostView.isUserInteractionEnabled = true
        controlsContainer.isUserInteractionEnabled = true
        controlsContainer.backgroundColor = .clear

        [rewindButton, playButton, forwardButton].forEach { button in
            button.tintColor = .white
            button.backgroundColor = UIColor.white.withAlphaComponent(0.14)
            button.layer.cornerRadius = 19
            button.layer.cornerCurve = .continuous
            button.widthAnchor.constraint(equalToConstant: 38).isActive = true
            button.heightAnchor.constraint(equalToConstant: 38).isActive = true
        }

        rewindButton.setImage(UIImage(systemName: "gobackward.10"), for: .normal)
        playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        forwardButton.setImage(UIImage(systemName: "goforward.10"), for: .normal)
        rewindButton.addTarget(self, action: #selector(rewindTapped), for: .touchUpInside)
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        forwardButton.addTarget(self, action: #selector(forwardTapped), for: .touchUpInside)

        [currentTimeLabel, durationLabel].forEach { label in
            label.textColor = UIColor.white.withAlphaComponent(0.92)
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            label.textAlignment = .center
            label.widthAnchor.constraint(equalToConstant: 48).isActive = true
        }

        progressSlider.minimumValue = 0
        progressSlider.maximumValue = 1
        progressSlider.minimumTrackTintColor = UIColor.systemPink
        progressSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.25)
        progressSlider.thumbTintColor = .white
        progressSlider.addTarget(self, action: #selector(sliderTouchDown), for: .touchDown)
        progressSlider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        progressSlider.addTarget(self, action: #selector(sliderTouchFinished), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        buttonStack.axis = .horizontal
        buttonStack.alignment = .center
        buttonStack.spacing = 10
        buttonStack.addArrangedSubview(rewindButton)
        buttonStack.addArrangedSubview(playButton)
        buttonStack.addArrangedSubview(forwardButton)

        progressStack.axis = .horizontal
        progressStack.alignment = .center
        progressStack.spacing = 10
        progressStack.addArrangedSubview(currentTimeLabel)
        progressStack.addArrangedSubview(progressSlider)
        progressStack.addArrangedSubview(durationLabel)

        controlsContainer.addSubview(buttonStack)
        controlsContainer.addSubview(progressStack)
        controlsHostView.addSubview(controlsContainer)
        view.addSubview(controlsHostView)
        refreshControls()
    }

    private func layoutControls() {
        let safe = view.safeAreaInsets
        let bounds = view.bounds
        controlsHostView.transform = .identity
        controlsHostView.frame = bounds

        let bottomInset = max(safe.bottom, 18)
        let horizontalInset: CGFloat = 34
        let availableWidth = max(bounds.width - safe.left - safe.right - horizontalInset * 2, 320)
        let containerHeight: CGFloat = 96
        controlsContainer.frame = CGRect(
            x: safe.left + horizontalInset,
            y: bounds.height - bottomInset - containerHeight,
            width: availableWidth,
            height: containerHeight
        )

        buttonStack.frame = CGRect(x: 0, y: 0, width: controlsContainer.bounds.width, height: 40)
        buttonStack.layoutIfNeeded()
        let buttonWidth = buttonStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width
        buttonStack.frame.origin.x = max((controlsContainer.bounds.width - buttonWidth) / 2, 0)
        buttonStack.frame.size.width = buttonWidth

        progressStack.frame = CGRect(
            x: 0,
            y: 52,
            width: controlsContainer.bounds.width,
            height: 34
        )
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshControls()
            }
        }
    }

    private func refreshControls() {
        guard isViewLoaded else { return }
        guard let viewModel else {
            playButton.isEnabled = false
            rewindButton.isEnabled = false
            forwardButton.isEnabled = false
            currentTimeLabel.text = "00:00"
            durationLabel.text = "--:--"
            progressSlider.value = 0
            return
        }

        playButton.isEnabled = true
        rewindButton.isEnabled = viewModel.canSeek
        forwardButton.isEnabled = viewModel.canSeek
        let playImage = UIImage(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
        playButton.setImage(playImage, for: .normal)
        currentTimeLabel.text = BiliFormatters.duration(Int(viewModel.currentTime.rounded()))
        if let duration = viewModel.displayDuration, duration > 0 {
            durationLabel.text = BiliFormatters.duration(Int(duration.rounded()))
        } else {
            durationLabel.text = "--:--"
        }
        if !isScrubbing {
            progressSlider.value = Float(viewModel.currentProgress)
        }
    }

    @objc private func handleFullscreenTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: controlsHostView)
        guard !controlsContainer.frame.contains(point) else { return }
        controlsVisible.toggle()
        updateControlsVisibility(animated: true)
        if controlsVisible {
            scheduleAutoHide()
        } else {
            autoHideTask?.cancel()
        }
    }

    @objc private func rewindTapped() {
        Haptics.light()
        viewModel?.seek(by: -10)
        handleControlInteraction()
    }

    @objc private func playTapped() {
        Haptics.light()
        viewModel?.togglePlayback()
        handleControlInteraction()
    }

    @objc private func forwardTapped() {
        Haptics.light()
        viewModel?.seek(by: 10)
        handleControlInteraction()
    }

    @objc private func sliderTouchDown() {
        isScrubbing = true
        controlsVisible = true
        updateControlsVisibility(animated: true)
        autoHideTask?.cancel()
    }

    @objc private func sliderValueChanged() {
        guard let duration = viewModel?.displayDuration, duration > 0 else { return }
        let time = Double(progressSlider.value) * duration
        currentTimeLabel.text = BiliFormatters.duration(Int(time.rounded()))
    }

    @objc private func sliderTouchFinished() {
        isScrubbing = false
        Haptics.light()
        viewModel?.seekAfterUserScrub(to: Double(progressSlider.value))
        handleControlInteraction()
    }

    private func handleControlInteraction() {
        controlsVisible = true
        updateControlsVisibility(animated: true)
        refreshControls()
        scheduleAutoHide()
    }

    private func updateControlsVisibility(animated: Bool) {
        let changes = {
            self.controlsHostView.alpha = self.controlsVisible ? 1 : 0
        }
        guard animated else {
            changes()
            return
        }
        UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            changes()
        }
    }

    private func scheduleAutoHide() {
        autoHideTask?.cancel()
        guard viewModel?.isPlaying == true else { return }
        autoHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard let self, !Task.isCancelled, self.viewModel?.isPlaying == true, !self.isScrubbing else { return }
            self.controlsVisible = false
            self.updateControlsVisibility(animated: true)
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
