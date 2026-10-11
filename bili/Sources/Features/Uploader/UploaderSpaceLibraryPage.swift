import SwiftUI
import Combine

enum UploaderSpaceLibraryKind: String {
    case favorites, bangumi
    var title: String { self == .favorites ? "收藏" : "追番" }
}

// Other spaces keep three tabs; public library content opens as a read-only destination.
struct UploaderSpaceLibraryPage: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var libraryStore: LibraryStore
    let owner: VideoOwner
    let kind: UploaderSpaceLibraryKind

    var body: some View {
        let _ = sessionStore.accountConfigurationVersion
        let _ = libraryStore.guestModeEnabled
        UploaderSpaceLibraryContent(owner: owner, kind: kind, api: dependencies.api)
            .id(UploaderSpaceRequestIdentity(dependencies.api.requestSnapshot()))
    }
}

private struct UploaderSpaceLibraryContent: View {
    let kind: UploaderSpaceLibraryKind
    @StateObject private var model: UploaderSpaceLibraryViewModel

    init(owner: VideoOwner, kind: UploaderSpaceLibraryKind, api: BiliAPIClient) {
        self.kind = kind
        _model = StateObject(wrappedValue: UploaderSpaceLibraryViewModel(owner: owner, kind: kind, api: api))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if kind == .favorites {
                    ForEach(model.folders, id: \.folder.id) { item in
                        UploaderFavoriteFolderPreviewCard(item: item, viewModel: model.previewModel)
                    }
                } else if !model.bangumi.isEmpty {
                    UploaderSpaceBangumiGrid(items: model.bangumi) { seasonID in
                        if seasonID == model.bangumi.last?.seasonID, model.loadMoreState == .idle {
                            await model.loadMore()
                        }
                    }
                }
                if model.state == .idle || model.state.isLoading {
                    InlineLoadingStateView(title: "正在加载\(kind.title)")
                } else if case .failed(let message) = model.state {
                    ErrorStateView(title: "\(kind.title)加载失败", message: message) { Task { await model.refresh() } }
                } else if model.folders.isEmpty && model.bangumi.isEmpty {
                    EmptyStateView(title: "暂无\(kind.title)", systemImage: "rectangle.stack", message: "下拉刷新后再试。")
                        .frame(maxWidth: .infinity)
                }
                if model.loadMoreState.isLoading {
                    InlineLoadingStateView(title: "正在加载更多追番")
                } else if case .failed(let message) = model.loadMoreState {
                    ErrorStateView(title: "更多追番加载失败", message: message) { Task { await model.loadMore() } }
                } else if model.hasMore {
                    Button("加载更多追番") { Task { await model.loadMore() } }.frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .task(id: model.folders.map { $0.folder.id }) {
                await model.previewModel.loadFavoriteFolderPreviews(folderIDs: model.folders.map { $0.folder.id })
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .nativeBottomScrollEdgeBlur()
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("刷新", systemImage: "arrow.clockwise") { Task { await refresh() } }
                    .disabled(model.state.isLoading || model.loadMoreState.isLoading)
                    .tint(.primary)
            }
        }
        .task { if model.state == .idle { await model.refresh() } }
        .refreshable { await refresh() }
    }

    private func refresh() async {
        await model.refresh()
        if kind == .favorites {
            await model.previewModel.loadFavoriteFolderPreviews(folderIDs: model.folders.map { $0.folder.id }, force: true)
        }
    }
}

@MainActor
final class UploaderSpaceLibraryViewModel: ObservableObject {
    @Published private(set) var folders: [UploaderSpaceFavoritePreview] = []
    @Published private(set) var bangumi: [UploaderSpaceVideoPreview] = []
    @Published private(set) var state: LoadingState = .idle
    @Published private(set) var loadMoreState: LoadingState = .idle
    @Published private(set) var hasMore = false
    let previewModel: UploaderViewModel
    private let api: BiliAPIClient
    private let mid: Int
    private let kind: UploaderSpaceLibraryKind
    private let snapshot: BiliAPIClient.RequestSnapshot
    private var page = 1

    init(owner: VideoOwner, kind: UploaderSpaceLibraryKind, api: BiliAPIClient) {
        mid = owner.mid
        self.kind = kind
        self.api = api
        snapshot = api.requestSnapshot()
        previewModel = UploaderViewModel(seedOwner: owner, api: api, enhancementEnabled: true)
    }

    private var mayApply: Bool {
        !Task.isCancelled && UploaderSpaceRequestIdentity(snapshot) == UploaderSpaceRequestIdentity(api.requestSnapshot())
    }

    func refresh() async {
        guard mayApply, !state.isLoading, !loadMoreState.isLoading else { return }
        state = .loading
        defer { if Task.isCancelled { state = .idle } }
        do {
            if kind == .favorites {
                let result = try await api.fetchSpaceFavoriteFolders(mid: mid, snapshot: snapshot)
                guard mayApply else { return }
                var seen = Set<Int>()
                folders = result.items.filter { seen.insert($0.folder.id).inserted }
            } else {
                let result = try await api.fetchSpaceBangumiPage(mid: mid, snapshot: snapshot, page: 1)
                guard mayApply else { return }
                var seen = Set<Int>()
                bangumi = result.list.filter { $0.seasonID.map { seen.insert($0).inserted } == true }
                hasMore = !bangumi.isEmpty && (result.total.map { bangumi.count < $0 } ?? (result.list.count == 20))
            }
            page = 1
            loadMoreState = .idle
            state = .loaded
        } catch {
            guard mayApply else { return }
            state = .failed(error.localizedDescription)
        }
    }

    func loadMore() async {
        guard mayApply, kind == .bangumi, hasMore, !state.isLoading, !loadMoreState.isLoading else { return }
        loadMoreState = .loading
        defer { if Task.isCancelled { loadMoreState = .idle } }
        do {
            let result = try await api.fetchSpaceBangumiPage(mid: mid, snapshot: snapshot, page: page + 1)
            guard mayApply else { return }
            var seen = Set(bangumi.compactMap(\.seasonID))
            let incoming = result.list.filter { $0.seasonID.map { seen.insert($0).inserted } == true }
            bangumi.append(contentsOf: incoming)
            page += 1
            hasMore = !incoming.isEmpty && (result.total.map { bangumi.count < $0 } ?? (result.list.count == 20))
            loadMoreState = .idle
        } catch {
            guard mayApply else { return }
            loadMoreState = .failed(error.localizedDescription)
        }
    }
}
