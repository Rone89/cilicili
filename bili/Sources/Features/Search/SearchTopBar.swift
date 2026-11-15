import SwiftUI

/// Page-owned Search top bar mirroring the Mine bar: a fading title beside a
/// glass search capsule that morphs between a 44pt circular search button and
/// a full-width search field, plus a circular glass settings button.
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
            if !isSearching, titleState.progress <= 0.9 {
                SearchMorphTitle(state: titleState)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
            if isSearching {
                searchField
            } else {
                searchButton
                if showsSettings, let viewModel {
                    SearchFilterToolbarMenu(viewModel: viewModel, iconPointSize: 18)
                        .frame(width: controlHeight, height: controlHeight)
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

    private var searchButton: some View {
        Button {
            isSearchFocused.wrappedValue = true
            withAnimation(.smooth(duration: 0.35)) { isSearching = true }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: controlHeight, height: controlHeight)
                .contentShape(Circle())
                .glassEffect(.regular.interactive(), in: Circle())
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
