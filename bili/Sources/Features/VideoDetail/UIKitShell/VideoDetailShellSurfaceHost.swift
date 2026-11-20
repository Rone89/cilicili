import AVFoundation
import AVKit
import Combine
import SwiftUI
import UIKit

/// 详情页 UIKit 外壳：播放器宿主（surface-only + 独立控件浮层）。
///
/// UIKit 容器只驱动 frame；视频层可绕过 surface-only SwiftUI Hosting，
/// 控件/手势/加载态作为 overlay 叠上去，不再让完整 `BiliPlayerView` 的
/// presentation 切换参与旋转。
@MainActor
final class VideoDetailShellSurfaceHost: UIView {
    @MainActor
    final class State: ObservableObject {
        @Published var isBareSurfaceTransitionActive = false
        @Published var retainsChromeDuringBareSurfaceTransition = false
        @Published var isCollapsedChromeActive = false
        @Published var playbackControlsHideRequestGeneration = 0
        @Published var playbackControlsRevealRequestGeneration = 0
        @Published var playerViewModel: PlayerStateViewModel
        @Published var videoAspectRatio: CGFloat = 16.0 / 9.0
        @Published var danmakuCanvasSize: CGSize?

        init(playerViewModel: PlayerStateViewModel) {
            self.playerViewModel = playerViewModel
        }

        func setBareSurfaceTransitionActive(_ active: Bool, retainsChromeTree: Bool) {
            if active {
                // 保留控件树时，先设标志再进入 bare state，避免 SwiftUI 删除子树。
                retainsChromeDuringBareSurfaceTransition = retainsChromeTree
                isBareSurfaceTransitionActive = true
            } else {
                // 先退出 bare state，再清标志，保证控件树连续存在。
                isBareSurfaceTransitionActive = false
                retainsChromeDuringBareSurfaceTransition = false
            }
        }

        func requestPlaybackControlsHideForRotation() {
            playbackControlsHideRequestGeneration &+= 1
        }
#if DEBUG
        func requestPlaybackControlsRevealForTesting() {
            playbackControlsRevealRequestGeneration &+= 1
        }
#endif
    }

    private let state: State
    private weak var detailViewModel: VideoDetailViewModel?
    private let overlayState: VideoDetailShellOverlayState
    private let experimentState: VideoDetailPerformanceExperimentState
    private let libraryStore: LibraryStore
    private let rotationCoordinator: PlaybackRotationCoordinator
    private let onShowMoreControls: (@escaping () -> Void) -> Void
    private let onRequestFullscreen: () -> Void
    private let onExitFullscreen: () -> Void
    private let onToggleDanmaku: () -> Void
    private let onShowDanmakuSettings: () -> Void
    private let surfaceHostView: DirectUIKitPlayerSurfaceHostView
    private let playbackTransitionImageView = UIImageView()
    private var nativeOptionsButton: UIButton?
    private var nativeQualityButton: UIButton?
    private var nativeOptionsContainerView: UIView?
    private var nativeControlsGlassGroup: NativeControlsGlassGroup?
    private var nativeOptionsBottomConstraint: NSLayoutConstraint?
    private var nativeOptionsTrailingConstraint: NSLayoutConstraint?
    private var nativeInlineExitFullscreenButton: UIButton?
    private var nativeInlineFullscreenButtonShowsExitIcon: Bool?
    private var nativeInlineExitCenterXConstraint: NSLayoutConstraint?
    private var nativeInlineExitCenterYConstraint: NSLayoutConstraint?
    private weak var suppressedNativeFullscreenButton: UIView?
    private var lastSyncedNativeControlsAlpha: CGFloat = 0
    private var lastSyncedNativeControlsInteractive = false
    private var nativeControlsVisibilitySynchronizer: NativeControlsVisibilitySynchronizer?
    private var playbackTransitionIsVideoFrame = true
    private var videoGravity: AVLayerVideoGravity = .resizeAspect
    private let overlayHostingController: UIHostingController<AnyView>
    /// 全屏迁移还原用：弹幕/字幕宿主在详情页层级里的原始父控制器。
    private var overlayOriginalParent: UIViewController?
    private var didInstallNativeSystemControlsAccessories = false
    private var nativeFullScreenPresentationCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var rotationChromePrewarmGeneration = 0
    private var isRotationChromePrewarming = false
    private(set) var isRotationChromePrewarmed = false
    private(set) var isTornDown = false
    var isTransferredToSystemMiniPlayer: Bool {
        detailViewModel?.didTransferToSystemMiniPlayer == true
    }
    private var canMutateBoundPlayer: Bool {
        !isTornDown && !isTransferredToSystemMiniPlayer
    }
#if DEBUG
    private var lastReportedDiagnosticOverlayBounds = CGRect.null
#endif

