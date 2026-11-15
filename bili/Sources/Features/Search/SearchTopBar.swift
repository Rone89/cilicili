import SwiftUI

/// Page-owned Search top bar mirroring the Mine bar: a fading title beside a
/// glass search capsule that morphs between a 44pt circular search button and
/// a full-width search field. On the root tab the search button and the
/// settings button share one glass capsule; pushed destinations keep the
/// standalone circular search button.
struct SearchTopBarMorph: View {
    @ObservedObject var titleState: FeedChromeTitleState
    @Binding var isSearching: Bool
    @Binding var searchText: String
    var isSearchFocused: FocusState<Bool>.Binding
    let prompt: String
    let onSubmit: () -> Void
    let onCancel: () -> Void
    var viewModel: SearchViewModel? = nil
    var showsSettings: Bool = false

    private let controlHeight: CGFloat = 44

    var body: some View {
        HStack(spacing: 10) {
            if isSearching {
                // The field is full-width, so the spacer must go: HStack's
                // inter-child spacing would otherwise land between the
                // zero-width spacer and the field, adding 10pt to the left
                // margin only.
                searchField
            } else {
                if titleState.progress <= 0.9 {
                    SearchMorphTitle(state: titleState)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
                if showsSettings, let viewModel {
                    mergedControls(viewModel: viewModel)
                } else {
                    searchButton
                        .glassEffect(.regular.interactive(), in: Circle())
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: controlHeight)
        .frame(maxWidth: .infinity)
        .animation(.smooth(duration: 0.35), value: isSearching)
    }

    /// Root tab: the search button and the settings button share one
    /// liquid-glass capsule, separated by a hairline divider.
    private func mergedControls(viewModel: SearchViewModel) -> some View {
        HStack(spacing: 0) {
            searchButton
            Rectangle()
                .fill(.separator)
                .frame(width: 0.5, height: controlHeight - 18)
            SearchFilterToolbarMenu(viewModel: viewModel, iconPointSize: 18)
                .frame(width: controlHeight, height: controlHeight)
        }
        .glassEffect(.regular.interactive(), in: Capsule())
        .transition(.opacity)
    }

    private var searchButton: some View {
        Button {
            isSearchFocused.wrappedValue = true
            withAnimation(.smooth(duration: 0.35)) { isSearching = true }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: controlHeight, height: controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("搜索")
        .accessibilityIdentifier("search.top.button")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $searchText)
                .focused(isSearchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit(onSubmit)
                .accessibilityIdentifier("search.top.field")
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索文字")
                .accessibilityIdentifier("search.top.clear")
            }

            Button("取消", action: onCancel)
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .fixedSize()
                .accessibilityIdentifier("search.top.cancel")
        }
        .font(.body)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: controlHeight)
        .glassEffect(.regular.interactive(), in: Capsule())
        .task {
            await Task.yield()
            isSearchFocused.wrappedValue = true
        }
    }
}

private struct SearchMorphTitle: View {
    @ObservedObject var state: FeedChromeTitleState

    var body: some View {
        let progress = state.progress
        Text(AppTab.search.title)
            .font(.system(size: 32, weight: .bold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .fixedSize(horizontal: true, vertical: false)
            .offset(y: -progress * FeedChromeTitleState.slideDistance)
            .opacity(1 - progress)
            .accessibilityIdentifier("search.feed.title")
            .accessibilityAddTraits(.isHeader)
            .allowsHitTesting(false)
    }
}
