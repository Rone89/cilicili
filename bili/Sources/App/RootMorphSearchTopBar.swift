import SwiftUI
import UIKit

/// 搜索页与「我的」页共用的根顶栏配置：控制标题、搜索按钮、输入框与取消按钮的文案和标识。
struct RootMorphSearchTopBarConfiguration {
    let title: String
    let titleAccessibilityID: String
    let searchPrompt: String
    let searchButtonAccessibilityLabel: String
    let searchButtonAccessibilityID: String
    let fieldAccessibilityID: String
    let clearAccessibilityID: String
    let cancelAccessibilityID: String
    let trailingExpandedGlassID: String
    let containerWidth: CGFloat
    let dismissesFocusOnNonEmptySubmit: Bool
}

/// 根页面与二级推入页面共用的官方 Liquid Glass 搜索形变顶栏容器。
struct RootMorphSearchTopBar<CompactAccessory: View, ExpandedAccessory: View>: View {
    @Environment(\.rootHiddenPageSwitcher) private var rootHiddenPageSwitcher
    @ObservedObject var titleState: FeedChromeTitleState
    let configuration: RootMorphSearchTopBarConfiguration
    @Binding var isSearching: Bool
    @Binding var searchText: String
    var isSearchFocused: FocusState<Bool>.Binding
    let isRootTabContent: Bool
    let onSubmit: () -> Void
    @ViewBuilder let compactAccessory: () -> CompactAccessory
    @ViewBuilder let expandedTrailingAccessory: (_ closeButton: AnyView) -> ExpandedAccessory

    @Namespace private var morphNamespace
    @State private var compactWidth: CGFloat = 0
    @State private var measuredRowWidth: CGFloat = 0
    @State private var hasAcquiredSearchFocus = false
    private let controlHeight: CGFloat = 44
    private let closeButtonSpacing: CGFloat = 12

    private var expandedRowWidth: CGFloat {
        if measuredRowWidth > 0 {
            return measuredRowWidth
        }
        let base = configuration.containerWidth > 0 ? configuration.containerWidth : 402
        return max(200, base - 32)
    }

    private var expandedSearchFieldWidth: CGFloat {
        max(140, expandedRowWidth - controlHeight - closeButtonSpacing)
    }

    private var pushedExpandedWidth: CGFloat {
        let base = configuration.containerWidth > 0 ? configuration.containerWidth : 402
        return max(140, base - 160)
    }

    var body: some View {
        if isRootTabContent {
            rootMorphBar
        } else {
            pushedMorphControl
        }
    }