    init(
        playerViewModel: PlayerStateViewModel,
        detailViewModel: VideoDetailViewModel,
        dependencies: AppDependencies,
        runtimeSettings: VideoDetailRuntimeSettingsStore,
        rotationCoordinator: PlaybackRotationCoordinator,
        onShowMoreControls: @escaping (@escaping () -> Void) -> Void,
        onDismissMoreControls: @escaping () -> Void,
        onRequestFullscreen: @escaping () -> Void,
        onExitFullscreen: @escaping () -> Void,
        onToggleDanmaku: @escaping () -> Void,
        onShowDanmakuSettings: @escaping () -> Void
    ) {
#if DEBUG
        PlayerMetricsLog.signpostEvent("VideoDetailDirectSurfaceHost")
#endif
        let state = State(playerViewModel: playerViewModel)
        let experimentState = VideoDetailPerformanceExperimentState(
            directUIKitSurfaceEnabled: true,
            narrowPlayerOverlayObservationEnabled: true
        )
        let overlayState = VideoDetailShellOverlayState(
            detailViewModel: detailViewModel,
            experimentState: experimentState
        )
        self.state = state
        self.detailViewModel = detailViewModel
        self.overlayState = overlayState
        self.experimentState = experimentState
        self.libraryStore = dependencies.libraryStore
        let bindsPlayerSurface = !detailViewModel.didTransferToSystemMiniPlayer
        if bindsPlayerSurface {
            playerViewModel.setBackgroundPlaybackEnabled(
                dependencies.libraryStore.backgroundPlaybackEnabled
            )
            playerViewModel.setAutomaticPictureInPictureFromInlineAllowed(
                dependencies.libraryStore.pictureInPictureEnabled
            )
        }
        self.rotationCoordinator = rotationCoordinator
        self.onShowMoreControls = onShowMoreControls
        self.onRequestFullscreen = onRequestFullscreen
        self.onExitFullscreen = onExitFullscreen
        self.onToggleDanmaku = onToggleDanmaku
        self.onShowDanmakuSettings = onShowDanmakuSettings
        let usesNativeSurface = dependencies.libraryStore.usesNativePlaybackSurface
        let usesSystemControlsUI = dependencies.libraryStore.usesSystemNativePlaybackControlsUI
        let usesCustomOverlay = dependencies.libraryStore.usesCustomPlaybackControlsOverlay
        self.surfaceHostView = DirectUIKitPlayerSurfaceHostView(
            viewModel: playerViewModel,
            isPictureInPictureEnabled: dependencies.libraryStore.allowsPictureInPictureController
                && !playerViewModel.isAudioOnlyPlayback,
            allowsAutomaticPictureInPictureFromInline: dependencies.libraryStore.pictureInPictureEnabled,
            prefersNativePlaybackSurface: usesNativeSurface,
            showsNativePlaybackControls: usesSystemControlsUI,
            showsNativePlaybackSpeeds: true,
            enablesNativeSurfaceGestures: usesNativeSurface && !usesCustomOverlay,
            nativeAllowsPictureInPicturePlayback: nil,
            bindsSurfaceImmediately: bindsPlayerSurface
        )
        let overlayRoot = PlayerOverlayHostRoot(
            detailViewModel: detailViewModel,
            state: state,
            rotationCoordinator: rotationCoordinator,
            overlayState: overlayState,
            experimentState: experimentState,
            runtimeSettings: runtimeSettings,
            usesNarrowObservation: true,
            dependencies: dependencies,
            onShowMoreControls: onShowMoreControls,
            onDismissMoreControls: onDismissMoreControls,
            onRequestFullscreen: onRequestFullscreen,
            onExitFullscreen: onExitFullscreen,
            onToggleDanmaku: onToggleDanmaku,
            onShowDanmakuSettings: onShowDanmakuSettings
        )
        self.overlayHostingController = UIHostingController(rootView: AnyView(overlayRoot))
        super.init(frame: .zero)

        backgroundColor = .black
        overlayHostingController.view.backgroundColor = .clear
        overlayHostingController.view.isOpaque = false
        overlayHostingController.view.isUserInteractionEnabled = usesCustomOverlay
        if #available(iOS 16.4, *) {
            overlayHostingController.safeAreaRegions = []
        }
        let hostedSurfaceView = surfaceHostView
        hostedSurfaceView.translatesAutoresizingMaskIntoConstraints = false
        hostedSurfaceView.isUserInteractionEnabled = !usesCustomOverlay
        playbackTransitionImageView.translatesAutoresizingMaskIntoConstraints = false
        playbackTransitionImageView.backgroundColor = .black
        playbackTransitionImageView.clipsToBounds = true
        playbackTransitionImageView.isUserInteractionEnabled = false
        playbackTransitionImageView.accessibilityElementsHidden = true
        playbackTransitionImageView.isHidden = true
        overlayHostingController.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostedSurfaceView)
        // Keep the outgoing frame above the drawable, below controls and danmaku.
        // The identity store publishes synchronously before the surface is rebound.
        addSubview(playbackTransitionImageView)
        addSubview(overlayHostingController.view)
        NSLayoutConstraint.activate([
            hostedSurfaceView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostedSurfaceView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostedSurfaceView.topAnchor.constraint(equalTo: topAnchor),
            hostedSurfaceView.bottomAnchor.constraint(equalTo: bottomAnchor),
            playbackTransitionImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playbackTransitionImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            playbackTransitionImageView.topAnchor.constraint(equalTo: topAnchor),
            playbackTransitionImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            overlayHostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlayHostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlayHostingController.view.topAnchor.constraint(equalTo: topAnchor),
            overlayHostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        detailViewModel.playerIdentityRenderStore.snapshotPublisher
            .sink { [weak self] snapshot in
                self?.updatePlaybackTransition(
                    snapshot: snapshot.transitionSnapshot,
                    opacity: snapshot.transitionPlayerOpacity
                )
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            dependencies.libraryStore.$pictureInPictureEnabled,
            dependencies.libraryStore.$autoPictureInPictureOnExitEnabled
        )
        .removeDuplicates { $0 == $1 }
        .sink { [weak self] isPictureInPictureEnabled, isAutoExitMiniPlayerEnabled in
            Task { @MainActor [weak self] in
                guard let self, self.canMutateBoundPlayer else { return }
                self.surfaceHostView.setPictureInPictureEnabled(
                    (isPictureInPictureEnabled || isAutoExitMiniPlayerEnabled)
                        && !self.state.playerViewModel.isAudioOnlyPlayback,
                    allowsAutomaticInline: isPictureInPictureEnabled
                )
                self.applyNativePlaybackControlsSettings()
            }
        }
        .store(in: &cancellables)

        rotationCoordinator.$isSystemRotationTransitioning
            .removeDuplicates()
            .sink { [weak self] isTransitioning in
                if isTransitioning {
                    Task { @MainActor [weak self] in
                        self?.state.requestPlaybackControlsHideForRotation()
                    }
                } else {
                    // 转场结束后强制校准布局，并在下一个主线程周期再核一次，避免延迟到来的 SwiftUI 提案覆写。
                    Task { @MainActor [weak self] in
                        guard let self, !self.isTornDown else { return }
                        self.setNeedsLayout()
                        self.layoutIfNeeded()
                        await Task.yield()
                        guard !self.isTornDown, !self.rotationCoordinator.isTransitioning else { return }
                        self.setNeedsLayout()
                        self.layoutIfNeeded()
                    }
                }
            }
            .store(in: &cancellables)

        if bindsPlayerSurface {
            bindNativeFullScreenPresentation(for: state.playerViewModel)
            if usesSystemControlsUI {
                installNativeSystemControlsAccessoriesIfNeeded()
            }
        }
    }

    private func bindNativeFullScreenPresentation(for playerViewModel: PlayerStateViewModel) {
        nativeFullScreenPresentationCancellable = playerViewModel.$isNativeFullScreenPresented
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isFullScreen in
                guard let self, self.canMutateBoundPlayer else { return }
                self.syncNativeFullScreenOverlays(isFullScreen: isFullScreen)
            }
    }

    private func installNativeSystemControlsAccessoriesIfNeeded() {
        guard !didInstallNativeSystemControlsAccessories, !isTornDown else { return }
        didInstallNativeSystemControlsAccessories = true

        let group = Self.makeNativeControlsGlassGroup()
        self.nativeControlsGlassGroup = group
        self.nativeOptionsContainerView = group.containerView
        self.nativeQualityButton = group.qualityButton
        self.nativeOptionsButton = group.optionsButton
        group.containerView.isHidden = !libraryStore.usesSystemNativePlaybackControlsUI
        attachNativeControlsContainer(group.containerView, to: self)

        let refreshMenus: @MainActor () -> Void = { [weak self] in
            guard let self, !self.isTornDown,
                  let optionsButton = self.nativeOptionsButton,
                  let qualityButton = self.nativeQualityButton,
                  let detailViewModel = self.detailViewModel else { return }
            Self.updateNativeQualityButton(
                qualityButton,
                qualityStore: detailViewModel.playbackRenderStore.qualityControlStore,
                detailViewModel: detailViewModel,
                isFullScreen: self.nativeControlsGlassGroup?.isFullScreen ?? false
            )
            optionsButton.menu = Self.makeNativeOptionsMenu(
                detailViewModel: detailViewModel,
                onToggleDanmaku: self.onToggleDanmaku,
                onShowDanmakuSettings: self.onShowDanmakuSettings,
                onShowMoreControls: self.onShowMoreControls
            )
        }
        refreshMenus()

        if let detailViewModel {
            detailViewModel.playbackRenderStore.qualityControlStore.objectWillChange
                .receive(on: RunLoop.main)
                .sink { _ in refreshMenus() }
                .store(in: &cancellables)

            detailViewModel.subtitleRenderStore.objectWillChange
                .receive(on: RunLoop.main)
                .sink { _ in refreshMenus() }
                .store(in: &cancellables)

            detailViewModel.danmakuRenderStore.objectWillChange
                .receive(on: RunLoop.main)
                .sink { _ in refreshMenus() }
                .store(in: &cancellables)
        }

        let inlineExitButton = Self.makeNativeInlineExitFullscreenButton { [weak self] in
            self?.handleNativeInlineFullscreenButtonTap()
        }
        self.nativeInlineExitFullscreenButton = inlineExitButton
        attachNativeInlineExitFullscreenButton(inlineExitButton, to: self)

        startNativeControlsVisibilitySync()

        Publishers.CombineLatest3(
            rotationCoordinator.$phase,
            rotationCoordinator.$isLandscape,
            rotationCoordinator.$isPortraitFullscreen
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _, _ in
            guard let self, !self.isTornDown else { return }
            self.syncNativeInlineExitFullscreenButton(
                controlsAlpha: self.lastSyncedNativeControlsAlpha,
                isInteractive: self.lastSyncedNativeControlsInteractive
            )
            self.nativeControlsVisibilitySynchronizer?.rebind(force: false)
        }
        .store(in: &cancellables)
    }

    private func syncNativeFullScreenOverlays(isFullScreen: Bool) {
        guard !isTornDown else { return }
        print("[NativeFullscreen] syncOverlays isFullScreen=\(isFullScreen)")
        let playerVC = surfaceHostView.nativePlayerViewController
        let overlayView = overlayHostingController.view!
        let overlayParent: UIView = isFullScreen ? (playerVC.contentOverlayView ?? self) : self
        let isOverlayInsidePlayer = overlayParent === playerVC.contentOverlayView

        // AVKit 系统全屏通过独立的 `AVFullScreenViewController` 接管 `contentOverlayView`
        // （`-[AVFullScreenViewController attachContentView]`），若 `overlayView` 移入
        // `contentOverlayView` 时 `overlayHostingController.parent` 仍指向详情页或 `playerVC`，
        // UIKit 层级检查会直接抛出 `UIViewControllerHierarchyInconsistency` 崩溃。
        // 因此进入 `contentOverlayView` 前先解除 parent 绑定，退回内嵌宿主后再恢复 `overlayOriginalParent`。
        if isOverlayInsidePlayer, overlayHostingController.parent != nil {
            overlayHostingController.willMove(toParent: nil)
            overlayHostingController.removeFromParent()
        }
        if overlayView.superview !== overlayParent {
            overlayView.removeFromSuperview()
            overlayParent.addSubview(overlayView)
            overlayView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                overlayView.leadingAnchor.constraint(equalTo: overlayParent.leadingAnchor),
                overlayView.trailingAnchor.constraint(equalTo: overlayParent.trailingAnchor),
                overlayView.topAnchor.constraint(equalTo: overlayParent.topAnchor),
                overlayView.bottomAnchor.constraint(equalTo: overlayParent.bottomAnchor),
            ])
        }
        if !isOverlayInsidePlayer, overlayHostingController.parent !== overlayOriginalParent {
            if overlayHostingController.parent != nil {
                overlayHostingController.willMove(toParent: nil)
                overlayHostingController.removeFromParent()
            }
            if let overlayOriginalParent {
                overlayOriginalParent.addChild(overlayHostingController)
                overlayHostingController.didMove(toParent: overlayOriginalParent)
            }
        }
        if var group = nativeControlsGlassGroup {
            if group.isFullScreen != isFullScreen {
                group.applyMetrics(isFullScreen: isFullScreen)
                nativeControlsGlassGroup = group
                if let detailViewModel {
                    Self.updateNativeQualityButton(
                        group.qualityButton,
                        qualityStore: detailViewModel.playbackRenderStore.qualityControlStore,
                        detailViewModel: detailViewModel,
                        isFullScreen: isFullScreen
                    )
                }
            }
            let container = group.containerView
            if container.superview !== overlayParent {
                attachNativeControlsContainer(container, to: overlayParent)
            } else {
                overlayParent.bringSubviewToFront(container)
            }
        }
        updateNativeOptionsButtonPosition(for: playerVC)
        nativeControlsVisibilitySynchronizer?.rebind()
    }

    private func attachNativeControlsContainer(_ container: UIView, to parentView: UIView) {
        if container.superview !== parentView {
            container.removeFromSuperview()
            parentView.addSubview(container)
        }
        parentView.bringSubviewToFront(container)
        let trailingConstraint = container.trailingAnchor.constraint(equalTo: parentView.trailingAnchor, constant: -8)
        let bottomConstraint = container.bottomAnchor.constraint(equalTo: parentView.bottomAnchor, constant: -51)
        NSLayoutConstraint.activate([
            trailingConstraint,
            bottomConstraint,
        ])
        nativeOptionsTrailingConstraint = trailingConstraint
        nativeOptionsBottomConstraint = bottomConstraint
    }

    private func attachNativeInlineExitFullscreenButton(_ button: UIButton, to parentView: UIView) {
        if button.superview !== parentView {
            button.removeFromSuperview()
            parentView.addSubview(button)
        }
        parentView.bringSubviewToFront(button)
        let centerX = button.centerXAnchor.constraint(equalTo: parentView.leadingAnchor, constant: 28)
        let centerY = button.centerYAnchor.constraint(equalTo: parentView.topAnchor, constant: 27.5)
        NSLayoutConstraint.activate([
            centerX,
            centerY,
            button.widthAnchor.constraint(equalToConstant: 40),
            button.heightAnchor.constraint(equalToConstant: 38),
        ])
        nativeInlineExitCenterXConstraint = centerX
        nativeInlineExitCenterYConstraint = centerY
    }

    private var isInlineFullscreenActive: Bool {
        guard !state.playerViewModel.isNativeFullScreenPresented else { return false }
        return rotationCoordinator.layoutLandscape
            || rotationCoordinator.isLandscape
            || rotationCoordinator.isPortraitFullscreen
    }

    private var shouldOverrideInlineFullscreenButton: Bool {
        libraryStore.usesSystemNativePlaybackControlsUI
            && !state.playerViewModel.isNativeFullScreenPresented
    }

    private func handleNativeInlineFullscreenButtonTap() {
        guard !isTornDown else { return }
        if isInlineFullscreenActive {
            onExitFullscreen()
        } else {
            onRequestFullscreen()
        }
    }

    private func updateNativeInlineFullscreenButtonAppearance(
        _ button: UIButton,
        showsExitIcon: Bool
    ) {
        guard nativeInlineFullscreenButtonShowsExitIcon != showsExitIcon else { return }
        nativeInlineFullscreenButtonShowsExitIcon = showsExitIcon
        var config = button.configuration ?? UIButton.Configuration.plain()
        config.baseForegroundColor = .white
        config.image = UIImage(
            systemName: showsExitIcon
                ? "arrow.down.right.and.arrow.up.left"
                : "arrow.up.left.and.arrow.down.right",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        )
        button.configuration = config
        button.accessibilityLabel = showsExitIcon ? "退出全屏" : "全屏"
    }

    private func restoreSuppressedNativeFullscreenButtonIfNeeded() {
        guard let button = suppressedNativeFullscreenButton else { return }
        if button.alpha == 0 {
            button.alpha = 1
        }
        if !button.isUserInteractionEnabled {
            button.isUserInteractionEnabled = true
        }
        suppressedNativeFullscreenButton = nil
    }

    private func syncNativeInlineExitFullscreenButton(
        controlsAlpha: CGFloat,
        isInteractive: Bool
    ) {
        lastSyncedNativeControlsAlpha = controlsAlpha
        lastSyncedNativeControlsInteractive = isInteractive
        guard let exitButton = nativeInlineExitFullscreenButton else { return }

        guard shouldOverrideInlineFullscreenButton else {
            restoreSuppressedNativeFullscreenButtonIfNeeded()
            if !exitButton.isHidden { exitButton.isHidden = true }
            if exitButton.alpha != 0 { exitButton.alpha = 0 }
            if exitButton.isUserInteractionEnabled { exitButton.isUserInteractionEnabled = false }
            return
        }

        let playerVC = surfaceHostView.nativePlayerViewController
        let nativeFSButton = Self.findNativeFullscreenButton(in: playerVC)
        if suppressedNativeFullscreenButton !== nativeFSButton {
            restoreSuppressedNativeFullscreenButtonIfNeeded()
            suppressedNativeFullscreenButton = nativeFSButton
        }
        let nativeButtonVisibleInLayout: Bool
        if let nativeFSButton {
            let enclosingDisplayModeHidden = Self.isEnclosingDisplayModeHidden(for: nativeFSButton, stopAt: playerVC.viewIfLoaded)
            nativeButtonVisibleInLayout = !nativeFSButton.isHidden
                && !enclosingDisplayModeHidden
                && nativeFSButton.bounds.width >= 8
                && nativeFSButton.bounds.height >= 8
            if nativeFSButton.alpha != 0 {
                nativeFSButton.alpha = 0
            }
            if nativeFSButton.isUserInteractionEnabled {
                nativeFSButton.isUserInteractionEnabled = false
            }
        } else {
            nativeButtonVisibleInLayout = false
        }

        let showsExitIcon = isInlineFullscreenActive
        updateNativeInlineFullscreenButtonAppearance(exitButton, showsExitIcon: showsExitIcon)

        guard nativeButtonVisibleInLayout || showsExitIcon else {
            if !exitButton.isHidden { exitButton.isHidden = true }
            if exitButton.alpha != 0 { exitButton.alpha = 0 }
            if exitButton.isUserInteractionEnabled { exitButton.isUserInteractionEnabled = false }
            return
        }

        let targetCenter: CGPoint
        if let nativeFSButton,
           nativeFSButton.window != nil,
           !nativeFSButton.bounds.isEmpty {
            targetCenter = nativeFSButton.convert(
                CGPoint(x: nativeFSButton.bounds.midX, y: nativeFSButton.bounds.midY),
                to: self
            )
        } else {
            targetCenter = CGPoint(
                x: max(28, safeAreaInsets.left + 28),
                y: max(27.5, safeAreaInsets.top + 27.5)
            )
        }
        if let cx = nativeInlineExitCenterXConstraint, abs(cx.constant - targetCenter.x) > 0.5 {
            cx.constant = targetCenter.x
        }
        if let cy = nativeInlineExitCenterYConstraint, abs(cy.constant - targetCenter.y) > 0.5 {
            cy.constant = targetCenter.y
        }

        if exitButton.isHidden {
            exitButton.isHidden = false
        }
        if exitButton.superview === self {
            bringSubviewToFront(exitButton)
        }
        if abs(exitButton.alpha - controlsAlpha) > 0.001 {
            exitButton.alpha = controlsAlpha
        }
        if exitButton.isUserInteractionEnabled != isInteractive {
            exitButton.isUserInteractionEnabled = isInteractive
        }
    }

    private static func isEnclosingDisplayModeHidden(for view: UIView, stopAt root: UIView?) -> Bool {
        var cursor: UIView? = view.superview
        while let current = cursor, current !== root {
            if current.isHidden || current.bounds.width < 8 || current.bounds.height < 8 {
                return true
            }
            cursor = current.superview
        }
        return false
    }

    private static func findNativeFullscreenButton(in playerViewController: AVPlayerViewController) -> UIView? {
        guard let rootView = playerViewController.viewIfLoaded else { return nil }
        let overlay = playerViewController.contentOverlayView
        var queue: [UIView] = rootView.subviews.filter { $0 !== overlay }
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if view === overlay { continue }
            if view.accessibilityIdentifier == "Fullscreen Button" {
                return view
            }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }

    private static func makeNativeInlineExitFullscreenButton(
        action: @escaping () -> Void
    ) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.overrideUserInterfaceStyle = .dark
        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = .white
        config.image = UIImage(
            systemName: "arrow.down.right.and.arrow.up.left",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        )
        button.configuration = config
        button.accessibilityLabel = "退出全屏"
        button.accessibilityIdentifier = "ui.player.nativeInlineExitFullscreenButton"
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.isHidden = true
        button.alpha = 0
        button.isUserInteractionEnabled = false
        return button
    }

    private func startNativeControlsVisibilitySync() {
        nativeControlsVisibilitySynchronizer?.invalidate()
        guard let container = nativeOptionsContainerView else { return }
        let synchronizer = NativeControlsVisibilitySynchronizer(
            playerViewController: surfaceHostView.nativePlayerViewController,
            targetContainer: container,
            onLayoutSyncNeeded: { [weak self] in
                guard let self, !self.isTornDown else { return }
                let vc = self.surfaceHostView.nativePlayerViewController
                self.updateNativeOptionsButtonPosition(for: vc)
                self.syncNativeInlineExitFullscreenButton(
                    controlsAlpha: self.lastSyncedNativeControlsAlpha,
                    isInteractive: self.lastSyncedNativeControlsInteractive
                )
            },
            onVisibilitySynced: { [weak self] alpha, isInteractive in
                guard let self, !self.isTornDown else { return }
                self.syncNativeInlineExitFullscreenButton(
                    controlsAlpha: alpha,
                    isInteractive: isInteractive
                )
            }
        )
        nativeControlsVisibilitySynchronizer = synchronizer
        synchronizer.start()
    }

    private func updateNativeOptionsButtonPosition(for playerViewController: AVPlayerViewController) {
        guard let container = nativeOptionsContainerView,
              let referenceView = container.superview,
              let bottomConstraint = nativeOptionsBottomConstraint,
              let trailingConstraint = nativeOptionsTrailingConstraint else { return }
        guard referenceView.bounds.height > 80, referenceView.bounds.width > 120 else { return }

        let isFullScreenGroup = nativeControlsGlassGroup?.isFullScreen ?? false
        let platterHeight: CGFloat = isFullScreenGroup ? 44 : 38
        let progressVerticalGap: CGFloat = if isFullScreenGroup {
            10
        } else {
            referenceView.bounds.height < 230 ? 6 : 8
        }
        let targetTrailing: CGFloat
        let targetBottom: CGFloat
        if let progressFrame = Self.nativeBottomProgressBarFrame(in: playerViewController, relativeTo: referenceView) {
            let rightInset = max(8, min(referenceView.bounds.width - 120, referenceView.bounds.width - progressFrame.maxX))
            let desiredBottomY = progressFrame.minY - progressVerticalGap
            let minBottomY = referenceView.safeAreaInsets.top + 54 + platterHeight
            let clampedBottomY = max(minBottomY, min(referenceView.bounds.height - referenceView.safeAreaInsets.bottom - 8, desiredBottomY))
            targetTrailing = -rightInset
            targetBottom = -(referenceView.bounds.height - clampedBottomY)
        } else {
            let rightInset = max(8, referenceView.safeAreaInsets.right + 8)
            let bottomInset = referenceView.safeAreaInsets.bottom + 43 + progressVerticalGap
            targetTrailing = -rightInset
            targetBottom = -bottomInset
        }

        if abs(bottomConstraint.constant - targetBottom) > 1 || abs(trailingConstraint.constant - targetTrailing) > 1 {
            bottomConstraint.constant = targetBottom
            trailingConstraint.constant = targetTrailing
            referenceView.layoutIfNeeded()
        }
    }

    private static func nativeBottomProgressBarFrame(
        in playerViewController: AVPlayerViewController,
        relativeTo targetView: UIView
    ) -> CGRect? {
        guard let rootView = playerViewController.viewIfLoaded,
              targetView.bounds.height > 80,
              targetView.bounds.width > 120 else { return nil }
        let overlay = playerViewController.contentOverlayView

        var transportRoot: UIView?
        var transportFrame: CGRect?
        var queue: [UIView] = rootView.subviews.filter { $0 !== overlay }
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if view === overlay { continue }
            let className = NSStringFromClass(type(of: view))
            if className.contains("TransportControls"),
               !view.isHidden, view.window != nil, view.bounds.width > 80 {
                let frame = view.convert(view.bounds, to: targetView)
                if frame.maxY > targetView.bounds.height * 0.5, frame.width > 80 {
                    transportRoot = view
                    transportFrame = frame
                    break
                }
            }
            queue.append(contentsOf: view.subviews)
        }

        let searchRoot = transportRoot ?? rootView
        var bottomRowFrame: CGRect?
        var timelineFrame: CGRect?
        var auxiliaryFrame: CGRect?
        var sliderFrame: CGRect?
        var titlebarTopY: CGFloat?

        var transportQueue: [UIView] = [searchRoot]
        while !transportQueue.isEmpty {
            let view = transportQueue.removeFirst()
            if view === overlay { continue }
            let className = NSStringFromClass(type(of: view))
            if !view.isHidden, view.alpha > 0.01, view.window != nil, !view.bounds.isEmpty {
                let frame = view.convert(view.bounds, to: targetView)
                if frame.minY > targetView.bounds.height * 0.45 {
                    if className.contains("TimelineView"), frame.width > 60, frame.height >= 20 {
                        timelineFrame = timelineFrame.map { $0.union(frame) } ?? frame
                    } else if className.contains("AuxiliaryControlsView"), frame.width >= 20, frame.height >= 20 {
                        auxiliaryFrame = auxiliaryFrame.map { $0.union(frame) } ?? frame
                    } else if view.superview === transportRoot,
                              className.contains("GlassBacked"),
                              frame.width > 80, frame.height >= 24, frame.height <= 64 {
                        bottomRowFrame = bottomRowFrame.map { $0.union(frame) } ?? frame
                    } else if className.contains("Slider"), frame.width > 60, frame.height >= 4 {
                        sliderFrame = sliderFrame.map { $0.union(frame) } ?? frame
                    } else if className.contains("TitlebarView"), frame.height >= 10 {
                        titlebarTopY = min(titlebarTopY ?? frame.minY, frame.minY)
                    }
                }
            }
            transportQueue.append(contentsOf: view.subviews)
        }

        var combinedFrame: CGRect?
        if let bottomRowFrame {
            combinedFrame = auxiliaryFrame.map { bottomRowFrame.union($0) } ?? bottomRowFrame
        } else if let timelineFrame {
            combinedFrame = auxiliaryFrame.map { timelineFrame.union($0) } ?? timelineFrame
        } else if let sliderFrame {
            combinedFrame = sliderFrame.insetBy(dx: -11, dy: -15)
        }

        guard var result = combinedFrame else { return nil }
        if let transportFrame {
            let clampedMinX = max(result.minX, transportFrame.minX)
            let clampedMaxX = min(result.maxX, transportFrame.maxX)
            if clampedMaxX > clampedMinX {
                result = CGRect(
                    x: clampedMinX,
                    y: result.minY,
                    width: clampedMaxX - clampedMinX,
                    height: result.height
                )
            }
        }
        if let titlebarTopY, titlebarTopY < result.minY {
            result = result.union(CGRect(x: result.minX, y: titlebarTopY, width: result.width, height: 1))
        }
        return result
    }

    private static func makeNativeControlsGlassGroup() -> NativeControlsGlassGroup {
        let containerEffect = UIGlassContainerEffect()
        containerEffect.spacing = 8
        let containerView = UIVisualEffectView(effect: containerEffect)
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.overrideUserInterfaceStyle = .dark
        containerView.accessibilityIdentifier = "ui.player.nativeControlsGroup"

        let qualityButton = makeNativeQualityButton()
        let qualityGlassView = wrapInNativeMediaGlass(qualityButton)

        let optionsButton = makeNativeGlassControl(
            systemImage: "slider.horizontal.3",
            accessibilityLabel: "播放设置与清晰度",
            accessibilityIdentifier: "ui.player.nativeOptionsButton"
        )
        optionsButton.showsMenuAsPrimaryAction = true
        let optionsGlassView = wrapInNativeMediaGlass(optionsButton)

        let stackView = UIStackView(arrangedSubviews: [qualityGlassView, optionsGlassView])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 8
        containerView.contentView.addSubview(stackView)

        let qualityHeightConstraint = qualityGlassView.heightAnchor.constraint(equalToConstant: 38)
        let optionsWidthConstraint = optionsGlassView.widthAnchor.constraint(equalToConstant: 38)
        let optionsHeightConstraint = optionsGlassView.heightAnchor.constraint(equalToConstant: 38)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: containerView.contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: containerView.contentView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: containerView.contentView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: containerView.contentView.bottomAnchor),
            qualityHeightConstraint,
            qualityGlassView.widthAnchor.constraint(greaterThanOrEqualToConstant: 56),
            qualityGlassView.widthAnchor.constraint(lessThanOrEqualToConstant: 108),
            optionsWidthConstraint,
            optionsHeightConstraint,
        ])

        return NativeControlsGlassGroup(
            containerView: containerView,
            containerEffect: containerEffect,
            stackView: stackView,
            qualityButton: qualityButton,
            optionsButton: optionsButton,
            qualityHeightConstraint: qualityHeightConstraint,
            optionsWidthConstraint: optionsWidthConstraint,
            optionsHeightConstraint: optionsHeightConstraint
        )
    }

    private static func wrapInNativeMediaGlass(_ child: UIView) -> UIVisualEffectView {
        let glassEffect = UIGlassEffect(style: .regular)
        glassEffect.isInteractive = true
        glassEffect.tintColor = UIColor.black.withAlphaComponent(0.26)
        let glassView = UIVisualEffectView(effect: glassEffect)
        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.overrideUserInterfaceStyle = .dark
        glassView.cornerConfiguration = .capsule()
        child.translatesAutoresizingMaskIntoConstraints = false
        glassView.contentView.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor),
            child.topAnchor.constraint(equalTo: glassView.contentView.topAnchor),
            child.bottomAnchor.constraint(equalTo: glassView.contentView.bottomAnchor),
        ])
        return glassView
    }

    private static func makeNativeQualityButton() -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.overrideUserInterfaceStyle = .dark
        button.configuration = makeNativeQualityButtonConfiguration(
            title: "清晰度",
            foregroundColor: UIColor.white.withAlphaComponent(0.55),
            isFullScreen: false
        )
        button.showsMenuAsPrimaryAction = true
        button.isEnabled = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.accessibilityIdentifier = "ui.player.nativeQualityButton"
        button.accessibilityLabel = "清晰度"
        return button
    }

    private static func makeNativeQualityButtonConfiguration(
        title: String,
        foregroundColor: UIColor,
        isFullScreen: Bool
    ) -> UIButton.Configuration {
        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = foregroundColor
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 0,
            leading: isFullScreen ? 14 : 12,
            bottom: 0,
            trailing: isFullScreen ? 14 : 12
        )
        config.titleLineBreakMode = .byTruncatingTail
        var titleAttributes = AttributeContainer()
        titleAttributes.font = UIFont.monospacedDigitSystemFont(
            ofSize: isFullScreen ? 14 : 13,
            weight: .semibold
        )
        config.attributedTitle = AttributedString(title, attributes: titleAttributes)
        return config
    }

    private static func makeNativeGlassControl(
        systemImage: String,
        accessibilityLabel: String,
        accessibilityIdentifier: String
    ) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.overrideUserInterfaceStyle = .dark
        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = .white
        config.image = UIImage(
            systemName: systemImage,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        )
        button.configuration = config
        button.accessibilityLabel = accessibilityLabel
        button.accessibilityIdentifier = accessibilityIdentifier
        return button
    }

    private static func updateNativeQualityButton(
        _ button: UIButton,
        qualityStore: VideoDetailQualityControlRenderStore,
        detailViewModel: VideoDetailViewModel,
        isFullScreen: Bool
    ) {
        let rawTitle = qualityStore.isSwitchingPlayQuality
            ? qualityStore.qualityAccessoryButtonTitle
            : qualityStore.qualityInlineButtonTitle
        let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = trimmedTitle.isEmpty ? "清晰度" : trimmedTitle
        let foregroundColor: UIColor = if !qualityStore.hasQualityMenu {
            UIColor.white.withAlphaComponent(0.55)
        } else if qualityStore.isSwitchingPlayQuality {
            UIColor.white.withAlphaComponent(0.82)
        } else {
            .white
        }
        button.configuration = makeNativeQualityButtonConfiguration(
            title: displayTitle,
            foregroundColor: foregroundColor,
            isFullScreen: isFullScreen
        )

        let actions = makeQualityMenuActions(
            qualityStore: qualityStore,
            detailViewModel: detailViewModel,
            identifierPrefix: "native.quality.button"
        )
        button.menu = actions.isEmpty ? nil : UIMenu(title: "清晰度", children: actions)
        button.isEnabled = !actions.isEmpty
        button.accessibilityLabel = "清晰度，\(displayTitle)"
        button.accessibilityValue = qualityStore.qualityAccessoryButtonTitle
    }

    private struct NativeControlsGlassGroup {
        let containerView: UIVisualEffectView
        let containerEffect: UIGlassContainerEffect
        let stackView: UIStackView
        let qualityButton: UIButton
        let optionsButton: UIButton
        let qualityHeightConstraint: NSLayoutConstraint
        let optionsWidthConstraint: NSLayoutConstraint
        let optionsHeightConstraint: NSLayoutConstraint
        var isFullScreen = false

        mutating func applyMetrics(isFullScreen: Bool) {
            self.isFullScreen = isFullScreen
            let platterHeight: CGFloat = isFullScreen ? 44 : 38
            let spacing: CGFloat = isFullScreen ? 10 : 8
            containerEffect.spacing = spacing
            stackView.spacing = spacing
            qualityHeightConstraint.constant = platterHeight
            optionsWidthConstraint.constant = platterHeight
            optionsHeightConstraint.constant = platterHeight
            var optConfig = optionsButton.configuration ?? UIButton.Configuration.plain()
            optConfig.image = UIImage(
                systemName: "slider.horizontal.3",
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: isFullScreen ? 17 : 15,
                    weight: .medium
                )
            )
            optionsButton.configuration = optConfig
        }
    }

    @MainActor
    private final class NativeControlsVisibilitySynchronizer: NSObject {
        private final class DisplayLinkProxy: NSObject {
            private let onTick: () -> Void

            init(onTick: @escaping () -> Void) {
                self.onTick = onTick
            }

            @objc func handleDisplayLink() {
                MainActor.assumeIsolated {
                    self.onTick()
                }
            }
        }

        private struct WeakView {
            weak var view: UIView?
        }

        private weak var playerViewController: AVPlayerViewController?
        private weak var targetContainer: UIView?
        private let onLayoutSyncNeeded: () -> Void
        private let onVisibilitySynced: ((CGFloat, Bool) -> Void)?
        private var controlsRoot: WeakView?
        private var animatedControls: [WeakView] = []
        private var observations: [NSKeyValueObservation] = []
        private var displayLink: CADisplayLink?
        private var isInvalidated = false
        private var settleFramesRemaining = 0

        init(
            playerViewController: AVPlayerViewController,
            targetContainer: UIView,
            onLayoutSyncNeeded: @escaping () -> Void,
            onVisibilitySynced: ((CGFloat, Bool) -> Void)? = nil
        ) {
            self.playerViewController = playerViewController
            self.targetContainer = targetContainer
            self.onLayoutSyncNeeded = onLayoutSyncNeeded
            self.onVisibilitySynced = onVisibilitySynced
            super.init()
        }

        func start() {
            guard !isInvalidated else { return }
            if let nativeVC = playerViewController as? NativeFullScreenPlayerViewController {
                nativeVC.onPlaybackControlsSuppressionChanged = { [weak self] isSuppressed in
                    guard let self, !self.isInvalidated else { return }
                    if isSuppressed {
                        self.syncNow()
                    } else {
                        self.rebind(force: true)
                    }
                }
            }
            ensureDisplayLink()
            rebind(force: true)
        }

        func rebind(force: Bool = true) {
            guard !isInvalidated else { return }
            let needsRebind = force
                || controlsRoot?.view?.superview == nil
                || animatedControls.isEmpty
                || animatedControls.contains(where: { $0.view?.superview == nil })
            if needsRebind {
                attachObservers()
            }
            wakeDisplayLink(settleFrames: 3)
            syncNow()
        }

        func invalidate() {
            guard !isInvalidated else { return }
            isInvalidated = true
            if let nativeVC = playerViewController as? NativeFullScreenPlayerViewController {
                nativeVC.onPlaybackControlsSuppressionChanged = nil
            }
            observations.forEach { $0.invalidate() }
            observations.removeAll()
            controlsRoot = nil
            animatedControls.removeAll()
            displayLink?.invalidate()
            displayLink = nil
        }

        private func ensureDisplayLink() {
            guard displayLink == nil else { return }
            let proxy = DisplayLinkProxy { [weak self] in
                self?.handleDisplayLinkTick()
            }
            let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.handleDisplayLink))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        private func wakeDisplayLink(settleFrames: Int = 2) {
            guard !isInvalidated else { return }
            settleFramesRemaining = max(settleFramesRemaining, settleFrames)
            ensureDisplayLink()
            displayLink?.isPaused = false
        }

        private func attachObservers() {
            observations.forEach { $0.invalidate() }
            observations.removeAll()
            controlsRoot = nil
            animatedControls.removeAll()

            guard let playerViewController,
                  let rootView = playerViewController.viewIfLoaded else { return }
            let showsControlsObs = playerViewController.observe(\.showsPlaybackControls, options: [.new]) { [weak self] _, _ in
                Self.dispatchMainSync { self?.rebind(force: true) }
            }
            observations.append(showsControlsObs)
            let overlay = playerViewController.contentOverlayView
            var foundRoot: UIView?
            var foundAnimated: [UIView] = []

            var queue: [UIView] = rootView.subviews.filter { $0 !== overlay }
            while !queue.isEmpty {
                let view = queue.removeFirst()
                if view === overlay { continue }
                let className = NSStringFromClass(type(of: view))
                if foundRoot == nil,
                   className.contains("MobileGlassControls") || className.contains("ChromelessControls") {
                    foundRoot = view
                } else if className.contains("DisplayModeControls")
                    || className.contains("TimelineView")
                    || className.contains("AuxiliaryControls")
                    || className.contains("PlaybackControls") {
                    foundAnimated.append(view)
                }
                if view.accessibilityIdentifier == "Fullscreen Button" {
                    let fsAlphaObs = view.observe(\.alpha, options: [.new]) { [weak self] _, _ in
                        Self.dispatchMainSync { self?.onLayoutSyncNeeded() }
                    }
                    observations.append(fsAlphaObs)
                }
                queue.append(contentsOf: view.subviews)
            }

            if let foundRoot {
                controlsRoot = WeakView(view: foundRoot)
                let hiddenObs = foundRoot.observe(\.isHidden, options: [.new]) { [weak self] _, _ in
                    Self.dispatchMainSync { self?.handleVisibilityPropertyChanged() }
                }
                observations.append(hiddenObs)
            }

            for control in foundAnimated {
                animatedControls.append(WeakView(view: control))
                let alphaObs = control.observe(\.alpha, options: [.new]) { [weak self] _, _ in
                    Self.dispatchMainSync { self?.handleVisibilityPropertyChanged() }
                }
                let hiddenObs = control.observe(\.isHidden, options: [.new]) { [weak self] _, _ in
                    Self.dispatchMainSync { self?.handleVisibilityPropertyChanged() }
                }
                observations.append(alphaObs)
                observations.append(hiddenObs)
            }
        }

        private static func dispatchMainSync(_ work: @escaping @MainActor () -> Void) {
            if Thread.isMainThread {
                MainActor.assumeIsolated { work() }
            } else {
                DispatchQueue.main.async { work() }
            }
        }

        private func handleVisibilityPropertyChanged() {
            wakeDisplayLink(settleFrames: 3)
            syncNow()
        }

        private func handleDisplayLinkTick() {
            rebind(force: false)
        }

        func syncNow() {
            guard !isInvalidated, let container = targetContainer else { return }
            let isSuppressedByGesture = (playerViewController as? NativeFullScreenPlayerViewController)?.isPlaybackControlsSuppressedBySurfaceGesture == true
            if playerViewController?.showsPlaybackControls == false || isSuppressedByGesture {
                if container.alpha != 0 { container.alpha = 0 }
                if container.isUserInteractionEnabled { container.isUserInteractionEnabled = false }
                onVisibilitySynced?(0, false)
                displayLink?.isPaused = true
                return
            }
            let activeAnimated = animatedControls.compactMap(\.view)
            let rootView = controlsRoot?.view

            if rootView == nil && activeAnimated.isEmpty {
                if container.alpha != 1 { container.alpha = 1 }
                if !container.isUserInteractionEnabled { container.isUserInteractionEnabled = true }
                onVisibilitySynced?(1, true)
                return
            }

            let rootHidden = rootView?.isHidden ?? false
            let inWindowControls = activeAnimated.filter { !$0.isHidden && $0.window != nil }
            let targetVisible = !rootHidden && inWindowControls.contains { $0.alpha > 0.05 }
            let isAnimating = inWindowControls.contains { !($0.layer.animationKeys()?.isEmpty ?? true) }

            let liveAlpha: CGFloat
            if rootHidden {
                liveAlpha = 0
            } else if isAnimating {
                let presentationOpacities = inWindowControls.compactMap { control -> CGFloat? in
                    guard let pres = control.layer.presentation() else { return nil }
                    return CGFloat(pres.opacity)
                }
                liveAlpha = presentationOpacities.max() ?? container.alpha
            } else {
                liveAlpha = targetVisible ? 1 : 0
            }

            let clampedAlpha = max(0, min(1, liveAlpha))
            if abs(container.alpha - clampedAlpha) > 0.001 {
                container.alpha = clampedAlpha
            }
            let interactive = targetVisible && !rootHidden
            if container.isUserInteractionEnabled != interactive {
                container.isUserInteractionEnabled = interactive
            }
            onVisibilitySynced?(clampedAlpha, interactive)

            if interactive || isAnimating || clampedAlpha > 0.01 {
                onLayoutSyncNeeded()
            }

            let targetOpacity: CGFloat = targetVisible ? 1 : 0
            if isAnimating || abs(clampedAlpha - targetOpacity) > 0.002 || settleFramesRemaining > 0 {
                if settleFramesRemaining > 0 {
                    settleFramesRemaining -= 1
                }
                displayLink?.isPaused = false
            } else {
                displayLink?.isPaused = true
            }
        }
    }

    private static func makeQualityMenuActions(
        qualityStore: VideoDetailQualityControlRenderStore,
        detailViewModel: VideoDetailViewModel,
        identifierPrefix: String
    ) -> [UIAction] {
        qualityStore.qualityMenuItems.map { item in
            UIAction(
                title: item.title,
                image: UIImage(systemName: item.systemImage),
                identifier: UIAction.Identifier("\(identifierPrefix).\(item.variant.quality)"),
                attributes: item.isDisabled ? [.disabled] : [],
                state: item.systemImage == "checkmark" ? .on : .off
            ) { [weak detailViewModel] _ in
                detailViewModel?.selectPlayVariant(item.variant)
            }
        }
    }

    private static func makeNativeOptionsMenu(
        detailViewModel: VideoDetailViewModel,
        onToggleDanmaku: @escaping () -> Void,
        onShowDanmakuSettings: @escaping () -> Void,
        onShowMoreControls: @escaping (@escaping () -> Void) -> Void
    ) -> UIMenu {
        var items: [UIMenuElement] = []

        let qualityStore = detailViewModel.playbackRenderStore.qualityControlStore
        let qualityActions = makeQualityMenuActions(
            qualityStore: qualityStore,
            detailViewModel: detailViewModel,
            identifierPrefix: "native.quality"
        )
        if !qualityActions.isEmpty {
            items.append(
                UIMenu(
                    title: "清晰度",
                    image: UIImage(systemName: "sparkles.tv"),
                    children: qualityActions
                )
            )
        }

        let subtitleStore = detailViewModel.subtitleRenderStore
        if !subtitleStore.tracks.isEmpty {
            var subtitleActions: [UIAction] = subtitleStore.tracks.map { track in
                UIAction(
                    title: track.isAI ? "\(track.lanDoc)（AI）" : track.lanDoc,
                    state: subtitleStore.selectedLan == track.lan ? .on : .off
                ) { [weak detailViewModel] _ in
                    Task { @MainActor in
                        await detailViewModel?.selectSubtitleTrack(lan: track.lan)
                    }
                }
            }
            subtitleActions.append(
                UIAction(
                    title: "关闭字幕",
                    state: subtitleStore.selectedLan == nil ? .on : .off
                ) { [weak detailViewModel] _ in
                    Task { @MainActor in
                        await detailViewModel?.selectSubtitleTrack(lan: nil)
                    }
                }
            )
            items.append(
                UIMenu(
                    title: "字幕",
                    image: UIImage(systemName: "captions.bubble"),
                    children: subtitleActions
                )
            )
        }

        let isDanmakuEnabled = detailViewModel.danmakuRenderStore.isDanmakuEnabled
        let danmakuMenu = UIMenu(
            title: "弹幕",
            image: UIImage(systemName: isDanmakuEnabled ? "captions.bubble.fill" : "captions.bubble"),
            children: [
                UIAction(
                    title: isDanmakuEnabled ? "关闭弹幕" : "开启弹幕",
                    image: UIImage(systemName: isDanmakuEnabled ? "eye.slash" : "eye")
                ) { _ in
                    onToggleDanmaku()
                },
                UIAction(
                    title: "弹幕设置",
                    image: UIImage(systemName: "slider.horizontal.3")
                ) { _ in
                    onShowDanmakuSettings()
                },
            ]
        )
        items.append(danmakuMenu)

        items.append(
            UIAction(
                title: "更多播放设置",
                image: UIImage(systemName: "gearshape")
            ) { _ in
                onShowMoreControls {}
            }
        )

        return UIMenu(title: "", children: items)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        let didReconcileFullscreenFrame = reconcileFullscreenBoundsIfNeeded()
        super.layoutSubviews()
        if didReconcileFullscreenFrame, canMutateBoundPlayer {
            surfaceHostView.refreshLayoutImmediately()
        }
        if nativeOptionsContainerView != nil {
            updateNativeOptionsButtonPosition(for: surfaceHostView.nativePlayerViewController)
            nativeControlsVisibilitySynchronizer?.rebind(force: false)
        }
#if DEBUG
        guard bounds != lastReportedDiagnosticOverlayBounds else { return }
        guard overlayHostingController.view.bounds.size == bounds.size else { return }
        lastReportedDiagnosticOverlayBounds = bounds
        state.playerViewModel.onVideoDetailPlaybackDiagnosticLayoutEvent?(.overlayGeometry)
#endif
    }

    /// 旋转或手动全屏结束后校准宿主边界：除窗口宽高精确互换的残留外，还覆盖横屏全屏态下的
    /// 任意非全窗尺寸或 origin 偏移（例如手动点击全屏前状态栏/底栏隐藏触发的异步竖屏布局覆盖）。
    /// 放在 `super.layoutSubviews()` 之前执行，避免子视图和播放层先按旧尺寸排版一次。
    @discardableResult
    private func reconcileFullscreenBoundsIfNeeded() -> Bool {
        guard !rotationCoordinator.isTransitioning else { return false }
        guard rotationCoordinator.isLandscape || rotationCoordinator.isPortraitFullscreen else {
            return false
        }
        guard let window else { return false }
        let windowSize = window.bounds.size
        guard windowSize.width > 1, windowSize.height > 1 else { return false }
        let currentSize = bounds.size
        let isSwapped = abs(currentSize.width - windowSize.height) <= 1
            && abs(currentSize.height - windowSize.width) <= 1
            && currentSize != windowSize
        let expectsFullWindow = rotationCoordinator.isPortraitFullscreen
            || (rotationCoordinator.isLandscape && windowSize.width > windowSize.height)
        guard isSwapped || expectsFullWindow else { return false }
        guard let superview else { return false }
        let target = superview.convert(window.bounds, from: window)
        let hasFrameMismatch = abs(frame.minX - target.minX) > 0.5
            || abs(frame.minY - target.minY) > 0.5
            || abs(frame.width - target.width) > 0.5
            || abs(frame.height - target.height) > 0.5
        let hasPendingLayerAnimations = !(layer.animationKeys()?.isEmpty ?? true)
        guard hasFrameMismatch || hasPendingLayerAnimations else { return false }
        UIView.performWithoutAnimation {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            removeLayerAnimationsRecursively()
            frame = target
            CATransaction.commit()
        }
        return true
    }

    func attach(to parent: UIViewController) {
        guard canMutateBoundPlayer else { return }
        guard overlayHostingController.parent == nil else { return }
        overlayOriginalParent = parent
        parent.addChild(overlayHostingController)
        overlayHostingController.didMove(toParent: parent)
    }

    func prepareForMiniPlayerExitIfDismantled() {
        guard !isTornDown, let detailViewModel else { return }
        guard !detailViewModel.isAwaitingRelatedVideoReturnPlayback else { return }
        let isRemovedFromStack = detailViewModel.isRouteRemovedFromNavigationStack?() ?? true
        guard isRemovedFromStack else { return }
        detailViewModel.markExitingVideoDetailRoute()
        let preferredWindow = window
        let frameInWindow = bounds.width > 16 ? convert(bounds, to: preferredWindow) : nil
        _ = detailViewModel.handoffToSystemMiniPlayerIfEligible(
            preferredFrameInWindow: frameInWindow,
            preferredWindow: preferredWindow
        )
    }

    func tearDown() {
        guard !isTornDown else { return }
        isTornDown = true
        let playerVC = surfaceHostView.nativePlayerViewController
        if overlayHostingController.parent != nil {
            overlayHostingController.willMove(toParent: nil)
            overlayHostingController.removeFromParent()
        }
        if playerVC.presentingViewController != nil {
            playerVC.dismiss(animated: false)
        }
        restoreSuppressedNativeFullscreenButtonIfNeeded()
        nativeInlineExitFullscreenButton?.removeFromSuperview()
        nativeInlineExitFullscreenButton = nil
        nativeControlsVisibilitySynchronizer?.invalidate()
        nativeControlsVisibilitySynchronizer = nil
        nativeFullScreenPresentationCancellable = nil
        cancelRotationChromePrewarm()
        cancellables.removeAll()
        playbackTransitionImageView.image = nil
        playbackTransitionImageView.isHidden = true
        playbackTransitionImageView.removeFromSuperview()
        surfaceHostView.tearDown()
        surfaceHostView.removeFromSuperview()
        overlayHostingController.willMove(toParent: nil)
        overlayHostingController.view.removeFromSuperview()
        overlayHostingController.removeFromParent()
    }

    func requestPlaybackControlsHideForRotation() {
        state.requestPlaybackControlsHideForRotation()
    }

