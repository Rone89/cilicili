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
        .safeAreaInset(edge: .top, spacing: 0) {
            if !viewModel.showsDiscovery {
                SearchScopeBar(viewModel: viewModel)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SearchFilterToolbarMenu(viewModel: viewModel)
            }
        }
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
    }

    private func loadDiscoveryStateIfNeeded() async {
        await viewModel.restoreDiscoveryState(loadHotSearches: showsHotSearches)
    }
}

struct SearchTabBottomAccessory: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @ObservedObject var store: SearchBottomAccessoryStore
    var providesOwnBackground = false

    @ViewBuilder
    var body: some View {
        if let viewModel = store.viewModel {
            SearchFilterCapsule(viewModel: viewModel, usesKeyboardControls: store.usesKeyboardControls, providesOwnBackground: providesOwnBackground)
                .frame(maxWidth: .infinity, minHeight: 40)
                .padding(.horizontal, libraryStore.standardPageHorizontalInset)
        }
    }
}

private struct SearchFilterCapsule: View {
    @ObservedObject var viewModel: SearchViewModel
    let usesKeyboardControls: Bool
    let providesOwnBackground: Bool

    var body: some View {
        HStack(spacing: usesKeyboardControls ? 12 : 0) {
            if usesKeyboardControls {
                scopeMenu.buttonStyle(.plain).frame(height: 44).biliGlassEffect(in: Capsule())
                orderMenu.buttonStyle(.plain).frame(height: 44).biliGlassEffect(in: Capsule())
            } else {
                scopeMenu.buttonStyle(.plain)
                orderMenu.buttonStyle(.plain)
            }
        }
        .buttonBorderShape(.capsule)
        .font(.subheadline.weight(.medium))
        .lineLimit(1)
        .frame(maxWidth: .infinity, minHeight: 40)
        .foregroundStyle(.primary)
        .background {
            if providesOwnBackground && !usesKeyboardControls {
                Capsule().fill(.clear).biliGlassEffect(in: Capsule())
            }
        }
    }

    private var scopeMenu: some View {
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
            filterLabel(title: viewModel.selectedScope.title)
        }
        .frame(maxWidth: .infinity, minHeight: 40)
        .contentShape(Rectangle())
        .accessibilityLabel("搜索类型")
        .accessibilityValue(viewModel.selectedScope.title)
    }

    private var orderMenu: some View {
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
            filterLabel(title: viewModel.selectedOrder.title)
        }
        .frame(maxWidth: .infinity, minHeight: 40)
        .contentShape(Rectangle())
        .disabled(!viewModel.selectedScope.supportsOrder)
        .foregroundStyle(viewModel.selectedScope.supportsOrder ? .primary : .secondary)
        .accessibilityLabel("排序方式")
        .accessibilityValue(viewModel.selectedOrder.title)
    }

    private func filterLabel(title: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, minHeight: 40)
        .contentShape(Rectangle())
    }
}

private struct SearchFilterToolbarMenu: View {
    @ObservedObject var viewModel: SearchViewModel

    var body: some View {
        Menu {
            Section("搜索内容") {
                scopeOptions
            }
            Section("排序方式") {
                orderOptions
            }
        } label: {
            Image(systemName: "slider.horizontal.3").foregroundStyle(.primary)
        }
        .tint(.primary)
        .accessibilityLabel("搜索内容与排序")
        .accessibilityValue(selectionDescription)
        .accessibilityIdentifier("search.filters.menu")
    }

    private var scopeOptions: some View {
        ForEach(SearchScope.allCases) { scope in
            Button {
                Task { await viewModel.selectScope(scope, animation: .smooth(duration: 0.28)) }
            } label: {
                Label(scope.title, systemImage: scope == viewModel.selectedScope ? "checkmark" : scope.systemImage)
            }
            .accessibilityValue(scope == viewModel.selectedScope ? "已选中" : "")
        }
    }

    private var orderOptions: some View {
        ForEach(SearchSortOrder.allCases) { order in
            Button {
                Task { await viewModel.selectOrder(order) }
            } label: {
                Label(order.title, systemImage: order == viewModel.selectedOrder ? "checkmark" : "arrow.up.arrow.down")
            }
            .accessibilityValue(order == viewModel.selectedOrder ? "已选中" : "")
            .disabled(!viewModel.selectedScope.supportsOrder)
        }
    }

    private var selectionDescription: String {
        let order = viewModel.selectedScope.supportsOrder ? viewModel.selectedOrder.title : "当前类型不支持排序"
        return viewModel.selectedScope.title + "，" + order
    }
}

/// Kept outside the results scroll view so categories remain directly reachable.
private struct SearchScopeBar: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var viewModel: SearchViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SearchScope.allCases) { scope in
                        let selected = scope == viewModel.selectedScope
                        Button {
                            Task { await viewModel.selectScope(scope) }
                        } label: {
                            Label(scope == .comprehensive ? "综合" : scope.title, systemImage: scope.systemImage)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 44)
                                .foregroundStyle(selected ? Color(.systemBackground) : Color.primary)
                                .background(selected ? Color.primary : Color(.secondarySystemGroupedBackground), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("搜索类型：\(scope.title)")
                        .accessibilityValue(selected ? "已选中" : "未选中")
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                        .accessibilityIdentifier("search.scope.\(scope.rawValue)")
                        .id(scope)
                    }
                }
                .padding(.horizontal, libraryStore.standardPageHorizontalInset)
                .padding(.vertical, 8)
            }
            .accessibilityIdentifier("search.scopes")
            .onAppear { proxy.scrollTo(viewModel.selectedScope, anchor: .center) }
            .onChange(of: viewModel.selectedScope) { _, scope in
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                    proxy.scrollTo(scope, anchor: .center)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}
