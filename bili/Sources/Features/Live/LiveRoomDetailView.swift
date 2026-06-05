import Combine
import SwiftUI
import UIKit

struct LiveRoomDetailView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    let seedRoom: LiveRoom
    @StateObject private var holder = LiveRoomViewModelHolder()
    @State private var hidesPlayerSystemChrome = false

    var body: some View {
        Group {
            if let viewModel = holder.viewModel {
                LiveRoomContentView(viewModel: viewModel)
            } else {
                LiveRoomInitialPlaceholder(room: seedRoom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task {
                        holder.configure(
                            room: seedRoom,
                            api: dependencies.api,
                            libraryStore: dependencies.libraryStore
                        )
                    }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                livePrincipalToolbarContent
            }
            ToolbarItem(placement: .topBarTrailing) {
                liveShareToolbarButton
            }
        }
        .toolbar(hidesPlayerSystemChrome ? .hidden : .visible, for: .navigationBar)
        .background(Color.videoDetailBackground)
        .hidesRootTabBarOnPush(restoreDelay: 180_000_000)
        .onPreferenceChange(LiveDetailChromeHiddenPreferenceKey.self) { isHidden in
            hidesPlayerSystemChrome = isHidden
        }
    }

    @ViewBuilder
    private var livePrincipalToolbarContent: some View {
        let viewModel = holder.viewModel
        let owner = viewModel?.anchorOwner ?? seedRoom.anchorOwner
        if owner.mid > 0 {
            NavigationLink(value: owner) {
                DetailNavigationOwnerFollowGroup(
                    avatarURLString: owner.face,
                    name: owner.name,
                    subtitle: liveToolbarSubtitle
                ) {
                    liveFollowToolbarButton
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开 \(owner.name) 的主页")
        } else {
            DetailNavigationOwnerFollowGroup(
                avatarURLString: owner.face,
                name: owner.name,
                subtitle: liveToolbarSubtitle
            ) {
                liveFollowToolbarButton
            }
        }
    }

    private var liveToolbarSubtitle: String? {
        guard let viewModel = holder.viewModel else {
            return seedRoom.isLive ? "直播中" : nil
        }
        if let liveTimeText = viewModel.liveTimeText, !liveTimeText.isEmpty {
            return "开播于 \(liveTimeText)"
        }
        return viewModel.isLive ? "直播中" : "未开播"
    }

    @ViewBuilder
    private var liveFollowToolbarButton: some View {
        if let viewModel = holder.viewModel {
            DetailToolbarFollowButton(
                isFollowing: viewModel.isFollowingAnchor,
                isLoading: viewModel.isMutatingAnchorFollow,
                canFollow: viewModel.anchorUIDForFollow != nil
            ) {
                Haptics.light()
                Task {
                    await viewModel.toggleFollowAnchor()
                    Haptics.success()
                }
            }
        } else {
            DetailToolbarFollowButton(
                isFollowing: false,
                isLoading: true,
                canFollow: false,
                action: {}
            )
            .hidden()
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var liveShareToolbarButton: some View {
        let roomID = holder.viewModel?.roomID ?? seedRoom.roomID
        let title = holder.viewModel?.title ?? seedRoom.title
        if let url = LiveRoomDetailView.liveShareURL(roomID: roomID) {
            ShareLink(
                item: url,
                subject: Text(title),
                message: Text(title)
            )
            .simultaneousGesture(TapGesture().onEnded { Haptics.light() })
            .accessibilityLabel("分享直播间")
        } else {
            Button {} label: {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(true)
            .accessibilityLabel("分享直播间")
        }
    }

    private static func liveShareURL(roomID: Int) -> URL? {
        guard roomID > 0 else { return nil }
        return URL(string: "https://live.bilibili.com/\(roomID)")
    }
}

private struct LiveRoomContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var viewModel: LiveRoomViewModel
    @State private var isShowingDescription = false
    @State private var manualFullscreenMode: ManualVideoFullscreenMode?
    @State private var isRestoringPortraitFromManualLandscape = false
    @State private var pendingManualLandscapeEnterTask: Task<Void, Never>?
    @State private var pendingManualLandscapeExitTask: Task<Void, Never>?

    private static let supportedLiveOrientations: UIInterfaceOrientationMask = [
        .portrait,
        .landscapeLeft,
        .landscapeRight
    ]

    var body: some View {
        GeometryReader { proxy in
            let fullscreenGeometry = proxy.liveDetailFullscreenContainerGeometry
            let fullscreenSize = fullscreenGeometry.size
            let fullscreenOffset = fullscreenGeometry.offset
            let sceneIsLandscape = proxy.size.width > proxy.size.height
            let isManualFullscreen = manualFullscreenMode != nil || isRestoringPortraitFromManualLandscape
            let isLandscape = sceneIsLandscape && !isManualFullscreen
            let shouldHideSystemChrome = isLandscape || isManualFullscreen
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
                isLandscape: isLandscape,
                isManualFullscreen: isManualFullscreen
            )
            .frame(
                width: isLandscape ? fullscreenSize.width : layoutSize.width,
                height: isLandscape ? fullscreenSize.height : layoutSize.height
            )
            .offset(isLandscape ? fullscreenOffset : .zero)
            .background(isLandscape ? Color.black : Color.videoDetailBackground)
            .ignoresSafeArea(.container, edges: (isLandscape || isManualFullscreen) ? .all : [])
            .preference(key: LiveDetailChromeHiddenPreferenceKey.self, value: shouldHideSystemChrome)
            .statusBar(hidden: shouldHideSystemChrome)
            .persistentSystemOverlays(shouldHideSystemChrome ? .hidden : .automatic)
            .background {
                LiveStatusBarStyleBridge(
                    style: (isLandscape || isManualFullscreen) ? .lightContent : .default,
                    isHidden: shouldHideSystemChrome
                )
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
            }
        }
        .background(Color.videoDetailBackground)
        .overlay {
            if case .failed(let message) = viewModel.state, viewModel.playerViewModel == nil {
                ErrorStateView(title: "直播加载失败", message: message, retry: viewModel.reload)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.videoDetailBackground.opacity(0.96))
            }
        }
        .task(id: viewModel.roomID) {
            viewModel.startLoading()
        }
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            allowLiveAutoRotation()
            updateLiveManualOrientation(UIDevice.current.orientation)
        }
        .onDisappear {
            pendingManualLandscapeEnterTask?.cancel()
            pendingManualLandscapeExitTask?.cancel()
            viewModel.stopPlaybackForNavigation()
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            AppOrientationLock.restorePortrait()
            manualFullscreenMode = nil
            isRestoringPortraitFromManualLandscape = false
        }
        .sheet(isPresented: $isShowingDescription) {
            LiveRoomDescriptionSheet(viewModel: viewModel)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                if manualFullscreenMode == nil {
                    allowLiveAutoRotation()
                }
                viewModel.resumeLiveDanmakuIfNeeded()
            case .background:
                viewModel.suspendLiveDanmaku()
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            updateLiveManualOrientation(UIDevice.current.orientation)
        }
        .ignoresSafeArea(.container, edges: (manualFullscreenMode != nil || isRestoringPortraitFromManualLandscape) ? .all : [])
    }

    private static func stablePortraitLayoutWidth(proxySize: CGSize, fullscreenSize: CGSize) -> CGFloat {
        let proxyShortSide = min(proxySize.width, proxySize.height)
        let fullscreenShortSide = min(fullscreenSize.width, fullscreenSize.height)
        let windowShortSide = UIApplication.shared.liveDetailForegroundKeyWindow.map { window in
            min(window.bounds.width, window.bounds.height)
        } ?? .greatestFiniteMagnitude
        return min(proxyShortSide, fullscreenShortSide, windowShortSide)
    }

    private func allowLiveAutoRotation() {
        AppOrientationLock.update(
            to: Self.supportedLiveOrientations,
            in: UIApplication.shared.liveDetailForegroundKeyWindow?.windowScene
        )
    }

    private func updateLiveManualOrientation(_ orientation: UIDeviceOrientation) {
        switch orientation {
        case .landscapeLeft, .landscapeRight:
            guard manualFullscreenMode?.isLandscape != true else { return }
            enterManualLandscapePlayback(playerViewModel: viewModel.playerViewModel)
        case .portrait, .portraitUpsideDown:
            guard manualFullscreenMode?.isLandscape == true else { return }
            exitManualLandscapePlayback(playerViewModel: viewModel.playerViewModel)
        default:
            break
        }
    }

    private func standardPlaybackPage(
        _ viewModel: LiveRoomViewModel,
        screenSize: CGSize,
        isLandscape: Bool,
        isManualFullscreen: Bool
    ) -> some View {
        let standardHeight = screenSize.width * 9 / 16
        let expandsToFullscreen = isLandscape || isManualFullscreen
        let playerHeight = expandsToFullscreen ? screenSize.height : standardHeight
        let playerWidth: CGFloat? = isLandscape ? screenSize.width : nil

        return ZStack(alignment: .top) {
            Color.videoDetailBackground
                .opacity(expandsToFullscreen ? 0 : 1)
                .ignoresSafeArea()

            if !isLandscape {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: standardHeight)

                    ScrollView(.vertical) {
                        detailScrollPage(viewModel, layoutWidth: screenSize.width)
                            .frame(width: screenSize.width, alignment: .top)
                    }
                    .scrollIndicators(.hidden)
                    .nativeTopScrollEdgeEffect()
                    .frame(width: screenSize.width, alignment: .top)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .opacity(isManualFullscreen ? 0 : 1)
                    .allowsHitTesting(!isManualFullscreen)
                }
                .frame(width: screenSize.width, height: screenSize.height, alignment: .top)
            }

            if expandsToFullscreen {
                Color.black
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            playerHero(
                viewModel,
                isLandscape: isLandscape,
                playerWidth: playerWidth,
                playerHeight: playerHeight
            )
        }
        .frame(width: screenSize.width, height: screenSize.height)
    }

    private func playerHero(
        _ viewModel: LiveRoomViewModel,
        isLandscape: Bool,
        playerWidth: CGFloat?,
        playerHeight: CGFloat
    ) -> some View {
        let usesLandscapeChrome = isLandscape || manualFullscreenMode?.isLandscape == true
        return ZStack {
            if let playerViewModel = viewModel.playerViewModel {
                BiliPlayerView(
                    viewModel: playerViewModel,
                    presentation: usesLandscapeChrome ? .fullScreen : .embedded,
                    showsNavigationChrome: false,
                    showsStartupLoadingIndicator: false,
                    pausesOnDisappear: false,
                    surfaceOverlay: AnyView(
                        LiveDanmakuOverlay(
                            store: viewModel.liveDanmakuRenderStore,
                            playerViewModel: playerViewModel,
                            usesLandscapeChrome: usesLandscapeChrome
                        )
                    ),
                    controlsAccessory: usesLandscapeChrome ? AnyView(livePlayerAccessory(viewModel)) : nil,
                    isDanmakuEnabled: viewModel.isDanmakuEnabled,
                    onToggleDanmaku: {
                        viewModel.toggleDanmaku()
                    },
                    embeddedAspectRatio: 16 / 9,
                    keepsPlayerSurfaceStable: true,
                    prefersNativePlaybackControls: false,
                    manualFullscreenMode: manualFullscreenMode,
                    onRequestManualFullscreen: {
                        enterManualLandscapePlayback(playerViewModel: playerViewModel)
                    },
                    onExitManualFullscreen: {
                        exitManualLandscapePlayback(playerViewModel: playerViewModel)
                    }
                )
                .id(ObjectIdentifier(playerViewModel))
                .frame(width: playerWidth)
                .frame(height: playerHeight)
            } else {
                liveLoadingPlaceholder(viewModel)
                    .frame(width: playerWidth)
                    .frame(height: playerHeight)
            }
            if let message = viewModel.streamFallbackMessage, viewModel.playerViewModel?.hasPresentedPlayback != true {
                Text(message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.56))
                    .clipShape(Capsule())
            }
            if viewModel.isLiveDanmakuDiagnosticsEnabled {
                LiveDanmakuDiagnosticsOverlay(
                    store: viewModel.liveDanmakuRenderStore.diagnosticsStore,
                    usesLandscapeChrome: usesLandscapeChrome
                )
            }
        }
        .frame(width: playerWidth)
        .frame(maxWidth: .infinity)
        .frame(height: playerHeight)
        .background(Color.black)
        .zIndex(1)
        .clipped()
        .overlay(alignment: .topTrailing) {
            liveTopPlayerTools(viewModel)
                .padding(.top, 10)
                .padding(.trailing, 10)
                .zIndex(100)
        }
    }

    private func detailScrollPage(_ viewModel: LiveRoomViewModel, layoutWidth: CGFloat) -> some View {
        let horizontalPadding: CGFloat = 12
        let contentWidth = max(layoutWidth - horizontalPadding * 2, 0)

        return VStack(alignment: .leading, spacing: 10) {
            liveDetailControls(viewModel, contentWidth: contentWidth)
                .padding(.horizontal, horizontalPadding)
        }
        .padding(.top, 12)
        .frame(width: layoutWidth, alignment: .top)
        .background(Color.videoDetailBackground)
    }

    private func liveDetailControls(_ viewModel: LiveRoomViewModel, contentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    Button {
                        isShowingDescription = true
                    } label: {
                        LiveInlineMetadataButtonLabel(title: "简介", systemImage: "text.alignleft")
                    }
                    .buttonStyle(.plain)

                    liveStreamInlineMenu(viewModel)

                    liveQualityInlineMenu(viewModel)

                    Button {
                        viewModel.toggleDanmaku()
                    } label: {
                        LiveInlineMetadataButtonLabel(
                            title: viewModel.isDanmakuEnabled ? "弹幕开" : "弹幕关",
                            systemImage: viewModel.isDanmakuEnabled ? "text.bubble.fill" : "text.bubble"
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(viewModel.isDanmakuEnabled ? .pink : .secondary)

                    Button {
                        viewModel.toggleLiveDanmakuDiagnostics()
                    } label: {
                        LiveInlineMetadataButtonLabel(
                            title: viewModel.isLiveDanmakuDiagnosticsEnabled ? "诊断开" : "诊断",
                            systemImage: "waveform.path.ecg"
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(viewModel.isLiveDanmakuDiagnosticsEnabled ? .pink : .secondary)

                    LiveInlineMetadataButtonLabel(
                        title: viewModel.isLive ? "直播中" : "未开播",
                        systemImage: viewModel.isLive ? "dot.radiowaves.left.and.right" : "pause.circle"
                    )
                    .foregroundStyle(viewModel.isLive ? .pink : .secondary)
                }
                .frame(height: 32)
            }
            .scrollIndicators(.hidden)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)

            liveActionStrip(viewModel, contentWidth: contentWidth)
            liveStatusNotice(viewModel)
        }
        .frame(width: contentWidth, alignment: .leading)
    }

    private func liveActionStrip(_ viewModel: LiveRoomViewModel, contentWidth: CGFloat) -> some View {
        let columnSpacing: CGFloat = 6
        let columnWidth = max((contentWidth - columnSpacing * 2) / 3, 1)

        return HStack(spacing: columnSpacing) {
            liveActionContent(
                title: viewModel.onlineActionText,
                systemImage: "person.2.fill",
                foregroundStyle: .secondary
            )
            .frame(width: columnWidth, height: 46)

            liveActionContent(
                title: viewModel.areaActionText,
                systemImage: "tag.fill",
                foregroundStyle: .secondary
            )
            .frame(width: columnWidth, height: 46)

            liveActionContent(
                title: viewModel.isFollowingAnchor ? "已关注" : "主播",
                systemImage: viewModel.isFollowingAnchor ? "person.crop.circle.badge.checkmark.fill" : "person.crop.circle.fill",
                foregroundStyle: viewModel.isFollowingAnchor ? .pink : .secondary
            )
            .frame(width: columnWidth, height: 46)
        }
        .frame(width: contentWidth, height: 50, alignment: .center)
        .padding(.vertical, 2)
    }

    private func liveActionContent(title: String, systemImage: String, foregroundStyle: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
            Text(title)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .foregroundStyle(foregroundStyle)
    }

    @ViewBuilder
    private func liveStatusNotice(_ viewModel: LiveRoomViewModel) -> some View {
        if let message = viewModel.streamFallbackMessage, !message.isEmpty {
            Label(message, systemImage: "antenna.radiowaves.left.and.right")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let message = viewModel.interactionMessage, !message.isEmpty {
            Label(message, systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if case .failed(let message) = viewModel.state {
            Label(message, systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func enterManualLandscapePlayback(playerViewModel: PlayerStateViewModel? = nil) {
        if let manualFullscreenMode {
            requestManualFullscreenSurfaceEntry(
                mode: manualFullscreenMode,
                playerViewModel: playerViewModel
            )
            return
        }

        pendingManualLandscapeExitTask?.cancel()
        pendingManualLandscapeEnterTask?.cancel()
        isRestoringPortraitFromManualLandscape = false

        let orientation = UIDevice.current.orientation
        let targetMode = ManualVideoFullscreenMode.landscape(orientation.isLandscape ? orientation : .landscapeRight)
        manualFullscreenMode = targetMode

        if let windowScene = UIApplication.shared.liveDetailForegroundKeyWindow?.windowScene {
            AppOrientationLock.update(to: targetMode.liveDetailInterfaceOrientationMask, in: windowScene)
            windowScene.requestGeometryUpdate(
                UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: targetMode.liveDetailInterfaceOrientationMask)
            ) { _ in }
        }

        if requestManualFullscreenSurfaceEntry(
            mode: targetMode,
            playerViewModel: playerViewModel
        ) {
            return
        }

        pendingManualLandscapeEnterTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled, manualFullscreenMode == targetMode else { return }
            _ = requestManualFullscreenSurfaceEntry(
                mode: targetMode,
                playerViewModel: playerViewModel
            )
        }
    }

    private func exitManualLandscapePlayback(playerViewModel: PlayerStateViewModel? = nil) {
        guard manualFullscreenMode != nil else { return }
        pendingManualLandscapeEnterTask?.cancel()
        pendingManualLandscapeExitTask?.cancel()
        isRestoringPortraitFromManualLandscape = true
        let restoringMode = ManualVideoFullscreenMode.portrait
        manualFullscreenMode = restoringMode

        if let playerViewModel {
            _ = playerViewModel.enterManualFullscreen(
                mode: restoringMode,
                onExit: nil,
                animated: true
            )
        }
        requestLivePortraitGeometry()

        pendingManualLandscapeExitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 320_000_000)
            guard !Task.isCancelled else { return }
            manualFullscreenMode = nil
            isRestoringPortraitFromManualLandscape = false
            allowLiveAutoRotation()
        }
    }

    private func requestLivePortraitGeometry() {
        if let windowScene = UIApplication.shared.liveDetailForegroundKeyWindow?.windowScene {
            AppOrientationLock.update(to: Self.supportedLiveOrientations, in: windowScene)
            windowScene.requestGeometryUpdate(
                UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .portrait)
            ) { _ in }
        } else {
            AppOrientationLock.update(to: Self.supportedLiveOrientations, in: nil)
        }
    }

    @discardableResult
    private func requestManualFullscreenSurfaceEntry(
        mode: ManualVideoFullscreenMode,
        playerViewModel: PlayerStateViewModel?
    ) -> Bool {
        guard let playerViewModel else { return false }
        return playerViewModel.enterManualFullscreen(
            mode: mode,
            onExit: {
                exitManualLandscapePlayback(playerViewModel: playerViewModel)
            },
            animated: true
        )
    }

    @ViewBuilder
    private func liveStreamMenu(_ viewModel: LiveRoomViewModel) -> some View {
        if viewModel.hasMultipleStreamCandidates || viewModel.currentStreamTitle != nil {
            Menu {
                ForEach(viewModel.streamMenuItems) { item in
                    Button {
                        viewModel.selectStreamCandidate(id: item.id)
                    } label: {
                        if item.isSelected {
                            Label(item.title, systemImage: "checkmark")
                        } else {
                            Text(item.title)
                        }
                    }
                }
            } label: {
                Label(viewModel.currentStreamTitle ?? "线路", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .biliPlayerGlassButtonStyle()
            .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private func liveQualityMenu(_ viewModel: LiveRoomViewModel) -> some View {
        if viewModel.hasMultipleQualities || viewModel.currentQualityTitle != nil {
            Menu {
                ForEach(viewModel.qualityMenuItems) { item in
                    Button {
                        viewModel.selectQuality(qn: item.qn)
                    } label: {
                        if item.isSelected {
                            Label(item.title, systemImage: "checkmark")
                        } else {
                            Text(item.title)
                        }
                    }
                }
            } label: {
                Label(viewModel.currentQualityTitle ?? "画质", systemImage: "slider.horizontal.3")
                    .font(.caption.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .biliPlayerGlassButtonStyle()
            .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private func liveStreamInlineMenu(_ viewModel: LiveRoomViewModel) -> some View {
        if viewModel.hasMultipleStreamCandidates || viewModel.currentStreamTitle != nil {
            Menu {
                ForEach(viewModel.streamMenuItems) { item in
                    Button {
                        viewModel.selectStreamCandidate(id: item.id)
                    } label: {
                        Label(
                            item.title,
                            systemImage: item.isSelected ? "checkmark" : "antenna.radiowaves.left.and.right"
                        )
                    }
                }
            } label: {
                LiveInlineMetadataButtonLabel(
                    title: viewModel.currentStreamTitle ?? "线路",
                    systemImage: "antenna.radiowaves.left.and.right"
                )
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        } else {
            LiveInlineMetadataButtonLabel(
                title: "线路",
                systemImage: "antenna.radiowaves.left.and.right"
            )
            .opacity(0.45)
        }
    }

    @ViewBuilder
    private func liveQualityInlineMenu(_ viewModel: LiveRoomViewModel) -> some View {
        if viewModel.hasMultipleQualities || viewModel.currentQualityTitle != nil {
            Menu {
                ForEach(viewModel.qualityMenuItems) { item in
                    Button {
                        viewModel.selectQuality(qn: item.qn)
                    } label: {
                        Label(
                            item.title,
                            systemImage: item.isSelected ? "checkmark" : "slider.horizontal.3"
                        )
                    }
                }
            } label: {
                LiveInlineMetadataButtonLabel(
                    title: viewModel.currentQualityTitle ?? "画质",
                    systemImage: "slider.horizontal.3"
                )
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        } else {
            LiveInlineMetadataButtonLabel(
                title: "画质",
                systemImage: "slider.horizontal.3"
            )
            .opacity(0.45)
        }
    }

    private func liveTopPlayerTools(_ viewModel: LiveRoomViewModel) -> some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                liveDanmakuDiagnosticsButton(viewModel)
                liveQualityMenu(viewModel)
                liveStreamMenu(viewModel)
            }
        }
        .fixedSize()
        .allowsHitTesting(true)
    }

    private func liveDanmakuDiagnosticsButton(_ viewModel: LiveRoomViewModel) -> some View {
        Button {
            Haptics.light()
            viewModel.toggleLiveDanmakuDiagnostics()
        } label: {
            Label(
                viewModel.isLiveDanmakuDiagnosticsEnabled ? "诊断开" : "诊断",
                systemImage: "waveform.path.ecg"
            )
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .biliPlayerGlassButtonStyle(prominent: viewModel.isLiveDanmakuDiagnosticsEnabled)
        .foregroundStyle(.white)
        .contentShape(Capsule())
        .accessibilityLabel(viewModel.isLiveDanmakuDiagnosticsEnabled ? "关闭直播弹幕诊断" : "开启直播弹幕诊断")
    }

    private func livePlayerAccessory(_ viewModel: LiveRoomViewModel) -> some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                liveQualityMenu(viewModel)
                liveStreamMenu(viewModel)
                Spacer(minLength: 0)

                Button {
                    viewModel.toggleDanmaku()
                } label: {
                    Label(
                        viewModel.isDanmakuEnabled ? "弹幕开" : "弹幕关",
                        systemImage: viewModel.isDanmakuEnabled ? "text.bubble.fill" : "text.bubble"
                    )
                    .font(.caption.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .biliPlayerGlassButtonStyle(prominent: viewModel.isDanmakuEnabled)
                .tint(viewModel.isDanmakuEnabled ? .white : .secondary)
                .accessibilityLabel(viewModel.isDanmakuEnabled ? "关闭直播弹幕" : "开启直播弹幕")

                Button {
                    viewModel.toggleLiveDanmakuDiagnostics()
                } label: {
                    Label(
                        viewModel.isLiveDanmakuDiagnosticsEnabled ? "诊断开" : "诊断",
                        systemImage: "waveform.path.ecg"
                    )
                    .font(.caption.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .biliPlayerGlassButtonStyle(prominent: viewModel.isLiveDanmakuDiagnosticsEnabled)
                .tint(viewModel.isLiveDanmakuDiagnosticsEnabled ? .white : .secondary)
                .accessibilityLabel(viewModel.isLiveDanmakuDiagnosticsEnabled ? "关闭直播弹幕诊断" : "开启直播弹幕诊断")
            }
        }
    }

    @ViewBuilder
    private func liveLoadingPlaceholder(_ viewModel: LiveRoomViewModel) -> some View {
        ZStack {
            Color.black

            if case .failed(let message) = viewModel.state {
                LivePlayerFailurePlaceholder(message: message, retry: viewModel.reload)
            } else {
                LivePlayerLoadingPlaceholder(
                    title: viewModel.title.nilIfEmpty ?? "正在进入直播间",
                    subtitle: viewModel.currentQualityTitle ?? viewModel.currentStreamTitle ?? "正在拉取直播流"
                )
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
    }
}

private struct LiveRoomInitialPlaceholder: View {
    let room: LiveRoom

    var body: some View {
        VStack(spacing: 12) {
            LivePlayerLoadingPlaceholder(
                title: room.title.nilIfEmpty ?? "正在进入直播间",
                subtitle: room.uname.nilIfEmpty ?? "准备直播信息"
            )
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .mediaShadow(.control)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 12)
        .background(Color.videoDetailBackground)
    }
}

private struct LivePlayerLoadingPlaceholder: View {
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            Color.black

            VStack(spacing: 10) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.05)

                VStack(spacing: 4) {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.90))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .padding(.horizontal, 24)
            }
        }
    }
}

private struct LivePlayerFailurePlaceholder: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)

            Text("直播加载失败")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))

            Text(message)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 28)

            Button(action: retry) {
                Label("重试", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.pink)
        }
    }
}