#if DEBUG
    func revealPlaybackControlsForTesting() {
        state.requestPlaybackControlsRevealForTesting()
    }
#endif

    func markRotationChromePrewarmed() {
        isRotationChromePrewarmed = true
    }

    /// 系统旋转期间退化成 bare surface，但始终保留弹幕层以避免重建和闪烁。
    /// 实验路径可保留不可见的控件树，避免旋转结束时集中重建 SwiftUI 叠层。
    func setBareSurfaceTransitionActive(_ active: Bool, retainsChromeTree: Bool = false) {
        guard state.isBareSurfaceTransitionActive != active
            || state.retainsChromeDuringBareSurfaceTransition != retainsChromeTree
        else { return }
        cancelRotationChromePrewarm()
        overlayState.setBareSurfaceTransitionActive(active)
        experimentState.setBareSurfaceTransitionActive(active)
        state.setBareSurfaceTransitionActive(active, retainsChromeTree: retainsChromeTree)
        UIView.performWithoutAnimation {
            overlayHostingController.view.isHidden = false
            let usesCustomOverlay = libraryStore.usesCustomPlaybackControlsOverlay
            overlayHostingController.view.isUserInteractionEnabled = !active && usesCustomOverlay
            surfaceHostView.isUserInteractionEnabled = !active && !usesCustomOverlay
        }
    }

    func refreshLayoutImmediately() {
        guard canMutateBoundPlayer else { return }
        UIView.performWithoutAnimation {
            setNeedsLayout()
            layoutIfNeeded()
            surfaceHostView.refreshLayoutImmediately()
            if !state.isBareSurfaceTransitionActive {
                overlayHostingController.view.setNeedsLayout()
                overlayHostingController.view.layoutIfNeeded()
            }
        }
    }

    func prewarmRotationChrome() {
        guard !isRotationChromePrewarming,
              !state.isBareSurfaceTransitionActive
        else { return }
        isRotationChromePrewarmed = false
        isRotationChromePrewarming = true
        rotationChromePrewarmGeneration &+= 1
        let generation = rotationChromePrewarmGeneration
        let prewarmLandscape = !rotationCoordinator.isLandscape

        UIView.performWithoutAnimation {
            state.setBareSurfaceTransitionActive(true, retainsChromeTree: true)
            rotationCoordinator.beginChromePrewarm(for: prewarmLandscape)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.isRotationChromePrewarming,
                  self.rotationChromePrewarmGeneration == generation
            else { return }
            self.layoutRotationChromePrewarm()
            UIView.performWithoutAnimation {
                self.rotationCoordinator.endChromePrewarm()
            }
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.isRotationChromePrewarming,
                      self.rotationChromePrewarmGeneration == generation
                else { return }
                self.layoutRotationChromePrewarm()
                UIView.performWithoutAnimation {
                    self.state.setBareSurfaceTransitionActive(false, retainsChromeTree: true)
                }
                self.isRotationChromePrewarming = false
                self.isRotationChromePrewarmed = true
            }
        }
    }

    func cancelRotationChromePrewarm() {
        guard isRotationChromePrewarming else { return }
        rotationChromePrewarmGeneration &+= 1
        isRotationChromePrewarming = false
        UIView.performWithoutAnimation {
            rotationCoordinator.endChromePrewarm()
            state.setBareSurfaceTransitionActive(false, retainsChromeTree: true)
        }
    }

    /// 清晰度切换等场景会替换 player 实例，UIKit 直连路径会原位重绑叠层。
    func setPlayerViewModel(_ playerViewModel: PlayerStateViewModel) {
        guard canMutateBoundPlayer else { return }
        guard state.playerViewModel !== playerViewModel else { return }
        state.playerViewModel = playerViewModel
        bindNativeFullScreenPresentation(for: playerViewModel)
        playerViewModel.setBackgroundPlaybackEnabled(
            libraryStore.backgroundPlaybackEnabled
        )
        surfaceHostView.setPlayerViewModel(playerViewModel)
        surfaceHostView.setPictureInPictureEnabled(
            libraryStore.allowsPictureInPictureController
                && !playerViewModel.isAudioOnlyPlayback,
            allowsAutomaticInline: libraryStore.pictureInPictureEnabled
        )
        applyNativePlaybackControlsSettings()
    }

    private func applyNativePlaybackControlsSettings() {
        guard canMutateBoundPlayer else { return }
        let usesNativeSurface = libraryStore.usesNativePlaybackSurface
        let usesSystemControlsUI = libraryStore.usesSystemNativePlaybackControlsUI
        let usesCustomOverlay = libraryStore.usesCustomPlaybackControlsOverlay
        let showsSpeeds = true
        let allowsPiP: Bool? = nil
        surfaceHostView.setNativePlaybackControlsOptions(
            prefersNativePlaybackSurface: usesNativeSurface,
            showsPlaybackControls: usesSystemControlsUI,
            showsPlaybackSpeeds: showsSpeeds,
            enablesNativeSurfaceGestures: usesNativeSurface && !usesCustomOverlay,
            allowsPictureInPicturePlayback: allowsPiP
        )
        let bareTransitionActive = state.isBareSurfaceTransitionActive
        overlayHostingController.view.isUserInteractionEnabled =
            !bareTransitionActive && usesCustomOverlay
        surfaceHostView.isUserInteractionEnabled =
            !bareTransitionActive && !usesCustomOverlay

        if usesSystemControlsUI {
            installNativeSystemControlsAccessoriesIfNeeded()
        }
        if didInstallNativeSystemControlsAccessories {
            nativeOptionsContainerView?.isHidden = !usesSystemControlsUI
            if !usesSystemControlsUI {
                nativeOptionsContainerView?.isUserInteractionEnabled = false
                syncNativeInlineExitFullscreenButton(controlsAlpha: 0, isInteractive: false)
            }
            let playerVC = surfaceHostView.nativePlayerViewController
            playerVC.viewIfLoaded?.setNeedsLayout()
            playerVC.viewIfLoaded?.layoutIfNeeded()
            updateNativeOptionsButtonPosition(for: playerVC)
            nativeControlsVisibilitySynchronizer?.rebind()
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isTornDown else { return }
                let vc = self.surfaceHostView.nativePlayerViewController
                vc.viewIfLoaded?.layoutIfNeeded()
                self.updateNativeOptionsButtonPosition(for: vc)
                self.nativeControlsVisibilitySynchronizer?.rebind()
            }
        }
    }

    func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        guard canMutateBoundPlayer else { return }
        videoGravity = gravity
        updatePlaybackTransitionContentMode()
        surfaceHostView.setVideoGravity(gravity)
    }

    private func updatePlaybackTransition(snapshot: PlaybackTransitionSnapshot?, opacity: Double) {
        guard !isTornDown else { return }
        // No independent timer or animation: first-frame/timeout/navigation cleanup
        // remains owned by VideoDetailViewModel's existing transition lifecycle.
        UIView.performWithoutAnimation {
            guard let snapshot, opacity > 0 else {
                playbackTransitionImageView.isHidden = true
                playbackTransitionImageView.image = nil
                return
            }
            playbackTransitionImageView.image = snapshot.image
            playbackTransitionIsVideoFrame = snapshot.isVideoFrame
            updatePlaybackTransitionContentMode()
            playbackTransitionImageView.alpha = CGFloat(min(opacity, 1))
            playbackTransitionImageView.isHidden = false
        }
    }

    private func updatePlaybackTransitionContentMode() {
        if !playbackTransitionIsVideoFrame || videoGravity == .resizeAspect {
            playbackTransitionImageView.contentMode = .scaleAspectFit
        } else if videoGravity == .resizeAspectFill {
            playbackTransitionImageView.contentMode = .scaleAspectFill
        } else {
            playbackTransitionImageView.contentMode = .scaleToFill
        }
    }

    func setDanmakuCanvasSize(_ size: CGSize?) {
        guard state.danmakuCanvasSize != size else { return }
        state.danmakuCanvasSize = size
#if DEBUG
        state.playerViewModel.onVideoDetailPlaybackDiagnosticLayoutEvent?(.danmakuCanvasConfigured)
#endif
    }

    func setVideoAspectRatio(_ aspectRatio: CGFloat) {
        guard aspectRatio > 0.1, abs(state.videoAspectRatio - aspectRatio) > 0.001 else { return }
        state.videoAspectRatio = aspectRatio
    }

    func setCollapsedChromeActive(_ active: Bool) {
        guard state.isCollapsedChromeActive != active else { return }
        state.isCollapsedChromeActive = active
    }

    private func layoutRotationChromePrewarm() {
        overlayHostingController.view.setNeedsLayout()
        overlayHostingController.view.layoutIfNeeded()
    }

}

