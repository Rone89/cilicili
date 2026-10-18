#if DEBUG
import SwiftUI

/// Actual search content and native search chrome, with network-free results and destinations.
struct UITestSearchScrollFixtureView: View {
    @StateObject private var viewModel: SearchViewModel
    @StateObject private var accessoryStore = SearchBottomAccessoryStore()
    @State private var path: [String] = []
    @State private var selectedTab: AppTab = .search
    @State private var searchText = "滚动位置测试"
    @FocusState private var isSearchFocused: Bool
    @State private var mineSearchText = ""
    @FocusState private var isMineSearchFocused: Bool

    init(api: BiliAPIClient) {
        let viewModel = SearchViewModel(api: api)
        viewModel.query = "滚动位置测试"
        viewModel.selectedScope = .video
        viewModel.results = Self.videos(prefix: "结果")
        viewModel.state = .loaded
        viewModel.hotSearches = [HotSearchItem(keyword: "热搜保留测试", showName: nil, icon: nil)]
        viewModel.hotSearchState = .loaded
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.defaultVisibleTabs) { tab in
                Tab(value: tab, role: tab == .search ? .search : nil) {
                    if tab == .search {
                        searchNavigationStack
                    } else if tab == .mine {
                        NavigationStack {
                            Color.clear
                                .navigationTitle("")
                                .navigationToolbarSearch(
                                    text: $mineSearchText,
                                    isFocused: $isMineSearchFocused,
                                    prompt: "搜索我的页功能",
                                    onSubmit: { isMineSearchFocused = false }
                                )
                        }
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
        .onChange(of: selectedTab) { _, tab in
            if tab != .search {
                isSearchFocused = false
            }
            if tab != .mine { isMineSearchFocused = false }
        }
    }

    private var searchNavigationStack: some View {
        NavigationStack(path: $path) {
            SearchContentView(viewModel: viewModel, showsHotSearches: true, accessoryStore: accessoryStore)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if ProcessInfo.processInfo.arguments.contains("--search-test-dismiss-background") {
                        // A deterministic blank target: tapping a result while
                        // editing is expected to navigate, not remain here.
                        Button {} label: {
                            Color(.systemGroupedBackground).frame(height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("搜索内容空白区域")
                        .accessibilityIdentifier("fixture.search.dismissBackground")
                    }
                }
                .toolbarTitleDisplayMode(.inline)
                .navigationTitle("")
                .navigationToolbarSearch(
                    text: searchTextBinding,
                    isFocused: $isSearchFocused,
                    prompt: "搜索",
                    trailingButtonCount: 2,
                    onSubmit: {
                        let keyword = viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !keyword.isEmpty else { return }
                        isSearchFocused = false
                        viewModel.results = Self.videos(prefix: keyword)
                        viewModel.state = .loaded
                    }
                )
                .onChange(of: viewModel.query) { _, query in
                    searchText = query
                }
                .onChange(of: isSearchFocused) { _, isFocused in
                    accessoryStore.isSearchFocused = isFocused
                }
                .onChange(of: path.count) { _, count in
                    if count > 0 {
                        isSearchFocused = false
                    }
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

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { searchText },
            set: { query in
                searchText = query
                guard viewModel.query != query else { return }
                viewModel.query = query
                viewModel.queryChanged()
            }
        )
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
