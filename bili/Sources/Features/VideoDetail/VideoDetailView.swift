import AVFoundation
import SwiftUI
import Combine
import UIKit

private enum VideoDetailContentTab: String, CaseIterable, Identifiable {
    case detail
    case comments

    var id: Self { self }

    var title: String {
        switch self {
        case .detail:
            return "详情"
        case .comments:
            return "评论"
        }
    }

    var systemImage: String {
        switch self {
        case .detail:
            return "text.alignleft"
        case .comments:
            return "bubble.left.and.bubble.right"
        }
    }
}

private enum VideoDetailPlaybackControlPolicy {
    static let prefersNativePlaybackControls = false
}

private enum VideoDetailFullscreenTrigger {
    case none
    case manual
    case rotation
}

struct VideoDetailView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    let seedVideo: VideoItem
    private let hidesRootTabBar: Bool
    private let onRequestClose: (() -> Void)?

    @StateObject private var holder = VideoDetailViewModelHolder()
    @StateObject private var runtimeSettings = VideoDetailRuntimeSettingsStore()
    @State private var replySheetComment: Comment?
    @State private var fullscreenMode: PlayerFullscreenMode?
    @State private var fullscreenTrigger: VideoDetailFullscreenTrigger = .none
    @State private var pendingRotationLandscapeOrientation: UIDeviceOrientation?
    @State private var exitingFullscreenMode: PlayerFullscreenMode?
    @State private var isCompletingFullscreenExit = false
    @State private var isSystemRotationLayoutTransitioning = false
    @State private var pendingFullscreenExitTask: Task<Void, Never>?
    @State private var isShowingDanmakuSettings = false
    @State private var isShowingFavoriteFolders = false
    @State private var isShowingNetworkDiagnostics = false
    @State private var selectedDetailContentTab: VideoDetailContentTab = .detail
    @State private var isClosingDetail = false

    private static let inlineFullscreenTransitionAnimation = Animation.easeInOut(duration: 0.26)

    init(
        seedVideo: VideoItem,
        hidesRootTabBar: Bool = true,
        onRequestClose: (() -> Void)? = nil
    ) {
        self.seedVideo = seedVideo
        self.hidesRootTabBar = hidesRootTabBar
        self.onRequestClose = onRequestClose
    }

    var body: some View {
        Group {
            if let viewModel = holder.viewModel {
                content(viewModel)
            } else {
                initialContent()
                    .task {
                        holder.configure(
                            seedVideo: seedVideo,
                            api: dependencies.api,
                            libraryStore: dependencies.libraryStore,
                            sponsorBlockService: dependencies.sponsorBlockService
                        )
                    }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .hideRootTabBarWhenNeeded(hidesRootTabBar)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .background(
            VideoDetailLifecycleBridge(
                onWillDisappear: {
                    holder.viewModel?.pausePlaybackForPotentialNavigation()
                },
                onDidAppear: {
                    guard !isClosingDetail else { return }
                    holder.viewModel?.resumePlaybackAfterCoveredNavigationIfNeeded()
                },
                onTransitionCompleted: { cancelled in
                    guard !isClosingDetail else { return }
                    if cancelled {
                        holder.viewModel?.resumePlaybackAfterCancelledNavigation()
                    } else {
                        holder.viewModel?.stopPlaybackForNavigation()
                    }
                }
            )
        )
        .background(
            VideoDetailSystemBackGestureBridge {
                holder.viewModel?.pausePlaybackForPotentialNavigation()
            }
        )
        .background(
            VideoDetailRotationLayoutBridge(
                onLayoutTransition: {
                    refreshActivePlayerSurfaceLayout()
                },
                onTransitionCompleted: {
                    isSystemRotationLayoutTransitioning = false
                    refreshActivePlayerSurfaceLayout()
                }
            )
        )
        .onAppear {
            runtimeSettings.bind(dependencies.libraryStore)
            restorePortraitWhenFullscreenInactive()
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            handleFullscreenDeviceOrientation(UIDevice.current.orientation)
            guard !isClosingDetail else { return }
            holder.viewModel?.resumePlaybackAfterCoveredNavigationIfNeeded()
        }
        .onDisappear {
            pendingFullscreenExitTask?.cancel()
            pendingRotationLandscapeOrientation = nil
            exitingFullscreenMode = nil
            fullscreenMode = nil
            fullscreenTrigger = .none
            isCompletingFullscreenExit = false
            holder.viewModel?.pausePlaybackForPotentialNavigation()
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            AppOrientationLock.restorePortrait()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            handleFullscreenDeviceOrientation(UIDevice.current.orientation)
        }
        .onReceive(NotificationCenter.default.publisher(for: .biliStopActiveVideoPlayback)) { _ in
            holder.viewModel?.stopPlaybackForNavigation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .biliPauseActiveVideoPlaybackForNavigation)) { _ in
            holder.viewModel?.pausePlaybackForPotentialNavigation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .biliResumeActiveVideoPlaybackAfterCancelledNavigation)) { _ in
            guard !isClosingDetail else { return }
            holder.viewModel?.resumePlaybackAfterCancelledNavigation()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, !isClosingDetail else { return }
            restorePortraitWhenFullscreenInactive()
            handleFullscreenDeviceOrientation(UIDevice.current.orientation)
            holder.viewModel?.recoverPlaybackAfterAppResume()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            guard !isClosingDetail else { return }
            restorePortraitWhenFullscreenInactive()
            handleFullscreenDeviceOrientation(UIDevice.current.orientation)
            holder.viewModel?.recoverPlaybackAfterAppResume()
        }
    }

    @ViewBuilder
    private func content(_ viewModel: VideoDetailViewModel) -> some View {
        GeometryReader { proxy in
            let fullscreenGeometry = proxy.fullscreenContainerGeometry
            let fullscreenSize = fullscreenGeometry.size
            let effectiveFullscreenMode = activeFullscreenMode
            let usesFullscreenLayout = fullscreenMode != nil
            let isLandscapeFullscreen = fullscreenMode?.isLandscape == true
            let shouldHideSystemChrome = effectiveFullscreenMode != nil || isCompletingFullscreenExit
            let stablePortraitWidth = Self.stablePortraitLayoutWidth(
                proxySize: proxy.size,
                fullscreenSize: fullscreenSize
            )
            let layoutSize = usesFullscreenLayout
                ? fullscreenSize
                : CGSize(width: stablePortraitWidth, height: proxy.size.height)

            let playbackSize = layoutSize
            let fullscreenOffset = usesFullscreenLayout ? fullscreenGeometry.offset : .zero

            ZStack(alignment: .topLeading) {
                if shouldHideSystemChrome {
                    Color.black
                        .ignoresSafeArea()
                }

                standardPlaybackPage(
                    viewModel,
                    screenSize: playbackSize,
                    isLandscape: isLandscapeFullscreen
                )
                .frame(
                    width: playbackSize.width,
                    height: playbackSize.height
                )
                .offset(
                    x: fullscreenOffset.width,
                    y: fullscreenOffset.height
                )
            }
            .frame(
                width: proxy.size.width,
                height: proxy.size.height,
                alignment: .topLeading
            )
            .animation(
                isSystemRotationLayoutTransitioning ? nil : Self.inlineFullscreenTransitionAnimation,
                value: fullscreenMode
            )
            .animation(
                isSystemRotationLayoutTransitioning ? nil : Self.inlineFullscreenTransitionAnimation,
                value: effectiveFullscreenMode
            )
            .background(shouldHideSystemChrome ? Color.black : Color.videoDetailBackground)
            .ignoresSafeArea(.container, edges: usesFullscreenLayout ? .all : [])
            .preference(key: VideoDetailChromeHiddenPreferenceKey.self, value: shouldHideSystemChrome)
            .statusBar(hidden: shouldHideSystemChrome)
            .persistentSystemOverlays(shouldHideSystemChrome ? .hidden : .automatic)
            .overlay(alignment: .top) {
                VideoDetailStatusBarBackdrop(isHidden: shouldHideSystemChrome)
            }
            .background {
                StatusBarStyleBridge(
                    style: .lightContent,
                    isHidden: shouldHideSystemChrome
                )
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            }
            .overlay {
                VideoDetailFailureOverlay(
                    placeholderStore: viewModel.playbackRenderStore.placeholderStore,
                    retry: {
                        Task { await viewModel.load() }
                    }
                )
            }
            .overlay(alignment: .topLeading) {
                if runtimeSettings.playerPerformanceOverlayEnabled {
                    VideoDetailPerformanceOverlayContainer(
                        store: viewModel.networkDiagnosticsRenderStore
                    )
                        .padding(.top, shouldHideSystemChrome ? 14 : 10)
                        .padding(.leading, 10)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
                }
            }
            .task {
                await viewModel.load()
            }
            .onReceive(viewModel.playerIdentityRenderStore.objectWillChange) { _ in
                Task { @MainActor in
                    await Task.yield()
                    restorePortraitWhenFullscreenInactive()
                    retryPendingRotationFullscreenIfNeeded()
                }
            }
            .sheet(item: $replySheetComment) { comment in
                CommentRepliesSheet(
                    rootComment: comment,
                    store: viewModel.commentThreadRenderStore,
                    loadReplies: { [weak viewModel] comment in
                        guard let viewModel else { return }
                        await viewModel.loadReplies(for: comment)
                    },
                    reloadReplies: { [weak viewModel] comment in
                        guard let viewModel else { return }
                        await viewModel.reloadReplies(for: comment)
                    },
                    loadMoreReplies: { [weak viewModel] comment in
                        guard let viewModel else { return }
                        await viewModel.loadMoreReplies(for: comment)
                    },
                    loadDialog: { [weak viewModel] rootComment, reply in
                        guard let viewModel else { return }
                        await viewModel.loadDialog(for: rootComment, reply: reply)
                    },
                    reloadDialog: { [weak viewModel] rootComment, reply in
                        guard let viewModel else { return }
                        await viewModel.reloadDialog(for: rootComment, reply: reply)
                    }
                )
            }
            .sheet(isPresented: $isShowingFavoriteFolders) {
                FavoriteFolderSelectionSheet(
                    store: viewModel.favoriteFolderRenderStore,
                    loadFavoriteFolders: { forceRefresh in
                        await viewModel.loadFavoriteFoldersForCurrentVideo(forceRefresh: forceRefresh)
                    },
                    saveFavoriteFolders: { selectedFolderIDs in
                        await viewModel.setFavoriteFolders(selectedIDs: selectedFolderIDs)
                    }
                )
            }
            .sheet(isPresented: $isShowingDanmakuSettings) {
                DanmakuSettingsSheet(
                    store: viewModel.danmakuSettingsRenderStore,
                    toggleDanmaku: {
                        viewModel.toggleDanmaku()
                    },
                    updateDanmakuSettings: { settings in
                        viewModel.updateDanmakuSettings(settings)
                    }
                )
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $isShowingNetworkDiagnostics) {
                PlaybackNetworkDiagnosticsSheet(
                    diagnosticsStore: viewModel.networkDiagnosticsRenderStore,
                    relatedStore: viewModel.relatedRenderStore,
                    libraryStore: dependencies.libraryStore
                )
            }
        }
        .ignoresSafeArea(.container, edges: fullscreenMode != nil ? .all : [])
    }

    private func initialContent() -> some View {
        GeometryReader { proxy in
            let fullscreenGeometry = proxy.fullscreenContainerGeometry
            let fullscreenSize = fullscreenGeometry.size
            let stablePortraitWidth = Self.stablePortraitLayoutWidth(
                proxySize: proxy.size,
                fullscreenSize: fullscreenSize
            )
            let layoutWidth = stablePortraitWidth
            let standardHeight = layoutWidth * 9 / 16

            ZStack(alignment: .top) {
                Color.videoDetailBackground
                    .ignoresSafeArea()

                VideoDetailNativeContentTabView(
                    selection: $selectedDetailContentTab,
                    layoutWidth: layoutWidth,
                    topInset: standardHeight,
                    minimizesTabBarOnScroll: runtimeSettings.minimizesTabBarOnScroll
                ) { tab in
                    initialDetailScrollPage(layoutWidth: layoutWidth, tab: tab)
                }
                .frame(width: layoutWidth, height: proxy.size.height)

                PlayerLoadingPlaceholder(
                    progress: 0.08,
                    message: "加载视频信息",
                    isFinishing: false,
                    showsChromeSkeleton: true
                )
                .frame(width: layoutWidth, height: standardHeight)
                .background(Color.black)
                .overlay(alignment: .topLeading) {
                    VideoDetailPlayerBackButton {
                        dismissVideoDetail()
                    }
                    .padding(.top, 10)
                    .padding(.leading, 10)
                }
                .overlay(alignment: .bottom) {
                    if runtimeSettings.showsPinnedProgressBar {
                        VideoDetailPinnedProgressPlaceholder()
                            .frame(width: layoutWidth, height: VideoDetailPinnedProgressBar.height)
                    }
                }
                .zIndex(1)

                VideoDetailStatusBarBackdrop(isHidden: false)
            }
            .frame(width: layoutWidth, height: proxy.size.height)
            .background(Color.videoDetailBackground)
            .background {
                StatusBarStyleBridge(
                    style: .lightContent,
                    isHidden: false
                )
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
            }
        }
    }

    private static func stablePortraitLayoutWidth(proxySize: CGSize, fullscreenSize: CGSize) -> CGFloat {
        let proxyShortSide = min(proxySize.width, proxySize.height)
        let fullscreenShortSide = min(fullscreenSize.width, fullscreenSize.height)
        let windowShortSide = UIApplication.shared.biliForegroundKeyWindow.map { window in
            min(window.bounds.width, window.bounds.height)
        } ?? .greatestFiniteMagnitude
        return min(proxyShortSide, fullscreenShortSide, windowShortSide)
    }

    private func standardPlaybackPage(
        _ viewModel: VideoDetailViewModel,
        screenSize: CGSize,
        isLandscape: Bool = false
    ) -> some View {
        let config = makeStandardPlaybackPageConfig(
            screenSize: screenSize,
            isLandscape: isLandscape
        )
        return VideoDetailStandardPlaybackPage(
            config: config,
            viewModel: viewModel,
            selectedContentTab: $selectedDetailContentTab,
            detailContent: {
                detailScrollPage(viewModel, layoutWidth: screenSize.width, tab: $0)
            }
        )
    }

    private func makeStandardPlaybackPageConfig(
        screenSize: CGSize,
        isLandscape: Bool
    ) -> VideoDetailStandardPlaybackPageConfig {
        let standardHeight: CGFloat = screenSize.width * 9 / 16
        let effectiveFullscreenMode = activeFullscreenMode
        let isFullscreen: Bool = effectiveFullscreenMode != nil || isCompletingFullscreenExit
        let playerHeight: CGFloat = isLandscape ? screenSize.height : (fullscreenMode != nil ? screenSize.height : standardHeight)
        let playerWidth: CGFloat? = isLandscape ? screenSize.width : nil
        let activeFullscreenMode: PlayerFullscreenMode?
        let exitHandler: (() -> Void)?
        activeFullscreenMode = effectiveFullscreenMode
        exitHandler = effectiveFullscreenMode == nil ? nil : { exitFullscreenPlayback() }

        return VideoDetailStandardPlaybackPageConfig(
            screenSize: screenSize,
            standardHeight: standardHeight,
            isLandscape: isLandscape,
            isFullscreen: isFullscreen,
            playerWidth: playerWidth,
            playerHeight: playerHeight,
            fullscreenMode: activeFullscreenMode,
            isDanmakuSettingsPresented: isShowingDanmakuSettings,
            minimizesTabBarOnScroll: runtimeSettings.minimizesTabBarOnScroll,
            showsPinnedProgressBar: runtimeSettings.showsPinnedProgressBar,
            onRequestFullscreen: { playerViewModel in
                enterFullscreenPlayback(playerViewModel: playerViewModel, trigger: .manual)
            },
            onExitFullscreen: exitHandler,
            onNavigateBack: {
                dismissVideoDetail()
            },
            onShowDanmakuSettings: {
                isShowingDanmakuSettings = true
            }
        )
    }

    private func dismissVideoDetail() {
        guard !isClosingDetail else { return }
        isClosingDetail = true
        holder.viewModel?.stopPlaybackForNavigation()
        if let onRequestClose {
            onRequestClose()
        } else {
            dismiss()
        }
    }

    private var isUsingSystemNativePlayerUI: Bool {
        false
    }

    private var shouldUseInlineFullscreenRotation: Bool {
        guard let decodePath = holder.viewModel?
            .playerIdentityRenderStore
            .playerViewModel?
            .engineDiagnostics
            .decodePath
        else { return false }
        return decodePath != .unknown && !isUsingSystemNativePlayerUI
    }

    private var currentPlayerDecodePath: PlayerEngineDiagnostics.DecodePath? {
        holder.viewModel?
            .playerIdentityRenderStore
            .playerViewModel?
            .engineDiagnostics
            .decodePath
    }

    private var activeFullscreenMode: PlayerFullscreenMode? {
        fullscreenMode ?? exitingFullscreenMode
    }

    private func exitFullscreenPlayback() {
        guard activeFullscreenMode != nil else { return }
        pendingRotationLandscapeOrientation = nil
        beginCompletingFullscreenExit()
    }

    private func handleFullscreenDeviceOrientation(_ orientation: UIDeviceOrientation) {
        guard let decodePath = currentPlayerDecodePath, decodePath != .unknown else {
            if orientation.isLandscape {
                pendingRotationLandscapeOrientation = orientation
            } else if orientation.isPortrait {
                pendingRotationLandscapeOrientation = nil
            }
            return
        }

        guard shouldUseInlineFullscreenRotation else {
            pendingRotationLandscapeOrientation = nil
            return
        }
        switch orientation {
        case .landscapeLeft, .landscapeRight:
            pendingRotationLandscapeOrientation = orientation
            enterFullscreenPlayback(
                playerViewModel: holder.viewModel?.playerIdentityRenderStore.playerViewModel,
                preferredLandscapeOrientation: orientation,
                trigger: fullscreenTrigger == .none ? .rotation : fullscreenTrigger
            )
        case .portrait, .portraitUpsideDown:
            pendingRotationLandscapeOrientation = nil
            guard fullscreenMode?.isLandscape == true else { return }
            guard fullscreenTrigger == .rotation else { return }
            exitFullscreenPlayback()
        default:
            break
        }
    }

    private func retryPendingRotationFullscreenIfNeeded() {
        guard let retryOrientation = pendingRotationLandscapeOrientation ?? (UIDevice.current.orientation.isLandscape ? UIDevice.current.orientation : nil) else {
            return
        }
        guard currentPlayerDecodePath != nil, currentPlayerDecodePath != .unknown else {
            pendingRotationLandscapeOrientation = retryOrientation
            return
        }
        guard shouldUseInlineFullscreenRotation else {
            pendingRotationLandscapeOrientation = nil
            return
        }
        enterFullscreenPlayback(
            playerViewModel: holder.viewModel?.playerIdentityRenderStore.playerViewModel,
            preferredLandscapeOrientation: retryOrientation,
            trigger: .rotation
        )
    }

    private func enterFullscreenPlayback(
        playerViewModel: PlayerStateViewModel? = nil,
        preferredLandscapeOrientation: UIDeviceOrientation? = nil,
        trigger: VideoDetailFullscreenTrigger
    ) {
        pendingFullscreenExitTask?.cancel()
        exitingFullscreenMode = nil
        isCompletingFullscreenExit = false
        guard shouldUseInlineFullscreenRotation else {
            pendingRotationLandscapeOrientation = nil
            return
        }
        let resolvedPlayerViewModel = playerViewModel
            ?? holder.viewModel?.playerIdentityRenderStore.playerViewModel
        let landscapeOrientation = preferredLandscapeOrientation?.isLandscape == true
            ? preferredLandscapeOrientation!
            : preferredLandscapeDeviceOrientation()
        let targetMode: PlayerFullscreenMode
        if shouldUsePortraitFullscreen, preferredLandscapeOrientation == nil {
            targetMode = .portrait
        } else {
            targetMode = .landscape(landscapeOrientation)
        }

        let isRotationTriggered = trigger == .rotation
        if fullscreenMode != nil {
            requestInlineFullscreenGeometry(for: targetMode)
            setFullscreenMode(
                targetMode,
                trigger: trigger,
                animated: !isRotationTriggered
            )
            resolvedPlayerViewModel?.refreshSurfaceLayout()
            return
        }

        guard let resolvedPlayerViewModel else {
            if preferredLandscapeOrientation?.isLandscape == true {
                pendingRotationLandscapeOrientation = preferredLandscapeOrientation
            }
            return
        }
        requestInlineFullscreenGeometry(for: targetMode)
        setFullscreenMode(
            targetMode,
            trigger: trigger,
            animated: !isRotationTriggered
        )
        resolvedPlayerViewModel.refreshSurfaceLayout()
    }

    private func requestInlineFullscreenGeometry(for mode: PlayerFullscreenMode) {
        let scene = UIApplication.shared.videoDetailKeyWindow?.windowScene
            ?? UIApplication.shared.biliForegroundKeyWindow?.windowScene
        AppOrientationLock.update(
            to: mode.videoDetailInterfaceOrientationMask,
            in: scene,
            requestsGeometryUpdate: true
        )
    }

    private func requestInlinePortraitGeometry() {
        let scene = UIApplication.shared.videoDetailKeyWindow?.windowScene
            ?? UIApplication.shared.biliForegroundKeyWindow?.windowScene
        AppOrientationLock.update(
            to: .portrait,
            in: scene,
            requestsGeometryUpdate: true
        )
    }

    private var shouldUsePortraitFullscreen: Bool {
        guard let viewModel = holder.viewModel else { return false }
        return videoAspectRatio(in: viewModel.playbackRenderStore).map { $0 < 0.9 } == true
    }

    private func videoAspectRatio(in store: VideoDetailPlaybackRenderStore) -> Double? {
        store.selectedPlayVariant?.videoAspectRatio
            ?? selectedPage(in: store.pageSelectorStore)?.dimension?.aspectRatio
            ?? store.qualityMenuItems.compactMap(\.variant.videoAspectRatio).first
    }

    private func selectedPage(in store: VideoDetailPageSelectorRenderStore) -> VideoPage? {
        guard let selectedCID = store.selectedCID else { return nil }
        return store.pages.first { $0.cid == selectedCID }
    }

    private func beginCompletingFullscreenExit() {
        guard let mode = activeFullscreenMode else { return }
        let isRotationTriggered = fullscreenTrigger == .rotation
        pendingFullscreenExitTask?.cancel()
        exitingFullscreenMode = mode
        isCompletingFullscreenExit = true
        requestInlinePortraitGeometry()
        setFullscreenMode(nil, trigger: .none, animated: !isRotationTriggered)
        refreshActivePlayerSurfaceLayout()
        pendingFullscreenExitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled else { return }
            exitingFullscreenMode = nil
            isCompletingFullscreenExit = false
            restorePortraitWhenFullscreenInactive()
            refreshActivePlayerSurfaceLayout()
        }
    }

    private func setFullscreenMode(
        _ mode: PlayerFullscreenMode?,
        trigger: VideoDetailFullscreenTrigger,
        animated: Bool
    ) {
        let update = {
            fullscreenMode = mode
            fullscreenTrigger = trigger
            if trigger == .rotation {
                isSystemRotationLayoutTransitioning = true
            }
        }

        if animated {
            withAnimation(Self.inlineFullscreenTransitionAnimation, update)
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, update)
        }
        refreshActivePlayerSurfaceLayout()
    }

    private func refreshActivePlayerSurfaceLayout() {
        holder.viewModel?
            .playerIdentityRenderStore
            .playerViewModel?
            .refreshSurfaceLayout()
    }

    private func restorePortraitWhenFullscreenInactive() {
        guard fullscreenMode == nil, !isCompletingFullscreenExit else { return }
        AppOrientationLock.restorePortrait(in: UIApplication.shared.videoDetailKeyWindow?.windowScene)
    }

    private func preferredLandscapeDeviceOrientation() -> UIDeviceOrientation {
        if let orientation = UIApplication.shared.videoDetailKeyWindow?.windowScene?.effectiveGeometry.interfaceOrientation,
           orientation.isLandscape {
            return orientation == .landscapeLeft ? .landscapeRight : .landscapeLeft
        }
        let current = UIDevice.current.orientation
        return current == .landscapeRight ? .landscapeRight : .landscapeLeft
    }

    private func detailCard(_ viewModel: VideoDetailViewModel, contentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VideoDetailInfoBlock(
                store: viewModel.descriptionRenderStore
            )
            actionStrip(viewModel, contentWidth: contentWidth)
            if runtimeSettings.showsNetworkDiagnosticsButton {
                networkDiagnosticsButton
            }
            VideoDetailInteractionNotice(store: viewModel.interactionRenderStore)
            VideoDetailPlayURLNotice(
                placeholderStore: viewModel.playbackRenderStore.placeholderStore,
                retry: {
                    Task {
                        await viewModel.retryPlayURL()
                    }
                }
            )
        }
        .frame(width: contentWidth, alignment: .leading)
    }

    private var networkDiagnosticsButton: some View {
        Button {
            isShowingNetworkDiagnostics = true
        } label: {
            Label("网络诊断", systemImage: "waveform.path.ecg.rectangle")
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .accessibilityLabel("打开网络诊断")
    }

    private func actionStrip(_ viewModel: VideoDetailViewModel, contentWidth: CGFloat) -> some View {
        VideoDetailActionStripContainer(
            descriptionStore: viewModel.descriptionRenderStore,
            store: viewModel.interactionRenderStore,
            contentWidth: contentWidth,
            onFollow: {
                Haptics.light()
                Task {
                    if await viewModel.toggleFollow() {
                        Haptics.success()
                    }
                }
            },
            onLike: {
                Haptics.light()
                Task {
                    if await viewModel.toggleLike() {
                        Haptics.success()
                    }
                }
            },
            onCoin: {
                Haptics.medium()
                Task {
                    if await viewModel.addCoin() {
                        Haptics.success()
                    }
                }
            },
            onFavorite: {
                Haptics.light()
                isShowingFavoriteFolders = true
            },
            onShareTap: {
                Haptics.light()
            }
        )
    }

    private func detailScrollPage(
        _ viewModel: VideoDetailViewModel,
        layoutWidth: CGFloat,
        tab: VideoDetailContentTab
    ) -> some View {
        let horizontalPadding: CGFloat = 12
        let contentWidth = max(layoutWidth - horizontalPadding * 2, 0)

        return VStack(alignment: .leading, spacing: 10) {
            switch tab {
            case .detail:
                detailCard(viewModel, contentWidth: contentWidth)
                    .padding(.horizontal, horizontalPadding)

                VideoDetailPageMenu(
                    store: viewModel.playbackRenderStore.pageSelectorStore,
                    selectPage: viewModel.selectPage
                )
                .padding(.horizontal, horizontalPadding)

                VideoDetailRelatedSection(
                    store: viewModel.relatedRenderStore,
                    layoutWidth: layoutWidth,
                    runtimeSettings: runtimeSettings.snapshot,
                    retryRelated: { [weak viewModel] in
                        guard let viewModel else { return }
                        await viewModel.retryRelated()
                    }
                )

            case .comments:
                commentsSection(
                    viewModel,
                    style: .plain,
                    maxVisibleComments: nil,
                    autoLoads: true
                )
                    .padding(.top, 4)
            }
        }
        .padding(.top, 8)
        .frame(width: layoutWidth, alignment: .top)
        .background(Color.videoDetailBackground)
    }

    private func initialDetailScrollPage(
        layoutWidth: CGFloat,
        tab: VideoDetailContentTab
    ) -> some View {
        let horizontalPadding: CGFloat = 12
        let contentWidth = max(layoutWidth - horizontalPadding * 2, 0)

        return VStack(alignment: .leading, spacing: 10) {
            switch tab {
            case .detail:
                initialDetailControls(contentWidth: contentWidth)
                    .padding(.horizontal, horizontalPadding)

                if shouldShowInitialPageMenuPlaceholder {
                    InitialPageMenuPlaceholder(pageCount: seedVideo.pages?.count ?? 0)
                        .padding(.horizontal, horizontalPadding)
                }

                InitialRelatedSection(layoutWidth: layoutWidth)

            case .comments:
                InitialCommentsSection()
                    .padding(.top, 4)
            }
        }
        .padding(.top, 8)
        .frame(width: layoutWidth, alignment: .top)
        .background(Color.videoDetailBackground)
    }

    private func initialDetailControls(contentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            initialTitleInfoPlaceholder()
            initialActionStrip(contentWidth: contentWidth)
        }
        .frame(width: contentWidth, alignment: .leading)
        .allowsHitTesting(false)
    }

    private var shouldShowInitialPageMenuPlaceholder: Bool {
        (seedVideo.pages?.count ?? 0) > 1
    }

    private func initialTitleInfoPlaceholder() -> some View {
        VideoDetailInfoLoadingPlaceholder(titleText: seedVideo.title)
    }

    private func initialActionStrip(contentWidth: CGFloat) -> some View {
        let columnSpacing: CGFloat = 4
        let columnWidth = max((contentWidth - columnSpacing * 5) / 6, 1)

        return HStack(spacing: columnSpacing) {
            ForEach(0..<6, id: \.self) { _ in
                Circle()
                    .fill(Color.videoDetailSecondarySurface.opacity(0.92))
                    .frame(width: 25, height: 25)
                    .frame(width: columnWidth, height: 25)
            }
        }
        .frame(width: contentWidth, height: 25, alignment: .center)
        .redacted(reason: .placeholder)
    }

    private func commentsSection(
        _ viewModel: VideoDetailViewModel,
        style: CommentSectionStyle = .grouped,
        maxVisibleComments: Int? = nil,
        autoLoads: Bool = true
    ) -> some View {
        CommentsSectionView(
            store: viewModel.commentsRenderStore,
            style: style,
            maxVisibleComments: maxVisibleComments,
            autoLoads: autoLoads,
            showAllComments: nil,
            beginInitialCommentsLoad: { [weak viewModel] in
                viewModel?.beginInitialCommentsLoadIfNeeded()
            },
            selectCommentSort: { [weak viewModel] sort in
                guard let viewModel else { return }
                await viewModel.selectCommentSort(sort)
            },
            retryComments: { [weak viewModel] in
                guard let viewModel else { return }
                await viewModel.retryComments()
            },
            loadMoreComments: { [weak viewModel] in
                guard let viewModel else { return }
                await viewModel.loadMoreComments()
            }
        ) { comment in
                replySheetComment = comment
        }
    }

}