extension VideoDetailShellSurfaceHost: PlayerSurfaceHosting {
    var surfaceView: UIView { self }

    func setLandscape(_: Bool) {}

    func setPortraitFullscreen(_: Bool) {}
}

private struct VideoDetailShellOverlaySnapshot: Equatable {
    var historyVideo: VideoItem
    var recordsPlaybackHistory = true
    var historyCID: Int?
    var historyDuration: TimeInterval?
    var isDanmakuEnabled = true
    var isSwitchingPlayQuality = false
    var playbackContentMode: PlayerPlaybackContentMode = .video
    var isSwitchingVideoListenMode = false

    init(
        detail: VideoItem,
        recordsPlaybackHistory: Bool,
        selectedCID: Int?,
        isDanmakuEnabled: Bool,
        isSwitchingPlayQuality: Bool,
        playbackContentMode: PlayerPlaybackContentMode,
        isSwitchingVideoListenMode: Bool
    ) {
        self.historyVideo = detail
        self.recordsPlaybackHistory = recordsPlaybackHistory
        self.historyCID = recordsPlaybackHistory ? (selectedCID ?? detail.cid) : nil
        self.historyDuration = detail.duration.map(TimeInterval.init)
        self.isDanmakuEnabled = isDanmakuEnabled
        self.isSwitchingPlayQuality = isSwitchingPlayQuality
        self.playbackContentMode = playbackContentMode
        self.isSwitchingVideoListenMode = isSwitchingVideoListenMode
    }
}

@MainActor
private final class VideoDetailShellOverlayState: ObservableObject {
    @Published private(set) var snapshot: VideoDetailShellOverlaySnapshot
    private var isBareSurfaceTransitionActive = false
    private var pendingSnapshot: VideoDetailShellOverlaySnapshot?
    private weak var experimentState: VideoDetailPerformanceExperimentState?
    private var cancellables = Set<AnyCancellable>()

    init(
        detailViewModel: VideoDetailViewModel,
        experimentState: VideoDetailPerformanceExperimentState
    ) {
        self.experimentState = experimentState
        self.snapshot = VideoDetailShellOverlaySnapshot(
            detail: detailViewModel.detail,
            recordsPlaybackHistory: detailViewModel.playbackOptions.recordsPlaybackHistory,
            selectedCID: detailViewModel.selectedCID,
            isDanmakuEnabled: detailViewModel.isDanmakuEnabled,
            isSwitchingPlayQuality: detailViewModel.isSwitchingPlayQuality,
            playbackContentMode: detailViewModel.playbackContentMode,
            isSwitchingVideoListenMode: detailViewModel.isSwitchingVideoListenMode
        )

        let playbackSnapshotPublisher = Publishers.CombineLatest4(
            detailViewModel.$detail,
            detailViewModel.$selectedCID,
            detailViewModel.$isDanmakuEnabled,
            detailViewModel.$isSwitchingPlayQuality
        )
        let listenModePublisher = detailViewModel.$playbackContentMode
            .combineLatest(detailViewModel.$isSwitchingVideoListenMode)

        Publishers.CombineLatest(playbackSnapshotPublisher, listenModePublisher)
        .map { playback, listenMode in
            let (detail, selectedCID, isDanmakuEnabled, isSwitchingPlayQuality) = playback
            let (playbackContentMode, isSwitchingVideoListenMode) = listenMode
            return VideoDetailShellOverlaySnapshot(
                detail: detail,
                recordsPlaybackHistory: detailViewModel.playbackOptions.recordsPlaybackHistory,
                selectedCID: selectedCID,
                isDanmakuEnabled: isDanmakuEnabled,
                isSwitchingPlayQuality: isSwitchingPlayQuality,
                playbackContentMode: playbackContentMode,
                isSwitchingVideoListenMode: isSwitchingVideoListenMode
            )
        }
        .removeDuplicates()
        .sink { [weak self] snapshot in
            self?.receive(snapshot)
        }
        .store(in: &cancellables)
    }

    func setBareSurfaceTransitionActive(_ active: Bool) {
        guard isBareSurfaceTransitionActive != active else { return }
        isBareSurfaceTransitionActive = active
        if !active {
            flushPendingSnapshot()
        }
    }

    private func receive(_ nextSnapshot: VideoDetailShellOverlaySnapshot) {
        guard nextSnapshot != snapshot else { return }
        if isBareSurfaceTransitionActive {
            pendingSnapshot = nextSnapshot
            experimentState?.recordOverlayDeferred()
            return
        }
        snapshot = nextSnapshot
        experimentState?.recordOverlayPublish()
    }

    private func flushPendingSnapshot() {
        guard let pendingSnapshot else { return }
        self.pendingSnapshot = nil
        guard pendingSnapshot != snapshot else { return }
        snapshot = pendingSnapshot
        experimentState?.recordOverlayFlush()
    }
}

private extension UIView {
    func removeLayerAnimationsRecursively() {
        layer.removeAllAnimations()
        subviews.forEach { $0.removeLayerAnimationsRecursively() }
    }
}

@MainActor
private final class VideoDetailPlayerOverlayLegacyObservationBridge: ObservableObject {
    @Published private(set) var revision = 0

    private var updateScheduled = false
    private var cancellables = Set<AnyCancellable>()

    init(
        viewModel: PlayerStateViewModel,
        libraryStore: LibraryStore,
        isEnabled: Bool
    ) {
        guard isEnabled else { return }
        Publishers.Merge(
            viewModel.objectWillChange,
            libraryStore.objectWillChange
        )
        .sink { [weak self] in
            self?.scheduleUpdate()
        }
        .store(in: &cancellables)
    }

    private func scheduleUpdate() {
        guard !updateScheduled else { return }
        updateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateScheduled = false
            self.revision &+= 1
        }
    }
}

private struct PlayerOverlayHostRoot: View {
    let detailViewModel: VideoDetailViewModel
    @ObservedObject var state: VideoDetailShellSurfaceHost.State
    @ObservedObject var rotationCoordinator: PlaybackRotationCoordinator
    @ObservedObject var overlayState: VideoDetailShellOverlayState
    let experimentState: VideoDetailPerformanceExperimentState
    let runtimeSettings: VideoDetailRuntimeSettingsStore
    let usesNarrowObservation: Bool
    let dependencies: AppDependencies
    let onShowMoreControls: (@escaping () -> Void) -> Void
    let onDismissMoreControls: () -> Void
    let onRequestFullscreen: () -> Void
    let onExitFullscreen: () -> Void
    let onToggleDanmaku: () -> Void
    let onShowDanmakuSettings: () -> Void

    var body: some View {
        let overlaySnapshot = overlayState.snapshot
        let overlay = SurfaceOnlyPlayerOverlayRoot(
            viewModel: state.playerViewModel,
            detailViewModel: detailViewModel,
            rotationCoordinator: rotationCoordinator,
            overlaySnapshot: overlaySnapshot,
            experimentState: experimentState,
            runtimeSettings: runtimeSettings,
            usesNarrowObservation: usesNarrowObservation,
            dependencies: dependencies,
            isBareSurfaceTransitionActive: state.isBareSurfaceTransitionActive,
            retainsChromeDuringBareSurfaceTransition: state.retainsChromeDuringBareSurfaceTransition,
            isCollapsedChromeActive: state.isCollapsedChromeActive,
            playbackControlsHideRequestGeneration: state.playbackControlsHideRequestGeneration,
            playbackControlsRevealRequestGeneration: state.playbackControlsRevealRequestGeneration,
            videoAspectRatio: state.videoAspectRatio,
            danmakuCanvasSize: state.danmakuCanvasSize,
            onShowMoreControls: onShowMoreControls,
            onDismissMoreControls: onDismissMoreControls,
            onToggleDanmaku: onToggleDanmaku,
            onShowDanmakuSettings: onShowDanmakuSettings,
            onRequestFullscreen: onRequestFullscreen,
            onExitFullscreen: onExitFullscreen
        )

        Group {
            if usesNarrowObservation {
                overlay
            } else {
                overlay.id(ObjectIdentifier(state.playerViewModel))
            }
        }
        .ignoresSafeArea()
    }
}

