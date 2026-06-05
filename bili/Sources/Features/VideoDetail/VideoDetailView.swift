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

struct VideoDetailView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    let seedVideo: VideoItem
    private let hidesRootTabBar: Bool

    @StateObject private var holder = VideoDetailViewModelHolder()
    @StateObject private var runtimeSettings = VideoDetailRuntimeSettingsStore()
    @State private var replySheetComment: Comment?
    @State private var manualFullscreenMode: ManualVideoFullscreenMode?
    @State private var isRestoringPortraitFromManualLandscape = false
    @State private var pendingManualLandscapeEnterTask: Task<Void, Never>?
    @State private var pendingManualLandscapeExitTask: Task<Void, Never>?
    @State private var lastManualLandscapeRequestTime: Date?
    @State private var manualFullscreenRequestMode: ManualVideoFullscreenMode?
    @State private var manualFullscreenRequestDeadline: Date?
    @State private var isShowingDanmakuSettings = false
    @State private var isShowingFavoriteFolders = false
    @State private var selectedDetailContentTab: VideoDetailContentTab = .detail

    init(
        seedVideo: VideoItem,
        hidesRootTabBar: Bool = true
    ) {
        self.seedVideo = seedVideo
        self.hidesRootTabBar = hidesRootTabBar
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
                    holder.viewModel?.resumePlaybackAfterCoveredNavigationIfNeeded()
                },
                onTransitionCompleted: { cancelled in
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
        .onAppear {
            runtimeSettings.bind(dependencies.libraryStore)
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            updateManualLandscapeOrientation(UIDevice.current.orientation)
            holder.viewModel?.resumePlaybackAfterCoveredNavigationIfNeeded()
        }
        .onDisappear {
            pendingManualLandscapeEnterTask?.cancel()
            pendingManualLandscapeExitTask?.cancel()
            holder.viewModel?.pausePlaybackForPotentialNavigation()
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            AppOrientationLock.restorePortrait()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            updateManualLandscapeOrientation(UIDevice.current.orientation)
        }
        .onReceive(NotificationCenter.default.publisher(for: .biliStopActiveVideoPlayback)) { _ in
            holder.viewModel?.stopPlaybackForNavigation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .biliPauseActiveVideoPlaybackForNavigation)) { _ in
            holder.viewModel?.pausePlaybackForPotentialNavigation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .biliResumeActiveVideoPlaybackAfterCancelledNavigation)) { _ in
            holder.viewModel?.resumePlaybackAfterCancelledNavigation()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            holder.viewModel?.recoverPlaybackAfterAppResume()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            holder.viewModel?.recoverPlaybackAfterAppResume()
        }
    }

    @ViewBuilder
    private func content(_ viewModel: VideoDetailViewModel) -> some View {
        GeometryReader { proxy in
            let fullscreenGeometry = proxy.fullscreenContainerGeometry
            let fullscreenSize = fullscreenGeometry.size
            let fullscreenOffset = fullscreenGeometry.offset
            let sceneIsLandscape = proxy.size.width > proxy.size.height
            let isManualFullscreen = manualFullscreenMode != nil
            let isRestoringPortrait = isRestoringPortraitFromManualLandscape
            let shouldReserveFullscreenChrome = isManualFullscreen || isRestoringPortrait
            let isLandscape = sceneIsLandscape && !shouldReserveFullscreenChrome
            let shouldHideSystemChrome = isLandscape || shouldReserveFullscreenChrome
            let isManualLandscapeFullscreen = manualFullscreenMode?.isLandscape == true
            let stablePortraitWidth = Self.stablePortraitLayoutWidth(
                proxySize: proxy.size,
                fullscreenSize: fullscreenSize
            )
            let layoutSize = isManualFullscreen
                ? (isManualLandscapeFullscreen
                    ? CGSize(width: max(proxy.size.width, proxy.size.height), height: min(proxy.size.width, proxy.size.height))
                    : CGSize(width: min(proxy.size.width, proxy.size.height), height: max(proxy.size.width, proxy.size.height)))
                : CGSize(width: stablePortraitWidth, height: proxy.size.height)

            standardPlaybackPage(
                viewModel,
                screenSize: isLandscape ? fullscreenSize : layoutSize,
                isLandscape: isLandscape
            )
            .frame(
                width: isLandscape ? fullscreenSize.width : layoutSize.width,
                height: isLandscape ? fullscreenSize.height : layoutSize.height
            )
            .offset(isLandscape ? fullscreenOffset : .zero)
            .background(isLandscape ? Color.black : Color.videoDetailBackground)
            .ignoresSafeArea(.container, edges: (isLandscape || shouldReserveFullscreenChrome) ? .all : [])
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
                        .padding(.top, isLandscape || isManualFullscreen ? 14 : 10)
                        .padding(.leading, 10)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
                }
            }
            .task {
                await viewModel.load()
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
        }
        .ignoresSafeArea(.container, edges: (manualFullscreenMode != nil || isRestoringPortraitFromManualLandscape) ? .all : [])
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
                    topInset: standardHeight
                ) { tab in
                    initialDetailScrollPage(layoutWidth: layoutWidth, tab: tab)
                }
                .frame(width: layoutWidth, height: proxy.size.height)

                PlayerLoadingPlaceholder(
                    progress: 0.08,
                    message: "加载视频信息",
                    isFinishing: false
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
                    VideoDetailPinnedProgressPlaceholder()
                        .frame(width: layoutWidth, height: VideoDetailPinnedProgressBar.height)
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

    private func updateManualLandscapeOrientation(_ orientation: UIDeviceOrientation) {
        guard !isRestoringPortraitFromManualLandscape else {
            if orientation.isPortrait {
                clearPendingManualFullscreenRequestIfNeeded(for: orientation)
            }
            return
        }
        if shouldIgnoreManualFullscreenOrientationChange(orientation) {
            return
        }
        switch orientation {
        case .landscapeLeft, .landscapeRight:
            pendingManualLandscapeExitTask?.cancel()
            isRestoringPortraitFromManualLandscape = false
            let mode: ManualVideoFullscreenMode = .landscape(orientation)
            guard manualFullscreenMode != mode else { return }
            pendingManualLandscapeEnterTask?.cancel()
            if shouldApplyManualLandscapeOrientation(orientation) {
                manualFullscreenMode = mode
            }
            clearPendingManualFullscreenRequestIfNeeded(for: orientation)
        case .portrait, .portraitUpsideDown:
            pendingManualLandscapeEnterTask?.cancel()
            clearPendingManualFullscreenRequestIfNeeded(for: orientation)
            guard manualFullscreenMode?.isLandscape == true else {
                pendingManualLandscapeExitTask?.cancel()
                return
            }
            pendingManualLandscapeExitTask?.cancel()
            beginRestoringPortraitFromManualLandscape()
        default:
            break
        }
    }

    private func standardPlaybackPage(
        _ viewModel: VideoDetailViewModel,
        screenSize: CGSize,
        isLandscape: Bool = false
    ) -> some View {
        let config = makeStandardPlaybackPageConfig(screenSize: screenSize, isLandscape: isLandscape)
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
        let isManualFullscreen: Bool = manualFullscreenMode != nil
        let expandsToFullscreen: Bool = isManualFullscreen || isLandscape
        let playerHeight: CGFloat = isLandscape ? screenSize.height : (isManualFullscreen ? screenSize.height : standardHeight)
        let playerWidth: CGFloat? = isLandscape ? screenSize.width : nil
        let activeManualFullscreenMode: ManualVideoFullscreenMode?
        let exitHandler: (() -> Void)?
        activeManualFullscreenMode = manualFullscreenMode
        exitHandler = manualFullscreenMode == nil ? nil : { exitManualLandscapePlayback() }

        return VideoDetailStandardPlaybackPageConfig(
            screenSize: screenSize,
            standardHeight: standardHeight,
            isLandscape: isLandscape,
            isManualFullscreen: isManualFullscreen,
            expandsToFullscreen: expandsToFullscreen,
            playerWidth: playerWidth,
            playerHeight: playerHeight,
            manualFullscreenMode: activeManualFullscreenMode,
            onRequestManualFullscreen: { playerViewModel in
                enterManualLandscapePlayback(playerViewModel: playerViewModel)
            },
            onExitManualFullscreen: exitHandler,
            onNavigateBack: {
                dismissVideoDetail()
            },
            onShowDanmakuSettings: {
                isShowingDanmakuSettings = true
            }
        )
    }

    private func dismissVideoDetail() {
        holder.viewModel?.stopPlaybackForNavigation()
        dismiss()
    }

    private func exitManualLandscapePlayback() {
        guard manualFullscreenMode != nil else { return }
        pendingManualLandscapeExitTask?.cancel()
        beginRestoringPortraitFromManualLandscape()
    }

    private func enterManualLandscapePlayback(playerViewModel: PlayerStateViewModel? = nil) {
        if let manualFullscreenMode {
            _ = requestManualFullscreenSurfaceEntry(
                mode: manualFullscreenMode,
                playerViewModel: playerViewModel
            )
            return
        }
        pendingManualLandscapeExitTask?.cancel()
        pendingManualLandscapeEnterTask?.cancel()
        isRestoringPortraitFromManualLandscape = false

        let deviceOrientation = UIDevice.current.orientation
        let targetMode: ManualVideoFullscreenMode
        if shouldUsePortraitFullscreen {
            targetMode = .portrait
        } else {
            targetMode = .landscape(deviceOrientation == .landscapeRight ? .landscapeRight : .landscapeLeft)
        }
        registerPendingManualFullscreenRequest(for: targetMode)
        if requestManualFullscreenSurfaceEntry(
            mode: targetMode,
            playerViewModel: playerViewModel
        ) {
            manualFullscreenMode = targetMode
        } else {
            manualFullscreenMode = targetMode
        }
        if let windowScene = UIApplication.shared.videoDetailKeyWindow?.windowScene {
            AppOrientationLock.update(to: targetMode.videoDetailInterfaceOrientationMask, in: windowScene)
            windowScene.requestGeometryUpdate(
                UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: targetMode.videoDetailInterfaceOrientationMask)
            ) { _ in }
        }
    }

    private func requestManualFullscreenSurfaceEntry(
        mode: ManualVideoFullscreenMode,
        playerViewModel: PlayerStateViewModel?
    ) -> Bool {
        guard let playerViewModel else { return false }
        let didEnter = playerViewModel.enterManualFullscreen(
            mode: mode,
            onExit: { exitManualLandscapePlayback() },
            animated: true
        )
        guard !didEnter else { return true }

        pendingManualLandscapeEnterTask?.cancel()
        pendingManualLandscapeEnterTask = Task { @MainActor in
            for attempt in 0..<8 {
                if attempt == 0 {
                    await Task.yield()
                } else {
                    try? await Task.sleep(nanoseconds: 60_000_000)
                }
                guard !Task.isCancelled, manualFullscreenMode == mode else { return }
                if playerViewModel.enterManualFullscreen(
                    mode: mode,
                    onExit: { exitManualLandscapePlayback() },
                    animated: attempt > 0
                ) {
                    break
                }
            }
            pendingManualLandscapeEnterTask = nil
        }
        return false
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

    private func beginRestoringPortraitFromManualLandscape() {
        guard manualFullscreenMode != nil else { return }
        pendingManualLandscapeEnterTask?.cancel()
        pendingManualLandscapeExitTask?.cancel()
        isRestoringPortraitFromManualLandscape = true
        let restoringMode = ManualVideoFullscreenMode.portrait
        registerPendingManualFullscreenRequest(for: restoringMode)
        manualFullscreenMode = restoringMode
        if let playerViewModel = holder.viewModel?.playerIdentityRenderStore.playerViewModel {
            _ = playerViewModel.enterManualFullscreen(
                mode: restoringMode,
                onExit: nil,
                animated: true
            )
        }
        if let windowScene = UIApplication.shared.videoDetailKeyWindow?.windowScene {
            AppOrientationLock.update(to: .portrait, in: windowScene)
            windowScene.requestGeometryUpdate(
                UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .portrait)
            ) { _ in }
        } else {
            AppOrientationLock.restorePortrait()
        }
        lastManualLandscapeRequestTime = nil

        pendingManualLandscapeExitTask = Task { @MainActor in
            for attempt in 0..<34 {
                if attempt == 0 {
                    await Task.yield()
                } else {
                    try? await Task.sleep(nanoseconds: 25_000_000)
                }
                guard !Task.isCancelled else { return }
                if Self.isVideoDetailWindowPortraitAndLaidOutOrUnavailable {
                    break
                }
            }

            guard !Task.isCancelled, manualFullscreenMode == restoringMode else { return }
            try? await Task.sleep(nanoseconds: 35_000_000)
            guard !Task.isCancelled, manualFullscreenMode == restoringMode else { return }
            clearPendingManualFullscreenRequest()
            manualFullscreenMode = nil
            isRestoringPortraitFromManualLandscape = false
            pendingManualLandscapeExitTask = nil
        }
    }

    private func shouldApplyManualLandscapeOrientation(_ orientation: UIDeviceOrientation) -> Bool {
        guard orientation.isLandscape else { return false }
        let now = Date()
        defer { lastManualLandscapeRequestTime = now }
        guard let lastManualLandscapeRequestTime else { return true }
        return now.timeIntervalSince(lastManualLandscapeRequestTime) > 0.34
    }

    private func registerPendingManualFullscreenRequest(for mode: ManualVideoFullscreenMode) {
        manualFullscreenRequestMode = mode
        manualFullscreenRequestDeadline = Date().addingTimeInterval(mode.isLandscape ? 0.9 : 0.45)
    }

    private func clearPendingManualFullscreenRequest() {
        manualFullscreenRequestMode = nil
        manualFullscreenRequestDeadline = nil
    }

    private func clearPendingManualFullscreenRequestIfNeeded(for orientation: UIDeviceOrientation) {
        guard let mode = manualFullscreenRequestMode else { return }
        switch mode {
        case .portrait:
            if orientation.isPortrait {
                clearPendingManualFullscreenRequest()
            }
        case .landscape:
            if orientation.isLandscape {
                clearPendingManualFullscreenRequest()
            }
        }
    }

    private func shouldIgnoreManualFullscreenOrientationChange(_ orientation: UIDeviceOrientation) -> Bool {
        guard let mode = manualFullscreenRequestMode,
              let deadline = manualFullscreenRequestDeadline
        else { return false }
        if Date() > deadline {
            clearPendingManualFullscreenRequest()
            return false
        }
        switch mode {
        case .portrait:
            return orientation.isLandscape
        case .landscape:
            return orientation.isPortrait
        }
    }

    private static var isVideoDetailWindowPortraitAndLaidOutOrUnavailable: Bool {
        guard let window = UIApplication.shared.videoDetailKeyWindow else { return true }
        let windowSize = window.bounds.size
        guard windowSize.width > 1, windowSize.height > 1 else { return false }

        let rootSize = window.rootViewController?.view.bounds.size ?? windowSize
        guard rootSize.width > 1, rootSize.height > 1 else { return false }

        let hasPortraitBounds = windowSize.height >= windowSize.width
            && rootSize.height >= rootSize.width
        if let orientation = window.windowScene?.effectiveGeometry.interfaceOrientation {
            return orientation.isPortrait && hasPortraitBounds
        }
        return hasPortraitBounds
    }

    private func detailCard(_ viewModel: VideoDetailViewModel, contentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VideoDetailInfoBlock(
                store: viewModel.descriptionRenderStore
            )
            actionStrip(viewModel, contentWidth: contentWidth)
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

    private func initialTitleInfoPlaceholder() -> some View {
        VStack(alignment: .leading, spacing: 7) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.18))
                .frame(height: 17)

            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 220, height: 12)

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .redacted(reason: .placeholder)
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
            loadMoreCommentsIfNeeded: { [weak viewModel] comment in
                guard let viewModel else { return }
                await viewModel.loadMoreCommentsIfNeeded(current: comment)
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
    let isManualFullscreen: Bool
    let expandsToFullscreen: Bool
    let playerWidth: CGFloat?
    let playerHeight: CGFloat
    let manualFullscreenMode: ManualVideoFullscreenMode?
    let onRequestManualFullscreen: (PlayerStateViewModel) -> Void
    let onExitManualFullscreen: (() -> Void)?
    let onNavigateBack: () -> Void
    let onShowDanmakuSettings: () -> Void
}

