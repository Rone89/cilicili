import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(\.isRootTabContent) private var isRootTabContent
    @ObservedObject var accessoryStore: SearchBottomAccessoryStore
    @ObservedObject var holder: SearchViewModelHolder
    @Binding var searchText: String
    var isSearchFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    @State private var isSearching = false
    @StateObject private var titleState = FeedChromeTitleState()

    init(
        holder: SearchViewModelHolder,
        accessoryStore: SearchBottomAccessoryStore,
        searchText: Binding<String>,
        isSearchFocused: FocusState<Bool>.Binding,
        onSubmit: @escaping () -> Void
    ) {
        self.holder = holder
        self.accessoryStore = accessoryStore
        _searchText = searchText
        self.isSearchFocused = isSearchFocused
        self.onSubmit = onSubmit
    }

    var body: some View {
        Group {
            if let viewModel = holder.viewModel {
                SearchContentView(
                    viewModel: viewModel,
                    showsHotSearches: libraryStore.showsHotSearches,
                    accessoryStore: accessoryStore,
                    titleState: titleState
                )
            } else {
                SearchLoadingList()
                    .task {
                        holder.configure(api: dependencies.api)
                }
            }
        }
        .safeAreaPadding(.top, isRootTabContent && !isSearching ? 8 : 0)
        // Keep the same breathing room below the field as the home toolbar.
        .safeAreaInset(edge: .top, spacing: isSearching ? 18 : 0) {
            if isSearching {
                SearchQueryField(
                    searchText: $searchText,
                    isSearchFocused: isSearchFocused,
                    prompt: holder.viewModel?.searchPrompt ?? "搜索",
                    onSubmit: onSubmit,
                    onCancel: cancelSearch
                )
            }
        }
        .toolbar {
            SearchTopBar(
                titleState: titleState,
                isRootTabContent: isRootTabContent,
                isSearching: isSearching,
                viewModel: holder.viewModel,
                onSearch: beginSearch
            )
        }
        .toolbarVisibility(isRootTabContent && isSearching ? .hidden : .visible, for: .navigationBar)
        .toolbarTitleDisplayMode(.inline)
    }

    private func beginSearch() {
        isSearchFocused.wrappedValue = true
        withAnimation(.smooth(duration: 0.35)) { isSearching = true }
    }

    private func cancelSearch() {
        isSearchFocused.wrappedValue = false
        searchText = ""
        titleState.reset()
        withAnimation(.smooth(duration: 0.35)) { isSearching = false }
    }
}