private extension View {
    @ViewBuilder
    func hideRootTabBarWhenNeeded(_ isHidden: Bool) -> some View {
        if isHidden {
            hidesRootTabBarOnPush()
        } else {
            self
        }
    }
}

private struct VideoDetailStandardPlaybackPageConfig {
    let screenSize: CGSize
    let standardHeight: CGFloat
    let isLandscape: Bool
    let isFullscreen: Bool
    let playerWidth: CGFloat?
    let playerHeight: CGFloat
    let fullscreenMode: PlayerFullscreenMode?
    let isDanmakuSettingsPresented: Bool
    let minimizesTabBarOnScroll: Bool
    let showsPinnedProgressBar: Bool
    let onRequestFullscreen: (PlayerStateViewModel) -> Void
    let onExitFullscreen: (() -> Void)?
    let onNavigateBack: () -> Void
    let onShowDanmakuSettings: () -> Void
}

private struct VideoDetailStandardPlaybackPage<DetailContent: View>: View {
    let config: VideoDetailStandardPlaybackPageConfig
    let viewModel: VideoDetailViewModel
    @Binding var selectedContentTab: VideoDetailContentTab
    let detailContent: (VideoDetailContentTab) -> DetailContent

    var body: some View {
        let hidesPortraitContent = config.isFullscreen
        let usesBlackBackdrop = config.isLandscape

        ZStack(alignment: .top) {
            Color.videoDetailBackground
                .ignoresSafeArea()

            if !config.isLandscape {
                VideoDetailNativeContentTabView(
                    selection: $selectedContentTab,
                    layoutWidth: config.screenSize.width,
                    topInset: config.standardHeight,
                    minimizesTabBarOnScroll: config.minimizesTabBarOnScroll,
                    content: detailContent
                )
                .frame(width: config.screenSize.width, height: config.screenSize.height, alignment: .top)
                .opacity(hidesPortraitContent ? 0 : 1)
                .allowsHitTesting(!config.isFullscreen)
                .animation(.easeOut(duration: 0.22), value: hidesPortraitContent)
            }

            if usesBlackBackdrop {
                Color.black
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            VideoDetailPlayerHero(
                playerIdentityStore: viewModel.playerIdentityRenderStore,
                surfaceStore: viewModel.playbackRenderStore.playerSurfaceStore,
                qualityControlStore: viewModel.playbackRenderStore.qualityControlStore,
                placeholderStore: viewModel.playbackRenderStore.placeholderStore,
                relatedStore: viewModel.relatedRenderStore,
                danmakuStore: viewModel.danmakuRenderStore,
                isLandscape: config.isLandscape,
                playerWidth: config.playerWidth,
                playerHeight: config.playerHeight,
                fullscreenMode: config.fullscreenMode,
                isDanmakuSettingsPresented: config.isDanmakuSettingsPresented,
                showsPinnedProgressBar: config.showsPinnedProgressBar,
                selectPlayVariant: { [weak viewModel] variant in
                    viewModel?.selectPlayVariant(variant)
                },
                onToggleDanmaku: { [weak viewModel] in
                    viewModel?.toggleDanmaku()
                },
                onPrepareForUserSeek: { [weak viewModel] progress in
                    viewModel?.prepareForUserSeek(toProgress: progress)
                },
                onDanmakuPlaybackTime: { [weak viewModel] currentTime, isLoadShedding in
                    viewModel?.updateDanmakuPlaybackTime(currentTime, underLoad: isLoadShedding)
                },
                onRequestFullscreen: config.onRequestFullscreen,
                onExitFullscreen: config.onExitFullscreen,
                onNavigateBack: config.onNavigateBack,
                onShowDanmakuSettings: config.onShowDanmakuSettings
            )
        }
        .frame(width: config.screenSize.width, height: config.screenSize.height)
    }
}

private struct VideoDetailNativeContentTabView<Content: View>: View {
    @Binding var selection: VideoDetailContentTab
    let layoutWidth: CGFloat
    let topInset: CGFloat
    let minimizesTabBarOnScroll: Bool
    let content: (VideoDetailContentTab) -> Content

