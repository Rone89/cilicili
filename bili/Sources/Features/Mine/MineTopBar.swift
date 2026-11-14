import SwiftUI
import UIKit

/// Page-owned Mine top bar mirroring the home/dynamic chrome: a large title
/// that fades on scroll plus a circular liquid-glass search button. Tapping the
/// button swaps the row for an inline search field that filters the page.
struct MineTopBar: View {
    @ObservedObject var titleState: FeedChromeTitleState
    @Binding var searchText: String
    @Binding var isSearching: Bool
    var isSearchFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 10) {
            if isSearching {
                searchField
                    .transition(.scale(scale: 0.85, anchor: .trailing).combined(with: .opacity))
                Button("取消") {
                    isSearchFocused.wrappedValue = false
                    searchText = ""
                    isSearching = false
                    titleState.reset()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .fixedSize()
                .accessibilityIdentifier("mine.search.cancel")
                .transition(.opacity)
            } else {
                if titleState.progress <= 0.9 {
                    MineTopBarTitle(state: titleState)
                        .transition(.opacity)
                }
                Spacer(minLength: 8)
                searchButton
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: MineTopBarLayout.controlHeight)
        .frame(maxWidth: .infinity)
        .animation(.smooth(duration: 0.3), value: isSearching)
    }

    private var searchButton: some View {
        MineSearchGlassButton {
            isSearching = true
            isSearchFocused.wrappedValue = true
        }
        .frame(width: MineTopBarLayout.controlHeight, height: MineTopBarLayout.controlHeight)
        .glassEffect(.regular.interactive(), in: Circle())
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("搜索我的页功能", text: $searchText)
                .focused(isSearchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { isSearchFocused.wrappedValue = false }
                .accessibilityIdentifier("mine.search.field")
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索文字")
                .accessibilityIdentifier("mine.search.clear")
            }
        }
        .font(.body)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: MineTopBarLayout.controlHeight)
        .glassEffect(.regular.interactive(), in: Capsule())
        .task {
            await Task.yield()
            isSearchFocused.wrappedValue = true
        }
    }
}

enum MineTopBarLayout {
    static let controlHeight: CGFloat = 44
}

private struct MineTopBarTitle: View {
    @ObservedObject var state: FeedChromeTitleState

    var body: some View {
        let progress = state.progress
        Text(AppTab.mine.title)
            .font(.system(size: 32, weight: .bold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .fixedSize(horizontal: true, vertical: false)
            .offset(y: -progress * FeedChromeTitleState.slideDistance)
            .opacity(1 - progress)
            .accessibilityIdentifier("mine.feed.title")
            .accessibilityAddTraits(.isHeader)
            .allowsHitTesting(false)
    }
}

/// UIKit-backed circular search button so the accessibility identifier is
/// exposed reliably (matching the home mode-menu button approach).
private struct MineSearchGlassButton: UIViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        let configuration = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        button.setImage(UIImage(systemName: "magnifyingglass", withConfiguration: configuration), for: .normal)
        button.tintColor = .label
        button.accessibilityIdentifier = "mine.search.button"
        button.accessibilityLabel = "搜索我的页功能"
        button.addAction(
            UIAction { _ in context.coordinator.action() },
            for: .touchUpInside
        )
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.action = action
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        CGSize(width: MineTopBarLayout.controlHeight, height: MineTopBarLayout.controlHeight)
    }

    final class Coordinator {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
    }
}
