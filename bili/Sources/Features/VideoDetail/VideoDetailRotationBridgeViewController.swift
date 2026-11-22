import AVKit
import Combine
import SwiftUI
import UIKit

/// 详情页保留的最小 UIKit 边界：方向锁、系统旋转和生命周期恢复。
/// SwiftUI 容器宿主负责内容树和播放器布局，surface 由其内部的 representable 保持稳定。
@MainActor
final class VideoDetailRotationBridgeViewController: UIViewController {
    private let rotationPolicy = VideoDetailRotationPolicy()
    private let rotationCoordinator: PlaybackRotationCoordinator
    private let contentController: VideoDetailSwiftUIContainerViewController
    private let systemBackGestureDelegateLease = SystemBackGestureDelegateLease()
    private let onSystemChromeVisibilityChange: (Bool) -> Void
    private var cancellables = Set<AnyCancellable>()
    private var isViewActive = false
    private var rotationCompletionTask: Task<Void, Never>?
    private var rotationWatchdogTask: Task<Void, Never>?
    private var rotationGeneration = 0
    private var didPrepareForDismantle = false
    private var didRegisterNavigationStopCompletion = false
    private var isImmersivePlayback = false
    private let usesTransparentNavigationBar: Bool
    private let navigationBarTouchPassthrough = PlaybackNavigationBarTouchPassthrough()

    init(
        initialVideo: VideoItem,
        viewModel: VideoDetailViewModel,
        runtimeSettings: VideoDetailRuntimeSettingsStore,
        dependencies: AppDependencies,
        openVideoOwnerRoute: ((VideoOwner) -> Void)?,
        selectedContentTab: Binding<VideoDetailContentTab>,
        sheetRoute: Binding<VideoDetailSheetRoute?> = .constant(nil),
        splitColumnOverlay: VideoDetailSplitColumnOverlayController = VideoDetailSplitColumnOverlayController(),
        submitReply: @escaping (DynamicCommentComposerTarget, String, [DynamicCommentImage]?) async throws -> Void = { _, _, _ in },
        onShowNetworkDiagnostics: @escaping () -> Void,
        onShowFavoriteFolders: @escaping () -> Void,
        onShowCoinPicker: @escaping () -> Void,
        onOpenCommentComposer: @escaping (Comment?) -> Void,
        onShowDanmakuSettings: @escaping () -> Void,
        onPresentPlayerMoreControls: @escaping (PlayerStateViewModel, @escaping () -> Void) -> Void,
        onDismissPlayerMoreControls: @escaping () -> Void,
        onReply: @escaping (Comment) -> Void,
        onSystemChromeVisibilityChange: @escaping (Bool) -> Void,
        usesTransparentNavigationBar: Bool = false,
        onNavigateBack: @escaping () -> Void
    ) {
        let rotationCoordinator = PlaybackRotationCoordinator()
        self.rotationCoordinator = rotationCoordinator
        self.onSystemChromeVisibilityChange = onSystemChromeVisibilityChange
        self.usesTransparentNavigationBar = usesTransparentNavigationBar
        contentController = VideoDetailSwiftUIContainerViewController(
            initialVideo: initialVideo,
            viewModel: viewModel,
            runtimeSettings: runtimeSettings,
            dependencies: dependencies,
            rotationCoordinator: rotationCoordinator,
            openVideoOwnerRoute: openVideoOwnerRoute,
            selectedContentTab: selectedContentTab,
            sheetRoute: sheetRoute,
            splitColumnOverlay: splitColumnOverlay,
            submitReply: submitReply,
            onShowNetworkDiagnostics: onShowNetworkDiagnostics,
            onShowFavoriteFolders: onShowFavoriteFolders,
            onShowCoinPicker: onShowCoinPicker,
            onOpenCommentComposer: onOpenCommentComposer,
            onShowDanmakuSettings: onShowDanmakuSettings,
            onPresentPlayerMoreControls: onPresentPlayerMoreControls,
            onDismissPlayerMoreControls: onDismissPlayerMoreControls,
            onReply: onReply,
            onToggleDanmaku: viewModel.toggleDanmaku,
            usesTransparentNavigationBar: usesTransparentNavigationBar,
            onNavigateBack: onNavigateBack
        )
        super.init(nibName: nil, bundle: nil)
        contentController.rotationDelegate = self
        bindApplicationLifecycleForRotationRecovery()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateSelectedContentTab(_ binding: Binding<VideoDetailContentTab>) {
        contentController.updateSelectedContentTab(binding)
    }

    func updateSheetRoute(_ binding: Binding<VideoDetailSheetRoute?>) {
        contentController.updateSheetRoute(binding)
    }

    func updateNavigateBackAction(_ action: @escaping () -> Void) {
        contentController.updateNavigateBackAction(action)
    }

    func updateNavigationHistory(_ history: NavigationHistoryContext?) {
        contentController.contentModel.updateNavigationHistory(history)
    }

    func scheduleNavigationHistoryUpdate(_ history: NavigationHistoryContext?) {
        guard history != nil || contentController.contentModel.navigationHistory != nil else { return }
        DispatchQueue.main.async { [weak self] in self?.updateNavigationHistory(history) }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        // 实验与经典模式一致：跟随 App 层掩码（由 rotationCoordinator 按视频
        // 内容方向与全屏状态维护），重力旋转走页面旋转机制。
        AppOrientationLock.supportedOrientations
    }

    override var prefersStatusBarHidden: Bool {
        isImmersivePlayback
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        isImmersivePlayback
    }

    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        isImmersivePlayback ? .all : []
    }

