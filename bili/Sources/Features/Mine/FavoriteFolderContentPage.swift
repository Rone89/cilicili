import SwiftUI

struct FavoriteFolderContentPage: View {
    let folder: FavoriteFolder
    @ObservedObject var viewModel: MineViewModel
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var libraryStore: LibraryStore

    @State private var selectedIDs = Set<String>()
    @State private var editMode: EditMode = .inactive
    @State private var searchText = ""
    @State private var sortOrder: LibraryVideoOrder = .original

    var body: some View {
        List(selection: managementEnabled ? $selectedIDs : nil) {
            Section {
                if sessionStore.isLoggedIn {
                    HStack {
                        LibrarySearchField(text: $searchText, prompt: "搜索已加载的收藏", identifier: "library.favorite.search.field")
                        LibraryVideoSortMenu(order: $sortOrder, identifier: "library.favorite.sort")
                    }
                }
                content
            } header: {
                if isSearching {
                    Text("仅搜索已加载的 \(items.count) 个内容")
                        .accessibilityIdentifier("library.favorite.search.scope")
                } else if sortOrder != .original {
                    Text("仅排序已加载的 \(items.count) 个内容")
                        .accessibilityIdentifier("library.favorite.sort.scope")
                } else if let count = viewModel.favoriteFolders.first(where: { $0.id == folder.id })?.mediaCount ?? folder.mediaCount {
                    Text("\(count) 个内容")
                }
            }
        }
        .modifier(AccountLibraryVideoManagementModifier(
            controller: viewModel.libraryManagement, enabled: managementEnabled, entries: visibleItems,
            source: folder, folders: viewModel.favoriteFolders,
            selection: $selectedIDs, editMode: $editMode, reload: reload
        ))
        .onChange(of: searchText) { _, _ in selectedIDs = [] }
        .onChange(of: sortOrder) { _, _ in selectedIDs = [] }
        .nativeTopScrollEdgeEffect()
        .standardPageHorizontalContentMargins(libraryStore.standardPageHorizontalInset)
        .hiddenInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(!sessionStore.isLoggedIn || state.isLoading)
            }
        }
        .task(id: managedTaskID) {
            selectedIDs = []; editMode = .inactive; searchText = ""; sortOrder = .original
            guard !viewModel.libraryManagement.isBusy else { return }
            await viewModel.synchronizeManagedLibrary(kind: .favorites, folder: folder)
            await loadIfNeeded()
        }
        .refreshable {
            await reload()
        }
    }

    @ViewBuilder
    private var content: some View {
        if !sessionStore.isLoggedIn {
            LibraryEmptyRow(title: "登录后同步账号收藏", systemImage: "star")
        } else if items.isEmpty && state.isLoading {
            LibraryLoadingRow(title: "正在同步收藏夹")
        } else if items.isEmpty, case .failed(let message) = state {
            LibraryErrorRow(title: "收藏夹同步失败", message: message) {
                Task { await reload() }
            }
        } else if items.isEmpty {
            LibraryEmptyRow(title: "这个收藏夹还没有视频", systemImage: "folder")
        } else {
            if isSearching && visibleItems.isEmpty {
                LibraryEmptyRow(title: "已加载的收藏中没有匹配结果", systemImage: "magnifyingglass")
            }
            ForEach(visibleItems) { item in
                AccountLibraryManagedVideoRow(item: item, timestampTitle: "收藏时间",
                    isEditing: managementEnabled && editMode.isEditing,
                    canManage: managementEnabled && (item.aid ?? 0) > 0) {
                    Task {
                        await viewModel.libraryManagement.perform(entries: [item], source: folder, action: .remove)
                        await reload()
                    }
                }
                .task {
                    if !usesLocalArrangement { await viewModel.loadMoreFavoriteFolderIfNeeded(folder, current: item) }
                }
            }

            if state.isLoading {
                LibraryLoadingRow(title: "正在同步收藏夹")
            } else if loadMoreState.isLoading {
                LibraryLoadingRow(title: "正在加载更多收藏")
            } else if case .failed(let message) = state {
                LibraryErrorRow(title: "收藏夹同步失败", message: message) {
                    Task { await reload() }
                }
            } else if case .failed(let message) = loadMoreState {
                LibraryErrorRow(title: "更多收藏加载失败", message: message) {
                    Task { await viewModel.loadMoreFavoriteFolder(folder) }
                }
            } else if hasMore {
                if usesLocalArrangement {
                    Button(isSearching ? "加载更多收藏后继续搜索" : "加载更多收藏后继续排序") {
                        Task { await viewModel.loadMoreFavoriteFolder(folder) }
                    }
                    .accessibilityIdentifier(isSearching ? "library.favorite.search.loadMore" : "library.favorite.sort.loadMore")
                } else {
                    LibraryLoadMoreTriggerRow(title: "正在加载更多收藏") {
                        Task { await viewModel.loadMoreFavoriteFolder(folder) }
                    }
                }
            }
        }
    }

    private var managementEnabled: Bool {
        sessionStore.isLoggedIn && folder.canManage(accountMID: viewModel.libraryManagement.api.requestSnapshot(purpose: .interaction).currentUserMID)
    }
    private var managedTaskID: String {
        return "\(sessionStore.accountConfigurationVersion)-\(sessionStore.interactionAccountCredentialVersion)-\(sessionStore.historyAccountCredentialVersion)-\(sessionStore.playbackCredentialVersion)-\(libraryStore.accountFavoriteChangeRevision)"
    }

    private var items: [AccountVideoEntry] {
        viewModel.favoriteFolderEntries[folder.id] ?? []
    }

    private var normalizedSearch: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isSearching: Bool { !normalizedSearch.isEmpty }
    private var usesLocalArrangement: Bool { isSearching || sortOrder != .original }
    private var visibleItems: [AccountVideoEntry] {
        sortOrder.arrange(items, query: normalizedSearch)
    }

    private var state: LoadingState {
        viewModel.favoriteFolderEntryStates[folder.id] ?? .idle
    }

    private var loadMoreState: LoadingState {
        viewModel.favoriteFolderLoadMoreStates[folder.id] ?? .idle
    }

    private var hasMore: Bool {
        viewModel.favoriteFolderHasMore[folder.id] == true
    }

    private func loadIfNeeded() async {
        if state != .idle { return }
        guard sessionStore.isLoggedIn, items.isEmpty, !state.isLoading else { return }
        await reload()
    }

    private func reload() async {
        guard !viewModel.libraryManagement.isBusy else { return }
        await viewModel.refreshFavoriteFolder(folder)
    }
}
