import Foundation
import SwiftUI

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var dependencies: AppDependencies
    @EnvironmentObject var libraryStore: LibraryStore
    @StateObject var runtimeSettings = RootRuntimeSettingsStore()
    @StateObject var homeViewModelHolder = RootHomeViewModelHolder()
    @StateObject var mineViewModelHolder = MineViewModelHolder()
    @StateObject var searchViewModelHolder = SearchViewModelHolder()
    @StateObject var searchBottomAccessoryStore = SearchBottomAccessoryStore()
    @State var selectedTab = Self.initialTab.appTab
    @State var homeNavigationPath = NavigationPath()
    @State var searchNavigationPath = NavigationPath()
    @State var dynamicNavigationPath = NavigationPath()
    @State var liveNavigationPath = NavigationPath()
    @State var mineNavigationPath = NavigationPath()
    @State var rootSearchQueryBuffer = ""
    @State var rootNavigationTitleHiddenByTab: [AppTab: Bool] = [:]
    @State var homeActionStore = HomeFeedScreenActionStore()
    @State var didConsumeStartupVideo = false
    @State var didConsumeStartupLiveRoom = false
    @State var didConsumeStartupUploader = false
    @State var inAppBrowserItem: InAppBrowserItem?
    @State var recentPlaybackPreloadGate = RecentPlaybackPreloadGate()
    let shouldStartDetail = ProcessInfo.processInfo.arguments.contains("--start-detail")
    let startBVID = Self.argumentValue(after: "--start-bvid")
    let startLiveRoomID = Self.argumentInt(after: "--start-live-room")
    let startUploaderMID = Self.argumentInt(after: "--start-uploader-mid")

    var body: some View {
        rootTabBar
        .environment(\.openVideoAction, openVideo)
        .environment(\.openLiveRoomAction, openLiveRoom)
        .environment(\.prewarmVideoRouteAction, beginPlaybackPreload)
        .environment(\.openPgcSeasonRouteAction, openPgcSeasonRoute)
        .environment(\.openVideoOwnerRouteAction, openVideoOwnerRoute)
        .environment(\.openAppURLAction, openAppURL)
        .environment(\.appThemeTintColor, libraryStore.appTintColor)
        .environment(
            \.usesDynamicDetailCommentSpacing,
            libraryStore.dynamicDetailCommentSpacingExperimentEnabled
        )
        .environment(\.showsVideoCoverDurationBadges, libraryStore.showsVideoCoverDurationBadges)
        .environment(\.openURL, OpenURLAction { url in
            guard AppLinkRouter.canHandle(url) else { return .systemAction }
            openAppURL(url)
            return .handled
        })
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
            mineViewModelHolder.configure(
                api: dependencies.api,
                sessionStore: dependencies.sessionStore,
                accountMessageService: dependencies.accountMessageService
            )
            configureSearchViewModelIfNeeded()
            repairSelectedTabIfNeeded(visibleTabs: runtimeSettings.visibleRootTabs)
            openStartupVideoIfNeeded()
            openStartupLiveRoomIfNeeded()
            openStartupUploaderIfNeeded()
            dependencies.scheduleStartupWorkIfNeeded()
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

    private var rootTabBar: some View {
        TabView(selection: tabSelection) {
            ForEach(visibleRootTabs) { tab in
                Tab(value: tab) {
                    rootTabNavigationStack(
                        for: tab,
                        detailPath: rootNavigationPathBinding(for: tab)
                    )
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
        .background(
            RootTabBarAppearanceInstaller(
                tintColorHex: libraryStore.appTintColorHex,
                glassStyle: libraryStore.videoDetailSegmentedPickerGlassStyle
            )
        )
    }

    @ViewBuilder
    private func rootTabNavigationStack(
        for tab: AppTab,
        detailPath: Binding<NavigationPath>
    ) -> some View {
        NavigationStack(path: detailPath) {
            rootTabContentWithChrome(for: tab, detailPath: detailPath)
                .toolbarVisibility(.visible, for: .navigationBar)
                .toolbarBackground(.automatic, for: .navigationBar)
                .navigationTitle(rootNavigationTitle(for: tab))
                .toolbarTitleDisplayMode(.inline)
                .environment(
                    \.rootNavigationTitleHidden,
                    rootNavigationTitleBinding(for: tab, detailPath: detailPath)
                )
                .navigationDestination(for: MineOverlayRoute.self) { route in
                    RootMineNavigationDestination(
                        route: route,
                        holder: mineViewModelHolder,
                        libraryStore: libraryStore,
                        sessionStore: dependencies.sessionStore,
                        api: dependencies.api
                    )
                }
                .videoDestinations()
                .dynamicDetailDestinations(
                    path: detailPath,
                    api: dependencies.api
                )
        }
        .coordinatesRootTabBarTransitions(
            isDetailPresented: !detailPath.wrappedValue.isEmpty
        )
    }

    @ViewBuilder
    private func rootTabContentWithChrome(
        for tab: AppTab,
        detailPath: Binding<NavigationPath>
    ) -> some View {
        Group {
            if tab == .home, let viewModel = homeViewModelHolder.viewModel {
                rootTabContent(for: tab, detailPath: detailPath)
                    .homeFeedNavigationChrome(
                        viewModel: viewModel,
                        modeActions: homeActionStore.mode,
                        scrollActions: homeActionStore.scroll,
                        nativeRefreshActionStore: homeActionStore.nativeRefresh,
                        accountMessageViewModel: mineViewModelHolder.accountMessageViewModel,
                        isDetailPresented: !detailPath.wrappedValue.isEmpty,
                        onOpenAccountMessages: {
                            openMineOverlayRoute(.accountMessages)
                        }
                    )
            } else {
                rootTabContent(for: tab, detailPath: detailPath)
            }
        }
        .nativeNavigationSearch(
            text: rootSearchQueryBinding,
            isPresented: $searchBottomAccessoryStore.isSearchFocused,
            isKeyboardVisible: $searchBottomAccessoryStore.isKeyboardVisible,
            isEnabled: tab == .search
                && selectedTab == .search
                && detailPath.wrappedValue.isEmpty,
            prompt: searchViewModelHolder.viewModel?.searchPrompt ?? "搜索",
            title: "搜索",
            onSubmit: submitRootSearch
        )
    }

    @ViewBuilder
    private func rootTabContent(
        for tab: AppTab,
        detailPath: Binding<NavigationPath>
    ) -> some View {
        switch tab {
        case .home:
            homePage(detailPath: detailPath)
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
            SearchView(
                holder: searchViewModelHolder,
                accessoryStore: searchBottomAccessoryStore
            )
        }
    }

    private func rootNavigationTitle(for tab: AppTab) -> String {
        if tab == .home { return "" }
        return rootNavigationTitleHiddenByTab[tab] == true ? "" : tab.title
    }

    private func rootNavigationTitleBinding(
        for tab: AppTab,
        detailPath: Binding<NavigationPath>
    ) -> Binding<Bool> {
        Binding(
            get: { rootNavigationTitleHiddenByTab[tab] ?? false },
            set: { isHidden in
                guard detailPath.wrappedValue.isEmpty else { return }
                rootNavigationTitleHiddenByTab[tab] = isHidden
            }
        )
    }

    private var rootTabBarMinimizeBehavior: TabBarMinimizeBehavior {
        if selectedTab == .search {
            return .onScrollDown
        }
        return runtimeSettings.minimizesTabBarOnScroll ? .onScrollDown : .never
    }

    private var showsSearchBottomAccessory: Bool {
        guard visibleRootTabs.contains(.search),
              selectedTab == .search,
              searchNavigationPath.isEmpty,
              searchBottomAccessoryStore.viewModel != nil else {
            return false
        }
        return !searchBottomAccessoryStore.usesKeyboardControls
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
                actionStore: homeActionStore,
                showsNavigationChrome: false,
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

    private var rootSearchQueryBinding: Binding<String> {
        Binding(
            get: { searchViewModelHolder.viewModel?.query ?? rootSearchQueryBuffer },
            set: { query in
                rootSearchQueryBuffer = query
                guard let viewModel = searchViewModelHolder.viewModel else { return }
                viewModel.query = query
                viewModel.queryChanged()
            }
        )
    }

    private func configureSearchViewModelIfNeeded() {
        searchViewModelHolder.configure(api: dependencies.api)
        guard let viewModel = searchViewModelHolder.viewModel else { return }
        if !rootSearchQueryBuffer.isEmpty, viewModel.query != rootSearchQueryBuffer {
            viewModel.query = rootSearchQueryBuffer
            viewModel.queryChanged()
        } else {
            rootSearchQueryBuffer = viewModel.query
        }
    }

    private func submitRootSearch() {
        guard let viewModel = searchViewModelHolder.viewModel else { return }
        Task { await viewModel.search() }
    }

    var activeRootNavigationPathIsEmpty: Bool {
        activeRootNavigationPath.wrappedValue.isEmpty
    }

    var activeRootNavigationPathCount: Int {
        activeRootNavigationPath.wrappedValue.count
    }

    func appendActiveRootRoute<Route: Hashable>(_ route: Route) {
        activeRootNavigationPath.wrappedValue.append(route)
    }

    func replaceActiveRootNavigationPath(with path: NavigationPath) {
        activeRootNavigationPath.wrappedValue = path
    }

    func removeLastRootRoute() {
        let path = activeRootNavigationPath
        guard !path.wrappedValue.isEmpty else { return }
        path.wrappedValue.removeLast()
    }

    private var activeRootNavigationPath: Binding<NavigationPath> {
        rootNavigationPathBinding(for: selectedTab)
    }

    private func rootNavigationPathBinding(for tab: AppTab) -> Binding<NavigationPath> {
        switch tab {
        case .home:
            return $homeNavigationPath
        case .search:
            return $searchNavigationPath
        case .dynamic:
            return $dynamicNavigationPath
        case .live:
            return $liveNavigationPath
        case .mine:
            return $mineNavigationPath
        }
    }

    private var homeMessageUnreadRefreshTaskID: HomeMessageUnreadRefreshTaskID {
        HomeMessageUnreadRefreshTaskID(
            credentialVersion: dependencies.sessionStore.playbackCredentialVersion
        )
    }

    private func refreshHomeMessageUnreadIfNeeded() async {
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
    let credentialVersion: Int
}

@MainActor
final class RecentPlaybackPreloadGate {
    private var recentTimes: [String: Date] = [:]

    func shouldBeginPreload(for bvid: String, now: Date = Date()) -> Bool {
        if let lastPreload = recentTimes[bvid],
           now.timeIntervalSince(lastPreload) < 1.2 {
            return false
        }

        recentTimes[bvid] = now
        recentTimes = recentTimes.filter { now.timeIntervalSince($0.value) < 8 }
        if recentTimes.count > 16 {
            let keptKeys = Set(
                recentTimes
                    .sorted { $0.value > $1.value }
                    .prefix(16)
                    .map(\.key)
            )
            recentTimes = recentTimes.filter { keptKeys.contains($0.key) }
        }
        return true
    }
}
