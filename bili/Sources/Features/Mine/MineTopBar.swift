import SwiftUI

struct MineTopBar: ToolbarContent {
    let titleState: FeedChromeTitleState
    let showsTitle: Bool
    let isSearching: Bool
    let onSearch: () -> Void

    var body: some ToolbarContent {
        if !isSearching {
            if showsTitle {
                ToolbarItem(placement: .topBarLeading) {
                    FeedToolbarTitle(
                        title: AppTab.mine.title,
                        state: titleState,
                        accessibilityID: "mine.feed.title"
                    )
                }
                .sharedBackgroundVisibility(.hidden)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("搜索我的页功能")
                .accessibilityIdentifier("mine.search.button")
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }
}

struct MineSearchField: View {
    @Binding var searchText: String
    var isSearchFocused: FocusState<Bool>.Binding
    let onCancel: () -> Void

    private let controlHeight: CGFloat = 44

    var body: some View {
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
        .padding(.horizontal, 16)
        .task {
            await Task.yield()
            isSearchFocused.wrappedValue = true
        }
    }
}