    var body: some View {
        TabView(selection: $selection) {
            Tab(value: VideoDetailContentTab.detail) {
                tabScrollPage(.detail)
            } label: {
                Label(VideoDetailContentTab.detail.title, systemImage: VideoDetailContentTab.detail.systemImage)
            }

            Tab(value: VideoDetailContentTab.comments) {
                tabScrollPage(.comments)
            } label: {
                Label(VideoDetailContentTab.comments.title, systemImage: VideoDetailContentTab.comments.systemImage)
            }
        }
        .tint(.pink)
        .tabBarMinimizeBehavior(minimizesTabBarOnScroll ? .onScrollDown : .never)
        .background(Color.videoDetailBackground)
    }

    private func tabScrollPage(_ tab: VideoDetailContentTab) -> some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: topInset)

                content(tab)
                    .frame(width: layoutWidth, alignment: .top)
            }
        }
        .scrollIndicators(.hidden)
        .nativeTopScrollEdgeEffect()
        .frame(width: layoutWidth, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.videoDetailBackground)
    }
}

private struct VideoDetailInfoBlock: View {
    @ObservedObject var store: VideoDetailDescriptionRenderStore
    @State private var isExpanded = false

    var body: some View {
        Group {
            if store.hasResolvedDetailMetadata {
                resolvedContent
            } else {
                VideoDetailInfoLoadingPlaceholder(titleText: store.titleText)
            }
        }
    }

