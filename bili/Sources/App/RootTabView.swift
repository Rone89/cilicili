import SwiftUI
import Combine
import UIKit

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
                        .labelStyle(.iconOnly)
                }

                Tab(value: AppTab.dynamic) {
                    NavigationStack {
                        DynamicView()
                            .videoDestinations()
                    }
                } label: {
                    Label(RootTab.dynamic.title, systemImage: RootTab.dynamic.systemImage)
                        .labelStyle(.iconOnly)
                }

                Tab(value: AppTab.mine) {
                    NavigationStack {
                        MineView()
                            .videoDestinations()
                    }
                } label: {
                    Label(RootTab.mine.title, systemImage: RootTab.mine.systemImage)
                        .labelStyle(.iconOnly)
                }

                Tab(value: AppTab.search, role: .search) {
                    NavigationStack {
                        SearchView()
                            .videoDestinations()
                    }
                } label: {
                    Label(RootTab.search.title, systemImage: RootTab.search.systemImage)
                        .labelStyle(.iconOnly)
                }
            }
            .tint(.pink)
            .liquidGlassTabBarBackground()

            if bottomMode == .video {
                videoNavigationHost()
                    .ignoresSafeArea()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .environment(\.openVideoAction, openVideo)
        .background(NavigationChromeInstaller(isStandardChromeEnabled: bottomMode == .video))
        .animation(.smooth(duration: 0.28), value: bottomMode)
        .animation(.smooth(duration: 0.22), value: selectedTab)
        .preferredColorScheme(libraryStore.appearanceMode.preferredColorScheme)
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
        !didConsumeStartupVideo && (shouldStartDetail || startBVID != nil)
    }

    private func videoNavigationHost() -> some View {
        NavigationStack(path: $videoNavigationPath) {
            Color.clear
                .background(VideoNavigationHostTransparency())
                .navigationDestination(for: VideoItem.self) { video in
                    VideoDetailView(
                        seedVideo: video,
                        hidesRootTabBar: false
                    )
                    .navigationDestination(for: VideoOwner.self) { owner in
                        UploaderView(owner: owner)
                    }
                    .navigationDestination(for: LiveRoom.self) { room in
                        LiveRoomDetailView(seedRoom: room)
                    }
                }
        }
        .background(VideoNavigationHostTransparency())
        .onAppear {
            ensureVideoPath()
        }
        .onChange(of: videoNavigationPath) { _, newPath in
            guard bottomMode == .video, newPath.isEmpty else { return }
            scheduleCloseVideo()
        }
    }

    private func openVideo(_ video: VideoItem) {
        if bottomMode == .video {
            pushVideo(video)
            return
        }

        withAnimation(.smooth(duration: 0.32)) {
            didConsumeStartupVideo = true
            isClosingVideo = false
            activeVideo = video
            videoNavigationPath = NavigationPath([video])
            bottomMode = .video
        }
    }

    private func pushVideo(_ video: VideoItem) {
        withAnimation(.smooth(duration: 0.28)) {
            didConsumeStartupVideo = true
            isClosingVideo = false
            activeVideo = video
            videoNavigationPath.append(video)
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

    private func ensureVideoPath() {
        guard bottomMode == .video,
              videoNavigationPath.isEmpty,
              let activeVideo
        else { return }

        DispatchQueue.main.async {
            guard bottomMode == .video,
                  videoNavigationPath.isEmpty
            else { return }

            withAnimation(.smooth(duration: 0.28)) {
                videoNavigationPath.append(activeVideo)
            }
        }
    }

    private func scheduleCloseVideo() {
        guard bottomMode == .video, !isClosingVideo else {
            return
        }

        isClosingVideo = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            guard bottomMode == .video else { return }
            completeCloseVideo()
        }
    }

    private func completeCloseVideo() {
        withAnimation(.smooth(duration: 0.30)) {
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
