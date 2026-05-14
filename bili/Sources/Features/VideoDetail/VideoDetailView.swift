import AVFoundation
import SwiftUI
import Combine
import UIKit

struct VideoDetailView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    let seedVideo: VideoItem
    private let hidesRootTabBar: Bool

    @StateObject private var holder = VideoDetailViewModelHolder()
    @State private var isShowingDescription = false
    @State private var isShowingCommentsSheet = false
    @State private var replySheetComment: Comment?
    @State private var introScrollOffset: CGFloat = 0
    @State private var manualFullscreenMode: ManualVideoFullscreenMode?
    @State private var isRestoringPortraitFromManualLandscape = false
    @State private var pendingManualLandscapeEnterTask: Task<Void, Never>?
    @State private var pendingManualLandscapeExitTask: Task<Void, Never>?
    @State private var lastManualLandscapeRequestTime: Date?
    @State private var hidesPlayerSystemChrome = false
    @State private var preloadedRelatedVideos = Set<String>()
    @State private var isShowingDanmakuSettings = false
    @State private var isShowingNetworkDiagnostics = false

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
                ProgressView()
                    .task {
                        holder.configure(
                            seedVideo: seedVideo,
                            api: dependencies.api,
                            libraryStore: libraryStore,
                            sponsorBlockService: dependencies.sponsorBlockService
                        )
                    }
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .background(
            VideoDetailLifecycleBridge(
                onWillDisappear: {
                    holder.viewModel?.suspendPlaybackForNavigation()
                }
            )
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                uploaderToolbarButton
            }
        }
        .hideRootTabBarWhenNeeded(hidesRootTabBar)
        .toolbar(hidesPlayerSystemChrome ? .hidden : .visible, for: .navigationBar)
        .onPreferenceChange(VideoDetailChromeHiddenPreferenceKey.self) { isHidden in
            hidesPlayerSystemChrome = isHidden
        }
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            updateManualLandscapeOrientation(UIDevice.current.orientation)
        }
        .onDisappear {
            pendingManualLandscapeEnterTask?.cancel()
            pendingManualLandscapeExitTask?.cancel()
            holder.viewModel?.stopPlaybackForNavigation()
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            AppOrientationLock.restorePortrait()
            hidesPlayerSystemChrome = false
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            updateManualLandscapeOrientation(UIDevice.current.orientation)
        }
        .onReceive(NotificationCenter.default.publisher(for: .biliStopActiveVideoPlayback)) { _ in
            holder.viewModel?.stopPlaybackForNavigation()
        }
    }

    private var navigationTitle: String {
        holder.viewModel?.detail.title ?? seedVideo.title
    }

    @ViewBuilder
    private var uploaderToolbarButton: some View {
        let owner = holder.viewModel?.detail.owner ?? seedVideo.owner
        if let owner, owner.mid > 0 {
            NavigationLink(value: owner) {
                ToolbarAvatar(urlString: owner.face)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开 \(owner.name) 的主页")
        }
    }

    @ViewBuilder
    private func content(_ viewModel: VideoDetailViewModel) -> some View {
        GeometryReader { proxy in
            let fullscreenGeometry = proxy.fullscreenContainerGeometry
            let fullscreenSize = fullscreenGeometry.size
            let fullscreenOffset = fullscreenGeometry.offset
            let sceneIsLandscape = fullscreenSize.width > fullscreenSize.height
            let isManualFullscreen = manualFullscreenMode != nil || isRestoringPortraitFromManualLandscape
            let isLandscape = sceneIsLandscape && !isManualFullscreen
            let shouldHideSystemChrome = isLandscape || isManualFullscreen
            let isManualLandscapeFullscreen = manualFullscreenMode?.isLandscape == true
            let layoutSize = isManualFullscreen
                ? (isManualLandscapeFullscreen
                    ? CGSize(width: max(proxy.size.width, proxy.size.height), height: min(proxy.size.width, proxy.size.height))
                    : CGSize(width: min(proxy.size.width, proxy.size.height), height: max(proxy.size.width, proxy.size.height)))
                : proxy.size

            standardPlaybackPage(
                viewModel,
                screenSize: isLandscape ? fullscreenSize : layoutSize,
                isLandscape: isLandscape
            )
            .frame(
                width: isLandscape ? fullscreenSize.width : proxy.size.width,
                height: isLandscape ? fullscreenSize.height : proxy.size.height
            )
            .offset(isLandscape ? fullscreenOffset : .zero)
            .background(isLandscape ? Color.black : Color.videoDetailBackground)
            .ignoresSafeArea(.container, edges: (isLandscape || manualFullscreenMode != nil) ? .all : [])
            .preference(key: VideoDetailChromeHiddenPreferenceKey.self, value: shouldHideSystemChrome)
            .statusBar(hidden: shouldHideSystemChrome)
            .persistentSystemOverlays(shouldHideSystemChrome ? .hidden : .automatic)
            .background {
                StatusBarStyleBridge(
                    style: (isLandscape || isManualFullscreen) ? .lightContent : .default,
                    isHidden: shouldHideSystemChrome
                )
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            }
            .overlay {
                if case .failed(let message) = viewModel.state {
                    ErrorStateView(title: "视频加载失败", message: message) {
                        Task { await viewModel.load() }
                    }
                    .background(.background.opacity(0.95))
                }
            }
            .overlay(alignment: .topLeading) {
                if libraryStore.playerPerformanceOverlayEnabled {
                    PlayerPerformanceOverlay(metricsID: viewModel.detail.bvid)
                        .padding(.top, isLandscape || isManualFullscreen ? 14 : 10)
                        .padding(.leading, 10)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
                }
            }
            .task {
                await viewModel.load()
            }
            .sheet(isPresented: $isShowingDescription) {
                VideoDescriptionSheet(
                    viewModel: viewModel
                )
            }
            .sheet(isPresented: $isShowingCommentsSheet) {
                commentsSheet(viewModel)
            }
            .sheet(item: $replySheetComment) { comment in
                CommentRepliesSheet(rootComment: comment, viewModel: viewModel)
            }
            .sheet(isPresented: $isShowingDanmakuSettings) {
                DanmakuSettingsSheet(viewModel: viewModel)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $isShowingNetworkDiagnostics) {
                PlaybackNetworkDiagnosticsSheet(
                    viewModel: viewModel,
                    libraryStore: libraryStore
                )
                .presentationDetents([.medium, .large])
            }
        }
        .ignoresSafeArea(.container, edges: manualFullscreenMode != nil ? .all : [])
    }

    private func updateManualLandscapeOrientation(_ orientation: UIDeviceOrientation) {
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
        case .portrait, .portraitUpsideDown:
            pendingManualLandscapeEnterTask?.cancel()
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
            detailContent: {
                detailScrollPage(viewModel)
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
            onShowDanmakuSettings: {
                isShowingDanmakuSettings = true
            },
            onShowNetworkDiagnostics: {
                isShowingNetworkDiagnostics = true
            }
        )
    }

    private func exitManualLandscapePlayback() {
        guard manualFullscreenMode != nil else { return }
        pendingManualLandscapeExitTask?.cancel()
        beginRestoringPortraitFromManualLandscape()
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

        let deviceOrientation = UIDevice.current.orientation
        let targetMode: ManualVideoFullscreenMode
        if shouldUsePortraitFullscreen {
            targetMode = .portrait
        } else {
            targetMode = .landscape(deviceOrientation == .landscapeRight ? .landscapeRight : .landscapeLeft)
        }
        manualFullscreenMode = targetMode
        requestManualFullscreenSurfaceEntry(
            mode: targetMode,
            playerViewModel: playerViewModel
        )
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
    ) {
        guard let playerViewModel else { return }
        let didEnter = playerViewModel.enterManualFullscreen(
            mode: mode,
            onExit: { exitManualLandscapePlayback() },
            animated: true
        )
        guard !didEnter else { return }

        pendingManualLandscapeEnterTask?.cancel()
        pendingManualLandscapeEnterTask = Task { @MainActor in
            await Task.yield()
            guard manualFullscreenMode == mode else { return }
            _ = playerViewModel.enterManualFullscreen(
                mode: mode,
                onExit: { exitManualLandscapePlayback() },
                animated: true
            )
            pendingManualLandscapeEnterTask = nil
        }
    }

    private var shouldUsePortraitFullscreen: Bool {
        guard let viewModel = holder.viewModel else { return false }
        return videoAspectRatio(for: viewModel).map { $0 < 0.9 } == true
    }

    private func videoAspectRatio(for viewModel: VideoDetailViewModel) -> Double? {
        viewModel.selectedPlayVariant?.videoAspectRatio
            ?? viewModel.detail.dimension?.aspectRatio
            ?? selectedPage(in: viewModel)?.dimension?.aspectRatio
            ?? viewModel.playVariants.compactMap(\.videoAspectRatio).first
    }

    private func selectedPage(in viewModel: VideoDetailViewModel) -> VideoPage? {
        guard let selectedCID = viewModel.selectedCID else { return nil }
        return viewModel.detail.pages?.first { $0.cid == selectedCID }
    }

    private func beginRestoringPortraitFromManualLandscape() {
        guard manualFullscreenMode != nil else { return }
        pendingManualLandscapeEnterTask?.cancel()
        pendingManualLandscapeExitTask?.cancel()
        isRestoringPortraitFromManualLandscape = true
        AppOrientationLock.restorePortrait()
        manualFullscreenMode = nil
        lastManualLandscapeRequestTime = nil

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            isRestoringPortraitFromManualLandscape = false
        }
    }

    private func shouldApplyManualLandscapeOrientation(_ orientation: UIDeviceOrientation) -> Bool {
        guard orientation.isLandscape else { return false }
        let now = Date()
        defer { lastManualLandscapeRequestTime = now }
        guard let lastManualLandscapeRequestTime else { return true }
        return now.timeIntervalSince(lastManualLandscapeRequestTime) > 0.34
    }

    private func commentsSheet(_ viewModel: VideoDetailViewModel) -> some View {
        PortraitCommentsSheet(viewModel: viewModel)
    }

    private func detailCard(_ viewModel: VideoDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            metadataBlock(viewModel)
            actionStrip(viewModel)
            interactionNotice(viewModel)
            playURLNotice(viewModel)
        }
        .padding(14)
        .background(Color.videoDetailSurface)
    }

    private func metadataBlock(_ viewModel: VideoDetailViewModel) -> some View {
        let video = viewModel.detail

        return HStack(spacing: 9) {
            Label(BiliFormatters.compactCount(video.stat?.view), systemImage: "play.rectangle")
                .frame(height: 28)
            Label(BiliFormatters.publishDate(video.pubdate), systemImage: "calendar")
                .frame(height: 28)

            Spacer(minLength: 2)

            descriptionInlineButton()
            networkDiagnosticsInlineButton()
            qualityInlineButton(viewModel)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionStrip(_ viewModel: VideoDetailViewModel) -> some View {
        let video = viewModel.detail
        let interaction = viewModel.interactionState

        return HStack(spacing: 0) {
            Button {
                Haptics.light()
                Task {
                    await viewModel.toggleLike()
                    Haptics.success()
                }
            } label: {
                detailActionContent(
                    title: BiliFormatters.compactCount(video.stat?.like),
                    systemImage: interaction.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
                    foregroundStyle: interaction.isLiked ? .pink : .secondary
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isMutatingInteraction)

            Button {
                Haptics.medium()
                Task {
                    await viewModel.addCoin()
                    Haptics.success()
                }
            } label: {
                detailActionContent(
                    title: BiliFormatters.compactCount(video.stat?.coin),
                    systemImage: interaction.isCoined ? "bitcoinsign.circle.fill" : "bitcoinsign.circle",
                    foregroundStyle: interaction.isCoined ? .pink : .secondary
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isMutatingInteraction || interaction.coinCount >= 2)

            Button {
                Haptics.light()
                Task {
                    await viewModel.toggleFavorite()
                    Haptics.success()
                }
            } label: {
                detailActionContent(
                    title: interaction.isFavorited ? "已收藏" : BiliFormatters.compactCount(video.stat?.favorite),
                    systemImage: interaction.isFavorited ? "star.fill" : "star",
                    foregroundStyle: interaction.isFavorited ? .pink : .secondary
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isMutatingInteraction)

            detailAction(title: "分享", systemImage: "arrowshape.turn.up.right")
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func interactionNotice(_ viewModel: VideoDetailViewModel) -> some View {
        if let message = viewModel.playbackFallbackMessage, !message.isEmpty {
            Label(message, systemImage: "sparkles.tv")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if let message = viewModel.interactionMessage, !message.isEmpty {
            Label(message, systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detailAction(title: String, systemImage: String) -> some View {
        detailActionContent(title: title, systemImage: systemImage, foregroundStyle: .secondary)
    }

    private func detailActionContent(title: String, systemImage: String, foregroundStyle: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.title3)
            Text(title)
                .font(.caption2)
        }
        .foregroundStyle(foregroundStyle)
        .frame(maxWidth: .infinity)
    }

    private func descriptionInlineButton() -> some View {
        Button {
            isShowingDescription = true
        } label: {
            InlineMetadataButtonLabel(title: "简介", systemImage: "text.alignleft")
        }
        .buttonStyle(.plain)
    }

    private func networkDiagnosticsInlineButton() -> some View {
        Button {
            isShowingNetworkDiagnostics = true
        } label: {
            InlineMetadataButtonLabel(title: "诊断", systemImage: "network")
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func qualityInlineButton(_ viewModel: VideoDetailViewModel) -> some View {
        if !viewModel.playVariants.isEmpty {
            Menu {
                if viewModel.isSupplementingPlayQualities {
                    Button {} label: {
                        Label("正在补全高清档位", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(true)
                }
                if viewModel.isSwitchingPlayQuality {
                    Button {} label: {
                        Label("正在切换清晰度", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(true)
                }

                ForEach(viewModel.playVariants) { variant in
                    Button {
                        viewModel.selectPlayVariant(variant)
                    } label: {
                        Label(
                            qualityMenuTitle(for: variant),
                            systemImage: qualityMenuIcon(for: variant, viewModel: viewModel)
                        )
                    }
                    .disabled(!variant.isPlayable || viewModel.isSwitchingPlayQuality)
                }
            } label: {
                InlineMetadataButtonLabel(
                    title: qualityButtonTitle(viewModel),
                    systemImage: viewModel.isSupplementingPlayQualities || viewModel.isSwitchingPlayQuality ? "arrow.triangle.2.circlepath" : "slider.horizontal.3"
                )
            }
            .buttonStyle(.plain)
        } else {
            InlineMetadataButtonLabel(title: "清晰度", systemImage: "slider.horizontal.3")
                .opacity(0.45)
        }
    }

    private func qualityButtonTitle(_ viewModel: VideoDetailViewModel) -> String {
        if viewModel.isSwitchingPlayQuality {
            return "切换中"
        }
        if viewModel.isSupplementingPlayQualities {
            return "补高清中"
        }
        return viewModel.selectedPlayVariant?.title ?? "清晰度"
    }

    private func qualityMenuIcon(for variant: PlayVariant, viewModel: VideoDetailViewModel) -> String {
        if viewModel.pendingPlayVariantID == variant.id {
            return "arrow.triangle.2.circlepath"
        }
        if viewModel.selectedPlayVariant == variant {
            return "checkmark"
        }
        return variant.isPlayable ? "circle" : "lock.fill"
    }

    private func qualityMenuTitle(for variant: PlayVariant) -> String {
        let subtitle = variant.subtitle
        guard !subtitle.isEmpty else { return variant.title }
        return "\(variant.title)  \(subtitle)"
    }

    @ViewBuilder
    private func playURLNotice(_ viewModel: VideoDetailViewModel) -> some View {
        if viewModel.selectedPlayVariant == nil {
            if case .failed = viewModel.playURLState {
                playURLStatus(viewModel)
            } else if viewModel.playURLState == .idle {
                playURLStatus(viewModel)
            }
        } else if viewModel.selectedPlayVariant?.isPlayable == false {
            Label("当前档位暂不可播放", systemImage: "lock.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func episodeSection(_ viewModel: VideoDetailViewModel) -> some View {
        if let pages = viewModel.detail.pages, pages.count > 1 {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("选集")
                        .font(.headline)
                    Spacer()
                    Text("\(pages.count)P")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)

                pageSelector(pages: pages, selectedCID: viewModel.selectedCID, viewModel: viewModel)
            }
            .padding(.vertical, 14)
            .background(Color.videoDetailSurface)
        }
    }

    private func detailScrollPage(_ viewModel: VideoDetailViewModel) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                scrollOffsetReader()
                detailCard(viewModel)
                episodeSection(viewModel)
                if viewModel.shouldShowRelatedSectionShell {
                    relatedSection(viewModel)
                }
                deferredCommentsEntry(viewModel)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 20)
            .contentTransition(.opacity)
        }
        .coordinateSpace(name: detailScrollSpaceName)
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
            updatePortraitScrollOffset(offset)
        }
        .background(Color.videoDetailBackground)
    }

    private func portraitScrollOffset() -> CGFloat {
        introScrollOffset
    }

    private func updatePortraitScrollOffset(_ offset: CGFloat) {
        guard abs(introScrollOffset - offset) > 0.5 else { return }
        introScrollOffset = offset
    }

    private var detailScrollSpaceName: String {
        "VideoDetailScrollSpace"
    }

    private func scrollOffsetReader() -> some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: ScrollOffsetPreferenceKey.self,
                    value: -proxy.frame(in: .named(detailScrollSpaceName)).minY
                )
        }
        .frame(height: 0)
    }

    @ViewBuilder
    private func playURLStatus(_ viewModel: VideoDetailViewModel) -> some View {
        switch viewModel.playURLState {
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    Task {
                        await viewModel.retryPlayURL()
                    }
                } label: {
                    Label("播放地址加载失败，点击重试", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .loading, .loaded:
            EmptyView()
        default:
            Button {
                Task {
                    await viewModel.retryPlayURL()
                }
            } label: {
                Label("加载播放地址", systemImage: "play.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func cover(_ video: VideoItem) -> some View {
        CachedRemoteImage(
            url: video.pic.flatMap { URL(string: $0.biliCoverThumbnailURL(width: 960, height: 540)) },
            targetPixelSize: 960
        ) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Color.gray.opacity(0.14)
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private func playerIdentity(_ viewModel: VideoDetailViewModel, variant: PlayVariant) -> String {
        "\(viewModel.selectedCID ?? 0)-\(variant.id)"
    }

    private func pageSelector(pages: [VideoPage], selectedCID: Int?, viewModel: VideoDetailViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pages) { page in
                    Button {
                        viewModel.selectPage(page)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("P\(page.page ?? 1)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(page.cid == selectedCID ? .pink : .secondary)
                            Text(page.part ?? "第 \(page.page ?? 1) 集")
                                .font(.caption.weight(.semibold))
                                .lineLimit(2)
                        }
                        .frame(width: 128, height: 54, alignment: .leading)
                        .padding(.horizontal, 10)
                        .background(page.cid == selectedCID ? Color.pink.opacity(0.1) : Color.videoDetailSecondarySurface)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(page.cid == selectedCID ? Color.pink.opacity(0.5) : Color.clear, lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private func commentsSection(
        _ viewModel: VideoDetailViewModel,
        style: CommentSectionStyle = .grouped,
        maxVisibleComments: Int? = nil,
        autoLoads: Bool = true
    ) -> some View {
        CommentsSectionView(
            viewModel: viewModel,
            style: style,
            maxVisibleComments: maxVisibleComments,
            autoLoads: autoLoads,
                showAllComments: {
                    isShowingCommentsSheet = true
                }
            ) { comment in
                replySheetComment = comment
            }
    }

    private func relatedSection(_ viewModel: VideoDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !viewModel.related.isEmpty {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(viewModel.related.prefix(5)) { video in
                            VideoRouteLink(video) {
                                RelatedVideoCard(video: video)
                            }
                            .onAppear {
                                beginRelatedPreloadIfNeeded(video)
                            }
                        }
                    }
                }
                .contentMargins(.horizontal, 14, for: .scrollContent)
                .scrollIndicators(.hidden)
                .overlay(alignment: .topTrailing) {
                    if viewModel.relatedState.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 14)
                    }
                }
                .transition(.opacity)
            } else if viewModel.relatedState == .idle || viewModel.relatedState.isLoading {
                relatedPlaceholderContent(viewModel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .background(Color.videoDetailSurface)
        .animation(.easeOut(duration: 0.18), value: viewModel.related.isEmpty)
        .animation(.easeOut(duration: 0.18), value: viewModel.relatedState)
    }

    private func beginRelatedPreloadIfNeeded(_ video: VideoItem) {
        guard !video.bvid.isEmpty,
              !preloadedRelatedVideos.contains(video.bvid),
              preloadedRelatedVideos.count < 3,
              !PlaybackEnvironment.current.shouldPreferConservativePlayback
        else { return }
        preloadedRelatedVideos.insert(video.bvid)
        let api = dependencies.api
        let preferredQuality = libraryStore.preferredVideoQuality
        let cdnPreference = libraryStore.effectivePlaybackCDNPreference
        Task(priority: .utility) {
            await VideoPreloadCenter.shared.preloadPlayInfo(
                video,
                api: api,
                preferredQuality: preferredQuality,
                cdnPreference: cdnPreference,
                priority: .utility
            )
        }
    }

    @ViewBuilder
    private func relatedPlaceholderContent(_ viewModel: VideoDetailViewModel) -> some View {
        if case .failed(let message) = viewModel.relatedState {
            RelatedVideoRetryState(
                message: viewModel.lastRelatedLoadTimedOut ? "相关推荐加载超时，可以稍后重试。" : message
            ) {
                Task {
                    await viewModel.retryRelated()
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 146)
        } else {
            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in
                    RelatedVideoPlaceholderCard(isLoading: viewModel.relatedState.isLoading)
                }
            }
            .padding(.horizontal, 14)
            .allowsHitTesting(false)
        }
    }

    private func deferredCommentsEntry(_ viewModel: VideoDetailViewModel) -> some View {
        Button {
            isShowingCommentsSheet = true
        } label: {
            HStack(spacing: 10) {
                Label("评论", systemImage: "bubble.left.and.bubble.right")
                    .font(.headline)

                Text(BiliFormatters.compactCount(viewModel.detail.stat?.reply))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.videoDetailSurface)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看 \(BiliFormatters.compactCount(viewModel.detail.stat?.reply)) 条评论")
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

private extension UIApplication {
    var videoDetailKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}

private extension ManualVideoFullscreenMode {
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
    let onShowDanmakuSettings: () -> Void
    let onShowNetworkDiagnostics: () -> Void
}

private struct VideoDetailStandardPlaybackPage<DetailContent: View>: View {
    let config: VideoDetailStandardPlaybackPageConfig
    @ObservedObject var viewModel: VideoDetailViewModel
    let detailContent: () -> DetailContent

    var body: some View {
        ZStack(alignment: .top) {
            Color.videoDetailBackground
                .opacity(config.expandsToFullscreen ? 0 : 1)
                .ignoresSafeArea()

            if !config.isLandscape {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: config.standardHeight)

                    detailContent()
                        .opacity(config.isManualFullscreen ? 0 : 1)
                        .allowsHitTesting(!config.isManualFullscreen)
                }
            }

            if config.expandsToFullscreen {
                Color.black
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            VideoDetailPlayerHero(
                viewModel: viewModel,
                isLandscape: config.isLandscape,
                playerWidth: config.playerWidth,
                playerHeight: config.playerHeight,
                manualFullscreenMode: config.manualFullscreenMode,
                onRequestManualFullscreen: config.onRequestManualFullscreen,
                onExitManualFullscreen: config.onExitManualFullscreen,
                onShowDanmakuSettings: config.onShowDanmakuSettings,
                onShowNetworkDiagnostics: config.onShowNetworkDiagnostics
            )
        }
        .frame(width: config.screenSize.width, height: config.screenSize.height)
    }
}

private struct VideoDetailPlayerHero: View {
    @ObservedObject var viewModel: VideoDetailViewModel
    let isLandscape: Bool
    let playerWidth: CGFloat?
    let playerHeight: CGFloat
    let manualFullscreenMode: ManualVideoFullscreenMode?
    let onRequestManualFullscreen: (PlayerStateViewModel) -> Void
    let onExitManualFullscreen: (() -> Void)?
    let onShowDanmakuSettings: () -> Void
    let onShowNetworkDiagnostics: () -> Void

    var body: some View {
        Group {
            if let playerViewModel = viewModel.stablePlayerViewModel {
                VideoDetailPlayerSurface(
                    viewModel: viewModel,
                    playerViewModel: playerViewModel,
                    isLandscape: isLandscape,
                    playerWidth: playerWidth,
                    playerHeight: playerHeight,
                    manualFullscreenMode: manualFullscreenMode,
                    onRequestManualFullscreen: onRequestManualFullscreen,
                    onExitManualFullscreen: onExitManualFullscreen,
                    onShowDanmakuSettings: onShowDanmakuSettings,
                    onShowNetworkDiagnostics: onShowNetworkDiagnostics
                )
            } else {
                VideoDetailPlayerPlaceholder(
                    viewModel: viewModel,
                    playerWidth: playerWidth,
                    playerHeight: playerHeight
                )
            }
        }
        .frame(width: playerWidth)
        .frame(maxWidth: .infinity)
        .frame(height: playerHeight)
        .zIndex(1)
        .clipped()
    }
}

private struct VideoDetailPlayerSurface: View {
    @ObservedObject var viewModel: VideoDetailViewModel
    @ObservedObject var playerViewModel: PlayerStateViewModel
    let isLandscape: Bool
    let playerWidth: CGFloat?
    let playerHeight: CGFloat
    let manualFullscreenMode: ManualVideoFullscreenMode?
    let onRequestManualFullscreen: (PlayerStateViewModel) -> Void
    let onExitManualFullscreen: (() -> Void)?
    let onShowDanmakuSettings: () -> Void
    let onShowNetworkDiagnostics: () -> Void
    private var usesLandscapePlaybackChrome: Bool {
        isLandscape || manualFullscreenMode?.isLandscape == true
    }

    var body: some View {
        BiliPlayerView(
            viewModel: playerViewModel,
            historyVideo: viewModel.detail,
            historyCID: viewModel.selectedCID,
            duration: viewModel.detail.duration.map(TimeInterval.init),
            presentation: usesLandscapePlaybackChrome ? .fullScreen : .embedded,
            showsNavigationChrome: false,
            showsStartupLoadingIndicator: false,
            pausesOnDisappear: false,
            surfaceOverlay: AnyView(danmakuOverlay),
            controlsAccessory: usesLandscapePlaybackChrome ? AnyView(danmakuControl) : nil,
            isDanmakuEnabled: viewModel.isDanmakuEnabled,
            onToggleDanmaku: {
                viewModel.toggleDanmaku()
            },
            onShowDanmakuSettings: onShowDanmakuSettings,
            embeddedAspectRatio: 16 / 9,
            keepsPlayerSurfaceStable: true,
            prefersNativePlaybackControls: false,
            manualFullscreenMode: manualFullscreenMode,
            onRequestManualFullscreen: {
                onRequestManualFullscreen(playerViewModel)
            },
            onExitManualFullscreen: onExitManualFullscreen
        )
        .id(ObjectIdentifier(playerViewModel))
        .frame(width: playerWidth)
        .frame(height: playerHeight)
        .overlay {
            PlaybackPosterOverlay(
                video: viewModel.detail,
                playerViewModel: playerViewModel,
                dimOpacity: 0.36,
                showsLoader: true
            )
        }
        .background(Color.black)
    }

    private var danmakuOverlay: some View {
        DanmakuOverlayView(
            items: viewModel.danmakuItems,
            currentTime: playerViewModel.currentTime,
            isPlaying: playerViewModel.isPlaying,
            playbackRate: playerViewModel.playbackRate.rawValue,
            isEnabled: viewModel.isDanmakuEnabled,
            hasPresentedPlayback: playerViewModel.hasPresentedPlayback,
            settings: viewModel.danmakuSettings,
            topInset: usesLandscapePlaybackChrome ? 28 : 8,
            bottomInset: usesLandscapePlaybackChrome ? 84 : 54
        )
        .padding(.horizontal, usesLandscapePlaybackChrome ? 18 : 4)
    }

    private var danmakuControl: some View {
        HStack {
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
                .glassEffect(
                    .regular
                        .tint(.black.opacity(viewModel.isDanmakuEnabled ? 0.18 : 0.10))
                        .interactive(true),
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(0.18), lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(viewModel.isDanmakuEnabled ? .white : .white.opacity(0.62))
            .accessibilityLabel(viewModel.isDanmakuEnabled ? "关闭弹幕" : "开启弹幕")

            Button {
                onShowNetworkDiagnostics()
            } label: {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.caption.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .glassEffect(
                        .regular
                            .tint(.black.opacity(0.12))
                            .interactive(true),
                        in: Circle()
                    )
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.18), lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .accessibilityLabel("播放网络诊断")

            Button {
                onShowDanmakuSettings()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .glassEffect(
                        .regular
                            .tint(.black.opacity(0.12))
                            .interactive(true),
                        in: Circle()
                    )
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.18), lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .accessibilityLabel("弹幕设置")
        }
    }
}

private struct VideoDetailPlayerPlaceholder: View {
    @ObservedObject var viewModel: VideoDetailViewModel
    let playerWidth: CGFloat?
    let playerHeight: CGFloat

    var body: some View {
        ZStack {
            PlayerLoadingPlaceholder(
                progress: loadingProgress,
                message: loadingMessage,
                isFinishing: false
            )
            .frame(width: playerWidth)
            .frame(height: playerHeight)

            if !viewModel.playURLState.isLoading, viewModel.selectedPlayVariant != nil {
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
        if viewModel.playURLState.isLoading {
            return 0.18
        }
        if viewModel.state.isLoading {
            return 0.08
        }
        if viewModel.relatedState.isLoading {
            return 0.05
        }
        return 0
    }

    private var loadingMessage: String {
        if viewModel.playURLState.isLoading {
            return "正在获取播放地址"
        }
        if viewModel.state.isLoading {
            return "正在获取视频详情"
        }
        if viewModel.relatedState.isLoading {
            return "正在加载相关推荐"
        }
        return "准备播放"
    }
}

private struct DanmakuSettingsSheet: View {
    @ObservedObject var viewModel: VideoDetailViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(
                        "启用弹幕",
                        isOn: Binding(
                            get: { viewModel.isDanmakuEnabled },
                            set: { isEnabled in
                                if viewModel.isDanmakuEnabled != isEnabled {
                                    viewModel.toggleDanmaku()
                                }
                            }
                        )
                    )
                }

                Section("显示区域") {
                    Picker("显示位置", selection: displayAreaBinding) {
                        ForEach(DanmakuDisplayArea.allCases) { area in
                            Text(area.title).tag(area)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("文字") {
                    settingSlider(
                        title: "字体大小",
                        value: fontScaleBinding,
                        range: 0.7...1.45,
                        step: 0.05,
                        valueText: "\(Int((viewModel.danmakuSettings.fontScale * 100).rounded()))%"
                    )

                    Picker("字体粗细", selection: fontWeightBinding) {
                        ForEach(DanmakuFontWeightOption.allCases) { weight in
                            Text(weight.title).tag(weight)
                        }
                    }
                }

                Section("透明度") {
                    settingSlider(
                        title: "不透明度",
                        value: opacityBinding,
                        range: 0.25...1.0,
                        step: 0.05,
                        valueText: "\(Int((viewModel.danmakuSettings.opacity * 100).rounded()))%"
                    )
                }
            }
            .navigationTitle("弹幕设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var fontScaleBinding: Binding<Double> {
        Binding(
            get: { viewModel.danmakuSettings.fontScale },
            set: { newValue in
                var settings = viewModel.danmakuSettings
                settings.fontScale = newValue
                viewModel.updateDanmakuSettings(settings)
            }
        )
    }

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { viewModel.danmakuSettings.opacity },
            set: { newValue in
                var settings = viewModel.danmakuSettings
                settings.opacity = newValue
                viewModel.updateDanmakuSettings(settings)
            }
        )
    }

    private var displayAreaBinding: Binding<DanmakuDisplayArea> {
        Binding(
            get: { viewModel.danmakuSettings.displayArea },
            set: { newValue in
                var settings = viewModel.danmakuSettings
                settings.displayArea = newValue
                viewModel.updateDanmakuSettings(settings)
            }
        )
    }

    private var fontWeightBinding: Binding<DanmakuFontWeightOption> {
        Binding(
            get: { viewModel.danmakuSettings.fontWeight },
            set: { newValue in
                var settings = viewModel.danmakuSettings
                settings.fontWeight = newValue
                viewModel.updateDanmakuSettings(settings)
            }
        )
    }

    private func settingSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }
}

private struct PlaybackNetworkDiagnosticsSheet: View {
    @ObservedObject var viewModel: VideoDetailViewModel
    @ObservedObject var libraryStore: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var isProbingPlaybackCDN = false
    @State private var probeMessage: String?
    @State private var copiedMessage: String?

    private var variant: PlayVariant? {
        viewModel.selectedPlayVariant
    }

    private var playerViewModel: PlayerStateViewModel? {
        viewModel.stablePlayerViewModel
    }

    private var playbackEnvironment: PlaybackEnvironment {
        PlaybackEnvironment.current
    }

    var body: some View {
        NavigationStack {
            Form {
                actionsSection
                cdnSection
                loadingMetricsSection
                streamSection
                playerSection
                environmentSection
                probeSection
            }
            .navigationTitle("网络诊断")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                copyDiagnostics()
            } label: {
                Label(copiedMessage ?? "复制诊断信息", systemImage: "doc.on.doc")
            }

            Button {
                probePlaybackCDN()
            } label: {
                Label(isProbingPlaybackCDN ? "CDN 测速中" : "重新测速 CDN", systemImage: "speedometer")
            }
            .disabled(isProbingPlaybackCDN)

            if let probeMessage {
                Text(probeMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var cdnSection: some View {
        Section("CDN") {
            diagnosticRow("当前使用", libraryStore.effectivePlaybackCDNPreference.title)
            diagnosticRow("设置模式", libraryStore.playbackCDNPreference.title)

            if libraryStore.playbackCDNPreference == .automatic {
                diagnosticRow(
                    "自动推荐",
                    libraryStore.automaticPlaybackCDNRecommendation?.title ?? "暂无可用推荐"
                )
            }

            diagnosticRow("视频 Host", variant?.videoURL?.host ?? "未获取")

            if let audioURL = variant?.audioURL {
                diagnosticRow("音频 Host", audioURL.host ?? "未知")
            }
        }
    }

    private var loadingMetricsSection: some View {
        Section("加载耗时") {
            diagnosticRow("视频详情", formattedMilliseconds(viewModel.detailLoadElapsedMilliseconds))
            diagnosticRow("播放地址", formattedMilliseconds(viewModel.playURLElapsedMilliseconds))
            diagnosticRow("相关推荐", formattedMilliseconds(viewModel.relatedElapsedMilliseconds))
            diagnosticRow("取流来源", playURLSourceTitle)

            if viewModel.lastRelatedLoadTimedOut {
                Label("相关推荐最近一次加载超时，已停止等待并保留主播放优先。", systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var streamSection: some View {
        Section("当前流") {
            diagnosticRow("清晰度", variant?.title ?? "未选择")
            diagnosticRow("封装模式", streamModeTitle)
            diagnosticRow("编码", variant?.codec?.nilIfEmpty ?? "未知")
            diagnosticRow("分辨率", variant?.resolution?.nilIfEmpty ?? "未知")
            diagnosticRow("帧率", frameRateTitle)
            diagnosticRow("带宽", bandwidthTitle)

            if let subtitle = variant?.subtitle, !subtitle.isEmpty {
                diagnosticMultilineRow("档位信息", subtitle)
            }
        }
    }

    private var playerSection: some View {
        Section("播放器") {
            diagnosticRow("状态", playerStateTitle)
            diagnosticRow("首帧", playerViewModel?.hasPresentedPlayback == true ? "已显示" : "等待中")
            diagnosticRow("缓冲", playerViewModel?.isBuffering == true ? "缓冲中" : "未缓冲")
            diagnosticRow("可拖动", playerViewModel?.canSeek == true ? "可用" : "等待就绪")
            diagnosticRow("准备耗时", formattedMilliseconds(playerViewModel?.prepareElapsedMilliseconds))
            diagnosticRow("首帧耗时", formattedMilliseconds(playerViewModel?.firstFrameElapsedMilliseconds))
            diagnosticRow("缓冲次数", "\(playerViewModel?.bufferingCount ?? 0)")
            diagnosticRow("最近缓冲", formattedMilliseconds(playerViewModel?.lastBufferingElapsedMilliseconds))

            if let loadingProgress = playerViewModel?.loadingProgress {
                diagnosticRow("加载进度", "\(Int((loadingProgress * 100).rounded()))%")
            }

            if let errorMessage = playerViewModel?.errorMessage, !errorMessage.isEmpty {
                diagnosticMultilineRow("错误", errorMessage)
            }

            if let fallbackMessage = viewModel.playbackFallbackMessage, !fallbackMessage.isEmpty {
                diagnosticMultilineRow("降级信息", fallbackMessage)
            }
        }
    }

    private var environmentSection: some View {
        Section("设备网络") {
            diagnosticRow("网络类型", playbackEnvironment.networkClass.diagnosticTitle)
            diagnosticRow("省电模式", playbackEnvironment.isLowPowerModeEnabled ? "开启" : "关闭")
            diagnosticRow("温控限制", playbackEnvironment.isThermallyConstrained ? "已触发" : "未触发")
            diagnosticRow("保守播放策略", playbackEnvironment.shouldPreferConservativePlayback ? "启用" : "未启用")
        }
    }

    @ViewBuilder
    private var probeSection: some View {
        Section("最近测速") {
            if let snapshot = libraryStore.playbackCDNProbeSnapshot {
                diagnosticRow(
                    "测速时间",
                    snapshot.probedAt.formatted(date: .abbreviated, time: .shortened)
                )
                diagnosticRow("有效状态", snapshot.isExpired() ? "已过期" : "有效")
                diagnosticRow("推荐 CDN", snapshot.recommendedPreference?.title ?? "暂无推荐")

                if let recommendation = snapshot.recommendedPreference,
                   let result = snapshot.result(for: recommendation) {
                    diagnosticRow("推荐延迟", result.elapsedMilliseconds.map { "\($0) ms" } ?? "失败")
                }

                if !snapshot.successfulResults.isEmpty {
                    DisclosureGroup {
                        ForEach(snapshot.results.prefix(8)) { result in
                            diagnosticProbeResultRow(result)
                        }
                    } label: {
                        Label("测速排行", systemImage: "list.number")
                    }
                }

                if snapshot.isExpired() {
                    Label("测速结果超过 24 小时，自动 CDN 可能需要重新测速。", systemImage: "clock.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else {
                ContentUnavailableView(
                    "暂无 CDN 测速结果",
                    systemImage: "network.slash",
                    description: Text("进入我的页面执行一次 CDN 测速后，这里会显示推荐节点和延迟。")
                )
            }
        }
    }

    private var streamModeTitle: String {
        guard let variant else { return "未获取" }
        if variant.videoStream != nil || variant.audioStream != nil {
            return variant.audioURL == nil ? "DASH 视频流" : "DASH 音视频分离"
        }
        return "Progressive 单流"
    }

    private var frameRateTitle: String {
        guard let frameRate = variant?.frameRate?.nilIfEmpty else { return "未知" }
        return frameRate.localizedCaseInsensitiveContains("fps") ? frameRate : "\(frameRate) fps"
    }

    private var bandwidthTitle: String {
        guard let bandwidth = variant?.bandwidth, bandwidth > 0 else { return "未知" }
        let mbps = Double(bandwidth) / 1_000_000
        return "\(String(format: "%.2f", mbps)) Mbps"
    }

    private var playerStateTitle: String {
        guard let playerViewModel else { return "等待播放器" }
        if playerViewModel.errorMessage?.isEmpty == false {
            return "播放错误"
        }
        if playerViewModel.isPreparing {
            return "准备中"
        }
        if playerViewModel.isBuffering {
            return "缓冲中"
        }
        if playerViewModel.isPlaying {
            return "播放中"
        }
        return "暂停/待播"
    }

    private var playURLSourceTitle: String {
        switch viewModel.lastPlayURLSource {
        case "playableCache":
            return "可播放缓存"
        case "playableCacheStaleWhileRefresh":
            return "可播放缓存，后台刷新"
        case "cache":
            return "缓存"
        case "pendingCache":
            return "预加载结果"
        case "pendingCacheStaleWhileRefresh":
            return "预加载结果，后台刷新"
        case "detailWarmCache":
            return "详情预热缓存"
        case "network":
            return "网络请求"
        case let source?:
            return source
        case nil:
            return "未获取"
        }
    }

    private func diagnosticRow(_ title: String, _ value: String) -> some View {
        LabeledContent {
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        } label: {
            Text(title)
        }
    }

    private func diagnosticMultilineRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func diagnosticProbeResultRow(_ result: PlaybackCDNProbeResult) -> some View {
        HStack(spacing: 8) {
            Image(systemName: result.didSucceed ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(result.didSucceed ? .green : .secondary)
            Text(result.preference.title)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(result.elapsedMilliseconds.map { "\($0) ms" } ?? result.errorDescription ?? "失败")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func formattedMilliseconds(_ value: Int?) -> String {
        guard let value else { return "未记录" }
        if value >= 1000 {
            return String(format: "%.2f s", Double(value) / 1000)
        }
        return "\(value) ms"
    }

    private func copyDiagnostics() {
        UIPasteboard.general.string = diagnosticsText
        copiedMessage = "已复制诊断信息"
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copiedMessage = nil
        }
    }

    private func probePlaybackCDN() {
        guard !isProbingPlaybackCDN else { return }
        isProbingPlaybackCDN = true
        probeMessage = "正在测试 CDN 线路..."
        Task {
            let snapshot = await PlaybackCDNProbeService.recommendedSnapshot()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                libraryStore.setPlaybackCDNProbeSnapshot(snapshot)
                if let preference = snapshot.recommendedPreference,
                   let elapsed = snapshot.result(for: preference)?.elapsedMilliseconds {
                    libraryStore.setPlaybackCDNPreference(preference)
                    probeMessage = "已推荐 \(preference.title)，\(elapsed) ms"
                } else {
                    probeMessage = "未找到可用 CDN，已保留当前设置"
                }
                isProbingPlaybackCDN = false
            }
        }
    }

    private var diagnosticsText: String {
        var lines = [String]()
        lines.append("播放器网络诊断")
        lines.append("视频：\(viewModel.detail.title)")
        lines.append("BVID：\(viewModel.detail.bvid)")
        lines.append("当前 CDN：\(libraryStore.effectivePlaybackCDNPreference.title)")
        lines.append("CDN 设置：\(libraryStore.playbackCDNPreference.title)")
        lines.append("视频 Host：\(variant?.videoURL?.host ?? "未获取")")
        lines.append("音频 Host：\(variant?.audioURL?.host ?? "未获取")")
        lines.append("清晰度：\(variant?.title ?? "未选择")")
        lines.append("封装模式：\(streamModeTitle)")
        lines.append("编码：\(variant?.codec?.nilIfEmpty ?? "未知")")
        lines.append("分辨率：\(variant?.resolution?.nilIfEmpty ?? "未知")")
        lines.append("帧率：\(frameRateTitle)")
        lines.append("带宽：\(bandwidthTitle)")
        lines.append("视频详情耗时：\(formattedMilliseconds(viewModel.detailLoadElapsedMilliseconds))")
        lines.append("播放地址耗时：\(formattedMilliseconds(viewModel.playURLElapsedMilliseconds))")
        lines.append("相关推荐耗时：\(formattedMilliseconds(viewModel.relatedElapsedMilliseconds))")
        lines.append("取流来源：\(playURLSourceTitle)")
        lines.append("播放器状态：\(playerStateTitle)")
        lines.append("准备耗时：\(formattedMilliseconds(playerViewModel?.prepareElapsedMilliseconds))")
        lines.append("首帧耗时：\(formattedMilliseconds(playerViewModel?.firstFrameElapsedMilliseconds))")
        lines.append("缓冲次数：\(playerViewModel?.bufferingCount ?? 0)")
        lines.append("最近缓冲：\(formattedMilliseconds(playerViewModel?.lastBufferingElapsedMilliseconds))")
        lines.append("网络类型：\(playbackEnvironment.networkClass.diagnosticTitle)")
        lines.append("省电模式：\(playbackEnvironment.isLowPowerModeEnabled ? "开启" : "关闭")")
        lines.append("温控限制：\(playbackEnvironment.isThermallyConstrained ? "已触发" : "未触发")")
        if let snapshot = libraryStore.playbackCDNProbeSnapshot {
            lines.append("测速时间：\(snapshot.probedAt.formatted(date: .abbreviated, time: .shortened))")
            lines.append("测速推荐：\(snapshot.recommendedPreference?.title ?? "暂无推荐")")
            lines.append("测速是否过期：\(snapshot.isExpired() ? "是" : "否")")
        }
        if let errorMessage = playerViewModel?.errorMessage, !errorMessage.isEmpty {
            lines.append("播放器错误：\(errorMessage)")
        }
        if let fallbackMessage = viewModel.playbackFallbackMessage, !fallbackMessage.isEmpty {
            lines.append("降级信息：\(fallbackMessage)")
        }
        return lines.joined(separator: "\n")
    }
}

private extension PlaybackEnvironment.NetworkClass {
    var diagnosticTitle: String {
        switch self {
        case .wifi:
            return "Wi-Fi"
        case .cellular:
            return "蜂窝网络"
        case .constrained:
            return "受限网络"
        case .unknown:
            return "未知"
        }
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
}

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct VideoTitleText: UIViewRepresentable {
    let text: String

    func makeUIView(context _: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 3
        label.lineBreakMode = .byCharWrapping
        label.textAlignment = .left
        label.adjustsFontForContentSizeCategory = true
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: UILabel, context _: Context) {
        label.text = text
        label.font = Self.font
        label.textColor = .label
        label.lineBreakMode = .byCharWrapping
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView label: UILabel, context _: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else {
            return nil
        }
        label.preferredMaxLayoutWidth = width
        return label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    private static var font: UIFont {
        let baseFont = UIFont.systemFont(ofSize: 20, weight: .semibold)
        return UIFontMetrics(forTextStyle: .title3).scaledFont(for: baseFont)
    }
}

private struct FullscreenContainerGeometry {
    let size: CGSize
    let offset: CGSize
}

private extension GeometryProxy {
    var fullscreenContainerGeometry: FullscreenContainerGeometry {
        if let window = UIApplication.shared.biliForegroundKeyWindow,
           let rootView = window.rootViewController?.view {
            let localFrame = frame(in: .global)
            let frameInWindow = rootView.convert(localFrame, from: nil)
            return FullscreenContainerGeometry(
                size: window.bounds.size,
                offset: CGSize(width: -frameInWindow.minX, height: -frameInWindow.minY)
            )
        }

        let expandedSize = CGSize(
            width: size.width + safeAreaInsets.leading + safeAreaInsets.trailing,
            height: size.height + safeAreaInsets.top + safeAreaInsets.bottom
        )
        return FullscreenContainerGeometry(
            size: expandedSize,
            offset: CGSize(width: -safeAreaInsets.leading, height: -safeAreaInsets.top)
        )
    }
}

private extension UIApplication {
    var biliForegroundKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}

private struct VideoDetailChromeHiddenPreferenceKey: PreferenceKey {
    static var defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

private struct StatusBarStyleBridge: UIViewControllerRepresentable {
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

private struct VideoDetailLifecycleBridge: UIViewControllerRepresentable {
    let onWillDisappear: () -> Void

    func makeUIViewController(context _: Context) -> Controller {
        let controller = Controller()
        controller.onWillDisappear = onWillDisappear
        return controller
    }

    func updateUIViewController(_ uiViewController: Controller, context _: Context) {
        uiViewController.onWillDisappear = onWillDisappear
    }

    final class Controller: UIViewController {
        var onWillDisappear: (() -> Void)?

        override func loadView() {
            view = ClearPassthroughView()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            onWillDisappear?()
        }
    }
}

private struct PlayerPerformanceOverlay: View {
    @StateObject private var store = PlayerPerformanceStore.shared
    let metricsID: String

    private var session: PlayerPerformanceSession? {
        store.sessions.first { $0.metricsID == metricsID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.caption2.weight(.bold))
                Text("播放性能")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 8)
                Text(shortID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            if let session {
                LazyVGrid(
                    columns: [
                        GridItem(.fixed(74), spacing: 8),
                        GridItem(.fixed(74), spacing: 8)
                    ],
                    alignment: .leading,
                    spacing: 6
                ) {
                    metric("总首帧", session.firstFrameTotalMilliseconds)
                    metric("播放器", session.firstFramePlayerMilliseconds)
                    metric("取流", session.playURLMilliseconds)
                    metric("Prepare", session.prepareMilliseconds)
                }

                if let cdnHost = session.cdnHostMessage {
                    Label(cdnHost, systemImage: "network")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let networkMessage = session.networkMessage {
                    Text(networkMessage)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let mediaCacheMessage = session.mediaCacheMessage {
                    Text(mediaCacheMessage)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Text("缓冲 \(session.bufferCount)")
                    if let quality = session.selectedQualityMessage {
                        Text(quality)
                            .lineLimit(1)
                    }
                }
                .font(.caption2)
                .foregroundStyle(session.bufferCount > 0 ? .orange : .secondary)

                if let failure = session.failureMessage {
                    Text(failure)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            } else {
                Text("等待播放事件")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(width: 178, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.20), lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }

    private var shortID: String {
        guard metricsID.count > 8 else { return metricsID }
        return String(metricsID.suffix(8))
    }

    private func metric(_ title: String, _ milliseconds: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(millisecondsText(milliseconds))
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(metricColor(milliseconds))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func millisecondsText(_ value: Int?) -> String {
        guard let value else { return "-" }
        if value >= 1000 {
            return String(format: "%.2fs", Double(value) / 1000)
        }
        return "\(value)ms"
    }

    private func metricColor(_ value: Int?) -> Color {
        guard let value else { return .secondary }
        if value >= 2500 {
            return .red
        }
        if value >= 1400 {
            return .orange
        }
        return .green
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var normalizedDetailTitle: String {
        var text = self
        ["\u{200B}", "\u{200C}", "\u{200D}", "\u{FEFF}"].forEach {
            text = text.replacingOccurrences(of: $0, with: "")
        }
        ["\u{2028}", "\u{2029}"].forEach {
            text = text.replacingOccurrences(of: $0, with: " ")
        }
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        text = text.replacingOccurrences(
            of: #"([\p{Han}\p{Hiragana}\p{Katakana}\p{Bopomofo}\p{N}，。！？、：；（）《》“”‘’【】])\s+([\p{Han}\p{Hiragana}\p{Katakana}\p{Bopomofo}\p{N}，。！？、：；（）《》“”‘’【】])"#,
            with: "$1$2",
            options: .regularExpression
        )
        return text
    }
}

private struct InlineMetadataButtonLabel: View {
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
        .glassEffect(
            .regular
                .tint(Color(.systemBackground).opacity(0.08))
                .interactive(true),
            in: Capsule(style: .continuous)
        )
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color(.separator).opacity(0.14), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }
}

private struct ToolbarAvatar: View {
    let urlString: String?

    var body: some View {
        CachedRemoteImage(
            url: urlString.flatMap { URL(string: $0.biliAvatarThumbnailURL(size: 72)) },
            targetPixelSize: 72
        ) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(.secondary)
        }
        .frame(width: 30, height: 30)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(Color(.separator).opacity(0.18), lineWidth: 0.7)
        }
        .contentShape(Circle())
    }
}

private enum CommentSectionStyle {
    case grouped
    case plain

    var horizontalPadding: CGFloat {
        switch self {
        case .grouped:
            return 14
        case .plain:
            return 16
        }
    }

    var showsReplyPreviewContainer: Bool {
        self == .grouped
    }

    var usesGroupedFooter: Bool {
        self == .grouped
    }
}

private struct PortraitCommentsSheet: View {
    @ObservedObject var viewModel: VideoDetailViewModel
    @State private var replySheetComment: Comment?
    @State private var imageSelection: CommentImageSelection?
    @Namespace private var imageTransitionNamespace

    var body: some View {
        NavigationStack {
            List {
                sortPickerRow
                commentsListContent
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(.clear)
            .navigationTitle("评论 \(BiliFormatters.compactCount(viewModel.detail.stat?.reply))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.automatic, for: .navigationBar)
            .nativeTopScrollEdgeEffect()
            .refreshable {
                await viewModel.retryComments()
            }
            .task {
                viewModel.beginInitialCommentsLoadIfNeeded()
            }
        }
        .presentationDetents([.fraction(0.7)])
        .presentationDragIndicator(.visible)
        .fullScreenCover(item: $imageSelection) { selection in
            NativeImageViewer(
                images: selection.images,
                initialIndex: selection.initialIndex,
                transitionID: selection.transitionID,
                transitionNamespace: imageTransitionNamespace
            )
        }
        .sheet(item: $replySheetComment) { comment in
            CommentRepliesSheet(rootComment: comment, viewModel: viewModel)
        }
    }

    private var sortPickerRow: some View {
        Picker(
            "评论排序",
            selection: Binding(
                get: { viewModel.selectedCommentSort },
                set: { sort in
                    Task { await viewModel.selectCommentSort(sort) }
                }
            )
        ) {
            ForEach(CommentSort.allCases) { sort in
                Text(sort.title).tag(sort)
            }
        }
        .pickerStyle(.segmented)
        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 10, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var commentsListContent: some View {
        if viewModel.comments.isEmpty && (viewModel.commentState.isLoading || viewModel.commentState == .idle) {
            loadingRow
        } else if viewModel.comments.isEmpty, case .failed(let message) = viewModel.commentState {
            errorRow(message: message)
        } else if viewModel.shouldShowEmptyCommentsState {
            emptyRow
        } else if viewModel.shouldShowCommentReloadPrompt {
            errorRow(message: "评论暂时没有返回内容")
        } else {
            ForEach(viewModel.comments) { comment in
                CommentRow(
                    comment: comment,
                    style: .plain,
                    transitionNamespace: imageTransitionNamespace,
                    showReplies: {
                        replySheetComment = comment
                    },
                    showImages: { images, initialIndex in
                        presentImages(
                            images,
                            initialIndex: initialIndex,
                            transitionID: NativeImageViewerTransitionID.image(
                                images[min(max(initialIndex, 0), max(images.count - 1, 0))],
                                index: min(max(initialIndex, 0), max(images.count - 1, 0)),
                                scope: comment.id.description
                            )
                        )
                    }
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(Color.clear)
                .task {
                    await viewModel.loadMoreCommentsIfNeeded(current: comment)
                }
            }

            footerRow
        }
    }

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("正在加载评论")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func errorRow(message: String) -> some View {
        CommentErrorView(message: message) {
            Task { await viewModel.retryComments() }
        }
        .padding(.vertical, 18)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var emptyRow: some View {
        EmptyStateView(title: "暂无评论", systemImage: "bubble.left", message: "这里还没有可展示的评论。")
            .padding(.vertical, 28)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var footerRow: some View {
        if viewModel.commentState.isLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("加载更多评论")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else if case .failed(let message) = viewModel.commentState {
            errorRow(message: message)
        } else if viewModel.hasMoreComments {
            Button {
                Task { await viewModel.loadMoreComments() }
            } label: {
                Label("加载更多评论", systemImage: "arrow.down.circle")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.pink)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else if !viewModel.comments.isEmpty {
            Text("没有更多评论了")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }

    private func presentImages(_ images: [DynamicImageItem], initialIndex: Int = 0, transitionID: String? = nil) {
        let visibleImages = images.filter { $0.normalizedURL != nil }
        guard !visibleImages.isEmpty else { return }
        let safeIndex = min(max(initialIndex, 0), visibleImages.count - 1)
        imageSelection = CommentImageSelection(
            images: visibleImages,
            initialIndex: safeIndex,
            transitionID: transitionID ?? NativeImageViewerTransitionID.image(visibleImages[safeIndex], index: safeIndex, scope: "portrait-comments")
        )
    }
}

private struct CommentsSectionView: View {
    @ObservedObject var viewModel: VideoDetailViewModel
    let style: CommentSectionStyle
    var maxVisibleComments: Int?
    var autoLoads = true
    var showAllComments: (() -> Void)?
    let showReplies: (Comment) -> Void
    @State private var imageSelection: CommentImageSelection?
    @Namespace private var imageTransitionNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            commentsHeader
            commentsContent
        }
        .padding(.vertical, 14)
        .background(style == .grouped ? Color.videoDetailSurface : Color.clear)
        .fullScreenCover(item: $imageSelection) { selection in
            NativeImageViewer(
                images: selection.images,
                initialIndex: selection.initialIndex,
                transitionID: selection.transitionID,
                transitionNamespace: imageTransitionNamespace
            )
        }
        .task {
            guard autoLoads else { return }
            viewModel.beginInitialCommentsLoadIfNeeded()
        }
    }

    private func presentImages(_ images: [DynamicImageItem], initialIndex: Int = 0, transitionID: String? = nil) {
        let visibleImages = images.filter { $0.normalizedURL != nil }
        guard !visibleImages.isEmpty else { return }
        let safeIndex = min(max(initialIndex, 0), visibleImages.count - 1)
        imageSelection = CommentImageSelection(
            images: visibleImages,
            initialIndex: safeIndex,
            transitionID: transitionID ?? NativeImageViewerTransitionID.image(visibleImages[safeIndex], index: safeIndex, scope: "comments-section")
        )
    }

    private var commentsHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("评论")
                .font(.headline)

            if let count = viewModel.detail.stat?.reply {
                Text(BiliFormatters.compactCount(count))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                ForEach(CommentSort.allCases) { sort in
                    Button {
                        Task { await viewModel.selectCommentSort(sort) }
                    } label: {
                        Text(sort.title)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(viewModel.selectedCommentSort == sort ? Color.pink.opacity(0.14) : Color.clear)
                            .foregroundStyle(viewModel.selectedCommentSort == sort ? .pink : .secondary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, style.horizontalPadding)
    }

    @ViewBuilder
    private var commentsContent: some View {
        if viewModel.comments.isEmpty && shouldShowLoadingPlaceholder {
            VStack(spacing: 10) {
                ProgressView()
                Text("正在加载评论")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
        } else if viewModel.comments.isEmpty, case .failed(let message) = viewModel.commentState {
            CommentErrorView(message: message) {
                Task { await viewModel.retryComments() }
            }
            .padding(.horizontal, style.horizontalPadding)
        } else if viewModel.shouldShowEmptyCommentsState {
            EmptyStateView(title: "暂无评论", systemImage: "bubble.left", message: "评论加载后会显示在这里。")
                .padding(.horizontal, style.horizontalPadding)
        } else if viewModel.shouldShowCommentReloadPrompt {
            CommentErrorView(message: "评论暂时没有返回内容") {
                Task { await viewModel.retryComments() }
            }
            .padding(.horizontal, style.horizontalPadding)
        } else if viewModel.comments.isEmpty {
            Color.clear
                .frame(height: 1)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(visibleComments) { comment in
                    CommentRow(
                        comment: comment,
                        style: style,
                        transitionNamespace: imageTransitionNamespace,
                        showReplies: {
                            showReplies(comment)
                        },
                        showImages: { images, initialIndex in
                            presentImages(
                                images,
                                initialIndex: initialIndex,
                                transitionID: NativeImageViewerTransitionID.image(
                                    images[min(max(initialIndex, 0), max(images.count - 1, 0))],
                                    index: min(max(initialIndex, 0), max(images.count - 1, 0)),
                                    scope: comment.id.description
                                )
                            )
                        }
                    )
                    .padding(.horizontal, style.horizontalPadding)
                    .task {
                        if maxVisibleComments == nil {
                            await viewModel.loadMoreCommentsIfNeeded(current: comment)
                        }
                    }

                    Divider()
                        .padding(.leading, 64)
                }

                Group {
                    if maxVisibleComments != nil {
                        commentPreviewFooter
                    } else {
                        commentFooter
                    }
                }
                .padding(.horizontal, style.horizontalPadding)
                .padding(.top, 8)
            }
        }
    }

    private var shouldShowLoadingPlaceholder: Bool {
        viewModel.commentState.isLoading || (autoLoads && viewModel.commentState == .idle)
    }

    private var visibleComments: [Comment] {
        guard let maxVisibleComments else { return viewModel.comments }
        return Array(viewModel.comments.prefix(maxVisibleComments))
    }

    @ViewBuilder
    private var commentPreviewFooter: some View {
        if viewModel.commentState.isLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("加载评论")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        } else {
            Button {
                showAllComments?()
            } label: {
                Label("查看全部评论", systemImage: "bubble.left.and.bubble.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.videoDetailSecondarySurface)
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var commentFooter: some View {
        if viewModel.commentState.isLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("加载更多评论")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        } else if case .failed(let message) = viewModel.commentState {
            CommentErrorView(message: message) {
                Task { await viewModel.retryComments() }
            }
        } else if viewModel.hasMoreComments {
            Button {
                Task { await viewModel.loadMoreComments() }
            } label: {
                if style.usesGroupedFooter {
                    Label("加载更多评论", systemImage: "arrow.down.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.videoDetailSecondarySurface)
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Label("加载更多评论", systemImage: "arrow.down.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(.pink)
                }
            }
            .buttonStyle(.plain)
        } else {
            Text("没有更多评论了")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
    }

}

private struct CommentRow: View {
    let comment: Comment
    let style: CommentSectionStyle
    let transitionNamespace: Namespace.ID
    let showReplies: () -> Void
    let showImages: ([DynamicImageItem], Int) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            avatar

            VStack(alignment: .leading, spacing: 8) {
                header

                BiliEmoteText(content: comment.content, font: .subheadline, textColor: .primary, emoteSize: 22)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                CommentImageThumbnailGrid(
                    images: comment.content?.pictures ?? [],
                    transitionScope: comment.id.description,
                    transitionNamespace: transitionNamespace,
                    showImage: showImages
                )

                if !replyPreviews.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(replyPreviews.enumerated()), id: \.offset) { _, reply in
                            ReplyPreviewRow(reply: reply)
                        }
                    }
                    .padding(style.showsReplyPreviewContainer ? 10 : 0)
                    .background(style.showsReplyPreviewContainer ? Color.videoDetailSecondarySurface : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: style.showsReplyPreviewContainer ? 10 : 0, style: .continuous))
                }

                if visibleReplyCount > 0 {
                    Button(action: showReplies) {
                        Label("\(visibleReplyCount) 条回复", systemImage: "bubble.left.and.bubble.right")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.pink)
                }
            }
        }
        .padding(.vertical, 12)
    }

    private var avatar: some View {
        CachedRemoteImage(
            url: comment.member?.avatar.flatMap { URL(string: $0.biliAvatarThumbnailURL(size: 96)) },
            targetPixelSize: 96
        ) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(comment.member?.uname ?? "Unknown")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !timeText.isEmpty {
                Text(timeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Label(BiliFormatters.compactCount(comment.like), systemImage: comment.likeState == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
                .font(.caption)
                .foregroundStyle(comment.likeState == 1 ? .pink : .secondary)
                .labelStyle(.titleAndIcon)
        }
    }

    private var message: String {
        let text = comment.content?.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? " " : text
    }

    private var timeText: String {
        BiliFormatters.relativeTime(comment.ctime)
    }

    private var replyPreviews: [Comment] {
        Array((comment.replies ?? []).prefix(2))
    }

    private var visibleReplyCount: Int {
        comment.replyCount ?? comment.replies?.count ?? 0
    }
}

private struct ReplyPreviewRow: View {
    let reply: Comment

    var body: some View {
        BiliEmoteText(
            content: reply.content,
            font: .caption,
            textColor: .primary,
            emoteSize: 18,
            leadingName: reply.member?.uname ?? "Unknown",
            leadingNameColor: .secondary
        )
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CommentImageButton: View {
    let images: [DynamicImageItem]
    let transitionScope: String
    let transitionNamespace: Namespace.ID
    let showImages: ([DynamicImageItem], String) -> Void

    private var visibleImages: [DynamicImageItem] {
        images.filter { $0.normalizedURL != nil }
    }

    var body: some View {
        if !visibleImages.isEmpty {
            Button {
                showImages(visibleImages, transitionID)
            } label: {
                Label(title, systemImage: "photo.on.rectangle.angled")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.videoDetailSecondarySurface)
                    .foregroundStyle(.pink)
                    .clipShape(Capsule())
                    .matchedTransitionSource(id: transitionID, in: transitionNamespace)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
    }

    private var title: String {
        visibleImages.count > 1 ? "点击查看图片 \(visibleImages.count) 张" : "点击查看图片"
    }

    private var transitionID: String {
        guard let firstImage = visibleImages.first else { return "\(transitionScope)|empty" }
        return NativeImageViewerTransitionID.image(firstImage, index: 0, scope: transitionScope)
    }
}

private struct CommentImageThumbnailGrid: View {
    let images: [DynamicImageItem]
    let transitionScope: String
    let transitionNamespace: Namespace.ID
    let showImage: ([DynamicImageItem], Int) -> Void

    private var visibleImages: [DynamicImageItem] {
        images.filter { $0.normalizedURL != nil }
    }

    var body: some View {
        if !visibleImages.isEmpty {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(Array(visibleImages.enumerated()), id: \.offset) { index, image in
                    Button {
                        showImage(visibleImages, index)
                    } label: {
                        CommentImageThumbnail(image: image, imageCount: visibleImages.count)
                            .matchedTransitionSource(
                                id: NativeImageViewerTransitionID.image(image, index: index, scope: transitionScope),
                                in: transitionNamespace
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: maxGridWidth, alignment: .leading)
            .padding(.top, 2)
        }
    }

    private var columns: [GridItem] {
        let count = min(visibleImages.count, 3)
        return Array(repeating: GridItem(.fixed(thumbnailSide), spacing: 6), count: max(count, 1))
    }

    private var thumbnailSide: CGFloat {
        visibleImages.count == 1 ? 132 : 86
    }

    private var maxGridWidth: CGFloat {
        let count = CGFloat(min(max(visibleImages.count, 1), 3))
        return thumbnailSide * count + 6 * max(count - 1, 0)
    }
}

private struct CommentImageThumbnail: View {
    let image: DynamicImageItem
    let imageCount: Int

    var body: some View {
        CachedRemoteImage(url: thumbnailURL, targetPixelSize: targetPixelSize) { loadedImage in
            loadedImage
                .resizable()
                .scaledToFill()
        } placeholder: {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.videoDetailSecondarySurface)
                .overlay {
                    Image(systemName: "photo")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(.separator).opacity(0.10), lineWidth: 0.6)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var thumbnailURL: URL? {
        image.normalizedURL
            .map { $0.biliCoverThumbnailURL(width: Int(size.width * 3), height: Int(size.height * 3)) }
            .flatMap(URL.init(string:))
    }

    private var targetPixelSize: Int {
        Int(ceil(max(size.width, size.height) * UIScreen.main.scale))
    }

    private var size: CGSize {
        if imageCount == 1 {
            let width: CGFloat = 132
            let ratio = min(max(CGFloat(image.aspectRatio), 0.55), 1.85)
            let height = min(max(width / ratio, 78), 176)
            return CGSize(width: width, height: height)
        }
        return CGSize(width: 86, height: 86)
    }
}

private struct CommentImageSelection: Identifiable {
    let id = UUID()
    let images: [DynamicImageItem]
    let initialIndex: Int
    let transitionID: String
}

private enum CommentTextBuilder {
    static func nameAndMessage(name: String, message: String, font: Font, contentColor: Color) -> AttributedString {
        var user = AttributedString("\(name)：")
        user.font = font.weight(.semibold)
        user.foregroundColor = .secondary

        return user + replyMessage(message, font: font, contentColor: contentColor)
    }

    static func replyMessage(_ message: String, font: Font, contentColor: Color) -> AttributedString {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let split = replyPrefixSplit(in: text) else {
            var content = AttributedString(text)
            content.font = font
            content.foregroundColor = contentColor
            return content
        }

        var verb = AttributedString("回复 ")
        verb.font = font
        verb.foregroundColor = contentColor

        var target = AttributedString(split.target)
        target.font = font.weight(.semibold)
        target.foregroundColor = .pink

        var separator = AttributedString(split.separator)
        separator.font = font
        separator.foregroundColor = contentColor

        var content = AttributedString(split.content)
        content.font = font
        content.foregroundColor = contentColor

        return verb + target + separator + content
    }

    static func hasReplyTarget(in message: String?) -> Bool {
        guard let message else { return false }
        return replyPrefixSplit(in: message.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    private static func replyPrefixSplit(in message: String) -> (target: String, separator: String, content: String)? {
        let supportedVerbs = ["回复", "回覆", "回復"]
        guard let verb = supportedVerbs.first(where: { message.hasPrefix($0) }) else { return nil }

        var cursor = message.index(message.startIndex, offsetBy: verb.count)
        while cursor < message.endIndex, message[cursor].isWhitespace {
            cursor = message.index(after: cursor)
        }

        guard cursor < message.endIndex, message[cursor] == "@" else { return nil }
        guard let colon = message[cursor...].firstIndex(where: { $0 == ":" || $0 == "：" }) else { return nil }

        let prefixEnd = message.index(after: colon)
        let target = String(message[cursor..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = String(message[colon..<prefixEnd])
        let content = String(message[prefixEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return nil }
        return (target, separator, content)
    }
}

private struct CommentErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                Text("评论加载失败")
                    .font(.subheadline.weight(.semibold))
            }

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Button(action: retry) {
                Label("重试", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.videoDetailSecondarySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct CommentRepliesSheet: View {
    let rootComment: Comment
    @ObservedObject var viewModel: VideoDetailViewModel
    @State private var dialogReply: Comment?
    @State private var imageSelection: CommentImageSelection?
    @Namespace private var imageTransitionNamespace

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CommentReplyRootView(
                        comment: rootComment,
                        transitionNamespace: imageTransitionNamespace,
                        showImages: presentImages
                    )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                    Divider()

                    repliesContent
                }
            }
            .navigationTitle("评论回复")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.loadReplies(for: rootComment)
            }
        }
        .presentationDetents([.fraction(0.7)])
        .presentationDragIndicator(.visible)
        .sheet(item: $dialogReply) { reply in
            CommentDialogSheet(rootComment: rootComment, focusReply: reply, viewModel: viewModel)
        }
        .fullScreenCover(item: $imageSelection) { selection in
            NativeImageViewer(
                images: selection.images,
                initialIndex: selection.initialIndex,
                transitionID: selection.transitionID,
                transitionNamespace: imageTransitionNamespace
            )
        }
    }

    private func presentImages(_ images: [DynamicImageItem], transitionID: String) {
        let visibleImages = images.filter { $0.normalizedURL != nil }
        guard !visibleImages.isEmpty else { return }
        imageSelection = CommentImageSelection(
            images: visibleImages,
            initialIndex: 0,
            transitionID: transitionID
        )
    }

    @ViewBuilder
    private var repliesContent: some View {
        let state = viewModel.replyState(for: rootComment)
        let replies = viewModel.replies(for: rootComment)

        if replies.isEmpty && state.isLoading {
            VStack(spacing: 10) {
                ProgressView()
                Text("正在加载回复")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        } else if replies.isEmpty, case .failed(let message) = state {
            CommentErrorView(message: message) {
                Task { await viewModel.reloadReplies(for: rootComment) }
            }
            .padding(16)
        } else if replies.isEmpty {
            EmptyStateView(title: "暂无回复", systemImage: "bubble.left.and.bubble.right", message: "这条评论还没有可展示的回复。")
                .padding(16)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(replies) { reply in
                    CommentReplyDetailRow(
                        reply: reply,
                        transitionNamespace: imageTransitionNamespace,
                        showDialog: canShowDialog(for: reply) ? {
                            dialogReply = reply
                        } : nil,
                        showImages: presentImages
                    )
                        .padding(.horizontal, 16)
                    Divider()
                        .padding(.leading, 66)
                }

                repliesFooter(state: state)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
    }

    @ViewBuilder
    private func repliesFooter(state: LoadingState) -> some View {
        if !viewModel.replies(for: rootComment).isEmpty, state.isLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("加载更多回复")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        } else if case .failed(let message) = state {
            CommentErrorView(message: message) {
                Task { await viewModel.loadMoreReplies(for: rootComment) }
            }
        } else if viewModel.hasMoreReplies(for: rootComment) {
            Button {
                Task { await viewModel.loadMoreReplies(for: rootComment) }
            } label: {
                Label("查看更多回复", systemImage: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.pink)
        }
    }

    private func canShowDialog(for reply: Comment) -> Bool {
        guard reply.id != rootComment.id else { return false }
        if let dialogID = reply.dialogID, dialogID > 0 {
            return true
        }
        if let parentID = reply.parentID, parentID > 0, parentID != rootComment.rpid {
            return true
        }
        return CommentTextBuilder.hasReplyTarget(in: reply.content?.message)
    }
}

private struct CommentReplyRootView: View {
    let comment: Comment
    let transitionNamespace: Namespace.ID
    let showImages: ([DynamicImageItem], String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CommentAvatar(urlString: comment.member?.avatar, size: 40)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(comment.member?.uname ?? "Unknown")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if let time = comment.ctime, !BiliFormatters.relativeTime(time).isEmpty {
                        Text(BiliFormatters.relativeTime(time))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                BiliEmoteText(content: comment.content, font: .subheadline, textColor: .primary, emoteSize: 22)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                CommentImageButton(
                    images: comment.content?.pictures ?? [],
                    transitionScope: comment.id.description,
                    transitionNamespace: transitionNamespace,
                    showImages: showImages
                )
            }
        }
    }
}

private struct CommentReplyDetailRow: View {
    let reply: Comment
    let transitionNamespace: Namespace.ID
    let showDialog: (() -> Void)?
    let showImages: ([DynamicImageItem], String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CommentAvatar(urlString: reply.member?.avatar, size: 36)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(reply.member?.uname ?? "Unknown")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if !BiliFormatters.relativeTime(reply.ctime).isEmpty {
                        Text(BiliFormatters.relativeTime(reply.ctime))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Label(BiliFormatters.compactCount(reply.like), systemImage: reply.likeState == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(.caption)
                        .foregroundStyle(reply.likeState == 1 ? .pink : .secondary)
                        .labelStyle(.titleAndIcon)
                }

                BiliEmoteText(content: reply.content, font: .subheadline, textColor: .primary, emoteSize: 22)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                CommentImageButton(
                    images: reply.content?.pictures ?? [],
                    transitionScope: reply.id.description,
                    transitionNamespace: transitionNamespace,
                    showImages: showImages
                )

                if let showDialog {
                    Button(action: showDialog) {
                        Label("查看对话", systemImage: "text.bubble")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.pink)
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 12)
    }
}

private struct CommentDialogSheet: View {
    let rootComment: Comment
    let focusReply: Comment
    @ObservedObject var viewModel: VideoDetailViewModel
    @State private var imageSelection: CommentImageSelection?
    @Namespace private var imageTransitionNamespace

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CommentReplyRootView(
                        comment: rootComment,
                        transitionNamespace: imageTransitionNamespace,
                        showImages: presentImages
                    )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                    Divider()

                    dialogContent
                }
            }
            .navigationTitle("查看对话")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.loadDialog(for: rootComment, reply: focusReply)
            }
        }
        .presentationDetents([.fraction(0.7)])
        .presentationDragIndicator(.visible)
        .fullScreenCover(item: $imageSelection) { selection in
            NativeImageViewer(
                images: selection.images,
                initialIndex: selection.initialIndex,
                transitionID: selection.transitionID,
                transitionNamespace: imageTransitionNamespace
            )
        }
    }

    private func presentImages(_ images: [DynamicImageItem], transitionID: String) {
        let visibleImages = images.filter { $0.normalizedURL != nil }
        guard !visibleImages.isEmpty else { return }
        imageSelection = CommentImageSelection(
            images: visibleImages,
            initialIndex: 0,
            transitionID: transitionID
        )
    }

    @ViewBuilder
    private var dialogContent: some View {
        let state = viewModel.dialogState(for: rootComment, reply: focusReply)
        let replies = viewModel.dialogReplies(for: rootComment, reply: focusReply)

        if replies.isEmpty && state.isLoading {
            VStack(spacing: 10) {
                ProgressView()
                Text("正在加载对话")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        } else if replies.isEmpty, case .failed(let message) = state {
            CommentErrorView(message: message) {
                Task { await viewModel.reloadDialog(for: rootComment, reply: focusReply) }
            }
            .padding(16)
        } else if replies.isEmpty {
            EmptyStateView(title: "暂无对话", systemImage: "text.bubble", message: "暂时没有找到这条回复的上下文。")
                .padding(16)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(replies) { reply in
                    CommentDialogRow(
                        reply: reply,
                        isFocused: reply.id == focusReply.id,
                        transitionNamespace: imageTransitionNamespace,
                        showImages: presentImages
                    )
                        .padding(.horizontal, 16)
                    Divider()
                        .padding(.leading, 66)
                }

                if case .failed(let message) = state {
                    CommentErrorView(message: message) {
                        Task { await viewModel.reloadDialog(for: rootComment, reply: focusReply) }
                    }
                    .padding(16)
                }
            }
        }
    }
}

private struct CommentDialogRow: View {
    let reply: Comment
    let isFocused: Bool
    let transitionNamespace: Namespace.ID
    let showImages: ([DynamicImageItem], String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CommentAvatar(urlString: reply.member?.avatar, size: 36)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(reply.member?.uname ?? "Unknown")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if !BiliFormatters.relativeTime(reply.ctime).isEmpty {
                        Text(BiliFormatters.relativeTime(reply.ctime))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Label(BiliFormatters.compactCount(reply.like), systemImage: reply.likeState == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(.caption)
                        .foregroundStyle(reply.likeState == 1 ? .pink : .secondary)
                        .labelStyle(.titleAndIcon)
                }

                BiliEmoteText(content: reply.content, font: .subheadline, textColor: .primary, emoteSize: 22)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                CommentImageButton(
                    images: reply.content?.pictures ?? [],
                    transitionScope: reply.id.description,
                    transitionNamespace: transitionNamespace,
                    showImages: showImages
                )
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, isFocused ? 10 : 0)
        .background(isFocused ? Color.pink.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct CommentAvatar: View {
    let urlString: String?
    let size: CGFloat

    var body: some View {
        let pixelSize = Int(size * 3)
        CachedRemoteImage(
            url: urlString.flatMap { URL(string: $0.biliAvatarThumbnailURL(size: pixelSize)) },
            targetPixelSize: pixelSize
        ) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: size * 0.9))
                .foregroundStyle(.tertiary)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

private struct VideoDescriptionSheet: View {
    @ObservedObject var viewModel: VideoDetailViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VideoTitleText(text: viewModel.detail.title.normalizedDetailTitle)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VideoDescriptionOwnerRow(viewModel: viewModel)

                    Divider()

                    Text(displayDescription)
                        .font(.body)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
            }
            .navigationTitle("视频简介")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var displayDescription: String {
        let text = (viewModel.detail.desc ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "这个视频暂时没有简介。" : text
    }
}

private struct VideoDescriptionOwnerRow: View {
    @ObservedObject var viewModel: VideoDetailViewModel

    var body: some View {
        let owner = viewModel.detail.owner
        let fanCount = viewModel.uploaderFanCount
        let canOpenUploader = (owner?.mid ?? 0) > 0
        let isFollowing = viewModel.interactionState.isFollowing

        HStack(spacing: 10) {
            if let owner, canOpenUploader {
                NavigationLink(value: owner) {
                    ownerIdentity(owner: owner, fanCount: fanCount, showsChevron: true)
                }
                .buttonStyle(.plain)
            } else {
                ownerIdentity(owner: owner, fanCount: fanCount, showsChevron: false)
            }

            Spacer(minLength: 8)

            Button {
                Task { await viewModel.toggleFollow() }
            } label: {
                Text(isFollowing ? "已关注" : "+ 关注")
                    .font(.caption.weight(.bold))
                    .frame(minWidth: 58)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isFollowing ? Color(.tertiarySystemFill) : Color.pink.opacity(0.12))
                    .foregroundStyle(isFollowing ? Color.secondary : Color.pink)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canOpenUploader || viewModel.isMutatingInteraction)
        }
    }

    private func ownerIdentity(owner: VideoOwner?, fanCount: Int?, showsChevron: Bool) -> some View {
        HStack(spacing: 10) {
            CachedRemoteImage(
                url: owner?.face.flatMap { URL(string: $0.biliAvatarThumbnailURL(size: 96)) },
                targetPixelSize: 96
            ) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(owner?.name ?? "Unknown")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("粉丝 \(BiliFormatters.compactCount(fanCount))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct RelatedVideoCard: View {
    let video: VideoItem

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            CachedRemoteImage(
                url: video.pic.flatMap { URL(string: $0.biliCoverThumbnailURL(width: 360, height: 228)) },
                targetPixelSize: 360
            ) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.videoDetailSecondarySurface)
                    .overlay {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.secondary)
                    }
            }
            .frame(width: 168, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(video.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .frame(height: 40, alignment: .topLeading)

            Text(video.owner?.name ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 168, alignment: .topLeading)
        .padding(.bottom, 2)
    }
}

private struct RelatedVideoPlaceholderCard: View {
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.videoDetailSecondarySurface)
                .frame(width: 168, height: 96)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.videoDetailSecondarySurface)
                .frame(width: 152, height: 14)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.videoDetailSecondarySurface)
                .frame(width: 118, height: 14)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.videoDetailSecondarySurface)
                .frame(width: 84, height: 12)
        }
        .frame(width: 168, height: 145, alignment: .topLeading)
        .padding(.bottom, 2)
        .overlay(alignment: .center) {
            if isLoading {
                ProgressView()
                    .controlSize(.regular)
                    .tint(.secondary)
                    .padding(10)
                    .background(.thinMaterial, in: Circle())
                    .accessibilityLabel("正在加载相关推荐")
            }
            }
    }
}

private struct RelatedVideoRetryState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Label("相关推荐加载失败", systemImage: "rectangle.stack.badge.exclamationmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Button {
                retry()
            } label: {
                Label("重新加载", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PlaybackPosterOverlay: View {
    let video: VideoItem
    @ObservedObject var playerViewModel: PlayerStateViewModel
    let dimOpacity: Double
    let showsLoader: Bool

    var body: some View {
        if shouldShowPoster {
            let isFinishing = playerViewModel.loadingProgress >= 0.98
            PlayerLoadingPlaceholder(
                progress: playerViewModel.loadingProgress,
                message: playerViewModel.isBuffering ? "正在缓冲" : "正在加载视频",
                isFinishing: isFinishing
            )
            .background(Color.black.opacity(dimOpacity))
            .compositingGroup()
            .clipped()
            .allowsHitTesting(false)
            .transition(
                .asymmetric(
                    insertion: .opacity,
                    removal: .opacity.animation(.smooth(duration: 0.30))
                )
            )
            .animation(.smooth(duration: 0.30), value: playerViewModel.isPlaybackSurfaceReady)
            .animation(.smooth(duration: 0.18), value: isFinishing)
            .animation(.smooth(duration: 0.20), value: playerViewModel.loadingProgress)
        }
    }

    private var shouldShowPoster: Bool {
        !playerViewModel.isPlaybackSurfaceReady
            && playerViewModel.errorMessage == nil
    }
}

private struct PlayerLoadingPlaceholder: View {
    let progress: Double
    let message: String
    let isFinishing: Bool

    private var normalizedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            Color.black

            VStack(spacing: 14) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.08)
                    .opacity(isFinishing ? 0.0 : 1.0)
                    .scaleEffect(isFinishing ? 0.88 : 1.0)

                VStack(spacing: 8) {
                    Text(message)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.18))
                            Capsule()
                                .fill(Color(red: 1, green: 0.25, blue: 0.50))
                                .frame(width: proxy.size.width * normalizedProgress)
                        }
                    }
                    .frame(width: 148, height: 3)

                    Text("\(Int((normalizedProgress * 100).rounded()))%")
                        .font(.caption2.monospacedDigit().weight(.medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .contentTransition(.numericText())
                }
            }
            .opacity(isFinishing ? 0.74 : 1)
            .scaleEffect(isFinishing ? 0.985 : 1)
            .blur(radius: isFinishing ? 0.4 : 0)
            .animation(.smooth(duration: 0.22), value: isFinishing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
final class VideoDetailViewModelHolder: ObservableObject {
    @Published var viewModel: VideoDetailViewModel?
    private var cancellable: AnyCancellable?
    private var lastSnapshot: VideoDetailRenderSnapshot?

    func configure(
        seedVideo: VideoItem,
        api: BiliAPIClient,
        libraryStore: LibraryStore,
        sponsorBlockService: SponsorBlockService
    ) {
        if viewModel == nil {
            let viewModel = VideoDetailViewModel(
                seedVideo: seedVideo,
                api: api,
                libraryStore: libraryStore,
                sponsorBlockService: sponsorBlockService
            )
            self.viewModel = viewModel
            lastSnapshot = VideoDetailRenderSnapshot(viewModel)
            cancellable = viewModel.objectWillChange.sink { [weak self] _ in
                Task { @MainActor [weak self, weak viewModel] in
                    guard let self, let viewModel else { return }
                    let snapshot = VideoDetailRenderSnapshot(viewModel)
                    guard snapshot != self.lastSnapshot else { return }
                    self.lastSnapshot = snapshot
                    self.objectWillChange.send()
                }
            }
        }
    }
}

private struct VideoDetailRenderSnapshot: Equatable {
    let detail: VideoItem
    let selectedCID: Int?
    let state: LoadingState
    let playURLState: LoadingState
    let playVariants: [PlayVariant]
    let selectedPlayVariant: PlayVariant?
    let isSupplementingPlayQualities: Bool
    let isSwitchingPlayQuality: Bool
    let pendingPlayVariantID: String?
    let interactionState: VideoInteractionState
    let interactionMessage: String?
    let isMutatingInteraction: Bool
    let playbackFallbackMessage: String?
    let related: [VideoItem]
    let relatedState: LoadingState
    let stablePlayerID: ObjectIdentifier?

    init(_ viewModel: VideoDetailViewModel) {
        detail = viewModel.detail
        selectedCID = viewModel.selectedCID
        state = viewModel.state
        playURLState = viewModel.playURLState
        playVariants = viewModel.playVariants
        selectedPlayVariant = viewModel.selectedPlayVariant
        isSupplementingPlayQualities = viewModel.isSupplementingPlayQualities
        isSwitchingPlayQuality = viewModel.isSwitchingPlayQuality
        pendingPlayVariantID = viewModel.pendingPlayVariantID
        interactionState = viewModel.interactionState
        interactionMessage = viewModel.interactionMessage
        isMutatingInteraction = viewModel.isMutatingInteraction
        playbackFallbackMessage = viewModel.playbackFallbackMessage
        related = viewModel.related
        relatedState = viewModel.relatedState
        stablePlayerID = viewModel.stablePlayerViewModel.map(ObjectIdentifier.init)
    }
}
