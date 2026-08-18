import Foundation
import SwiftUI

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var dependencies: AppDependencies
    @EnvironmentObject var libraryStore: LibraryStore
    @StateObject var runtimeSettings = RootRuntimeSettingsStore()
    @StateObject var homeViewModelHolder = RootHomeViewModelHolder()
    @StateObject var mineViewModelHolder = MineViewModelHolder()
    @StateObject var searchBottomAccessoryStore = SearchBottomAccessoryStore()
    @State var selectedTab = Self.initialTab.appTab
    @State var bottomMode: BottomTabMode = .root
    @State var rootTabBarRestoreRequestID = 0
    @State var activeVideo: VideoItem?
    @State var videoNavigationPath = NavigationPath()
    @State var rootNavigationPath = NavigationPath()
    @State var didConsumeStartupVideo = false
    @State var didConsumeStartupLiveRoom = false
    @State var didConsumeStartupUploader = false
    @State var isClosingVideo = false
    @State var closeVideoFallbackTask: Task<Void, Never>?
    @State var inAppBrowserItem: InAppBrowserItem?
    @State var recentPlaybackPreloadTimes: [String: Date] = [:]
    let shouldStartDetail = ProcessInfo.processInfo.arguments.contains("--start-detail")
    let startBVID = Self.argumentValue(after: "--start-bvid")
    let startLiveRoomID = Self.argumentInt(after: "--start-live-room")
    let startUploaderMID = Self.argumentInt(after: "--start-uploader-mid")

    var body: some View {
        ZStack {
            rootNavigationStack

            if bottomMode == .video {
                videoNavigationHost()
                    .ignoresSafeArea()
                    .transition(.identity)
                    .zIndex(2)
            }
        }
        .environment(\.openVideoAction, openVideo)
        .environment(\.openLiveRoomAction, openLiveRoom)
        .environment(\.prewarmVideoRouteAction, beginPlaybackPreload)
        .environment(\.openPgcSeasonRouteAction, openPgcSeasonRoute)
        .environment(\.openVideoOwnerRouteAction, openVideoOwnerRoute)
        .environment(\.openAppURLAction, openAppURL)
        .environment(\.appThemeTintColor, libraryStore.appTintColor)
        .environment(\.showsVideoCoverDurationBadges, libraryStore.showsVideoCoverDurationBadges)
        .environment(\.scrollEdgeEffectPreference, runtimeSettings.scrollEdgeEffectPreference)
        .environment(\.openURL, OpenURLAction { url in
            guard AppLinkRouter.canHandle(url) else { return .systemAction }
            openAppURL(url)
            return .handled
        })
        .background(NavigationChromeInstaller(isStandardChromeEnabled: bottomMode == .video))
        .animation(.smooth(duration: 0.28), value: bottomMode)
        .preferredColorScheme(runtimeSettings.appearanceMode.preferredColorScheme)
        .sheet(item: $inAppBrowserItem) { item in
            InAppBrowserView(url: item.url)
                .ignoresSafeArea()
        }
        .task {
            AppIconController.apply(libraryStore.appIconPreference)
            PictureInPictureRestoreCoordinator.shared.restoreHandler = { video in
                await restoreVideoPlaybackUIForPictureInPicture(video)
            }
            runtimeSettings.bind(dependencies.libraryStore)
            repairSelectedTabIfNeeded(visibleTabs: runtimeSettings.visibleRootTabs)
            openStartupVideoIfNeeded()
            openStartupLiveRoomIfNeeded()
            openStartupUploaderIfNeeded()
            dependencies.scheduleDeferredStartupWorkIfNeeded()
        }
        .task(id: homeMessageUnreadRefreshTaskID) {
            await refreshHomeMessageUnreadIfNeeded()
        }
        .onChange(of: runtimeSettings.visibleRootTabs) { _, tabs in
            repairSelectedTabIfNeeded(visibleTabs: tabs)
        }
        .onChange(of: libraryStore.appIconPreference) { _, preference in
            AppIconController.apply(preference)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task {
                    await refreshHomeMessageUnreadIfNeeded()
                }
            case .background:
                Task {
                    await VideoPreloadCenter.shared.cancelMediaWarmups(clearCache: false)
                }
            default:
                break
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

    private var rootNavigationStack: some View {
        NavigationStack(path: $rootNavigationPath) {
            rootTabBar
                .navigationDestination(for: MineOverlayRoute.self) { route in
                    RootMineNavigationDestination(
                        route: route,
                        holder: mineViewModelHolder,
                        libraryStore: libraryStore,
                        sessionStore: dependencies.sessionStore,
                        api: dependencies.api
                    )
                }
                .videoDestinations(hidesRootTabBar: false)
        }
    }

    private var rootTabBar: some View {
        TabView(selection: tabSelection) {
            ForEach(visibleRootTabs) { tab in
                Tab(value: tab) {
                    rootTabContent(for: tab)
                } label: {
                    Label(tab.title, systemImage: tab.systemImage)
                }
            }
        }
        .tint(libraryStore.appTintColor)
        .tabViewBottomAccessory(isEnabled: showsSearchBottomAccessory) {
            SearchTabBottomAccessory(store: searchBottomAccessoryStore)
        }
        .tabBarMinimizeBehavior(rootTabBarMinimizeBehavior)
        .restoresRootTabBarWhenRequested(requestID: rootTabBarRestoreRequestID)
        .background(RootTabBarAppearanceInstaller(tintColorHex: libraryStore.appTintColorHex))
    }

    private var showsSearchBottomAccessory: Bool {
        guard visibleRootTabs.contains(.search),
              selectedTab == .search,
              searchBottomAccessoryStore.viewModel != nil,
              !searchBottomAccessoryStore.isSearchFocused else {
            return false
        }
        // Keep the accessory alive under pushed and overlay detail pages so it does not reappear late on return.
        return true
    }

    private var rootTabBarMinimizeBehavior: TabBarMinimizeBehavior {
        if selectedTab == .search {
            return .onScrollDown
        }
        return runtimeSettings.minimizesTabBarOnScroll ? .onScrollDown : .never
    }

    private func cancelMediaWarmupsIfEnvironmentConstrained() {
        let environment = PlaybackEnvironment.current
        guard environment.shouldPreferConservativePlayback || environment.isThermallyElevated else { return }
        Task {
            await VideoPreloadCenter.shared.cancelMediaWarmups(clearCache: false)
        }
    }

    @ViewBuilder
    private func homePage(detailPath: Binding<NavigationPath>) -> some View {
        if let viewModel = homeViewModelHolder.viewModel {
            HomeView(
                viewModel: viewModel,
                detailPath: detailPath,
                launchConfiguration: HomeFeedLaunchConfiguration(
                    autoOpenDetail: shouldAutoOpenDetail,
                    startVideo: startBVID.map(Self.seedVideo),
                    onVideoSelect: openVideo
                ),
                accountMessageViewModel: mineViewModelHolder.accountMessageViewModel,
                onOpenAccountMessages: {
                    openMineOverlayRoute(.accountMessages)
                }
            )
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
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

    @ViewBuilder
    private func rootTabContent(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            homePage(detailPath: $rootNavigationPath)
        case .dynamic:
            DynamicView()
        case .live:
            LiveView()
        case .mine:
            MineView(
                holder: mineViewModelHolder,
                onOpenRoute: openMineOverlayRoute
            )
        case .search:
            SearchView(accessoryStore: searchBottomAccessoryStore)
        }
    }

    private var homeMessageUnreadRefreshTaskID: HomeMessageUnreadRefreshTaskID {
        HomeMessageUnreadRefreshTaskID(
            homeNavigationExperimentEnabled: libraryStore.homeNavigationModeSwitcherExperimentEnabled,
            credentialVersion: dependencies.sessionStore.playbackCredentialVersion
        )
    }

    private func refreshHomeMessageUnreadIfNeeded() async {
        guard libraryStore.homeNavigationModeSwitcherExperimentEnabled else {
            return
        }
        mineViewModelHolder.configure(
            api: dependencies.api,
            sessionStore: dependencies.sessionStore,
            accountMessageService: dependencies.accountMessageService
        )
        guard dependencies.sessionStore.isLoggedIn,
              let accountMessageViewModel = mineViewModelHolder.accountMessageViewModel
        else {
            return
        }
        await accountMessageViewModel.refreshUnread()
    }
}

private struct HomeMessageUnreadRefreshTaskID: Hashable {
    let homeNavigationExperimentEnabled: Bool
    let credentialVersion: Int
}
