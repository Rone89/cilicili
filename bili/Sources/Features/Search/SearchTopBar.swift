import SwiftUI

struct SearchTopBar: ToolbarContent {
    let titleState: FeedChromeTitleState
    let isRootTabContent: Bool
    let isSearching: Bool
    let viewModel: SearchViewModel?
    let onSearch: () -> Void

    private let controlHeight: CGFloat = 44

    var body: some ToolbarContent {
        if !isSearching {
            if isRootTabContent {
                ToolbarItem(placement: .topBarLeading) {
                    FeedToolbarTitle(
                        title: AppTab.search.title,
                        state: titleState,
                        accessibilityID: "search.feed.title"
                    )
                }
                .sharedBackgroundVisibility(.hidden)
            }

            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 0) {
                    searchButton
                    if isRootTabContent, let viewModel {
                        Rectangle()
                            .fill(.separator)
                            .frame(width: 0.5, height: controlHeight - 18)
                        SearchFilterToolbarMenu(viewModel: viewModel, iconPointSize: 18)
                            .frame(width: controlHeight, height: controlHeight)
                    }
                }
                .frame(height: controlHeight)
                .glassEffect(.regular.interactive(), in: Capsule())
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    private var searchButton: some View {
        Button(action: onSearch) {
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
}

struct SearchQueryField: View {
    @Binding var searchText: String
    var isSearchFocused: FocusState<Bool>.Binding
    let prompt: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    private let controlHeight: CGFloat = 44

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
        .padding(.horizontal, 16)
        .task {
            await Task.yield()
            isSearchFocused.wrappedValue = true
        }
    }
}