private struct LiveDanmakuOverlay: View {
    @ObservedObject var store: LiveDanmakuRenderStore
    @ObservedObject var playerViewModel: PlayerStateViewModel
    let usesLandscapeChrome: Bool

    var body: some View {
        let shouldDriveLiveDanmaku = playerViewModel.isPlaying || playerViewModel.wantsAutoplay

        DanmakuOverlayView(
            items: store.items,
            itemsRevision: store.itemsRevision,
            currentTime: store.playbackTime,
            isPlaying: shouldDriveLiveDanmaku,
            playbackRate: 1,
            isEnabled: store.isEnabled,
            hasPresentedPlayback: playerViewModel.hasPresentedPlayback || shouldDriveLiveDanmaku,
            settings: store.settings,
            topInset: usesLandscapeChrome ? 28 : 8,
            bottomInset: usesLandscapeChrome ? 84 : 54
        )
        .padding(.horizontal, usesLandscapeChrome ? 18 : 4)
    }
}

private struct LiveDanmakuDiagnosticsOverlay: View {
    @ObservedObject var store: LiveDanmakuDiagnosticsStore
    let usesLandscapeChrome: Bool

    var body: some View {
        VStack {
            HStack(alignment: .top) {
                LiveDanmakuDiagnosticsHUD(
                    snapshot: store.snapshot,
                    isExpanded: usesLandscapeChrome
                )
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, usesLandscapeChrome ? 46 : 10)
        .padding(.leading, usesLandscapeChrome ? 18 : 8)
        .padding(.trailing, 8)
        .allowsHitTesting(false)
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
    }
}

@MainActor
final class LiveDanmakuRenderStore: ObservableObject {
    @Published private(set) var items: [DanmakuItem] = []
    @Published private(set) var itemsRevision = 0
    @Published private(set) var playbackTime: TimeInterval = 0
    @Published private(set) var isEnabled: Bool
    @Published private(set) var settings: DanmakuSettings
    let diagnosticsStore: LiveDanmakuDiagnosticsStore