    private var resolvedContent: some View {
        let descriptionText = store.descriptionText
        let descriptionPreview = Self.collapsedDescriptionPreview(descriptionText)
        let hasDescriptionContent = descriptionPreview != nil
        let metadataText = metadataText(descriptionPreview: isExpanded ? nil : descriptionPreview)

        return VStack(alignment: .leading, spacing: 6) {
            VideoDetailInfoTitleText(text: titleText, isExpanded: isExpanded)

            HStack(alignment: .center, spacing: 8) {
                Text(metadataText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if hasDescriptionContent {
                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(isExpanded ? "收起视频简介" : "展开视频简介")
                }
            }
            .frame(height: 24, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .leading)

            if isExpanded {
                BiliLinkedText(
                    descriptionText,
                    font: UIFont.preferredFont(forTextStyle: .caption1),
                    textColor: .secondary
                )
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy(duration: 0.22), value: isExpanded)
    }

    private var titleText: String {
        if !store.titleText.isEmpty {
            return store.titleText
        }
        return "视频详情"
    }

    private func metadataText(descriptionPreview: String?) -> String {
        var parts = [String]()
        let ownerName = store.owner?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !ownerName.isEmpty {
            parts.append(ownerName)
        }

        if store.viewCountText != "-" {
            parts.append("\(store.viewCountText)观看")
        }

        if store.publishDateText != "-" {
            parts.append(store.publishDateText)
        }

        if let descriptionPreview {
            parts.append(descriptionPreview)
        }

        return parts.isEmpty ? "视频详情" : parts.joined(separator: "  ")
    }

    private static func collapsedDescriptionPreview(_ text: String) -> String? {
        let trimmed = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "这个视频暂时没有简介。" else { return nil }
        return trimmed
    }
}

private struct VideoDetailInfoLoadingPlaceholder: View {
    let titleText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                titleSkeleton
            } else {
                VideoDetailInfoTitleText(text: titleText, isExpanded: false)
            }

            VideoDetailMetadataLoadingRow()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleSkeleton: some View {
        VStack(alignment: .leading, spacing: 5) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.secondary.opacity(0.16))
                .frame(height: 17)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 17)
                .padding(.trailing, 96)
        }
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

