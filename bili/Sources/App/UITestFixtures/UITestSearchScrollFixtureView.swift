#if DEBUG
import SwiftUI

/// Actual search content and native search chrome, with network-free results and destinations.
struct UITestSearchScrollFixtureView: View {
    @StateObject private var viewModel: SearchViewModel
    @StateObject private var accessoryStore = SearchBottomAccessoryStore()
    @State private var path: [String] = []

    init(api: BiliAPIClient) {
        let viewModel = SearchViewModel(api: api)
        viewModel.query = "滚动位置测试"
        viewModel.selectedScope = .video
        viewModel.results = Self.videos(prefix: "结果")
        viewModel.state = .loaded
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack(path: $path) {
            SearchContentView(viewModel: viewModel, showsHotSearches: false, accessoryStore: accessoryStore)
                .toolbarTitleDisplayMode(.inline)
                .nativeNavigationSearch(
                    text: $viewModel.query,
                    isPresented: $accessoryStore.isSearchFocused,
                    isKeyboardVisible: $accessoryStore.isKeyboardVisible,
                    isEnabled: path.isEmpty,
                    prompt: "搜索", title: "搜索", onSubmit: {}
                )
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
