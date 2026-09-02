import SwiftUI

struct SearchContentView: View {
    @ObservedObject var viewModel: SearchViewModel
    let showsHotSearches: Bool
    @ObservedObject var accessoryStore: SearchBottomAccessoryStore

    var body: some View {
        SearchListView(
            viewModel: viewModel,
            showsHotSearches: showsHotSearches
        )
        .overlay {
            if case .failed(let message) = viewModel.state, viewModel.results.isEmpty {
                ErrorStateView(title: "搜索失败", message: message) {
                    Task { await viewModel.search() }
                }
            }
        }
        .task(id: viewModel.showsDiscovery) {
            accessoryStore.attach(viewModel)
            await loadDiscoveryStateIfNeeded()
        }
        .onDisappear {
            accessoryStore.isSearchFocused = false
            accessoryStore.isKeyboardVisible = false
        }
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                SearchFilterCapsule(viewModel: viewModel)
            }
        }
    }

    private func loadDiscoveryStateIfNeeded() async {
        await viewModel.restoreDiscoveryState(loadHotSearches: showsHotSearches)
    }
}

struct SearchTabBottomAccessory: View {
    @ObservedObject var store: SearchBottomAccessoryStore

    @ViewBuilder
    var body: some View {
        if let viewModel = store.viewModel {
            SearchFilterCapsule(viewModel: viewModel)
                .frame(maxWidth: .infinity, minHeight: 40)
                .padding(.horizontal, 16)
        }
    }
}

private struct SearchFilterCapsule: View {
    @ObservedObject var viewModel: SearchViewModel

    var body: some View {
        Menu {
            Section("搜索类型") {
                ForEach(SearchScope.allCases) { scope in
                    Button {
                        Task {
                            await viewModel.selectScope(scope, animation: .smooth(duration: 0.28))
                        }
                    } label: {
                        Label(
                            scope.title,
                            systemImage: scope == viewModel.selectedScope
                                ? "checkmark"
                                : scope.systemImage
                        )
                    }
                }
            }
            Section("排序方式") {
                ForEach(SearchSortOrder.allCases) { order in
                    Button {
                        Task { await viewModel.selectOrder(order) }
                    } label: {
                        Label(
                            order.title,
                            systemImage: order == viewModel.selectedOrder
                                ? "checkmark"
                                : "arrow.up.arrow.down"
                        )
                    }
                    .disabled(!viewModel.selectedScope.supportsOrder)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(viewModel.selectedScope.title)
                Text("·")
                    .foregroundStyle(.secondary)
                Text(viewModel.selectedOrder.shortTitle)
            }
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .foregroundStyle(.primary)
        .accessibilityLabel("搜索筛选")
        .accessibilityValue("搜索类型：\(viewModel.selectedScope.title)，排序方式：\(viewModel.selectedOrder.title)")
    }
}