    init(
        isEnabled: Bool,
        settings: DanmakuSettings,
        diagnostics: LiveDanmakuDiagnosticSnapshot
    ) {
        self.isEnabled = isEnabled
        self.settings = settings.normalized
        self.diagnosticsStore = LiveDanmakuDiagnosticsStore(snapshot: diagnostics)
    }

    var itemCount: Int {
        items.count
    }

    func updateEnabled(_ isEnabled: Bool) {
        guard self.isEnabled != isEnabled else { return }
        self.isEnabled = isEnabled
    }

    func updateSettings(_ settings: DanmakuSettings) {
        let normalized = settings.normalized
        guard self.settings != normalized else { return }
        self.settings = normalized
    }

    func updatePlaybackTime(_ playbackTime: TimeInterval) {
        let sanitizedTime = max(0, playbackTime)
        guard abs(self.playbackTime - sanitizedTime) >= 0.1 || sanitizedTime == 0 else { return }
        self.playbackTime = sanitizedTime
    }

    func appendItems(_ newItems: [DanmakuItem], retainingLimit limit: Int) {
        guard !newItems.isEmpty else { return }
        items.append(contentsOf: newItems)
        if items.count > limit {
            items.removeFirst(items.count - limit)
        }
        itemsRevision &+= 1
    }

