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
    @State private var containerWidth: CGFloat = 0
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
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _, width in
            if width > 0 {
                containerWidth = width
            }
        }
        .safeAreaInset(edge: .top, spacing: 18) {
            if isRootTabContent {
                SearchMorphTopBar(
                    titleState: titleState,
                    isSearching: $isSearching,
                    containerWidth: containerWidth,
                    viewModel: holder.viewModel,
                    searchText: $searchText,
                    isSearchFocused: isSearchFocused,
                    onSubmit: onSubmit
                )
            }
        }
        .toolbar {
            if !isRootTabContent {
                SearchTopBar(
                    titleState: titleState,
                    isRootTabContent: isRootTabContent,
                    isSearching: $isSearching,
                    containerWidth: containerWidth,
                    viewModel: holder.viewModel,
                    searchText: $searchText,
                    isSearchFocused: isSearchFocused,
                    onSubmit: onSubmit
                )
            }
        }
        .toolbarVisibility(isRootTabContent ? .hidden : .visible, for: .navigationBar)
        .toolbarTitleDisplayMode(.inline)
    }
}
