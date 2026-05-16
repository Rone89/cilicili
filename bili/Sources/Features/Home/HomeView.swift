import SwiftUI
import Combine
import UIKit

struct HomeView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    @ObservedObject private var viewModel: HomeViewModel
    let autoOpenDetail: Bool
    let startVideo: VideoItem?
    @Binding var detailPath: NavigationPath
    let onVideoSelect: ((VideoItem) -> Void)?
    @State private var didAutoOpenDetail = false
    @State private var pullDistance: CGFloat = 0

    private let doubleColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]
    private let singleColumns = [
        GridItem(.flexible(minimum: 0), spacing: 0)
    ]
    @State private var pressedPreloadVideos = Set<String>()
    @State private var visiblePreloadVideos = Set<String>()
    @State private var visiblePreloadCandidates = [String: VideoItem]()
    @State private var visiblePreloadDebouncer = TaskDebouncer()

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
        .navigationBarTitleDisplayMode(.large)
        .nativeTopNavigationChrome()
    }

    @ViewBuilder
    private func content(_ viewModel: HomeViewModel) -> some View {
        videoFeed(viewModel)
            .id(viewModel.mode)
            .transition(feedTransition)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .animation(.smooth(duration: 0.26), value: viewModel.mode)
        .task {
            await dependencies.api.prewarmPlaybackSigningKeys()
            await viewModel.loadInitial()
            openFirstDetailIfNeeded(viewModel)
        }
        .onChange(of: viewModel.videos.first?.id) { _, _ in
            openFirstDetailIfNeeded(viewModel)
        }
    }

    private func feedPicker(_ viewModel: HomeViewModel) -> some View {
        Picker("Feed", selection: Binding(
            get: { viewModel.mode },
            set: { newMode in
                Task { await viewModel.switchMode(newMode) }
            }
        )) {
            ForEach(HomeFeedMode.allCases, id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private func feedPickerRow(_ viewModel: HomeViewModel) -> some View {
        feedPicker(viewModel)
            .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
    }

    private var feedTransition: AnyTransition {
        .opacity.combined(with: .move(edge: .trailing))
    }

    @ViewBuilder
    private func videoFeed(_ viewModel: HomeViewModel) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                if isPullRefreshIndicatorVisible {
                    pullRefreshIndicator
                }

                feedPickerRow(viewModel)

                if viewModel.videos.isEmpty && viewModel.state.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在加载\(viewModel.mode.title)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 120)
                } else if viewModel.videos.isEmpty {
                    EmptyStateView(
                        title: "暂无内容",
                        systemImage: "play.rectangle",
                        message: "下拉刷新或切换频道再试。"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 120)
                } else {
                    LazyVGrid(columns: feedColumns, spacing: feedSpacing) {
                        ForEach(viewModel.videoCells) { cell in
                            videoCard(cell.video, display: cell.display)
                                .onAppear {
                                    registerVisiblePreloadCandidate(cell.video)
                                }
                                .onDisappear {
                                    unregisterVisiblePreloadCandidate(cell.video)
                                }
                                .task(id: cell.id) {
                                    await viewModel.loadMoreIfNeeded(current: cell.video)
                                }
                        }

                        if viewModel.state.isLoading && !viewModel.isRefreshing {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .gridCellColumns(feedColumns.count)
                                .padding()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, feedHorizontalPadding)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 12)),
                        removal: .opacity
                    ))
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(refreshBridge(viewModel))
        }
        .nativeTopScrollEdgeEffect()
        .background(Color(.systemGroupedBackground))
        .animation(.smooth(duration: 0.22), value: pullRefreshIndicatorHeight)
        .animation(.smooth(duration: 0.2), value: isPullRefreshIndicatorVisible)
        .animation(.smooth(duration: 0.24), value: libraryStore.homeFeedLayout)
        .overlay {
            if case .failed(let message) = viewModel.state, viewModel.videos.isEmpty {
                ErrorStateView(title: "加载失败", message: message) {
                    Task { await viewModel.refresh() }
                }
            }
        }
    }

    private var feedColumns: [GridItem] {
        libraryStore.homeFeedLayout == .singleColumn ? singleColumns : doubleColumns
    }

    private var feedSpacing: CGFloat {
        libraryStore.homeFeedLayout == .singleColumn ? 22 : 18
    }

    private var feedHorizontalPadding: CGFloat {
        libraryStore.homeFeedLayout == .singleColumn ? 0 : 10
    }

    private func refreshBridge(_ viewModel: HomeViewModel) -> some View {
        HomeScrollRefreshBridge(
            isRefreshing: viewModel.isRefreshing,
            triggerDistance: CGFloat(libraryStore.homeRefreshTriggerDistance),
            onPullDistanceChange: { distance in
                DispatchQueue.main.async {
                    guard abs(pullDistance - distance) >= 0.5 else { return }
                    pullDistance = distance
                }
            },
            onRefresh: {
                Task {
                    await viewModel.refreshFromUserPull()
                }
            }
        )
        .frame(height: 0)
    }

    private var isPullRefreshIndicatorVisible: Bool {
        pullDistance > 10 || viewModel.isRefreshing
    }

    private var pullRefreshIndicatorHeight: CGFloat {
        guard isPullRefreshIndicatorVisible else { return 0 }
        return 48
    }

    @ViewBuilder
    private var pullRefreshIndicator: some View {
        let triggerDistance = CGFloat(libraryStore.homeRefreshTriggerDistance)
        let progress = min(max(pullDistance / max(triggerDistance, 1), 0), 1)
        ZStack(alignment: .center) {
            HomePullRefreshIndicator(
                progress: progress,
                isRefreshing: viewModel.isRefreshing,
                isReady: pullDistance >= triggerDistance
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: pullRefreshIndicatorHeight)
        .transition(.opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.96)))
        .clipped()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func videoCard(_ video: VideoItem, display: VideoCardDisplayModel) -> some View {
        if let onVideoSelect {
            Button {
                onVideoSelect(video)
            } label: {
                cardContent(display)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
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
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
            .buttonStyle(PressPreloadButtonStyle {
                beginPressedPreloadIfNeeded(for: video)
            })
        }
    }

    @ViewBuilder
    private func cardContent(_ display: VideoCardDisplayModel) -> some View {
        if libraryStore.homeFeedLayout == .singleColumn {
            YouTubeStyleVideoFeedCardView(display: display)
        } else {
            VideoCardView(display: display, showsPublishTimeInAuthorRow: true)
        }
    }

    private func beginPressedPreloadIfNeeded(for video: VideoItem) {
        let bvid = video.bvid
        guard !pressedPreloadVideos.contains(bvid) else { return }
        let api = dependencies.api
        let preferredQuality = libraryStore.preferredVideoQuality
        let cdnPreference = libraryStore.effectivePlaybackCDNPreference
        let playbackAdaptationProfile = PlayerPerformanceStore.shared.playbackAdaptationProfile(
            for: video.bvid,
            isEnabled: libraryStore.isPlaybackAutoOptimizationEnabled
        )
        DispatchQueue.main.async {
            guard !pressedPreloadVideos.contains(bvid) else { return }
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
                    playbackAdaptationProfile: playbackAdaptationProfile
                )
            }
        }
    }

    private func beginVisiblePreloadIfNeeded(for video: VideoItem) {
        let bvid = video.bvid
        guard !bvid.isEmpty,
              !visiblePreloadVideos.contains(bvid),
              visiblePreloadVideos.count < 4
        else { return }
        let api = dependencies.api
        let preferredQuality = libraryStore.preferredVideoQuality
        let cdnPreference = libraryStore.effectivePlaybackCDNPreference
        let playbackAdaptationProfile = PlayerPerformanceStore.shared.playbackAdaptationProfile(
            isEnabled: libraryStore.isPlaybackAutoOptimizationEnabled
        )
        visiblePreloadVideos.insert(bvid)
        Task(priority: .utility) {
            await VideoPreloadCenter.shared.preloadPlayInfo(
                video,
                api: api,
                preferredQuality: preferredQuality,
                cdnPreference: cdnPreference,
                priority: .utility,
                playbackAdaptationProfile: playbackAdaptationProfile
            )
        }
    }

    private func endVisiblePreload(for video: VideoItem) {
        visiblePreloadVideos.remove(video.bvid)
    }

    private func registerVisiblePreloadCandidate(_ video: VideoItem) {
        guard !video.bvid.isEmpty else { return }
        visiblePreloadCandidates[video.bvid] = video
        if visiblePreloadCandidates.count > 4,
           let oldestKey = visiblePreloadCandidates.keys.first {
            visiblePreloadCandidates.removeValue(forKey: oldestKey)
        }
        scheduleVisiblePreloadFlush()
    }

    private func unregisterVisiblePreloadCandidate(_ video: VideoItem) {
        visiblePreloadCandidates.removeValue(forKey: video.bvid)
        endVisiblePreload(for: video)
        if visiblePreloadCandidates.isEmpty {
            visiblePreloadDebouncer.cancel()
        }
    }

    private func scheduleVisiblePreloadFlush() {
        let candidates = Array(visiblePreloadCandidates.values.prefix(2))
        visiblePreloadDebouncer.schedule(delay: .milliseconds(420)) {
            for video in candidates {
                guard visiblePreloadCandidates[video.bvid] != nil else { continue }
                beginVisiblePreloadIfNeeded(for: video)
            }
        }
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

private struct HomePullRefreshIndicator: View {
    let progress: CGFloat
    let isRefreshing: Bool
    let isReady: Bool

    private var normalizedProgress: CGFloat {
        min(max(progress, 0), 1)
    }

    private var statusText: String {
        if isRefreshing {
            return "更新中"
        }
        return isReady ? "准备更新" : "拉取推荐"
    }

    var body: some View {
        HStack(spacing: 9) {
            progressGlyph

            VStack(alignment: .leading, spacing: 5) {
                Text(statusText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isReady || isRefreshing ? Color.pink : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(width: 58, alignment: .leading)

                progressTrack
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(Color(.systemBackground).opacity(0.92))
        }
        .overlay {
            Capsule()
                .stroke(Color(.separator).opacity(0.10), lineWidth: 0.6)
        }
        .animation(.smooth(duration: 0.22), value: normalizedProgress)
        .animation(.smooth(duration: 0.18), value: isReady)
        .animation(.smooth(duration: 0.18), value: isRefreshing)
    }

    private var progressGlyph: some View {
        ZStack {
            Circle()
                .stroke(Color(.separator).opacity(0.18), lineWidth: 2.4)

            Circle()
                .trim(from: 0, to: isRefreshing ? 1 : max(normalizedProgress, 0.06))
                .stroke(
                    Color.pink.opacity(isRefreshing || isReady ? 1 : 0.78),
                    style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            if isRefreshing {
                ProgressView()
                    .controlSize(.mini)
                    .tint(.pink)
                    .scaleEffect(0.78)
            } else {
                Image(systemName: "arrow.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isReady ? Color.pink : Color.secondary)
                    .rotationEffect(.degrees(isReady ? 180 : Double(normalizedProgress) * 130))
            }
        }
        .frame(width: 24, height: 24)
    }

    private var progressTrack: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.tertiarySystemFill))

                Capsule()
                    .fill(Color.pink.opacity(isRefreshing || isReady ? 0.95 : 0.68))
                    .frame(width: max(width * (isRefreshing ? 1 : normalizedProgress), 5))
            }
        }
        .frame(width: 58, height: 3)
    }
}