    func clearItems() {
        guard !items.isEmpty else { return }
        items.removeAll()
        itemsRevision &+= 1
    }

    func updateDiagnostics(_ diagnostics: LiveDanmakuDiagnosticSnapshot) {
        diagnosticsStore.update(diagnostics)
    }
}

@MainActor
final class LiveDanmakuDiagnosticsStore: ObservableObject {
    @Published private(set) var snapshot: LiveDanmakuDiagnosticSnapshot

    init(snapshot: LiveDanmakuDiagnosticSnapshot) {
        self.snapshot = snapshot
    }

    func update(_ snapshot: LiveDanmakuDiagnosticSnapshot) {
        guard self.snapshot != snapshot else { return }
        self.snapshot = snapshot
    }
}

@MainActor
private final class LiveRoomViewModelHolder: ObservableObject {
    @Published var viewModel: LiveRoomViewModel?
    private var cancellable: AnyCancellable?
    private var lastSnapshot: LiveRoomToolbarSnapshot?

    func configure(room: LiveRoom, api: BiliAPIClient, libraryStore: LibraryStore) {
        guard viewModel == nil else { return }
        let viewModel = LiveRoomViewModel(seedRoom: room, api: api, libraryStore: libraryStore)
        self.viewModel = viewModel
        lastSnapshot = LiveRoomToolbarSnapshot(viewModel)
        cancellable = viewModel.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self, weak viewModel] in
                guard let self, let viewModel else { return }
                let snapshot = LiveRoomToolbarSnapshot(viewModel)
                guard snapshot != self.lastSnapshot else { return }
                self.lastSnapshot = snapshot
                self.objectWillChange.send()
            }
        }
    }
}

private struct LiveRoomToolbarSnapshot: Equatable {
    let roomID: Int
    let title: String
    let anchorOwner: VideoOwner
    let liveTimeText: String?
    let isLive: Bool
    let isFollowingAnchor: Bool
    let isMutatingAnchorFollow: Bool
    let anchorUIDForFollow: Int?

    init(_ viewModel: LiveRoomViewModel) {
        roomID = viewModel.roomID
        title = viewModel.title
        anchorOwner = viewModel.anchorOwner
        liveTimeText = viewModel.liveTimeText
        isLive = viewModel.isLive
        isFollowingAnchor = viewModel.isFollowingAnchor
        isMutatingAnchorFollow = viewModel.isMutatingAnchorFollow
        anchorUIDForFollow = viewModel.anchorUIDForFollow
    }
}

@MainActor
final class LiveRoomViewModel: ObservableObject {
    @Published private(set) var roomSummary: LiveRoomSummary?
    @Published private(set) var roomInfo: LiveRoomInfo?
    @Published private(set) var anchorInfo: LiveAnchorInfoData?
    @Published private(set) var playerViewModel: PlayerStateViewModel?
    @Published var state: LoadingState = .idle
    @Published private(set) var streamFallbackMessage: String?
    @Published private(set) var streamMenuItems: [LiveStreamMenuItem] = []
    @Published private(set) var qualityMenuItems: [LiveStreamQualityMenuItem] = []
    @Published private(set) var currentQualityTitle: String?
    @Published var isDanmakuEnabled: Bool
    @Published private(set) var danmakuSettings: DanmakuSettings
    @Published var isLiveDanmakuDiagnosticsEnabled = false
    @Published private(set) var isMutatingAnchorFollow = false
    @Published private(set) var interactionMessage: String?

    let seedRoom: LiveRoom
    let liveDanmakuRenderStore: LiveDanmakuRenderStore
    private let api: BiliAPIClient
    private let libraryStore: LibraryStore
    private var streamCandidates: [LiveStreamURLCandidate] = []
    private var availableQualities: [LiveStreamQuality] = []
    private var currentCandidateIndex = 0
    private var selectedQualityQN: Int?
    private var loadingTask: Task<Void, Never>?
    private var metadataTask: Task<Void, Never>?
    private var qualitySwitchTask: Task<Void, Never>?
    private var startupWatchdogTask: Task<Void, Never>?
    private var playbackStallWatchdogTask: Task<Void, Never>?
    private var liveDanmakuService: LiveDanmakuService?
    private var liveDanmakuStartupTask: Task<Void, Never>?
    private var liveDanmakuClockTask: Task<Void, Never>?
    private var liveDanmakuStartDate: Date?
    private var liveDanmakuDiagnosticsDraft = LiveDanmakuDiagnosticSnapshot(roomID: 0)
    private var cancellables = Set<AnyCancellable>()
    private var loadGeneration = 0

