import AVFoundation
import Combine
import SwiftUI
import UIKit

/// 详情页 UIKit 外壳：播放器宿主（surface-only + 独立控件浮层）。
///
/// 对齐原型：UIKit 容器只驱动 frame，SwiftUI 根视图里直接铺 `VideoSurfaceView`，
/// 控件/手势/加载态作为 overlay 叠上去，不再让完整 `BiliPlayerView` 的
/// presentation 切换参与旋转。
@MainActor
final class VideoDetailShellSurfaceHost: UIView {
    @MainActor
    final class State: ObservableObject {
        @Published var isLandscape = false
        @Published var isBareSurfaceTransitionActive = false
        @Published var playerViewModel: PlayerStateViewModel
        @Published var videoAspectRatio: CGFloat = 16.0 / 9.0

        init(playerViewModel: PlayerStateViewModel) {
            self.playerViewModel = playerViewModel
        }
    }

    private let state: State
    private let surfaceHostView: UIKitPlayerSurfaceHostView
    private let overlayHostingController: UIHostingController<PlayerOverlayHostRoot>

    init(
        playerViewModel: PlayerStateViewModel,
        detailViewModel: VideoDetailViewModel,
        dependencies: AppDependencies,
        onRequestFullscreen: @escaping () -> Void,
        onExitFullscreen: @escaping () -> Void,
        onToggleDanmaku: @escaping () -> Void,
        onShowDanmakuSettings: @escaping () -> Void,
        onNavigateBack: @escaping () -> Void
    ) {
        let state = State(playerViewModel: playerViewModel)
        self.state = state
        self.surfaceHostView = UIKitPlayerSurfaceHostView(
            viewModel: playerViewModel,
            isPictureInPictureEnabled: dependencies.libraryStore.pictureInPictureEnabled
        )
        let overlayRoot = PlayerOverlayHostRoot(
            detailViewModel: detailViewModel,
            state: state,
            dependencies: dependencies,
            onRequestFullscreen: onRequestFullscreen,
            onExitFullscreen: onExitFullscreen,
            onToggleDanmaku: onToggleDanmaku,
            onShowDanmakuSettings: onShowDanmakuSettings,
            onNavigateBack: onNavigateBack
        )
        self.overlayHostingController = UIHostingController(rootView: overlayRoot)
        super.init(frame: .zero)

        backgroundColor = .black
        overlayHostingController.view.backgroundColor = .clear
        overlayHostingController.view.isOpaque = false
        if #available(iOS 16.4, *) {
            overlayHostingController.safeAreaRegions = []
        }
        surfaceHostView.translatesAutoresizingMaskIntoConstraints = false
        surfaceHostView.isUserInteractionEnabled = false
        overlayHostingController.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surfaceHostView)
        addSubview(overlayHostingController.view)
        NSLayoutConstraint.activate([
            surfaceHostView.leadingAnchor.constraint(equalTo: leadingAnchor),
            surfaceHostView.trailingAnchor.constraint(equalTo: trailingAnchor),
            surfaceHostView.topAnchor.constraint(equalTo: topAnchor),
            surfaceHostView.bottomAnchor.constraint(equalTo: bottomAnchor),
            overlayHostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlayHostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlayHostingController.view.topAnchor.constraint(equalTo: topAnchor),
            overlayHostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attach(to parent: UIViewController) {
        surfaceHostView.attach(to: parent)
        parent.addChild(overlayHostingController)
        overlayHostingController.didMove(toParent: parent)
    }

    /// 容器 VC 旋转时调用，切换横屏/竖屏控件形态。
    func setLandscape(_ landscape: Bool) {
        guard state.isLandscape != landscape else { return }
        state.isLandscape = landscape
    }

    /// 系统旋转期间退化成原型同款 bare surface：只保留 live video surface。
    func setBareSurfaceTransitionActive(_ active: Bool) {
        state.isBareSurfaceTransitionActive = active
        UIView.performWithoutAnimation {
            overlayHostingController.view.isHidden = active
            overlayHostingController.view.isUserInteractionEnabled = !active
            overlayHostingController.view.removeLayerAnimationsRecursively()
        }
    }

    func refreshLayoutImmediately() {
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

    /// 清晰度切换等场景会重建 player 实例，需让 surface-only 根视图重建运行时状态。
    func setPlayerViewModel(_ playerViewModel: PlayerStateViewModel) {
        guard state.playerViewModel !== playerViewModel else { return }
        state.playerViewModel = playerViewModel
        surfaceHostView.setPlayerViewModel(playerViewModel)
    }

    func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        surfaceHostView.setVideoGravity(gravity)
    }

    func setVideoAspectRatio(_ aspectRatio: CGFloat) {
        guard aspectRatio > 0.1, abs(state.videoAspectRatio - aspectRatio) > 0.001 else { return }
        state.videoAspectRatio = aspectRatio
    }

}

private extension UIView {
    func removeLayerAnimationsRecursively() {
        layer.removeAllAnimations()
        subviews.forEach { $0.removeLayerAnimationsRecursively() }
    }
}

private struct PlayerOverlayHostRoot: View {
    @ObservedObject var detailViewModel: VideoDetailViewModel
    @ObservedObject var state: VideoDetailShellSurfaceHost.State
    let dependencies: AppDependencies
    let onRequestFullscreen: () -> Void
    let onExitFullscreen: () -> Void
    let onToggleDanmaku: () -> Void
    let onShowDanmakuSettings: () -> Void
    let onNavigateBack: () -> Void

    var body: some View {
        SurfaceOnlyPlayerOverlayRoot(
            viewModel: state.playerViewModel,
            detailViewModel: detailViewModel,
            dependencies: dependencies,
            isLandscape: state.isLandscape,
            isBareSurfaceTransitionActive: state.isBareSurfaceTransitionActive,
            videoAspectRatio: state.videoAspectRatio,
            isDanmakuEnabled: detailViewModel.isDanmakuEnabled,
            onToggleDanmaku: onToggleDanmaku,
            onShowDanmakuSettings: onShowDanmakuSettings,
            onNavigateBack: onNavigateBack,
            onRequestFullscreen: onRequestFullscreen,
            onExitFullscreen: onExitFullscreen
        )
        .id(ObjectIdentifier(state.playerViewModel))
        .ignoresSafeArea()
    }
}

private struct SurfaceOnlyPlayerOverlayRoot: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @ObservedObject var viewModel: PlayerStateViewModel
    @ObservedObject var detailViewModel: VideoDetailViewModel
    @ObservedObject var libraryStore: LibraryStore

    let dependencies: AppDependencies
    let isLandscape: Bool
    let isBareSurfaceTransitionActive: Bool
    let videoAspectRatio: CGFloat
    let isDanmakuEnabled: Bool
    let onToggleDanmaku: () -> Void
    let onShowDanmakuSettings: () -> Void
    let onNavigateBack: () -> Void
    let onRequestFullscreen: () -> Void
    let onExitFullscreen: () -> Void

    @StateObject private var surfaceState: PlayerSurfaceStateModel
    @StateObject private var playbackControlsVisibility = PlayerPlaybackControlsVisibilityModel()
    @StateObject private var rotationTransitionSnapshotModel = PlayerRotationTransitionSnapshotModel()
    @StateObject private var seekTransitionSnapshotModel = PlayerRotationTransitionSnapshotModel()
    @StateObject private var speedBoostModel = PlayerSpeedBoostModel()
    @StateObject private var playbackProgressCoordinator = PlayerPlaybackProgressCoordinator()
    @StateObject private var progressReporter = PlayerPlaybackProgressReporter()
    @State private var lastPreparedScrubProgress = -1.0
    @State private var isMoreControlsPresented = false
    @State private var isMoreControlsSheetPresented = false

    init(
        viewModel: PlayerStateViewModel,
        detailViewModel: VideoDetailViewModel,
        dependencies: AppDependencies,
        isLandscape: Bool,
        isBareSurfaceTransitionActive: Bool,
        videoAspectRatio: CGFloat,
        isDanmakuEnabled: Bool,
        onToggleDanmaku: @escaping () -> Void,
        onShowDanmakuSettings: @escaping () -> Void,
        onNavigateBack: @escaping () -> Void,
        onRequestFullscreen: @escaping () -> Void,
        onExitFullscreen: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.detailViewModel = detailViewModel
        self.dependencies = dependencies
        self.libraryStore = dependencies.libraryStore
        self.isLandscape = isLandscape
        self.isBareSurfaceTransitionActive = isBareSurfaceTransitionActive
        self.videoAspectRatio = videoAspectRatio
        self.isDanmakuEnabled = isDanmakuEnabled
        self.onToggleDanmaku = onToggleDanmaku
        self.onShowDanmakuSettings = onShowDanmakuSettings
        self.onNavigateBack = onNavigateBack
        self.onRequestFullscreen = onRequestFullscreen
        self.onExitFullscreen = onExitFullscreen
        _surfaceState = StateObject(wrappedValue: PlayerSurfaceStateModel(viewModel: viewModel))
    }

    var body: some View {
        let context = runtimeContext
        let renderContext = context.renderContext
        let renderState = BiliPlayerViewRenderState(
            context: renderContext,
            verticalSizeClass: verticalSizeClass
        )
        let visibilityActions = renderState.visibilityActions
        let speedActions = renderState.speedBoostActions

        GeometryReader { proxy in
            let videoInsets = visibleVideoInsets(in: proxy.size)
            let chromeState = surfaceChromeState(
                context: renderContext,
                renderState: renderState,
                contentInsets: videoInsets
            )

            ZStack {
                if !isBareSurfaceTransitionActive {
                    BiliPlayerSurfaceGestureLayerHost(
                        content: Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity),
                        visibilityActions: visibilityActions,
                        speedBoostActions: speedActions,
                        viewModel: viewModel
                    )
                    .zIndex(1)

                    BiliPlayerSurfaceOverlayLayer(state: chromeState)
                        .zIndex(2)

                    VideoDetailPlayerSurfaceDanmakuLayer(
                        store: detailViewModel.danmakuRenderStore,
                        playerViewModel: viewModel,
                        usesLandscapePlaybackChrome: configuration.isFullscreenActive,
                        onPlaybackTime: { detailViewModel.updateDanmakuPlaybackTime($0, underLoad: $1) }
                    )
                    .allowsHitTesting(false)
                    .zIndex(2.5)

                    BiliPlayerControlsOverlayLayer(
                        state: chromeState,
                        playbackControls: AnyView(
                            BiliPlayerNativeControlsHost(
                                context: renderContext,
                                renderState: renderState
                            )
                        )
                    )
                    .zIndex(3)

                    persistentMoreControlsButton(contentInsets: videoInsets)

                    if isLandscape, isMoreControlsPresented {
                        SurfaceOnlyLandscapeMoreControlsOverlay(
                            detailViewModel: detailViewModel,
                            viewModel: viewModel,
                            qualityStore: detailViewModel.playbackRenderStore.qualityControlStore,
                            selectPlayVariant: { detailViewModel.selectPlayVariant($0) },
                            onToggleDanmaku: onToggleDanmaku,
                            contentInsets: videoInsets,
                            close: { isMoreControlsPresented = false }
                        )
                        .transition(.opacity)
                        .zIndex(9)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .environmentObject(dependencies)
        .environmentObject(libraryStore)
        .biliPlayerLifecycle(
            isFullscreenActive: configuration.isFullscreenActive,
            presentation: configuration.presentation,
            isLayoutTransitioning: configuration.isLayoutTransitioning,
            isSecondaryControlsPresented: configuration.isSecondaryControlsPresented,
            isPictureInPictureEnabled: libraryStore.pictureInPictureEnabled,
            actions: context.lifecycleActions
        )
        .onAppear {
            detailViewModel.scheduleDanmakuLoadIfNeeded()
        }
        .onChange(of: isLandscape) { _, isLandscape in
            if isLandscape {
                isMoreControlsSheetPresented = false
            } else {
                isMoreControlsPresented = false
            }
        }
        .onChange(of: isBareSurfaceTransitionActive) { _, isActive in
            guard isActive else { return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isMoreControlsPresented = false
                isMoreControlsSheetPresented = false
            }
            playbackControlsVisibility.cancelAutoHide()
        }
        .onChange(of: surfaceState.isUserSeeking) { _, isUserSeeking in
            updateSeekTransitionSnapshot(isUserSeeking: isUserSeeking)
        }
        .sheet(isPresented: $isMoreControlsSheetPresented) {
            SurfaceOnlyMoreControlsSheet(
                detailViewModel: detailViewModel,
                viewModel: viewModel,
                qualityStore: detailViewModel.playbackRenderStore.qualityControlStore,
                selectPlayVariant: { detailViewModel.selectPlayVariant($0) },
                onToggleDanmaku: onToggleDanmaku
            )
        }
    }

    private var backButton: some View {
        VideoDetailPlayerSurfaceBackButtonHost(action: handleBackButton)
            .environment(\.playerNativeControlMetrics, controlMetrics)
    }

    private func handleBackButton() {
        if fullscreenMode != nil {
            onExitFullscreen()
        } else {
            onNavigateBack()
        }
    }

    private var fullscreenMode: PlayerFullscreenMode? {
        isLandscape ? .landscape(.landscapeRight) : nil
    }

    private var configuration: BiliPlayerViewConfiguration {
        BiliPlayerViewOptions(
            presentation: isLandscape ? .fullScreen : .embedded,
            showsNavigationChrome: false,
            showsPlaybackControls: !isBareSurfaceTransitionActive,
            showsStartupLoadingIndicator: !isBareSurfaceTransitionActive,
            pausesOnDisappear: false,
            topLeadingControlsAccessory: isBareSurfaceTransitionActive ? nil : AnyView(backButton),
            isDanmakuEnabled: !isBareSurfaceTransitionActive && isDanmakuEnabled,
            onToggleDanmaku: onToggleDanmaku,
            onShowDanmakuSettings: onShowDanmakuSettings,
            isSecondaryControlsPresented: !isBareSurfaceTransitionActive
                && (isMoreControlsPresented || isMoreControlsSheetPresented),
            ignoresContainerSafeArea: true,
            keepsPlayerSurfaceStable: true,
            fullscreenMode: fullscreenMode,
            isLayoutTransitioning: isBareSurfaceTransitionActive,
            usesLiveSurfaceDuringLayoutTransition: true,
            disablesSurfaceImplicitLayoutAnimations: true,
            showsRotationTransitionSnapshot: false,
            onRequestFullscreen: onRequestFullscreen,
            onExitFullscreen: onExitFullscreen
        ).configuration()
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
            speedBoostModel: speedBoostModel,
            playbackProgressCoordinator: playbackProgressCoordinator,
            progressReporter: progressReporter,
            historyVideo: nil,
            historyCID: nil,
            historyDuration: nil,
            configuration: configuration,
            isPictureInPictureEnabled: libraryStore.pictureInPictureEnabled,
            videoGravity: .resizeAspect,
            holdCurrentFrameForSeek: holdCurrentFrameForSeek,
            prepareUserSeekWarmup: prepareUserSeekWarmupIfNeeded,
            resetPreparedScrubProgress: { lastPreparedScrubProgress = -1 }
        ).context
    }

    private var moreControlsButton: some View {
        Button {
            playbackControlsVisibility.cancelAutoHide()
            if isLandscape {
                withAnimation(.default) {
                    isMoreControlsPresented = true
                }
            } else {
                isMoreControlsSheetPresented = true
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: controlMetrics.iconSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: moreControlsButtonWidth, height: controlMetrics.controlHeight)
        }
        .biliPlayerCompactGlassCapsule(metrics: controlMetrics)
        .frame(width: 44, height: controlMetrics.controlHeight, alignment: .trailing)
        .biliPlayerExpandedHitTarget(horizontal: 0, vertical: moreControlsVerticalHitPadding)
        .accessibilityLabel("更多播放设置")
    }

    private var moreControlsButtonWidth: CGFloat {
        controlMetrics.controlHeight + 10
    }

    private var moreControlsVerticalHitPadding: CGFloat {
        max((44 - controlMetrics.controlHeight) / 2, 8)
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
        .opacity(playbackControlsVisibility.opacity)
        .allowsHitTesting(playbackControlsVisibility.acceptsHitTesting)
        .zIndex(4)
    }

    private func visibleVideoInsets(in size: CGSize) -> EdgeInsets {
        guard configuration.isFullscreenActive,
              size.width > 1,
              size.height > 1,
              videoAspectRatio > 0.1
        else { return EdgeInsets() }

        let containerAspect = size.width / size.height
        let horizontalInset: CGFloat
        let verticalInset: CGFloat
        if videoAspectRatio > containerAspect {
            let fittedHeight = size.width / videoAspectRatio
            horizontalInset = 0
            verticalInset = max(0, (size.height - fittedHeight) / 2)
        } else {
            let fittedWidth = size.height * videoAspectRatio
            horizontalInset = max(0, (size.width - fittedWidth) / 2)
            verticalInset = 0
        }

        return EdgeInsets(
            top: verticalInset,
            leading: horizontalInset,
            bottom: verticalInset,
            trailing: horizontalInset
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
        usesFullscreenChromeSpacing ? 14 : 10
    }

    private func fullscreenSafeAreaInsets() -> UIEdgeInsets {
        guard configuration.isFullscreenActive,
              let window = UIApplication.shared.biliSurfaceHostForegroundKeyWindow
        else { return .zero }
        return window.safeAreaInsets
    }

    private var controlMetrics: PlayerNativeControlMetrics {
        if fullscreenMode?.isLandscape == true || verticalSizeClass == .compact {
            return .landscape
        }
        return .portrait
    }

    private func surfaceChromeState(
        context: BiliPlayerViewRenderContext,
        renderState: BiliPlayerViewRenderState,
        contentInsets: EdgeInsets
    ) -> BiliPlayerSurfaceChromeState {
        BiliPlayerSurfaceChromeState(
            presentation: context.configuration.presentation,
            surfaceOverlay: context.configuration.surfaceOverlay,
            rotationSnapshot: nil,
            seekSnapshot: seekTransitionSnapshotModel.snapshot,
            rotationFallbackCoverURL: nil,
            rotationSnapshotOpacity: 0,
            seekSnapshotOpacity: seekTransitionSnapshotModel.opacity,
            constrainsRotationSnapshotToVideoAspect: false,
            showsPlayerLoadingChrome: renderState.showsPlayerLoadingChrome,
            isBuffering: context.surfaceState.isBuffering,
            showsInlineLoadingProgress: renderState.showsInlineLoadingProgress,
            isUserSeeking: context.surfaceState.isUserSeeking,
            isSpeedBoostActive: context.speedBoostModel.isActive,
            showsActivePlaybackControls: renderState.showsActivePlaybackControls,
            playbackControlsOpacity: playbackControlsVisibility.opacity,
            playbackControlsAllowsHitTesting: playbackControlsVisibility.acceptsHitTesting,
            topLeadingControlsAccessory: context.configuration.topLeadingControlsAccessory,
            topTrailingControlsAccessory: nil,
            isFullscreenActive: context.configuration.isFullscreenActive,
            controlsBottomLift: context.configuration.controlsBottomLift,
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
        seekTransitionSnapshotModel.hold(
            hasPresentedPlayback: surfaceState.hasPresentedPlayback,
            surfaceLayoutGeneration: viewModel.surfaceLayoutGeneration
        ) {
            viewModel.makePlaybackTransitionSnapshot()
        }
    }

    private func updateSeekTransitionSnapshot(isUserSeeking: Bool) {
        if isUserSeeking {
            holdCurrentFrameForSeek()
        } else {
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

private struct SurfaceOnlyMoreControlsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var detailViewModel: VideoDetailViewModel
    @ObservedObject var viewModel: PlayerStateViewModel
    @ObservedObject var qualityStore: VideoDetailQualityControlRenderStore
    let selectPlayVariant: (PlayVariant) -> Void
    let onToggleDanmaku: () -> Void

    var body: some View {
        SurfaceOnlyMoreControlsNavigationContent(
            detailViewModel: detailViewModel,
            viewModel: viewModel,
            qualityStore: qualityStore,
            selectPlayVariant: selectPlayVariant,
            onToggleDanmaku: onToggleDanmaku,
            close: { dismiss() }
        )
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

private struct SurfaceOnlyMoreControlsNavigationContent: View {
    @ObservedObject var detailViewModel: VideoDetailViewModel
    @ObservedObject var viewModel: PlayerStateViewModel
    @ObservedObject var qualityStore: VideoDetailQualityControlRenderStore
    let selectPlayVariant: (PlayVariant) -> Void
    let onToggleDanmaku: () -> Void
    let close: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if qualityStore.hasQualityMenu {
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
                }

                NavigationLink {
                    SurfaceOnlyDanmakuSettingsPage(
                        detailViewModel: detailViewModel,
                        toggleDanmaku: onToggleDanmaku
                    )
                } label: {
                    Label("弹幕设置", systemImage: "text.bubble")
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

                Label("视频格式：\(videoFormatTitle)", systemImage: "film")
                    .foregroundStyle(.secondary)

                Label("解码：\(decodeTitle)", systemImage: "cpu")
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .navigationTitle("播放设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var decodeTitle: String {
        SurfaceOnlyPlaybackFormatText.decodeTitle(for: viewModel.engineDiagnostics)
    }

    private var videoFormatTitle: String {
        SurfaceOnlyPlaybackFormatText.videoFormatTitle(for: viewModel.engineDiagnostics)
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
    @ObservedObject var qualityStore: VideoDetailQualityControlRenderStore
    let selectPlayVariant: (PlayVariant) -> Void
    let onToggleDanmaku: () -> Void
    let contentInsets: EdgeInsets
    let close: () -> Void
    @State private var page: SurfaceOnlyLandscapeMoreControlsPage = .root

    var body: some View {
        GeometryReader { proxy in
            let visibleFrame = visibleVideoFrame(in: proxy.size)
            let panelSize = landscapePanelSize(in: visibleFrame)
            ZStack {
                Color.black.opacity(0.04)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: close)

                landscapePanel(size: panelSize)
                    .position(landscapePanelCenter(panelSize: panelSize, visibleFrame: visibleFrame))
                    .contentShape(Rectangle())
                    .onTapGesture {}
            }
        }
    }

    @ViewBuilder
    private func landscapePanel(size: CGSize) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        VStack(spacing: 0) {
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
                qualityStore: qualityStore,
                selectPlayVariant: selectPlayVariant,
                onToggleDanmaku: onToggleDanmaku,
                close: close
            )
        }
        .frame(width: size.width, height: size.height)
        .surfaceOnlyLandscapeGlassPanel(in: shape)
        .clipShape(shape)
        .overlay {
            shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.24), radius: 18, x: 0, y: 10)
    }

    private func visibleVideoFrame(in size: CGSize) -> CGRect {
        CGRect(
            x: contentInsets.leading,
            y: contentInsets.top,
            width: max(1, size.width - contentInsets.leading - contentInsets.trailing),
            height: max(1, size.height - contentInsets.top - contentInsets.bottom)
        )
    }

    private func landscapePanelSize(in visibleFrame: CGRect) -> CGSize {
        let horizontalMargin: CGFloat = 18
        let verticalMargin: CGFloat = 14
        let topOffset: CGFloat = 58
        let availableWidth = max(1, visibleFrame.width - horizontalMargin * 2)
        let width = min(330, availableWidth)
        let availableHeight = max(1, visibleFrame.height - topOffset - verticalMargin)
        let height = min(318, availableHeight)
        return CGSize(width: width, height: height)
    }

    private func landscapePanelCenter(panelSize: CGSize, visibleFrame: CGRect) -> CGPoint {
        let horizontalMargin: CGFloat = 18
        let verticalMargin: CGFloat = 14
        let preferredTop: CGFloat = visibleFrame.minY + 58
        let preferredX = visibleFrame.maxX - horizontalMargin - panelSize.width / 2
        let preferredY = preferredTop + panelSize.height / 2
        return CGPoint(
            x: clamped(
                preferredX,
                lower: visibleFrame.minX + horizontalMargin + panelSize.width / 2,
                upper: visibleFrame.maxX - horizontalMargin - panelSize.width / 2,
                fallback: visibleFrame.midX
            ),
            y: clamped(
                preferredY,
                lower: visibleFrame.minY + verticalMargin + panelSize.height / 2,
                upper: visibleFrame.maxY - verticalMargin - panelSize.height / 2,
                fallback: visibleFrame.midY
            )
        )
    }

    private func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat, fallback: CGFloat) -> CGFloat {
        guard lower <= upper else { return fallback }
        return min(max(value, lower), upper)
    }

}

private enum SurfaceOnlyLandscapeMoreControlsPage {
    case root
    case quality
    case danmaku
    case rate

    var title: String {
        switch self {
        case .root:
            return "播放设置"
        case .quality:
            return "清晰度"
        case .danmaku:
            return "弹幕设置"
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
            case .danmaku:
                SurfaceOnlyDanmakuSettingsPage(
                    detailViewModel: detailViewModel,
                    toggleDanmaku: onToggleDanmaku
                )
                .scrollContentBackground(.hidden)
            case .rate:
                ratePage
            }
        }
    }

    private var rootPage: some View {
        ScrollView {
            VStack(spacing: 10) {
                VStack(spacing: 0) {
                    if qualityStore.hasQualityMenu {
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

                    SurfaceOnlyLandscapeMenuRow(
                        title: "弹幕设置",
                        systemImage: "text.bubble",
                        accessory: nil,
                        showsChevron: true
                    ) {
                        page = .danmaku
                    }

                    Divider().padding(.leading, 44)

                    SurfaceOnlyLandscapeMenuRow(
                        title: "倍速",
                        systemImage: "speedometer",
                        accessory: viewModel.playbackRate.title,
                        showsChevron: true
                    ) {
                        page = .rate
                    }
                }
                .surfaceOnlyLandscapeGlassGroup()

                VStack(spacing: 0) {
                    SurfaceOnlyLandscapeInfoRow(
                        title: "视频格式",
                        systemImage: "film",
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
                    SurfaceOnlyLandscapeInfoRow(
                        title: "正在切换清晰度",
                        systemImage: "arrow.triangle.2.circlepath",
                        value: nil
                    )
                    .surfaceOnlyLandscapeGlassGroup()
                }

                VStack(spacing: 0) {
                    ForEach(Array(qualityStore.qualityMenuItems.enumerated()), id: \.element.id) { index, item in
                        SurfaceOnlyLandscapeMenuRow(
                            title: item.title,
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

    private var decodeTitle: String {
        SurfaceOnlyPlaybackFormatText.decodeTitle(for: viewModel.engineDiagnostics)
    }

    private var videoFormatTitle: String {
        SurfaceOnlyPlaybackFormatText.videoFormatTitle(for: viewModel.engineDiagnostics)
    }
}

private struct SurfaceOnlyLandscapeMenuRow: View {
    let title: String
    let systemImage: String
    let accessory: String?
    let showsChevron: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
                Label("正在切换清晰度", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
            }

            ForEach(qualityStore.qualityMenuItems) { item in
                Button {
                    selectPlayVariant(item.variant)
                    closeSheet()
                } label: {
                    Label(item.title, systemImage: item.systemImage)
                }
                .disabled(item.isDisabled)
            }
        }
        .foregroundStyle(.primary)
        .navigationTitle("清晰度")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SurfaceOnlyDanmakuSettingsPage: View {
    @ObservedObject var detailViewModel: VideoDetailViewModel
    let toggleDanmaku: () -> Void

    var body: some View {
        DanmakuSettingsSheetContent(
            store: detailViewModel.danmakuSettingsRenderStore,
            summary: settingsSummary,
            displayAreaBinding: displayAreaBinding,
            fontScaleBinding: fontScaleBinding,
            fontWeightBinding: fontWeightBinding,
            opacityBinding: opacityBinding,
            toggleDanmaku: toggleDanmaku
        )
        .navigationTitle("弹幕设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var settingsSummary: String {
        let store = detailViewModel.danmakuSettingsRenderStore
        if store.isDanmakuEnabled {
            return "当前使用 \(store.danmakuSettings.displayArea.title)，字号 \(Int((store.danmakuSettings.fontScale * 100).rounded()))%，不透明度 \(Int((store.danmakuSettings.opacity * 100).rounded()))%。"
        }
        return "弹幕已关闭，播放时不会显示滚动评论。"
    }

    private var displayAreaBinding: Binding<DanmakuDisplayArea> {
        Binding(
            get: { detailViewModel.danmakuSettingsRenderStore.danmakuSettings.displayArea },
            set: { newValue in
                var settings = detailViewModel.danmakuSettingsRenderStore.danmakuSettings
                settings.displayArea = newValue
                detailViewModel.updateDanmakuSettings(settings)
            }
        )
    }

    private var fontScaleBinding: Binding<Double> {
        Binding(
            get: { detailViewModel.danmakuSettingsRenderStore.danmakuSettings.fontScale },
            set: { newValue in
                var settings = detailViewModel.danmakuSettingsRenderStore.danmakuSettings
                settings.fontScale = newValue
                detailViewModel.updateDanmakuSettings(settings)
            }
        )
    }

    private var fontWeightBinding: Binding<DanmakuFontWeightOption> {
        Binding(
            get: { detailViewModel.danmakuSettingsRenderStore.danmakuSettings.fontWeight },
            set: { newValue in
                var settings = detailViewModel.danmakuSettingsRenderStore.danmakuSettings
                settings.fontWeight = newValue
                detailViewModel.updateDanmakuSettings(settings)
            }
        )
    }

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { detailViewModel.danmakuSettingsRenderStore.danmakuSettings.opacity },
            set: { newValue in
                var settings = detailViewModel.danmakuSettingsRenderStore.danmakuSettings
                settings.opacity = newValue
                detailViewModel.updateDanmakuSettings(settings)
            }
        )
    }
}

private extension View {
    @ViewBuilder
    func surfaceOnlyLandscapeGlassPanel<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26, *) {
            self
                .background(Color(.systemBackground).opacity(0.22), in: shape)
                .glassEffect(.regular.tint(Color(.systemBackground).opacity(0.18)), in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
        }
    }

    @ViewBuilder
    func surfaceOnlyLandscapeGlassGroup() -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        if #available(iOS 26, *) {
            self
                .background(Color(.secondarySystemGroupedBackground).opacity(0.34), in: shape)
                .glassEffect(.clear, in: shape)
        } else {
            self
                .background(.thinMaterial, in: shape)
        }
    }
}

private extension UIApplication {
    var biliSurfaceHostForegroundKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
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
        .foregroundStyle(.primary)
        .navigationTitle("倍速")
        .navigationBarTitleDisplayMode(.inline)
    }
}
