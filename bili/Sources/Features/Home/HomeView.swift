import SwiftUI
import Combine

private enum HomePullRefreshCoordinateSpace {
    static let name = "homePullRefreshScroll"
    static let distanceStep: CGFloat = 10

    static func quantizedPullDistance(_ distance: CGFloat) -> CGFloat {
        let normalized = max(0, distance)
        guard normalized > 0 else { return 0 }
        return (normalized / distanceStep).rounded(.down) * distanceStep
    }
}

private struct HomePullRefreshDistancePreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct HomeFeedWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct HomeView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @StateObject private var runtimeSettings = HomeRuntimeSettingsStore()
    @ObservedObject private var viewModel: HomeViewModel
    let autoOpenDetail: Bool
    let startVideo: VideoItem?
    @Binding var detailPath: NavigationPath
    let onVideoSelect: ((VideoItem) -> Void)?
    @State private var didAutoOpenDetail = false
    @State private var didTriggerConfiguredPullRefresh = false
    @State private var feedContainerWidth: CGFloat = 0

    private let doubleColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]
    private let singleColumns = [
        GridItem(.flexible(minimum: 0), spacing: 0)
    ]
    private let singleColumnHorizontalPadding: CGFloat = 12
    @State private var preloadCoordinator = HomeFeedPreloadCoordinator()

    init(
        viewModel: HomeViewModel,
        autoOpenDetail: Bool,
        startVideo: VideoItem?,
        detailPath: Binding<NavigationPath>,
        onVideoSelect: ((VideoItem) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.autoOpenDetail = autoOpenDetail
        self.startVideo = startVideo
        _detailPath = detailPath
        self.onVideoSelect = onVideoSelect
    }

    var body: some View {
        content(viewModel)
        .navigationTitle("首页")
        .navigationBarTitleDisplayMode(.inline)
        .nativeTopNavigationChrome()
    }

    @ViewBuilder
    private func content(_ viewModel: HomeViewModel) -> some View {
        videoFeed(viewModel)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .task {
            runtimeSettings.bind(dependencies.libraryStore)
            Task(priority: .utility) {
                await dependencies.api.prewarmPlaybackSigningKeys()
            }
            await viewModel.loadInitial()
            openFirstDetailIfNeeded(viewModel)
        }
        .onChange(of: viewModel.videos.first?.id) { _, _ in
            openFirstDetailIfNeeded(viewModel)
        }
    }

    private func feedPickerRow(_ viewModel: HomeViewModel) -> some View {
        Picker(
            "首页内容",
            selection: Binding(
                get: { viewModel.mode },
                set: { newMode in
                    Task { await viewModel.switchMode(newMode) }
                }
            )
        ) {
            ForEach(HomeFeedMode.allCases, id: \.self) { mode in
                Text(mode.title)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func videoFeed(_ viewModel: HomeViewModel) -> some View {
        ScrollView {
            homePullRefreshOffsetReader
            homeFeedWidthReader

            VStack(spacing: 6) {
                feedPickerRow(viewModel)

                if viewModel.videos.isEmpty && (viewModel.state == .idle || viewModel.state.isLoading) {
                    initialFeedSkeleton
                } else if viewModel.videos.isEmpty {
                    EmptyStateView(
                        title: "暂无内容",
                        systemImage: "play.rectangle",
                        message: "下拉刷新或切换频道再试。"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 120)
                } else {
                    feedContent(viewModel)
                }
            }
            .padding(.top, 2)
            .padding(.bottom, 18)
        }
        .coordinateSpace(name: HomePullRefreshCoordinateSpace.name)
        .rootFloatingTabBarContentPadding()
        .onPreferenceChange(HomeFeedWidthPreferenceKey.self) { width in
            let roundedWidth = width.rounded(.down)
            guard abs(roundedWidth - feedContainerWidth) > 0.5 else { return }
            feedContainerWidth = roundedWidth
        }
        .onPreferenceChange(HomePullRefreshDistancePreferenceKey.self) { pullDistance in
            handleConfiguredPullRefresh(pullDistance: pullDistance, viewModel: viewModel)
        }
        .scrollBounceBehavior(.always, axes: .vertical)
        .background(Color(.systemBackground))
        .nativeTopScrollEdgeEffect()
        .animation(.smooth(duration: 0.24), value: runtimeSettings.homeFeedLayout)
        .overlay {
            if case .failed(let message) = viewModel.state, viewModel.videos.isEmpty {
                ErrorStateView(title: "加载失败", message: message) {
                    Task { await viewModel.refresh() }
                }
            }
        }
        .overlay(alignment: .top) {
            if viewModel.isUserRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
    }

    private var homePullRefreshOffsetReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: HomePullRefreshDistancePreferenceKey.self,
                value: HomePullRefreshCoordinateSpace.quantizedPullDistance(
                    proxy.frame(in: .named(HomePullRefreshCoordinateSpace.name)).minY
                )
            )
        }
        .frame(height: 0)
    }

    private var homeFeedWidthReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: HomeFeedWidthPreferenceKey.self, value: proxy.size.width)
        }
        .frame(height: 0)
    }

    private func handleConfiguredPullRefresh(
        pullDistance: CGFloat,
        viewModel: HomeViewModel
    ) {
        let triggerDistance = CGFloat(runtimeSettings.homeRefreshTriggerDistance)
        if pullDistance < max(12, triggerDistance * 0.32) {
            didTriggerConfiguredPullRefresh = false
            return
        }
        guard pullDistance >= triggerDistance,
              !didTriggerConfiguredPullRefresh,
              !viewModel.isRefreshing
        else { return }
        didTriggerConfiguredPullRefresh = true
        Haptics.medium()
        Task {
            await viewModel.refreshFromUserPull()
            if viewModel.state == .loaded {
                Haptics.success()
            }
        }
    }

    private var feedColumns: [GridItem] {
        runtimeSettings.homeFeedLayout == .doubleColumn ? doubleColumns : singleColumns
    }

    private var feedSpacing: CGFloat {
        switch runtimeSettings.homeFeedLayout {
        case .singleColumn:
            return 0
        case .doubleColumn:
            return 22
        }
    }

    private var feedHorizontalPadding: CGFloat {
        switch runtimeSettings.homeFeedLayout {
        case .singleColumn:
            return 0
        case .doubleColumn:
            return 16
        }
    }

    private var singleColumnFixedCoverSize: CGSize? {
        let width = feedContainerWidth - singleColumnHorizontalPadding * 2
        guard width > 0 else { return nil }
        return CGSize(width: width, height: width * 9 / 16)
    }

    private var doubleColumnFixedCoverSize: CGSize? {
        let width = (feedContainerWidth - (feedHorizontalPadding * 2) - 14) / 2
        guard width > 0 else { return nil }
        return CGSize(width: width, height: width * 9 / 16)
    }

    @ViewBuilder
    private var initialFeedSkeleton: some View {
        if runtimeSettings.homeFeedLayout == .doubleColumn {
            LazyVGrid(columns: doubleColumns, spacing: feedSpacing) {
                ForEach(0..<6, id: \.self) { _ in
                    VideoFeedSkeletonCard(style: .grid)
                }
            }
            .padding(.horizontal, feedHorizontalPadding)
            .padding(.top, 2)
            .allowsHitTesting(false)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { _ in
                    VideoFeedSkeletonCard(style: .singleColumn)
                }
            }
            .padding(.horizontal, singleColumnHorizontalPadding)
            .padding(.top, 2)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func feedContent(_ viewModel: HomeViewModel) -> some View {
        let cells = viewModel.videoCells
        let isLoadingMore = viewModel.state.isLoading && !viewModel.isRefreshing
        let loadMoreTriggerCellID = cells.last?.id
        if runtimeSettings.homeFeedLayout != .doubleColumn {
            LazyVStack(spacing: 0) {
                ForEach(cells) { cell in
                    VStack(spacing: 0) {
                        videoCard(cell.video, display: cell.display)
                            .padding(.top, 9)
                            .padding(.bottom, 14)
                            .onAppear {
                                registerVisiblePreloadCandidate(cell.video)
                            }
                            .onDisappear {
                                unregisterVisiblePreloadCandidate(cell.video)
                            }
                            .homeLoadMoreTask(if: cell.id == loadMoreTriggerCellID, id: cell.id) {
                                await viewModel.loadMoreIfNeeded(current: cell.video)
                            }
                    }
                }

                if isLoadingMore {
                    VideoFeedSkeletonCard(style: .singleColumn)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, singleColumnHorizontalPadding)
            .padding(.top, 0)
            .padding(.bottom, 18)
        } else {
            LazyVGrid(columns: feedColumns, spacing: feedSpacing) {
                ForEach(cells) { cell in
                    videoCard(cell.video, display: cell.display)
                        .onAppear {
                            registerVisiblePreloadCandidate(cell.video)
                        }
                        .onDisappear {
                            unregisterVisiblePreloadCandidate(cell.video)
                        }
                        .homeLoadMoreTask(if: cell.id == loadMoreTriggerCellID, id: cell.id) {
                            await viewModel.loadMoreIfNeeded(current: cell.video)
                        }
                }

                if isLoadingMore {
                    ForEach(0..<2, id: \.self) { _ in
                        VideoFeedSkeletonCard(style: .grid)
                            .allowsHitTesting(false)
                    }
                    Color.clear
                        .frame(height: 1)
                        .gridCellColumns(feedColumns.count)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, feedHorizontalPadding)
        }
    }

    @ViewBuilder
    private func videoCard(_ video: VideoItem, display: VideoCardDisplayModel) -> some View {
        if let onVideoSelect {
            Button {
                onVideoSelect(video)
            } label: {
                cardContent(display)
            }
            .buttonStyle(.plain)
            .buttonStyle(PressPreloadButtonStyle {
                beginPressedPreloadIfNeeded(for: video)
            })
        } else {
            Button {
                detailPath.append(video)
            } label: {
                cardContent(display)
            }
            .buttonStyle(PressPreloadButtonStyle {
                beginPressedPreloadIfNeeded(for: video)
            })
        }
    }

    @ViewBuilder
    private func cardContent(_ display: VideoCardDisplayModel) -> some View {
        switch runtimeSettings.homeFeedLayout {
        case .singleColumn:
            YouTubeStyleVideoFeedCardView(
                display: display,
                fixedCoverAspectRatio: 16 / 9,
                fixedCoverSize: singleColumnFixedCoverSize
            )
                .equatable()
        case .doubleColumn:
            VideoCardView(
                display: display,
                showsPublishTimeInAuthorRow: true,
                surfaceStyle: .blended,
                fixedCoverSize: doubleColumnFixedCoverSize
            )
                .equatable()
        }
    }

    private func beginPressedPreloadIfNeeded(for video: VideoItem) {
        preloadCoordinator.beginPressedPreloadIfNeeded(
            for: video,
            api: dependencies.api,
            preferredQuality: dependencies.libraryStore.preferredVideoQuality,
            cdnPreference: dependencies.libraryStore.effectivePlaybackCDNPreference,
            playbackAdaptationProfile: PlayerPerformanceStore.shared.playbackAdaptationProfile(
                for: video.bvid,
                isEnabled: dependencies.libraryStore.isPlaybackAutoOptimizationEnabled
            )
        )
    }

    private func registerVisiblePreloadCandidate(_ video: VideoItem) {
        preloadCoordinator.registerVisiblePreloadCandidate(
            video,
            api: dependencies.api,
            preferredQuality: dependencies.libraryStore.preferredVideoQuality,
            cdnPreference: dependencies.libraryStore.effectivePlaybackCDNPreference,
            playbackAdaptationProfile: PlayerPerformanceStore.shared.playbackAdaptationProfile(
                isEnabled: dependencies.libraryStore.isPlaybackAutoOptimizationEnabled
            )
        )
    }

    private func unregisterVisiblePreloadCandidate(_ video: VideoItem) {
        preloadCoordinator.unregisterVisiblePreloadCandidate(video)
    }

    private func openFirstDetailIfNeeded(_ viewModel: HomeViewModel) {
        guard autoOpenDetail,
              !didAutoOpenDetail,
              detailPath.isEmpty else {
            return
        }

        let video = startVideo ?? viewModel.videos.first
        guard let video else { return }
        didAutoOpenDetail = true
        if let onVideoSelect {
            onVideoSelect(video)
        } else {
            detailPath.append(video)
        }
    }
}

private extension View {
    @ViewBuilder
    func homeLoadMoreTask(
        if shouldAttachTask: Bool,
        id: String,
        action: @escaping () async -> Void
    ) -> some View {
        if shouldAttachTask {
            task(id: id) {
                await action()
            }
        } else {
            self
        }
    }
}

@MainActor
private final class HomeFeedPreloadCoordinator {
    private var pressedPreloadVideos = Set<String>()
    private var visiblePreloadVideos = Set<String>()
    private var recentVisiblePreloadVideos = Set<String>()
    private var recentVisiblePreloadOrder: [String] = []
    private var visiblePreloadCandidates = [String: VideoItem]()
    private let visiblePreloadDebouncer = TaskDebouncer()
    private let recentVisiblePreloadLimit = 18

    func beginPressedPreloadIfNeeded(
        for video: VideoItem,
        api: BiliAPIClient,
        preferredQuality: Int?,
        cdnPreference: PlaybackCDNPreference,
        playbackAdaptationProfile: PlayerPlaybackAdaptationProfile
    ) {
        let bvid = video.bvid
        guard !bvid.isEmpty, !pressedPreloadVideos.contains(bvid) else { return }
        pressedPreloadVideos.insert(bvid)

        Task {
            await VideoPreloadCenter.shared.updatePlaybackPreferences(
                preferredQuality: preferredQuality,
                cdnPreference: cdnPreference,
                playbackAdaptationProfile: playbackAdaptationProfile
            )
            await VideoPreloadCenter.shared.prioritizePlayback(for: video)
            await VideoPreloadCenter.shared.preloadPlayInfo(
                video,
                api: api,
                preferredQuality: preferredQuality,
                cdnPreference: cdnPreference,
                priority: .userInitiated,
                warmsMedia: true,
                mediaWarmupDelay: 0,
                playbackAdaptationProfile: playbackAdaptationProfile
            )
        }
    }

    func registerVisiblePreloadCandidate(
        _ video: VideoItem,
        api: BiliAPIClient,
        preferredQuality: Int?,
        cdnPreference: PlaybackCDNPreference,
        playbackAdaptationProfile: PlayerPlaybackAdaptationProfile
    ) {
        guard !video.bvid.isEmpty else { return }

        visiblePreloadCandidates[video.bvid] = video
        if visiblePreloadCandidates.count > 4,
           let oldestKey = visiblePreloadCandidates.keys.first {
            visiblePreloadCandidates.removeValue(forKey: oldestKey)
        }

        let candidates = Array(visiblePreloadCandidates.values.prefix(1))
        visiblePreloadDebouncer.schedule(delay: .milliseconds(420)) { [weak self] in
            guard let self else { return }
            for video in candidates {
                guard self.visiblePreloadCandidates[video.bvid] != nil else { continue }
                self.beginVisiblePreloadIfNeeded(
                    for: video,
                    api: api,
                    preferredQuality: preferredQuality,
                    cdnPreference: cdnPreference,
                    playbackAdaptationProfile: playbackAdaptationProfile
                )
            }
        }
    }

    func unregisterVisiblePreloadCandidate(_ video: VideoItem) {
        visiblePreloadCandidates.removeValue(forKey: video.bvid)
        visiblePreloadVideos.remove(video.bvid)
        if visiblePreloadCandidates.isEmpty {
            visiblePreloadDebouncer.cancel()
        }
    }

    private func beginVisiblePreloadIfNeeded(
        for video: VideoItem,
        api: BiliAPIClient,
        preferredQuality: Int?,
        cdnPreference: PlaybackCDNPreference,
        playbackAdaptationProfile: PlayerPlaybackAdaptationProfile
    ) {
        let bvid = video.bvid
        guard !bvid.isEmpty,
              !visiblePreloadVideos.contains(bvid),
              !recentVisiblePreloadVideos.contains(bvid),
              visiblePreloadVideos.count < 1,
              playbackAdaptationProfile.backgroundPreloadLimit > 0,
              !PlaybackEnvironment.current.shouldPreferConservativePlayback
        else { return }

        visiblePreloadVideos.insert(bvid)
        rememberVisiblePreload(bvid)
        Task(priority: .utility) {
            await VideoPreloadCenter.shared.preloadPlayInfo(
                video,
                api: api,
                preferredQuality: preferredQuality,
                cdnPreference: cdnPreference,
                priority: .utility,
                warmsMedia: true,
                mediaWarmupDelay: 0.35,
                playbackAdaptationProfile: playbackAdaptationProfile
            )
        }
    }

    private func rememberVisiblePreload(_ bvid: String) {
        recentVisiblePreloadVideos.insert(bvid)
        recentVisiblePreloadOrder.removeAll { $0 == bvid }
        recentVisiblePreloadOrder.append(bvid)
        while recentVisiblePreloadOrder.count > recentVisiblePreloadLimit {
            let evicted = recentVisiblePreloadOrder.removeFirst()
            recentVisiblePreloadVideos.remove(evicted)
        }
    }
}

private struct PressPreloadButtonStyle: ButtonStyle {
    let onPress: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.94 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.smooth(duration: 0.12), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    onPress()
                }
            }
    }
}