    private var rootMorphBar: some View {
        let searchBarWidth: CGFloat? = isSearching
            ? expandedSearchFieldWidth
            : (compactWidth > 0 ? compactWidth : nil)
        let trailingReserve: CGFloat = isSearching
            ? (controlHeight + closeButtonSpacing)
            : (rootHiddenPageSwitcher != nil ? (controlHeight + closeButtonSpacing) : 0)

        return ZStack(alignment: .trailing) {
            HStack {
                if titleState.progress <= 0.9 {
                    FeedToolbarTitle(
                        title: configuration.title,
                        state: titleState,
                        accessibilityID: configuration.titleAccessibilityID
                    )
                }
                Spacer(minLength: 0)
            }
            .opacity(isSearching ? 0 : 1)
            .scaleEffect(isSearching ? 0.92 : 1, anchor: .leading)
            .accessibilityHidden(isSearching)
            .allowsHitTesting(false)
            .animation(
                isSearching ? .easeOut(duration: 0.05) : .easeIn(duration: 0.2).delay(0.14),
                value: isSearching
            )

            GlassEffectContainer(spacing: 10) {
                ZStack(alignment: .trailing) {
                    ZStack(alignment: .trailing) {
                        if isSearching {
                            Color.clear
                                .frame(height: controlHeight)
                                .overlay(alignment: .trailing) {
                                    RootMorphSearchQueryField(
                                        searchText: $searchText,
                                        isSearchFocused: isSearchFocused,
                                        prompt: configuration.searchPrompt,
                                        fieldAccessibilityID: configuration.fieldAccessibilityID,
                                        clearAccessibilityID: configuration.clearAccessibilityID,
                                        dismissesFocusOnNonEmptySubmit: configuration.dismissesFocusOnNonEmptySubmit,
                                        onSubmit: onSubmit
                                    )
                                    .frame(width: expandedSearchFieldWidth, height: controlHeight)
                                }
                                .transition(
                                    .asymmetric(
                                        insertion: .opacity.animation(.easeIn(duration: 0.16).delay(0.06)),
                                        removal: .opacity.animation(.easeOut(duration: 0.04))
                                    )
                                )
                        } else {
                            compactControlsCapsule
                                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _, width in
                                    if width > 0 {
                                        compactWidth = width
                                    }
                                }
                                .transition(
                                    .asymmetric(
                                        insertion: .opacity.animation(.easeIn(duration: 0.15).delay(0.10)),
                                        removal: .opacity.animation(.easeOut(duration: 0.05))
                                    )
                                )
                        }
                    }
                    .frame(width: searchBarWidth, height: controlHeight, alignment: .trailing)
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .glassEffectID("searchControl", in: morphNamespace)
                    .padding(.trailing, trailingReserve)

                    if isSearching {
                        expandedTrailingAccessory(AnyView(closeSearchButton))
                            .frame(width: controlHeight, height: controlHeight)
                            .glassEffect(.regular.interactive(), in: Circle())
                            .glassEffectID(configuration.trailingExpandedGlassID, in: morphNamespace)
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.animation(.easeIn(duration: 0.16).delay(0.05))
                                        .combined(with: .scale(scale: 0.70)),
                                    removal: .opacity.animation(.easeOut(duration: 0.08))
                                        .combined(with: .scale(scale: 0.60))
                                )
                            )
                    } else if let rootHiddenPageSwitcher {
                        RootHiddenPageSwitcherButton(switcher: rootHiddenPageSwitcher)
                            .frame(width: controlHeight, height: controlHeight)
                            .glassEffect(.regular.interactive(), in: Circle())
                            .glassEffectID("hiddenPageSwitcher", in: morphNamespace)
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.animation(.easeIn(duration: 0.15).delay(0.14))
                                        .combined(with: .scale(scale: 0.72)),
                                    removal: .opacity.animation(.easeOut(duration: 0.08))
                                        .combined(with: .scale(scale: 0.60))
                                )
                            )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .frame(height: controlHeight)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _, width in
            if width > 0 {
                measuredRowWidth = width
            }
        }
        .padding(.horizontal, 16)
        .animation(.smooth(duration: 0.4), value: isSearching)
        .onAppear {
            if hasNonEmptySearchText, !isSearching {
                isSearching = true
            }
        }
        .onChange(of: searchText) { _, _ in
            if hasNonEmptySearchText, !isSearching {
                withAnimation(.smooth(duration: 0.4)) {
                    isSearching = true
                }
            }
        }
        .onChange(of: isSearching) { _, searching in
            if !searching {
                hasAcquiredSearchFocus = false
            }
        }
        .onChange(of: isSearchFocused.wrappedValue) { wasFocused, isFocused in
            if isFocused {
                hasAcquiredSearchFocus = true
            } else if wasFocused, isSearching, hasAcquiredSearchFocus, !hasNonEmptySearchText {
                collapseEmptySearch()
            }
        }
    }

    private var hasNonEmptySearchText: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var compactControlsCapsule: some View {
        HStack(spacing: 0) {
            searchButton
            compactAccessory()
        }
        .frame(height: controlHeight)
    }

    private var pushedMorphControl: some View {
        GlassEffectContainer(spacing: 10) {
            if isSearching {
                HStack(spacing: 8) {
                    RootMorphSearchQueryField(
                        searchText: $searchText,
                        isSearchFocused: isSearchFocused,
                        prompt: configuration.searchPrompt,
                        fieldAccessibilityID: configuration.fieldAccessibilityID,
                        clearAccessibilityID: configuration.clearAccessibilityID,
                        dismissesFocusOnNonEmptySubmit: configuration.dismissesFocusOnNonEmptySubmit,
                        onSubmit: onSubmit
                    )
                    .frame(width: pushedExpandedWidth, height: controlHeight)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .glassEffectID("searchControl", in: morphNamespace)
                    .glassEffectTransition(.matchedGeometry)

                    closeSearchButton
                        .frame(width: controlHeight, height: controlHeight)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
            } else {
                searchButton
                    .frame(width: controlHeight, height: controlHeight)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .glassEffectID("searchControl", in: morphNamespace)
                    .glassEffectTransition(.matchedGeometry)
            }
        }
        .animation(.smooth(duration: 0.4), value: isSearching)
    }

    private var searchButton: some View {
        Button(action: beginSearch) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: controlHeight, height: controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(configuration.searchButtonAccessibilityLabel)
        .accessibilityIdentifier(configuration.searchButtonAccessibilityID)
    }

    private var closeSearchButton: some View {
        Button(action: cancelSearch) {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: controlHeight, height: controlHeight)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("取消")
        .accessibilityIdentifier(configuration.cancelAccessibilityID)
    }

    private func beginSearch() {
        withAnimation(.smooth(duration: 0.4)) {
            isSearching = true
        }
    }

    private func cancelSearch() {
        searchText = ""
        collapseEmptySearch()
    }

    private func collapseEmptySearch() {
        isSearchFocused.wrappedValue = false
        // Preserve scroll-driven title visibility; if closing search actually
        // scrolls back to top, onScrollGeometryChange updates titleState.
        hasAcquiredSearchFocus = false
        withAnimation(.smooth(duration: 0.4)) {
            isSearching = false
        }
    }
}

