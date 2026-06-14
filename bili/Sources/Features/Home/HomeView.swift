import SwiftUI
import Combine
import OSLog

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

private struct HomeVisibleVideoFrame: Equatable {
    let bvid: String
    let index: Int
    let minY: CGFloat
    let midY: CGFloat
    let maxY: CGFloat
    let height: CGFloat

    init(bvid: String, index: Int, frame: CGRect) {
        self.bvid = bvid
        self.index = index
        minY = Self.quantized(frame.minY)
        midY = Self.quantized(frame.midY)
        maxY = Self.quantized(frame.maxY)
        height = Self.quantized(frame.height)
    }

    private static func quantized(_ value: CGFloat) -> CGFloat {
        (value / 4).rounded() * 4
    }
}

private struct HomeVisibleVideoFramePreferenceKey: PreferenceKey {
    static var defaultValue: [HomeVisibleVideoFrame] = []

    static func reduce(value: inout [HomeVisibleVideoFrame], nextValue: () -> [HomeVisibleVideoFrame]) {
        value.append(contentsOf: nextValue())
    }
}

private extension Color {
    static let homeGitHubLikeBackground = Color(red: 0.965, green: 0.973, blue: 0.984)
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
    @State private var currentPullRefreshDistance: CGFloat = 0

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
        .rootNavigationTitle("首页") {
            feedPickerRow(viewModel)
        }
        .nativeTopNavigationChrome()
    }

    @ViewBuilder
    private func content(_ viewModel: HomeViewModel) -> some View {
        videoFeed(viewModel)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.homeGitHubLikeBackground)
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
        Menu {
            ForEach(HomeFeedMode.allCases, id: \.self) { mode in
                Button {
                    Task { await viewModel.switchMode(mode) }
                } label: {
                    Label(mode.title, systemImage: viewModel.mode == mode ? "checkmark" : mode.systemImage)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.semibold))
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .biliPlayerClearGlass(interactive: true, in: Circle())
        .accessibilityLabel("首页内容")
        .accessibilityValue(viewModel.mode.title)
    }

    @ViewBuilder
    private func videoFeed(_ viewModel: HomeViewModel) -> some View {
        ScrollView {
            homePullRefreshOffsetReader
            homeFeedWidthReader

            VStack(spacing: 6) {
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
        .onPreferenceChange(HomeVisibleVideoFramePreferenceKey.self) { frames in
            updateVisiblePreloadFrames(frames)
        }
        .onPreferenceChange(HomePullRefreshDistancePreferenceKey.self) { pullDistance in
            currentPullRefreshDistance = pullDistance
            handleConfiguredPullRefresh(pullDistance: pullDistance, viewModel: viewModel)
        }
        .scrollBounceBehavior(.always, axes: .vertical)
        .background(Color.homeGitHubLikeBackground)
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
            HomePullRefreshIndicator(
                pullDistance: currentPullRefreshDistance,
                triggerDistance: CGFloat(runtimeSettings.homeRefreshTriggerDistance),
                isRefreshing: viewModel.isUserRefreshing
            )
            .padding(.top, 6)
            .allowsHitTesting(false)
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

    private struct HomePullRefreshIndicator: View {
        let pullDistance: CGFloat
        let triggerDistance: CGFloat
        let isRefreshing: Bool

        private var progress: CGFloat {
            guard triggerDistance > 0 else { return 0 }
            return min(max(pullDistance / triggerDistance, 0), 1)
        }

        private var isVisible: Bool {
            isRefreshing || progress > 0.08
        }

        var body: some View {
            HStack(spacing: 7) {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: progress >= 1 ? "checkmark" : "arrow.down")
                        .font(.system(size: 12, weight: .bold))
                        .rotationEffect(.degrees(Double(progress) * 180))
                        .symbolEffect(.bounce, value: progress >= 1)
                }

                Text(isRefreshing ? "正在刷新" : progress >= 1 ? "松开刷新" : "下拉刷新")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .biliPlayerClearGlass(interactive: false, in: Capsule())
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.82)
            .offset(y: isVisible ? min(max(pullDistance * 0.18, 0), 14) : -8)
            .animation(.smooth(duration: 0.18), value: isVisible)
            .animation(.smooth(duration: 0.18), value: isRefreshing)
            .accessibilityHidden(!isVisible)
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
                ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                    VStack(spacing: 0) {
                        videoCard(cell.video, display: cell.display)
                            .homeVisibleVideoFrame(for: cell.video, index: index)
                            .padding(.top, 9)
                            .padding(.bottom, 14)
                            .onAppear {
                                registerVisiblePreloadCandidate(cell.video, index: index)
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
                ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                    videoCard(cell.video, display: cell.display)
                        .homeVisibleVideoFrame(for: cell.video, index: index)
                        .onAppear {
                            registerVisiblePreloadCandidate(cell.video, index: index)
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
                fixedCoverSize: singleColumnFixedCoverSize,
                coverMaximumPixelLength: 720
            )
                .equatable()
        case .doubleColumn:
            VideoCardView(
                display: display,
                showsPublishTimeInAuthorRow: true,
                showsCoverViewCountBadge: false,
                surfaceStyle: .blended,
                fixedCoverSize: doubleColumnFixedCoverSize,
                coverMaximumPixelLength: 480
            )
                .equatable()
        }
    }

    private func beginPressedPreloadIfNeeded(for video: VideoItem) {
        guard !video.bvid.hasPrefix("av") else { return }
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

    private func registerVisiblePreloadCandidate(_ video: VideoItem, index: Int) {
        guard !video.bvid.hasPrefix("av") else { return }
        preloadCoordinator.registerVisiblePreloadCandidate(
            video,
            index: index,
            api: dependencies.api,
            preferredQuality: dependencies.libraryStore.preferredVideoQuality,
            cdnPreference: dependencies.libraryStore.effectivePlaybackCDNPreference,
            playbackAdaptationProfile: PlayerPerformanceStore.shared.playbackAdaptationProfile(
                isEnabled: dependencies.libraryStore.isPlaybackAutoOptimizationEnabled
            )
        )
    }

    private func updateVisiblePreloadFrames(_ frames: [HomeVisibleVideoFrame]) {
        preloadCoordinator.updateVisiblePreloadFrames(
            frames,
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
    func homeVisibleVideoFrame(for video: VideoItem, index: Int) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: HomeVisibleVideoFramePreferenceKey.self,
                    value: [
                        HomeVisibleVideoFrame(
                            bvid: video.bvid,
                            index: index,
                            frame: proxy.frame(in: .global)
                        )
                    ]
                )
            }
        }
    }

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
    private var visiblePreloadCandidates = [String: VisiblePreloadCandidate]()
    private var latestVisibleFrames = [String: HomeVisibleVideoFrame]()
    private var visiblePreloadSequence = 0
    private let visiblePreloadDebouncer = TaskDebouncer()
    private let recentVisiblePreloadLimit = 18
    private let visibleCandidateLimit = 8

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
        index: Int,
        api: BiliAPIClient,
        preferredQuality: Int?,
        cdnPreference: PlaybackCDNPreference,
        playbackAdaptationProfile: PlayerPlaybackAdaptationProfile
    ) {
        guard !video.bvid.isEmpty else { return }

        if var candidate = visiblePreloadCandidates[video.bvid] {
            candidate.video = video
            candidate.index = index
            visiblePreloadCandidates[video.bvid] = candidate
        } else {
            visiblePreloadSequence += 1
            visiblePreloadCandidates[video.bvid] = VisiblePreloadCandidate(
                video: video,
                index: index,
                frame: latestVisibleFrames[video.bvid],
                sequence: visiblePreloadSequence
            )
        }
        trimVisiblePreloadCandidatesIfNeeded()
        scheduleVisiblePreload(
            delay: .milliseconds(620),
            api: api,
            preferredQuality: preferredQuality,
            cdnPreference: cdnPreference,
            playbackAdaptationProfile: playbackAdaptationProfile
        )
    }

    func updateVisiblePreloadFrames(
        _ frames: [HomeVisibleVideoFrame],
        api: BiliAPIClient,
        preferredQuality: Int?,
        cdnPreference: PlaybackCDNPreference,
        playbackAdaptationProfile: PlayerPlaybackAdaptationProfile
    ) {
        guard !frames.isEmpty else { return }
        var didUpdate = false
        for frame in frames {
            latestVisibleFrames[frame.bvid] = frame
            guard var candidate = visiblePreloadCandidates[frame.bvid] else { continue }
            if candidate.frame != frame || candidate.index != frame.index {
                candidate.frame = frame
                candidate.index = frame.index
                visiblePreloadCandidates[frame.bvid] = candidate
                didUpdate = true
            }
        }
        guard didUpdate else { return }
        trimVisiblePreloadCandidatesIfNeeded()
        scheduleVisiblePreload(
            delay: .milliseconds(180),
            api: api,
            preferredQuality: preferredQuality,
            cdnPreference: cdnPreference,
            playbackAdaptationProfile: playbackAdaptationProfile
        )
    }

    func unregisterVisiblePreloadCandidate(_ video: VideoItem) {
        visiblePreloadCandidates.removeValue(forKey: video.bvid)
        latestVisibleFrames.removeValue(forKey: video.bvid)
        visiblePreloadVideos.remove(video.bvid)
        if visiblePreloadCandidates.isEmpty {
            visiblePreloadDebouncer.cancel()
        }
    }

    private func scheduleVisiblePreload(
        delay: Duration,
        api: BiliAPIClient,
        preferredQuality: Int?,
        cdnPreference: PlaybackCDNPreference,
        playbackAdaptationProfile: PlayerPlaybackAdaptationProfile
    ) {
        visiblePreloadDebouncer.schedule(delay: delay) { [weak self] in
            guard let self,
                  let candidate = self.bestVisiblePreloadCandidate()
            else { return }
            self.logVisiblePreloadChoice(candidate)
            self.beginVisiblePreloadIfNeeded(
                for: candidate.video,
                api: api,
                preferredQuality: preferredQuality,
                cdnPreference: cdnPreference,
                playbackAdaptationProfile: playbackAdaptationProfile
            )
        }
    }

    private func bestVisiblePreloadCandidate() -> VisiblePreloadCandidate? {
        let screenHeight = max(UIScreen.main.bounds.height, 1)
        return visiblePreloadCandidates.values
            .filter {
                let bvid = $0.video.bvid
                return !bvid.isEmpty
                    && !visiblePreloadVideos.contains(bvid)
                    && !recentVisiblePreloadVideos.contains(bvid)
                    && isVisibleEnough($0, screenHeight: screenHeight)
            }
            .sorted { lhs, rhs in
                let lhsScore = visiblePreloadScore(lhs, screenHeight: screenHeight)
                let rhsScore = visiblePreloadScore(rhs, screenHeight: screenHeight)
                if abs(lhsScore - rhsScore) > 0.01 {
                    return lhsScore < rhsScore
                }
                if lhs.index != rhs.index {
                    return lhs.index < rhs.index
                }
                return lhs.sequence < rhs.sequence
            }
            .first
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
              playbackAdaptationProfile.backgroundRoutePlanPreloadLimit > 0
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
                mediaWarmupMode: .routePlanOnly,
                mediaWarmupDelay: 0.35,
                playbackAdaptationProfile: playbackAdaptationProfile
            )
        }
    }

    private func trimVisiblePreloadCandidatesIfNeeded() {
        guard visiblePreloadCandidates.count > visibleCandidateLimit else { return }
        let kept = Set(
            visiblePreloadCandidates.values
                .sorted { lhs, rhs in
                    if lhs.index != rhs.index {
                        return lhs.index < rhs.index
                    }
                    return lhs.sequence < rhs.sequence
                }
                .prefix(visibleCandidateLimit)
                .map { $0.video.bvid }
        )
        visiblePreloadCandidates = visiblePreloadCandidates.filter { kept.contains($0.key) }
    }

    private func isVisibleEnough(_ candidate: VisiblePreloadCandidate, screenHeight: CGFloat) -> Bool {
        guard let frame = candidate.frame else { return true }
        let topBound = screenHeight * 0.12
        let bottomBound = screenHeight * 0.86
        let visibleHeight = max(0, min(frame.maxY, bottomBound) - max(frame.minY, topBound))
        let ratio = visibleHeight / max(frame.height, 1)
        return ratio >= 0.18
    }

    private func visiblePreloadScore(_ candidate: VisiblePreloadCandidate, screenHeight: CGFloat) -> CGFloat {
        guard let frame = candidate.frame else {
            return 10_000 + CGFloat(candidate.index)
        }

        let topBound = screenHeight * 0.12
        let bottomBound = screenHeight * 0.86
        let visibleHeight = max(0, min(frame.maxY, bottomBound) - max(frame.minY, topBound))
        let visibilityRatio = min(max(visibleHeight / max(frame.height, 1), 0), 1)
        let targetY = screenHeight * 0.38
        var score = abs(frame.midY - targetY)
        if frame.midY > screenHeight * 0.70 {
            score += screenHeight * 0.40
        }
        if frame.minY < topBound {
            score += screenHeight * 0.15
        }
        score -= visibilityRatio * 40
        score += CGFloat(candidate.index) * 0.01
        return score
    }

    private func logVisiblePreloadChoice(_ candidate: VisiblePreloadCandidate) {
        let screenHeight = max(UIScreen.main.bounds.height, 1)
        let score = visiblePreloadScore(candidate, screenHeight: screenHeight)
        let midY = candidate.frame.map { Double($0.midY) } ?? -1
        PlayerMetricsLog.logger.info(
            "homeVisiblePreloadCandidate bvid=\(candidate.video.bvid, privacy: .public) index=\(candidate.index, privacy: .public) score=\(Double(score), format: .fixed(precision: 1), privacy: .public) midY=\(midY, format: .fixed(precision: 1), privacy: .public)"
        )
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

    private struct VisiblePreloadCandidate {
        var video: VideoItem
        var index: Int
        var frame: HomeVisibleVideoFrame?
        let sequence: Int
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