    init(seedRoom: LiveRoom, api: BiliAPIClient, libraryStore: LibraryStore) {
        self.seedRoom = seedRoom
        self.api = api
        self.libraryStore = libraryStore
        self.isDanmakuEnabled = libraryStore.danmakuEnabled
        self.danmakuSettings = libraryStore.danmakuSettings
        let initialDiagnostics = LiveDanmakuDiagnosticSnapshot(roomID: seedRoom.roomID)
        self.liveDanmakuDiagnosticsDraft = initialDiagnostics
        self.liveDanmakuRenderStore = LiveDanmakuRenderStore(
            isEnabled: libraryStore.danmakuEnabled,
            settings: libraryStore.danmakuSettings,
            diagnostics: initialDiagnostics
        )
        self.liveDanmakuRenderStore.updateSettings(self.effectiveDanmakuSettings)
        libraryStore.$danmakuEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                self?.applyGlobalDanmakuEnabled(isEnabled)
            }
            .store(in: &cancellables)
        libraryStore.$danmakuSettings
            .removeDuplicates()
            .sink { [weak self] settings in
                guard let self else { return }
                self.danmakuSettings = settings.normalized
                self.liveDanmakuRenderStore.updateSettings(self.effectiveDanmakuSettings)
            }
            .store(in: &cancellables)
    }

    deinit {
        loadingTask?.cancel()
        metadataTask?.cancel()
        qualitySwitchTask?.cancel()
        startupWatchdogTask?.cancel()
        playbackStallWatchdogTask?.cancel()
        liveDanmakuStartupTask?.cancel()
        liveDanmakuClockTask?.cancel()
        liveDanmakuService?.stop()
    }

    var roomID: Int {
        roomInfo?.roomID ?? roomSummary?.roomID ?? seedRoom.roomID
    }

    var title: String {
        let value = roomInfo?.title ?? roomSummary?.title ?? seedRoom.title
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "直播间" : value
    }

    var coverURL: String? {
        (roomInfo?.displayCover ?? roomSummary?.cover ?? seedRoom.displayCover)?.normalizedBiliURL()
    }

    var areaText: String? {
        [roomInfo?.parentAreaName ?? seedRoom.parentAreaName, roomInfo?.areaName ?? seedRoom.areaName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
            .nilIfEmpty
    }

    var onlineText: String {
        let online = roomInfo?.online ?? roomSummary?.online ?? seedRoom.online
        guard let online, online > 0 else { return "在线人数 -" }
        return "在线 \(BiliFormatters.compactCount(online))"
    }

    var onlineActionText: String {
        let online = roomInfo?.online ?? roomSummary?.online ?? seedRoom.online
        guard let online, online > 0 else { return "-" }
        return BiliFormatters.compactCount(online)
    }

    var areaActionText: String {
        roomInfo?.areaName?.nilIfEmpty
            ?? seedRoom.areaName?.nilIfEmpty
            ?? roomInfo?.parentAreaName?.nilIfEmpty
            ?? seedRoom.parentAreaName?.nilIfEmpty
            ?? "分区"
    }

    var liveTimeText: String? {
        roomInfo?.liveTime?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var descriptionText: String? {
        roomInfo?.description?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var anchorName: String {
        anchorInfo?.info?.uname?.nilIfEmpty ?? seedRoom.uname
    }

    var anchorFace: String? {
        anchorInfo?.info?.face?.normalizedBiliURL() ?? seedRoom.face?.normalizedBiliURL()
    }

    var anchorUIDForFollow: Int? {
        let uid = anchorInfo?.info?.uid ?? roomInfo?.uid ?? seedRoom.uid
        guard let uid, uid > 0 else { return nil }
        return uid
    }

    var anchorOwner: VideoOwner {
        VideoOwner(mid: anchorUIDForFollow ?? 0, name: anchorName, face: anchorFace)
    }

    var isFollowingAnchor: Bool {
        (anchorInfo?.relationInfo?.attention ?? 0) > 0
    }

    var isLive: Bool {
        if let roomInfo {
            return roomInfo.isLive
        }
        if let liveStatus = roomSummary?.liveStatus {
            return liveStatus == 1
        }
        return seedRoom.isLive
    }

    var hasMultipleStreamCandidates: Bool {
        streamMenuItems.count > 1
    }

    var hasMultipleQualities: Bool {
        qualityMenuItems.count > 1
    }

    var effectiveDanmakuSettings: DanmakuSettings {
        var settings = danmakuSettings.normalized
        settings.loadFactor = min(settings.loadFactor, 0.75)
        return settings
    }

    var currentStreamTitle: String? {
        guard streamCandidates.indices.contains(currentCandidateIndex) else { return nil }
        return Self.streamTitle(for: streamCandidates[currentCandidateIndex], index: currentCandidateIndex)
    }

    func startLoading() {
        guard playerViewModel == nil else { return }
        guard loadingTask == nil else { return }
        let generation = nextLoadGeneration()
        loadingTask = Task { [weak self] in
            await self?.loadFromNetwork(generation: generation)
        }
    }

    func reload() {
        stopCurrentLoadAndPlayback()
        streamCandidates = []
        availableQualities = []
        currentCandidateIndex = 0
        selectedQualityQN = nil
        updateStreamMenuItems()
        updateQualityMenuItems()
        streamFallbackMessage = nil
        state = .idle
        startLoading()
    }

    func stopPlaybackForNavigation() {
        stopCurrentLoadAndPlayback()
        streamCandidates = []
        availableQualities = []
        currentCandidateIndex = 0
        selectedQualityQN = nil
        updateStreamMenuItems()
        updateQualityMenuItems()
        streamFallbackMessage = nil
        if state.isLoading {
            state = .idle
        }
    }

    private func stopCurrentLoadAndPlayback() {
        loadGeneration += 1
        loadingTask?.cancel()
        metadataTask?.cancel()
        qualitySwitchTask?.cancel()
        startupWatchdogTask?.cancel()
        playbackStallWatchdogTask?.cancel()
        liveDanmakuStartupTask?.cancel()
        loadingTask = nil
        metadataTask = nil
        qualitySwitchTask = nil
        startupWatchdogTask = nil
        playbackStallWatchdogTask = nil
        liveDanmakuStartupTask = nil
        playerViewModel?.onPlaybackFailure = nil
        playerViewModel?.stop()
        playerViewModel = nil
        stopLiveDanmaku(clearItems: true)
    }

    private func nextLoadGeneration() -> Int {
        loadGeneration += 1
        return loadGeneration
    }

    private func isCurrentLoad(_ generation: Int) -> Bool {
        generation == loadGeneration
    }

    private func loadFromNetwork(generation: Int) async {
        guard isCurrentLoad(generation), playerViewModel == nil else {
            loadingTask = nil
            return
        }
        state = .loading
        defer {
            if isCurrentLoad(generation) {
                loadingTask = nil
            }
        }
        let api = self.api
        let roomID: Int
        if seedRoom.roomID > 0 {
            roomID = seedRoom.roomID
        } else if let uid = seedRoom.uid, uid > 0 {
            do {
                let summary = try await api.fetchLiveRoomSummary(uid: uid)
                guard !Task.isCancelled, isCurrentLoad(generation) else { return }
                roomSummary = summary
                roomID = summary.roomID
            } catch {
                guard !Task.isCancelled, isCurrentLoad(generation) else { return }
                state = .failed("没有找到这个 UP 的直播间")
                return
            }
        } else {
            state = .failed("这条直播动态缺少直播间信息")
            return
        }

        let resolvedRoomID = roomID
        metadataTask = Task { [weak self] in
            await self?.loadRoomMetadata(roomID: resolvedRoomID, generation: generation)
        }

        do {
            let streamResult = try await api.fetchLiveStreamInfo(roomID: resolvedRoomID, quality: selectedQualityQN)
            guard !Task.isCancelled, isCurrentLoad(generation) else { return }
            let candidates = streamResult.candidates
            guard let firstCandidate = candidates.first else {
                state = .failed("没有获取到可播放的直播流")
                return
            }
            streamCandidates = candidates
            availableQualities = streamResult.playableQualities
            currentCandidateIndex = Self.preferredCandidateIndex(
                in: candidates,
                preferredQuality: selectedQualityQN,
                preferredSource: nil
            )
            selectedQualityQN = candidates[currentCandidateIndex].currentQN ?? selectedQualityQN
            updateStreamMenuItems()
            updateQualityMenuItems()
            let selectedCandidate = streamCandidates.indices.contains(currentCandidateIndex)
                ? streamCandidates[currentCandidateIndex]
                : firstCandidate
            installPlayer(for: selectedCandidate, generation: generation)
            if let playerViewModel {
                scheduleLiveDanmakuStart(roomID: resolvedRoomID, playerViewModel: playerViewModel, generation: generation)
            }
            state = .loaded
        } catch {
            guard !Task.isCancelled, isCurrentLoad(generation) else { return }
            if roomInfo?.isLive == false || seedRoom.isLive == false {
                state = .failed("这个直播间当前未开播")
            } else {
                state = .failed("没有获取到可播放的直播流：\(error.localizedDescription)")
            }
        }
    }

    private func installPlayer(for candidate: LiveStreamURLCandidate, generation: Int) {
        guard isCurrentLoad(generation) else { return }
        startupWatchdogTask?.cancel()
        playbackStallWatchdogTask?.cancel()
        playerViewModel?.onPlaybackFailure = nil
        playerViewModel?.stop()

        let viewModel = PlayerStateViewModel(
            videoURL: candidate.url,
            audioURL: nil,
            videoStream: nil,
            audioStream: nil,
            title: title,
            referer: "https://live.bilibili.com/\(roomID)",
            metricsID: "live-\(roomID)-\(currentCandidateIndex)",
            engine: DefaultPlayerRenderingEngine.make()
        )
        viewModel.onPlaybackFailure = { [weak self] message in
            self?.handlePlaybackFailure(message: message, generation: generation)
        }
        playerViewModel = viewModel
        refreshLiveDanmakuDiagnosticsRenderState()
        updateStreamMenuItems()
        updateQualityMenuItems()
        scheduleStartupWatchdog(for: viewModel, generation: generation)
        schedulePlaybackStallWatchdog(for: viewModel, generation: generation)
    }

    private func handlePlaybackFailure(message: String?, generation: Int) {
        guard isCurrentLoad(generation) else { return }
        startupWatchdogTask?.cancel()
        guard currentCandidateIndex + 1 < streamCandidates.count else {
            streamFallbackMessage = nil
            playerViewModel?.onPlaybackFailure = nil
            playerViewModel?.stop()
            playerViewModel = nil
            state = .failed(message ?? "这个直播流暂时无法播放")
            return
        }

        currentCandidateIndex += 1
        streamFallbackMessage = "正在切换到 \(currentStreamTitle ?? "备用直播源")"
        state = .loading
        installPlayer(for: streamCandidates[currentCandidateIndex], generation: generation)
        state = .loaded
        playerViewModel?.play()
    }

    func selectStreamCandidate(id: Int) {
        guard streamCandidates.indices.contains(id), id != currentCandidateIndex else { return }
        let generation = loadGeneration
        currentCandidateIndex = id
        updateStreamMenuItems()
        streamFallbackMessage = "正在切换到 \(currentStreamTitle ?? "直播线路")"
        state = .loading
        installPlayer(for: streamCandidates[id], generation: generation)
        state = .loaded
        playerViewModel?.play()
    }

    func selectQuality(qn: Int) {
        guard qn > 0, qn != selectedQualityQN || currentQualityTitle == nil else { return }
        let generation = loadGeneration
        qualitySwitchTask?.cancel()
        qualitySwitchTask = Task { [weak self] in
            await self?.switchQuality(to: qn, generation: generation)
        }
    }

    func toggleDanmaku() {
        isDanmakuEnabled.toggle()
        libraryStore.setDanmakuEnabled(isDanmakuEnabled)
        refreshLiveDanmakuDiagnosticsRenderState()
        if isDanmakuEnabled {
            resumeLiveDanmakuIfNeeded()
        } else {
            stopLiveDanmaku(clearItems: true)
        }
    }

    func toggleLiveDanmakuDiagnostics() {
        isLiveDanmakuDiagnosticsEnabled.toggle()
        refreshLiveDanmakuDiagnosticsRenderState(forcePublish: true)
        if isLiveDanmakuDiagnosticsEnabled {
            resumeLiveDanmakuIfNeeded()
        }
    }

    func toggleFollowAnchor() async {
        guard !isMutatingAnchorFollow else { return }
        guard let uid = anchorUIDForFollow else {
            interactionMessage = "没有找到主播 UID，无法关注"
            return
        }

        isMutatingAnchorFollow = true
        interactionMessage = nil
        let targetState = !isFollowingAnchor
        do {
            try await api.setUploaderFollowing(mid: uid, following: targetState)
            let roomID = self.roomID
            if roomID > 0 {
                anchorInfo = try? await api.fetchLiveAnchorInfo(roomID: roomID)
            }
            interactionMessage = targetState ? "已关注主播" : "已取消关注"
        } catch {
            interactionMessage = "关注操作失败：\(error.localizedDescription)"
        }
        isMutatingAnchorFollow = false
    }

    func suspendLiveDanmaku() {
        stopLiveDanmaku(clearItems: false)
    }

    func resumeLiveDanmakuIfNeeded() {
        guard isDanmakuEnabled, playerViewModel != nil, roomID > 0 else { return }
        startLiveDanmakuIfNeeded(roomID: roomID)
    }

    private func switchQuality(to qn: Int, generation: Int) async {
        guard isCurrentLoad(generation), roomID > 0 else { return }
        let previousCandidate = streamCandidates.indices.contains(currentCandidateIndex)
            ? streamCandidates[currentCandidateIndex]
            : nil
        streamFallbackMessage = "正在切换到 \(LiveStreamQuality.defaultTitle(for: qn))"
        state = .loading
        do {
            let streamResult = try await api.fetchLiveStreamInfo(roomID: roomID, quality: qn)
            guard !Task.isCancelled, isCurrentLoad(generation) else { return }
            guard !streamResult.candidates.isEmpty else {
                streamFallbackMessage = "这个画质暂时不可用"
                state = .loaded
                return
            }
            streamCandidates = streamResult.candidates
            availableQualities = streamResult.playableQualities
            currentCandidateIndex = Self.preferredCandidateIndex(
                in: streamResult.candidates,
                preferredQuality: qn,
                preferredSource: previousCandidate
            )
            let selectedCandidate = streamCandidates[currentCandidateIndex]
            selectedQualityQN = qn
            updateStreamMenuItems()
            updateQualityMenuItems()
            if selectedCandidate.currentQN != qn {
                streamFallbackMessage = "该画质暂不可用，已切到 \(currentQualityTitle ?? "可用画质")"
            } else {
                streamFallbackMessage = nil
            }
            installPlayer(for: selectedCandidate, generation: generation)
            state = .loaded
            playerViewModel?.play()
        } catch {
            guard !Task.isCancelled, isCurrentLoad(generation) else { return }
            streamFallbackMessage = "画质切换失败：\(error.localizedDescription)"
            updateQualityMenuItems()
            state = playerViewModel == nil ? .failed(streamFallbackMessage ?? "画质切换失败") : .loaded
        }
    }

    private func scheduleStartupWatchdog(for viewModel: PlayerStateViewModel, generation: Int) {
        startupWatchdogTask = Task { [weak self, weak viewModel] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      let viewModel,
                      self.isCurrentLoad(generation),
                      self.playerViewModel === viewModel,
                      !viewModel.hasPresentedPlayback
                else { return }
                self.handlePlaybackFailure(message: "直播流首帧加载超时", generation: generation)
            }
        }
    }

    private func schedulePlaybackStallWatchdog(for viewModel: PlayerStateViewModel, generation: Int) {
        playbackStallWatchdogTask = Task { [weak self, weak viewModel] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      let viewModel,
                      self.isCurrentLoad(generation),
                      self.playerViewModel === viewModel,
                      viewModel.hasPresentedPlayback
                else { return }
            }

            var lastTime = await MainActor.run { viewModel?.currentTime ?? 0 }
            var stalledChecks = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard !Task.isCancelled else { return }
                let shouldSwitch = await MainActor.run { () -> Bool in
                    guard let self,
                          let viewModel,
                          self.isCurrentLoad(generation),
                          self.playerViewModel === viewModel
                    else { return false }
                    if viewModel.errorMessage != nil {
                        return true
                    }
                    guard viewModel.wantsAutoplay else {
                        stalledChecks = 0
                        lastTime = viewModel.currentTime
                        return false
                    }
                    let currentTime = viewModel.currentTime
                    if viewModel.isBuffering || abs(currentTime - lastTime) < 0.1 {
                        stalledChecks += 1
                    } else {
                        stalledChecks = 0
                    }
                    lastTime = currentTime
                    return stalledChecks >= 2 && self.currentCandidateIndex + 1 < self.streamCandidates.count
                }
                guard shouldSwitch else { continue }
                await MainActor.run {
                    self?.handlePlaybackFailure(message: "直播流长时间无画面", generation: generation)
                }
                return
            }
        }
    }

    private func updateStreamMenuItems() {
        streamMenuItems = streamCandidates.indices.map { index in
            LiveStreamMenuItem(
                id: index,
                title: Self.streamTitle(for: streamCandidates[index], index: index),
                isSelected: index == currentCandidateIndex
            )
        }
    }

    private func updateQualityMenuItems() {
        let currentQN = streamCandidates.indices.contains(currentCandidateIndex)
            ? streamCandidates[currentCandidateIndex].currentQN
            : selectedQualityQN
        let qualities = availableQualities.isEmpty
            ? LiveStreamQuality.merged(
                streamCandidates.compactMap { candidate in
                    candidate.currentQN.map {
                        LiveStreamQuality(qn: $0, description: candidate.qualityTitle)
                    }
                }
            )
            : availableQualities
        qualityMenuItems = qualities.map { quality in
            LiveStreamQualityMenuItem(
                qn: quality.qn,
                title: quality.title,
                isSelected: quality.qn == currentQN || (currentQN == nil && quality.qn == selectedQualityQN)
            )
        }
        if let currentQN {
            currentQualityTitle = qualities.first(where: { $0.qn == currentQN })?.title
                ?? LiveStreamQuality.defaultTitle(for: currentQN)
        } else {
            currentQualityTitle = nil
        }
    }

    private func applyGlobalDanmakuEnabled(_ isEnabled: Bool) {
        guard isDanmakuEnabled != isEnabled else { return }
        isDanmakuEnabled = isEnabled
        liveDanmakuRenderStore.updateEnabled(isEnabled)
        refreshLiveDanmakuDiagnosticsRenderState()
        if isEnabled {
            resumeLiveDanmakuIfNeeded()
        } else {
            stopLiveDanmaku(clearItems: true)
        }
    }

    private func startLiveDanmakuIfNeeded(roomID: Int) {
        guard isDanmakuEnabled, liveDanmakuService == nil else { return }
        liveDanmakuStartDate = Date()
        liveDanmakuRenderStore.updatePlaybackTime(0)
        let service = LiveDanmakuService(
            roomID: roomID,
            api: api,
            onDiagnostics: { [weak self] event in
                self?.handleLiveDanmakuDiagnosticEvent(event)
            },
            onItems: { [weak self] items in
                self?.appendLiveDanmakuItems(items)
            }
        )
        liveDanmakuService = service
        service.start()
        startLiveDanmakuClock()
    }

    private func scheduleLiveDanmakuStart(
        roomID: Int,
        playerViewModel: PlayerStateViewModel,
        generation: Int
    ) {
        liveDanmakuStartupTask?.cancel()
        guard isDanmakuEnabled else { return }
        liveDanmakuStartupTask = Task { [weak self, weak playerViewModel] in
            let pollIntervalNanoseconds: UInt64 = 150_000_000
            let maximumWaitNanoseconds: UInt64 = 1_800_000_000
            var waitedNanoseconds: UInt64 = 0

            while !Task.isCancelled, waitedNanoseconds < maximumWaitNanoseconds {
                let shouldStart = await MainActor.run { () -> Bool in
                    guard let self,
                          let playerViewModel,
                          self.isCurrentLoad(generation),
                          self.playerViewModel === playerViewModel
                    else { return false }
                    return playerViewModel.hasPresentedPlayback || playerViewModel.errorMessage != nil
                }
                if shouldStart { break }
                try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
                waitedNanoseconds += pollIntervalNanoseconds
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      let playerViewModel,
                      self.isCurrentLoad(generation),
                      self.playerViewModel === playerViewModel
                else { return }
                self.liveDanmakuStartupTask = nil
                self.startLiveDanmakuIfNeeded(roomID: roomID)
            }
        }
    }

    private func stopLiveDanmaku(clearItems: Bool) {
        liveDanmakuStartupTask?.cancel()
        liveDanmakuStartupTask = nil
        liveDanmakuService?.stop()
        liveDanmakuService = nil
        liveDanmakuClockTask?.cancel()
        liveDanmakuClockTask = nil
        liveDanmakuStartDate = nil
        liveDanmakuRenderStore.updatePlaybackTime(0)
        if clearItems {
            liveDanmakuRenderStore.clearItems()
        }
        refreshLiveDanmakuDiagnosticsRenderState()
    }

    private func startLiveDanmakuClock() {
        liveDanmakuClockTask?.cancel()
        liveDanmakuClockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, let liveDanmakuStartDate = self.liveDanmakuStartDate else { return }
                    self.liveDanmakuRenderStore.updatePlaybackTime(
                        max(0, Date().timeIntervalSince(liveDanmakuStartDate))
                    )
                }
            }
        }
    }

    private func appendLiveDanmakuItems(_ items: [DanmakuItem]) {
        guard isDanmakuEnabled, !items.isEmpty else { return }
        liveDanmakuRenderStore.appendItems(items, retainingLimit: 240)
        if let liveDanmakuStartDate {
            liveDanmakuRenderStore.updatePlaybackTime(max(0, Date().timeIntervalSince(liveDanmakuStartDate)))
        }
        refreshLiveDanmakuDiagnosticsRenderState()
    }

    private func handleLiveDanmakuDiagnosticEvent(_ event: LiveDanmakuDiagnosticEvent) {
        liveDanmakuDiagnosticsDraft.apply(event)
        applyCurrentRenderStateToDiagnosticsDraft()
        publishLiveDanmakuDiagnosticsIfNeeded()
    }

    private func refreshLiveDanmakuDiagnosticsRenderState(forcePublish: Bool = false) {
        applyCurrentRenderStateToDiagnosticsDraft()
        publishLiveDanmakuDiagnosticsIfNeeded(force: forcePublish)
    }

    private func applyCurrentRenderStateToDiagnosticsDraft() {
        liveDanmakuDiagnosticsDraft.apply(
            .renderState(
                isDanmakuEnabled: isDanmakuEnabled,
                overlayItemCount: liveDanmakuRenderStore.itemCount,
                hasPresentedPlayback: playerViewModel?.hasPresentedPlayback == true
            )
        )
    }

    private func publishLiveDanmakuDiagnosticsIfNeeded(force: Bool = false) {
        guard force || isLiveDanmakuDiagnosticsEnabled else { return }
        liveDanmakuRenderStore.updateDiagnostics(liveDanmakuDiagnosticsDraft)
    }

    private static func streamTitle(for candidate: LiveStreamURLCandidate, index: Int) -> String {
        var parts = ["线路 \(index + 1)"]
        if let currentQN = candidate.currentQN, currentQN > 0 {
            parts.append(liveQualityTitle(currentQN))
        }
        if let protocolName = candidate.protocolName?.uppercased(), !protocolName.isEmpty {
            parts.append(protocolName)
        } else if candidate.isLikelyHLS {
            parts.append("HLS")
        }
        if let formatName = candidate.formatName?.uppercased(), !formatName.isEmpty {
            parts.append(formatName)
        }
        if let codecName = candidate.codecName?.uppercased(), !codecName.isEmpty {
            parts.append(codecName)
        }
        return parts.joined(separator: " · ")
    }

    private static func liveQualityTitle(_ quality: Int) -> String {
        switch quality {
        case 10000:
            return "原画"
        case 400:
            return "蓝光"
        case 250:
            return "超清"
        case 150:
            return "高清"
        case 80:
            return "流畅"
        default:
            return "清晰度 \(quality)"
        }
    }

    private func loadRoomMetadata(roomID: Int, generation: Int) async {
        let api = self.api
        async let roomInfoTask: LiveRoomInfo? = optionalFetch { try await api.fetchLiveRoomInfo(roomID: roomID) }
        async let anchorInfoTask: LiveAnchorInfoData? = optionalFetch { try await api.fetchLiveAnchorInfo(roomID: roomID) }

        let loadedRoomInfo = await roomInfoTask
        let loadedAnchorInfo = await anchorInfoTask
        guard !Task.isCancelled, isCurrentLoad(generation) else { return }
        roomInfo = loadedRoomInfo
        anchorInfo = loadedAnchorInfo
    }

    private func optionalFetch<T>(_ operation: @escaping () async throws -> T) async -> T? {
        do {
            return try await operation()
        } catch {
            return nil
        }
    }

    private static func preferredCandidateIndex(
        in candidates: [LiveStreamURLCandidate],
        preferredQuality: Int?,
        preferredSource: LiveStreamURLCandidate?
    ) -> Int {
        guard !candidates.isEmpty else { return 0 }
        let qualityMatches = candidates.indices.filter { index in
            preferredQuality == nil || candidates[index].currentQN == preferredQuality
        }
        let searchIndices = qualityMatches.isEmpty ? Array(candidates.indices) : qualityMatches
        if let preferredSource,
           let matchingSource = searchIndices.first(where: { index in
               candidates[index].source == preferredSource.source
                   && candidates[index].protocolName == preferredSource.protocolName
                   && candidates[index].formatName == preferredSource.formatName
                   && candidates[index].codecName == preferredSource.codecName
           }) {
            return matchingSource
        }
        if let hlsIndex = searchIndices.first(where: { candidates[$0].isLikelyHLS }) {
            return hlsIndex
        }
        return searchIndices.first ?? 0
    }

}

