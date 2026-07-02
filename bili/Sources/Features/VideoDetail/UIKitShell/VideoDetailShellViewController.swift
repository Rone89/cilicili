import AVFoundation
import Combine
import SwiftUI
import UIKit

/// 正式的详情页 UIKit 外壳容器。
///
/// 播放器由 UIKit 容器接管布局，内容区复用现有 SwiftUI 内容
/// `VideoDetailShellContentView`。
/// - 复用现有 `VideoDetailViewModel`（load playurl）、`stablePlayerViewModel`
///   + `VideoSurfaceView` 渲染、`VideoDetailFullscreenCoordinator`（不改造）。
/// - 自己接管布局：竖屏 = 顶部按视频宽高比的播放器 + 下方内容区；横屏 = 播放器全屏。
/// - 旋转走全局 `AppOrientationLock`，`viewWillTransition` 协调块驱动 frame，
///   completion 控制内容区隐藏（照搬原型已验证的防闪黑逻辑）。
@MainActor
final class VideoDetailShellViewController: UIViewController {
    private let viewModel: VideoDetailViewModel
    private let fullscreenCoordinator: VideoDetailFullscreenCoordinator
    private let runtimeSettings: VideoDetailRuntimeSettingsStore
    private let dependencies: AppDependencies
    private let onShowDanmakuSettings: () -> Void
    private let onNavigateBack: () -> Void
    private var cancellables = Set<AnyCancellable>()

    private var surfaceHost: VideoDetailShellSurfaceHost?
    private let playerContainer = UIView()
    private let contentHost: UIHostingController<VideoDetailShellContentView>
    private let contentState = VideoDetailShellContentView.State()
    /// 暂停下翻收缩时的折叠工具条（黑色遮罩，对齐原项目），盖在 playerContainer 上。
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
    /// VC 是否处于可见活跃态（viewDidAppear~viewWillDisappear 之间）。
    /// 用于防止 $detail sink 在 VC 消失后重新解锁横屏，导致全局朝向锁卡在 landscape。
    private var isViewActive = false
    private let selectedContentTabBinding: Binding<VideoDetailContentTab>
    private var activeContentTab: VideoDetailContentTab
    private var scrollOffsets: [VideoDetailContentTab: CGFloat] = [:]
    private var contentActionSuppressionWorkItem: DispatchWorkItem?

    /// 竖屏标准高度（对齐原项目：固定 16:9，与视频真实比例无关）。
    private func standardPlayerHeight(forWidth width: CGFloat) -> CGFloat {
        (width * 9 / 16).rounded()
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

    init(
        viewModel: VideoDetailViewModel,
        fullscreenCoordinator: VideoDetailFullscreenCoordinator,
        runtimeSettings: VideoDetailRuntimeSettingsStore,
        dependencies: AppDependencies,
        selectedContentTab: Binding<VideoDetailContentTab>,
        onShowNetworkDiagnostics: @escaping () -> Void,
        onShowFavoriteFolders: @escaping () -> Void,
        onShowDanmakuSettings: @escaping () -> Void,
        onReply: @escaping (Comment) -> Void,
        onNavigateBack: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.fullscreenCoordinator = fullscreenCoordinator
        self.runtimeSettings = runtimeSettings
        self.dependencies = dependencies
        self.onShowDanmakuSettings = onShowDanmakuSettings
        self.onNavigateBack = onNavigateBack
        self.selectedContentTabBinding = selectedContentTab
        self.activeContentTab = selectedContentTab.wrappedValue
        self.contentHost = UIHostingController(
            rootView: VideoDetailShellContentView(
                viewModel: viewModel,
                runtimeSettings: runtimeSettings,
                state: contentState,
                layoutWidth: UIScreen.main.bounds.width,
                selectedContentTab: selectedContentTab,
                onShowNetworkDiagnostics: onShowNetworkDiagnostics,
                onShowFavoriteFolders: onShowFavoriteFolders,
                onReply: onReply,
                onSelectedTabChange: { _ in },
                onScrollOffsetChange: { _, _ in }
            )
        )
        super.init(nibName: nil, bundle: nil)
        // self 已可用，注入滚动联动缩放回调（值类型 rootView 需整体重设）。
        contentHost.rootView = VideoDetailShellContentView(
            viewModel: viewModel,
            runtimeSettings: runtimeSettings,
            state: contentState,
            layoutWidth: UIScreen.main.bounds.width,
            selectedContentTab: selectedContentTab,
            onShowNetworkDiagnostics: onShowNetworkDiagnostics,
            onShowFavoriteFolders: onShowFavoriteFolders,
            onReply: onReply,
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
        view.backgroundColor = .black

        playerContainer.backgroundColor = .black
        collapsedDimmingView.backgroundColor = .black
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
        // window 此时已挂载，按视频类型设置朝向锁。
        updateOrientationLock()
        restoreSystemBackGestures()
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
        } else {
            AppOrientationLock.update(to: [.portrait, .landscape], in: scene)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isViewActive = false
        // 离开页面恢复竖屏锁定，避免横屏解锁残留影响其它页面（首页/动态/直播/我的）。
        AppOrientationLock.restorePortrait(in: view.window?.windowScene)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isViewActive = false
        // 双保险：tab 切换等场景 viewWillDisappear 可能不触发，这里再兜一次。
        AppOrientationLock.restorePortrait(in: view.window?.windowScene)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyLayout()
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
        // 过渡开始就让内容区可见并参与动画，避免动画期间露出黑背景闪黑；
        // 横屏时它被全屏 playerContainer 覆盖，动画结束后再真正隐藏。
        contentHost.view.isHidden = false
        isSystemRotationTransitioning = true
        setBareSurfaceTransitionActive(true)
        // 转回竖屏时重置缩放高度为默认（最大），避免横屏前的缩放残留。
        if !toLandscape {
            currentPlayerHeight = nil
        }
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.applyLayout(forBoundsSize: size)
            self?.view.layoutIfNeeded()
            self?.surfaceHost?.refreshLayoutImmediately()
            self?.setNeedsStatusBarAppearanceUpdate()
            self?.setNeedsUpdateOfHomeIndicatorAutoHidden()
        }, completion: { [weak self] _ in
            guard let self else { return }
            self.contentHost.view.isHidden = toLandscape
            self.applyLayout()
            self.view.layoutIfNeeded()
            self.surfaceHost?.refreshLayoutImmediately()
            self.surfaceHost?.setLandscape(toLandscape || self.isPortraitFullscreen)
            self.isSystemRotationTransitioning = false
            self.setBareSurfaceTransitionActive(false)
            self.applyLayout()
            self.view.layoutIfNeeded()
            self.surfaceHost?.refreshLayoutImmediately()
        })
    }