struct RootMorphSearchQueryField: View {
    @Binding var searchText: String
    var isSearchFocused: FocusState<Bool>.Binding
    let prompt: String
    let fieldAccessibilityID: String
    let clearAccessibilityID: String
    let dismissesFocusOnNonEmptySubmit: Bool
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $searchText)
                .focused(isSearchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        isSearchFocused.wrappedValue = false
                    } else {
                        if dismissesFocusOnNonEmptySubmit {
                            isSearchFocused.wrappedValue = false
                        }
                        onSubmit()
                    }
                }
                .accessibilityIdentifier(fieldAccessibilityID)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    isSearchFocused.wrappedValue = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索文字")
                .accessibilityIdentifier(clearAccessibilityID)
            }
        }
        .font(.body)
        .padding(.horizontal, 14)
        .task {
            guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !isSearchFocused.wrappedValue else { return }
            await Task.yield()
            isSearchFocused.wrappedValue = true
        }
    }
}

private struct RootHiddenPageSwitcherButton: UIViewRepresentable {
    let switcher: RootHiddenPageSwitcher

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.showsMenuAsPrimaryAction = true
        button.tintColor = .label
        let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        button.setImage(
            UIImage(systemName: "line.3.horizontal.decrease", withConfiguration: configuration),
            for: .normal
        )
        button.accessibilityIdentifier = "root.hiddenPageSwitcher"
        button.accessibilityLabel = "切换页面"
        button.menu = makeMenu()
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        button.menu = makeMenu()
    }

    private func makeMenu() -> UIMenu {
        let actions = switcher.pages.map { page in
            UIAction(
                title: page.title,
                image: UIImage(systemName: page.systemImage),
                state: page == switcher.currentPage ? .on : .off
            ) { _ in
                switcher.onSelect(page)
            }
        }
        return UIMenu(title: "", options: .singleSelection, children: actions)
    }
}
