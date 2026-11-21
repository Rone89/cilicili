import Foundation
import SwiftUI

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var usesVideoStatusBarContrast = false
    @State private var videoContentColorScheme: ColorScheme?
    @EnvironmentObject var dependencies: AppDependencies
    @EnvironmentObject var libraryStore: LibraryStore
    @StateObject var runtimeSettings = RootRuntimeSettingsStore()
    @StateObject var homeViewModelHolder = RootHomeViewModelHolder()
    @StateObject var mineViewModelHolder = MineViewModelHolder()
    @StateObject var searchViewModelHolder = SearchViewModelHolder()
    @StateObject var searchBottomAccessoryStore = SearchBottomAccessoryStore()
    @State var hostedRootTabs: [AppTab]?
    @State var openedHiddenRootPage = false
    @State var selectedTab = Self.initialTab == .live ? .home : Self.initialTab.appTab
    @State var showsHomeLiveFeed = Self.initialTab == .live
    @State var rootTabScrollRequests: [AppTab: RootTabScrollRequest] = [:]
    @State var homeNavigationPath = NavigationPath()
    @State var searchNavigationPath = NavigationPath()
    @State var dynamicNavigationPath = NavigationPath()
    @State var liveNavigationPath = NavigationPath()
    @State var mineNavigationPath = NavigationPath()
    @State var rootSearchQueryBuffer = ""
    @FocusState private var isRootSearchFocused: Bool
    @State var mineSearchQuery = ""
    @FocusState var isMineSearchFocused: Bool
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
        .environment(\.videoDetailActionButtonStyle, libraryStore.videoDetailActionButtonStyle)
        .environment(\.showsVideoCoverDurationBadges, libraryStore.showsVideoCoverDurationBadges)
        .environment(\.openURL, OpenURLAction { url in
            guard AppLinkRouter.canHandle(url) else { return .systemAction }
            openAppURL(url)
            return .handled
        })
        .environment(
            \.colorScheme,
            runtimeSettings.appearanceMode.preferredColorScheme
                ?? videoContentColorScheme ?? systemColorScheme
        )
        .preferredColorScheme(usesVideoStatusBarContrast ? .dark : runtimeSettings.appearanceMode.preferredColorScheme)
        .onPreferenceChange(VideoDetailStatusBarContrastPreferenceKey.self) { active in
            guard usesVideoStatusBarContrast != active else { return }
            videoContentColorScheme = active ? systemColorScheme : nil
            usesVideoStatusBarContrast = active
        }
        .sheet(item: $inAppBrowserItem) { item in
            InAppBrowserView(url: item.url)
                .ignoresSafeArea()
        }
        .environment(
            \.appContentColorScheme,
            runtimeSettings.appearanceMode.preferredColorScheme
                ?? videoContentColorScheme ?? systemColorScheme
        )
        .task {
            // Let the initial tab hierarchy commit a frame before configuring
            // nonessential feature holders and startup maintenance. Otherwise a
            // cold launch can present only the window background while this
            // work occupies the main actor.
            await Task.yield()
            guard !Task.isCancelled else { return }

            AppIconController.apply(libraryStore.appIconPreference)
            PictureInPictureRestoreCoordinator.shared.restoreHandler = { video in
                await restoreVideoPlaybackUIForPictureInPicture(video)
            }
            runtimeSettings.bind(dependencies.libraryStore)
            hostedRootTabs = runtimeSettings.visibleRootTabs
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
            // Keep the mounted navigation hierarchy stable throughout settings
            // edits; apply its new tab configuration after returning to a root.
            guard activeRootNavigationPathIsEmpty else { return }
            repairSelectedTabIfNeeded(visibleTabs: tabs)
            hostedRootTabs = tabs
        }
        .onChange(of: activeRootNavigationPathCount) { _, count in
            if count == 0 {
                repairSelectedTabIfNeeded(visibleTabs: visibleRootTabs)
                hostedRootTabs = visibleRootTabs
            }
        }
        .onChange(of: selectedTab) { _, tab in
            if tab != .search {
                isRootSearchFocused = false
            }
            if tab != .mine {
                isMineSearchFocused = false
            }
        }
        .onChange(of: searchNavigationPath.count) { _, count in
            if count > 0 {
                isRootSearchFocused = false
            }
        }
        .onChange(of: mineNavigationPath.count) { _, count in
            if count > 0 {
                isMineSearchFocused = false
            }
        }
        .onChange(of: isRootSearchFocused) { _, isFocused in
            searchBottomAccessoryStore.isSearchFocused = isFocused
        }
        .onChange(of: searchViewModelHolder.viewModel?.query) { _, query in
            rootSearchQueryBuffer = query ?? ""
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
        Group {
            if displayedRootTabs == [.home] {
                // There is no tab switcher in the one-page configuration. A plain
                // navigation stack cannot resurrect a tab bar during a pop.
                rootTabSlot(.home)
            } else {
                TabView(selection: tabSelection) {
                    ForEach(displayedRootTabs) { tab in
                        Tab(value: tab, role: tab == .search ? .search : nil) {
                            rootTabSlot(tab)
                        } label: {
                            Label(tab.title, systemImage: tab.systemImage)
                        }
                    }
                }
                .adaptiveRootTabViewStyle(isEnabled: runtimeSettings.adaptiveLargeScreenLayoutExperimentEnabled)
            }
        }
        .toolbarVisibility(visibleRootTabs.count == 1 ? .hidden : .automatic, for: .tabBar)
        .tint(libraryStore.appTintColor)
        .tabBarMinimizeBehavior(rootTabBarMinimizeBehavior)
    }

    private func rootTabSlot(_ tab: AppTab) -> some View {
        let page = tab == .home && isShowingHiddenRootPage ? selectedTab : tab
        return rootTabNavigationStack(
            for: page,
            detailPath: rootNavigationPathBinding(for: page),
            showsPageSwitcher: page != tab
        )
        .id(page)
    }

    @ViewBuilder
    private func rootTabNavigationStack(
        for tab: AppTab,
        detailPath: Binding<NavigationPath>,
        showsPageSwitcher: Bool
    ) -> some View {
        let usesTransparentPlaybackNavigationBar = [.home, .mine, .search, .live].contains(tab)
            || (tab == .dynamic && (libraryStore.visibleDynamicFeedKinds.count > 1 || showsPageSwitcher))
        let navigationBarColorScheme = runtimeSettings.appearanceMode.preferredColorScheme
            ?? videoContentColorScheme ?? systemColorScheme
        NavigationStack(path: detailPath) {
            rootTabContentWithChrome(for: tab, detailPath: detailPath)
                .environment(\.rootTabScrollRequest, rootTabScrollRequests[tab])
                .environment(\.showsHiddenRootPageSwitcher, showsPageSwitcher)
                .environment(
                    \.rootHiddenPageSwitcher,
                    showsPageSwitcher && [.search, .mine].contains(tab)
                        ? RootHiddenPageSwitcher(
                            currentPage: tab,
                            pages: [.home] + hiddenRootPages,
                            onSelect: { selectRootPageFromMenu($0) }
                        )
                        : nil
                )
                .toolbarBackground(.automatic, for: .navigationBar)
                .toolbarColorScheme(navigationBarColorScheme, for: .navigationBar)
                .navigationTitle("")
                .navigationHistoryTitle(tab.title)
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    if showsPageSwitcher && ![.search, .mine].contains(tab) {
                        ToolbarSpacer(.fixed, placement: .topBarTrailing)
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu("切换页面", systemImage: "line.3.horizontal.decrease") {
                                ForEach([AppTab.home] + hiddenRootPages) { page in
                                    Button {
                                        selectRootPageFromMenu(page)
                                    } label: {
                                        Label(page.title, systemImage: page == tab ? "checkmark" : page.systemImage)
                                    }
                                }
                            }
                            .labelStyle(.iconOnly)
                            .tint(.primary)
                            .accessibilityIdentifier("root.hiddenPageSwitcher")
                        }
                    }
                }
                .navigationDestination(for: MineOverlayRoute.self) { route in
                    RootMineNavigationDestination(
                        route: route,
                        holder: mineViewModelHolder,
                        libraryStore: libraryStore,
                        sessionStore: dependencies.sessionStore,
                        api: dependencies.api
                    )
                    .toolbarColorScheme(navigationBarColorScheme, for: .navigationBar)
                    .navigationHistoryTitle(route.navigationDisplayTitle)
                }
                .videoDestinations(
                    usesTransparentNavigationBar: usesTransparentPlaybackNavigationBar,
                    navigationBarColorScheme: navigationBarColorScheme
                )
                .dynamicDetailDestinations(
                    path: detailPath,
                    api: dependencies.api
                )
        }
        .coordinatesRootTabBarTransitions(
            isDetailPresented: !detailPath.wrappedValue.isEmpty,
            hidesRootTabBar: visibleRootTabs.count == 1,
            onRootTabTap: selectedTab == tab ? { tabSelection.wrappedValue = showsPageSwitcher ? .home : tab } : nil,
            capturesSelectedTabTap: tab == .search || showsPageSwitcher,
            isSearchTab: tab == .search
        )
        .navigationHistoryStack(path: detailPath, rootTitle: tab.title)
        // Configure the native scrolling boundary without adding an overlay or changing safe areas.
        .nativeBottomScrollEdgeBlur()
    }

    @ViewBuilder
    private func rootTabContentWithChrome(
        for tab: AppTab,
        detailPath: Binding<NavigationPath>
    ) -> some View {
        Group {
            if tab == .home {
                rootTabContent(for: tab, detailPath: detailPath)
                    .environment(\.homeTopBarActions, HomeTopBarActions(
                        accountMessageViewModel: mineViewModelHolder.accountMessageViewModel,
                        onOpenProfile: {
                            if dependencies.sessionStore.isLoggedIn,
                               let user = dependencies.sessionStore.user,
                               let mid = user.mid, mid > 0 {
                                openVideoOwnerRoute(VideoOwner(mid: mid, name: user.uname ?? "", face: user.face))
                            } else {
                                openMineOverlayRoute(.accountManagement)
                            }
                        },
                        onOpenMessages: {
                            openMineOverlayRoute(.accountMessages)
                        },
                        onOpenRootPage: selectRootPageFromMenu
                    ))
            } else {
                rootTabContent(for: tab, detailPath: detailPath)
            }
        }
        .environment(\.isRootTabContent, true)
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
                searchText: $mineSearchQuery,
                isSearchFocused: $isMineSearchFocused,
                hasBackButton: !detailPath.wrappedValue.isEmpty,
                onOpenRoute: openMineOverlayRoute
            )
        case .search:
            SearchView(
                holder: searchViewModelHolder,
                accessoryStore: searchBottomAccessoryStore,
                searchText: rootSearchQueryBinding,
                isSearchFocused: $isRootSearchFocused,
                onSubmit: submitRootSearch
            )
        }
    }

    private var rootTabBarMinimizeBehavior: TabBarMinimizeBehavior {
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
                showsLiveFeed: $showsHomeLiveFeed,
                actionStore: homeActionStore,
                launchConfiguration: HomeFeedLaunchConfiguration(
                    autoOpenDetail: shouldAutoOpenDetail,
                    startVideo: startBVID.map(Self.seedVideo),
                    onVideoSelect: openVideo
                )
            )
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .toolbarVisibility(.hidden, for: .navigationBar)
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
            get: { rootSearchQueryBuffer },
            set: { query in
                rootSearchQueryBuffer = query
                guard let viewModel = searchViewModelHolder.viewModel,
                      viewModel.query != query else { return }
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
        let keyword = viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        isRootSearchFocused = false
        Task { await viewModel.search(keyword) }
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

private extension View {
    @ViewBuilder
    func adaptiveRootTabViewStyle(isEnabled: Bool) -> some View {
        if isEnabled {
            tabViewStyle(.sidebarAdaptable)
        } else {
            self
        }
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
