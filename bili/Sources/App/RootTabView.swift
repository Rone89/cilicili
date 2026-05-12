import SwiftUI
import Combine

struct RootTabView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    @StateObject private var homeViewModelHolder = RootHomeViewModelHolder()
    @State private var selectedTab = Self.initialTab.appTab
    @State private var bottomMode: BottomTabMode = .root
    @State private var activeVideo: VideoItem?
    @State private var videoNavigationPath = NavigationPath()
    @State private var navigationPath = NavigationPath()
    @State private var didConsumeStartupVideo = false
    @State private var isClosingVideo = false
    private let shouldStartDetail = ProcessInfo.processInfo.arguments.contains("--start-detail")
    private let startBVID = Self.argumentValue(after: "--start-bvid")

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
                    NavigationStack {
                        DynamicView()
                            .videoDestinations()
                    }
                } label: {
                    Label(RootTab.dynamic.title, systemImage: RootTab.dynamic.systemImage)
                }

                Tab(value: AppTab.mine) {
                    NavigationStack {
                        MineView()
                            .videoDestinations()
                    }
                } label: {
                    Label(RootTab.mine.title, systemImage: RootTab.mine.systemImage)
                }

                Tab(value: AppTab.search, role: .search) {
                    NavigationStack {
                        SearchView()
                            .videoDestinations()
                    }
                } label: {
                    Label(RootTab.search.title, systemImage: RootTab.search.systemImage)
                }
            }
            .tint(.pink)
            .tabBarMinimizeBehavior(.onScrollDown)
            .liquidGlassTabBarBackground()

            if bottomMode == .video {
                videoNavigationHost()
                    .ignoresSafeArea()
                    .transition(.identity)
                    .zIndex(1)
            }
        }
        .environment(\.openVideoAction, openVideo)
        .background(NavigationChromeInstaller(isStandardChromeEnabled: bottomMode == .video))
        .animation(.smooth(duration: 0.28), value: bottomMode)
        .animation(.smooth(duration: 0.22), value: selectedTab)
        .preferredColorScheme(libraryStore.appearanceMode.preferredColorScheme)
        .task {
            openStartupVideoIfNeeded()
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
                        libraryStore: libraryStore,
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

    private func videoNavigationHost() -> some View {
        NavigationStack(path: $videoNavigationPath) {
            Color.clear
                .ignoresSafeArea()
                .background(VideoNavigationHostTransparency(suppressesNavigationBar: true))
                .navigationTitle(selectedTab.title)
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
        .background(VideoNavigationTransitionObserver(isClosing: isClosingVideo) {
            completeCloseVideoIfNeeded()
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
        ActivePlaybackCoordinator.shared.stopActivePlayback()
        NotificationCenter.default.post(name: .biliStopActiveVideoPlayback, object: nil)
        beginPlaybackPreload(for: video)
        withAnimation(.smooth(duration: 0.28)) {
            didConsumeStartupVideo = true
            isClosingVideo = false
            videoNavigationPath.append(video)
        }
    }

    private func beginPlaybackPreload(for video: VideoItem) {
        Task { [preferredQuality = libraryStore.preferredVideoQuality, api = dependencies.api] in
            await VideoPreloadCenter.shared.updatePlaybackPreferences(preferredQuality: preferredQuality)
            await VideoPreloadCenter.shared.prioritizePlayback(for: video)
            await VideoPreloadCenter.shared.preloadPlayInfo(
                video,
                api: api,
                preferredQuality: preferredQuality,
                priority: .userInitiated,
                warmsMedia: true
            )
        }
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
        ActivePlaybackCoordinator.shared.stopActivePlayback()
        NotificationCenter.default.post(name: .biliStopActiveVideoPlayback, object: nil)

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

        ActivePlaybackCoordinator.shared.stopActivePlayback()
        NotificationCenter.default.post(name: .biliStopActiveVideoPlayback, object: nil)
        isClosingVideo = true
    }

    private func completeCloseVideoIfNeeded() {
        guard bottomMode == .video, isClosingVideo else { return }
        AppOrientationLock.restorePortrait()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            activeVideo = nil
            videoNavigationPath = NavigationPath()
            bottomMode = .root
            isClosingVideo = false
        }
    }

    private static var initialTab: RootTab {
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
    static let biliStopActiveVideoPlayback = Notification.Name("cc.bili.stopActiveVideoPlayback")
}

@MainActor
private final class RootHomeViewModelHolder: ObservableObject {
    @Published var viewModel: HomeViewModel?
    private var cancellable: AnyCancellable?

    func configure(api: BiliAPIClient, libraryStore: LibraryStore, initialMode: HomeFeedMode) {
        if viewModel == nil {
            let viewModel = HomeViewModel(api: api, libraryStore: libraryStore, initialMode: initialMode)
            self.viewModel = viewModel
            cancellable = viewModel.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
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
    case mine
    case search

    var title: String {
        switch self {
        case .home:
            return "首页"
        case .dynamic:
            return "动态"
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

private enum RootTab: Hashable {
    case home
    case search
    case dynamic
    case mine

    init?(argumentValue: String) {
        switch argumentValue.lowercased() {
        case "home":
            self = .home
        case "search":
            self = .search
        case "dynamic":
            self = .dynamic
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
        case .mine:
            return "person.crop.circle"
        }
    }
}
