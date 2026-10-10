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
    @State var rootTabScrollRequests: [AppTab: RootTabScrollRequest] = [:]
    @State var homeNavigationPath = NavigationPath()
    @State var searchNavigationPath = NavigationPath()
    @State var dynamicNavigationPath = NavigationPath()
    @State var liveNavigationPath = NavigationPath()
    @State var mineNavigationPath = NavigationPath()
    @State var rootSearchQueryBuffer = ""
    @State private var isRootSearchPresented = false
    @State private var preservesSearchResultsOnDismissal = false
    @FocusState private var isRootSearchFocused: Bool
    @State var mineSearchQuery = ""
    @State var isMineSearchEditing = false
    @FocusState var isMineSearchFocused: Bool
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
        .environment(\.videoDetailActionButtonStyle, libraryStore.videoDetailActionButtonStyle)
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
        .onChange(of: activeRootNavigationPathCount) { _, count in
            if count == 0 {
                repairSelectedTabIfNeeded(visibleTabs: visibleRootTabs)
            }
        }
        .onChange(of: selectedTab) { _, tab in
            if tab != .search {
                preservesSearchResultsOnDismissal = true
                isRootSearchPresented = false
            }
            if tab != .mine {
                isMineSearchFocused = false
                isMineSearchEditing = false
            }
        }
        .onChange(of: searchNavigationPath.count) { _, count in
            if count > 0 {
                preservesSearchResultsOnDismissal = true
                isRootSearchPresented = false
            }
        }
        .onChange(of: isRootSearchPresented) { _, isPresented in
            if isPresented { preservesSearchResultsOnDismissal = false }
        }
        .onChange(of: isRootSearchFocused) { _, isFocused in
            searchBottomAccessoryStore.isSearchFocused = isFocused
        }
        .onChange(of: searchViewModelHolder.viewModel?.query) { _, query in
            rootSearchQueryBuffer = query ?? ""
        }
        .onChange(of: isMineSearchFocused) { wasFocused, isFocused in
            if wasFocused && !isFocused {
                isMineSearchEditing = false
            }
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
            ForEach(displayedRootTabs) { tab in
                Tab(value: tab, role: tab == .search ? .search : nil) {
                    rootTabNavigationStack(
                        for: tab,
                        detailPath: rootNavigationPathBinding(for: tab)
                    )
                } label: {
                    Label(tab.title, systemImage: tab.systemImage)
                }
            }
        }
        .toolbarVisibility(visibleRootTabs.count == 1 ? .hidden : .automatic, for: .tabBar)
        .tint(libraryStore.appTintColor)
        .tabViewBottomAccessory(isEnabled: showsTabBottomAccessory) {
            rootTabBottomAccessory
        }
        .tabBarMinimizeBehavior(rootTabBarMinimizeBehavior)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsSearchKeyboardFilters {
                SearchTabBottomAccessory(store: searchBottomAccessoryStore)
                    .padding(.vertical, 8)
            } else if showsMineKeyboardSearch {
                MineKeyboardSearchAccessory(
                    text: $mineSearchQuery,
                    isFocused: $isMineSearchFocused
                )
                .padding(.horizontal, libraryStore.standardPageHorizontalInset)
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private func rootTabNavigationStack(
        for tab: AppTab,
        detailPath: Binding<NavigationPath>
    ) -> some View {
        NavigationStack(path: detailPath) {
            rootTabContentWithChrome(for: tab, detailPath: detailPath)
                .environment(\.rootTabScrollRequest, rootTabScrollRequests[tab])
                .toolbarVisibility(.visible, for: .navigationBar)
                .toolbarBackground(.automatic, for: .navigationBar)
                .navigationTitle(rootNavigationTitle(for: tab))
                .navigationHistoryTitle(tab.title)
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
                    .navigationHistoryTitle(route.navigationDisplayTitle)
                }
                .navigationDestination(for: AppTab.self) { destination in
                    rootTabContent(for: destination, detailPath: detailPath)
                        .navigationTitle(destination.title)
                        .toolbarTitleDisplayMode(.inline)
                        .toolbarVisibility(.hidden, for: .tabBar)
                        .safeAreaInset(edge: .bottom) {
                            if destination == .search {
                                SearchTabBottomAccessory(store: searchBottomAccessoryStore)
                            }
                        }
                }
                .videoDestinations()
                .dynamicDetailDestinations(
                    path: detailPath,
                    api: dependencies.api
                )
        }
        .coordinatesRootTabBarTransitions(
            isDetailPresented: !detailPath.wrappedValue.isEmpty,
            onRootTabTap: selectedTab == tab ? { tabSelection.wrappedValue = tab } : nil,
            capturesSearchReselection: tab == .search
        )
        .navigationHistoryStack(path: detailPath, rootTitle: tab.title)
        // Configure the native scrolling boundary without adding an overlay or changing safe areas.
        .nativeBottomScrollEdgeBlurExperiment()
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
                        },
                        onOpenRootPage: { page in
                            appendActiveRootRoute(page)
                        },
                        onOpenProfile: {
                            if dependencies.sessionStore.isLoggedIn,
                               let user = dependencies.sessionStore.user,
                               let mid = user.mid, mid > 0 {
                                openVideoOwnerRoute(VideoOwner(mid: mid, name: user.uname ?? "", face: user.face))
                            } else {
                                openMineOverlayRoute(.accountManagement)
                            }
                        }
                    )
            } else {
                rootTabContent(for: tab, detailPath: detailPath)
            }
        }
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
                onOpenRoute: openMineOverlayRoute
            )
        case .search:
            SearchView(
                holder: searchViewModelHolder,
                accessoryStore: searchBottomAccessoryStore
            )
            .searchable(
                text: rootSearchQueryBinding,
                isPresented: $isRootSearchPresented,
                prompt: Text(searchViewModelHolder.viewModel?.searchPrompt ?? "搜索")
            )
            .searchFocused($isRootSearchFocused)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit(of: .search, submitRootSearch)
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

    private var showsMineBottomAccessory: Bool {
        selectedTab == .mine && mineNavigationPath.isEmpty && !isMineSearchEditing
    }

    private var showsSearchKeyboardFilters: Bool {
        selectedTab == .search && searchNavigationPath.isEmpty && isRootSearchFocused
    }

    private var showsMineKeyboardSearch: Bool {
        selectedTab == .mine && mineNavigationPath.isEmpty && isMineSearchEditing
    }

    private var showsTabBottomAccessory: Bool {
        showsSearchBottomAccessory || showsMineBottomAccessory
    }

    @ViewBuilder
    private var rootTabBottomAccessory: some View {
        if showsSearchBottomAccessory {
            SearchTabBottomAccessory(store: searchBottomAccessoryStore)
        } else {
            MineTabBottomSearchAccessory(
                text: $mineSearchQuery,
                onActivate: {
                    isMineSearchEditing = true
                }
            )
            .padding(.horizontal, libraryStore.standardPageHorizontalInset)
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
            get: { rootSearchQueryBuffer },
            set: { query in
                // Preserve results only when the app closes search to submit or navigate.
                // The system's Cancel and clear actions must restore discovery.
                if query.isEmpty && !isRootSearchPresented && preservesSearchResultsOnDismissal {
                    let retainedQuery = searchViewModelHolder.viewModel?.query ?? rootSearchQueryBuffer
                    rootSearchQueryBuffer = ""
                    if !retainedQuery.isEmpty {
                        DispatchQueue.main.async {
                            guard !isRootSearchPresented, preservesSearchResultsOnDismissal,
                                  rootSearchQueryBuffer.isEmpty else { return }
                            rootSearchQueryBuffer = searchViewModelHolder.viewModel?.query ?? retainedQuery
                        }
                    }
                    return
                }
                rootSearchQueryBuffer = query
                guard let viewModel = searchViewModelHolder.viewModel else { return }
                guard viewModel.query != query else { return }
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
        preservesSearchResultsOnDismissal = true
        isRootSearchPresented = false
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