private struct SurfaceOnlyPlayerOverlayRoot: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let viewModel: PlayerStateViewModel
    let detailViewModel: VideoDetailViewModel
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var runtimeSettings: VideoDetailRuntimeSettingsStore

    let overlaySnapshot: VideoDetailShellOverlaySnapshot
    let experimentState: VideoDetailPerformanceExperimentState
    let usesNarrowObservation: Bool
    let dependencies: AppDependencies
    @ObservedObject var rotationCoordinator: PlaybackRotationCoordinator
    let isBareSurfaceTransitionActive: Bool
    let retainsChromeDuringBareSurfaceTransition: Bool
    let isCollapsedChromeActive: Bool
    let playbackControlsHideRequestGeneration: Int
    let playbackControlsRevealRequestGeneration: Int
    let videoAspectRatio: CGFloat
    let danmakuCanvasSize: CGSize?
    let onShowMoreControls: (@escaping () -> Void) -> Void
    let onDismissMoreControls: () -> Void
    let onToggleDanmaku: () -> Void
    let onShowDanmakuSettings: () -> Void
    let onRequestFullscreen: () -> Void
    let onExitFullscreen: () -> Void

    @StateObject private var surfaceState: PlayerSurfaceStateModel
    @StateObject private var playbackControlsVisibility = PlayerPlaybackControlsVisibilityModel()
    @StateObject private var rotationTransitionSnapshotModel = PlayerRotationTransitionSnapshotModel()
    @StateObject private var seekTransitionSnapshotModel = PlayerRotationTransitionSnapshotModel()
    @StateObject private var appBackgroundRecoverySnapshotModel = PlayerRotationTransitionSnapshotModel()
    @StateObject private var speedBoostModel = PlayerSpeedBoostModel()
    @StateObject private var seekPreviewBox = PlayerSeekPreviewModelBox()
    @StateObject private var playbackProgressCoordinator = PlayerPlaybackProgressCoordinator()

    private var seekPreviewModel: PlayerSeekPreviewModel {
        seekPreviewBox.model
    }
    @StateObject private var progressReporter = PlayerPlaybackProgressReporter()
    @StateObject private var legacyObservationBridge: VideoDetailPlayerOverlayLegacyObservationBridge
    @State private var lastPreparedScrubProgress = -1.0
    @State private var isMoreControlsPresented = false
    @State private var portraitMoreControlsRequestID: UUID?
    @State private var isMoreControlsButtonPressed = false
    @State private var isVideoListenQueuePresented = false
    @State private var isQualitySelectionPresented = false
    @State private var hasSelectableSubtitleTracks = false

    private var isLandscape: Bool {
        rotationCoordinator.chromeLandscape
    }

    private var isPortraitFullscreen: Bool {
        rotationCoordinator.isPortraitFullscreen
    }

    init(
        viewModel: PlayerStateViewModel,
        detailViewModel: VideoDetailViewModel,
        rotationCoordinator: PlaybackRotationCoordinator,
        overlaySnapshot: VideoDetailShellOverlaySnapshot,
        experimentState: VideoDetailPerformanceExperimentState,
        runtimeSettings: VideoDetailRuntimeSettingsStore,
        usesNarrowObservation: Bool,
        dependencies: AppDependencies,
        isBareSurfaceTransitionActive: Bool,
        retainsChromeDuringBareSurfaceTransition: Bool,
        isCollapsedChromeActive: Bool,
        playbackControlsHideRequestGeneration: Int,
        playbackControlsRevealRequestGeneration: Int = 0,
        videoAspectRatio: CGFloat,
        danmakuCanvasSize: CGSize?,
        onShowMoreControls: @escaping (@escaping () -> Void) -> Void,
        onDismissMoreControls: @escaping () -> Void,
        onToggleDanmaku: @escaping () -> Void,
        onShowDanmakuSettings: @escaping () -> Void,
        onRequestFullscreen: @escaping () -> Void,
        onExitFullscreen: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.detailViewModel = detailViewModel
        self.rotationCoordinator = rotationCoordinator
        self.overlaySnapshot = overlaySnapshot
        self.experimentState = experimentState
        self.runtimeSettings = runtimeSettings
        self.usesNarrowObservation = usesNarrowObservation
        self.dependencies = dependencies
        _libraryStore = ObservedObject(wrappedValue: dependencies.libraryStore)
        self.isBareSurfaceTransitionActive = isBareSurfaceTransitionActive
        self.retainsChromeDuringBareSurfaceTransition = retainsChromeDuringBareSurfaceTransition
        self.isCollapsedChromeActive = isCollapsedChromeActive
        self.playbackControlsHideRequestGeneration = playbackControlsHideRequestGeneration
        self.playbackControlsRevealRequestGeneration = playbackControlsRevealRequestGeneration
        self.videoAspectRatio = videoAspectRatio
        self.danmakuCanvasSize = danmakuCanvasSize
        self.onShowMoreControls = onShowMoreControls
        self.onDismissMoreControls = onDismissMoreControls
        self.onToggleDanmaku = onToggleDanmaku
        self.onShowDanmakuSettings = onShowDanmakuSettings
        self.onRequestFullscreen = onRequestFullscreen
        self.onExitFullscreen = onExitFullscreen
        _surfaceState = StateObject(wrappedValue: PlayerSurfaceStateModel(viewModel: viewModel))
        _legacyObservationBridge = StateObject(
            wrappedValue: VideoDetailPlayerOverlayLegacyObservationBridge(
                viewModel: viewModel,
                libraryStore: dependencies.libraryStore,
                isEnabled: !usesNarrowObservation
            )
        )
    }

    var body: some View {
        let _ = legacyObservationBridge.revision
        let context = runtimeContext
        let renderContext = context.renderContext
        let renderState = BiliPlayerViewRenderState(
            context: renderContext,
            verticalSizeClass: verticalSizeClass
        )
        let visibilityActions = renderState.visibilityActions
        let speedActions = renderState.speedBoostActions
        let nativeActions = BiliPlayerNativeControlsActionBuilder(
            viewModel: viewModel,
            configuration: renderContext.configuration,
            visibilityActions: visibilityActions,
            seekPreviewModel: renderContext.seekPreviewModel,
            seekPreviewAPI: renderContext.seekPreviewAPI,
            seekPreviewContext: renderContext.seekPreviewContext,
            holdCurrentFrameForSeek: holdCurrentFrameForSeek,
            prepareUserSeekWarmup: prepareUserSeekWarmupIfNeeded,
            resetPreparedScrubProgress: { lastPreparedScrubProgress = -1 },
            isFullscreenActiveOverride: isPortraitFullscreen ? true : nil
        ).actions
        let shouldKeepChromeMounted = keepsChromeMounted && !isCollapsedChromeActive

        GeometryReader { proxy in
            let videoInsets = visibleVideoInsets(in: proxy.size)
            let chromeState = surfaceChromeState(
                context: renderContext,
                renderState: renderState,
                contentInsets: videoInsets
            )
            ZStack {
                if isAudioOnlyPlayback {
                    VideoListenArtworkLayer(
                        video: overlaySnapshot.historyVideo,
                        isLandscape: isLandscape
                    )
                    .allowsHitTesting(false)
                    .zIndex(0.5)
                }

                if shouldKeepChromeMounted {
                    Group {
                        BiliPlayerSurfaceGestureLayerHost(
                            content: Color.clear
                                .frame(maxWidth: .infinity, maxHeight: .infinity),
                            visibilityActions: visibilityActions,
                            speedBoostActions: speedActions,
                            viewModel: viewModel,
                            allowsDoubleTapPlaybackToggle: true,
                            seekPreviewModel: renderContext.seekPreviewModel,
                            seekPreviewAPI: renderContext.seekPreviewAPI,
                            seekPreviewContext: renderContext.seekPreviewContext,
                            holdCurrentFrameForSeek: holdCurrentFrameForSeek,
                            prepareUserSeekWarmup: prepareUserSeekWarmupIfNeeded,
                            resetPreparedScrubProgress: { lastPreparedScrubProgress = -1 }
                        )
                        .zIndex(1)

                        BiliPlayerSurfaceOverlayLayer(
                            state: chromeState,
                            speedBoostModel: renderContext.speedBoostModel,
                            seekPreviewModel: renderContext.seekPreviewModel
                        )
                            .zIndex(2)

                        BiliPlayerControlsOverlayLayer(
                            state: chromeState,
                            playbackControls: AnyView(
                                BiliPlayerNativeControlsHost(
                                    context: renderContext,
                                    renderState: renderState,
                                    actions: nativeActions,
                                    progressStyle: .telegram,
                                    isFullscreenActiveOverride: isPortraitFullscreen ? true : nil
                                )
                            ),
                            usesFullscreenSafeArea: isPortraitFullscreen
                        )
                        .zIndex(3)

                        if isAudioOnlyPlayback {
                            persistentMoreControlsButton(contentInsets: videoInsets)
                        }

                        if runtimeSettings.playerPerformanceOverlayEnabled {
                            performanceOverlay(contentInsets: videoInsets, in: proxy.size)
                                .zIndex(8)
                        }

                        let rotationReportMetricsID = overlaySnapshot.historyVideo.bvid
                        if runtimeSettings.videoRotationFrameReportOverlayEnabled,
                           !rotationReportMetricsID.isEmpty {
                            VideoRotationFrameReportFloatingWindow(
                                metricsID: rotationReportMetricsID,
                                contentInsets: videoInsets
                            )
                            .zIndex(8.5)
                        }

                        if isLandscape, isMoreControlsPresented {
                            SurfaceOnlyLandscapeMoreControlsOverlay(
                                detailViewModel: detailViewModel,
                                viewModel: viewModel,
                                libraryStore: libraryStore,
                                qualityStore: detailViewModel.playbackRenderStore.qualityControlStore,
                                selectPlayVariant: { detailViewModel.selectPlayVariant($0) },
                                onToggleDanmaku: onToggleDanmaku,
                                contentInsets: videoInsets,
                                close: {
                                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
                                        isMoreControlsPresented = false
                                    }
                                }
                            )
                            .zIndex(9)
                        }
                    }
                    .opacity(isBareSurfaceTransitionActive ? 0 : 1)
                    .allowsHitTesting(!isBareSurfaceTransitionActive)
                }

                if showsCenterPlaybackControl {
                    centerPlaybackControl
                        .zIndex(5)
                }

                if !isAudioOnlyPlayback {
                    let danmakuExtra = danmakuExtraInsets(in: proxy.size, videoInsets: videoInsets)
                    VideoDetailPlayerSurfaceDanmakuLayer(
                        store: detailViewModel.danmakuRenderStore,
                        playerViewModel: viewModel,
                        usesLandscapePlaybackChrome: danmakuUsesLandscapePlaybackChrome,
                        logicalCanvasSize: danmakuCanvasSize,
                        videoAspectRatio: videoAspectRatio,
                        additionalTopInset: danmakuExtra.top + (isPortraitFullscreen ? 8 : 0),
                        additionalBottomInset: danmakuExtra.bottom,
                        // The bare-surface flag also covers control-tree
                        // prewarming. Danmaku must only see the real UIKit
                        // rotation transition; prewarm should not pause or
                        // rebuild its timeline.
                        isLayoutTransitioning: rotationCoordinator.isSystemRotationTransitioning,
                        onPlaybackTime: { detailViewModel.updateDanmakuPlaybackTime($0, underLoad: $1) }
                    )
                    .allowsHitTesting(false)
                    .zIndex(2.5)

                    VideoDetailPlayerSurfaceSubtitleLayer(
                        store: detailViewModel.subtitleRenderStore,
                        controlsVisibility: playbackControlsVisibility,
                        clock: viewModel.playbackClock,
                        cid: detailViewModel.selectedCID,
                        isFullscreen: configuration.isFullscreenActive,
                        contentInsets: videoInsets,
                        loadTracks: { await detailViewModel.loadSubtitleTracksForCurrentVideo() }
                    )
                    .allowsHitTesting(false)
                    .zIndex(2.55)
                }
            }
            .playerOfflineNotice(
                isBuffering: chromeState.isBuffering,
                isPresented: shouldKeepChromeMounted && !isBareSurfaceTransitionActive,
                bottomInset: chromeState.contentInsets.bottom
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .background {
            PlaybackDetailPlayerReadinessProbe(
                playerViewModel: viewModel,
                context: .video(overlaySnapshot.historyVideo)
            )
        }
        .environmentObject(dependencies)
        .environmentObject(libraryStore)
        .environment(\.appThemeTintColor, runtimeSettings.appTintColor)
        .biliPlayerLifecycle(
            isFullscreenActive: configuration.isFullscreenActive,
            presentation: configuration.presentation,
            isLayoutTransitioning: configuration.isLayoutTransitioning,
            isSecondaryControlsPresented: configuration.isSecondaryControlsPresented,
            isPictureInPictureEnabled: effectivePictureInPictureEnabled,
            actions: context.lifecycleActions
        )
        .onAppear {
            if !isAudioOnlyPlayback {
                detailViewModel.scheduleDanmakuLoadIfNeeded()
            }
        }
        .onDisappear {
            setQualitySelectionPresented(false)
        }
        .onReceive(detailViewModel.$isShowingQualitySelection.removeDuplicates()) { isShowing in
            guard isQualitySelectionPresented != isShowing else { return }
            isQualitySelectionPresented = isShowing
        }
        .onChange(of: rotationCoordinator.isSystemRotationTransitioning) { _, isTransitioning in
            guard isTransitioning else { return }
            setQualitySelectionPresented(false)
        }
        .onChange(of: ObjectIdentifier(viewModel)) { _, _ in
            guard usesNarrowObservation else { return }
            context.lifecycleActions.onPlayerChanged()
            experimentState.recordPlayerRebind()
        }
        .onChange(of: isLandscape) { _, isLandscape in
            // 旋转控件预热会在 bare transition 中短暂翻转该值，不能把它当成
            // 用户真实进入横屏，否则刚弹出的竖屏菜单会被预热流程立即关闭。
            guard !isBareSurfaceTransitionActive else { return }
            setQualitySelectionPresented(false)
            if isLandscape {
                portraitMoreControlsRequestID = nil
                onDismissMoreControls()
                isVideoListenQueuePresented = false
                detailViewModel.isShowingSubtitleSelection = false
            } else {
                isMoreControlsPresented = false
            }
        }
        .onChange(of: overlaySnapshot.playbackContentMode) { _, mode in
            if mode != .audioOnly {
                isVideoListenQueuePresented = false
            }
            guard mode == .audioOnly else { return }
            isMoreControlsPresented = false
            setQualitySelectionPresented(false)
            portraitMoreControlsRequestID = nil
            onDismissMoreControls()
            if isLandscape {
                onExitFullscreen()
            }
        }
        .onChange(of: isBareSurfaceTransitionActive) { _, isActive in
            guard isActive else { return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isMoreControlsPresented = false
                isVideoListenQueuePresented = false
                setQualitySelectionPresented(false)
                isMoreControlsButtonPressed = false
                portraitMoreControlsRequestID = nil
            }
            onDismissMoreControls()
            playbackControlsVisibility.cancelAutoHide()
        }
        .onChange(of: playbackControlsHideRequestGeneration) { _, _ in
            setQualitySelectionPresented(false)
            playbackControlsVisibility.hide(animated: false)
        }
        .onChange(of: playbackControlsRevealRequestGeneration) { _, _ in
            playbackControlsVisibility.markInteraction(
                keepsVisible: true,
                showsPlaybackControls: keepsChromeMounted,
                isLayoutTransitioning: isBareSurfaceTransitionActive
            )
        }
        .onChange(of: usesCustomControlsOverlay) { _, usesCustom in
            if usesCustom {
                playbackControlsVisibility.showAndSchedule(
                    showsPlaybackControls: keepsChromeMounted,
                    isLayoutTransitioning: isBareSurfaceTransitionActive
                )
            } else {
                setQualitySelectionPresented(false)
                playbackControlsVisibility.hide(animated: false)
            }
        }
        .onChange(of: surfaceState.isUserSeeking) { _, isUserSeeking in
            updateSeekTransitionSnapshot(isUserSeeking: isUserSeeking)
        }
        .onReceive(surfaceState.$snapshot.dropFirst()) { _ in
            guard usesNarrowObservation else { return }
            experimentState.recordPlayerStatePublish()
        }
        .onReceive(runtimeSettings.$snapshot.dropFirst()) { _ in
            guard usesNarrowObservation else { return }
            experimentState.recordSettingsStatePublish()
        }
        .onReceive(subtitleControlAvailabilityPublisher) { hasTracks in
            hasSelectableSubtitleTracks = hasTracks
        }
        .sheet(isPresented: $isVideoListenQueuePresented) {
            NavigationStack {
                SurfaceOnlyVideoListenQueuePage(
                    detailViewModel: detailViewModel,
                    closeSheet: { isVideoListenQueuePresented = false }
                )
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var fullscreenMode: PlayerFullscreenMode? {
        guard !isAudioOnlyPlayback else { return nil }
        if isLandscape { return .landscape(.landscapeRight) }
        return isPortraitFullscreen ? .portrait : nil
    }

    private var danmakuUsesLandscapePlaybackChrome: Bool {
        // Rotation chrome pre-warm temporarily flips `chromeLandscape` to
        // materialize the controls tree. Danmaku visibility and insets must
        // follow the stable physical orientation during that pre-warm, and
        // otherwise match the geometric target (`layoutLandscape`) immediately
        // so `topInset` does not jump from 0 to 8 after rotation finishes.
        if rotationCoordinator.prewarmLandscape != nil {
            return rotationCoordinator.isLandscape || isPortraitFullscreen
        }
        return rotationCoordinator.layoutLandscape || isPortraitFullscreen
    }

    private var isAudioOnlyPlayback: Bool {
        overlaySnapshot.playbackContentMode == .audioOnly
    }

    private var effectivePictureInPictureEnabled: Bool {
        runtimeSettings.allowsPictureInPictureController && !isAudioOnlyPlayback
    }

    private var usesCustomControlsOverlay: Bool {
        libraryStore.usesCustomPlaybackControlsOverlay
    }

    private var keepsChromeMounted: Bool {
        usesCustomControlsOverlay
            && (!isBareSurfaceTransitionActive || retainsChromeDuringBareSurfaceTransition)
    }

    private var showsCenterPlaybackControl: Bool {
        keepsChromeMounted
            && !isCollapsedChromeActive
            && !isBareSurfaceTransitionActive
            && surfaceState.showsExplicitPlaybackStartControl
            && surfaceState.errorMessage == nil
    }

    private var centerPlaybackControl: some View {
        PlayerNativeGlassIconButton(
            systemName: "play.fill",
            accessibilityLabel: "播放",
            accessibilityIdentifier: "ui.player.playback.start",
            metrics: centerPlaybackControlMetrics
        ) {
            viewModel.playFromUserInteraction()
            playbackControlsVisibility.showAndSchedule(
                showsPlaybackControls: keepsChromeMounted,
                isLayoutTransitioning: isBareSurfaceTransitionActive
            )
        }
        .biliLiquidGlassForeground(shadowOpacity: 0.20)
    }

    private var centerPlaybackControlMetrics: PlayerNativeControlMetrics {
        controlMetrics.sized(controlHeight: 56, iconSize: 24)
    }

    private var configuration: BiliPlayerViewConfiguration {
        BiliPlayerViewOptions(
            presentation: isLandscape ? .fullScreen : .embedded,
            showsNavigationChrome: false,
            showsPlaybackControls: keepsChromeMounted,
            showsStartupLoadingIndicator: false,
            pausesOnDisappear: false,
            controlsAccessory: isAudioOnlyPlayback
                ? AnyView(videoListenQuickControls)
                : AnyView(subtitleAndMoreControlsAccessory),
            isDanmakuEnabled: keepsChromeMounted && overlaySnapshot.isDanmakuEnabled && !isAudioOnlyPlayback,
            onToggleDanmaku: isAudioOnlyPlayback ? nil : onToggleDanmaku,
            onShowDanmakuSettings: isAudioOnlyPlayback ? nil : onShowDanmakuSettings,
            isSecondaryControlsPresented: keepsChromeMounted
                && (isMoreControlsPresented
                    || portraitMoreControlsRequestID != nil
                    || isVideoListenQueuePresented
                    || isQualitySelectionPresented),
            ignoresContainerSafeArea: true,
            keepsPlayerSurfaceStable: true,
            fullscreenMode: fullscreenMode,
            isLayoutTransitioning: isBareSurfaceTransitionActive,
            usesLiveSurfaceDuringLayoutTransition: true,
            disablesSurfaceImplicitLayoutAnimations: true,
            showsRotationTransitionSnapshot: false,
            onRequestFullscreen: isAudioOnlyPlayback ? nil : onRequestFullscreen,
            onExitFullscreen: isAudioOnlyPlayback ? nil : onExitFullscreen
        ).configuration()
    }

    private var videoListenQuickControls: some View {
        SurfaceOnlyVideoListenQuickControls(
            detailViewModel: detailViewModel,
            libraryStore: libraryStore,
            metrics: controlMetrics,
            showQueue: { isVideoListenQueuePresented = true }
        )
    }

    /// 非听书模式下的 accessory 槽位：字幕（CC）按钮 + 全屏状态时的更多播放设置按钮。
    private var subtitleAndMoreControlsAccessory: some View {
        HStack(spacing: controlMetrics.controlSpacing) {
            if hasSelectableSubtitleTracks {
                subtitleControlButton
            }

            qualityMenuControl

            if usesFullscreenStatusChrome {
                moreControlsButton
            }
        }
    }

    private var subtitleControlAvailabilityPublisher: AnyPublisher<Bool, Never> {
        let store = detailViewModel.subtitleRenderStore
        return Publishers.CombineLatest(
            store.$selectableTracksCID,
            detailViewModel.$selectedCID
        )
        .map { values in
            guard let tracksCID = values.0 else { return false }
            return tracksCID == values.1
        }
        .removeDuplicates()
        .eraseToAnyPublisher()
    }

    private var qualityMenuControl: some View {
        VideoDetailInlineQualityMenuControl(
            store: detailViewModel.playbackRenderStore.qualityControlStore,
            metrics: controlMetrics,
            isLandscape: isLandscape,
            onPress: {
                guard !isLandscape else { return }
                playbackControlsVisibility.cancelAutoHide()
                setQualitySelectionPresented(true)
            },
            onMenuWillOpen: {
                guard isLandscape else { return }
                playbackControlsVisibility.cancelAutoHide()
            },
            onMenuDidClose: {
                guard isLandscape else { return }
                playbackControlsVisibility.showAndSchedule(
                    showsPlaybackControls: keepsChromeMounted,
                    isLayoutTransitioning: isBareSurfaceTransitionActive
                )
            },
            selectPlayVariant: { detailViewModel.selectPlayVariant($0) }
        )
    }

    private func setQualitySelectionPresented(_ isPresented: Bool) {
        if isQualitySelectionPresented != isPresented {
            isQualitySelectionPresented = isPresented
        }
        if detailViewModel.isShowingQualitySelection != isPresented {
            detailViewModel.isShowingQualitySelection = isPresented
        }
    }

    /// 字幕（CC）按钮：UIKit 承担触摸与选轨弹窗（系统 action sheet），
    /// SwiftUI 只提供玻璃外观（同 moreControlsButton）。
    /// 字幕（CC）按钮：与其他控制按钮等宽等高，触控区单独扩展，
    /// 保证与齿轮/全屏按钮的间距一致。选轨弹窗交给外层系统 sheet 呈现。
    private var subtitleControlButton: some View {
        Group {
            if isLandscape {
                // 横屏：点按直接由按钮展开系统菜单（UIMenu），不覆盖画面。
                VideoDetailSubtitleMenuButton(
                    store: detailViewModel.subtitleRenderStore,
                    metrics: controlMetrics,
                    onMenuWillOpen: {
                        // 菜单展开期间挂起控制条自动隐藏。
                        playbackControlsVisibility.cancelAutoHide()
                    },
                    onSelect: { lan in
                        Task { await detailViewModel.selectSubtitleTrack(lan: lan) }
                        // 菜单关闭后恢复正常的自动隐藏节奏。
                        playbackControlsVisibility.showAndSchedule(
                            showsPlaybackControls: keepsChromeMounted,
                            isLayoutTransitioning: isBareSurfaceTransitionActive
                        )
                    }
                )
            } else {
                VideoDetailSubtitleControlButton(
                    store: detailViewModel.subtitleRenderStore,
                    metrics: controlMetrics,
                    onSelect: {
                        playbackControlsVisibility.cancelAutoHide()
                        detailViewModel.isShowingSubtitleSelection = true
                    }
                )
            }
        }
        .frame(width: controlMetrics.controlHeight, height: controlMetrics.controlHeight)
        .biliPlayerClearGlass(interactive: true, in: Circle())
        .biliPlayerExpandedHitTarget(metrics: controlMetrics)
    }

    private var runtimeContext: BiliPlayerViewRuntimeContext {
        BiliPlayerViewRuntimeContextBuilder(
            dependencies: dependencies,
            libraryStore: libraryStore,
            viewModel: viewModel,
            surfaceState: surfaceState,
            playbackControlsVisibility: playbackControlsVisibility,
            rotationTransitionSnapshotModel: rotationTransitionSnapshotModel,
            seekTransitionSnapshotModel: seekTransitionSnapshotModel,
            appBackgroundRecoverySnapshotModel: appBackgroundRecoverySnapshotModel,
            speedBoostModel: speedBoostModel,
            seekPreviewModel: seekPreviewModel,
            playbackProgressCoordinator: playbackProgressCoordinator,
            progressReporter: progressReporter,
            historyVideo: overlaySnapshot.recordsPlaybackHistory ? overlaySnapshot.historyVideo : nil,
            historyCID: overlaySnapshot.historyCID,
            historyDuration: overlaySnapshot.historyDuration,
            configuration: configuration,
            isPictureInPictureEnabled: effectivePictureInPictureEnabled,
            videoGravity: .resizeAspect,
            holdCurrentFrameForSeek: holdCurrentFrameForSeek,
            prepareUserSeekWarmup: prepareUserSeekWarmupIfNeeded,
            resetPreparedScrubProgress: { lastPreparedScrubProgress = -1 }
        ).context
    }

    private var moreControlsButton: some View {
        SurfaceOnlyUIKitMoreControlsButton(
            metrics: controlMetrics,
            systemImageName: usesFullscreenStatusChrome ? "gearshape.fill" : "ellipsis.circle",
            onPressBegan: {
                isMoreControlsButtonPressed = true
                playbackControlsVisibility.cancelAutoHide()
            },
            onPressEnded: {
                isMoreControlsButtonPressed = false
                guard portraitMoreControlsRequestID == nil,
                      !isMoreControlsPresented
                else { return }
                playbackControlsVisibility.scheduleAutoHide(
                    showsPlaybackControls: keepsChromeMounted,
                    isLayoutTransitioning: isBareSurfaceTransitionActive
                )
            }
        ) {
            playbackControlsVisibility.cancelAutoHide()
            if isLandscape {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
                    isMoreControlsPresented = true
                }
            } else {
                let requestID = UUID()
                portraitMoreControlsRequestID = requestID
                onShowMoreControls {
                    guard portraitMoreControlsRequestID == requestID else { return }
                    portraitMoreControlsRequestID = nil
                }
            }
        }
        .frame(width: controlMetrics.controlHeight, height: controlMetrics.controlHeight)
        // Render the glass with the same SwiftUI container/visibility as the other controls.
        .biliPlayerClearGlass(interactive: true, in: Circle())
        .biliPlayerExpandedHitTarget(metrics: controlMetrics)
        .accessibilityLabel("更多播放设置")
    }

    private func persistentMoreControlsButton(contentInsets: EdgeInsets) -> some View {
        GeometryReader { _ in
            let safeAreaInsets = fullscreenSafeAreaInsets()
            let topInset = max(safeAreaInsets.top, contentInsets.top)
            let trailingInset = max(safeAreaInsets.right, contentInsets.trailing)
            VStack {
                HStack {
                    Spacer()
                    moreControlsButton
                        .padding(.top, topControlsPadding + topInset)
                        .padding(.trailing, moreControlsTrailingPadding(trailingInset: trailingInset))
                }
                Spacer()
            }
        }
        .opacity(isMoreControlsButtonPressed ? 1 : playbackControlsVisibility.opacity)
        .allowsHitTesting(
            isMoreControlsButtonPressed || playbackControlsVisibility.acceptsHitTesting
        )
        .zIndex(4)
    }

    private func performanceOverlay(contentInsets: EdgeInsets, in size: CGSize) -> some View {
        let safeAreaInsets = fullscreenSafeAreaInsets()
        let statusRowClearance = showsFullscreenStatusControls
            ? controlMetrics.controlHeight + 8
            : 0
        let topInset = max(safeAreaInsets.top + statusRowClearance, contentInsets.top)
        let leadingInset = max(safeAreaInsets.left, contentInsets.leading)
        let trailingInset = max(safeAreaInsets.right, contentInsets.trailing)
        let bottomInset = max(safeAreaInsets.bottom, contentInsets.bottom)
        let horizontalPadding = horizontalControlsPadding
        let availableWidth = max(1, size.width - leadingInset - trailingInset - horizontalPadding * 2)
        let availableHeight = max(1, size.height - topInset - bottomInset - topControlsPadding - 14)
        let panelWidth = min(isLandscape ? 340 : 320, max(260, availableWidth))
        let maximumHeight = min(isLandscape ? 420 : 360, max(180, availableHeight))

        return VStack {
            HStack {
                VideoDetailPerformanceOverlayContainer(
                    store: detailViewModel.networkDiagnosticsRenderStore,
                    experimentState: experimentState,
                    panelWidth: panelWidth,
                    maximumHeight: maximumHeight
                )
                .padding(.top, topControlsPadding + topInset)
                .padding(.leading, horizontalPadding + leadingInset)

                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var fullscreenStatusControls: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                VideoDetailFullscreenClockStatus()
                    .frame(height: controlMetrics.controlHeight)
                    .biliPlayerClearGlass(interactive: false, in: Capsule())

                Spacer(minLength: 0)

                VideoDetailFullscreenBatteryStatus()
                    .frame(height: controlMetrics.controlHeight)
                    .biliPlayerClearGlass(interactive: false, in: Capsule())
            }
        }
    }

    private func visibleVideoInsets(in size: CGSize) -> EdgeInsets {
        guard configuration.isFullscreenActive else { return EdgeInsets() }
        let insets = DanmakuVideoViewport.fullscreenContentInsets(
            in: size,
            videoAspectRatio: videoAspectRatio,
            isPortraitFullscreen: isPortraitFullscreen
        )
        return EdgeInsets(
            top: insets.top,
            leading: insets.leading,
            bottom: insets.bottom,
            trailing: insets.trailing
        )
    }

    private func danmakuExtraInsets(
        in size: CGSize,
        videoInsets: EdgeInsets
    ) -> (top: CGFloat, bottom: CGFloat) {
        guard isPortraitFullscreen, size.width > 1, size.height > 1 else {
            return (0, 0)
        }
        let canvas = DanmakuVideoViewport.scrollingCanvas(
            in: CGRect(origin: .zero, size: size),
            aspectRatio: videoAspectRatio
        )
        let canvasBottomInset = max(0, size.height - canvas.maxY)
        return (
            top: max(0, videoInsets.top - canvas.minY),
            bottom: max(0, videoInsets.bottom - canvasBottomInset)
        )
    }

    private func moreControlsTrailingPadding(trailingInset: CGFloat) -> CGFloat {
        horizontalControlsPadding + trailingInset
    }

    private var usesFullscreenChromeSpacing: Bool {
        configuration.presentation == .fullScreen || configuration.isFullscreenActive
    }

    private var topControlsPadding: CGFloat {
        usesFullscreenChromeSpacing ? 14 : 10
    }

    private var horizontalControlsPadding: CGFloat {
        20
    }

    private func fullscreenSafeAreaInsets() -> UIEdgeInsets {
        guard configuration.isFullscreenActive,
              let window = UIApplication.shared.playbackDetailForegroundKeyWindow
        else { return .zero }
        return window.safeAreaInsets
    }

    private var controlMetrics: PlayerNativeControlMetrics {
        if fullscreenMode?.isLandscape == true || verticalSizeClass == .compact {
            return .landscape
        }
        return .portrait
    }

    private var usesFullscreenStatusChrome: Bool {
        !isAudioOnlyPlayback
    }

    private var showsFullscreenStatusControls: Bool {
        configuration.isFullscreenActive
            && VideoDetailSurfaceChromePolicy.showsFullscreenStatusControls(
            usesFullscreenChrome: usesFullscreenStatusChrome
                && fullscreenMode?.isLandscape == true,
            isPortraitFullscreen: isPortraitFullscreen
        )
    }

    private func surfaceChromeState(
        context: BiliPlayerViewRenderContext,
        renderState: BiliPlayerViewRenderState,
        contentInsets: EdgeInsets
    ) -> BiliPlayerSurfaceChromeState {
        return BiliPlayerSurfaceChromeState(
            presentation: context.configuration.presentation,
            surfaceOverlay: context.configuration.surfaceOverlay,
            rotationSnapshot: nil,
            seekSnapshot: seekTransitionSnapshotModel.snapshot,
            appBackgroundRecoverySnapshot: appBackgroundRecoverySnapshotModel.snapshot,
            rotationFallbackCoverURL: nil,
            rotationSnapshotOpacity: 0,
            seekSnapshotOpacity: seekTransitionSnapshotModel.opacity,
            appBackgroundRecoverySnapshotOpacity: appBackgroundRecoverySnapshotModel.opacity,
            constrainsRotationSnapshotToVideoAspect: false,
            showsPlayerLoadingChrome: renderState.showsPlayerLoadingChrome
                && !overlaySnapshot.isSwitchingPlayQuality,
            isBuffering: context.surfaceState.isBuffering,
            isPlaying: context.surfaceState.isPlaying,
            hasPresentedPlayback: context.surfaceState.hasPresentedPlayback,
            showsInlineLoadingProgress: renderState.showsInlineLoadingProgress,
            isUserSeeking: context.surfaceState.isUserSeeking,
            showsActivePlaybackControls: renderState.showsActivePlaybackControls,
            playbackControlsOpacity: playbackControlsVisibility.opacity,
            playbackControlsAllowsHitTesting: playbackControlsVisibility.acceptsHitTesting,
            topLeadingControlsAccessory: context.configuration.topLeadingControlsAccessory,
            topCenterControlsAccessory: showsFullscreenStatusControls
                ? AnyView(fullscreenStatusControls.allowsHitTesting(false))
                : nil,
            topTrailingControlsAccessory: nil,
            isFullscreenActive: context.configuration.isFullscreenActive,
            controlsBottomLift: context.configuration.controlsBottomLift,
            controlsHorizontalInset: context.configuration.controlsHorizontalInset,
            contentInsets: contentInsets,
            errorMessage: context.surfaceState.errorMessage
        )
    }

    private func prepareUserSeekWarmupIfNeeded(_ progress: Double, force: Bool = false) {
        let clampedProgress = min(max(progress, 0), 1)
        guard force || abs(clampedProgress - lastPreparedScrubProgress) >= 0.008 else { return }
        lastPreparedScrubProgress = clampedProgress
        configuration.onPrepareForUserSeek?(clampedProgress)
    }

    private func holdCurrentFrameForSeek() {
        guard !viewModel.usesNativePlaybackSurfaceController else {
            seekTransitionSnapshotModel.release(immediate: true)
            return
        }
        seekTransitionSnapshotModel.hold(
            hasPresentedPlayback: surfaceState.hasPresentedPlayback,
            surfaceLayoutGeneration: viewModel.surfaceLayoutGeneration
        ) {
            viewModel.makePlaybackTransitionSnapshot()
        }
    }

    private func updateSeekTransitionSnapshot(isUserSeeking: Bool) {
        if isUserSeeking {
            guard viewModel.shouldHoldSeekSnapshotAtInteractionStart,
                  !viewModel.usesNativePlaybackSurfaceController
            else { return }
            holdCurrentFrameForSeek()
        } else {
            if viewModel.usesNativePlaybackSurfaceController {
                seekTransitionSnapshotModel.release(immediate: true) {
                    viewModel.finishUserSeekVisualReveal()
                }
                return
            }
            seekTransitionSnapshotModel.releaseForSeekTransition(
                isReadyForReveal: {
                    viewModel.isSeekRecoverySnapshotReadyForReveal()
                },
                onReleased: {
                    viewModel.finishUserSeekVisualReveal()
                }
            )
        }
    }
}

struct SurfaceOnlyMoreControlsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var detailViewModel: VideoDetailViewModel
    @ObservedObject var viewModel: PlayerStateViewModel
    @ObservedObject var qualityStore: VideoDetailQualityControlRenderStore
    let selectPlayVariant: (PlayVariant) -> Void
    let onToggleDanmaku: () -> Void
    let closeAction: (() -> Void)?

    init(
        detailViewModel: VideoDetailViewModel,
        viewModel: PlayerStateViewModel,
        qualityStore: VideoDetailQualityControlRenderStore,
        selectPlayVariant: @escaping (PlayVariant) -> Void,
        onToggleDanmaku: @escaping () -> Void,
        close: (() -> Void)? = nil
    ) {
        self.detailViewModel = detailViewModel
        self.viewModel = viewModel
        self.qualityStore = qualityStore
        self.selectPlayVariant = selectPlayVariant
        self.onToggleDanmaku = onToggleDanmaku
        self.closeAction = close
    }

    var body: some View {
        SurfaceOnlyMoreControlsNavigationContent(
            detailViewModel: detailViewModel,
            viewModel: viewModel,
            libraryStore: detailViewModel.libraryStore,
            qualityStore: qualityStore,
            selectPlayVariant: selectPlayVariant,
            onToggleDanmaku: onToggleDanmaku,
            close: closeSheet
        )
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func closeSheet() {
        if let closeAction {
            closeAction()
        } else {
            dismiss()
        }
    }
}

private struct SurfaceOnlyVideoListenQuickControls: View {
    @ObservedObject var detailViewModel: VideoDetailViewModel
    @ObservedObject var libraryStore: LibraryStore
    let metrics: PlayerNativeControlMetrics
    let showQueue: () -> Void

    var body: some View {
        HStack(spacing: metrics.controlSpacing) {
            PlayerNativeGlassIconButton(
                systemName: "list.bullet",
                accessibilityLabel: "播放列表，\(detailViewModel.videoListenQueueAccessoryTitle)",
                metrics: metrics,
                action: showQueue
            )

            Menu {
                ForEach(VideoListenPlaybackOrder.allCases) { order in
                    Button {
                        libraryStore.setVideoListenPlaybackOrder(order)
                    } label: {
                        Label(
                            order.title,
                            systemImage: libraryStore.videoListenPlaybackOrder == order
                                ? "checkmark"
                                : order.systemImage
                        )
                    }
                }
            } label: {
                Image(systemName: libraryStore.videoListenPlaybackOrder.systemImage)
                    .font(.system(size: iconSize, weight: .semibold))
                    .frame(width: metrics.controlHeight, height: metrics.controlHeight)
            }
            .biliPlayerCompactGlassCircle(metrics: metrics)
            .accessibilityLabel("播放顺序，\(libraryStore.videoListenPlaybackOrder.title)")

            Menu {
                ForEach(VideoListenSleepTimerOption.allCases) { option in
                    Button {
                        detailViewModel.setVideoListenSleepTimer(option)
                    } label: {
                        Label(
                            option.title,
                            systemImage: detailViewModel.videoListenSleepTimerOption == option
                                ? "checkmark"
                                : option.systemImage
                        )
                    }
                }
            } label: {
                sleepTimerLabel
            }
            .biliPlayerCompactGlassCapsule(metrics: metrics)
            .accessibilityLabel("定时关闭，\(detailViewModel.videoListenSleepTimerAccessoryTitle)")
        }
    }

    @ViewBuilder
    private var sleepTimerLabel: some View {
        if let deadline = detailViewModel.videoListenSleepTimerDeadline {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(VideoListenSleepTimerCountdownFormatter.text(deadline: deadline, now: context.date))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                    .frame(width: max(48, metrics.controlHeight + 20), height: metrics.controlHeight)
            }
        } else {
            Image(systemName: detailViewModel.videoListenSleepTimerOption.systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .frame(width: metrics.controlHeight, height: metrics.controlHeight)
        }
    }

    private var iconSize: CGFloat {
        metrics.iconSize
    }
}

private struct VideoListenArtworkLayer: View {
    let video: VideoItem
    let isLandscape: Bool

    private let artworkAspectRatio: CGFloat = 16.0 / 9.0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black

                backgroundArtwork
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                Color.black.opacity(0.52)

                if proxy.size.height < 280 {
                    compactContent(in: proxy.size)
                } else {
                    regularContent(in: proxy.size)
                }
            }
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("听视频中，\(video.title)，\(ownerName)")
    }

    private var backgroundArtwork: some View {
        CachedRemoteImage(
            url: artworkURL,
            targetPixelSize: 1_280,
            animatesAppearance: false
        ) { image in
            image
                .resizable()
                .scaledToFill()
                .scaleEffect(1.12)
                .blur(radius: 24)
        } placeholder: {
            Color.black
        }
    }

    private func compactContent(in size: CGSize) -> some View {
        let horizontalPadding = min(20.0, max(size.width * 0.05, 12.0))
        let spacing = min(14.0, max(size.width * 0.035, 10.0))
        let availableWidth = max(size.width - horizontalPadding * 2 - spacing, 0)
        let artworkMaximumWidth = min(148.0, availableWidth * 0.43)
        let artworkMaximumHeight = max(size.height - 28, 0)
        let artworkSize = fittedArtworkSize(
            maximumWidth: artworkMaximumWidth,
            maximumHeight: artworkMaximumHeight
        )
        let metadataWidth = max(availableWidth - artworkSize.width, 0)

        return HStack(spacing: spacing) {
            foregroundArtwork
                .frame(width: artworkSize.width, height: artworkSize.height)

            metadata(alignment: .leading, textAlignment: .leading, titleLines: 2)
                .frame(width: metadataWidth, alignment: .leading)
                .layoutPriority(1)
        }
        .padding(.horizontal, horizontalPadding)
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func regularContent(in size: CGSize) -> some View {
        let artworkSize = fittedArtworkSize(
            maximumWidth: min(isLandscape ? 300 : 220, size.width * 0.52),
            maximumHeight: max(size.height * 0.55, 0)
        )

        return VStack(spacing: isLandscape ? 14 : 12) {
            foregroundArtwork
                .frame(width: artworkSize.width, height: artworkSize.height)

            metadata(alignment: .center, textAlignment: .center, titleLines: 2)
                .frame(maxWidth: min(460, size.width * 0.70))
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var foregroundArtwork: some View {
        CachedRemoteImage(
            url: artworkURL,
            targetPixelSize: 960,
            animatesAppearance: true
        ) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            BiliMediaPlaceholder(style: .video, iconSize: 22)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.34), radius: 12, x: 0, y: 7)
    }

    private func metadata(
        alignment: HorizontalAlignment,
        textAlignment: TextAlignment,
        titleLines: Int
    ) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            Label("听视频中", systemImage: "headphones")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)

            Text(video.title)
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(textAlignment)
                .lineLimit(titleLines)

            Text(ownerName)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.76))
                .lineLimit(1)
        }
    }

    private var ownerName: String {
        let name = video.owner?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "未知 UP 主" : name
    }

    private var artworkURL: URL? {
        guard let picture = video.pic?.normalizedBiliURL(), !picture.isEmpty else { return nil }
        return URL(string: picture.biliCoverThumbnailURL(width: 1_280, height: 720))
    }

    private func fittedArtworkSize(
        maximumWidth: CGFloat,
        maximumHeight: CGFloat
    ) -> CGSize {
        guard maximumWidth > 0, maximumHeight > 0 else { return .zero }
        let widthFromHeight = maximumHeight * artworkAspectRatio
        let width = min(maximumWidth, widthFromHeight)
        return CGSize(width: width, height: width / artworkAspectRatio)
    }
}

