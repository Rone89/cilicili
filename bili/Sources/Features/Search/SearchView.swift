import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(\.isRootTabContent) private var isRootTabContent
    @ObservedObject var accessoryStore: SearchBottomAccessoryStore
    @ObservedObject var holder: SearchViewModelHolder
    @Binding var searchText: String
    var isSearchFocused: FocusState<Bool>.Binding
    let activationRequestID: Int
    let usesTabBarSearchIntegration: Bool
    let onSubmit: () -> Void
    @State private var isSearching = false
    @State private var handledActivationRequestID = 0
    @StateObject private var titleState = FeedChromeTitleState()

    init(
        holder: SearchViewModelHolder,
        accessoryStore: SearchBottomAccessoryStore,
        searchText: Binding<String>,
        isSearchFocused: FocusState<Bool>.Binding,
        activationRequestID: Int = 0,
        usesTabBarSearchIntegration: Bool = false,
        onSubmit: @escaping () -> Void
    ) {
        self.holder = holder
        self.accessoryStore = accessoryStore
        _searchText = searchText
        self.isSearchFocused = isSearchFocused
        self.activationRequestID = activationRequestID
        self.usesTabBarSearchIntegration = usesTabBarSearchIntegration
        self.onSubmit = onSubmit
    }

    var body: some View {
        if usesTabBarSearchIntegration {
            searchContent
                .toolbar {
                    SearchTopBar(
                        titleState: titleState,
                        isRootTabContent: isRootTabContent,
                        viewModel: holder.viewModel
                    )
                }
                .toolbarVisibility(.visible, for: .navigationBar)
                .toolbarTitleDisplayMode(.inline)
        } else {
            searchContent
                .toolbar {
                    SearchTopBar(
                        titleState: titleState,
                        isRootTabContent: isRootTabContent,
                        viewModel: holder.viewModel
                    )
                }
                .toolbarVisibility(.visible, for: .navigationBar)
                .toolbarTitleDisplayMode(.inline)
                .modifier(
                    SearchViewSearchableModifier(
                        usesTabBarSearchIntegration: false,
                        searchText: $searchText,
                        isSearching: $isSearching,
                        isSearchFocused: isSearchFocused,
                        prompt: holder.viewModel?.searchPrompt ?? "搜索",
                        onSubmit: onSubmit
                    )
                )
                .onAppear {
                    activateSearchIfRequested()
                }
                .onChange(of: activationRequestID) { _, _ in
                    activateSearchIfRequested()
                }
        }
    }

    @ViewBuilder
    private var searchContent: some View {
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

    private func activateSearchIfRequested() {
        guard activationRequestID > 0, activationRequestID != handledActivationRequestID else {
            return
        }
        handledActivationRequestID = activationRequestID
        isSearching = true
        Task { @MainActor in
            await Task.yield()
            isSearchFocused.wrappedValue = true
            try? await Task.sleep(for: .milliseconds(80))
            if isSearching, !isSearchFocused.wrappedValue {
                isSearchFocused.wrappedValue = true
            }
        }
    }
}

private struct SearchViewSearchableModifier: ViewModifier {
    let usesTabBarSearchIntegration: Bool
    @Binding var searchText: String
    @Binding var isSearching: Bool
    var isSearchFocused: FocusState<Bool>.Binding
    let prompt: String
    let onSubmit: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if usesTabBarSearchIntegration {
            // Search is owned by the root `TabView` (`Tab(role: .search)` + `.searchable`) so iOS 26/27
            // morphs the bottom TabBar into the Liquid Glass search field without duplicating a top bar.
            content
        } else {
            content
                .searchable(
                    text: $searchText,
                    isPresented: $isSearching,
                    placement: .automatic,
                    prompt: prompt
                )
                .searchFocused(isSearchFocused)
                .onChange(of: searchText) { _, newValue in
                    if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isSearching {
                        isSearching = true
                    }
                }
                .onSubmit(of: .search) {
                    isSearchFocused.wrappedValue = false
                    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        isSearching = false
                    } else {
                        onSubmit()
                    }
                }
        }
    }
}
