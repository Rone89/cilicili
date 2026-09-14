import AVFoundation
import Combine
import QuartzCore
import SwiftUI
import UIKit

/// 正式的详情页 UIKit 外壳容器。
///
/// 播放器由 UIKit 容器接管布局，内容区复用现有 SwiftUI 内容
/// `VideoDetailShellContentView`。
/// - 复用现有 `VideoDetailViewModel`（load playurl）、`stablePlayerViewModel`
///   + `VideoSurfaceView` 渲染。
/// - 自己接管布局：竖屏 = 顶部按视频宽高比的播放器 + 下方内容区；横屏 = 播放器全屏。
/// - 旋转走全局 `AppOrientationLock`，`viewWillTransition` 协调块驱动 frame，
///   completion 控制内容区隐藏（照搬原型已验证的防闪黑逻辑）。
@MainActor
final class VideoDetailShellViewController: UIViewController {
    private let viewModel: VideoDetailViewModel
    private let runtimeSettings: VideoDetailRuntimeSettingsStore
    private let dependencies: AppDependencies
    private let onShowDanmakuSettings: () -> Void
    private let onPresentPlayerMoreControls: (PlayerStateViewModel, @escaping () -> Void) -> Void
    private let onDismissPlayerMoreControls: () -> Void
    private let onNavigateBack: () -> Void
    private var cancellables = Set<AnyCancellable>()
    private let systemBackGestureDelegateLease = SystemBackGestureDelegateLease()

    private lazy var playerSurfaceController: PlayerSurfaceController = {
        PlayerSurfaceController(
            parentViewController: self,
            containerView: playerContainer,
            makeHost: { [weak self] playerViewModel in
                self?.makeSurfaceHost(for: playerViewModel)
            },
            onActivePlayerChange: { [weak self] playerViewModel in
                self?.bindPlaybackState(to: playerViewModel)
            }
        )
    }()
    private let playerContainer = UIView()
    private weak var videoSurfaceHost: VideoDetailShellSurfaceHost?
    private let contentHost: UIHostingController<VideoDetailShellContentView>
    private let contentState = VideoDetailShellContentView.State()
    private let contentUpdateGate: VideoDetailContentUpdateGate
    /// 暂停下翻收缩时的折叠工具条（主题色遮罩），盖在 playerContainer 上。
    private var collapsedBarHost: UIHostingController<VideoDetailShellCollapsedBar>?
    private let collapsedDimmingView = UIView()

    /// 视频真实宽高比（surface 用）；拿到真实 dimension 后更新。
    private var videoAspectRatio: CGFloat = 16.0 / 9.0

    /// 竖屏拖动缩放：当前播放器高度，nil 表示用默认（standardHeight）。
    private var currentPlayerHeight: CGFloat?
    /// 竖屏视频的「竖屏全屏」态：播放器占满整屏、不旋转、隐藏内容区。
    private var isPortraitFullscreen = false
    /// 上次滚动偏移，用于暂停时按当前位置重算高度（暂停后 min 变小可继续收缩）。
    private var lastScrollOffset: CGFloat = 0
    /// 播放状态订阅（player 实例变化时重建）。
    private var playbackStateCancellable: AnyCancellable?
    /// 系统旋转期间冻结 SwiftUI chrome/滚动联动，让 live surface 跟随 UIKit frame 动画。
    private var isSystemRotationTransitioning = false
    private let rotationFrameProbe = VideoRotationFrameProbe()
    private var rotationFrameProbeGeneration = 0
    private var rotationCompletionRecoveryDisplayLink: CADisplayLink?
    private var pendingRotationCompletionPreparation: (() -> Void)?
    private var pendingRotationCompletionRecovery: (() -> Void)?
    private var pendingRotationCompletionRecoveryGeneration: Int?
    private var rotationCompletionRecoveryNotBefore: TimeInterval?
    private var rotationCompletionRecoveryGeneration = 0
    private var rotationRecoveryWatchdogTask: Task<Void, Never>?
    private var rotationRequestCoalescer = VideoDetailRotationRequestCoalescer()
    /// VC 是否处于可见活跃态（viewDidAppear~viewWillDisappear 之间）。
    /// 用于防止 $detail sink 在 VC 消失后重新解锁横屏，导致全局朝向锁卡在 landscape。
    private var isViewActive = false
    private var isBackgroundRenderFreezeActive = false
    private let selectedContentTabBinding: Binding<VideoDetailContentTab>
    private var activeContentTab: VideoDetailContentTab
    private var visitedContentTabs: Set<VideoDetailContentTab>
    private var scrollOffsets: [VideoDetailContentTab: CGFloat] = [:]
    private var contentActionSuppressionWorkItem: DispatchWorkItem?
    private var didTearDownPlayerSurface = false

    /// 竖屏标准高度（对齐原项目：固定 16:9，与视频真实比例无关）。
    private func standardPlayerHeight(forWidth width: CGFloat) -> CGFloat {
        PlaybackDetailShellLayout.standardPlayerHeight(for: width)
    }

    /// 是否竖屏视频（aspectRatio < 0.9，对齐原项目）。
    private var isPortraitVideo: Bool {
        videoAspectRatio < 0.9
    }

    /// 缩放上限（对齐原项目 expandedHeight）：竖屏视频放大到屏高 0.65~0.72 区间，
    /// 横屏视频就是 standardHeight。
    private func expandedPlayerHeight(bounds: CGSize) -> CGFloat {
        let standard = standardPlayerHeight(forWidth: bounds.width)
        guard isPortraitVideo else { return standard }
        let proposed = max(bounds.height * 0.65, bounds.width)
        let maximum = max(standard, bounds.height * 0.72)
        return max(standard, min(proposed, maximum))
    }

    /// 缩放下限（对齐原项目）：播放中=standardHeight，暂停=58pt 工具条。
    private func minimumPlayerHeight(forWidth width: CGFloat) -> CGFloat {
        let standard = standardPlayerHeight(forWidth: width)
        let isPlaybackActive = isPlaybackActiveForCollapsedChrome
        return isPlaybackActive ? standard : collapsedToolbarHeight
    }

    private var isPlaybackActiveForCollapsedChrome: Bool {
        guard let player = viewModel.stablePlayerViewModel else { return false }
        return player.isPlaying || player.isUserSeeking
    }

    private let collapsedToolbarHeight: CGFloat = 54

    private var isLandscape: Bool {
        view.bounds.width > view.bounds.height
    }

