import SwiftUI
import Combine
import UIKit

struct VideoDetailView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let seedVideo: VideoItem
    private let hidesRootTabBar: Bool

    @StateObject private var holder = VideoDetailViewModelHolder()
    @State private var isShowingDescription = false
    @State private var isShowingPortraitInfoSheet = false
    @State private var isShowingCommentsSheet = false
    @State private var replySheetComment: Comment?
    @State private var nativeTopSafeAreaInset: CGFloat = 0
    @State private var isPortraitPlayerModeEnabled = true
    @State private var introScrollOffset: CGFloat = 0
    @State private var manualLandscapeOrientation: UIDeviceOrientation?
    @State private var isRestoringPortraitFromManualLandscape = false
    @State private var pendingManualLandscapeExitTask: Task<Void, Never>?

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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .nativeTopNavigationChrome()
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .hideRootTabBarWhenNeeded(hidesRootTabBar)
        .overlay(alignment: .topLeading) {
            NativeNavigationBackGestureSupport(
                topSafeAreaInset: $nativeTopSafeAreaInset,
                isPopGestureEnabled: manualLandscapeOrientation == nil
            )
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
        }
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            updateManualLandscapeOrientation(UIDevice.current.orientation)
        }
        .onDisappear {
            pendingManualLandscapeExitTask?.cancel()
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            holder.viewModel?.suspendPlaybackForNavigation()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            updateManualLandscapeOrientation(UIDevice.current.orientation)
        }
    }

    @ViewBuilder
    private func content(_ viewModel: VideoDetailViewModel) -> some View {
        GeometryReader { proxy in
            let sceneIsLandscape = proxy.size.width > proxy.size.height
            let isManualLandscape = manualLandscapeOrientation != nil || isRestoringPortraitFromManualLandscape
            let isLandscape = sceneIsLandscape && !isManualLandscape
            let layoutSize = isManualLandscape
                ? CGSize(width: min(proxy.size.width, proxy.size.height), height: max(proxy.size.width, proxy.size.height))
                : proxy.size
            let statusBarInset = isLandscape ? 0 : max(proxy.safeAreaInsets.top, nativeTopSafeAreaInset, UIApplication.shared.activeWindowSafeAreaTop)
            let isPortraitPlaybackReady = viewModel.supportsPortraitPlayerMode

            Group {
                if isLandscape {
                    playerHero(
                        viewModel,
                        isLandscape: true,
                        playerHeight: proxy.size.height,
                        usesPortraitMode: false,
                        showsPortraitModeToggle: false
                    )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .background(.black)
                        .ignoresSafeArea()
                } else if isPortraitPlaybackReady {
                    portraitPlaybackPage(viewModel, statusBarInset: statusBarInset)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    standardPlaybackPage(
                        viewModel,
                        screenSize: layoutSize,
                        statusBarInset: statusBarInset
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(isLandscape ? Color.black : Color.videoDetailBackground)
            .ignoresSafeArea(.container, edges: (isLandscape || manualLandscapeOrientation != nil) ? .all : .top)
            .background {
                StatusBarStyleBridge(style: .lightContent, isHidden: manualLandscapeOrientation != nil)
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
            .task {
                await viewModel.load()
            }
            .sheet(isPresented: $isShowingDescription) {
                VideoDescriptionSheet(
                    title: viewModel.detail.title,
                    description: viewModel.detail.desc ?? ""
                )
            }
            .sheet(isPresented: $isShowingPortraitInfoSheet) {
                portraitInfoSheet(viewModel)
            }
            .sheet(isPresented: $isShowingCommentsSheet) {
                portraitCommentsSheet(viewModel)
            }
            .sheet(item: $replySheetComment) { comment in
                CommentRepliesSheet(rootComment: comment, viewModel: viewModel)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .statusBar(hidden: manualLandscapeOrientation != nil)
        .persistentSystemOverlays(manualLandscapeOrientation == nil ? .automatic : .hidden)
    }

    private func updateManualLandscapeOrientation(_ orientation: UIDeviceOrientation) {
        switch orientation {
        case .landscapeLeft, .landscapeRight:
            pendingManualLandscapeExitTask?.cancel()
            isRestoringPortraitFromManualLandscape = false
            guard manualLandscapeOrientation != orientation else { return }
            withAnimation(.smooth(duration: 0.22)) {
                manualLandscapeOrientation = orientation
            }
        case .portrait, .portraitUpsideDown:
            guard manualLandscapeOrientation != nil else {
                pendingManualLandscapeExitTask?.cancel()
                return
            }
            pendingManualLandscapeExitTask?.cancel()
            pendingManualLandscapeExitTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 420_000_000)
                guard !Task.isCancelled else { return }
                switch UIDevice.current.orientation {
                case .portrait, .portraitUpsideDown:
                    beginRestoringPortraitFromManualLandscape()
                default:
                    break
                }
            }
        default:
            break
        }
    }

    private func standardPlaybackPage(
        _ viewModel: VideoDetailViewModel,
        screenSize: CGSize,
        statusBarInset: CGFloat
    ) -> some View {
        let standardHeight = screenSize.width * 9 / 16
        let isManualLandscape = manualLandscapeOrientation != nil

        return ZStack(alignment: .top) {
            Color.videoDetailBackground
                .opacity(isManualLandscape ? 0 : 1)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if statusBarInset > 0 {
                    Color.black
                        .frame(height: statusBarInset)
                        .allowsHitTesting(false)
                }

                Color.clear
                    .frame(height: standardHeight)

                detailScrollPage(viewModel)
                    .opacity(isManualLandscape ? 0 : 1)
                    .allowsHitTesting(!isManualLandscape)
            }

            if isManualLandscape {
                Color.black
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            playerHero(
                viewModel,
                isLandscape: false,
                playerHeight: standardHeight,
                usesPortraitMode: false,
                showsPortraitModeToggle: false,
                manualFullscreenOrientation: manualLandscapeOrientation,
                onExitManualFullscreen: exitManualLandscapePlayback
            )
            .frame(maxWidth: .infinity)
            .frame(height: standardHeight)
            .padding(.top, isManualLandscape ? 0 : statusBarInset)
            .zIndex(1)
            .clipped()
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .background(isManualLandscape ? Color.black : Color.videoDetailBackground)
        .ignoresSafeArea(.container, edges: isManualLandscape ? .all : .top)
        .animation(.smooth(duration: 0.28), value: isManualLandscape)
    }

    private func exitManualLandscapePlayback() {
        guard manualLandscapeOrientation != nil else { return }
        pendingManualLandscapeExitTask?.cancel()
        beginRestoringPortraitFromManualLandscape()
    }

    private func beginRestoringPortraitFromManualLandscape() {
        guard manualLandscapeOrientation != nil else { return }
        isRestoringPortraitFromManualLandscape = true
        AppOrientationLock.update(to: .portrait, in: nil)
        UIApplication.shared.requestPortraitGeometryForConnectedScenes()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 360_000_000)
            withAnimation(.smooth(duration: 0.24)) {
                manualLandscapeOrientation = nil
            }
            try? await Task.sleep(nanoseconds: 180_000_000)
            isRestoringPortraitFromManualLandscape = false
        }
    }

    @ViewBuilder
    private func playerHero(
        _ viewModel: VideoDetailViewModel,
        isLandscape: Bool,
        playerHeight: CGFloat,
        usesPortraitMode: Bool,
        showsPortraitModeToggle: Bool,
        manualFullscreenOrientation: UIDeviceOrientation? = nil,
        onExitManualFullscreen: (() -> Void)? = nil
    ) -> some View {
        ZStack {
            if usesPortraitMode {
                cover(viewModel.detail)
                    .frame(maxWidth: .infinity)
                    .frame(height: playerHeight)
                    .overlay(Color.black.opacity(0.58))
            }

            if let playerViewModel = viewModel.stablePlayerViewModel {
                BiliPlayerView(
                    viewModel: playerViewModel,
                    historyVideo: viewModel.detail,
                    historyCID: viewModel.selectedCID,
                    duration: viewModel.detail.duration.map(TimeInterval.init),
                    presentation: isLandscape ? .fullScreen : .embedded,
                    showsNavigationChrome: false,
                    pausesOnDisappear: false,
                    embeddedAspectRatio: usesPortraitMode ? CGFloat(viewModel.selectedVideoAspectRatio) : 16 / 9,
                    manualFullscreenOrientation: manualFullscreenOrientation,
                    onExitManualFullscreen: onExitManualFullscreen
                )
                .frame(maxWidth: .infinity)
                .frame(height: isLandscape ? playerHeight : playerHeight)
                .clipShape(RoundedRectangle(cornerRadius: usesPortraitMode ? 18 : 0, style: .continuous))
                .padding(.horizontal, usesPortraitMode ? 12 : 0)
            } else {
                cover(viewModel.detail)
                    .frame(maxWidth: .infinity)
                    .frame(height: playerHeight)
                    .overlay {
                        LinearGradient(
                            colors: [.black.opacity(0.08), .black.opacity(0.48)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }

                if viewModel.playURLState.isLoading {
                    ProgressView()
                        .tint(.white)
                        .padding(16)
                        .background(.black.opacity(0.38))
                        .clipShape(Circle())
                } else if viewModel.selectedPlayVariant != nil {
                    Label("当前档位暂不可播放", systemImage: "lock.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.48))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
        }
        .background(.black)
        .overlay(alignment: .topLeading) {
            if showsPortraitModeToggle {
                Button {
                    withAnimation(.smooth(duration: 0.24)) {
                        isPortraitPlayerModeEnabled.toggle()
                    }
                } label: {
                    Image(systemName: isPortraitModeToggleOn ? "iphone" : "rectangle")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(.black.opacity(0.38))
                        .foregroundStyle(.white)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
                .padding(.top, 12)
            }
        }
    }

    private var isPortraitModeToggleOn: Bool {
        isPortraitPlayerModeEnabled
    }

    private func playerHeight(
        proxy: GeometryProxy,
        statusBarInset: CGFloat,
        isLandscape: Bool,
        usesPortraitMode: Bool,
        aspectRatio: Double,
        scrollOffset: CGFloat
    ) -> CGFloat {
        if isLandscape {
            return proxy.size.height
        }

        let standardHeight = proxy.size.width * 9 / 16
        guard usesPortraitMode else {
            return standardHeight
        }

        let availableHeight = max(proxy.size.height - statusBarInset, 0)
        let portraitAspect = CGFloat(max(aspectRatio, 0.35))
        let naturalHeight = proxy.size.width / portraitAspect
        let maxPortraitHeight = max(standardHeight, availableHeight * 0.74)
        let minPortraitHeight = max(240, min(standardHeight, availableHeight * 0.32))
        let expandedHeight = min(max(naturalHeight, standardHeight), maxPortraitHeight)
        let collapseRange = max(expandedHeight - minPortraitHeight, 0)
        let collapse = min(max(scrollOffset, 0), collapseRange)
        let stretch = min(max(-scrollOffset, 0) * 0.35, availableHeight * 0.10)
        return max(minPortraitHeight, expandedHeight - collapse + stretch)
    }

    private func playbackLoadingView(_ viewModel: VideoDetailViewModel, statusBarInset: CGFloat) -> some View {
        ZStack {
            cover(viewModel.detail)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
                .overlay(Color.black.opacity(0.72))

            if statusBarInset > 0 {
                Color.black
                    .frame(height: statusBarInset)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
            }

            ProgressView()
                .tint(.white)
                .padding(16)
                .background(.black.opacity(0.38))
                .clipShape(Circle())
        }
        .background(Color.black)
    }

    private func portraitPlaybackPage(_ viewModel: VideoDetailViewModel, statusBarInset: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Color.black
                .ignoresSafeArea()

            if let playerViewModel = viewModel.stablePlayerViewModel {
                BiliPlayerView(
                    viewModel: playerViewModel,
                    historyVideo: viewModel.detail,
                    historyCID: viewModel.selectedCID,
                    duration: viewModel.detail.duration.map(TimeInterval.init),
                    presentation: .fullScreen,
                    showsNavigationChrome: false,
                    showsPlaybackControls: true,
                    pausesOnDisappear: false,
                    controlsAccessory: AnyView(portraitControlAccessory(viewModel, compact: true)),
                    controlsBottomLift: 160,
                    embeddedAspectRatio: CGFloat(viewModel.selectedVideoAspectRatio),
                    manualFullscreenOrientation: manualLandscapeOrientation,
                    onExitManualFullscreen: exitManualLandscapePlayback
                )
                .ignoresSafeArea()
            } else {
                cover(viewModel.detail)
                    .ignoresSafeArea()
                    .overlay(Color.black.opacity(0.42))
                if viewModel.playURLState.isLoading {
                    ProgressView()
                        .tint(.white)
                        .padding(16)
                        .background(.black.opacity(0.38))
                        .clipShape(Circle())
                } else {
                    portraitControlAccessory(viewModel, compact: false)
                }
            }

            if statusBarInset > 0 {
                Color.black
                    .frame(height: statusBarInset)
                    .ignoresSafeArea(.container, edges: .top)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
            }

        }
        .background(Color.black)
        .overlay {
            StatusBarStyleBridge(style: .lightContent, isHidden: manualLandscapeOrientation != nil)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
    }

    private func portraitControlAccessory(
        _ viewModel: VideoDetailViewModel,
        compact: Bool
    ) -> some View {
        GlassEffectContainer(spacing: 20) {
            HStack {
                Button {
                    isShowingPortraitInfoSheet = true
                } label: {
                    PortraitAvatarButton(urlString: viewModel.detail.owner?.face)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("视频简介")

                Spacer()

                Button {
                    isShowingCommentsSheet = true
                } label: {
                    PortraitGlassIconButton(systemImage: "bubble.left.and.bubble.right.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("评论")
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, compact ? 6 : 22)
        .padding(.bottom, compact ? 0 : 160)
    }

    private func portraitInfoSheet(_ viewModel: VideoDetailViewModel) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ownerRow(viewModel)

                    Text(viewModel.detail.title.normalizedDetailTitle)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 12) {
                        Label(BiliFormatters.compactCount(viewModel.detail.stat?.view), systemImage: "play.rectangle")
                        Label(BiliFormatters.publishDate(viewModel.detail.pubdate), systemImage: "calendar")
                        Spacer(minLength: 6)
                        qualityInlineButton(viewModel)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    actionStrip(viewModel)
                    interactionNotice(viewModel)
                    playURLNotice(viewModel)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("视频简介")
                            .font(.headline)

                        Text(displayDescription(for: viewModel.detail))
                            .font(.body)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)

                    episodeSection(viewModel)
                }
                .padding(16)
            }
            .navigationTitle("视频简介")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func displayDescription(for video: VideoItem) -> String {
        let desc = video.desc?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return desc.isEmpty ? video.title.normalizedDetailTitle : desc
    }

    private func portraitCommentsSheet(_ viewModel: VideoDetailViewModel) -> some View {
        PortraitCommentsSheet(viewModel: viewModel)
    }

    private func detailCard(_ viewModel: VideoDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ownerRow(viewModel)
            titleBlock(viewModel)
            actionStrip(viewModel)
            interactionNotice(viewModel)
            playURLNotice(viewModel)
        }
        .padding(14)
        .background(Color.videoDetailSurface)
    }

    private func titleBlock(_ viewModel: VideoDetailViewModel) -> some View {
        let video = viewModel.detail

        return VStack(alignment: .leading, spacing: 8) {
            VideoTitleText(text: video.title.normalizedDetailTitle)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 9) {
                Label(BiliFormatters.compactCount(video.stat?.view), systemImage: "play.rectangle")
                    .frame(height: 28)
                Label(BiliFormatters.publishDate(video.pubdate), systemImage: "calendar")
                    .frame(height: 28)

                Spacer(minLength: 2)

                descriptionInlineButton(video.desc)
                qualityInlineButton(viewModel)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
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

    private func descriptionInlineButton(_ desc: String?) -> some View {
        Button {
            isShowingDescription = true
        } label: {
            InlineMetadataButtonLabel(title: "简介", systemImage: "text.alignleft")
        }
        .buttonStyle(.plain)
        .disabled(desc?.isEmpty != false)
        .opacity(desc?.isEmpty == false ? 1 : 0.45)
    }

    @ViewBuilder
    private func qualityInlineButton(_ viewModel: VideoDetailViewModel) -> some View {
        if !viewModel.playVariants.isEmpty {
            Menu {
                ForEach(viewModel.playVariants) { variant in
                    Button {
                        viewModel.selectPlayVariant(variant)
                    } label: {
                        Label(
                            variant.title,
                            systemImage: viewModel.selectedPlayVariant == variant ? "checkmark" : (variant.isPlayable ? "circle" : "lock.fill")
                        )
                    }
                    .disabled(!variant.isPlayable)
                }
            } label: {
                InlineMetadataButtonLabel(title: viewModel.selectedPlayVariant?.title ?? "清晰度", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.plain)
        } else {
            InlineMetadataButtonLabel(title: "清晰度", systemImage: "slider.horizontal.3")
                .opacity(0.45)
        }
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
            VStack(alignment: .leading, spacing: 10) {
                scrollOffsetReader()
                detailCard(viewModel)
                episodeSection(viewModel)
                relatedSection(viewModel.related)
                commentsSection(viewModel, maxVisibleComments: 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 20)
            .contentTransition(.opacity)
        }
        .coordinateSpace(name: detailScrollSpaceName)
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
            updatePortraitScrollOffset(offset)
        }
        .background(NativeContentPopGestureDependency())
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
        AsyncImage(url: video.pic.flatMap { URL(string: $0.biliCoverThumbnailURL(width: 960, height: 540)) }) { image in
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

    @ViewBuilder
    private func ownerRow(_ viewModel: VideoDetailViewModel) -> some View {
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
            AsyncImage(url: owner?.face.flatMap { URL(string: $0.biliAvatarThumbnailURL(size: 96)) }) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 36, height: 36)
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
        maxVisibleComments: Int? = nil
    ) -> some View {
        CommentsSectionView(
            viewModel: viewModel,
            style: style,
            maxVisibleComments: maxVisibleComments,
            showAllComments: {
                isShowingCommentsSheet = true
            }
        ) { comment in
            replySheetComment = comment
        }
    }

    private func relatedSection(_ videos: [VideoItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("相关推荐")
                .font(.headline)
                .padding(.horizontal, 14)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(videos.prefix(5)) { video in
                        VideoRouteLink(video) {
                            RelatedVideoCard(video: video)
                        }
                    }
                }
            }
            .contentMargins(.horizontal, 14, for: .scrollContent)
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .background(Color.videoDetailSurface)
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

private extension UIApplication {
    var activeWindowSafeAreaTop: CGFloat {
        let windowTop = connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.top }
            .first ?? 0
        let statusBarTop = connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.statusBarManager?.statusBarFrame.height }
            .first ?? 0

        return max(windowTop, statusBarTop, inferredPortraitStatusBarHeight)
    }

    private var inferredPortraitStatusBarHeight: CGFloat {
        let bounds = connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.bounds }
            .first ?? .zero
        let shortSide = min(bounds.width, bounds.height)
        let longSide = max(bounds.width, bounds.height)

        guard shortSide >= 375 else { return 20 }
        if longSide >= 852 {
            return 62
        }
        if longSide >= 812 {
            return 47
        }
        return 20
    }

    func requestPortraitGeometryForConnectedScenes() {
        if #available(iOS 16.0, *) {
            connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .forEach { scene in
                    scene.requestGeometryUpdate(
                        UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .portrait)
                    ) { _ in }
                }
        }
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? {
        windows.first { $0.isKeyWindow }
    }
}

private extension String {
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

private struct NativeNavigationBackGestureSupport: UIViewControllerRepresentable {
    @Binding var topSafeAreaInset: CGFloat
    let isPopGestureEnabled: Bool

    func makeUIViewController(context _: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context _: Context) {
        uiViewController.onTopSafeAreaInsetChange = { topSafeAreaInset = $0 }
        uiViewController.isPopGestureEnabled = isPopGestureEnabled
        uiViewController.refreshGestures()
    }

    final class Controller: UIViewController {
        private var previousTintColor: UIColor?
        private var previousNavigationBarUserInteractionEnabled: Bool?
        private var previousStandardAppearance: UINavigationBarAppearance?
        private var previousScrollEdgeAppearance: UINavigationBarAppearance?
        private var previousCompactAppearance: UINavigationBarAppearance?
        private var previousBackIndicatorImage: UIImage?
        private var previousBackIndicatorTransitionMaskImage: UIImage?
        private var previousBarStyle: UIBarStyle?
        private var didCaptureNavigationChrome = false
        private let hiddenNavigationControls = NSHashTable<UIView>.weakObjects()
        var onTopSafeAreaInsetChange: ((CGFloat) -> Void)?
        var isPopGestureEnabled = true

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            refreshGestures()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            refreshGestures()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            restoreNavigationChrome()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            refreshGestures()
        }

        func refreshGestures() {
            guard let navigationController else { return }
            applyNavigationChrome(to: navigationController)
            updateTopSafeAreaInset()

            let canPop = navigationController.viewControllers.count > 1
            navigationController.interactivePopGestureRecognizer?.isEnabled = canPop && isPopGestureEnabled

            if #available(iOS 26.0, *) {
                navigationController.interactiveContentPopGestureRecognizer?.isEnabled = canPop && isPopGestureEnabled
            }
        }

        private func applyNavigationChrome(to navigationController: UINavigationController) {
            if !didCaptureNavigationChrome {
                let navigationBar = navigationController.navigationBar
                previousTintColor = navigationBar.tintColor
                previousNavigationBarUserInteractionEnabled = navigationBar.isUserInteractionEnabled
                previousStandardAppearance = navigationBar.standardAppearance
                previousScrollEdgeAppearance = navigationBar.scrollEdgeAppearance
                previousCompactAppearance = navigationBar.compactAppearance
                previousBackIndicatorImage = navigationBar.backIndicatorImage
                previousBackIndicatorTransitionMaskImage = navigationBar.backIndicatorTransitionMaskImage
                previousBarStyle = navigationBar.barStyle
                didCaptureNavigationChrome = true
            }

            let appearance = UINavigationBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.titleTextAttributes = [.foregroundColor: UIColor.clear]
            appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.clear]
            appearance.setBackIndicatorImage(Self.clearImage, transitionMaskImage: Self.clearImage)

            let buttonAppearance = UIBarButtonItemAppearance(style: .plain)
            [buttonAppearance.normal, buttonAppearance.highlighted, buttonAppearance.disabled, buttonAppearance.focused].forEach { state in
                state.titleTextAttributes = [.foregroundColor: UIColor.clear]
                state.backgroundImage = Self.clearImage
            }
            appearance.buttonAppearance = buttonAppearance
            appearance.backButtonAppearance = buttonAppearance

            let navigationBar = navigationController.navigationBar
            navigationBar.barStyle = .black
            navigationBar.tintColor = .clear
            navigationBar.backIndicatorImage = Self.clearImage
            navigationBar.backIndicatorTransitionMaskImage = Self.clearImage
            navigationBar.standardAppearance = appearance
            navigationBar.scrollEdgeAppearance = appearance
            navigationBar.compactAppearance = appearance
            hideLeadingNavigationControls(in: navigationBar)
            DispatchQueue.main.async { [weak navigationBar] in
                guard let navigationBar else { return }
                self.hideLeadingNavigationControls(in: navigationBar)
            }
        }

        private func restoreNavigationChrome() {
            guard didCaptureNavigationChrome else { return }
            hiddenNavigationControls.allObjects.forEach {
                $0.alpha = 1
                $0.isUserInteractionEnabled = true
            }
            hiddenNavigationControls.removeAllObjects()
            if let navigationBar = navigationController?.navigationBar {
                navigationBar.tintColor = previousTintColor
                navigationBar.standardAppearance = previousStandardAppearance ?? UINavigationBarAppearance()
                navigationBar.scrollEdgeAppearance = previousScrollEdgeAppearance
                navigationBar.compactAppearance = previousCompactAppearance
                navigationBar.backIndicatorImage = previousBackIndicatorImage
                navigationBar.backIndicatorTransitionMaskImage = previousBackIndicatorTransitionMaskImage
                navigationBar.barStyle = previousBarStyle ?? .default
                navigationBar.isUserInteractionEnabled = previousNavigationBarUserInteractionEnabled ?? true
            }
            didCaptureNavigationChrome = false
            previousTintColor = nil
            previousNavigationBarUserInteractionEnabled = nil
            previousStandardAppearance = nil
            previousScrollEdgeAppearance = nil
            previousCompactAppearance = nil
            previousBackIndicatorImage = nil
            previousBackIndicatorTransitionMaskImage = nil
            previousBarStyle = nil
        }

        private func updateTopSafeAreaInset() {
            let window = view.window ?? navigationController?.view.window
            let windowTop = window?.safeAreaInsets.top ?? 0
            let statusBarTop = window?.windowScene?.statusBarManager?.statusBarFrame.height ?? 0
            let inset = max(windowTop, statusBarTop)

            DispatchQueue.main.async { [weak self] in
                self?.onTopSafeAreaInsetChange?(inset)
            }
        }

        private static let clearImage: UIImage = {
            UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
        }()

        private func hideLeadingNavigationControls(in navigationBar: UINavigationBar) {
            navigationBar.layoutIfNeeded()
            hideLeadingButtonLikeSubviews(in: navigationBar, navigationBar: navigationBar)
        }

        private func hideLeadingButtonLikeSubviews(in view: UIView, navigationBar: UINavigationBar) {
            for subview in view.subviews {
                let frame = subview.convert(subview.bounds, to: navigationBar)
                let typeName = String(describing: type(of: subview))
                let isLeadingChrome = frame.minX < 116 && frame.maxX > 0 && frame.midY > 0
                let isCompactChrome = frame.width < 140 && frame.height < 100
                let isBarBackground = typeName.localizedCaseInsensitiveContains("barbackground")

                if isLeadingChrome && isCompactChrome && !isBarBackground {
                    subview.alpha = 0
                    subview.isUserInteractionEnabled = false
                    hiddenNavigationControls.add(subview)
                }

                hideLeadingButtonLikeSubviews(in: subview, navigationBar: navigationBar)
            }
        }
    }
}

private struct NativeContentPopGestureDependency: UIViewRepresentable {
    func makeUIView(context _: Context) -> DependencyView {
        DependencyView()
    }

    func updateUIView(_ uiView: DependencyView, context _: Context) {
        uiView.refreshGestureDependencies()
    }

    final class DependencyView: UIView {
        private weak var attachedNavigationController: UINavigationController?
        private weak var attachedScrollView: UIScrollView?
        private weak var attachedPopGesture: UIGestureRecognizer?
        private weak var attachedContentPopGesture: UIGestureRecognizer?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            refreshGestureDependencies()
        }

        func refreshGestureDependencies() {
            guard let navigationController = enclosingNavigationController(),
                  let scrollView = enclosingScrollView() else {
                return
            }

            attachedNavigationController = navigationController
            attachedScrollView = scrollView

            if let popGesture = navigationController.interactivePopGestureRecognizer,
               attachedPopGesture !== popGesture {
                scrollView.panGestureRecognizer.require(toFail: popGesture)
                attachedPopGesture = popGesture
            }

            if #available(iOS 26.0, *),
               let contentPopGesture = navigationController.interactiveContentPopGestureRecognizer,
               attachedContentPopGesture !== contentPopGesture {
                scrollView.panGestureRecognizer.require(toFail: contentPopGesture)
                attachedContentPopGesture = contentPopGesture
            }
        }

        private func enclosingNavigationController() -> UINavigationController? {
            var responder: UIResponder? = self
            while let current = responder {
                if let viewController = current as? UIViewController,
                   let navigationController = viewController.navigationController {
                    return navigationController
                }
                responder = current.next
            }
            return nil
        }

        private func enclosingScrollView() -> UIScrollView? {
            var current = superview
            while let view = current {
                if let scrollView = view as? UIScrollView {
                    return scrollView
                }
                current = view.superview
            }
            return nil
        }
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
        .background(.regularMaterial)
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color(.separator).opacity(0.18), lineWidth: 0.7)
        }
        .clipShape(Capsule(style: .continuous))
    }
}

private struct PortraitAvatarButton: View {
    let urlString: String?

    var body: some View {
        ZStack {
            Circle()
                .fill(.clear)

            AsyncImage(url: urlString.flatMap { URL(string: $0.biliAvatarThumbnailURL(size: 120)) }) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 50, height: 50)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.64), lineWidth: 1.4)
            }
        }
        .frame(width: 58, height: 58)
        .contentShape(Circle())
        .glassEffect(.regular.tint(.white.opacity(0.18)).interactive(), in: Circle())
        .shadow(color: .black.opacity(0.28), radius: 12, y: 5)
    }
}