    @available(iOS 27.1, *)
    override var preferredVerticalBarBehavior: UIVerticalBarBehavior {
        if isImmersivePlayback || AdaptiveLayoutPolicy.isDuoUnfoldedInnerDisplay(
            containerSize: view.bounds.size,
            userInterfaceIdiom: traitCollection.userInterfaceIdiom
        ) {
            return .disabled
        }
        return .automatic
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        addChild(contentController)
        contentController.view.backgroundColor = .clear
        contentController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentController.view)
        NSLayoutConstraint.activate([
            contentController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentController.view.topAnchor.constraint(equalTo: view.topAnchor),
            contentController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        contentController.didMove(toParent: self)
        contentController.viewModel.isRouteRemovedFromNavigationStack = { [weak self] in
            guard let self else { return true }
            return self.isRemovedOrLeavingNavigationHierarchy
        }
        contentController.viewModel.playerWindowFrameProvider = { [weak self] in
            guard let self else { return (nil, nil) }
            let window = self.view.window
            let frameInWindow = self.contentController.playerFrame.width > 16
                ? self.contentController.view.convert(self.contentController.playerFrame, to: window)
                : nil
            return (frameInWindow, window)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isViewActive = true
        updateOrientationLock()
        reconcileTransparentNavigationBarSafeAreaIfNeeded()
        if shouldUseImmersiveChrome(
            for: view.bounds.size,
            isLandscapeFullscreen: resolvedLandscapeForRecovery
        ) {
            setImmersivePlayback(true)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        reconcileTransparentNavigationBarSafeAreaIfNeeded()
        if isViewActive, !rotationCoordinator.isTransitioning {
            setImmersivePlayback(
                shouldUseImmersiveChrome(
                    for: view.bounds.size,
                    isLandscapeFullscreen: rotationCoordinator.layoutLandscape
                )
            )
        }
#if DEBUG
        print(
            "[VideoDetailGeometry] stage=rotationBridgeLayout window=\(view.window?.bounds as Any) root=\(view.bounds) safeArea=\(view.safeAreaInsets) playerFrame=\(contentController.playerFrame)"
        )
#endif
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        reconcileTransparentNavigationBarSafeAreaIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isViewActive = true
        didRegisterNavigationStopCompletion = false
        contentController.viewModel.clearExitingVideoDetailRoute()
        rotationCoordinator.activate(
            isLandscape: resolvedLandscapeForRecovery,
            isPortraitFullscreen: rotationCoordinator.isPortraitFullscreen
        )
        setImmersivePlayback(
            shouldUseImmersiveChrome(
                for: view.bounds.size,
                isLandscapeFullscreen: resolvedLandscapeForRecovery
            )
        )
        contentController.setSecondaryContentMounted(true)
        if rotationCoordinator.isTransitioning {
            recoverInterruptedRotationIfNeeded(reason: "viewDidAppear")
        } else {
            contentController.recoverStableLayout()
        }
        updateOrientationLock()
        reconcileTransparentNavigationBarSafeAreaIfNeeded()
        restoreSystemBackGestures()
        if usesTransparentNavigationBar {
            navigationBarTouchPassthrough.begin(in: navigationController)
        }
        contentController.setBackgroundRenderFreezeActive(false)
    }

    /// 当外层页面保留透明 NavigationBar 时，UINavigationController 会向
    /// NavigationStackHostingController 注入导航栏高度（~54pt）的顶部安全区。
    /// 详情页播放器已自行按 `window.safeAreaInsets.top` 排版，若不抵消该残留安全区，
    /// 会沿 UIKit 视图树透传进内嵌 `AVPlayerViewController` 并挤压折叠顶部系统控件
    /// （全屏、AirPlay 与静音按钮在竖屏 16:9 播放器内归零隐藏）。
    private func reconcileTransparentNavigationBarSafeAreaIfNeeded() {
        guard usesTransparentNavigationBar,
              !isCoveredByNativePlayerFullscreenPresentation,
              let navHost = parent,
              let navController = navHost.parent as? UINavigationController,
              navController.viewControllers.first !== navHost,
              let window = view.window
        else { return }
        let baseTopInset = navHost.view.safeAreaInsets.top - navHost.additionalSafeAreaInsets.top
        let windowTopInset = window.safeAreaInsets.top
        let desiredAdditionalTop = -max(0, baseTopInset - windowTopInset)
        if abs(navHost.additionalSafeAreaInsets.top - desiredAdditionalTop) > 0.5 {
            navHost.additionalSafeAreaInsets.top = desiredAdditionalTop
        }
    }

    /// 同步识别"被系统全屏模态覆盖"：全屏标记经 AVKit 回调异步置位，
    /// 转场早期生命周期回调可能先到，需直接查 presentedViewController 链
    /// （AVKit 私有全屏容器类名含 FullScreen；手动 present 的即播放器本身）。
    private var isCoveredByNativePlayerFullscreenPresentation: Bool {
        if contentController.viewModel.stablePlayerViewModel?.isNativeFullScreenPresented == true {
            return true
        }
        var cursor: UIViewController? = self
        while let controller = cursor {
            if let presented = controller.presentedViewController {
                if presented is AVPlayerViewController { return true }
                if NSStringFromClass(type(of: presented)).contains("FullScreen") { return true }
            }
            cursor = controller.parent
        }
        return false
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationBarTouchPassthrough.end()
        isViewActive = false
        let isLeavingHierarchy = isRemovedOrLeavingNavigationHierarchy
        if NativePlaybackControlsExperiment.stored(),
           !isLeavingHierarchy,
           isCoveredByNativePlayerFullscreenPresentation {
            return
        }
        if isLeavingHierarchy {
            NativeFullscreenOrientationLease.shared.cancel()
            contentController.viewModel.markExitingVideoDetailRoute()
        } else if NativePlaybackControlsExperiment.stored() {
            // 被其他页面/标签页/弹层覆盖时收回 App 层自由旋转，恢复全局竖屏。
            NativeFullscreenOrientationLease.shared.cancel()
            AppOrientationLock.update(to: .portrait, in: view.window?.windowScene)
        }
        let preferredWindow = view.window
        let playerFrameInWindow = contentController.playerFrame.width > 16
            ? contentController.view.convert(contentController.playerFrame, to: preferredWindow)
            : nil
        finishPlaybackStopAfterNavigationTransition(
            isLeavingHierarchy: isLeavingHierarchy,
            preferredFrameInWindow: playerFrameInWindow,
            preferredWindow: preferredWindow
        )
        contentController.dismissPlayerMoreControls()
        recoverInterruptedRotationIfNeeded(reason: "viewWillDisappear")
        cancelRotationTasks()
        rotationCoordinator.deactivate(in: view.window?.windowScene)
        contentController.setBackgroundRenderFreezeActive(!isLeavingHierarchy)
        releaseSystemBackGestureOwnership()
    }

    private func resolveDestinationHostingController(
        in navigationController: UINavigationController
    ) -> UIViewController? {
        var cursor: UIViewController? = self
        while let controller = cursor {
            if controller.parent === navigationController {
                return controller
            }
            if controller.parent is UINavigationController || controller.parent is UITabBarController {
                break
            }
            cursor = controller.parent
        }
        return nil
    }

    /// Detects both button pops and interactive swipe-back pops across UIKit and
    /// SwiftUI `NavigationStack` while ignoring child pushes (e.g. related videos,
    /// uploader pages) on top of this controller.
    private var isRemovedOrLeavingNavigationHierarchy: Bool {
        if navigationController?.isBeingDismissed == true {
            return true
        }
        var cursor: UIViewController? = self
        while let controller = cursor {
            if controller.isMovingFromParent || controller.isBeingDismissed {
                return true
            }
            if controller.parent is UINavigationController || controller.parent is UITabBarController {
                break
            }
            cursor = controller.parent
        }
        guard let navigationController else { return true }
        if let destinationVC = resolveDestinationHostingController(in: navigationController) {
            return !navigationController.viewControllers.contains(where: { $0 === destinationVC })
        }
        return false
    }

    private func finishPlaybackStopAfterNavigationTransition(
        isLeavingHierarchy: Bool,
        preferredFrameInWindow: CGRect?,
        preferredWindow: UIWindow?
    ) {
        guard !didRegisterNavigationStopCompletion else { return }
        didRegisterNavigationStopCompletion = true

        let attemptHandoff: () -> Bool = { [weak self] in
            guard let self else { return false }
            let viewModel = self.contentController.viewModel
            guard isLeavingHierarchy || self.isRemovedOrLeavingNavigationHierarchy else {
                return false
            }
            viewModel.markExitingVideoDetailRoute()
            let currentWindow = self.view.window ?? preferredWindow
            let liveFrameInWindow: CGRect? = self.contentController.playerFrame.width > 16
                ? self.contentController.view.convert(self.contentController.playerFrame, to: currentWindow)
                : preferredFrameInWindow
            return viewModel.handoffToSystemMiniPlayerIfEligible(
                preferredFrameInWindow: liveFrameInWindow,
                preferredWindow: currentWindow
            )
        }

        let finish = { [weak self] in
            guard let self else { return }
            if attemptHandoff() {
                return
            }
            _ = Task { @MainActor [weak self] in
                await Task.yield()
                self?.contentController.viewModel.finishPlaybackStopAfterNavigationTransition()
            }
        }

        guard let transitionCoordinator else {
            finish()
            return
        }

        if transitionCoordinator.isInteractive {
            // Hand off as soon as the user releases the swipe-back gesture without cancelling,
            // so system PiP begins shrinking alongside the remaining pop animation instead of
            // popping in abruptly after the detail page has already disappeared.
            transitionCoordinator.notifyWhenInteractionChanges { [weak self] context in
                guard !context.isCancelled else {
                    self?.contentController.viewModel.clearExitingVideoDetailRoute()
                    return
                }
                _ = attemptHandoff()
            }
        } else {
            _ = attemptHandoff()
        }

        transitionCoordinator.animate(alongsideTransition: nil) { [weak self] context in
            guard !context.isCancelled else {
                self?.contentController.viewModel.clearExitingVideoDetailRoute()
                return
            }
            finish()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        let isLeavingHierarchy = isRemovedOrLeavingNavigationHierarchy
        if NativePlaybackControlsExperiment.stored(),
           !isLeavingHierarchy,
           isCoveredByNativePlayerFullscreenPresentation {
            // 系统全屏模态覆盖期间（.fullScreen 呈现会触发本回调）：
            // 不做方向回收与页面清理，交给方向租约与全屏退出流程。
            isViewActive = false
            releaseSystemBackGestureOwnership()
            return
        }
        contentController.markPageDisappeared()
        isViewActive = false
        setImmersivePlayback(false)
        cancelRotationTasks()
        NativeFullscreenOrientationLease.shared.cancel()
        rotationCoordinator.deactivate(in: view.window?.windowScene)
        rotationCoordinator.restorePortrait(in: view.window?.windowScene)
        releaseSystemBackGestureOwnership()
        if isMovingFromParent || isBeingDismissed || navigationController?.isBeingDismissed == true {
            contentController.setBackgroundRenderFreezeActive(false)
        } else {
            contentController.setBackgroundRenderFreezeActive(true)
        }
    }

    func prepareForDismantle() {
        guard !didPrepareForDismantle else { return }
        didPrepareForDismantle = true
        NativeFullscreenOrientationLease.shared.cancel()
        let viewModel = contentController.viewModel
        viewModel.isRouteRemovedFromNavigationStack = nil
        viewModel.playerWindowFrameProvider = nil
        if !viewModel.isAwaitingRelatedVideoReturnPlayback {
            viewModel.markExitingVideoDetailRoute()
            let preferredWindow = view.window
            let playerFrameInWindow = contentController.playerFrame.width > 16
                ? contentController.view.convert(contentController.playerFrame, to: preferredWindow)
                : nil
            _ = viewModel.handoffToSystemMiniPlayerIfEligible(
                preferredFrameInWindow: playerFrameInWindow,
                preferredWindow: preferredWindow
            )
        }
        navigationBarTouchPassthrough.end()
        setImmersivePlayback(false)
        recoverInterruptedRotationIfNeeded(reason: "dismantle")
        cancelRotationTasks()
        rotationCoordinator.deactivate(in: view.window?.windowScene)
        contentController.prepareForDismantle()
        releaseSystemBackGestureOwnership()
    }

    override func viewWillTransition(
        to size: CGSize,
        with transitionCoordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: transitionCoordinator)
        let toLandscape: Bool
        if AdaptiveLayoutPolicy.treatsLandscapeRotationAsSplitDetail(
            containerSize: size,
            traitCollection: traitCollection,
            adaptiveEnabled: contentController.viewModel.libraryStore.adaptiveLargeScreenLayoutExperimentEnabled
        ) {
            toLandscape = rotationCoordinator.isLandscape
        } else {
            toLandscape = size.width > size.height
        }
        rotationGeneration += 1
        let generation = rotationGeneration
        cancelRotationTasks()
        if toLandscape != rotationCoordinator.isLandscape {
            rotationCoordinator.beginSystemTransition(toLandscape: toLandscape)
        }
        // The outer SwiftUI page owns the toolbar. System-driven rotation
        // must notify it too, not just requests from the fullscreen button.
        setImmersivePlayback(
            shouldUseImmersiveChrome(
                for: size,
                isLandscapeFullscreen: toLandscape
            )
        )
        if toLandscape != rotationCoordinator.isLandscape || rotationCoordinator.isTransitioning {
            contentController.beginSystemRotation(toLandscape: toLandscape)
            contentController.markRotationStarted(toLandscape: toLandscape)
            scheduleRotationWatchdog(
                generation: generation,
                coordinatorDuration: transitionCoordinator.transitionDuration
            )
        }
        if toLandscape {
            contentController.dismissPlayerMoreControls()
        }
        transitionCoordinator.animate(alongsideTransition: { [weak self] _ in
            self?.setNeedsStatusBarAppearanceUpdate()
            self?.setNeedsUpdateOfHomeIndicatorAutoHidden()
            self?.setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
            self?.contentController.view.layoutIfNeeded()
        }, completion: { [weak self] _ in
            guard let self, self.rotationGeneration == generation else { return }
            if self.rotationCoordinator.isTransitioning {
                self.contentController.markSystemTransitionEnded()
                self.scheduleRotationCompletion(
                    generation: generation,
                    toLandscape: toLandscape,
                    settleDelay: PlaybackDetailRotationTiming.recoverySettleDelay
                )
            } else {
                self.contentController.recoverStableLayout()
            }
        })
    }

    private func requestFullscreen() {
        if contentController.isPortraitVideo {
            setImmersivePlayback(true)
            rotationCoordinator.setPortraitFullscreen(true)
            updateOrientationLock()
            setNeedsStatusBarAppearanceUpdate()
            setNeedsUpdateOfHomeIndicatorAutoHidden()
            return
        }
        if AdaptiveLayoutPolicy.treatsLandscapeRotationAsSplitDetail(
            containerSize: view.bounds.size,
            traitCollection: traitCollection,
            adaptiveEnabled: contentController.viewModel.libraryStore.adaptiveLargeScreenLayoutExperimentEnabled
        ) {
            setImmersivePlayback(true)
            rotationCoordinator.setInPlaceFullscreen(true)
            contentController.recoverStableLayout()
            setNeedsStatusBarAppearanceUpdate()
            setNeedsUpdateOfHomeIndicatorAutoHidden()
            return
        }
        let scene = view.window?.windowScene
        if scene?.effectiveGeometry.interfaceOrientation.isLandscape == true {
            setImmersivePlayback(true)
            rotationCoordinator.reconcileStableState(
                isLandscape: true,
                isPortraitFullscreen: false
            )
            contentController.recoverStableLayout()
            return
        }
        // Defer hiding the bottom toolbar and status bar until `viewWillTransition`
        // so portrait safe-area/toolbar animations do not race with `requestGeometryUpdate`.
        rotationCoordinator.allowLandscape(in: scene)
        let target = rotationPolicy.preferredLandscapeInterfaceOrientation(
            currentInterfaceOrientation: scene?.effectiveGeometry.interfaceOrientation,
            deviceOrientation: UIDevice.current.orientation
        )
        rotationCoordinator.requestGeometryUpdate(to: target, in: scene) { [weak self] _ in
            self?.reconcileOrientationStateAfterRejectedRequest()
        }
    }

    private func requestExitFullscreen() {
        if rotationCoordinator.isPortraitFullscreen {
            rotationCoordinator.setPortraitFullscreen(false)
            setImmersivePlayback(
                shouldUseImmersiveChrome(for: view.bounds.size, isLandscapeFullscreen: false)
            )
            contentController.recoverStableLayout()
            updateOrientationLock()
            setNeedsStatusBarAppearanceUpdate()
            setNeedsUpdateOfHomeIndicatorAutoHidden()
            return
        }
        if rotationCoordinator.isInPlaceFullscreen {
            rotationCoordinator.setInPlaceFullscreen(false)
            setImmersivePlayback(
                shouldUseImmersiveChrome(for: view.bounds.size, isLandscapeFullscreen: false)
            )
            contentController.recoverStableLayout()
            updateOrientationLock()
            setNeedsStatusBarAppearanceUpdate()
            setNeedsUpdateOfHomeIndicatorAutoHidden()
            return
        }
        let scene = view.window?.windowScene
        if scene?.effectiveGeometry.interfaceOrientation.isPortrait == true {
            setImmersivePlayback(
                shouldUseImmersiveChrome(for: view.bounds.size, isLandscapeFullscreen: false)
            )
            rotationCoordinator.reconcileStableState(
                isLandscape: false,
                isPortraitFullscreen: false
            )
            contentController.recoverStableLayout()
            return
        }
        rotationCoordinator.allowLandscape(in: scene)
        rotationCoordinator.requestGeometryUpdate(to: .portrait, in: scene) { [weak self] _ in
            self?.reconcileOrientationStateAfterRejectedRequest()
        }
    }

    private func reconcileOrientationStateAfterRejectedRequest() {
        guard isViewActive, !didPrepareForDismantle else { return }
        guard !rotationCoordinator.isSystemRotationTransitioning else { return }
        let landscape = resolvedLandscapeForRecovery
        rotationCoordinator.reconcileStableState(
            isLandscape: landscape,
            isPortraitFullscreen: rotationCoordinator.isPortraitFullscreen
        )
        setImmersivePlayback(
            shouldUseImmersiveChrome(for: view.bounds.size, isLandscapeFullscreen: landscape)
        )
        contentController.recoverStableLayout()
    }

    private func handleBackButton() {
        if rotationCoordinator.isAnyFullscreen {
            requestExitFullscreen()
        } else {
            contentController.recoverStableLayout()
            contentController.navigateBack()
        }
    }

    private func updateOrientationLock() {
        guard isViewActive else { return }
        if AdaptiveLayoutPolicy.allowsUnrestrictedRootOrientation(for: view.window) {
            let mask: UIInterfaceOrientationMask = view.window?.traitCollection.userInterfaceIdiom == .pad
                ? .all
                : .allButUpsideDown
            AppOrientationLock.update(to: mask, in: view.window?.windowScene)
            return
        }
        if contentController.viewModel.libraryStore.usesSystemNativePlaybackControlsUI {
            // 系统原生控制栏模式下放开 App 层方向：这是 AVKit 显示系统自带全屏按钮的前提；
            // 「原生底座 + 自绘控件」与纯自绘模式统一走 rotationCoordinator 方向策略。
            guard NativeFullscreenOrientationLease.shared.phase == nil else { return }
            AppOrientationLock.update(to: .allButUpsideDown, in: view.window?.windowScene)
            return
        }
        rotationCoordinator.updateOrientationLock(
            isPortraitVideo: contentController.isPortraitVideo,
            isCurrentlyLandscape: rotationCoordinator.isLandscape,
            in: view.window?.windowScene
        )
    }

    private func shouldUseImmersiveChrome(
        for containerSize: CGSize,
        isLandscapeFullscreen: Bool
    ) -> Bool {
        if isLandscapeFullscreen
            || rotationCoordinator.isPortraitFullscreen
            || rotationCoordinator.isInPlaceFullscreen {
            return true
        }
        let adaptiveEnabled = contentController.viewModel.libraryStore.adaptiveLargeScreenLayoutExperimentEnabled
        let resolvedHorizontalSizeClass: UserInterfaceSizeClass? =
            traitCollection.horizontalSizeClass == .compact ? .compact : .regular
        return AdaptiveLayoutPolicy.videoDetailMode(
            containerSize: containerSize,
            horizontalSizeClass: resolvedHorizontalSizeClass,
            isFullscreenActive: false,
            adaptiveEnabled: adaptiveEnabled
        ) == .twoColumnSplit
    }

    private func setImmersivePlayback(_ active: Bool) {
        guard isImmersivePlayback != active else { return }
        isImmersivePlayback = active
        onSystemChromeVisibilityChange(active)
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        if #available(iOS 27.1, *) {
            setNeedsUpdateOfVerticalBarConfiguration()
        }
    }

    private func bindApplicationLifecycleForRotationRecovery() {
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isViewActive else { return }
                    self.recoverInterruptedRotationIfNeeded(reason: "applicationWillResignActive")
                }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isViewActive else { return }
                    if !self.recoverInterruptedRotationIfNeeded(reason: "applicationDidBecomeActive") {
                        self.contentController.recoverStableLayout()
                        self.setImmersivePlayback(
                            self.shouldUseImmersiveChrome(
                                for: self.view.bounds.size,
                                isLandscapeFullscreen: self.resolvedLandscapeForRecovery
                            )
                        )
                    }
                    self.updateOrientationLock()
                }
            }
            .store(in: &cancellables)
    }

    private func scheduleRotationWatchdog(
        generation: Int,
        coordinatorDuration: TimeInterval
    ) {
        rotationWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(
                VideoDetailRotationRecoveryPolicy().watchdogDelay(
                    coordinatorDuration: coordinatorDuration
                )
            ))
            guard let self,
                  !Task.isCancelled,
                  self.rotationGeneration == generation,
                  self.rotationCoordinator.isTransitioning
            else { return }
            self.recoverInterruptedRotationIfNeeded(reason: "watchdogTimeout")
        }
    }

    private func scheduleRotationCompletion(
        generation: Int,
        toLandscape: Bool,
        settleDelay: TimeInterval
    ) {
        rotationCompletionTask = Task { @MainActor [weak self] in
            if settleDelay > 0 {
                try? await Task.sleep(for: .seconds(settleDelay))
            }
            try? await Task.sleep(for: .milliseconds(34))
            guard let self,
                  !Task.isCancelled,
                  self.rotationGeneration == generation
            else { return }
            let currentOrientation = self.view.window?.windowScene?.effectiveGeometry.interfaceOrientation
                ?? (toLandscape ? .landscapeRight : .portrait)
            if let pending = self.rotationCoordinator.finishSystemTransition(
                toLandscape: toLandscape,
                currentOrientation: currentOrientation
            ) {
                self.rotationCoordinator.requestGeometryUpdate(
                    to: pending,
                    in: self.view.window?.windowScene
                )
            }
            self.contentController.finishSystemRotation()
            self.setImmersivePlayback(
                self.shouldUseImmersiveChrome(
                    for: self.view.bounds.size,
                    isLandscapeFullscreen: self.rotationCoordinator.layoutLandscape
                )
            )
            let actualOrientation: String?
            switch currentOrientation {
            case .portrait:
                actualOrientation = "portrait"
            case .landscapeLeft:
                actualOrientation = "landscapeLeft"
            case .landscapeRight:
                actualOrientation = "landscapeRight"
            default:
                actualOrientation = nil
            }
            self.contentController.markRotationFinished(
                toLandscape: toLandscape,
                actualOrientation: actualOrientation
            )
            self.rotationWatchdogTask?.cancel()
            self.rotationWatchdogTask = nil
            self.setNeedsStatusBarAppearanceUpdate()
            self.setNeedsUpdateOfHomeIndicatorAutoHidden()
        }
    }

    @discardableResult
    private func recoverInterruptedRotationIfNeeded(reason: String) -> Bool {
        guard rotationCoordinator.isTransitioning else { return false }
        rotationGeneration += 1
        cancelRotationTasks()
        let landscape = VideoDetailRotationRecoveryPolicy().resolvesLandscape(
            interfaceOrientation: view.window?.windowScene?.effectiveGeometry.interfaceOrientation,
            fallbackBounds: view.bounds.size
        )
        rotationCoordinator.recover(
            isLandscape: landscape,
            isPortraitFullscreen: rotationCoordinator.isPortraitFullscreen
        )
        if isViewActive, !didPrepareForDismantle {
            setImmersivePlayback(
                shouldUseImmersiveChrome(
                    for: view.bounds.size,
                    isLandscapeFullscreen: landscape
                )
            )
        }
        contentController.recoverStableLayout()
        contentController.markRotationRecovered(reason: reason)
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        return true
    }

    private var resolvedLandscapeForRecovery: Bool {
        if AdaptiveLayoutPolicy.treatsLandscapeRotationAsSplitDetail(
            containerSize: view.bounds.size,
            traitCollection: traitCollection,
            adaptiveEnabled: contentController.viewModel.libraryStore.adaptiveLargeScreenLayoutExperimentEnabled
        ) {
            return rotationCoordinator.isLandscape
        }
        return VideoDetailRotationRecoveryPolicy().resolvesLandscape(
            interfaceOrientation: view.window?.windowScene?.effectiveGeometry.interfaceOrientation,
            fallbackBounds: view.bounds.size
        )
    }

    private func cancelRotationTasks() {
        rotationCompletionTask?.cancel()
        rotationCompletionTask = nil
        rotationWatchdogTask?.cancel()
        rotationWatchdogTask = nil
    }

    private func restoreSystemBackGestures() {
        guard let navigationController else { return }
        systemBackGestureDelegateLease.acquire(in: navigationController, owner: self)
    }

    private func releaseSystemBackGestureOwnership() {
        systemBackGestureDelegateLease.release()
    }

    private func isSystemBackGesture(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigationController else { return false }
        return gestureRecognizer === navigationController.interactivePopGestureRecognizer
            || gestureRecognizer === navigationController.interactiveContentPopGestureRecognizer
    }
}

extension VideoDetailRotationBridgeViewController: VideoDetailRotationBridgeDelegate {
    func requestVideoDetailFullscreen() {
        requestFullscreen()
    }

    func requestVideoDetailExitFullscreen() {
        requestExitFullscreen()
    }

    func navigateBackFromVideoDetail() {
        handleBackButton()
    }
}

extension VideoDetailRotationBridgeViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard isSystemBackGesture(gestureRecognizer) else { return true }
        guard !rotationCoordinator.isAnyFullscreen else { return false }
        guard let navigationController,
              navigationController.viewControllers.count > 1
        else { return false }
        contentController.suppressContentActionsDuringSystemBackGesture()
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard isSystemBackGesture(gestureRecognizer) else { return true }
        guard !rotationCoordinator.isAnyFullscreen else { return false }
        return !contentController.playerFrame.contains(touch.location(in: view))
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard isSystemBackGesture(gestureRecognizer)
            || isSystemBackGesture(otherGestureRecognizer)
        else { return true }
        return !(gestureRecognizer is UITapGestureRecognizer
            || otherGestureRecognizer is UITapGestureRecognizer)
    }
}
