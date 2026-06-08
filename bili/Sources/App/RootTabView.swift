import SwiftUI
import Combine
import UIKit

struct RootTabView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @StateObject private var runtimeSettings = RootRuntimeSettingsStore()
    @StateObject private var homeViewModelHolder = RootHomeViewModelHolder()
    @State private var selectedTab = Self.initialTab.appTab
    @State private var bottomMode: BottomTabMode = .root
    @State private var rootTabBarRestoreRequestID = 0
    @State private var activeVideo: VideoItem?
    @State private var videoNavigationPath = NavigationPath()
    @State private var navigationPath = NavigationPath()
    @State private var dynamicNavigationPath = NavigationPath()
    @State private var liveNavigationPath = NavigationPath()
    @State private var mineNavigationPath = NavigationPath()
    @State private var searchNavigationPath = NavigationPath()
    @State private var didConsumeStartupVideo = false
    @State private var didConsumeStartupLiveRoom = false
    @State private var isClosingVideo = false
    @State private var closeVideoFallbackTask: Task<Void, Never>?
    @State private var inAppBrowserItem: InAppBrowserItem?
    @State private var recentPlaybackPreloadTimes: [String: Date] = [:]
    private let shouldStartDetail = ProcessInfo.processInfo.arguments.contains("--start-detail")
    private let startBVID = Self.argumentValue(after: "--start-bvid")
    private let startLiveRoomID = Self.argumentInt(after: "--start-live-room")

    var body: some View {
        ZStack {
            TabView(selection: tabSelection) {
                Tab(value: AppTab.home) {
                    NavigationStack(path: $navigationPath) {
                        homePage()
                    }
                } label: {
                    Label(RootTab.home.title, systemImage: RootTab.home.systemImage)
                }

                Tab(value: AppTab.dynamic) {
                    NavigationStack(path: $dynamicNavigationPath) {
                        DynamicView()
                            .videoDestinations()
                    }
                } label: {
                    Label(RootTab.dynamic.title, systemImage: RootTab.dynamic.systemImage)
                }

                Tab(value: AppTab.live) {
                    NavigationStack(path: $liveNavigationPath) {
                        LiveView()
                            .videoDestinations()
                    }
                } label: {
                    Label(RootTab.live.title, systemImage: RootTab.live.systemImage)
                }

                Tab(value: AppTab.mine) {
                    NavigationStack(path: $mineNavigationPath) {
                        MineView()
                            .videoDestinations()
                    }
                } label: {
                    Label(RootTab.mine.title, systemImage: RootTab.mine.systemImage)
                }

                Tab(value: AppTab.search, role: .search) {
                    NavigationStack(path: $searchNavigationPath) {
                        SearchView()
                            .videoDestinations()
                    }
                } label: {
                    Label(RootTab.search.title, systemImage: RootTab.search.systemImage)
                }
            }
            .tint(.pink)
            .tabBarMinimizeBehavior(runtimeSettings.minimizesTabBarOnScroll ? .onScrollDown : .never)
            .tabViewSearchActivation(.searchTabSelection)
            .restoresRootTabBarWhenRequested(requestID: rootTabBarRestoreRequestID)
            .background(RootTabBarAppearanceInstaller())

            if bottomMode == .video {
                videoNavigationHost()
                    .ignoresSafeArea()
                    .transition(.identity)
                    .zIndex(1)
            }
        }
        .environment(\.openVideoAction, openVideo)
        .environment(\.prewarmVideoRouteAction, beginPlaybackPreload)
        .environment(\.openAppURLAction, openAppURL)
        .environment(\.openURL, OpenURLAction { url in
            guard AppLinkRouter.canHandle(url) else { return .systemAction }
            openAppURL(url)
            return .handled
        })
        .background(NavigationChromeInstaller(isStandardChromeEnabled: bottomMode == .video))
        .animation(.smooth(duration: 0.28), value: bottomMode)
        .animation(.smooth(duration: 0.22), value: selectedTab)
        .preferredColorScheme(runtimeSettings.appearanceMode.preferredColorScheme)
        .sheet(item: $inAppBrowserItem) { item in
            InAppBrowserView(url: item.url)
                .ignoresSafeArea()
        }
        .task {
            runtimeSettings.bind(dependencies.libraryStore)
            dependencies.refreshPlaybackCDNProbeIfNeeded()
            openStartupVideoIfNeeded()
            openStartupLiveRoomIfNeeded()
            await dependencies.api.prewarmPlaybackSigningKeys()
        }
    }

    @ViewBuilder
    private func homePage() -> some View {
        if let viewModel = homeViewModelHolder.viewModel {
            HomeView(
                viewModel: viewModel,
                autoOpenDetail: shouldAutoOpenDetail,
                startVideo: startBVID.map(Self.seedVideo),
                detailPath: $navigationPath,
                onVideoSelect: openVideo
            )
            .videoDestinations()
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
                .task {
                    homeViewModelHolder.configure(
                        api: dependencies.api,
                        libraryStore: dependencies.libraryStore,
                        initialMode: .recommend
                    )
                }
        }
    }

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { selectedTab = $0 }
        )
    }

    private var shouldAutoOpenDetail: Bool {
        !didConsumeStartupVideo && shouldStartDetail && startBVID == nil
    }

    private func openStartupVideoIfNeeded() {
        guard !didConsumeStartupVideo,
              let startBVID
        else { return }

        openVideo(Self.seedVideo(bvid: startBVID))
    }

    private func openStartupLiveRoomIfNeeded() {
        guard !didConsumeStartupLiveRoom,
              let startLiveRoomID
        else { return }

        didConsumeStartupLiveRoom = true
        selectedTab = .live
        DispatchQueue.main.async {
            liveNavigationPath.append(Self.seedLiveRoom(roomID: startLiveRoomID))
        }
    }

    private func openAppURL(_ url: URL) {
        guard AppLinkRouter.canHandle(url) else { return }

        Task { @MainActor in
            let destination = await AppLinkRouter.destination(for: url, api: dependencies.api)
            routeAppLinkDestination(destination)
        }
    }

    private func routeAppLinkDestination(_ destination: AppLinkDestination) {
        switch destination {
        case .video(let video):
            openVideo(video)
        case .liveRoom(let room):
            openLiveRoomFromLink(room)
        case .user(let owner):
            openUserFromLink(owner)
        case .browser(let url):
            inAppBrowserItem = InAppBrowserItem(url: url)
        }
    }

    private func openLiveRoomFromLink(_ room: LiveRoom) {
        AppOrientationLock.restorePortrait()
        if bottomMode == .video {
            ActivePlaybackCoordinator.shared.stopActivePlayback()
            NotificationCenter.default.post(name: .biliStopActiveVideoPlayback, object: nil)
            withAnimation(.smooth(duration: 0.28)) {
                videoNavigationPath.append(room)
            }
            return
        }

        selectedTab = .live
        DispatchQueue.main.async {
            liveNavigationPath.append(room)
        }
    }

    private func openUserFromLink(_ owner: VideoOwner) {
        AppOrientationLock.restorePortrait()
        if bottomMode == .video {
            withAnimation(.smooth(duration: 0.28)) {
                videoNavigationPath.append(owner)
            }
            return
        }

        DispatchQueue.main.async {
            switch selectedTab {
            case .home:
                navigationPath.append(owner)
            case .dynamic:
                dynamicNavigationPath.append(owner)
            case .live:
                liveNavigationPath.append(owner)
            case .mine:
                mineNavigationPath.append(owner)
            case .search:
                searchNavigationPath.append(owner)
            }
        }
    }

    private func videoNavigationHost() -> some View {
        NavigationStack(path: $videoNavigationPath) {
            Color.clear
                .ignoresSafeArea()
                .background(VideoNavigationHostTransparency(suppressesNavigationBar: true))
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: VideoItem.self) { video in
                    VideoDetailView(
                        seedVideo: video,
                        hidesRootTabBar: false
                    )
                    .id(video.id)
                }
                .navigationDestination(for: VideoOwner.self) { owner in
                    UploaderView(owner: owner)
                }
                .navigationDestination(for: LiveRoom.self) { room in
                    LiveRoomDetailView(seedRoom: room)
                }
        }
        .background(VideoNavigationHostTransparency(suppressesNavigationBar: true))
        .background(VideoNavigationTransitionObserver(isClosing: isClosingVideo) { cancelled in
            if cancelled {
                cancelCloseVideoIfNeeded()
            } else {
                completeCloseVideoIfNeeded()
            }
        })
        .onChange(of: videoNavigationPath) { _, newPath in
            guard bottomMode == .video, newPath.isEmpty else { return }
            scheduleCloseVideo()
        }
    }

    private func openVideo(_ video: VideoItem) {
        AppOrientationLock.restorePortrait()
        PlayerMetricsLog.record(.routeOpen, metricsID: video.bvid, title: video.title)
        if bottomMode == .video {
            pushVideo(video)
            return
        }

        beginPlaybackPreload(for: video)
        let update = {
            didConsumeStartupVideo = true
            isClosingVideo = false
            activeVideo = video
            videoNavigationPath = NavigationPath()
            bottomMode = .video
        }

        let opensFromStartup = shouldStartDetail && !didConsumeStartupVideo
        if shouldStartDetail && !didConsumeStartupVideo {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, update)
        } else {
            withAnimation(.smooth(duration: 0.32), update)
        }
        pushInitialVideo(video, animated: !opensFromStartup)
    }

    private func pushVideo(_ video: VideoItem) {
        AppOrientationLock.restorePortrait()
        PlayerMetricsLog.record(.routeOpen, metricsID: video.bvid, title: video.title)
        ActivePlaybackCoordinator.shared.pauseActivePlaybackForNavigation()
        NotificationCenter.default.post(name: .biliPauseActiveVideoPlaybackForNavigation, object: nil)
        beginPlaybackPreload(for: video)
        withAnimation(.smooth(duration: 0.28)) {
            didConsumeStartupVideo = true
            isClosingVideo = false
            videoNavigationPath.append(video)
        }
    }

    private func beginPlaybackPreload(for video: VideoItem) {
        guard !video.bvid.isEmpty else { return }
        let now = Date()
        if let lastPreload = recentPlaybackPreloadTimes[video.bvid],
           now.timeIntervalSince(lastPreload) < 1.2 {
            return
        }
        recentPlaybackPreloadTimes[video.bvid] = now
        trimRecentPlaybackPreloads(now: now)

        Task {
            dependencies.refreshPlaybackCDNProbeIfNeeded()
            let playbackAdaptationProfile = PlayerPerformanceStore.shared.playbackAdaptationProfile(
                for: video.bvid,
                isEnabled: dependencies.libraryStore.isPlaybackAutoOptimizationEnabled
            )
            let preferredQuality = dependencies.libraryStore.preferredVideoQuality
            let cdnPreference = dependencies.libraryStore.effectivePlaybackCDNPreference
            let api = dependencies.api
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

    private func trimRecentPlaybackPreloads(now: Date) {
        recentPlaybackPreloadTimes = recentPlaybackPreloadTimes.filter { _, date in
            now.timeIntervalSince(date) < 8
        }
        guard recentPlaybackPreloadTimes.count > 16 else { return }
        let keptKeys = Set(
            recentPlaybackPreloadTimes
                .sorted { $0.value > $1.value }
                .prefix(16)
                .map(\.key)
        )
        recentPlaybackPreloadTimes = recentPlaybackPreloadTimes.filter { keptKeys.contains($0.key) }
    }

    private func pushInitialVideo(_ video: VideoItem, animated: Bool) {
        DispatchQueue.main.async {
            guard bottomMode == .video,
                  videoNavigationPath.isEmpty,
                  activeVideo?.id == video.id
            else { return }

            let push = {
                videoNavigationPath.append(video)
            }

            if animated {
                withAnimation(.smooth(duration: 0.30), push)
            } else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction, push)
            }
        }
    }

    private func closeVideo() {
        guard bottomMode == .video else { return }

        if videoNavigationPath.isEmpty {
            scheduleCloseVideo()
            return
        }

        withAnimation(.smooth(duration: 0.24)) {
            videoNavigationPath = NavigationPath()
        }
        scheduleCloseVideo()
    }

    private func scheduleCloseVideo() {
        guard bottomMode == .video, !isClosingVideo else {
            return
        }
        isClosingVideo = true
        ActivePlaybackCoordinator.shared.pauseActivePlaybackForNavigation()
        NotificationCenter.default.post(name: .biliPauseActiveVideoPlaybackForNavigation, object: nil)
        closeVideoFallbackTask?.cancel()
        closeVideoFallbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 850_000_000)
            guard !Task.isCancelled, bottomMode == .video, isClosingVideo else { return }
            completeCloseVideoIfNeeded()
        }
    }

    private func cancelCloseVideoIfNeeded() {
        guard bottomMode == .video, isClosingVideo else { return }
        closeVideoFallbackTask?.cancel()
        closeVideoFallbackTask = nil
        isClosingVideo = false
        NotificationCenter.default.post(name: .biliResumeActiveVideoPlaybackAfterCancelledNavigation, object: nil)
    }

    private func completeCloseVideoIfNeeded() {
        guard bottomMode == .video, isClosingVideo else { return }
        closeVideoFallbackTask?.cancel()
        closeVideoFallbackTask = nil
        ActivePlaybackCoordinator.shared.stopActivePlayback()
        NotificationCenter.default.post(name: .biliStopActiveVideoPlayback, object: nil)
        AppOrientationLock.restorePortrait()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            activeVideo = nil
            videoNavigationPath = NavigationPath()
            bottomMode = .root
            isClosingVideo = false
        }
        rootTabBarRestoreRequestID &+= 1
    }

    private static var initialTab: RootTab {
        if argumentValue(after: "--start-live-room") != nil {
            return .live
        }
        if let value = argumentValue(after: "--start-tab"),
           let tab = RootTab(argumentValue: value) {
            return tab
        }
        return .home
    }

    nonisolated private static func argumentValue(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard arguments.indices.contains(valueIndex) else { return nil }
        let value = arguments[valueIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    nonisolated private static func argumentInt(after flag: String) -> Int? {
        argumentValue(after: flag).flatMap(Int.init)
    }

    nonisolated private static func seedVideo(bvid: String) -> VideoItem {
        VideoItem(
            bvid: bvid,
            aid: nil,
            title: "正在加载",
            pic: nil,
            desc: nil,
            duration: nil,
            pubdate: nil,
            owner: nil,
            stat: nil,
            cid: nil,
            pages: nil,
            dimension: nil
        )
    }

    nonisolated private static func seedLiveRoom(roomID: Int) -> LiveRoom {
        LiveRoom(
            roomID: roomID,
            title: "正在进入直播间",
            uname: "直播间",
            uid: nil,
            face: nil,
            cover: nil,
            keyframe: nil,
            online: nil,
            areaName: nil,
            parentAreaName: nil,
            liveStatus: 1
        )
    }
}

private struct NavigationChromeInstaller: UIViewControllerRepresentable {
    let isStandardChromeEnabled: Bool

    func makeUIViewController(context _: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context _: Context) {
        uiViewController.isStandardChromeEnabled = isStandardChromeEnabled
        uiViewController.apply()
    }

    final class Controller: UIViewController {
        var isStandardChromeEnabled = false

        override func loadView() {
            view = ClearPassthroughView()
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            applySoon()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            apply()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            apply()
        }

        func apply() {
            guard isStandardChromeEnabled else { return }
            guard let navigationController = enclosingNavigationController() else { return }
            AppNavigationChrome.applyStandard(to: navigationController.navigationBar)
        }

        private func applySoon() {
            DispatchQueue.main.async { [weak self] in
                self?.apply()
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
    }
}

extension Notification.Name {
    static let biliPauseActiveVideoPlaybackForNavigation = Notification.Name("cc.bili.pauseActiveVideoPlaybackForNavigation")
    static let biliResumeActiveVideoPlaybackAfterCancelledNavigation = Notification.Name("cc.bili.resumeActiveVideoPlaybackAfterCancelledNavigation")
    static let biliStopActiveVideoPlayback = Notification.Name("cc.bili.stopActiveVideoPlayback")
}

@MainActor
private final class RootHomeViewModelHolder: ObservableObject {
    @Published var viewModel: HomeViewModel?

    func configure(api: BiliAPIClient, libraryStore: LibraryStore, initialMode: HomeFeedMode) {
        if viewModel == nil {
            let viewModel = HomeViewModel(api: api, libraryStore: libraryStore, initialMode: initialMode)
            self.viewModel = viewModel
        }
    }
}

private extension View {
    func videoDestinations() -> some View {
        navigationDestination(for: VideoItem.self) { video in
            VideoDetailView(seedVideo: video)
        }
        .navigationDestination(for: VideoOwner.self) { owner in
            UploaderView(owner: owner)
        }
        .navigationDestination(for: LiveRoom.self) { room in
            LiveRoomDetailView(seedRoom: room)
        }
    }
}

private enum AppTab: Hashable {
    case home
    case dynamic
    case live
    case mine
    case search

    var title: String {
        switch self {
        case .home:
            return "首页"
        case .dynamic:
            return "动态"
        case .live:
            return "直播"
        case .mine:
            return "我的"
        case .search:
            return "搜索"
        }
    }
}

private enum BottomTabMode {
    case root
    case video
}

private struct RootTabBarAppearanceInstaller: UIViewControllerRepresentable {
    func makeUIViewController(context _: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context _: Context) {
        controller.applySoon()
    }

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyAppearance()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            applyAppearance()
        }

        func applySoon() {
            DispatchQueue.main.async { [weak self] in
                self?.applyAppearance()
            }
        }

        private func applyAppearance() {
            guard let tabBar = tabBarController?.tabBar ?? enclosingTabBarController()?.tabBar else { return }

            let appearance = UITabBarAppearance()
            appearance.configureWithDefaultBackground()
            appearance.backgroundEffect = UIBlurEffect(style: .systemMaterial)
            appearance.backgroundColor = UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark
                    ? UIColor.black.withAlphaComponent(0.50)
                    : UIColor.systemBackground.withAlphaComponent(0.68)
            }
            appearance.shadowColor = UIColor.label.withAlphaComponent(0.08)

            let normalColor = UIColor.secondaryLabel.withAlphaComponent(0.82)
            let selectedColor = UIColor.systemPink
            configure(appearance.stackedLayoutAppearance, normalColor: normalColor, selectedColor: selectedColor)
            configure(appearance.inlineLayoutAppearance, normalColor: normalColor, selectedColor: selectedColor)
            configure(appearance.compactInlineLayoutAppearance, normalColor: normalColor, selectedColor: selectedColor)

            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
            tabBar.tintColor = selectedColor
            tabBar.unselectedItemTintColor = normalColor
            tabBar.layer.shadowColor = UIColor.black.cgColor
            tabBar.layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.22 : 0.10
            tabBar.layer.shadowRadius = 18
            tabBar.layer.shadowOffset = CGSize(width: 0, height: -3)
        }

        private func configure(
            _ itemAppearance: UITabBarItemAppearance,
            normalColor: UIColor,
            selectedColor: UIColor
        ) {
            itemAppearance.normal.iconColor = normalColor
            itemAppearance.normal.titleTextAttributes = [
                .foregroundColor: normalColor,
                .font: UIFont.systemFont(ofSize: 11.5, weight: .semibold)
            ]
            itemAppearance.selected.iconColor = selectedColor
            itemAppearance.selected.titleTextAttributes = [
                .foregroundColor: selectedColor,
                .font: UIFont.systemFont(ofSize: 11.5, weight: .bold)
            ]
        }

        private func enclosingTabBarController() -> UITabBarController? {
            var responder: UIResponder? = view
            while let current = responder {
                if let tabBarController = current as? UITabBarController {
                    return tabBarController
                }
                responder = current.next
            }
            return nil
        }
    }
}

private enum RootTab: Hashable {
    case home
    case search
    case dynamic
    case live
    case mine

    init?(argumentValue: String) {
        switch argumentValue.lowercased() {
        case "home":
            self = .home
        case "search":
            self = .search
        case "dynamic":
            self = .dynamic
        case "live":
            self = .live
        case "mine":
            self = .mine
        default:
            return nil
        }
    }

    var appTab: AppTab {
        switch self {
        case .home:
            return .home
        case .search:
            return .search
        case .dynamic:
            return .dynamic
        case .live:
            return .live
        case .mine:
            return .mine
        }
    }

    var title: String {
        switch self {
        case .home:
            return "首页"
        case .search:
            return "搜索"
        case .dynamic:
            return "动态"
        case .live:
            return "直播"
        case .mine:
            return "我的"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            return "house"
        case .search:
            return "magnifyingglass"
        case .dynamic:
            return "sparkles"
        case .live:
            return "play.tv"
        case .mine:
            return "person.crop.circle"
        }
    }
}
