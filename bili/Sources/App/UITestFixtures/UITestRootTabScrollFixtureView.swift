#if DEBUG
import SwiftUI
import Foundation
import Combine

/// Uses the production root scroll containers with deterministic data.
struct UITestRootTabScrollFixtureView: View {
    let dependencies: AppDependencies
    private let api: BiliAPIClient
    @StateObject private var home: HomeViewModel
    @StateObject private var dynamic: DynamicViewModel
    @StateObject private var live: LiveViewModel
    @StateObject private var search: SearchViewModel
    @StateObject private var mine: MineViewModel
    @StateObject private var messages: AccountMessageCenterViewModel
    @StateObject private var requests = RootTabFixtureRequests.shared
    @StateObject private var searchAccessory = SearchBottomAccessoryStore()
    @State private var homeViewport = HomeFeedViewportState()
    @State private var homeActions = HomeFeedScrollActions()
    @State private var nativeRefresh = HomeNativeRefreshActionStore()
    @State private var selectedTab: AppTab = .home
    @State private var paths: [AppTab: NavigationPath] = [:]
    @State private var metrics = RootTabFixtureMetrics()
    @State private var scrollRequests: [AppTab: RootTabScrollRequest] = [:]
    @State private var mineQuery = ""
    @State private var isSearchPresented = false
    @FocusState private var searchFocused: Bool
    @FocusState private var mineFocused: Bool

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RootTabFixtureURLProtocol.self]
        let api = BiliAPIClient(session: URLSession(configuration: configuration),
            sessionStore: dependencies.sessionStore, libraryStore: dependencies.libraryStore,
            homeRecommendDiagnosticsStore: .shared)
        self.api = api
        let videos = (1...60).map { (index: Int) in
            VideoItem(bvid: "BVroot\(index)", aid: index, title: "搜索结果 \(index)", pic: nil,
                desc: nil, duration: 120, pubdate: nil, owner: nil, stat: nil, cid: nil, pages: nil, dimension: nil)
        }
        let home = HomeViewModel(api: api, libraryStore: dependencies.libraryStore, sessionStore: dependencies.sessionStore)
        home.updateFeed(videos)
        home.state = .loaded
        _home = StateObject(wrappedValue: home)
        let dynamic = DynamicViewModel(api: api, libraryStore: dependencies.libraryStore, sessionStore: dependencies.sessionStore)
        dynamic.items = (1...60).map { (index: Int) in
            let json = "{\"id_str\":\"\(index)\",\"type\":\"DYNAMIC_TYPE_WORD\",\"modules\":{\"module_author\":{\"mid\":1,\"name\":\"测试作者\"},\"module_dynamic\":{\"desc\":{\"text\":\"动态内容 \(index)\"}}}}"
            return try! JSONDecoder.bili.decode(DynamicFeedItem.self, from: Data(json.utf8))
        }
        dynamic.state = .loaded
        _dynamic = StateObject(wrappedValue: dynamic)
        _live = StateObject(wrappedValue: LiveViewModel(api: api))
        let search = SearchViewModel(api: api)
        search.query = "保留关键词"
        search.results = videos.map(SearchResultItem.video)
        search.state = .loaded
        _search = StateObject(wrappedValue: search)
        _mine = StateObject(wrappedValue: MineViewModel(api: api, sessionStore: dependencies.sessionStore))
        _messages = StateObject(wrappedValue: AccountMessageCenterViewModel(service: dependencies.accountMessageService,
            sessionStore: dependencies.sessionStore))
    }

    private var selection: Binding<AppTab> {
        Binding(get: { selectedTab }, set: { tab in
            if tab == selectedTab {
                guard paths[tab]?.isEmpty ?? true else { return }
                if tab == .home { homeActions.requestScrollToTop() }
                else { scrollRequests[tab] = RootTabScrollRequest() }
            } else { selectedTab = tab }
        })
    }

    var body: some View {
        rootTabs
            .tabBarMinimizeBehavior(ProcessInfo.processInfo.arguments.contains("--test-minimize") ? .onScrollDown : .never)
            .tabViewBottomAccessory(isEnabled: showsBottomAccessory) {
                if selectedTab == .search { SearchTabBottomAccessory(store: searchAccessory) }
                else { MineTabBottomSearchAccessory(text: $mineQuery, onActivate: {}) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if selectedTab == .search && searchFocused {
                    SearchTabBottomAccessory(store: searchAccessory).padding(.vertical, 8)
                }
            }
            .overlay(alignment: .topLeading) {
                VStack {
                    RootTabFixtureMetricsView(metrics: metrics, requests: requests, search: search, tab: selectedTab)
                    Button("重复当前") { selection.wrappedValue = selectedTab }
                        .accessibilityIdentifier("fixture.root.reselect")
                        .buttonStyle(.bordered)
                }
            }
            .transformEnvironment(\.accessibilityReduceMotion) { value in
                if ProcessInfo.processInfo.arguments.contains("--test-reduce-motion") { value = true }
            }
    }

    private var showsBottomAccessory: Bool {
        (paths[selectedTab]?.isEmpty ?? true) && !searchFocused && (selectedTab == .search || selectedTab == .mine)
    }

    private var rootTabs: some View {
        TabView(selection: selection) {
            ForEach(AppTab.defaultVisibleTabs) { tab in
                Tab(value: tab, role: tab == .search ? .search : nil) {
                    navigationStack(tab)
                } label: { Label(tab.title, systemImage: tab.systemImage) }
            }
        }
    }

    private func navigationStack(_ tab: AppTab) -> some View {
        NavigationStack(path: path(for: tab)) {
            navigationPage(tab)
        }
        .coordinatesRootTabBarTransitions(isDetailPresented: !(paths[tab]?.isEmpty ?? true),
            onRootTabTap: selectedTab == tab ? { selection.wrappedValue = tab } : nil,
            capturesSearchReselection: tab == .search)
        .navigationHistoryStack(path: path(for: tab), rootTitle: tab.title)
    }

    private func navigationPage(_ tab: AppTab) -> some View {
        page(tab)
            .environment(\.rootTabScrollRequest, scrollRequests[tab])
            .navigationHistoryTitle(tab.title)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top }
                action: { _, value in metrics.offsets[tab] = value }
            .navigationTitle(tab.title)
            .toolbarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { _ in
                ScrollView { Text("二级页面").frame(height: 1800) }
                    .toolbar { Button("返回") { paths[tab]?.removeLast() } }
            }
            .toolbar { fixtureToolbar(for: tab) }
    }

    @ToolbarContentBuilder
    private func fixtureToolbar(for tab: AppTab) -> some ToolbarContent {
        if tab == .search {
            ToolbarItem(placement: .topBarLeading) {
                Button("输入") { isSearchPresented = true }
                    .accessibilityIdentifier("fixture.root.focusSearch")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("详情") { paths[tab, default: NavigationPath()].append("detail") }
                .accessibilityIdentifier("fixture.root.detail")
        }
    }

    @ViewBuilder private func page(_ tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeFeedScrollView(viewModel: home, viewportState: $homeViewport, scrollActions: homeActions,
                nativeRefreshActionStore: nativeRefresh, layout: .singleColumn) {
                LazyVStack { ForEach(1...60, id: \.self) { Text("首页内容 \($0)").frame(height: 120) } }
            }
        case .dynamic:
            DynamicFeedScrollContent(api: api, viewModel: dynamic, isLoggedIn: true, contentWidth: 360, horizontalInset: 20)
        case .live:
            LiveFeedView(viewModel: live)
        case .search:
            SearchContentView(viewModel: search, showsHotSearches: false, accessoryStore: searchAccessory)
                .searchable(text: $search.query, isPresented: $isSearchPresented)
                .searchFocused($searchFocused)
                .onChange(of: searchFocused) { _, value in searchAccessory.isSearchFocused = value }
        case .mine:
            MineContentView(viewModel: mine, accountMessageViewModel: messages,
                sessionStore: dependencies.sessionStore, libraryStore: dependencies.libraryStore,
                onQRCodeLogin: {}, onSMSLogin: {}, onWebLogin: {}, onOpenRoute: { _ in },
                searchText: $mineQuery, isSearchFocused: $mineFocused)
        }
    }

    private func path(for tab: AppTab) -> Binding<NavigationPath> {
        Binding(get: { paths[tab, default: NavigationPath()] }, set: { paths[tab] = $0 })
    }
}

