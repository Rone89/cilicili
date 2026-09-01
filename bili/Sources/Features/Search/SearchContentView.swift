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
        }
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                SearchBottomControls(viewModel: viewModel)
            }
        }
    }

    private func loadDiscoveryStateIfNeeded() async {
        await viewModel.restoreDiscoveryState(loadHotSearches: showsHotSearches)
    }
}

struct SearchBottomControls: View {
    @ObservedObject var viewModel: SearchViewModel
    var showsContainer = true

    @ViewBuilder
    var body: some View {
        if showsContainer {
            controlContent
                .biliBottomTabGlassEffect(interactive: false, in: Capsule())
        } else {
            controlContent
        }
    }

    private var controlContent: some View {
        HStack(spacing: 0) {
            BiliGlassSegmentedControl(
                options: Array(SearchScope.allCases),
                selected: viewModel.selectedScope,
                title: { $0.title },
                select: { scope in
                    Task {
                        await viewModel.selectScope(scope, animation: .smooth(duration: 0.28))
                    }
                },
                showsContainer: false
            )
            .frame(maxWidth: .infinity)

            Divider()
                .frame(height: 20)

            SearchSortHeaderButton(viewModel: viewModel, showsContainer: false)
                .frame(minWidth: 86)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityLabel("搜索类型和排序")
    }
}

struct SearchTabBottomAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @ObservedObject var store: SearchBottomAccessoryStore

    @ViewBuilder
    var body: some View {
        if let viewModel = store.viewModel {
            if usesInlineLayout {
                SearchInlineBottomControls(viewModel: viewModel)
            } else {
                SearchBottomControls(viewModel: viewModel, showsContainer: false)
            }
        }
    }

    private var usesInlineLayout: Bool {
        placement == .inline
    }
}

private struct SearchInlineBottomControls: View {
    @ObservedObject var viewModel: SearchViewModel

    var body: some View {
        HStack(spacing: 0) {
            Menu {
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
            } label: {
                ZStack {
                    Color.clear

                    HStack(spacing: 6) {
                        ViewThatFits(in: .horizontal) {
                            Label(viewModel.selectedScope.title, systemImage: viewModel.selectedScope.systemImage)
                            Image(systemName: viewModel.selectedScope.systemImage)
                        }
                    }
                }
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())

            if viewModel.selectedScope.supportsOrder {
                Divider()
                    .frame(height: 20)

                Menu {
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
                    }
                } label: {
                    ZStack {
                        Color.clear

                        Label(viewModel.selectedOrder.shortTitle, systemImage: "arrow.up.arrow.down")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .accessibilityLabel("搜索结果排序")
                .accessibilityValue(viewModel.selectedOrder.title)
            }
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(.primary)
        .accessibilityElement(children: .contain)
    }
}
