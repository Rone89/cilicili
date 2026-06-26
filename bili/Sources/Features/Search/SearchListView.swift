import SwiftUI

struct SearchListView: View {
    @ObservedObject var viewModel: SearchViewModel
    let showsHotSearches: Bool
    @Binding var showsAllHotSearches: Bool

    var body: some View {
        List {
            if viewModel.showsDiscovery {
                discoverySections
            } else if viewModel.results.isEmpty && viewModel.state.isLoading {
                SearchLoadingSection()
            } else if viewModel.showsEmptyResults {
                emptyResultsView
            } else {
                resultSections
            }
        }
        .nativeTopScrollEdgeEffect()
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .refreshable {
            await refresh()
        }
    }

    @ViewBuilder
    private var discoverySections: some View {
        if viewModel.state.isLoading {
            SearchLoadingSection()
        }

        if !showsHotSearches {
            SearchDiscoveryEmptyView(title: "开始搜索", message: "输入关键词后搜索视频或 UP 主。")
        } else if viewModel.hotSearchState.isLoading {
            SearchHotSearchLoadingSection()
        } else if viewModel.hotSearches.isEmpty {
            SearchDiscoveryEmptyView(title: "暂无热门搜索", message: "输入关键词后搜索。")
        } else {
            SearchHotSearchSection(
                viewModel: viewModel,
                showsAllHotSearches: $showsAllHotSearches
            )
        }
    }

    @ViewBuilder
    private var resultSections: some View {
        if viewModel.selectedScope.supportsOrder {
            SearchSortSection(viewModel: viewModel)
        }

        SearchResultsSection(viewModel: viewModel)
    }

    private var emptyResultsView: some View {
        EmptyStateView(
            title: "没有找到\(viewModel.selectedScope.title)",
            systemImage: viewModel.selectedScope.systemImage,
            message: "换个关键词或切换搜索类型试试。"
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .listRowBackground(Color.clear)
    }

    private func refresh() async {
        if viewModel.showsDiscovery {
            guard showsHotSearches else { return }
            await viewModel.loadHotSearch()
        } else {
            await viewModel.search(viewModel.query)
        }
    }
}

private struct SearchDiscoveryEmptyView: View {
    let title: String
    let message: String

    var body: some View {
        EmptyStateView(title: title, systemImage: "magnifyingglass", message: message)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .listRowBackground(Color.clear)
    }
}
