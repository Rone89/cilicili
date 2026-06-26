import SwiftUI

struct SearchHotSearchSection: View {
    @ObservedObject var viewModel: SearchViewModel
    @Binding var showsAllHotSearches: Bool

    var body: some View {
        Section {
            ForEach(Array(displayedHotSearches.enumerated()), id: \.element.id) { index, item in
                Button {
                    Task { await viewModel.search(item.keyword) }
                } label: {
                    SearchHotSearchRow(item: item, index: index)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("热门搜索第 \(index + 1) 名，\(item.showName ?? item.keyword)")
            }

            if viewModel.hotSearches.count > 3 {
                Button {
                    withAnimation(.smooth(duration: 0.2)) {
                        showsAllHotSearches.toggle()
                    }
                } label: {
                    Label(
                        showsAllHotSearches ? "收起热搜" : "查看更多热搜",
                        systemImage: showsAllHotSearches ? "chevron.up" : "chevron.down"
                    )
                    .font(.subheadline)
                }
            }
        } header: {
            SearchSectionHeader(title: "热门搜索", systemImage: "flame")
        }
    }

    private var displayedHotSearches: [HotSearchItem] {
        showsAllHotSearches ? viewModel.hotSearches : Array(viewModel.hotSearches.prefix(3))
    }
}

struct SearchHotSearchLoadingSection: View {
    var body: some View {
        Section {
            ForEach(0..<3, id: \.self) { _ in
                SearchHotSearchSkeletonRow()
                    .allowsHitTesting(false)
            }
        } header: {
            SearchSectionHeader(title: "热门搜索", systemImage: "flame")
        }
    }
}

struct SearchResultsSection: View {
    @ObservedObject var viewModel: SearchViewModel

    var body: some View {
        Section {
            let results = viewModel.results
            let lastResultID = results.last?.id
            ForEach(results) { result in
                SearchResultRouteRow(result: result)
                    .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
                    .searchLoadMoreTask(if: result.id == lastResultID, id: result.id) {
                        await viewModel.loadMoreIfNeeded(current: result)
                    }
            }

            if viewModel.state.isLoading {
                ForEach(0..<2, id: \.self) { _ in
                    SearchResultSkeletonRow()
                        .allowsHitTesting(false)
                        .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
                }
            }
        } header: {
            SearchSectionHeader(title: viewModel.resultSectionTitle, systemImage: viewModel.selectedScope.systemImage)
        }
    }
}

struct SearchLoadingSection: View {
    var body: some View {
        Section {
            ForEach(0..<4, id: \.self) { _ in
                SearchResultSkeletonRow()
                    .allowsHitTesting(false)
                    .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
            }
        } header: {
            SearchSectionHeader(title: "正在搜索", systemImage: "magnifyingglass")
        }
    }
}

struct SearchSortSection: View {
    @ObservedObject var viewModel: SearchViewModel

    var body: some View {
        Section {
            Picker(
                "排序",
                selection: Binding(
                    get: { viewModel.selectedOrder },
                    set: { order in
                        Task { await viewModel.selectOrder(order) }
                    }
                )
            ) {
                ForEach(SearchSortOrder.allCases) { order in
                    Text(order.shortTitle)
                        .tag(order)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .padding(.vertical, 2)
        } header: {
            SearchSectionHeader(title: "排序", systemImage: "arrow.up.arrow.down")
        }
    }
}