struct LiveStreamMenuItem: Identifiable, Hashable {
    let id: Int
    let title: String
    let isSelected: Bool
}

struct LiveStreamQualityMenuItem: Identifiable, Hashable {
    var id: Int { qn }
    let qn: Int
    let title: String
    let isSelected: Bool
}

private struct LiveDetailFullscreenContainerGeometry {
    let size: CGSize
    let offset: CGSize
}

private extension GeometryProxy {
    var liveDetailFullscreenContainerGeometry: LiveDetailFullscreenContainerGeometry {
        if let window = UIApplication.shared.liveDetailForegroundKeyWindow,
           let rootView = window.rootViewController?.view {
            let localFrame = frame(in: .global)
            let frameInWindow = rootView.convert(localFrame, from: nil)
            return LiveDetailFullscreenContainerGeometry(
                size: window.bounds.size,
                offset: CGSize(width: -frameInWindow.minX, height: -frameInWindow.minY)
            )
        }

        let expandedSize = CGSize(
            width: size.width + safeAreaInsets.leading + safeAreaInsets.trailing,
            height: size.height + safeAreaInsets.top + safeAreaInsets.bottom
        )
        return LiveDetailFullscreenContainerGeometry(
            size: expandedSize,
            offset: CGSize(width: -safeAreaInsets.leading, height: -safeAreaInsets.top)
        )
    }
}