private struct VideoDetailInfoTitleText: View {
    let text: String
    let isExpanded: Bool

    var body: some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .lineSpacing(1.5)
            .foregroundStyle(.primary)
            .lineLimit(isExpanded ? nil : 1)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct VideoDetailMetadataLoadingRow: View {
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .frame(maxWidth: 220)
                .frame(height: 12)

            Spacer(minLength: 0)

            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.secondary.opacity(0.28))
                .frame(width: 24, height: 24)
        }
        .frame(height: 24, alignment: .center)
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct VideoDetailPageMenu: View {
    @ObservedObject var store: VideoDetailPageSelectorRenderStore
    let selectPage: (VideoPage) -> Void

    var body: some View {
        if store.shouldShowPageSelector {
            Menu {
                ForEach(store.pages) { page in
                    Button {
                        selectPage(page)
                    } label: {
                        Label(
                            page.part ?? "第 \(page.page ?? 1) 集",
                            systemImage: page.cid == store.selectedCID ? "checkmark" : "play.rectangle"
                        )
                    }
                }
            } label: {
                Label(store.pageCountText, systemImage: "rectangle.stack")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}

private struct InitialPageMenuPlaceholder: View {
    let pageCount: Int

    var body: some View {
        Label("\(pageCount)P", systemImage: "rectangle.stack")
            .frame(maxWidth: .infinity)
            .buttonStylePlaceholder()
            .controlSize(.large)
            .opacity(0.42)
            .redacted(reason: .placeholder)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private extension View {
    func buttonStylePlaceholder() -> some View {
        frame(height: 36)
            .background(Color.videoDetailSecondarySurface.opacity(0.82), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.10), lineWidth: 0.7)
            }
    }
}

private struct VideoDetailFailureOverlay: View {
    @ObservedObject var placeholderStore: VideoDetailPlayerPlaceholderRenderStore
    let retry: () -> Void

    var body: some View {
        if let message = placeholderStore.failedMessage {
            ErrorStateView(
                title: "视频加载失败",
                message: message,
                retry: retry
            )
            .background(.background.opacity(0.95))
        }
    }
}

private struct VideoDetailPlayerHero: View {
    @ObservedObject var playerIdentityStore: VideoDetailPlayerIdentityRenderStore
    let surfaceStore: VideoDetailPlayerSurfaceRenderStore
    let qualityControlStore: VideoDetailQualityControlRenderStore
    let placeholderStore: VideoDetailPlayerPlaceholderRenderStore
    let relatedStore: VideoDetailRelatedRenderStore
    let danmakuStore: VideoDetailDanmakuRenderStore
    let isLandscape: Bool
    let playerWidth: CGFloat?
    let playerHeight: CGFloat
    let fullscreenMode: PlayerFullscreenMode?
    let isDanmakuSettingsPresented: Bool
    let showsPinnedProgressBar: Bool
    let selectPlayVariant: (PlayVariant) -> Void
    let onToggleDanmaku: () -> Void
    let onPrepareForUserSeek: (Double) -> Void
    let onDanmakuPlaybackTime: (TimeInterval, Bool) -> Void
    let onRequestFullscreen: (PlayerStateViewModel) -> Void
    let onExitFullscreen: (() -> Void)?
    let onNavigateBack: () -> Void
    let onShowDanmakuSettings: () -> Void

    var body: some View {
        Group {
            if let playerViewModel = playerIdentityStore.playerViewModel {
                ZStack {
                    VideoDetailPlayerSurface(
                        surfaceStore: surfaceStore,
                        qualityControlStore: qualityControlStore,
                        danmakuStore: danmakuStore,
                        playerViewModel: playerViewModel,
                        isLandscape: isLandscape,
                        playerWidth: playerWidth,
                        playerHeight: playerHeight,
                        fullscreenMode: fullscreenMode,
                        isDanmakuSettingsPresented: isDanmakuSettingsPresented,
                        selectPlayVariant: selectPlayVariant,
                        onToggleDanmaku: onToggleDanmaku,
                        onPrepareForUserSeek: onPrepareForUserSeek,
                        onDanmakuPlaybackTime: onDanmakuPlaybackTime,
                        onRequestFullscreen: onRequestFullscreen,
                        onExitFullscreen: onExitFullscreen,
                        onNavigateBack: handleBackButtonTap,
                        onShowDanmakuSettings: onShowDanmakuSettings
                    )

                    if playerIdentityStore.transitionSnapshot != nil
                        || playerIdentityStore.transitionFallbackCoverURL != nil {
                        VideoDetailPlayerTransitionMask(
                            snapshot: playerIdentityStore.transitionSnapshot,
                            fallbackCoverURL: playerIdentityStore.transitionFallbackCoverURL,
                            playerWidth: playerWidth,
                            playerHeight: playerHeight
                        )
                        .opacity(playerIdentityStore.transitionPlayerOpacity)
                        .zIndex(2)
                    }
                }
                .animation(
                    .easeInOut(duration: 0.28),
                    value: playerIdentityStore.transitionPlayerOpacity
                )
            } else {
                VideoDetailPlayerPlaceholder(
                    placeholderStore: placeholderStore,
                    relatedStore: relatedStore,
                    playerWidth: playerWidth,
                    playerHeight: playerHeight
                )
                .overlay(alignment: .topLeading) {
                    VideoDetailPlayerBackButton(action: handleBackButtonTap)
                        .padding(.top, 10)
                        .padding(.leading, 10)
                }
            }
        }
        .frame(width: playerWidth)
        .frame(maxWidth: .infinity)
        .frame(height: playerHeight)
        .overlay(alignment: .bottom) {
            if showsPinnedProgressBar,
               !isLandscape,
               fullscreenMode == nil {
                if let playerViewModel = playerIdentityStore.playerViewModel {
                    VideoDetailPinnedProgressBar(
                        playerViewModel: playerViewModel,
                        onPrepareSeek: onPrepareForUserSeek
                    )
                        .frame(width: playerWidth)
                        .frame(maxWidth: .infinity)
                        .frame(height: VideoDetailPinnedProgressBar.height)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    VideoDetailPinnedProgressPlaceholder()
                        .frame(width: playerWidth)
                        .frame(maxWidth: .infinity)
                        .frame(height: VideoDetailPinnedProgressBar.height)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .zIndex(1)
        .clipped()
    }

    private func handleBackButtonTap() {
        if let onExitFullscreen {
            onExitFullscreen()
        } else {
            onNavigateBack()
        }
    }
}

private struct VideoDetailPlayerTransitionMask: View {
    let snapshot: PlaybackTransitionSnapshot?
    let fallbackCoverURL: URL?
    let playerWidth: CGFloat?
    let playerHeight: CGFloat

    var body: some View {
        ZStack {
            Color.black
            if let image = snapshot?.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                CachedRemoteImage(
                    url: fallbackCoverURL,
                    targetPixelSize: 720,
                    animatesAppearance: false
                ) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    Color.black
                }
            }
        }
            .frame(width: playerWidth)
            .frame(height: playerHeight)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct VideoDetailPlayerSurface: View {
    @ObservedObject var surfaceStore: VideoDetailPlayerSurfaceRenderStore
    let qualityControlStore: VideoDetailQualityControlRenderStore
    let danmakuStore: VideoDetailDanmakuRenderStore
    let playerViewModel: PlayerStateViewModel
    let isLandscape: Bool
    let playerWidth: CGFloat?
    let playerHeight: CGFloat
    let fullscreenMode: PlayerFullscreenMode?
    let isDanmakuSettingsPresented: Bool
    let selectPlayVariant: (PlayVariant) -> Void
    let onToggleDanmaku: () -> Void
    let onPrepareForUserSeek: (Double) -> Void
    let onDanmakuPlaybackTime: (TimeInterval, Bool) -> Void
    let onRequestFullscreen: (PlayerStateViewModel) -> Void
    let onExitFullscreen: (() -> Void)?
    let onNavigateBack: () -> Void
    let onShowDanmakuSettings: () -> Void
    @State private var isShowingQualityControls = false
    private var usesLandscapePlaybackChrome: Bool {
        isLandscape || fullscreenMode?.isLandscape == true
    }
    var body: some View {
        BiliPlayerView(
            viewModel: playerViewModel,
            historyVideo: surfaceStore.historyVideo,
            historyCID: surfaceStore.historyCID,
            duration: surfaceStore.duration,
            presentation: usesLandscapePlaybackChrome ? .fullScreen : .embedded,
            showsNavigationChrome: false,
            showsStartupLoadingIndicator: false,
            pausesOnDisappear: false,
            surfaceOverlay: AnyView(playerSurfaceOverlay),
            controlsAccessory: AnyView(
                VideoDetailPlayerQualityControl(
                    store: qualityControlStore,
                    selectPlayVariant: selectPlayVariant,
                    onPresentationChange: { isShowingQualityControls = $0 }
                )
            ),
            topLeadingControlsAccessory: AnyView(VideoDetailPlayerBackButton(action: onNavigateBack)),
            isDanmakuEnabled: surfaceStore.isDanmakuEnabled,
            onToggleDanmaku: onToggleDanmaku,
            onShowDanmakuSettings: onShowDanmakuSettings,
            isSecondaryControlsPresented: isShowingQualityControls || isDanmakuSettingsPresented,
            embeddedAspectRatio: 16 / 9,
            keepsPlayerSurfaceStable: true,
            prefersNativePlaybackControls: VideoDetailPlaybackControlPolicy.prefersNativePlaybackControls,
            fullscreenMode: fullscreenMode,
            onPrepareForUserSeek: onPrepareForUserSeek,
            onRequestFullscreen: {
                onRequestFullscreen(playerViewModel)
            },
            onExitFullscreen: onExitFullscreen
        )
        .id(ObjectIdentifier(playerViewModel))
        .frame(width: playerWidth)
        .frame(height: playerHeight)
        .background(Color.black)
    }

    private var playerSurfaceOverlay: some View {
        ZStack {
            danmakuOverlay

            if let historyVideo = surfaceStore.historyVideo {
                PlaybackPosterOverlay(
                    video: historyVideo,
                    playerViewModel: playerViewModel,
                    dimOpacity: 0.36,
                    showsLoader: true
                )
            }
        }
    }

    private var danmakuOverlay: some View {
        VideoDetailDanmakuOverlay(
            store: danmakuStore,
            playerViewModel: playerViewModel,
            clock: playerViewModel.playbackClock,
            usesLandscapePlaybackChrome: usesLandscapePlaybackChrome,
            onPlaybackTime: onDanmakuPlaybackTime
        )
    }
}

private struct VideoDetailPlayerQualityControl: View {
    @Environment(\.playerNativeControlMetrics) private var controlMetrics
    @ObservedObject var store: VideoDetailQualityControlRenderStore
    let selectPlayVariant: (PlayVariant) -> Void
    let onPresentationChange: (Bool) -> Void
    @State private var isShowingQualityDialog = false

    var body: some View {
        if store.hasQualityMenu {
            Button {
                isShowingQualityDialog = true
            } label: {
                Text(store.qualityAccessoryButtonTitle)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .truncationMode(.tail)
                    .padding(.horizontal, controlMetrics.qualityHorizontalPadding)
                    .frame(maxWidth: controlMetrics.qualityButtonMaxWidth)
                    .frame(height: controlMetrics.controlHeight)
            }
            .biliPlayerCompactGlassCapsule(metrics: controlMetrics)
            .foregroundStyle(.white)
            .accessibilityLabel("清晰度")
            .confirmationDialog(
                "清晰度",
                isPresented: $isShowingQualityDialog,
                titleVisibility: .visible
            ) {
                if store.isSwitchingPlayQuality {
                    Button {} label: {
                        Label("正在切换清晰度", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(true)
                }

                ForEach(store.qualityMenuItems) { item in
                    Button {
                        selectPlayVariant(item.variant)
                    } label: {
                        Label(item.title, systemImage: item.systemImage)
                    }
                    .disabled(item.isDisabled)
                }
            }
            .onChange(of: isShowingQualityDialog) { _, isPresented in
                onPresentationChange(isPresented)
            }
            .onDisappear {
                onPresentationChange(false)
            }
        }
    }

}

private struct VideoDetailPlayerPlaceholder: View {
    @ObservedObject var placeholderStore: VideoDetailPlayerPlaceholderRenderStore
    @ObservedObject var relatedStore: VideoDetailRelatedRenderStore
    let playerWidth: CGFloat?
    let playerHeight: CGFloat
    @State private var isTakingLong = false

    var body: some View {
        ZStack {
            PlayerLoadingPlaceholder(
                progress: loadingProgress,
                message: loadingMessage,
                isFinishing: false,
                secondaryMessage: secondaryLoadingMessage,
                showsChromeSkeleton: true
            )
            .frame(width: playerWidth)
            .frame(height: playerHeight)
            .task(id: loadingMessage) {
                isTakingLong = false
                guard shouldWatchSlowLoading else { return }
                try? await Task.sleep(nanoseconds: 4_800_000_000)
                guard !Task.isCancelled, shouldWatchSlowLoading else { return }
                withAnimation(.smooth(duration: 0.24)) {
                    isTakingLong = true
                }
            }

            if !placeholderStore.playURLState.isLoading, placeholderStore.selectedPlayVariant != nil {
                Label("当前档位暂不可播放", systemImage: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.48))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .frame(width: playerWidth)
        .frame(height: playerHeight)
        .background(Color.black)
    }

    private var loadingProgress: Double {
        if placeholderStore.playURLState.isLoading {
            return 0.18
        }
        if placeholderStore.isDetailLoading {
            return 0.08
        }
        if relatedStore.state.isLoading {
            return 0.05
        }
        return 0
    }

    private var loadingMessage: String {
        if placeholderStore.playURLState.isLoading {
            return "连接播放线路"
        }
        if placeholderStore.isDetailLoading {
            return "加载视频信息"
        }
        if relatedStore.state.isLoading {
            return "准备相关推荐"
        }
        return "准备播放"
    }

    private var secondaryLoadingMessage: String? {
        guard isTakingLong else { return nil }
        if placeholderStore.playURLState.isLoading {
            return "网络较慢，继续保持连接"
        }
        if placeholderStore.isDetailLoading {
            return "视频信息响应较慢，仍在等待"
        }
        if relatedStore.state.isLoading {
            return "相关推荐稍后补齐，不影响播放"
        }
        return nil
    }

    private var shouldWatchSlowLoading: Bool {
        placeholderStore.playURLState.isLoading || placeholderStore.isDetailLoading || relatedStore.state.isLoading
    }
}

private struct VideoDetailPlayerBackButton: View {
    @Environment(\.playerNativeControlMetrics) private var controlMetrics
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.light()
            action()
        }) {
            Image(systemName: "chevron.left")
                .font(.system(size: controlMetrics.iconSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(
                    width: controlMetrics.controlHeight,
                    height: controlMetrics.controlHeight
                )
        }
        .biliPlayerCompactGlassCircle(metrics: controlMetrics)
        .accessibilityLabel("返回")
    }
}

private struct VideoDetailStatusBarBackdrop: View {
    let isHidden: Bool

    var body: some View {
        GeometryReader { proxy in
            if !isHidden {
                Color.black
                    .frame(height: proxy.safeAreaInsets.top)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(.container, edges: .top)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private extension Color {
    static let videoDetailBackground = Color(UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.075, green: 0.075, blue: 0.085, alpha: 1)
            : .systemGroupedBackground
    })

    static let videoDetailSurface = Color(UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.115, green: 0.115, blue: 0.128, alpha: 1)
            : .systemBackground
    })

    static let videoDetailSecondarySurface = Color(UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1)
            : .secondarySystemGroupedBackground
    })

    static let videoDetailGlassTint = Color(UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.055)
            : UIColor(white: 1, alpha: 0.74)
    })
}

private extension PlayerFullscreenMode {
    var videoDetailInterfaceOrientationMask: UIInterfaceOrientationMask {
        switch self {
        case .portrait:
            return .portrait
        case .landscape(let orientation):
            switch orientation {
            case .landscapeLeft:
                return .landscapeRight
            case .landscapeRight:
                return .landscapeLeft
            default:
                return .landscapeRight
            }
        }
    }
}