private struct VideoDetailStandardPlaybackPage<DetailContent: View>: View {
    let config: VideoDetailStandardPlaybackPageConfig
    let viewModel: VideoDetailViewModel
    @Binding var selectedContentTab: VideoDetailContentTab
    let detailContent: (VideoDetailContentTab) -> DetailContent

    var body: some View {
        ZStack(alignment: .top) {
            Color.videoDetailBackground
                .opacity(config.expandsToFullscreen ? 0 : 1)
                .ignoresSafeArea()

            if !config.isLandscape {
                VideoDetailNativeContentTabView(
                    selection: $selectedContentTab,
                    layoutWidth: config.screenSize.width,
                    topInset: config.standardHeight,
                    content: detailContent
                )
                .frame(width: config.screenSize.width, height: config.screenSize.height, alignment: .top)
                .opacity(config.isManualFullscreen ? 0 : 1)
                .allowsHitTesting(!config.isManualFullscreen)
            }

            if config.expandsToFullscreen {
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
                manualFullscreenMode: config.manualFullscreenMode,
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
                onRequestManualFullscreen: config.onRequestManualFullscreen,
                onExitManualFullscreen: config.onExitManualFullscreen,
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
        .tabBarMinimizeBehavior(.onScrollDown)
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
        let descriptionText = store.descriptionText
        let descriptionPreview = Self.collapsedDescriptionPreview(descriptionText)
        let hasDescriptionContent = descriptionPreview != nil
        let metadataText = metadataText(descriptionPreview: isExpanded ? nil : descriptionPreview)

        VStack(alignment: .leading, spacing: 6) {
            Text(titleText)
                .font(.callout.weight(.semibold))
                .lineSpacing(1.5)
                .foregroundStyle(.primary)
                .lineLimit(isExpanded ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

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
    let manualFullscreenMode: ManualVideoFullscreenMode?
    let selectPlayVariant: (PlayVariant) -> Void
    let onToggleDanmaku: () -> Void
    let onPrepareForUserSeek: (Double) -> Void
    let onDanmakuPlaybackTime: (TimeInterval, Bool) -> Void
    let onRequestManualFullscreen: (PlayerStateViewModel) -> Void
    let onExitManualFullscreen: (() -> Void)?
    let onNavigateBack: () -> Void
    let onShowDanmakuSettings: () -> Void

    var body: some View {
        Group {
            if let playerViewModel = playerIdentityStore.playerViewModel {
                VideoDetailPlayerSurface(
                    surfaceStore: surfaceStore,
                    qualityControlStore: qualityControlStore,
                    danmakuStore: danmakuStore,
                    playerViewModel: playerViewModel,
                    isLandscape: isLandscape,
                    playerWidth: playerWidth,
                    playerHeight: playerHeight,
                    manualFullscreenMode: manualFullscreenMode,
                    selectPlayVariant: selectPlayVariant,
                    onToggleDanmaku: onToggleDanmaku,
                    onPrepareForUserSeek: onPrepareForUserSeek,
                    onDanmakuPlaybackTime: onDanmakuPlaybackTime,
                    onRequestManualFullscreen: onRequestManualFullscreen,
                    onExitManualFullscreen: onExitManualFullscreen,
                    onNavigateBack: onNavigateBack,
                    onShowDanmakuSettings: onShowDanmakuSettings
                )
            } else {
                VideoDetailPlayerPlaceholder(
                    placeholderStore: placeholderStore,
                    relatedStore: relatedStore,
                    playerWidth: playerWidth,
                    playerHeight: playerHeight
                )
                .overlay(alignment: .topLeading) {
                    VideoDetailPlayerBackButton(action: onNavigateBack)
                        .padding(.top, 10)
                        .padding(.leading, 10)
                }
            }
        }
        .frame(width: playerWidth)
        .frame(maxWidth: .infinity)
        .frame(height: playerHeight)
        .overlay(alignment: .bottom) {
            if !isLandscape, manualFullscreenMode == nil {
                if let playerViewModel = playerIdentityStore.playerViewModel {
                    VideoDetailPinnedProgressBar(
                        playerViewModel: playerViewModel,
                        onPrepareSeek: onPrepareForUserSeek
                    )
                        .frame(width: playerWidth)
                        .frame(maxWidth: .infinity)
                        .frame(height: VideoDetailPinnedProgressBar.height)
                } else {
                    VideoDetailPinnedProgressPlaceholder()
                        .frame(width: playerWidth)
                        .frame(maxWidth: .infinity)
                        .frame(height: VideoDetailPinnedProgressBar.height)
                }
            }
        }
        .zIndex(1)
        .clipped()
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
    let manualFullscreenMode: ManualVideoFullscreenMode?
    let selectPlayVariant: (PlayVariant) -> Void
    let onToggleDanmaku: () -> Void
    let onPrepareForUserSeek: (Double) -> Void
    let onDanmakuPlaybackTime: (TimeInterval, Bool) -> Void
    let onRequestManualFullscreen: (PlayerStateViewModel) -> Void
    let onExitManualFullscreen: (() -> Void)?
    let onNavigateBack: () -> Void
    let onShowDanmakuSettings: () -> Void
    private var usesLandscapePlaybackChrome: Bool {
        isLandscape || manualFullscreenMode?.isLandscape == true
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
            surfaceOverlay: AnyView(danmakuOverlay),
            controlsAccessory: AnyView(
                VideoDetailPlayerQualityControl(
                    store: qualityControlStore,
                    selectPlayVariant: selectPlayVariant
                )
            ),
            topLeadingControlsAccessory: AnyView(VideoDetailPlayerBackButton(action: onNavigateBack)),
            isDanmakuEnabled: surfaceStore.isDanmakuEnabled,
            onToggleDanmaku: onToggleDanmaku,
            onShowDanmakuSettings: onShowDanmakuSettings,
            embeddedAspectRatio: 16 / 9,
            keepsPlayerSurfaceStable: true,
            prefersNativePlaybackControls: false,
            manualFullscreenMode: manualFullscreenMode,
            onPrepareForUserSeek: onPrepareForUserSeek,
            onRequestManualFullscreen: {
                onRequestManualFullscreen(playerViewModel)
            },
            onExitManualFullscreen: onExitManualFullscreen
        )
        .id(ObjectIdentifier(playerViewModel))
        .frame(width: playerWidth)
        .frame(height: playerHeight)
        .overlay {
            if let historyVideo = surfaceStore.historyVideo {
                PlaybackPosterOverlay(
                    video: historyVideo,
                    playerViewModel: playerViewModel,
                    dimOpacity: 0.36,
                    showsLoader: true
                )
            }
        }
        .background(Color.black)
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
    @ObservedObject var store: VideoDetailQualityControlRenderStore
    let selectPlayVariant: (PlayVariant) -> Void

    var body: some View {
        if store.hasQualityMenu {
            Menu {
                if store.isSupplementingPlayQualities {
                    Button {} label: {
                        Label("正在补全高清档位", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(true)
                }
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
            } label: {
                Text(store.qualityAccessoryButtonTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(minWidth: 54, minHeight: 30)
                    .padding(.horizontal, 5)
            }
            .foregroundStyle(.white)
            .biliPlayerYouTubePillStyle()
            .accessibilityLabel("清晰度")
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
                secondaryMessage: secondaryLoadingMessage
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
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.light()
            action()
        }) {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .background(Circle().fill(.black.opacity(0.34)))
        .contentShape(Circle())
        .foregroundStyle(.white)
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