private struct PortraitGlassIconButton: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 58, height: 58)
            .contentShape(Circle())
            .glassEffect(.regular.tint(.white.opacity(0.18)).interactive(), in: Circle())
            .shadow(color: .black.opacity(0.28), radius: 12, y: 5)
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

    var body: some View {
        NavigationStack {
            ScrollView {
                CommentsSectionView(viewModel: viewModel, style: .plain) { comment in
                    replySheetComment = comment
                }
                .padding(.vertical, 8)
            }
            .background(Color.videoDetailBackground)
            .navigationTitle("评论")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.fraction(0.7)])
        .presentationDragIndicator(.visible)
        .sheet(item: $replySheetComment) { comment in
            CommentRepliesSheet(rootComment: comment, viewModel: viewModel)
        }
    }
}

private struct CommentsSectionView: View {
    @ObservedObject var viewModel: VideoDetailViewModel
    let style: CommentSectionStyle
    var maxVisibleComments: Int?
    var showAllComments: (() -> Void)?
    let showReplies: (Comment) -> Void
    @State private var imageSelection: CommentImageSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            commentsHeader
            commentsContent
        }
        .padding(.vertical, 14)
        .background(style == .grouped ? Color.videoDetailSurface : Color.clear)
        .fullScreenCover(item: $imageSelection) { selection in
            CommentImageViewer(images: selection.images, initialIndex: selection.initialIndex)
        }
    }

    private func presentImages(_ images: [DynamicImageItem]) {
        let visibleImages = images.filter { $0.normalizedURL != nil }
        guard !visibleImages.isEmpty else { return }
        imageSelection = CommentImageSelection(images: visibleImages, initialIndex: 0)
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
        if viewModel.comments.isEmpty && viewModel.commentState.isLoading {
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
        } else if viewModel.comments.isEmpty {
            EmptyStateView(title: "暂无评论", systemImage: "bubble.left", message: "评论加载后会显示在这里。")
                .padding(.horizontal, style.horizontalPadding)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(visibleComments) { comment in
                    CommentRow(
                        comment: comment,
                        style: style,
                        showReplies: {
                            showReplies(comment)
                        },
                        showImages: presentImages
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
    let showReplies: () -> Void
    let showImages: ([DynamicImageItem]) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            avatar

            VStack(alignment: .leading, spacing: 8) {
                header

                BiliEmoteText(content: comment.content, font: .subheadline, textColor: .primary, emoteSize: 22)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                CommentImageButton(images: comment.content?.pictures ?? [], showImages: showImages)

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
        AsyncImage(url: comment.member?.avatar.flatMap { URL(string: $0.biliAvatarThumbnailURL(size: 96)) }) { image in
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
    let showImages: ([DynamicImageItem]) -> Void

    private var visibleImages: [DynamicImageItem] {
        images.filter { $0.normalizedURL != nil }
    }

    var body: some View {
        if !visibleImages.isEmpty {
            Button {
                showImages(visibleImages)
            } label: {
                Label(title, systemImage: "photo.on.rectangle.angled")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.videoDetailSecondarySurface)
                    .foregroundStyle(.pink)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
    }

    private var title: String {
        visibleImages.count > 1 ? "点击查看图片 \(visibleImages.count) 张" : "点击查看图片"
    }
}

private struct CommentImageSelection: Identifiable {
    let id = UUID()
    let images: [DynamicImageItem]
    let initialIndex: Int
}

private struct CommentImageViewer: View {
    let images: [DynamicImageItem]
    let initialIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int
    @State private var dragOffset: CGSize = .zero
    @State private var isPresented = false
    @State private var isClosing = false

    init(images: [DynamicImageItem], initialIndex: Int) {
        self.images = images
        self.initialIndex = initialIndex
        _selection = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                    CommentViewerImage(image: image) {
                        close()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .automatic : .never))
            .offset(y: dragOffset.height)
            .scaleEffect(viewerScale * presentationScale)
            .opacity(presentationOpacity)

            if images.count > 1 {
                Text("\(selection + 1) / \(images.count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.44))
                    .clipShape(Capsule())
                    .padding(.bottom, 22)
                    .opacity(1 - dismissProgress)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(dragToDismissGesture)
        .animation(.smooth(duration: 0.2), value: isPresented)
        .animation(.smooth(duration: 0.16), value: isClosing)
        .animation(.interactiveSpring(duration: 0.24, extraBounce: 0.08), value: dragOffset)
        .onAppear {
            isPresented = true
        }
        .preferredColorScheme(.dark)
    }

    private var dismissProgress: CGFloat {
        min(abs(dragOffset.height) / 260, 1)
    }

    private var backgroundOpacity: Double {
        Double(presentationOpacity) * Double(1 - dismissProgress * 0.72)
    }

    private var viewerScale: CGFloat {
        1 - dismissProgress * 0.08
    }

    private var presentationOpacity: CGFloat {
        isClosing ? 0 : (isPresented ? 1 : 0)
    }

    private var presentationScale: CGFloat {
        isClosing ? 0.96 : (isPresented ? 1 : 0.96)
    }

    private func close() {
        guard !isClosing else { return }
        withAnimation(.smooth(duration: 0.16)) {
            isClosing = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            dismiss()
        }
    }

    private var dragToDismissGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                let vertical = abs(value.translation.height)
                let horizontal = abs(value.translation.width)
                guard vertical > horizontal * 1.1 else {
                    if dragOffset != .zero {
                        dragOffset = .zero
                    }
                    return
                }
                dragOffset = value.translation
            }
            .onEnded { value in
                let vertical = abs(value.translation.height)
                let horizontal = abs(value.translation.width)
                let predictedVertical = abs(value.predictedEndTranslation.height)
                let shouldDismiss = vertical > horizontal * 1.1
                    && (vertical > 150 || predictedVertical > 260)

                if shouldDismiss {
                    close()
                } else {
                    withAnimation(.interactiveSpring(duration: 0.26, extraBounce: 0.1)) {
                        dragOffset = .zero
                    }
                }
            }
    }
}

private struct CommentViewerImage: View {
    let image: DynamicImageItem
    let close: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let imageWidth = proxy.size.width
            let imageHeight = max(imageWidth / CGFloat(max(image.aspectRatio, 0.1)), 1)
            let verticalInset = max((proxy.size.height - imageHeight) / 2, 0)

            ScrollView(.vertical) {
                imageContent(width: imageWidth, height: imageHeight)
                    .padding(.top, verticalInset)
                    .padding(.bottom, verticalInset)
            }
            .scrollIndicators(.hidden)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    @ViewBuilder
    private func imageContent(width: CGFloat, height: CGFloat) -> some View {
        AsyncImage(url: image.normalizedURL.flatMap(URL.init(string:))) { phase in
            switch phase {
            case .success(let loadedImage):
                loadedImage
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: close)
            case .failure:
                VStack(spacing: 10) {
                    Image(systemName: "photo")
                        .font(.title2)
                    Text("图片加载失败")
                        .font(.footnote)
                }
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: width, height: max(height, 220))
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
            case .empty:
                ProgressView()
                    .tint(.white)
                    .frame(width: width, height: max(height, 220))
            @unknown default:
                Color.clear
                    .frame(width: width, height: height)
            }
        }
    }
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CommentReplyRootView(comment: rootComment, showImages: presentImages)
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
            CommentImageViewer(images: selection.images, initialIndex: selection.initialIndex)
        }
    }

    private func presentImages(_ images: [DynamicImageItem]) {
        let visibleImages = images.filter { $0.normalizedURL != nil }
        guard !visibleImages.isEmpty else { return }
        imageSelection = CommentImageSelection(images: visibleImages, initialIndex: 0)
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
    let showImages: ([DynamicImageItem]) -> Void

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

                CommentImageButton(images: comment.content?.pictures ?? [], showImages: showImages)
            }
        }
    }
}