@MainActor private final class RootTabFixtureMetrics: ObservableObject {
    @Published var offsets: [AppTab: CGFloat] = [:]
}

private struct RootTabFixtureMetricsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var metrics: RootTabFixtureMetrics
    @ObservedObject var requests: RootTabFixtureRequests
    @ObservedObject var search: SearchViewModel
    let tab: AppTab
    var body: some View {
        VStack {
            Text(String(format: "%.1f", metrics.offsets[tab, default: 0])).accessibilityIdentifier("fixture.root.offset")
            Text("\(requests.count)").accessibilityIdentifier("fixture.root.requests")
            Text(search.query).accessibilityIdentifier("fixture.root.query")
            Text(reduceMotion ? "1" : "0").accessibilityIdentifier("fixture.root.reduceMotion")
        }.font(.caption2).allowsHitTesting(false)
    }
}

@MainActor private final class RootTabFixtureRequests: ObservableObject {
    static let shared = RootTabFixtureRequests()
    @Published var count = 0
}

nonisolated private final class RootTabFixtureURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Task { @MainActor in RootTabFixtureRequests.shared.count += 1 }
        let rooms = (1...60).map { ["roomid": $0, "title": "直播内容 \($0)", "uname": "测试主播"] as [String: Any] }
        let data = try! JSONSerialization.data(withJSONObject: ["code": 0, "data": ["recommend_room_list": rooms]])
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