private struct SurfaceOnlyMoreControlsNavigationContent: View {
    @AppStorage(PlaybackRecoveryTestSettings.showsPlayerMenuEntryKey) private var showsRecoveryTestEntry = false
    @ObservedObject var detailViewModel: VideoDetailViewModel
    @ObservedObject var viewModel: PlayerStateViewModel
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var qualityStore: VideoDetailQualityControlRenderStore
    let selectPlayVariant: (PlayVariant) -> Void
    let onToggleDanmaku: () -> Void
    let close: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if detailViewModel.isVideoListenModeEnabled,
                   !detailViewModel.videoListenAudioVariants.isEmpty {
                    NavigationLink {
                        SurfaceOnlyAudioChoicesPage(
                            detailViewModel: detailViewModel,
                            closeSheet: close
                        )
                    } label: {
                        HStack {
                            Label("音质", systemImage: "waveform")
                            Spacer()
                            Text(detailViewModel.videoListenAudioAccessoryTitle)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if qualityStore.hasQualityMenu {
                    NavigationLink {
                        SurfaceOnlyQualityChoicesPage(
                            qualityStore: qualityStore,
                            closeSheet: close,
                            selectPlayVariant: selectPlayVariant
                        )
                    } label: {
                        HStack {
                            Label("清晰度", systemImage: qualityStore.qualityButtonSystemImage)
                            Spacer()
                            Text(qualityStore.qualityAccessoryButtonTitle)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("ui.player.quality")
                }

                if detailViewModel.isVideoListenModeEnabled {
                    NavigationLink {
                        SurfaceOnlyVideoListenQueuePage(
                            detailViewModel: detailViewModel,
                            closeSheet: close
                        )
                    } label: {
                        HStack {
                            Label("播放列表", systemImage: "list.bullet")
                            Spacer()
                            Text(detailViewModel.videoListenQueueAccessoryTitle)
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        SurfaceOnlyVideoListenPlaybackOrderPage(
                            libraryStore: libraryStore,
                            closeSheet: close
                        )
                    } label: {
                        HStack {
                            Label("播放顺序", systemImage: libraryStore.videoListenPlaybackOrder.systemImage)
                            Spacer()
                            Text(libraryStore.videoListenPlaybackOrder.title)
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        SurfaceOnlyVideoListenSleepTimerPage(
                            detailViewModel: detailViewModel,
                            closeSheet: close
                        )
                    } label: {
                        HStack {
                            Label("定时关闭", systemImage: "timer")
                            Spacer()
                            Text(detailViewModel.videoListenSleepTimerAccessoryTitle)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !detailViewModel.isVideoListenModeEnabled {
                    NavigationLink {
                        SurfaceOnlyDanmakuSettingsPage(
                            detailViewModel: detailViewModel,
                            toggleDanmaku: onToggleDanmaku,
                            usesLandscapePanel: false
                        )
                    } label: {
                        Label("弹幕设置", systemImage: "text.bubble")
                    }
                }

                NavigationLink {
                    SurfaceOnlyRateChoicesPage(
                        viewModel: viewModel,
                        closeSheet: close
                    )
                } label: {
                    HStack {
                        Label("倍速", systemImage: "speedometer")
                        Spacer()
                        Text(viewModel.playbackRate.title)
                            .foregroundStyle(.secondary)
                    }
                }

                if showsVideoListenModeToggle {
                    Toggle(isOn: videoListenModeBinding) {
                        Label {
                            HStack(spacing: 8) {
                                Text("听视频")
                                if detailViewModel.isSwitchingVideoListenMode {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                        } icon: {
                            Image(systemName: "headphones")
                        }
                    }
                    .disabled(detailViewModel.isSwitchingVideoListenMode)
                }

                if !detailViewModel.isVideoListenModeEnabled {
                    NavigationLink {
                        SurfaceOnlyPictureInPictureAndBackgroundPage(
                            libraryStore: libraryStore,
                            viewModel: viewModel,
                            usesLandscapePanel: false
                        )
                    } label: {
                        Label("画中画&后台播放", systemImage: "pip")
                    }
                    .accessibilityIdentifier("ui.player.pipAndBackgroundMenu")
                }

                if showsRecoveryTestEntry && !detailViewModel.isVideoListenModeEnabled {
                    NavigationLink {
                        PlaybackRecoveryTestView(player: viewModel)
                    } label: {
                        Label("自动恢复测试", systemImage: "testtube.2")
                    }
                    .accessibilityIdentifier("recovery.test.open")
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.playerPerformanceOverlayEnabled },
                    set: { libraryStore.setPlayerPerformanceOverlayEnabled($0) }
                )) {
                    Label("播放性能诊断", systemImage: "waveform.path.ecg.rectangle")
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.playerControlEdgeScrimEnabled },
                    set: { libraryStore.setPlayerControlEdgeScrimEnabled($0) }
                )) {
                    Label("播放控件边缘遮罩", systemImage: "rectangle.topthird.inset.filled")
                }

                Label("\(mediaFormatLabel)：\(videoFormatTitle)", systemImage: mediaFormatSystemImage)
                    .foregroundStyle(.secondary)

                Label("解码：\(decodeTitle)", systemImage: "cpu")
                    .foregroundStyle(.secondary)

                Toggle(isOn: Binding(
                    get: { libraryStore.forceHardwareDecodeEnabled },
                    set: { libraryStore.setForceHardwareDecodeEnabled($0) }
                )) {
                    Label("硬解优先", systemImage: "cpu")
                }
            }
            .scrollContentBackground(.hidden)
            .listRowBackground(Color.clear)
            .listStyle(.plain)
            .background(Color.clear)
            .foregroundStyle(.primary)
            .navigationTitle("播放设置")
            .navigationBarTitleDisplayMode(.inline)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var decodeTitle: String {
        SurfaceOnlyPlaybackFormatText.decodeTitle(for: viewModel.engineDiagnostics)
    }

    private var videoFormatTitle: String {
        SurfaceOnlyPlaybackFormatText.videoFormatTitle(for: viewModel.engineDiagnostics)
    }

    private var showsVideoListenModeToggle: Bool {
        detailViewModel.isVideoListenModeEnabled || detailViewModel.canUseVideoListenMode
    }

    private var videoListenModeBinding: Binding<Bool> {
        Binding(
            get: { detailViewModel.isVideoListenModeEnabled },
            set: { detailViewModel.setVideoListenModeEnabled($0) }
        )
    }

    private var mediaFormatLabel: String {
        detailViewModel.isVideoListenModeEnabled ? "音频格式" : "视频格式"
    }

    private var mediaFormatSystemImage: String {
        detailViewModel.isVideoListenModeEnabled ? "waveform" : "film"
    }

}

private enum SurfaceOnlyPlaybackFormatText {
    static func decodeTitle(for diagnostics: PlayerEngineDiagnostics) -> String {
        var parts = [diagnostics.decodePath.title]
        if diagnostics.hardwareDecodeRequested {
            parts.append("硬解")
        }
        if let isHardwareDecodeCompatible = diagnostics.isHardwareDecodeCompatible {
            parts.append(isHardwareDecodeCompatible ? "硬解兼容" : "硬解不兼容")
        }
        return parts.joined(separator: " · ")
    }

    static func videoFormatTitle(for diagnostics: PlayerEngineDiagnostics) -> String {
        var parts = [String]()
        if let codec = diagnostics.codec, !codec.isEmpty {
            parts.append(codecDisplayName(codec))
        }
        if let resolution = diagnostics.resolution, !resolution.isEmpty {
            parts.append(resolution)
        }
        if let frameRate = diagnostics.frameRate, !frameRate.isEmpty {
            parts.append(frameRate)
        }
        if let dynamicRangeTitle = dynamicRangeTitle(for: diagnostics.dynamicRange) {
            parts.append(dynamicRangeTitle)
        }
        if !parts.isEmpty {
            return parts.joined(separator: " · ")
        }
        let description = diagnostics.compactDescription
        return description.isEmpty ? "未知" : description
    }

    private static func dynamicRangeTitle(for dynamicRange: BiliVideoDynamicRange) -> String? {
        switch dynamicRange {
        case .sdr:
            return nil
        case .hdr10:
            return "HDR"
        case .hlg:
            return "HLG"
        case .dolbyVision:
            return "杜比视界"
        }
    }

    private static func codecDisplayName(_ codec: String) -> String {
        switch codec.uppercased() {
        case "AVC":
            return "H.264 / AVC"
        case "HEVC":
            return "HEVC / H.265"
        default:
            return codec
        }
    }
}

private struct SurfaceOnlyLandscapeMoreControlsOverlay: View {
    @ObservedObject var detailViewModel: VideoDetailViewModel
    @ObservedObject var viewModel: PlayerStateViewModel
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var qualityStore: VideoDetailQualityControlRenderStore
    let selectPlayVariant: (PlayVariant) -> Void
    let onToggleDanmaku: () -> Void
    let contentInsets: EdgeInsets
    let close: () -> Void
    @State private var page: SurfaceOnlyLandscapeMoreControlsPage = .root

    var body: some View {
        GeometryReader { proxy in
            // 宽度取横屏宽度的 40%，并夹在 320...420 之间，避免超宽屏过于空旷。
            let panelWidth = min(max(proxy.size.width * 0.4, 320), 420)
            let safeArea = Self.safeAreaInsets()
            ZStack(alignment: .trailing) {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: close)

                panel(width: panelWidth, safeArea: safeArea)
                    .transition(.move(edge: .trailing))
            }
        }
    }

    /// 面板跟随 App 的深浅色设置；播放器 overlay 可能被强制为深色，这里单独决议。
    private var resolvedColorScheme: ColorScheme {
        switch libraryStore.appearanceMode {
        case .system:
            // 视频页会为状态栏对比度把窗口强制为深色，窗口 trait 不可用；
            // 屏幕 trait 反映系统外观设置。
            return UIScreen.main.traitCollection.userInterfaceStyle == .dark ? .dark : .light
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    private func panel(width: CGFloat, safeArea: EdgeInsets) -> some View {
        let scheme = resolvedColorScheme
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        let background = Color(UIColor.systemBackground.resolvedColor(with: traits))
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 0,
            style: .continuous
        )
        return VStack(spacing: 0) {
            SurfaceOnlyLandscapeMoreHeader(
                title: page.title,
                canGoBack: page != .root,
                goBack: { page = .root },
                close: close
            )

            Divider()

            SurfaceOnlyLandscapeMoreContent(
                page: $page,
                detailViewModel: detailViewModel,
                viewModel: viewModel,
                libraryStore: libraryStore,
                qualityStore: qualityStore,
                selectPlayVariant: selectPlayVariant,
                onToggleDanmaku: onToggleDanmaku,
                close: close
            )
        }
        .padding(.top, safeArea.top)
        .padding(.trailing, safeArea.trailing)
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(background)
        .clipShape(shape)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 0.6)
        }
        .environment(\.colorScheme, scheme)
    }

    private static func safeAreaInsets() -> EdgeInsets {
        guard let insets = UIApplication.shared.playbackDetailForegroundKeyWindow?.safeAreaInsets
        else { return EdgeInsets() }
        return EdgeInsets(
            top: max(insets.top, 0),
            leading: max(insets.left, 0),
            bottom: max(insets.bottom, 0),
            trailing: max(insets.right, 0)
        )
    }
}

private enum SurfaceOnlyLandscapeMoreControlsPage {
    case root
    case quality
    case audio
    case queue
    case playbackOrder
    case sleepTimer
    case danmaku
    case pictureInPictureAndBackground
    case rate

    var title: String {
        switch self {
        case .root:
            return "播放设置"
        case .quality:
            return "清晰度"
        case .audio:
            return "音质"
        case .queue:
            return "播放列表"
        case .playbackOrder:
            return "播放顺序"
        case .sleepTimer:
            return "定时关闭"
        case .danmaku:
            return "弹幕设置"
        case .pictureInPictureAndBackground:
            return "画中画&后台播放"
        case .rate:
            return "倍速"
        }
    }
}

private struct SurfaceOnlyLandscapeMoreHeader: View {
    let title: String
    let canGoBack: Bool
    let goBack: () -> Void
    let close: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)

            HStack {
                if canGoBack {
                    Button(action: goBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .contentShape(Circle())
                }

                Spacer()

                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .contentShape(Circle())
            }
        }
        .frame(height: 48)
        .padding(.horizontal, 12)
    }
}

private struct SurfaceOnlyLandscapeMoreContent: View {
    @Binding var page: SurfaceOnlyLandscapeMoreControlsPage
    @ObservedObject var detailViewModel: VideoDetailViewModel
    @ObservedObject var viewModel: PlayerStateViewModel
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var qualityStore: VideoDetailQualityControlRenderStore
    let selectPlayVariant: (PlayVariant) -> Void
    let onToggleDanmaku: () -> Void
    let close: () -> Void

    var body: some View {
        Group {
            switch page {
            case .root:
                rootPage
            case .quality:
                qualityPage
            case .audio:
                audioPage
            case .queue:
                queuePage
            case .playbackOrder:
                playbackOrderPage
            case .sleepTimer:
                sleepTimerPage
            case .danmaku:
                SurfaceOnlyDanmakuSettingsPage(
                    detailViewModel: detailViewModel,
                    toggleDanmaku: onToggleDanmaku,
                    usesLandscapePanel: true
                )
                .scrollContentBackground(.hidden)
            case .pictureInPictureAndBackground:
                SurfaceOnlyPictureInPictureAndBackgroundPage(
                    libraryStore: libraryStore,
                    viewModel: viewModel,
                    usesLandscapePanel: true
                )
            case .rate:
                ratePage
            }
        }
    }

    private var rootPage: some View {
        ScrollView {
            VStack(spacing: 10) {
                VStack(spacing: 0) {
                    if detailViewModel.isVideoListenModeEnabled,
                       !detailViewModel.videoListenAudioVariants.isEmpty {
                        SurfaceOnlyLandscapeMenuRow(
                            title: "音质",
                            systemImage: "waveform",
                            accessory: detailViewModel.videoListenAudioAccessoryTitle,
                            showsChevron: true
                        ) {
                            page = .audio
                        }

                        Divider().padding(.leading, 44)
                    } else if qualityStore.hasQualityMenu {
                        SurfaceOnlyLandscapeMenuRow(
                            title: "清晰度",
                            systemImage: qualityStore.qualityButtonSystemImage,
                            accessory: qualityStore.qualityAccessoryButtonTitle,
                            showsChevron: true
                        ) {
                            page = .quality
                        }

                        Divider().padding(.leading, 44)
                    }

                    if detailViewModel.isVideoListenModeEnabled {
                        SurfaceOnlyLandscapeMenuRow(
                            title: "播放列表",
                            systemImage: "list.bullet",
                            accessory: detailViewModel.videoListenQueueAccessoryTitle,
                            showsChevron: true
                        ) {
                            page = .queue
                        }

                        Divider().padding(.leading, 44)

                        SurfaceOnlyLandscapeMenuRow(
                            title: "播放顺序",
                            systemImage: libraryStore.videoListenPlaybackOrder.systemImage,
                            accessory: libraryStore.videoListenPlaybackOrder.title,
                            showsChevron: true
                        ) {
                            page = .playbackOrder
                        }

                        Divider().padding(.leading, 44)

                        SurfaceOnlyLandscapeMenuRow(
                            title: "定时关闭",
                            systemImage: "timer",
                            accessory: detailViewModel.videoListenSleepTimerAccessoryTitle,
                            showsChevron: true
                        ) {
                            page = .sleepTimer
                        }

                        Divider().padding(.leading, 44)
                    }

                    if !detailViewModel.isVideoListenModeEnabled {
                        SurfaceOnlyLandscapeMenuRow(
                            title: "弹幕设置",
                            systemImage: "text.bubble",
                            accessory: nil,
                            showsChevron: true
                        ) {
                            page = .danmaku
                        }

                        Divider().padding(.leading, 44)
                    }

                    SurfaceOnlyLandscapeMenuRow(
                        title: "倍速",
                        systemImage: "speedometer",
                        accessory: viewModel.playbackRate.title,
                        showsChevron: true
                    ) {
                        page = .rate
                    }

                    Divider().padding(.leading, 44)

                    if showsVideoListenModeToggle {
                        SurfaceOnlyLandscapeToggleRow(
                            title: "听视频",
                            systemImage: "headphones",
                            accessory: nil,
                            isOn: videoListenModeBinding
                        )
                        .disabled(detailViewModel.isSwitchingVideoListenMode)

                        Divider().padding(.leading, 44)
                    }

                    if !detailViewModel.isVideoListenModeEnabled {
                        SurfaceOnlyLandscapeMenuRow(
                            title: "画中画&后台播放",
                            systemImage: "pip",
                            accessory: nil,
                            showsChevron: true
                        ) {
                            page = .pictureInPictureAndBackground
                        }
                        .accessibilityIdentifier("ui.player.pipAndBackgroundMenu")

                        Divider().padding(.leading, 44)
                    }

                    SurfaceOnlyLandscapeToggleRow(
                        title: "播放性能诊断",
                        systemImage: "waveform.path.ecg.rectangle",
                        accessory: nil,
                        isOn: Binding(
                            get: { libraryStore.playerPerformanceOverlayEnabled },
                            set: { libraryStore.setPlayerPerformanceOverlayEnabled($0) }
                        )
                    )

                    Divider().padding(.leading, 44)

                    SurfaceOnlyLandscapeToggleRow(
                        title: "播放控件边缘遮罩",
                        systemImage: "rectangle.topthird.inset.filled",
                        accessory: nil,
                        isOn: Binding(
                            get: { libraryStore.playerControlEdgeScrimEnabled },
                            set: { libraryStore.setPlayerControlEdgeScrimEnabled($0) }
                        )
                    )
                }
                .surfaceOnlyLandscapeGlassGroup()

                VStack(spacing: 0) {
                    SurfaceOnlyLandscapeInfoRow(
                        title: mediaFormatLabel,
                        systemImage: mediaFormatSystemImage,
                        value: videoFormatTitle
                    )

                    Divider().padding(.leading, 44)

                    SurfaceOnlyLandscapeInfoRow(
                        title: "解码",
                        systemImage: "cpu",
                        value: decodeTitle
                    )
                }
                .surfaceOnlyLandscapeGlassGroup()
            }
            .padding(12)
        }
    }

    private var qualityPage: some View {
        ScrollView {
            VStack(spacing: 10) {
                if qualityStore.isSwitchingPlayQuality {
                    SurfaceOnlyQualitySwitchingIndicator()
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .surfaceOnlyLandscapeGlassGroup()
                }

                VStack(spacing: 0) {
                    ForEach(Array(qualityStore.qualityMenuItems.enumerated()), id: \.element.id) { index, item in
                        SurfaceOnlyLandscapeMenuRow(
                            title: item.title,
                            subtitle: item.subtitle,
                            systemImage: item.systemImage,
                            accessory: nil,
                            showsChevron: false
                        ) {
                            selectPlayVariant(item.variant)
                            close()
                        }
                        .disabled(item.isDisabled)
                        .opacity(item.isDisabled ? 0.45 : 1)

                        if index < qualityStore.qualityMenuItems.count - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .surfaceOnlyLandscapeGlassGroup()
            }
            .padding(12)
        }
    }

    private var audioPage: some View {
        ScrollView {
            VStack(spacing: 10) {
                if detailViewModel.isSwitchingVideoListenMode {
                    SurfaceOnlyAudioSwitchingIndicator()
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .surfaceOnlyLandscapeGlassGroup()
                }

                VStack(spacing: 0) {
                    SurfaceOnlyLandscapeMenuRow(
                        title: "自动",
                        subtitle: automaticAudioSubtitle,
                        systemImage: detailViewModel.selectedVideoListenAudioPreferenceKey == nil
                            ? "checkmark"
                            : "wand.and.stars",
                        accessory: nil,
                        showsChevron: false
                    ) {
                        detailViewModel.selectVideoListenAudioVariant(nil)
                        close()
                    }

                    if !detailViewModel.videoListenAudioVariants.isEmpty {
                        Divider().padding(.leading, 44)
                    }

                    ForEach(Array(detailViewModel.videoListenAudioVariants.enumerated()), id: \.element.id) { index, variant in
                        SurfaceOnlyLandscapeMenuRow(
                            title: variant.title,
                            subtitle: variant.subtitle,
                            systemImage: detailViewModel.selectedVideoListenAudioPreferenceKey == variant.preferenceKey
                                ? "checkmark"
                                : variant.systemImage,
                            accessory: nil,
                            showsChevron: false
                        ) {
                            detailViewModel.selectVideoListenAudioVariant(variant)
                            close()
                        }

                        if index < detailViewModel.videoListenAudioVariants.count - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .surfaceOnlyLandscapeGlassGroup()
            }
            .padding(12)
        }
    }

    private var ratePage: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(BiliPlaybackRate.allCases.enumerated()), id: \.element.id) { index, rate in
                    SurfaceOnlyLandscapeMenuRow(
                        title: rate.title,
                        systemImage: rate == viewModel.playbackRate ? "checkmark" : "speedometer",
                        accessory: nil,
                        showsChevron: false
                    ) {
                        viewModel.setPlaybackRate(rate)
                        close()
                    }

                    if index < BiliPlaybackRate.allCases.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .surfaceOnlyLandscapeGlassGroup()
            .padding(12)
        }
    }

    private var queuePage: some View {
        ScrollView {
            if detailViewModel.videoListenQueueEntries.isEmpty {
                VStack(spacing: 10) {
                    if detailViewModel.isLoadingVideoListenQueue {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在载入播放列表")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(detailViewModel.videoListenQueueLoadFailed ? "播放列表载入失败" : "没有可播放内容")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if detailViewModel.videoListenQueueLoadFailed {
                            Button("重新载入") {
                                Task {
                                    await detailViewModel.prepareVideoListenQueue()
                                }
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .surfaceOnlyLandscapeGlassGroup()
                .padding(12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(detailViewModel.videoListenQueueEntries.enumerated()), id: \.element.id) { index, entry in
                        SurfaceOnlyLandscapeMenuRow(
                            title: entry.title,
                            subtitle: entry.subtitle,
                            systemImage: entry.isCurrent ? "checkmark.circle.fill" : "play.circle",
                            accessory: entry.isCurrent ? "正在播放" : nil,
                            showsChevron: false
                        ) {
                            detailViewModel.selectVideoListenQueueEntry(entry)
                            close()
                        }
                        .task {
                            await detailViewModel.loadMoreVideoListenQueueIfNeeded(current: entry)
                        }

                        if index < detailViewModel.videoListenQueueEntries.count - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }

                    if detailViewModel.isLoadingVideoListenQueue {
                        Divider().padding(.leading, 44)
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在载入更多视频")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    } else if detailViewModel.videoListenQueueLoadFailed,
                              detailViewModel.videoListenQueueEntries.count <= 1 {
                        Divider().padding(.leading, 44)
                        Button("重新载入播放列表") {
                            Task {
                                await detailViewModel.prepareVideoListenQueue()
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    } else if detailViewModel.videoListenQueueSession.isLoadingMore {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .surfaceOnlyLandscapeGlassGroup()
                .padding(12)
            }
        }
        .task {
            await detailViewModel.prepareVideoListenQueue()
        }
    }

    private var playbackOrderPage: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(VideoListenPlaybackOrder.allCases.enumerated()), id: \.element.id) { index, order in
                    SurfaceOnlyLandscapeMenuRow(
                        title: order.title,
                        subtitle: order.subtitle,
                        systemImage: libraryStore.videoListenPlaybackOrder == order
                            ? "checkmark.circle.fill"
                            : order.systemImage,
                        accessory: nil,
                        showsChevron: false
                    ) {
                        libraryStore.setVideoListenPlaybackOrder(order)
                        close()
                    }

                    if index < VideoListenPlaybackOrder.allCases.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .surfaceOnlyLandscapeGlassGroup()
            .padding(12)
        }
    }

    private var sleepTimerPage: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(VideoListenSleepTimerOption.allCases.enumerated()), id: \.element.id) { index, option in
                    SurfaceOnlyLandscapeMenuRow(
                        title: option.title,
                        systemImage: detailViewModel.videoListenSleepTimerOption == option
                            ? "checkmark.circle.fill"
                            : option.systemImage,
                        accessory: nil,
                        showsChevron: false
                    ) {
                        detailViewModel.setVideoListenSleepTimer(option)
                        close()
                    }

                    if index < VideoListenSleepTimerOption.allCases.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .surfaceOnlyLandscapeGlassGroup()
            .padding(12)
        }
    }

    private var decodeTitle: String {
        SurfaceOnlyPlaybackFormatText.decodeTitle(for: viewModel.engineDiagnostics)
    }

    private var videoFormatTitle: String {
        SurfaceOnlyPlaybackFormatText.videoFormatTitle(for: viewModel.engineDiagnostics)
    }

    private var showsVideoListenModeToggle: Bool {
        detailViewModel.isVideoListenModeEnabled || detailViewModel.canUseVideoListenMode
    }

    private var videoListenModeBinding: Binding<Bool> {
        Binding(
            get: { detailViewModel.isVideoListenModeEnabled },
            set: { detailViewModel.setVideoListenModeEnabled($0) }
        )
    }

    private var automaticAudioSubtitle: String {
        guard let variant = detailViewModel.automaticVideoListenAudioVariant else {
            return "优先选择兼容性较好的音轨"
        }
        return ["当前 \(variant.title)", variant.subtitle]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var mediaFormatLabel: String {
        detailViewModel.isVideoListenModeEnabled ? "音频格式" : "视频格式"
    }

    private var mediaFormatSystemImage: String {
        detailViewModel.isVideoListenModeEnabled ? "waveform" : "film"
    }

}

private struct SurfaceOnlyLandscapeToggleRow: View {
    let title: String
    let systemImage: String
    let accessory: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let accessory {
                    Text(accessory)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(minHeight: 44)
            .padding(.leading, 12)
        }
        .toggleStyle(.switch)
        .padding(.trailing, 12)
        .contentShape(Rectangle())
    }
}

struct SurfaceOnlyLandscapeMenuRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let accessory: String?
    let showsChevron: Bool
    let action: () -> Void

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        accessory: String?,
        showsChevron: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.accessory = accessory
        self.showsChevron = showsChevron
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if let accessory {
                    Text(accessory)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SurfaceOnlyLandscapeInfoRow: View {
    let title: String
    let systemImage: String
    let value: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let value {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 12)
    }
}

private struct SurfaceOnlyQualityChoicesPage: View {
    @ObservedObject var qualityStore: VideoDetailQualityControlRenderStore
    let closeSheet: () -> Void
    let selectPlayVariant: (PlayVariant) -> Void

    var body: some View {
        List {
            if qualityStore.isSwitchingPlayQuality {
                SurfaceOnlyQualitySwitchingIndicator()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            ForEach(qualityStore.qualityMenuItems) { item in
                Button {
                    selectPlayVariant(item.variant)
                    closeSheet()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                            if let subtitle = item.subtitle, !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: item.systemImage)
                    }
                }
                .disabled(item.isDisabled)
                .opacity(item.isDisabled ? 0.45 : 1)
            }
        }
        .scrollContentBackground(.hidden)
        .listRowBackground(Color.clear)
        .listStyle(.plain)
        .background(Color.clear)
        .foregroundStyle(.primary)
        .navigationTitle("清晰度")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.automatic, for: .navigationBar)
    }
}

private struct SurfaceOnlyAudioChoicesPage: View {
    @ObservedObject var detailViewModel: VideoDetailViewModel
    let closeSheet: () -> Void

    var body: some View {
        List {
            if detailViewModel.isSwitchingVideoListenMode {
                SurfaceOnlyAudioSwitchingIndicator()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            Button {
                detailViewModel.selectVideoListenAudioVariant(nil)
                closeSheet()
            } label: {
                audioChoiceLabel(
                    title: "自动",
                    subtitle: automaticSubtitle,
                    systemImage: detailViewModel.selectedVideoListenAudioPreferenceKey == nil
                        ? "checkmark"
                        : "wand.and.stars"
                )
            }

            ForEach(detailViewModel.videoListenAudioVariants) { variant in
                Button {
                    detailViewModel.selectVideoListenAudioVariant(variant)
                    closeSheet()
                } label: {
                    audioChoiceLabel(
                        title: variant.title,
                        subtitle: variant.subtitle,
                        systemImage: detailViewModel.selectedVideoListenAudioPreferenceKey == variant.preferenceKey
                            ? "checkmark"
                            : variant.systemImage
                    )
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listRowBackground(Color.clear)
        .listStyle(.plain)
        .background(Color.clear)
        .foregroundStyle(.primary)
        .navigationTitle("音质")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.automatic, for: .navigationBar)
    }

    private func audioChoiceLabel(
        title: String,
        subtitle: String,
        systemImage: String
    ) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: systemImage)
        }
    }

    private var automaticSubtitle: String {
        guard let variant = detailViewModel.automaticVideoListenAudioVariant else {
            return "优先选择兼容性较好的音轨"
        }
        return ["当前 \(variant.title)", variant.subtitle]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

private struct SurfaceOnlyVideoListenQueuePage: View {
    @ObservedObject var detailViewModel: VideoDetailViewModel
    let closeSheet: () -> Void

    var body: some View {
        List {
            if detailViewModel.videoListenQueueEntries.isEmpty {
                VStack(spacing: 10) {
                    if detailViewModel.isLoadingVideoListenQueue {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在载入播放列表")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(detailViewModel.videoListenQueueLoadFailed ? "播放列表载入失败" : "没有可播放内容")
                            .foregroundStyle(.secondary)
                        if detailViewModel.videoListenQueueLoadFailed {
                            Button("重新载入") {
                                Task {
                                    await detailViewModel.prepareVideoListenQueue()
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                ForEach(detailViewModel.videoListenQueueEntries) { entry in
                    Button {
                        detailViewModel.selectVideoListenQueueEntry(entry)
                        closeSheet()
                    } label: {
                        Label {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title)
                                    if let subtitle = entry.subtitle {
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if entry.isCurrent {
                                    Text("正在播放")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: entry.isCurrent ? "checkmark.circle.fill" : "play.circle")
                        }
                    }
                    .task {
                        await detailViewModel.loadMoreVideoListenQueueIfNeeded(current: entry)
                    }
                }

                if detailViewModel.isLoadingVideoListenQueue {
                    HStack(spacing: 8) {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Text("正在载入更多视频")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else if detailViewModel.videoListenQueueLoadFailed,
                          detailViewModel.videoListenQueueEntries.count <= 1 {
                    Button("重新载入播放列表") {
                        Task {
                            await detailViewModel.prepareVideoListenQueue()
                        }
                    }
                    .frame(maxWidth: .infinity)
                } else if detailViewModel.videoListenQueueSession.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Spacer()
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listRowBackground(Color.clear)
        .listStyle(.plain)
        .background(Color.clear)
        .foregroundStyle(.primary)
        .navigationTitle("播放列表")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.automatic, for: .navigationBar)
        .task {
            await detailViewModel.prepareVideoListenQueue()
        }
    }
}

private struct SurfaceOnlyVideoListenPlaybackOrderPage: View {
    @ObservedObject var libraryStore: LibraryStore
    let closeSheet: () -> Void

    var body: some View {
        List {
            ForEach(VideoListenPlaybackOrder.allCases) { order in
                Button {
                    libraryStore.setVideoListenPlaybackOrder(order)
                    closeSheet()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(order.title)
                            Text(order.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: libraryStore.videoListenPlaybackOrder == order
                            ? "checkmark.circle.fill"
                            : order.systemImage)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listRowBackground(Color.clear)
        .listStyle(.plain)
        .background(Color.clear)
        .foregroundStyle(.primary)
        .navigationTitle("播放顺序")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.automatic, for: .navigationBar)
    }
}

private struct SurfaceOnlyVideoListenSleepTimerPage: View {
    @ObservedObject var detailViewModel: VideoDetailViewModel
    let closeSheet: () -> Void

    var body: some View {
        List {
            ForEach(VideoListenSleepTimerOption.allCases) { option in
                Button {
                    detailViewModel.setVideoListenSleepTimer(option)
                    closeSheet()
                } label: {
                    Label(
                        option.title,
                        systemImage: detailViewModel.videoListenSleepTimerOption == option
                            ? "checkmark.circle.fill"
                            : option.systemImage
                    )
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listRowBackground(Color.clear)
        .listStyle(.plain)
        .background(Color.clear)
        .foregroundStyle(.primary)
        .navigationTitle("定时关闭")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.automatic, for: .navigationBar)
    }
}

private struct SurfaceOnlyQualitySwitchingIndicator: View {
    var body: some View {
        PlayerInlineLoadingIndicator(message: "正在切换清晰度")
            .accessibilityLabel("正在切换清晰度")
    }
}

private struct SurfaceOnlyAudioSwitchingIndicator: View {
    var body: some View {
        PlayerInlineLoadingIndicator(message: "正在切换音质")
            .accessibilityLabel("正在切换音质")
    }
}

private struct SurfaceOnlyDanmakuSettingsPage: View {
    @ObservedObject var detailViewModel: VideoDetailViewModel
    let toggleDanmaku: () -> Void
    let usesLandscapePanel: Bool

    var body: some View {
        Group {
            if usesLandscapePanel {
                DanmakuSettingsLandscapePanelContent(
                    store: detailViewModel.danmakuSettingsRenderStore,
                    summary: settingsSummary,
                    hidesDanmakuInPortraitBinding: hidesDanmakuInPortraitBinding,
                    toggleDanmaku: toggleDanmaku,
                    updateDanmakuSettings: { detailViewModel.updateDanmakuSettings($0) }
                )
            } else {
                DanmakuSettingsSheetContent(
                    store: detailViewModel.danmakuSettingsRenderStore,
                    summary: settingsSummary,
                    hidesDanmakuInPortraitBinding: hidesDanmakuInPortraitBinding,
                    toggleDanmaku: toggleDanmaku,
                    updateDanmakuSettings: { detailViewModel.updateDanmakuSettings($0) }
                )
                .navigationTitle("弹幕设置")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private var settingsSummary: String {
        let store = detailViewModel.danmakuSettingsRenderStore
        if store.isDanmakuEnabled {
            return store.danmakuSettings.danmakuKit.summaryDescription
        }
        return "弹幕已关闭，播放时不会显示滚动评论。"
    }

    private var hidesDanmakuInPortraitBinding: Binding<Bool> {
        Binding(
            get: { detailViewModel.danmakuSettingsRenderStore.danmakuSettings.hidesInPortrait },
            set: { newValue in
                var settings = detailViewModel.danmakuSettingsRenderStore.danmakuSettings
                settings.hidesInPortrait = newValue
                detailViewModel.updateDanmakuSettings(settings)
            }
        )
    }

}

private struct SurfaceOnlyPictureInPictureAndBackgroundPage: View {
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var viewModel: PlayerStateViewModel
    let usesLandscapePanel: Bool

    var body: some View {
        if usesLandscapePanel {
            ScrollView {
                VStack(spacing: 10) {
                    VStack(spacing: 0) {
                        SurfaceOnlyLandscapeToggleRow(
                            title: "应用外画中画播放",
                            systemImage: "pip",
                            accessory: nil,
                            isOn: outsideAppPictureInPictureBinding
                        )
                        .accessibilityIdentifier("ui.player.pictureInPicture")

                        Divider().padding(.leading, 44)

                        SurfaceOnlyLandscapeToggleRow(
                            title: "应用内画中画播放",
                            systemImage: "pip.enter",
                            accessory: nil,
                            isOn: inAppPictureInPictureOnExitBinding
                        )
                        .accessibilityIdentifier("ui.player.autoPictureInPictureOnExit")

                        Divider().padding(.leading, 44)

                        SurfaceOnlyLandscapeToggleRow(
                            title: "后台播放",
                            systemImage: "speaker.wave.2",
                            accessory: nil,
                            isOn: backgroundPlaybackBinding
                        )
                        .accessibilityIdentifier("ui.player.backgroundPlayback")
                    }
                    .surfaceOnlyLandscapeGlassGroup()
                }
                .padding(12)
            }
        } else {
            Form {
                Section {
                    Toggle(isOn: outsideAppPictureInPictureBinding) {
                        Label("应用外画中画播放", systemImage: "pip")
                    }
                    .accessibilityIdentifier("ui.player.pictureInPicture")

                    Toggle(isOn: inAppPictureInPictureOnExitBinding) {
                        Label("应用内画中画播放", systemImage: "pip.enter")
                    }
                    .accessibilityIdentifier("ui.player.autoPictureInPictureOnExit")

                    Toggle(isOn: backgroundPlaybackBinding) {
                        Label("后台播放", systemImage: "speaker.wave.2")
                    }
                    .accessibilityIdentifier("ui.player.backgroundPlayback")
                } footer: {
                    Text("应用外画中画会在切出 App 时自动开启系统小窗；应用内画中画会在播放中退出视频页时以小窗继续播放。")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("画中画&后台播放")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var outsideAppPictureInPictureBinding: Binding<Bool> {
        Binding(
            get: { libraryStore.pictureInPictureEnabled },
            set: { libraryStore.setPictureInPictureEnabled($0) }
        )
    }

    private var inAppPictureInPictureOnExitBinding: Binding<Bool> {
        Binding(
            get: { libraryStore.autoPictureInPictureOnExitEnabled },
            set: { libraryStore.setAutoPictureInPictureOnExitEnabled($0) }
        )
    }

    private var backgroundPlaybackBinding: Binding<Bool> {
        Binding(
            get: { libraryStore.backgroundPlaybackEnabled },
            set: {
                libraryStore.setBackgroundPlaybackEnabled($0)
                viewModel.setBackgroundPlaybackEnabled($0)
            }
        )
    }
}

private struct SurfaceOnlyUIKitMoreControlsButton: UIViewRepresentable {
    let metrics: PlayerNativeControlMetrics
    let systemImageName: String
    let onPressBegan: () -> Void
    let onPressEnded: () -> Void
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onPressBegan: onPressBegan,
            onPressEnded: onPressEnded,
            action: action
        )
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(
            configuration: configuration,
            primaryAction: context.coordinator.primaryAction
        )
        configure(button)
        button.addAction(context.coordinator.pressBeganAction, for: .touchDown)
        button.addAction(
            context.coordinator.pressEndedAction,
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )
        button.accessibilityLabel = "更多播放设置"
        button.accessibilityIdentifier = "ui.player.more"
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.onPressBegan = onPressBegan
        context.coordinator.onPressEnded = onPressEnded
        context.coordinator.action = action
        configure(button)
    }

    private var configuration: UIButton.Configuration {
        // The owning SwiftUI view supplies the glass; UIKit only owns touch delivery.
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = .white
        configuration.contentInsets = .zero
        return configuration
    }

    private func configure(_ button: UIButton) {
        button.configuration = configuration
        button.tintColor = .white

        let iconView: UIImageView
        if let existingIconView = button.viewWithTag(Self.iconViewTag) as? UIImageView {
            iconView = existingIconView
        } else {
            iconView = UIImageView()
            iconView.tag = Self.iconViewTag
            iconView.contentMode = .center
            iconView.tintColor = .white
            iconView.isUserInteractionEnabled = false
            iconView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(iconView)
            NSLayoutConstraint.activate([
                iconView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                iconView.centerYAnchor.constraint(equalTo: button.centerYAnchor)
            ])
        }

        iconView.image = UIImage(
            systemName: systemImageName,
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: metrics.iconSize + 3,
                weight: .semibold
            )
        )
    }

    private static let iconViewTag = 1_634_081

    final class Coordinator {
        var onPressBegan: () -> Void
        var onPressEnded: () -> Void
        var action: () -> Void

        init(
            onPressBegan: @escaping () -> Void,
            onPressEnded: @escaping () -> Void,
            action: @escaping () -> Void
        ) {
            self.onPressBegan = onPressBegan
            self.onPressEnded = onPressEnded
            self.action = action
        }

        lazy var pressBeganAction = UIAction { [weak self] _ in
            self?.onPressBegan()
        }

        lazy var pressEndedAction = UIAction { [weak self] _ in
            self?.onPressEnded()
        }

        lazy var primaryAction = UIAction { [weak self] _ in
            self?.action()
        }
    }
}

private extension View {
    /// 设置抽屉内的分组容器：面板已是纯色，分组不再叠液态玻璃。
    @ViewBuilder
    func surfaceOnlyLandscapeGlassGroup() -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        self
            .background(Color(.secondarySystemGroupedBackground), in: shape)
    }
}

private struct SurfaceOnlyRateChoicesPage: View {
    @ObservedObject var viewModel: PlayerStateViewModel
    let closeSheet: () -> Void

    var body: some View {
        List {
            ForEach(BiliPlaybackRate.allCases) { rate in
                Button {
                    viewModel.setPlaybackRate(rate)
                    closeSheet()
                } label: {
                    Label(
                        rate.title,
                        systemImage: rate == viewModel.playbackRate ? "checkmark" : "speedometer"
                    )
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listRowBackground(Color.clear)
        .listStyle(.plain)
        .background(Color.clear)
        .foregroundStyle(.primary)
        .navigationTitle("倍速")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.automatic, for: .navigationBar)
    }
}
