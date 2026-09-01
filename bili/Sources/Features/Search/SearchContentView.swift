import SwiftUI

struct SearchContentView: View {
    @ObservedObject var viewModel: SearchViewModel
    let showsHotSearches: Bool
    @ObservedObject var accessoryStore: SearchBottomAccessoryStore
    let usesSearchTabExpansion: Bool

    var body: some View {
        SearchListView(
            viewModel: viewModel,
            showsHotSearches: showsHotSearches
        )
        .safeAreaInset(edge: .bottom, spacing: 8) {
            if usesSearchTabExpansion {
                GlassEffectContainer(spacing: 8) {
                    SearchBottomControls(viewModel: viewModel)
                }
                .padding(.vertical, 4)
            } else if !usesSearchTabExpansion,
                      !accessoryStore.isSearchFocused {
                SearchSortHeaderButton(viewModel: viewModel)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
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
        .toolbar {
            if !usesSearchTabExpansion {
                ToolbarItem(placement: .keyboard) {
                    SearchBottomControls(viewModel: viewModel)
                }
            }
        }
    }

    private func loadDiscoveryStateIfNeeded() async {
        await viewModel.restoreDiscoveryState(loadHotSearches: showsHotSearches)
    }
}

struct SearchBottomControls: View {
    @ObservedObject var viewModel: SearchViewModel
    var showsGlass = true

    var body: some View {
        HStack(spacing: 8) {
            SearchScopeBottomControl(viewModel: viewModel, showsGlass: showsGlass)

            SearchSortHeaderButton(viewModel: viewModel, showsContainer: showsGlass)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .padding(.horizontal, 16)
    }
}

private struct SearchScopeBottomControl: View {
    @ObservedObject var viewModel: SearchViewModel
    var showsGlass = true

    var body: some View {
        BiliGlassSegmentedControl(
            options: Array(SearchScope.allCases),
            selected: viewModel.selectedScope,
            title: { $0.title },
            select: { scope in
                Task {
                    await viewModel.selectScope(scope, animation: .smooth(duration: 0.28))
                }
            },
            showsContainer: showsGlass
        )
        .frame(maxWidth: .infinity)
    }
}

struct SearchTabBottomAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @ObservedObject var store: SearchBottomAccessoryStore

    @ViewBuilder
    var body: some View {
        if let viewModel = store.viewModel {
            if placement == .inline {
                SearchInlineScopeControl(viewModel: viewModel)
            } else {
                SearchScopeBottomControl(viewModel: viewModel, showsGlass: false)
                    .frame(height: 40)
                    .padding(.horizontal, 16)
            }
        }
    }
}

private struct SearchInlineScopeControl: View {
    @ObservedObject var viewModel: SearchViewModel

    var body: some View {
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
            HStack(spacing: 4) {
                Text(viewModel.selectedScope.title)
                Image(systemName: "chevron.down")
                    .imageScale(.small)
            }
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .foregroundStyle(.primary)
        .accessibilityLabel("搜索类型")
        .accessibilityValue(viewModel.selectedScope.title)
    }
}
