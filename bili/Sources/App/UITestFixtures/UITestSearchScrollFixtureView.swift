#if DEBUG
import SwiftUI

/// Actual search content and native search chrome, with network-free results and destinations.
struct UITestSearchScrollFixtureView: View {
    @StateObject private var viewModel: SearchViewModel
    @StateObject private var accessoryStore = SearchBottomAccessoryStore()
    @State private var path: [String] = []
    @State private var selectedTab: AppTab = .search
    @State private var isSearchPresented = false
    @State private var preservesSearchResultsOnDismissal = false
    @State private var searchText = "滚动位置测试"
    @FocusState private var isSearchFocused: Bool

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
                preservesSearchResultsOnDismissal = true
                isSearchPresented = false
            }
        }
    }

    private var searchNavigationStack: some View {
        NavigationStack(path: $path) {
            SearchContentView(viewModel: viewModel, showsHotSearches: true, accessoryStore: accessoryStore)
                .toolbarTitleDisplayMode(.inline)
                .navigationTitle("")
                .searchable(
                    text: searchTextBinding,
                    isPresented: $isSearchPresented,
                    placement: .toolbar,
                    prompt: "搜索"
                )
                .integratedNavigationSearch()
                .searchFocused($isSearchFocused)
                .onChange(of: viewModel.query) { _, query in
                    searchText = query
                }
                .onChange(of: isSearchPresented) { _, isPresented in
                    if isPresented { preservesSearchResultsOnDismissal = false }
                }
                .onSubmit(of: .search) {
                    let keyword = viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !keyword.isEmpty else { return }
                    preservesSearchResultsOnDismissal = true
                    isSearchPresented = false
                    viewModel.results = Self.videos(prefix: keyword)
                    viewModel.state = .loaded
                }
                .onChange(of: isSearchFocused) { _, isFocused in
                    accessoryStore.isSearchFocused = isFocused
                }
                .onChange(of: path.count) { _, count in
                    if count > 0 {
                        preservesSearchResultsOnDismissal = true
                        isSearchPresented = false
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
                if query.isEmpty && !isSearchPresented && preservesSearchResultsOnDismissal {
                    let retainedQuery = viewModel.query
                    searchText = ""
                    DispatchQueue.main.async {
                        guard !isSearchPresented, preservesSearchResultsOnDismissal,
                              searchText.isEmpty else { return }
                        searchText = viewModel.query.isEmpty ? retainedQuery : viewModel.query
                    }
                    return
                }
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
