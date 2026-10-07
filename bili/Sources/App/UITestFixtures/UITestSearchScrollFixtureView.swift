#if DEBUG
import SwiftUI

/// Actual search content and native search chrome, with network-free results and destinations.
struct UITestSearchScrollFixtureView: View {
    @StateObject private var viewModel: SearchViewModel
    @StateObject private var accessoryStore = SearchBottomAccessoryStore()
    @State private var path: [String] = []
    @State private var selectedTab: AppTab = .search
    @State private var isSearchPresented = false
    @FocusState private var isSearchFocused: Bool

    init(api: BiliAPIClient) {
        let viewModel = SearchViewModel(api: api)
        viewModel.query = "滚动位置测试"
        viewModel.selectedScope = .video
        viewModel.results = Self.videos(prefix: "结果")
        viewModel.state = .loaded
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.defaultVisibleTabs) { tab in
                Tab(value: tab, role: tab == .search ? .search : nil) {
                    if tab == .search {
                        searchNavigationStack
                    } else {
                        NavigationStack {
                            Color.clear.navigationTitle(tab.title)
                        }
                    }
                } label: {
                    Label(tab.title, systemImage: tab.systemImage)
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(
            isEnabled: selectedTab == .search && path.isEmpty && !accessoryStore.usesKeyboardControls
        ) {
            SearchTabBottomAccessory(store: accessoryStore)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selectedTab == .search && path.isEmpty && isSearchFocused {
                SearchTabBottomAccessory(store: accessoryStore)
                    .padding(.vertical, 8)
            }
        }
        .onChange(of: selectedTab) { _, tab in
            if tab != .search { isSearchPresented = false }
        }
    }

    private var searchNavigationStack: some View {
        NavigationStack(path: $path) {
            SearchContentView(viewModel: viewModel, showsHotSearches: false, accessoryStore: accessoryStore)
                .toolbarTitleDisplayMode(.inline)
                .navigationTitle("搜索")
                .searchable(
                    text: $viewModel.query,
                    isPresented: $isSearchPresented,
                    prompt: "搜索"
                )
                .searchFocused($isSearchFocused)
                .onChange(of: viewModel.query) { oldQuery, query in
                    if query.isEmpty && !isSearchPresented && !oldQuery.isEmpty {
                        DispatchQueue.main.async { viewModel.query = oldQuery }
                    }
                }
                .onSubmit(of: .search) {
                    let keyword = viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !keyword.isEmpty else { return }
                    isSearchPresented = false
                    viewModel.results = Self.videos(prefix: keyword)
                    viewModel.state = .loaded
                }
                .onChange(of: isSearchFocused) { _, isFocused in
                    accessoryStore.isSearchFocused = isFocused
                }
                .onChange(of: path.count) { _, count in
                    if count > 0 { isSearchPresented = false }
                }
                .environment(\.openVideoAction, { video in path.append(video.bvid) })
                .navigationDestination(for: String.self) { id in
                    VStack(spacing: 20) {
                        Text(id).accessibilityIdentifier("fixture.search.detail")
                        Button("返回搜索") { path.removeLast() }
                            .accessibilityIdentifier("fixture.search.back")
                    }
                    .navigationTitle("测试详情")
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("新搜索") {
                            viewModel.clearQuery()
                            viewModel.query = "新搜索"
                            viewModel.results = Self.videos(prefix: "新结果")
                            viewModel.state = .loaded
                        }.accessibilityIdentifier("fixture.search.newQuery")
                    }
                }
        }
        .coordinatesRootTabBarTransitions(isDetailPresented: !path.isEmpty)
    }

    private static func videos(prefix: String) -> [SearchResultItem] {
        (1...60).map { (index: Int) -> SearchResultItem in
            .video(VideoItem(
                bvid: "BVfixture\(index)", aid: index, title: "\(prefix) \(index)", pic: nil,
                desc: nil, duration: 120, pubdate: nil, owner: nil, stat: nil, cid: nil,
                pages: nil, dimension: nil
            ))
        }
    }
}
#endif