private struct CommentReplyDetailRow: View {
    let reply: Comment
    let showDialog: (() -> Void)?
    let showImages: ([DynamicImageItem]) -> Void

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

                CommentImageButton(images: reply.content?.pictures ?? [], showImages: showImages)

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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CommentReplyRootView(comment: rootComment, showImages: presentImages)
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
            CommentImageViewer(images: selection.images, initialIndex: selection.initialIndex)
        }
    }

    private func presentImages(_ images: [DynamicImageItem]) {
        let visibleImages = images.filter { $0.normalizedURL != nil }
        guard !visibleImages.isEmpty else { return }
        imageSelection = CommentImageSelection(images: visibleImages, initialIndex: 0)
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
    let showImages: ([DynamicImageItem]) -> Void

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

                CommentImageButton(images: reply.content?.pictures ?? [], showImages: showImages)
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
        AsyncImage(url: urlString.flatMap { URL(string: $0.biliAvatarThumbnailURL(size: Int(size * 3))) }) { image in
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
    let title: String
    let description: String

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(displayDescription)
                    .font(.body)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .navigationTitle("视频简介")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var displayDescription: String {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? title : text
    }
}

private struct RelatedVideoCard: View {
    let video: VideoItem

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            AsyncImage(url: video.pic.flatMap { URL(string: $0.biliCoverThumbnailURL(width: 360, height: 228)) }) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.gray.opacity(0.14)
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

@MainActor
final class VideoDetailViewModelHolder: ObservableObject {
    @Published var viewModel: VideoDetailViewModel?
    private var cancellable: AnyCancellable?

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
            cancellable = viewModel.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
    }
}
