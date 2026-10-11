import SwiftUI
import Combine

// A read-only space destination reusing the account-library API and video rows.
// It never reads another interaction account's folders or exposes management actions.
struct UploaderFavoriteFolderContentPage: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var libraryStore: LibraryStore
    let folder: FavoriteFolder

    var body: some View {
        let _ = sessionStore.accountConfigurationVersion
        let _ = libraryStore.guestModeEnabled
        UploaderFavoriteFolderList(folder: folder, api: dependencies.api)
            .id(UploaderSpaceRequestIdentity(dependencies.api.requestSnapshot()))
    }
}

private struct UploaderFavoriteFolderList: View {
    let folder: FavoriteFolder
    @StateObject private var model: UploaderFavoriteFolderViewModel

    init(folder: FavoriteFolder, api: BiliAPIClient) {
        self.folder = folder
        _model = StateObject(wrappedValue: UploaderFavoriteFolderViewModel(folderID: folder.id, api: api))
    }

    var body: some View {
        List {
            if model.entries.isEmpty {
                if model.state.isLoading { LibraryLoadingRow(title: "正在加载收藏夹") }
                else if case .failed(let message) = model.state {
                    LibraryErrorRow(title: "收藏夹加载失败", message: message) { Task { await model.refresh() } }
                } else { LibraryEmptyRow(title: "这个收藏夹还没有视频", systemImage: "folder") }
            } else {
                ForEach(model.entries) { item in
                    VideoRouteLink(item.videoItem) {
                        LibraryVideoRow(item: item, timestampTitle: "收藏时间")
                    }
                        .task { await model.loadMoreIfNeeded(current: item) }
                }
                if model.state.isLoading { LibraryLoadingRow(title: "正在加载收藏夹") }
                else if case .failed(let message) = model.state {
                    LibraryErrorRow(title: "收藏夹刷新失败", message: message) { Task { await model.refresh() } }
                }
                if model.loadMoreState.isLoading { LibraryLoadingRow(title: "正在加载更多收藏") }
                else if case .failed(let message) = model.loadMoreState {
                    LibraryErrorRow(title: "更多收藏加载失败", message: message) { Task { await model.loadMore() } }
                } else if model.hasMore {
                    LibraryLoadMoreTriggerRow(title: "正在加载更多收藏") { Task { await model.loadMore() } }
                }
            }
        }
        .standardPageHorizontalContentMargins(20)
        .nativeTopScrollEdgeEffect()
        .navigationTitle(folder.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("刷新", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                    .disabled(model.state.isLoading || model.loadMoreState.isLoading)
                    .tint(.primary)
            }
        }
        .task { if model.state == .idle { await model.refresh() } }
        .refreshable { await model.refresh() }
    }
}

@MainActor
final class UploaderFavoriteFolderViewModel: ObservableObject {
    @Published private(set) var entries: [AccountVideoEntry] = []
    @Published private(set) var state: LoadingState = .idle
    @Published private(set) var loadMoreState: LoadingState = .idle
    @Published private(set) var hasMore = false
    private let api: BiliAPIClient
    private let folderID: Int
    private let snapshot: BiliAPIClient.RequestSnapshot
    private var page = 1

    init(folderID: Int, api: BiliAPIClient) {
        self.folderID = folderID
        self.api = api
        snapshot = api.requestSnapshot()
    }

    private var mayApply: Bool {
        !Task.isCancelled && UploaderSpaceRequestIdentity(snapshot) == UploaderSpaceRequestIdentity(api.requestSnapshot())
    }

    func refresh() async {
        guard mayApply, !state.isLoading, !loadMoreState.isLoading else { return }
        state = .loading
        defer { if Task.isCancelled { state = .idle } }
        do {
            let result = try await api.fetchFavoriteFolderVideoPage(folderID: folderID, viewerSnapshot: snapshot)
            guard mayApply else { return }
            var seen = Set<String>()
            entries = result.entries.filter { seen.insert($0.id).inserted }
            page = 1
            hasMore = result.hasMore && !entries.isEmpty
            loadMoreState = .idle
            state = .loaded
        } catch {
            guard mayApply else { return }
            state = .failed(error.localizedDescription)
        }
    }

    func loadMoreIfNeeded(current: AccountVideoEntry) async {
        guard entries.last?.id == current.id, loadMoreState == .idle else { return }
        await loadMore()
    }

    func loadMore() async {
        guard mayApply, hasMore, !state.isLoading, !loadMoreState.isLoading else { return }
        loadMoreState = .loading
        defer { if Task.isCancelled { loadMoreState = .idle } }
        do {
            let result = try await api.fetchFavoriteFolderVideoPage(folderID: folderID, page: page + 1, viewerSnapshot: snapshot)
            guard mayApply else { return }
            var seen = Set(entries.map(\.id))
            let incoming = result.entries.filter { seen.insert($0.id).inserted }
            entries.append(contentsOf: incoming)
            page += 1
            hasMore = result.hasMore && !incoming.isEmpty
            loadMoreState = .idle
        } catch {
            guard mayApply else { return }
            loadMoreState = .failed(error.localizedDescription)
        }
    }
}
