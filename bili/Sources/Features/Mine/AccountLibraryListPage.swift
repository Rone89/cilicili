import SwiftUI

struct AccountLibraryListPage: View {
    let kind: AccountLibraryKind
    @ObservedObject var viewModel: MineViewModel
    @EnvironmentObject private var sessionStore: SessionStore

    var body: some View {
        List {
            Section {
                content
            }
        }
        .nativeTopScrollEdgeEffect()
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
        .task {
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
                VideoRouteLink(item.videoItem) {
                    LibraryVideoRow(item: item, timestampTitle: kind.timestampTitle)
                }
            }

            if state.isLoading {
                LibraryLoadingRow(title: kind.loadingTitle)
            } else if case .failed(let message) = state {
                LibraryErrorRow(title: kind.errorTitle, message: message) {
                    Task { await reload() }
                }
            }
        }
    }

    @ViewBuilder
    private var favoriteFolderContent: some View {
        if favoriteFolders.isEmpty {
            LibraryEmptyRow(title: kind.emptyTitle, systemImage: kind.systemImage)
        } else {
            ForEach(favoriteFolders) { folder in
                NavigationLink {
                    FavoriteFolderContentPage(folder: folder, viewModel: viewModel)
                } label: {
                    FavoriteFolderRow(folder: folder)
                }
            }
        }
    }

    private var items: [AccountVideoEntry] {
        switch kind {
        case .history:
            return viewModel.accountHistory
        case .favorites:
            return viewModel.accountFavorites
        }
    }

    private var state: LoadingState {
        switch kind {
        case .history:
            return viewModel.historyState
        case .favorites:
            return viewModel.favoriteState
        }
    }

    private var favoriteFolders: [FavoriteFolder] {
        viewModel.favoriteFolders
    }

    private func loadIfNeeded() async {
        guard sessionStore.isLoggedIn, items.isEmpty, !state.isLoading else { return }
        await reload()
    }

    private func reload() async {
        switch kind {
        case .history:
            await viewModel.refreshHistory()
        case .favorites:
            await viewModel.refreshFavorites()
        }
    }
}
