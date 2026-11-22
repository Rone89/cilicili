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
    let handlesOwnSearchable: Bool
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
        handlesOwnSearchable: Bool = true,
        onSubmit: @escaping () -> Void
    ) {
        self.holder = holder
        self.accessoryStore = accessoryStore
        _searchText = searchText
        self.isSearchFocused = isSearchFocused
        self.activationRequestID = activationRequestID
        self.handlesOwnSearchable = handlesOwnSearchable
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
        .modifier(
            SearchViewOwnSearchableModifier(
                isEnabled: handlesOwnSearchable,
                searchText: $searchText,
                isSearching: $isSearching,
                isSearchFocused: isSearchFocused,
                prompt: holder.viewModel?.searchPrompt ?? "搜索",
                onSubmit: onSubmit
            )
        )
        .onAppear {
            if handlesOwnSearchable {
                activateSearchIfRequested()
            }
        }
        .onChange(of: activationRequestID) { _, _ in
            if handlesOwnSearchable {
                activateSearchIfRequested()
            }
        }
        .toolbar {
            SearchTopBar(
                titleState: titleState,
                isRootTabContent: isRootTabContent,
                viewModel: holder.viewModel
            )
        }
        .toolbarVisibility(.visible, for: .navigationBar)
        .toolbarTitleDisplayMode(.inline)
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

private struct SearchViewOwnSearchableModifier: ViewModifier {
    let isEnabled: Bool
    @Binding var searchText: String
    @Binding var isSearching: Bool
    var isSearchFocused: FocusState<Bool>.Binding
    let prompt: String
    let onSubmit: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
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
        } else {
            content
        }
    }
}
