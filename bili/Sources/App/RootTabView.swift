import Foundation
import SwiftUI

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var dependencies: AppDependencies
    @StateObject var runtimeSettings = RootRuntimeSettingsStore()
    @StateObject var homeViewModelHolder = RootHomeViewModelHolder()
    @State var selectedTab = Self.initialTab.appTab
    @State var bottomMode: BottomTabMode = .root
    @State var rootTabBarRestoreRequestID = 0
    @State var activeVideo: VideoItem?
    @State var videoNavigationPath = NavigationPath()
    @State var navigationPath = NavigationPath()
    @State var dynamicNavigationPath = NavigationPath()
    @State var liveNavigationPath = NavigationPath()
    @State var mineNavigationPath = NavigationPath()
    @State var searchNavigationPath = NavigationPath()
    @State var didConsumeStartupVideo = false
    @State var didConsumeStartupLiveRoom = false
    @State var isClosingVideo = false
    @State var videoPresentationGeneration = 0
    @State var closeVideoFallbackTask: Task<Void, Never>?
    @State var inAppBrowserItem: InAppBrowserItem?
    @State var recentPlaybackPreloadTimes: [String: Date] = [:]
    let shouldStartDetail = ProcessInfo.processInfo.arguments.contains("--start-detail")
    let startBVID = Self.argumentValue(after: "--start-bvid")
    let startLiveRoomID = Self.argumentInt(after: "--start-live-room")

    var body: some View {
        ZStack {
            TabView(selection: tabSelection) {
                if visibleRootTabs.contains(.home) {
                    Tab(value: AppTab.home) {
                        NavigationStack(path: $navigationPath) {
                            homePage()
                        }
                    } label: {
                        Label(AppTab.home.title, systemImage: AppTab.home.systemImage)
                    }
                }

                if visibleRootTabs.contains(.dynamic) {
                    Tab(value: AppTab.dynamic) {
                        NavigationStack(path: $dynamicNavigationPath) {
                            DynamicView()
                                .videoDestinations()
                        }
                    } label: {
                        Label(AppTab.dynamic.title, systemImage: AppTab.dynamic.systemImage)
                    }
                }

                if visibleRootTabs.contains(.live) {
                    Tab(value: AppTab.live) {
                        NavigationStack(path: $liveNavigationPath) {
                            LiveView()
                                .videoDestinations()
                        }
                    } label: {
                        Label(AppTab.live.title, systemImage: AppTab.live.systemImage)
                    }
                }

                if visibleRootTabs.contains(.mine) {
                    Tab(value: AppTab.mine) {
                        NavigationStack(path: $mineNavigationPath) {
                            MineView()
                                .videoDestinations()
                        }
                    } label: {
                        Label(AppTab.mine.title, systemImage: AppTab.mine.systemImage)
                    }
                }

                Tab(AppTab.search.title, systemImage: AppTab.search.systemImage, value: AppTab.search, role: .search) {
                    NavigationStack(path: $searchNavigationPath) {
                        SearchView()
                            .videoDestinations()
                    }
                }
                .tabPlacement(.pinned)
            }
            .tint(.pink)
            .tabViewSearchActivation(.searchTabSelection)
            .tabBarMinimizeBehavior(runtimeSettings.minimizesTabBarOnScroll ? .onScrollDown : .never)
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
        .animation(.smooth(duration: 0.22), value: runtimeSettings.visibleRootTabs)
        .preferredColorScheme(runtimeSettings.appearanceMode.preferredColorScheme)
        .sheet(item: $inAppBrowserItem) { item in
            InAppBrowserView(url: item.url)
                .ignoresSafeArea()
        }
        .task {
            PictureInPictureRestoreCoordinator.shared.restoreHandler = { video in
                await restoreVideoPlaybackUIForPictureInPicture(video)
            }
            runtimeSettings.bind(dependencies.libraryStore)
            openStartupVideoIfNeeded()
            openStartupLiveRoomIfNeeded()
            dependencies.scheduleDeferredStartupWorkIfNeeded()
        }
        .onChange(of: runtimeSettings.visibleRootTabs) { _, tabs in
            repairSelectedTabIfNeeded(visibleTabs: tabs)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            Task {
                await VideoPreloadCenter.shared.cancelMediaWarmups(clearCache: false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            cancelMediaWarmupsIfEnvironmentConstrained()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.NSProcessInfoPowerStateDidChange)) { _ in
            cancelMediaWarmupsIfEnvironmentConstrained()
        }
        .onReceive(NotificationCenter.default.publisher(for: .biliPlaybackNetworkClassDidChange)) { _ in
            cancelMediaWarmupsIfEnvironmentConstrained()
        }
    }

    private func cancelMediaWarmupsIfEnvironmentConstrained() {
        let environment = PlaybackEnvironment.current
        guard environment.shouldPreferConservativePlayback || environment.isThermallyElevated else { return }
        Task {
            await VideoPreloadCenter.shared.cancelMediaWarmups(clearCache: false)
        }
    }

    @ViewBuilder
    private func homePage() -> some View {
        if let viewModel = homeViewModelHolder.viewModel {
            HomeView(
                viewModel: viewModel,
                detailPath: $navigationPath,
                launchConfiguration: HomeFeedLaunchConfiguration(
                    autoOpenDetail: shouldAutoOpenDetail,
                    startVideo: startBVID.map(Self.seedVideo),
                    onVideoSelect: openVideo
                )
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
                        sessionStore: dependencies.sessionStore,
                        initialMode: .recommend
                    )
                }
        }
    }

}
