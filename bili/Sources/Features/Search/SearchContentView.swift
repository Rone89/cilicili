import SwiftUI
import UIKit

struct SearchContentView: View {
    @Environment(\.isRootTabContent) private var isRootTabContent
    @ObservedObject var viewModel: SearchViewModel
    let showsHotSearches: Bool
    @ObservedObject var accessoryStore: SearchBottomAccessoryStore
    var titleState: FeedChromeTitleState? = nil

    var body: some View {
        SearchListView(
            viewModel: viewModel,
            showsHotSearches: showsHotSearches,
            titleState: titleState
        )
        .toolbar {
            // The root tab supplies the settings item from SearchView;
            // pushed destinations and fixtures keep the native bar menu.
            if !isRootTabContent {
                ToolbarItem(placement: .topBarTrailing) {
                    SearchFilterToolbarMenu(viewModel: viewModel)
                }
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

struct SearchFilterToolbarMenu: View {
    @ObservedObject var viewModel: SearchViewModel
    var iconPointSize: CGFloat = 15
    var controlSize: CGFloat? = nil

    var body: some View {
        SearchFilterToolbarMenuButton(
            selectedOrder: viewModel.selectedOrder,
            supportsOrder: viewModel.selectedScope.supportsOrder,
            selectionDescription: selectionDescription,
            iconPointSize: iconPointSize,
            controlSize: controlSize,
            onSelectOrder: { order in
                Task { await viewModel.selectOrder(order) }
            }
        )
    }

    private var selectionDescription: String {
        viewModel.selectedScope.supportsOrder ? viewModel.selectedOrder.title : "当前类型不支持排序"
    }
}

private struct SearchFilterToolbarMenuButton: UIViewRepresentable {
    let selectedOrder: SearchSortOrder
    let supportsOrder: Bool
    let selectionDescription: String
    let iconPointSize: CGFloat
    let controlSize: CGFloat?
    let onSelectOrder: (SearchSortOrder) -> Void

    func makeUIView(context _: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.showsMenuAsPrimaryAction = true
        button.tintColor = .label
        button.accessibilityIdentifier = "search.filters.menu"
        button.accessibilityLabel = "排序方式"
        applyIcon(to: button)
        button.accessibilityValue = selectionDescription
        button.menu = makeMenu()
        return button
    }

    func updateUIView(_ button: UIButton, context _: Context) {
        button.tintColor = .label
        applyIcon(to: button)
        button.accessibilityValue = selectionDescription
        button.menu = makeMenu()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView button: UIButton, context _: Context) -> CGSize? {
        if let controlSize {
            return CGSize(width: controlSize, height: controlSize)
        }
        let size = button.intrinsicContentSize
        return CGSize(width: max(36, size.width), height: max(36, size.height))
    }

    private func applyIcon(to button: UIButton) {
        let configuration = UIImage.SymbolConfiguration(pointSize: iconPointSize, weight: .semibold)
        button.setImage(
            UIImage(systemName: "slider.horizontal.3", withConfiguration: configuration),
            for: .normal
        )
    }

    private func makeMenu() -> UIMenu {
        let actions = SearchSortOrder.allCases.map { order in
            let isSelected = order == selectedOrder
            let action = UIAction(
                title: order.title,
                image: UIImage(systemName: isSelected ? "checkmark" : "arrow.up.arrow.down"),
                attributes: supportsOrder ? [] : [.disabled],
                state: isSelected ? .on : .off
            ) { _ in
                onSelectOrder(order)
            }
            action.accessibilityValue = isSelected ? "已选中" : ""
            return action
        }
        let section = UIMenu(title: "排序方式", options: .displayInline, children: actions)
        return UIMenu(title: "", children: [section])
    }
}