    // MARK: - Layout

    private func setBareSurfaceTransitionActive(_ active: Bool) {
        surfaceHost?.setBareSurfaceTransitionActive(active)
        collapsedDimmingView.isHidden = active
        collapsedBarHost?.view.isHidden = active
        if active {
            collapsedDimmingView.alpha = 0
            collapsedDimmingView.layer.removeAllAnimations()
            collapsedBarHost?.view.layer.removeAllAnimations()
        }
    }

    private func applyLayout(forBoundsSize size: CGSize? = nil) {
        let bounds = CGRect(origin: .zero, size: size ?? view.bounds.size)
        let landscape = bounds.width > bounds.height

        if landscape || isPortraitFullscreen {
            // 横屏全屏 或 竖屏视频的竖屏全屏：播放器占满整屏，内容区移出屏幕。
            playerContainer.frame = bounds
            contentHost.view.frame = CGRect(
                x: 0,
                y: bounds.height,
                width: bounds.width,
                height: max(bounds.height, 1)
            )
        } else {
            let topInset = view.safeAreaInsets.top
            let expanded = expandedPlayerHeight(bounds: bounds.size)
            // 叠放结构（对齐原项目）：内容区始终占满屏幕，顶部留白 = expanded 高度；
            // 播放器盖在顶部、高度随缩放在 [min, expanded] 间变。滚动只改播放器高度，
            // 内容区 frame 不变 → 无 ScrollView 尺寸反馈抽搐。
            contentHost.view.frame = CGRect(
                x: 0,
                y: topInset,
                width: bounds.width,
                height: bounds.height - topInset
            )
            // 内容留白 = expanded（固定，对齐原项目）：播放器覆盖在内容上层、随滚动
            // 收缩，内容顶部始终贴播放器底部。这样"拖动先把播放器收到最小、再正常
            // 滚内容"是自然结果，且内容不会双倍滚动。
            contentState.topInset = expanded

            let playerHeight = resolvedPlayerHeight(bounds: bounds.size)
            playerContainer.frame = CGRect(
                x: 0,
                y: topInset,
                width: bounds.width,
                height: playerHeight
            )
        }

        surfaceHost?.frame = playerContainer.bounds
        surfaceHost?.setVideoGravity(.resizeAspect)
        if !isSystemRotationTransitioning {
            updateCollapsedChrome(playerHeight: playerContainer.bounds.height)
            surfaceHost?.setLandscape(landscape || isPortraitFullscreen)
        }
    }

    // MARK: - Player surface