private extension UIApplication {
    var liveDetailForegroundKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}

private extension ManualVideoFullscreenMode {
    var liveDetailInterfaceOrientationMask: UIInterfaceOrientationMask {
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

private struct LiveDetailChromeHiddenPreferenceKey: PreferenceKey {
    static var defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

private struct LiveStatusBarStyleBridge: UIViewControllerRepresentable {
    let style: UIStatusBarStyle
    let isHidden: Bool

    func makeUIViewController(context _: Context) -> Controller {
        Controller(style: style, isHidden: isHidden)
    }

    func updateUIViewController(_ uiViewController: Controller, context _: Context) {
        uiViewController.style = style
        uiViewController.isHidden = isHidden
    }

    final class Controller: UIViewController {
        var style: UIStatusBarStyle {
            didSet {
                requestChromeUpdate()
            }
        }

        var isHidden: Bool {
            didSet {
                requestChromeUpdate()
            }
        }

        init(style: UIStatusBarStyle, isHidden: Bool) {
            self.style = style
            self.isHidden = isHidden
            super.init(nibName: nil, bundle: nil)
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var preferredStatusBarStyle: UIStatusBarStyle {
            style
        }

        override var prefersStatusBarHidden: Bool {
            isHidden
        }

        override var prefersHomeIndicatorAutoHidden: Bool {
            isHidden
        }

        override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
            isHidden ? .all : []
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            requestChromeUpdate()
        }

        private func requestChromeUpdate() {
            var controllers = [UIViewController]()
            var current: UIViewController? = self
            while let controller = current {
                controllers.append(controller)
                current = controller.parent
            }
            if let navigationController {
                controllers.append(navigationController)
            }
            if let tabBarController {
                controllers.append(tabBarController)
            }
            if let root = view.window?.rootViewController {
                controllers.append(root)
            }

            controllers.forEach { controller in
                controller.setNeedsStatusBarAppearanceUpdate()
                controller.setNeedsUpdateOfHomeIndicatorAutoHidden()
            }
        }
    }
}

private struct LiveDanmakuDiagnosticsHUD: View {
    let snapshot: LiveDanmakuDiagnosticSnapshot
    let isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: snapshot.phase.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(snapshot.phase.tintColor)
                    .frame(width: 18, height: 18)

                Text("弹幕诊断")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)

                Spacer(minLength: 8)

                Text(snapshot.phase.title)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(snapshot.phase.tintColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(snapshot.phase.tintColor.opacity(0.18), in: Capsule())
            }

            Text(snapshot.conclusion)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(isExpanded ? 2 : 3)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 5) {
                ForEach(rows, id: \.title) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(row.title)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.58))
                            .frame(width: 44, alignment: .leading)

