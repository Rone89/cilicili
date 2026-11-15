import SwiftUI

/// Page-owned Mine top bar: the fading title sits beside a glass search
/// capsule that morphs between a 44pt circular search button and a full-width
/// search field. The morph is driven by the HStack layout change animated with
/// `.smooth`, avoiding `matchedGeometryEffect` layout cycles in insets.
struct MineTopBarMorph: View {
    @ObservedObject var titleState: FeedChromeTitleState
    @Binding var isSearching: Bool
    @Binding var searchText: String
    var isSearchFocused: FocusState<Bool>.Binding
    let onCancel: () -> Void
    /// Whether to show the title (root tab). Pushed destinations hide it
    /// because the navigation bar already carries one.
    let showsTitle: Bool

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
                if showsTitle, titleState.progress <= 0.9 {
                    MineMorphTitle(state: titleState)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
                searchButton
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
        .accessibilityLabel("搜索我的页功能")
        .accessibilityIdentifier("mine.search.button")
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

            Button("取消", action: onCancel)
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .fixedSize()
                .accessibilityIdentifier("mine.search.cancel")
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

private struct MineMorphTitle: View {
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
