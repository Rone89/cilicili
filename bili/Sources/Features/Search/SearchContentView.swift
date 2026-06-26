import SwiftUI

struct SearchContentView: View {
    @ObservedObject var viewModel: SearchViewModel
    let showsHotSearches: Bool
    @Binding var showsAllHotSearches: Bool

    var body: some View {
        SearchListView(
            viewModel: viewModel,
            showsHotSearches: showsHotSearches,
            showsAllHotSearches: $showsAllHotSearches
        )
        .searchable(
            text: Binding(
                get: { viewModel.query },
                set: { query in
                    viewModel.query = query
                    viewModel.queryChanged()
                }
            ),
            placement: .automatic,
            prompt: viewModel.selectedScope == .video ? "搜索视频" : "搜索 UP 主"
        )
        .searchSuggestions {
            ForEach(viewModel.suggestions) { item in
                Label(item.value, systemImage: "magnifyingglass")
                    .searchCompletion(item.value)
            }
        }
        .onSubmit(of: .search) {
            Task { await viewModel.search() }
        }
        .overlay {
            if case .failed(let message) = viewModel.state, viewModel.results.isEmpty {
                ErrorStateView(title: "搜索失败", message: message) {
                    Task { await viewModel.search() }
                }
            }
        }
        .task {
            await loadHotSearchIfNeeded()
        }
    }

    private func loadHotSearchIfNeeded() async {
        guard showsHotSearches else { return }
        await viewModel.loadHotSearch()
    }
}