private struct HomeScrollRefreshBridge: UIViewRepresentable {
    let isRefreshing: Bool
    let triggerDistance: CGFloat
    let onPullDistanceChange: (CGFloat) -> Void
    let onRefresh: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isRefreshing: isRefreshing,
            triggerDistance: triggerDistance,
            onPullDistanceChange: onPullDistanceChange,
            onRefresh: onRefresh
        )
    }

    func makeUIView(context: Context) -> RefreshProbeView {
        let view = RefreshProbeView()
        view.onMoveToWindow = { [weak coordinator = context.coordinator, weak view] in
            guard let view else { return }
            coordinator?.attach(from: view)
        }
        DispatchQueue.main.async { [weak view, weak coordinator = context.coordinator] in
            guard let view else { return }
            coordinator?.attach(from: view)
        }
        return view
    }

    func updateUIView(_ uiView: RefreshProbeView, context: Context) {
        let wasRefreshing = context.coordinator.isRefreshing
        context.coordinator.isRefreshing = isRefreshing
        context.coordinator.triggerDistance = triggerDistance
        context.coordinator.onPullDistanceChange = onPullDistanceChange
        context.coordinator.onRefresh = onRefresh
        if wasRefreshing, !isRefreshing {
            context.coordinator.finishRefreshing()
        }
        DispatchQueue.main.async { [weak uiView, weak coordinator = context.coordinator] in
            guard let uiView else { return }
            coordinator?.attach(from: uiView)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var isRefreshing: Bool
        var triggerDistance: CGFloat
        var onPullDistanceChange: (CGFloat) -> Void
        var onRefresh: () -> Void

        private weak var scrollView: UIScrollView?
        private var contentOffsetObservation: NSKeyValueObservation?
        private var didTriggerRefresh = false
        private var lastReportedPullDistance: CGFloat = 0

        init(
            isRefreshing: Bool,
            triggerDistance: CGFloat,
            onPullDistanceChange: @escaping (CGFloat) -> Void,
            onRefresh: @escaping () -> Void
        ) {
            self.isRefreshing = isRefreshing
            self.triggerDistance = triggerDistance
            self.onPullDistanceChange = onPullDistanceChange
            self.onRefresh = onRefresh
            super.init()
        }

        deinit {
            contentOffsetObservation?.invalidate()
        }

        func attach(from view: UIView) {
            guard let foundScrollView = view.enclosingScrollView(),
                  scrollView !== foundScrollView
            else {
                return
            }

            contentOffsetObservation?.invalidate()
            scrollView = foundScrollView
            foundScrollView.alwaysBounceVertical = true
            foundScrollView.refreshControl = nil

            contentOffsetObservation = foundScrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
                guard Thread.isMainThread else {
                    DispatchQueue.main.async { [weak self, weak scrollView] in
                        guard let self, let scrollView else { return }
                        self.handleScroll(scrollView)
                    }
                    return
                }

                MainActor.assumeIsolated {
                    self?.handleScroll(scrollView)
                }
            }
        }

        func finishRefreshing() {
            guard let scrollView else {
                didTriggerRefresh = false
                onPullDistanceChange(0)
                return
            }

            let distance = max(0, -(scrollView.contentOffset.y + scrollView.adjustedContentInset.top))
            guard distance < 12, !scrollView.isDragging else { return }
            didTriggerRefresh = false
            onPullDistanceChange(0)
        }

        private func handleScroll(_ scrollView: UIScrollView) {
            let distance = max(0, -(scrollView.contentOffset.y + scrollView.adjustedContentInset.top))
            reportPullDistanceIfNeeded(distance)

            guard !isRefreshing else { return }

            if distance < 12, !scrollView.isDragging {
                didTriggerRefresh = false
                reportPullDistanceIfNeeded(0, force: true)
                return
            }

            guard distance >= triggerDistance,
                  scrollView.isDragging,
                  !didTriggerRefresh
            else { return }

            didTriggerRefresh = true
            Haptics.medium()
            onRefresh()
        }

        private func reportPullDistanceIfNeeded(_ distance: CGFloat, force: Bool = false) {
            guard force || abs(distance - lastReportedPullDistance) >= 1.5 else { return }
            lastReportedPullDistance = distance
            onPullDistanceChange(distance)
        }
    }
}

private final class RefreshProbeView: UIView {
    var onMoveToWindow: (() -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onMoveToWindow?()
    }
}

private extension UIView {
    func enclosingScrollView() -> UIScrollView? {
        var view: UIView? = self
        while let current = view {
            if let scrollView = current as? UIScrollView {
                return scrollView
            }
            view = current.superview
        }
        return nil
    }
}
