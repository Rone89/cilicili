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
        .safeAreaInset(edge: .top, spacing: 12) {
            SearchTopBar(
                titleState: titleState,
                searchText: $searchText,
                isSearching: $isSearching,
                isSearchFocused: isSearchFocused,
                prompt: holder.viewModel?.searchPrompt ?? "搜索",
                onSubmit: onSubmit,
                viewModel: holder.viewModel,
                showsSettings: isRootTabContent
            )
        }
        .toolbar(isRootTabContent ? .hidden : .visible, for: .navigationBar)
        .toolbarTitleDisplayMode(.inline)
    }
}