    private func installSurfaceHost(for playerViewModel: PlayerStateViewModel) {
        guard surfaceHost == nil else { return }
        let host = VideoDetailShellSurfaceHost(
            playerViewModel: playerViewModel,
            detailViewModel: viewModel,
            dependencies: dependencies,
            onRequestFullscreen: { [weak self] in self?.requestFullscreen() },
            onExitFullscreen: { [weak self] in self?.requestExitFullscreen() },
            onToggleDanmaku: { [weak self] in self?.viewModel.toggleDanmaku() },
            onShowDanmakuSettings: { [weak self] in self?.onShowDanmakuSettings() },
            onNavigateBack: { [weak self] in self?.handleBackButton() }
        )
        host.attach(to: self)
        host.frame = playerContainer.bounds
        host.setLandscape(isLandscape)
        host.setVideoAspectRatio(videoAspectRatio)
        playerContainer.insertSubview(host, at: 0)
        surfaceHost = host
        playerViewModel.play()
        applyLayout()
    }

    // MARK: - Fullscreen

    /// 控件「全屏」按钮：横屏视频→旋转横屏全屏；竖屏视频→竖屏全屏态（不旋转）。
    private func requestFullscreen() {
        if isPortraitVideo {
            setPortraitFullscreen(true)
        } else {
            let scene = view.window?.windowScene
            AppOrientationLock.update(to: [.portrait, .landscape], in: scene)
            AppOrientationLock.requestGeometryUpdate(to: .landscapeRight, in: scene)
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
        AppOrientationLock.update(to: [.portrait, .landscape], in: scene)
        AppOrientationLock.requestGeometryUpdate(to: .portrait, in: scene)
    }

    /// 竖屏视频的「竖屏全屏」态切换：播放器占满整屏、隐藏内容区，带动画。
    private func setPortraitFullscreen(_ active: Bool) {
        guard isPortraitFullscreen != active else { return }
        isPortraitFullscreen = active
        surfaceHost?.setLandscape(active) // 复用全屏 chrome 样式（隐藏导航栏等）
        UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseInOut]) {
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
        surfaceHost?.frame = playerContainer.bounds
        updateCollapsedChrome(playerHeight: playerHeight)
        // 注意：滚动路径不改 topInset（改 contentSize 会引发 offset 反馈抽搐）。
    }

    /// 折叠工具条（黑色遮罩）：暂停且播放器已经明显收缩时显示，
    /// 盖满 playerContainer（对齐原项目 usesCollapsedChrome）。
    private func updateCollapsedChrome(playerHeight: CGFloat) {
        let minimum = minimumPlayerHeight(forWidth: view.bounds.width)
        let standard = standardPlayerHeight(forWidth: view.bounds.width)
        let threshold = standard - 4
        let isPlaybackActive = isPlaybackActiveForCollapsedChrome
        let shouldShow = !isLandscape && !isPlaybackActive && playerHeight <= threshold

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
        } else if let host = collapsedBarHost {
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
            collapsedBarHost = nil
        }
    }

    // MARK: - Bindings

    private func bindViewModel() {
        viewModel.$detail
            .receive(on: RunLoop.main)
            .sink { [weak self] detail in
                guard let self, let ratio = detail.dimension?.aspectRatio, ratio > 0.1 else { return }
                self.videoAspectRatio = CGFloat(ratio)
                self.surfaceHost?.setVideoAspectRatio(self.videoAspectRatio)
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

        viewModel.$stablePlayerViewModel
            .receive(on: RunLoop.main)
            .sink { [weak self] playerViewModel in
                guard let self, let playerViewModel else { return }
                if let surfaceHost = self.surfaceHost {
                    // 清晰度切换等会重建 player 实例，重绑到现有 surface host。
                    surfaceHost.setPlayerViewModel(playerViewModel)
                } else {
                    self.installSurfaceHost(for: playerViewModel)
                }
                // 订阅播放状态：暂停只放宽最小高度，不主动收起播放器；恢复播放时
                // 再按当前滚动位置回到播放态允许的高度。
                self.playbackStateCancellable = playerViewModel.$isPlaying
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
            }
            .store(in: &cancellables)
    }

    // MARK: - System back gestures

    /// 恢复导航控制器的边缘返回手势。全屏 UIKit 容器会接管触摸区域，
    /// 需把 interactivePopGestureRecognizer（及 iOS26 的 content pop）的
    /// delegate 设回自己并启用，否则系统右滑返回失效。
    private func restoreSystemBackGestures() {
        guard let navigationController else { return }
        if let popGesture = navigationController.interactivePopGestureRecognizer {
            popGesture.isEnabled = true
            popGesture.delegate = self
        }
        if let contentPopGesture = navigationController.interactiveContentPopGestureRecognizer {
            contentPopGesture.isEnabled = true
            contentPopGesture.delegate = self
        }
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