    private let rotationPolicy = VideoDetailRotationPolicy()

    init(
        viewModel: VideoDetailViewModel,
        runtimeSettings: VideoDetailRuntimeSettingsStore,
        dependencies: AppDependencies,
        openVideoOwnerRoute: ((VideoOwner) -> Void)?,
        selectedContentTab: Binding<VideoDetailContentTab>,
        onShowNetworkDiagnostics: @escaping () -> Void,
        onShowFavoriteFolders: @escaping () -> Void,
        onShowCoinPicker: @escaping () -> Void,
        onOpenCommentComposer: @escaping (Comment?) -> Void,
        onShowDanmakuSettings: @escaping () -> Void,
        onPresentPlayerMoreControls: @escaping (PlayerStateViewModel, @escaping () -> Void) -> Void,
        onDismissPlayerMoreControls: @escaping () -> Void,
        onReply: @escaping (Comment) -> Void,
        onNavigateBack: @escaping () -> Void
    ) {
        let contentUpdateGate = VideoDetailContentUpdateGate()
        self.viewModel = viewModel
        self.runtimeSettings = runtimeSettings
        self.dependencies = dependencies
        self.onShowDanmakuSettings = onShowDanmakuSettings
        self.onPresentPlayerMoreControls = onPresentPlayerMoreControls
        self.onDismissPlayerMoreControls = onDismissPlayerMoreControls
        self.onNavigateBack = onNavigateBack
        self.selectedContentTabBinding = selectedContentTab
        self.activeContentTab = selectedContentTab.wrappedValue
        self.visitedContentTabs = [selectedContentTab.wrappedValue]
        self.contentUpdateGate = contentUpdateGate
        self.contentHost = UIHostingController(
            rootView: VideoDetailShellContentView(
                viewModel: viewModel,
                updateGate: contentUpdateGate,
                runtimeSettings: runtimeSettings,
                state: contentState,
                layoutWidth: Self.initialLayoutWidth,
                selectedContentTab: selectedContentTab,
                onShowNetworkDiagnostics: onShowNetworkDiagnostics,
                onShowFavoriteFolders: onShowFavoriteFolders,
                onShowCoinPicker: onShowCoinPicker,
                onOpenCommentComposer: onOpenCommentComposer,
                onReply: onReply,
                openVideoOwnerRoute: openVideoOwnerRoute,
                onSelectedTabChange: { _ in },
                onScrollOffsetChange: { _, _ in }
            )
        )
        super.init(nibName: nil, bundle: nil)
        viewModel.objectWillChange
            .sink { [weak contentUpdateGate] _ in
                contentUpdateGate?.receiveUpdate()
            }
            .store(in: &cancellables)
        bindApplicationLifecycleForRotationRecovery()
        // self 已可用，注入滚动联动缩放回调（值类型 rootView 需整体重设）。
        contentHost.rootView = VideoDetailShellContentView(
            viewModel: viewModel,
            updateGate: contentUpdateGate,
            runtimeSettings: runtimeSettings,
            state: contentState,
            layoutWidth: Self.initialLayoutWidth,
            selectedContentTab: selectedContentTab,
            onShowNetworkDiagnostics: onShowNetworkDiagnostics,
            onShowFavoriteFolders: onShowFavoriteFolders,
            onShowCoinPicker: onShowCoinPicker,
            onOpenCommentComposer: onOpenCommentComposer,
            onReply: onReply,
            openVideoOwnerRoute: openVideoOwnerRoute,
            onSelectedTabChange: { [weak self] tab in
                self?.handleSelectedTabChange(tab)
            },
            onScrollOffsetChange: { [weak self] tab, offset in
                self?.handleScrollOffset(tab: tab, offset: offset)
            }
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static var initialLayoutWidth: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.bounds.width }
            .first ?? 393
    }

