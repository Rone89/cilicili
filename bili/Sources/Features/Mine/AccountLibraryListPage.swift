import SwiftUI

struct AccountLibraryListPage: View {
    let kind: AccountLibraryKind
    @ObservedObject var viewModel: MineViewModel
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var libraryStore: LibraryStore

    @State private var selectedIDs = Set<String>()
    @State private var editMode: EditMode = .inactive
    @State private var confirmsClear = false

    var body: some View {
        List(selection: managementEnabled ? $selectedIDs : nil) {
            Section {
                content
            }
        }
        .modifier(AccountLibraryVideoManagementModifier(
            controller: viewModel.libraryManagement, enabled: managementEnabled, entries: items,
            source: nil, folders: viewModel.favoriteFolders,
            selection: $selectedIDs, editMode: $editMode, reload: reload
        ))
        .modifier(FavoriteFolderManagementModifier(
            viewModel: viewModel, controller: viewModel.libraryManagement,
            enabled: kind == .favorites && sessionStore.isLoggedIn
        ))
        .nativeTopScrollEdgeEffect()
        .bottomScrollEdgeBlurFallback(isEnabled: !editMode.isEditing)
        .standardPageHorizontalContentMargins(libraryStore.standardPageHorizontalInset)
        .hiddenInlineNavigationTitle()
        .confirmationDialog("清空稍后再看？", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button("清空全部", role: .destructive) {
                Task {
                    _ = await viewModel.libraryManagement.mutate(purpose: .historyRead) { context in
                        guard let displayed = viewModel.libraryManagement.displayedContexts[.historyRead] else { throw CancellationError() }
                        try await viewModel.libraryManagement.api.clearWatchLater(context: displayed)
                    }
                    selectedIDs = []; await reload()
                }
            }
            Button("取消", role: .cancel) {}
        } message: { Text("将移除该账号稍后再看中的全部视频，此操作不能撤销。") }
        .toolbar {
            if managementEnabled {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let resume = items.first(where: { $0.resumeTime != nil }) ?? items.first {
                            VideoRouteLink(resume.videoItem) { Label("继续播放", systemImage: "play.fill") }
                        }
                        Button("清空稍后再看", systemImage: "trash", role: .destructive) { confirmsClear = true }
                            .disabled(items.isEmpty)
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityIdentifier("library.watchLater.actions")
                    .disabled(viewModel.libraryManagement.isBusy)
                }
            }
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
            selectedIDs = []; editMode = .inactive
            guard !viewModel.libraryManagement.isBusy else { return }
            await viewModel.synchronizeManagedLibrary(kind: kind)
            await loadIfNeeded()
        }
        .refreshable {
            await reload()
        }
    }

    @ViewBuilder
    private var content: some View {
        if !sessionStore.isLoggedIn {
            LibraryEmptyRow(title: kind.loggedOutTitle, systemImage: kind.systemImage)
        } else if items.isEmpty && state.isLoading {
            LibraryLoadingRow(title: kind.loadingTitle)
        } else if items.isEmpty, case .failed(let message) = state {
            LibraryErrorRow(title: kind.errorTitle, message: message) {
                Task { await reload() }
            }
        } else if kind == .favorites {
            favoriteFolderContent
        } else if items.isEmpty {
            LibraryEmptyRow(title: kind.emptyTitle, systemImage: kind.systemImage)
        } else {
            ForEach(items) { item in
                AccountLibraryManagedVideoRow(item: item, timestampTitle: kind.timestampTitle,
                    isEditing: managementEnabled && editMode.isEditing,
                    canManage: managementEnabled && (item.aid ?? 0) > 0) {
                    Task {
                        await viewModel.libraryManagement.perform(entries: [item], source: nil, action: .remove)
                        await reload()
                    }
                }
                .task {
                    await loadMoreIfNeeded(current: item)
                }
            }

            if state.isLoading {
                LibraryLoadingRow(title: kind.loadingTitle)
            } else if loadMoreState.isLoading {
                LibraryLoadingRow(title: kind.loadMoreTitle)
            } else if case .failed(let message) = state {
                LibraryErrorRow(title: kind.errorTitle, message: message) {
                    Task { await reload() }
                }
            } else if case .failed(let message) = loadMoreState {
                LibraryErrorRow(title: kind.loadMoreErrorTitle, message: message) {
                    Task { await loadMore() }
                }
            } else if hasMore {
                LibraryLoadMoreTriggerRow(title: kind.loadMoreTitle) {
                    Task { await loadMore() }
                }
            }
        }
    }

    private var favoriteFolderContent: some View {
        FavoriteFolderManagementContent(viewModel: viewModel, controller: viewModel.libraryManagement)
    }

    private var managementEnabled: Bool {
        sessionStore.isLoggedIn && kind == .watchLater
    }
    private var managedTaskID: String {
        return "\(sessionStore.accountConfigurationVersion)-\(sessionStore.interactionAccountCredentialVersion)-\(sessionStore.historyAccountCredentialVersion)-\(sessionStore.playbackCredentialVersion)-\(libraryStore.accountLibraryRevision(for: kind == .watchLater ? .historyRead : .interaction))"
    }

    private var items: [AccountVideoEntry] {
        switch kind {
        case .history:
            return viewModel.accountHistory
        case .favorites:
            return viewModel.accountFavorites
        case .watchLater:
            return viewModel.accountWatchLater
        }
    }

    private var state: LoadingState {
        switch kind {
        case .history:
            return viewModel.historyState
        case .favorites:
            return viewModel.favoriteState
        case .watchLater:
            return viewModel.watchLaterState
        }
    }

    private var loadMoreState: LoadingState {
        switch kind {
        case .history:
            return viewModel.historyLoadMoreState
        case .favorites, .watchLater:
            return .idle
        }
    }

    private var hasMore: Bool {
        switch kind {
        case .history:
            return viewModel.historyHasMore
        case .favorites, .watchLater:
            return false
        }
    }

    private func loadIfNeeded() async {
        if kind != .history, state != .idle { return }
        guard sessionStore.isLoggedIn, items.isEmpty, !state.isLoading else { return }
        await reload()
    }

    private func reload() async {
        guard !viewModel.libraryManagement.isBusy else { return }
        switch kind {
        case .history:
            await viewModel.refreshHistory()
        case .favorites:
            await viewModel.refreshFavorites()
        case .watchLater:
            await viewModel.refreshWatchLater()
        }
    }

    private func loadMoreIfNeeded(current item: AccountVideoEntry) async {
        switch kind {
        case .history:
            await viewModel.loadMoreHistoryIfNeeded(current: item)
        case .favorites, .watchLater:
            break
        }
    }

    private func loadMore() async {
        switch kind {
        case .history:
            await viewModel.loadMoreHistory()
        case .favorites, .watchLater:
            break
        }
    }
}