                        Text(row.value)
                            .font(.caption2.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.86))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        Spacer(minLength: 0)
                    }
                }
            }

            if isExpanded, let lastCommandName = snapshot.lastCommandName {
                Text("最后命令 \(lastCommandName)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(10)
        .frame(width: isExpanded ? 360 : 292, alignment: .leading)
        .background(.black.opacity(0.36), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
    }

    private var rows: [(title: String, value: String)] {
        var values: [(title: String, value: String)] = [
            ("配置", snapshot.configSummary),
            ("连接", snapshot.connectionSummary),
            ("收包", snapshot.receiveSummary),
            ("弹幕", snapshot.commandSummary)
        ]
        if isExpanded {
            values.append(("覆盖层", snapshot.renderSummary))
            values.append(("心跳", "\(snapshot.heartbeatReplyCount)/\(snapshot.heartbeatSentCount)"))
            values.append(("解析", "\(snapshot.inflateSuccessCount) 成功 · \(snapshot.inflateFailureCount) 失败"))
            values.append(("重连", "\(snapshot.reconnectCount) 次"))
        }
        return values
    }
}

private extension LiveDanmakuDiagnosticPhase {
    var tintColor: Color {
        switch self {
        case .rendering:
            return .green
        case .receiving, .waitingForPackets:
            return .cyan
        case .fetchingConfig, .connecting, .authenticating, .reconnecting:
            return .yellow
        case .failed:
            return .red
        case .idle, .stopped:
            return .white.opacity(0.72)
        }
    }
}

private struct LiveInlineMetadataButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        } icon: {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
        }
        .frame(height: 28)
        .padding(.horizontal, 8)
        .foregroundStyle(.primary)
    }
}

private struct LiveRoomDescriptionSheet: View {
    @ObservedObject var viewModel: LiveRoomViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(viewModel.title)
                        .font(.title3.weight(.bold))
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    LiveRoomDescriptionAnchorRow(viewModel: viewModel)

                    VStack(alignment: .leading, spacing: 10) {
                        if let areaText = viewModel.areaText {
                            Label(areaText, systemImage: "tag")
                        }
                        Label(viewModel.onlineText, systemImage: "person.2")
                        if let liveTimeText = viewModel.liveTimeText {
                            Label(liveTimeText, systemImage: "clock")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    Text(displayDescription)
                        .font(.body)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
            }
            .navigationTitle("直播简介")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var displayDescription: String {
        viewModel.descriptionText ?? "这个直播间暂时没有简介。"
    }
}

private struct LiveRoomDescriptionAnchorRow: View {
    @ObservedObject var viewModel: LiveRoomViewModel

    var body: some View {
        HStack(spacing: 10) {
            AvatarRemoteImage(urlString: viewModel.anchorFace, pixelSize: 96) {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(viewModel.anchorName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if viewModel.isFollowingAnchor {
                        Text("已关注")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.pink)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.pink.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                Text(viewModel.isLive ? "直播中" : "未开播")
                    .font(.caption)
                    .foregroundStyle(viewModel.isLive ? .pink : .secondary)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("主播 \(viewModel.anchorName)")
    }
}

private struct LiveRoomInfoCard: View {
    @ObservedObject var viewModel: LiveRoomViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                AvatarRemoteImage(urlString: viewModel.anchorFace, pixelSize: 96) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 42, height: 42)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(viewModel.anchorName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if viewModel.isFollowingAnchor {
                            Text("已关注")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.pink)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.pink.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: 8) {
                        Label(viewModel.isLive ? "直播中" : "未开播", systemImage: viewModel.isLive ? "dot.radiowaves.left.and.right" : "pause.circle")
                            .foregroundStyle(viewModel.isLive ? .pink : .secondary)

                        Text(viewModel.onlineText)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            Text(viewModel.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(3)

            HStack(spacing: 8) {
                if let areaText = viewModel.areaText {
                    Label(areaText, systemImage: "tag")
                }
                if let liveTimeText = viewModel.liveTimeText {
                    Label(liveTimeText, systemImage: "clock")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let descriptionText = viewModel.descriptionText {
                Text(descriptionText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(
            .regular.tint(Color.videoDetailGlassTint).interactive(false),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.8)
        }
    }
}

private extension Color {
    static let videoDetailBackground = Color(UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.075, green: 0.075, blue: 0.085, alpha: 1)
            : .systemGroupedBackground
    })

    static let videoDetailGlassTint = Color(UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.055)
            : UIColor(white: 1, alpha: 0.74)
    })
}

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