    // MARK: - Orientation / Chrome

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        AppOrientationLock.supportedOrientations
    }

    override var prefersStatusBarHidden: Bool {
        isLandscape || isPortraitFullscreen
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        isLandscape || isPortraitFullscreen
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        markNavigationLatency(.viewControllerLoaded)
        view.backgroundColor = .black

        playerContainer.backgroundColor = .black
        playerContainer.clipsToBounds = true
        updateCollapsedDimmingColor()
        collapsedDimmingView.alpha = 0
        collapsedDimmingView.isUserInteractionEnabled = false
        addChild(contentHost)
        view.addSubview(contentHost.view)
        contentHost.didMove(toParent: self)
        view.addSubview(playerContainer)
        playerContainer.addSubview(collapsedDimmingView)

        bindViewModel()

        Task { await viewModel.load() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isViewActive = true
        contentState.mountsSecondaryContent = true
        let wasBackgroundRenderFrozen = isBackgroundRenderFreezeActive
        let shouldHideContent = isLandscape || isPortraitFullscreen
        if isSystemRotationTransitioning
            || rotationRequestCoalescer.isTransitioning
            || contentHost.view.isHidden != shouldHideContent
        {
            reconcileStableRotationState()
        }
        // window 此时已挂载，按视频类型设置朝向锁。
        updateOrientationLock()
        restoreSystemBackGestures()
        setBackgroundRenderFreezeActive(false)
        markNavigationLatency(.viewControllerAppeared)
        markReturnedPageVisibleIfNeeded()
        markNavigationLatency(
            .backgroundRenderFreezeReleased,
            detail: "wasFrozen=\(wasBackgroundRenderFrozen)"
        )
    }

    /// 按视频类型设置朝向锁：横屏视频允许横屏（设备旋转/全屏按钮均可）；
    /// 竖屏视频锁竖屏（不随设备旋转成横屏，全屏走竖屏全屏态）。
    /// 仅在 VC 可见时才解锁横屏——防止 $detail sink 在 VC 消失后重新解锁，
    /// 导致全局朝向锁卡在 landscape、其它页面能旋转（问题③）。
    private func updateOrientationLock() {
        guard isViewActive else { return }
        let scene = view.window?.windowScene
        if isPortraitVideo {
            AppOrientationLock.update(to: .portrait, in: scene)
            if rotationPolicy.restoresPortraitAfterResolvingPortraitVideo(
                isCurrentlyLandscape: isLandscape
            ) {
                requestCoalescedGeometryUpdate(to: .portrait, in: scene)
            }
        } else {
            AppOrientationLock.update(to: .allButUpsideDown, in: scene)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isViewActive = false
        dismissPlayerMoreControls()
        recoverInterruptedRotationIfNeeded(reason: "viewWillDisappear")
        cancelPendingRotationCompletionRecovery()
        cancelRotationRecoveryWatchdog()
        rotationRequestCoalescer.reset()
        setBackgroundRenderFreezeActive(
            !isMovingFromParent
                && !isBeingDismissed
                && navigationController?.isBeingDismissed != true
        )
        playerSurfaceController.cancelRotationChromePrewarm()
        rotationFrameProbe.cancel()
        // 离开页面恢复竖屏锁定，避免横屏解锁残留影响其它页面（首页/动态/直播/我的）。
        AppOrientationLock.restorePortrait(in: view.window?.windowScene)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isViewActive = false
        releaseSystemBackGestureOwnership()
        recoverInterruptedRotationIfNeeded(reason: "viewDidDisappear")
        cancelPendingRotationCompletionRecovery()
        cancelRotationRecoveryWatchdog()
        rotationRequestCoalescer.reset()
        playerSurfaceController.cancelRotationChromePrewarm()
        // 双保险：tab 切换等场景 viewWillDisappear 可能不触发，这里再兜一次。
        AppOrientationLock.restorePortrait(in: view.window?.windowScene)
        if isMovingFromParent || isBeingDismissed || navigationController?.isBeingDismissed == true {
            setBackgroundRenderFreezeActive(false)
            tearDownPlayerSurfaceIfNeeded()
        } else {
            setBackgroundRenderFreezeActive(true)
        }
    }

    func prepareForDismantle() {
        dismissPlayerMoreControls()
        recoverInterruptedRotationIfNeeded(reason: "dismantle")
        cancelRotationRecoveryWatchdog()
        setBackgroundRenderFreezeActive(false)
        releaseSystemBackGestureOwnership()
        tearDownPlayerSurfaceIfNeeded()
    }

    private func tearDownPlayerSurfaceIfNeeded() {
        guard !didTearDownPlayerSurface else { return }
        didTearDownPlayerSurface = true
        playbackStateCancellable = nil
        guard let host = playerSurfaceController.releaseHost() else { return }
        (host as? VideoDetailShellSurfaceHost)?.tearDown()
        host.surfaceView.removeFromSuperview()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyLayout(
            publishesContentLayout: !isSystemRotationTransitioning
                || rotationPolicy.publishesContentLayoutDuringSystemTransition
        )
        // 全屏 UIKit 容器会盖住导航控制器的边缘返回区，需主动恢复
        // interactivePopGestureRecognizer（含 iOS26 全局右滑的 content pop）。
        restoreSystemBackGestures()
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        let toLandscape = size.width > size.height
        let policy = rotationPolicy
        rotationRequestCoalescer.beginTransition()
        let usesPrewarmedFastRecovery = policy.usesPrewarmedFastRecovery(
            hasPrewarmedRotationChrome: playerSurfaceController.isRotationChromePrewarmed
        )
        let recoverySettleDelay = usesPrewarmedFastRecovery
            ? 0
            : PlaybackDetailRotationTiming.recoverySettleDelay
        let recoveryStrategy = usesPrewarmedFastRecovery
            ? "prewarmedTwoDisplayFrames"
            : "retainedChromeStagedDisplayFrames"
        if toLandscape {
            dismissPlayerMoreControls()
        }
        rotationCompletionRecoveryGeneration &+= 1
        let completionRecoveryGeneration = rotationCompletionRecoveryGeneration
        cancelPendingRotationCompletionRecovery()
        cancelRotationRecoveryWatchdog()
        playerSurfaceController.cancelRotationChromePrewarm()
        let performanceContext = PlaybackDetailPerformanceContext.video(viewModel.detail)
        PlaybackDetailPerformanceMonitor.shared.mark(
            .fullscreenTransitionStarted,
            context: performanceContext,
            detail: "to=\(toLandscape ? "landscape" : "portrait")"
        )
        // 横屏转场只让播放器 live surface 跟随系统旋转，内容区不参与重排。
        // 转回竖屏时再恢复内容区，避免下方 SwiftUI 列表和播放器一起动画布局。
        startRotationFrameProbe(
            toLandscape: toLandscape,
            coordinator: coordinator,
            recoveryStrategy: recoveryStrategy
        )
        contentHost.view.isHidden = policy.hidesContentHost(
            duringTransitionToLandscape: toLandscape
        )
        contentHost.view.isUserInteractionEnabled = !contentHost.view.isHidden
        isSystemRotationTransitioning = true
        setContentUpdatesDeferred(true)
        scheduleRotationRecoveryWatchdog(
            generation: completionRecoveryGeneration,
            coordinatorDuration: coordinator.transitionDuration
        )
        if policy.hidesPlaybackControlsDuringSystemTransition {
            videoSurfaceHost?.requestPlaybackControlsHideForRotation()
        }
        setBareSurfaceTransitionActive(true)
        // 目标方向的控件树在系统动画开始就准备好，避免首次旋转在结束帧冷启动。
        setSurfaceLandscape(toLandscape || isPortraitFullscreen)
        rotationFrameProbe.mark("旋转开始：目标方向控件已预热")
        // 转回竖屏时重置缩放高度为默认（最大），避免横屏前的缩放残留。
        if !toLandscape {
            currentPlayerHeight = nil
        }
        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self else { return }
            self.rotationFrameProbe.mark("系统动画布局开始")
            self.applyLayout(
                forBoundsSize: size,
                publishesContentLayout: self.rotationPolicy
                    .publishesContentLayoutDuringSystemTransition
            )
            self.view.layoutIfNeeded()
            self.refreshSurfaceLayoutImmediately()
            self.setNeedsStatusBarAppearanceUpdate()
            self.setNeedsUpdateOfHomeIndicatorAutoHidden()
            self.rotationFrameProbe.mark("系统动画布局完成")
        }, completion: { [weak self] _ in
            guard let self else { return }
            guard self.rotationCompletionRecoveryGeneration == completionRecoveryGeneration else { return }
            self.finishSystemRotationWithStagedRecovery(
                toLandscape: toLandscape,
                generation: completionRecoveryGeneration,
                recoverySettleDelay: recoverySettleDelay,
                recoveryStrategy: recoveryStrategy
            )
        })
    }

    private func startRotationFrameProbe(
        toLandscape: Bool,
        coordinator: UIViewControllerTransitionCoordinator,
        recoveryStrategy: String
    ) {
        guard runtimeSettings.videoRotationFrameReportOverlayEnabled else { return }
        let detail = viewModel.detail
        guard !detail.bvid.isEmpty else { return }
        rotationFrameProbeGeneration &+= 1
        let durationMs = Int((coordinator.transitionDuration * 1000).rounded())
        let coordinatorSummary = "coordinatorDuration=\(durationMs)ms animated=\(coordinator.isAnimated) interactive=\(coordinator.isInteractive) completionRecovery=\(recoveryStrategy)"
        rotationFrameProbe.start(
            metricsID: detail.bvid,
            title: detail.title,
            mode: "videoDetailShell",
            generation: rotationFrameProbeGeneration,
            toLandscape: toLandscape,
            coordinatorSummary: coordinatorSummary,
            maximumFrameRate: view.window?.windowScene?.screen.maximumFramesPerSecond ?? 60
        )
    }

    private func finishSystemRotationWithStagedRecovery(
        toLandscape: Bool,
        generation: Int,
        recoverySettleDelay: TimeInterval,
        recoveryStrategy: String
    ) {
        rotationFrameProbe.mark("系统完成：保持视频层与已挂载控件树")
        contentHost.view.isHidden = rotationPolicy.hidesContentHost(
            duringTransitionToLandscape: toLandscape
        )
        contentHost.view.isUserInteractionEnabled = false

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applyLayout(
            publishesContentLayout: rotationPolicy
                .publishesContentLayoutDuringSystemTransition
        )
        CATransaction.commit()
        rotationFrameProbe.mark("视频层几何已提交，等待下一帧")

        scheduleRotationCompletionRecovery(
            generation: generation,
            settleDelay: recoverySettleDelay,
            preparation: { [weak self] in
                guard let self,
                      self.rotationCompletionRecoveryGeneration == generation
                else { return }

                // 先单独让 SwiftUI 控件树切到目标方向，仍保持 bare surface。
                // 下一次显示刷新再把控件、手势与交互加回来，避免压在系统结束帧。
                self.rotationFrameProbe.mark("第一帧：预热已挂载控件状态")
                self.setSurfaceLandscape(toLandscape || self.isPortraitFullscreen)
                self.rotationFrameProbe.mark("第一帧：控件方向已就绪")
            },
            recovery: { [weak self] in
                guard let self,
                      self.rotationCompletionRecoveryGeneration == generation
                else { return }

                self.rotationFrameProbe.mark("第二帧：恢复内容开始")
                self.isSystemRotationTransitioning = false
                self.contentHost.view.isHidden = toLandscape
                self.contentHost.view.isUserInteractionEnabled = !toLandscape
                self.setContentUpdatesDeferred(false)
                self.cancelRotationRecoveryWatchdog()
                self.rotationFrameProbe.mark("第二帧：内容已恢复")

                self.setBareSurfaceTransitionActive(false)
                self.videoSurfaceHost?.markRotationChromePrewarmed()
                self.rotationFrameProbe.mark("第二帧：叠层和手势已恢复")
                self.recordCompletedSystemRotation(
                    toLandscape: toLandscape,
                    strategy: recoveryStrategy
                )
                self.finishRotationRequestCoalescing(toLandscape: toLandscape)
            }
        )
    }

    private func setContentUpdatesDeferred(_ deferred: Bool) {
        let shouldDefer = deferred || isBackgroundRenderFreezeActive
        viewModel.setContentRenderUpdatesDeferred(shouldDefer)
        viewModel.setPlaybackRenderUpdatesDeferred(
            shouldDefer
        )
        contentUpdateGate.setUpdatesDeferred(shouldDefer)
    }

    private func setBackgroundRenderFreezeActive(_ active: Bool) {
        isBackgroundRenderFreezeActive = active
        setContentUpdatesDeferred(false)
    }

    private func markNavigationLatency(
        _ milestone: PlaybackDetailPerformanceMilestone,
        detail: String? = nil
    ) {
        guard dependencies.libraryStore.videoDetailNavigationLatencyDiagnosticsEnabled else {
            return
        }
        PlaybackDetailPerformanceMonitor.shared.mark(
            milestone,
            context: .video(viewModel.detail),
            detail: detail
        )
    }

    private func beginBackNavigationLatencyMeasurement(source: String) {
        guard dependencies.libraryStore.videoDetailNavigationLatencyDiagnosticsEnabled else {
            return
        }
        PlaybackDetailPerformanceMonitor.shared.beginBackNavigation(
            from: .video(viewModel.detail),
            source: source
        )
    }

    private func markReturnedPageVisibleIfNeeded() {
        guard dependencies.libraryStore.videoDetailNavigationLatencyDiagnosticsEnabled else {
            return
        }
        PlaybackDetailPerformanceMonitor.shared.markReturnedPageVisible(
            .video(viewModel.detail)
        )
    }

    private func bindApplicationLifecycleForRotationRecovery() {
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleApplicationWillResignActive()
                }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleApplicationDidBecomeActive()
                }
            }
            .store(in: &cancellables)
    }

    private func handleApplicationWillResignActive() {
        guard isViewActive else { return }
        recoverInterruptedRotationIfNeeded(reason: "applicationWillResignActive")
    }

    private func handleApplicationDidBecomeActive() {
        guard isViewActive else { return }
        if !recoverInterruptedRotationIfNeeded(reason: "applicationDidBecomeActive") {
            reconcileStableRotationState()
        }
        updateOrientationLock()
    }

    private func scheduleRotationRecoveryWatchdog(
        generation: Int,
        coordinatorDuration: TimeInterval
    ) {
        cancelRotationRecoveryWatchdog()
        let delay = VideoDetailRotationRecoveryPolicy().watchdogDelay(
            coordinatorDuration: coordinatorDuration
        )
        rotationRecoveryWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self,
                  !Task.isCancelled,
                  self.rotationCompletionRecoveryGeneration == generation,
                  self.isSystemRotationTransitioning
            else { return }
            self.recoverInterruptedRotationIfNeeded(reason: "watchdogTimeout")
        }
    }

    private func cancelRotationRecoveryWatchdog() {
        rotationRecoveryWatchdogTask?.cancel()
        rotationRecoveryWatchdogTask = nil
    }

    @discardableResult
    private func recoverInterruptedRotationIfNeeded(reason: String) -> Bool {
        guard isSystemRotationTransitioning || rotationRequestCoalescer.isTransitioning else {
            return false
        }
        rotationCompletionRecoveryGeneration &+= 1
        cancelPendingRotationCompletionRecovery()
        cancelRotationRecoveryWatchdog()
        rotationRequestCoalescer.reset()
        isSystemRotationTransitioning = false
        reconcileStableRotationState()
        rotationFrameProbe.finish(reason: "旋转中断自恢复 reason=\(reason)")
        PlaybackDetailPerformanceMonitor.shared.mark(
            .fullscreenLayoutUpdated,
            context: PlaybackDetailPerformanceContext.video(viewModel.detail),
            detail: "rotationRecovery=\(reason) landscape=\(resolvedLandscapeForRecovery)"
        )
        return true
    }

    private var resolvedLandscapeForRecovery: Bool {
        VideoDetailRotationRecoveryPolicy().resolvesLandscape(
            interfaceOrientation: view.window?.windowScene?.effectiveGeometry.interfaceOrientation,
            fallbackBounds: view.bounds.size
        )
    }

    private func reconcileStableRotationState() {
        guard isViewLoaded else { return }
        let landscape = resolvedLandscapeForRecovery
        let hidesContent = landscape || isPortraitFullscreen
        contentHost.view.isHidden = hidesContent
        contentHost.view.isUserInteractionEnabled = !hidesContent
        setSurfaceLandscape(landscape || isPortraitFullscreen)
        setBareSurfaceTransitionActive(false)
        setContentUpdatesDeferred(false)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applyLayout(publishesContentLayout: true)
        view.layoutIfNeeded()
        CATransaction.commit()
        refreshSurfaceLayoutImmediately()
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
    }

    private func finishRotationRequestCoalescing(toLandscape: Bool) {
        let scene = view.window?.windowScene
        let currentOrientation = scene?.effectiveGeometry.interfaceOrientation
            ?? (toLandscape ? .landscapeRight : .portrait)
        guard let pendingTarget = rotationRequestCoalescer.completeTransition(
            currentOrientation: currentOrientation
        ) else { return }
        requestCoalescedGeometryUpdate(to: pendingTarget, in: scene)
    }

    private func recordCompletedSystemRotation(toLandscape: Bool, strategy: String) {
        PlaybackDetailPerformanceMonitor.shared.mark(
            .fullscreenLayoutUpdated,
            context: PlaybackDetailPerformanceContext.video(viewModel.detail),
            detail: "landscape=\(toLandscape) strategy=\(strategy)"
        )
        rotationFrameProbe.finish(
            reason: "系统旋转完成 landscape=\(toLandscape) strategy=\(strategy)"
        )
    }

    private func scheduleRotationCompletionRecovery(
        generation: Int,
        settleDelay: TimeInterval,
        preparation: @escaping () -> Void,
        recovery: @escaping () -> Void
    ) {
        cancelPendingRotationCompletionRecovery()
        pendingRotationCompletionPreparation = preparation
        pendingRotationCompletionRecovery = recovery
        pendingRotationCompletionRecoveryGeneration = generation
        rotationCompletionRecoveryNotBefore = CACurrentMediaTime()
            + settleDelay
        let displayLink = CADisplayLink(
            target: self,
            selector: #selector(runPendingRotationCompletionRecovery(_:))
        )
        if #available(iOS 15.0, *) {
            let maximumFrameRate = Float(max(view.window?.windowScene?.screen.maximumFramesPerSecond ?? 60, 60))
            displayLink.preferredFrameRateRange = CAFrameRateRange(
                minimum: 30,
                maximum: maximumFrameRate,
                preferred: maximumFrameRate
            )
        }
        displayLink.add(to: .main, forMode: .common)
        rotationCompletionRecoveryDisplayLink = displayLink
    }

    @objc private func runPendingRotationCompletionRecovery(_ displayLink: CADisplayLink) {
        guard rotationCompletionRecoveryDisplayLink === displayLink,
              let generation = pendingRotationCompletionRecoveryGeneration,
              let recovery = pendingRotationCompletionRecovery
        else { return }

        guard generation == rotationCompletionRecoveryGeneration else {
            cancelPendingRotationCompletionRecovery()
            return
        }
        if let notBefore = rotationCompletionRecoveryNotBefore,
           CACurrentMediaTime() < notBefore {
            return
        }
        rotationCompletionRecoveryNotBefore = nil
        if let preparation = pendingRotationCompletionPreparation {
            pendingRotationCompletionPreparation = nil
            preparation()
            return
        }

        cancelPendingRotationCompletionRecovery()
        recovery()
    }

    private func cancelPendingRotationCompletionRecovery() {
        rotationCompletionRecoveryDisplayLink?.invalidate()
        rotationCompletionRecoveryDisplayLink = nil
        pendingRotationCompletionPreparation = nil
        pendingRotationCompletionRecovery = nil
        pendingRotationCompletionRecoveryGeneration = nil
        rotationCompletionRecoveryNotBefore = nil
    }

    // MARK: - Layout

    private func setBareSurfaceTransitionActive(_ active: Bool) {
        setSurfaceBareTransitionActive(
            active,
            retainsChromeTree: active
        )
        collapsedDimmingView.isHidden = active
        collapsedBarHost?.view.isHidden = active
        if active {
            collapsedDimmingView.alpha = 0
            collapsedDimmingView.layer.removeAllAnimations()
            collapsedBarHost?.view.layer.removeAllAnimations()
        }
    }

    private func applyLayout(
        forBoundsSize size: CGSize? = nil,
        publishesContentLayout: Bool = true
    ) {
        let bounds = CGRect(origin: .zero, size: size ?? view.bounds.size)
        let landscape = bounds.width > bounds.height

        let usesFullscreenLayout = landscape || isPortraitFullscreen
        if contentState.hidesBottomToolbar != usesFullscreenLayout {
            contentState.hidesBottomToolbar = usesFullscreenLayout
        }
        view.backgroundColor = .black
        let expanded = expandedPlayerHeight(bounds: bounds.size)
        let shellLayout = PlaybackDetailShellLayout(
            bounds: bounds,
            safeAreaTop: view.safeAreaInsets.top,
            playerHeight: usesFullscreenLayout
                ? bounds.height
                : resolvedPlayerHeight(bounds: bounds.size),
            contentTopInset: expanded,
            usesFullscreenLayout: usesFullscreenLayout
        )
        playerContainer.frame = shellLayout.playerFrame
        contentHost.view.frame = shellLayout.contentFrame
        if publishesContentLayout, let contentTopInset = shellLayout.contentTopInset {
            // 内容留白 = expanded（固定，对齐原项目）：播放器覆盖在内容上层、随滚动
            // 收缩，内容顶部始终贴播放器底部。这样"拖动先把播放器收到最小、再正常
            // 滚内容"是自然结果，且内容不会双倍滚动。
            contentState.topInset = contentTopInset
        }

        updateSurfaceLayout(usesLandscapeChrome: landscape || isPortraitFullscreen)
        if !isSystemRotationTransitioning {
            updateCollapsedChrome(playerHeight: playerContainer.bounds.height)
        }
    }

    // MARK: - Player surface

    private func makeSurfaceHost(for playerViewModel: PlayerStateViewModel) -> VideoDetailShellSurfaceHost {
        let host = VideoDetailShellSurfaceHost(
            playerViewModel: playerViewModel,
            detailViewModel: viewModel,
            dependencies: dependencies,
            runtimeSettings: runtimeSettings,
            onShowMoreControls: { [weak self] onDismiss in
                guard let self else {
                    onDismiss()
                    return
                }
                self.presentPlayerMoreControls(onDismiss: onDismiss)
            },
            onDismissMoreControls: { [weak self] in
                self?.dismissPlayerMoreControls()
            },
            onRequestFullscreen: { [weak self] in self?.requestFullscreen() },
            onExitFullscreen: { [weak self] in self?.requestExitFullscreen() },
            onToggleDanmaku: { [weak self] in self?.viewModel.toggleDanmaku() },
            onShowDanmakuSettings: { [weak self] in self?.onShowDanmakuSettings() },
            onNavigateBack: { [weak self] in self?.handleBackButton() }
        )
        videoSurfaceHost = host
        host.setCollapsedChromeActive(
            shouldShowCollapsedChrome(playerHeight: playerContainer.bounds.height)
        )
        return host
    }

    private func currentSurfaceLayout(usesLandscapeChrome: Bool) -> PlayerSurfaceLayout {
        PlayerSurfaceLayout(
            frame: playerContainer.bounds,
            videoAspectRatio: videoAspectRatio,
            videoGravity: .resizeAspect,
            usesLandscapeChrome: usesLandscapeChrome,
            usesPortraitFullscreen: isPortraitFullscreen,
            isTransitioning: isSystemRotationTransitioning
        )
    }

    private func updateSurfaceLayout(usesLandscapeChrome: Bool) {
        playerSurfaceController.updateLayout(
            currentSurfaceLayout(usesLandscapeChrome: usesLandscapeChrome)
        )
    }

    private func setSurfaceVideoAspectRatio(_ aspectRatio: CGFloat) {
        playerSurfaceController.setVideoAspectRatio(aspectRatio)
    }

    private func presentPlayerMoreControls(onDismiss: @escaping () -> Void) {
        guard isViewLoaded,
              view.window != nil,
              !isLandscape,
              let playerViewModel = viewModel.stablePlayerViewModel
        else {
            onDismiss()
            return
        }

        onPresentPlayerMoreControls(playerViewModel, onDismiss)
    }

    private func dismissPlayerMoreControls() {
        onDismissPlayerMoreControls()
    }

    private func setSurfaceLandscape(_ landscape: Bool) {
        playerSurfaceController.setLandscape(landscape)
    }

    private func setSurfaceBareTransitionActive(_ active: Bool, retainsChromeTree: Bool) {
        playerSurfaceController.setBareSurfaceTransitionActive(
            active,
            retainsChromeTree: retainsChromeTree
        )
    }

    private func refreshSurfaceLayoutImmediately() {
        playerSurfaceController.refreshLayoutImmediately()
    }

    // MARK: - Fullscreen

    /// 控件「全屏」按钮：横屏视频→旋转横屏全屏；竖屏视频→竖屏全屏态（不旋转）。
    private func requestFullscreen() {
        if isPortraitVideo {
            setPortraitFullscreen(true)
        } else {
            let scene = view.window?.windowScene
            AppOrientationLock.update(to: .allButUpsideDown, in: scene)
            let targetOrientation = rotationPolicy.preferredLandscapeInterfaceOrientation(
                currentInterfaceOrientation: scene?.effectiveGeometry.interfaceOrientation,
                deviceOrientation: UIDevice.current.orientation
            )
            requestCoalescedGeometryUpdate(to: targetOrientation, in: scene)
        }
    }

    /// 控件「退出全屏」按钮：竖屏全屏态→退出；横屏→旋转回竖屏。
    private func requestExitFullscreen() {
        if isPortraitFullscreen {
            setPortraitFullscreen(false)
        } else {
            requestPortrait()
        }
    }

    /// 旋转回竖屏。
    private func requestPortrait() {
        let scene = view.window?.windowScene
        AppOrientationLock.update(to: .allButUpsideDown, in: scene)
        requestCoalescedGeometryUpdate(to: .portrait, in: scene)
    }

    private func requestCoalescedGeometryUpdate(
        to target: UIInterfaceOrientationMask,
        in scene: UIWindowScene?
    ) {
        guard let target = rotationRequestCoalescer.submit(target) else { return }
        AppOrientationLock.requestGeometryUpdate(to: target, in: scene)
    }

    /// 竖屏视频的「竖屏全屏」态切换：播放器占满整屏、隐藏内容区，带动画。
    private func setPortraitFullscreen(_ active: Bool) {
        guard isPortraitFullscreen != active else { return }
        isPortraitFullscreen = active
        contentHost.view.isHidden = active
        contentHost.view.isUserInteractionEnabled = !active
        setSurfaceLandscape(active) // 复用全屏 chrome 样式（隐藏导航栏等）
        UIView.animate(
            withDuration: PlaybackDetailRotationTiming.portraitFullscreenDuration,
            delay: 0,
            options: [.curveEaseInOut]
        ) {
            self.applyLayout()
            self.setNeedsStatusBarAppearanceUpdate()
            self.setNeedsUpdateOfHomeIndicatorAutoHidden()
        }
    }

    /// 左上角返回按钮：全屏态（横屏或竖屏全屏）时退出全屏；否则 pop 上一层。
    private func handleBackButton() {
        if isLandscape || isPortraitFullscreen {
            requestExitFullscreen()
        } else {
            beginBackNavigationLatencyMeasurement(source: "button")
            onNavigateBack()
        }
    }

    // MARK: - Drag-resize player (portrait)

    /// 内容区滚动联动：竖屏时随滚动偏移缩放播放器高度（对齐原项目公式）。
    /// 高度 = clamp(expandedHeight - 滚动距离, 最小, expanded)，跟手无动画。
    /// 最小高度：播放中=standardHeight，暂停=54pt 工具条。
    private func handleSelectedTabChange(_ tab: VideoDetailContentTab) {
        guard !isSystemRotationTransitioning else { return }
        guard !isLandscape, !isPortraitFullscreen else { return }
        if visitedContentTabs.contains(tab) {
            activeContentTab = tab
            if let preservedOffset = scrollOffsets[tab] {
                lastScrollOffset = preservedOffset
                if preservedOffset <= 0.5 {
                    currentPlayerHeight = nil
                    updatePlayerContainerHeight()
                } else {
                    applyPlayerHeight(forOffset: preservedOffset)
                }
                contentState.requestScrollAdjustment(tab: tab, offset: preservedOffset)
            }
            return
        }

        visitedContentTabs.insert(tab)
        let expanded = expandedPlayerHeight(bounds: view.bounds.size)
        let playerHeight = resolvedPlayerHeight(bounds: view.bounds.size)
        let targetOffset = max(0, expanded - playerHeight)
        lastScrollOffset = targetOffset
        Task { @MainActor [weak self] in
            guard let self, self.selectedContentTabBinding.wrappedValue == tab else { return }
            self.contentState.requestScrollAdjustment(tab: tab, offset: targetOffset)
        }
    }

    private func resolvedPlayerHeight(bounds: CGSize) -> CGFloat {
        let expanded = expandedPlayerHeight(bounds: bounds)
        let minimum = minimumPlayerHeight(forWidth: bounds.width)
        return max(minimum, min(currentPlayerHeight ?? expanded, expanded))
    }

    private func handleScrollOffset(tab: VideoDetailContentTab, offset: CGFloat) {
        guard !isSystemRotationTransitioning else { return }
        guard !isLandscape, !isPortraitFullscreen else { return }
        // 只响应当前可见 tab 的滚动，避免另一 tab 的 offset 干扰。
        let selectedTab = selectedContentTabBinding.wrappedValue
        guard tab == selectedTab else {
            scrollOffsets[tab] = offset
            return
        }

        if activeContentTab != selectedTab {
            activeContentTab = selectedTab
            scrollOffsets[tab] = offset
            lastScrollOffset = offset
            return
        }

        let previousOffset = scrollOffsets[tab]
        scrollOffsets[tab] = offset
        // 滚动到顶（offset≈0）时用 expanded；切到一个本来就在顶部的 tab 不改当前高度。
        if offset <= 0.5 {
            lastScrollOffset = 0
            if previousOffset.map({ $0 > 0.5 }) == true, currentPlayerHeight != nil {
                currentPlayerHeight = nil
                updatePlayerContainerHeight()
            }
            return
        }
        lastScrollOffset = offset
        applyPlayerHeight(forOffset: offset)
    }

    /// 按滚动偏移计算并应用播放器高度（滚动 & 暂停状态变化共用）。
    private func applyPlayerHeight(forOffset offset: CGFloat) {
        guard !isSystemRotationTransitioning else { return }
        let expanded = expandedPlayerHeight(bounds: view.bounds.size)
        let minimum = minimumPlayerHeight(forWidth: view.bounds.width)
        let target = max(minimum, min(expanded, expanded - offset))
        // 变化阈值去抖（onScrollGeometryChange 高频触发）。
        if let current = currentPlayerHeight, abs(current - target) < 0.5 { return }
        currentPlayerHeight = target
        // 叠放结构下只改播放器高度，不动 contentHost / topInset，避免 ScrollView
        // 尺寸反馈抽搐。
        updatePlayerContainerHeight()
    }

    /// 只更新播放器容器高度与 surface frame（竖屏缩放用），不触碰内容区布局。
    private func updatePlayerContainerHeight() {
        guard !isSystemRotationTransitioning else { return }
        guard !isLandscape, !isPortraitFullscreen else { return }
        let topInset = view.safeAreaInsets.top
        let playerHeight = resolvedPlayerHeight(bounds: view.bounds.size)
        playerContainer.frame = CGRect(
            x: 0,
            y: topInset,
            width: view.bounds.width,
            height: playerHeight
        )
        updateSurfaceLayout(usesLandscapeChrome: false)
        updateCollapsedChrome(playerHeight: playerHeight)
        // 注意：滚动路径不改 topInset（改 contentSize 会引发 offset 反馈抽搐）。
    }

    /// 折叠工具条（主题色遮罩）：暂停且播放器已经明显收缩时显示，
    /// 盖满 playerContainer（对齐原项目 usesCollapsedChrome）。
    private func updateCollapsedChrome(playerHeight: CGFloat) {
        let minimum = minimumPlayerHeight(forWidth: view.bounds.width)
        let standard = standardPlayerHeight(forWidth: view.bounds.width)
        let isPlaybackActive = isPlaybackActiveForCollapsedChrome
        let shouldShow = shouldShowCollapsedChrome(playerHeight: playerHeight)
        videoSurfaceHost?.setCollapsedChromeActive(shouldShow)

        collapsedDimmingView.frame = playerContainer.bounds
        let collapseDistance = max(standard - minimum, 1)
        let progress = max(0, min(1, (standard - playerHeight) / collapseDistance))
        collapsedDimmingView.alpha = (!isLandscape && !isPlaybackActive) ? progress : 0
        playerContainer.bringSubviewToFront(collapsedDimmingView)

        if shouldShow {
            if collapsedBarHost == nil, let player = viewModel.stablePlayerViewModel {
                let bar = VideoDetailShellCollapsedBar(
                    playerViewModel: player,
                    onNavigateBack: { [weak self] in self?.handleBackButton() },
                    onRequestFullscreen: { [weak self] in self?.requestFullscreen() }
                )
                let host = UIHostingController(rootView: bar)
                host.view.backgroundColor = .clear
                addChild(host)
                playerContainer.addSubview(host.view)
                host.didMove(toParent: self)
                collapsedBarHost = host
            }
            collapsedBarHost?.view.frame = playerContainer.bounds
            if let barView = collapsedBarHost?.view {
                playerContainer.bringSubviewToFront(barView)
            }
        } else {
            removeCollapsedBarHost()
        }
    }

    private func removeCollapsedBarHost() {
        videoSurfaceHost?.setCollapsedChromeActive(false)
        guard let host = collapsedBarHost else { return }
        host.willMove(toParent: nil)
        host.view.removeFromSuperview()
        host.removeFromParent()
        collapsedBarHost = nil
    }

    private func shouldShowCollapsedChrome(playerHeight: CGFloat) -> Bool {
        guard playerHeight > 0 else { return false }
        let threshold = standardPlayerHeight(forWidth: view.bounds.width) - 4
        return !isLandscape
            && !isPlaybackActiveForCollapsedChrome
            && playerHeight <= threshold
    }

    // MARK: - Bindings

    private func updateCollapsedDimmingColor() {
        collapsedDimmingView.backgroundColor = AppThemeTintColor.uiColor(
            for: dependencies.libraryStore.appTintColorHex
        )
    }

    private func bindViewModel() {
        dependencies.libraryStore.$appTintColorHex
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateCollapsedDimmingColor()
            }
            .store(in: &cancellables)

        viewModel.$detail
            .receive(on: RunLoop.main)
            .sink { [weak self] detail in
                guard let self, let ratio = detail.dimension?.aspectRatio, ratio > 0.1 else { return }
                self.videoAspectRatio = CGFloat(ratio)
                self.setSurfaceVideoAspectRatio(self.videoAspectRatio)
                // 真实宽高比到达后才知道是否竖屏视频，更新朝向锁（竖屏视频锁竖屏）。
                self.updateOrientationLock()
                // 真实宽高比变化后（影响 isPortraitVideo→expanded），若已缩放则重新 clamp。
                if let current = self.currentPlayerHeight {
                    let expanded = self.expandedPlayerHeight(bounds: self.view.bounds.size)
                    let minimum = self.minimumPlayerHeight(forWidth: self.view.bounds.width)
                    self.currentPlayerHeight = max(minimum, min(expanded, current))
                }
                self.view.setNeedsLayout()
            }
            .store(in: &cancellables)

        playerSurfaceController.bind(
            to: viewModel.playbackSession,
            layout: currentSurfaceLayout(
                usesLandscapeChrome: isLandscape || isPortraitFullscreen
            )
        )
    }

    private func bindPlaybackState(to playerViewModel: PlayerStateViewModel?) {
        playbackStateCancellable = nil
        removeCollapsedBarHost()
        guard let playerViewModel else {
            return
        }
        // 订阅播放状态：暂停只放宽最小高度，不主动收起播放器；恢复播放时
        // 再按当前滚动位置回到播放态允许的高度。
        playbackStateCancellable = playerViewModel.$isPlaying
            .combineLatest(playerViewModel.$isUserSeeking)
            .receive(on: RunLoop.main)
            .map { isPlaying, isUserSeeking in isPlaying || isUserSeeking }
            .removeDuplicates()
            .sink { [weak self] isPlaybackActive in
                guard let self, !self.isLandscape, !self.isPortraitFullscreen else { return }
                guard isPlaybackActive else {
                    self.updatePlayerContainerHeight()
                    return
                }
                guard self.lastScrollOffset > 0.5 else {
                    self.updatePlayerContainerHeight()
                    return
                }
                let minimum = self.minimumPlayerHeight(forWidth: self.view.bounds.width)
                let expanded = self.expandedPlayerHeight(bounds: self.view.bounds.size)
                let target = max(minimum, min(expanded, expanded - self.lastScrollOffset))
                guard self.currentPlayerHeight.map({ abs($0 - target) > 0.5 }) ?? true else { return }
                self.currentPlayerHeight = target
                UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseInOut]) {
                    self.updatePlayerContainerHeight()
                }
            }

        if isViewLoaded, playerContainer.bounds.height > 0 {
            updateCollapsedChrome(playerHeight: playerContainer.bounds.height)
        }
    }

    // MARK: - System back gestures

    /// 恢复导航控制器的边缘返回手势。全屏 UIKit 容器会接管触摸区域，
    /// 需把 interactivePopGestureRecognizer（及 iOS26 的 content pop）的
    /// delegate 设回自己并启用，否则系统右滑返回失效。
    private func restoreSystemBackGestures() {
        guard let navigationController else { return }
        systemBackGestureDelegateLease.acquire(in: navigationController, owner: self)
    }

    func releaseSystemBackGestureOwnership() {
        systemBackGestureDelegateLease.release()
    }

    private func isSystemBackGesture(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigationController else { return false }
        if let popGesture = navigationController.interactivePopGestureRecognizer,
           gestureRecognizer === popGesture {
            return true
        }
        if let contentPopGesture = navigationController.interactiveContentPopGestureRecognizer,
           gestureRecognizer === contentPopGesture {
            return true
        }
        return false
    }

    private func suppressContentActionsDuringSystemBackGesture() {
        contentActionSuppressionWorkItem?.cancel()
        contentState.suppressesInteractiveContentActions = true
        contentHost.view.isUserInteractionEnabled = false

        let workItem = DispatchWorkItem { [weak self] in
            self?.resetContentActionSuppression()
        }
        contentActionSuppressionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
    }

    private func resetContentActionSuppression() {
        contentActionSuppressionWorkItem?.cancel()
        contentActionSuppressionWorkItem = nil
        contentState.suppressesInteractiveContentActions = false
        contentHost.view.isUserInteractionEnabled = true
    }

}

extension VideoDetailShellViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard isSystemBackGesture(gestureRecognizer) else { return true }
        // 仅竖屏允许边缘返回；横屏（全屏播放）下交给控件的退出全屏按钮。
        guard !isLandscape else { return false }
        guard let navigationController else { return true }
        guard navigationController.viewControllers.count > 1 else { return false }
        beginBackNavigationLatencyMeasurement(source: "gesture")
        suppressContentActionsDuringSystemBackGesture()
        return navigationController.viewControllers.count > 1
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard isSystemBackGesture(gestureRecognizer) else { return true }
        // 竖屏时屏蔽视频窗口区域的右滑返回（避免与播放器手势冲突）；
        // 触点落在 playerContainer 内则不触发返回。
        guard !isLandscape else { return false }
        let location = touch.location(in: view)
        return !playerContainer.frame.contains(location)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard isSystemBackGesture(gestureRecognizer) || isSystemBackGesture(otherGestureRecognizer) else {
            return true
        }
        return !(gestureRecognizer is UITapGestureRecognizer || otherGestureRecognizer is UITapGestureRecognizer)
    }
}
