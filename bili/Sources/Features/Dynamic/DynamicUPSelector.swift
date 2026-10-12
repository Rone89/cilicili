import SwiftUI
import Combine

struct DynamicUPSelector: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: DynamicUPSelectionModel
    @State private var searchText = ""
    let select: (VideoOwner) -> Void

    init(api: BiliAPIClient, recentOwners: [VideoOwner], select: @escaping (VideoOwner) -> Void) {
        _model = StateObject(wrappedValue: DynamicUPSelectionModel(api: api, recentOwners: recentOwners))
        self.select = select
    }

    var body: some View {
        let searching = !model.searchQuery.isEmpty
        let loading = searching ? model.isSearching : model.isLoading
        let error = searching ? model.searchErrorMessage : model.errorMessage
        let hasMore = searching ? model.searchHasMore : model.hasMore
        NavigationStack {
            List {
                ForEach(searching ? model.searchOwners : model.owners, id: \.mid) { owner in
                    Button {
                        select(owner)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            AvatarRemoteImage(urlString: owner.face, pixelSize: 96) {
                                Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
                            }
                            .frame(width: 40, height: 40).clipShape(Circle())
                            Text(owner.name).foregroundStyle(.primary)
                        }
                    }
                    .accessibilityIdentifier("dynamic.up.select.\(owner.mid)")
                }
                if loading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    if let error {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                    }
                    if hasMore || error != nil {
                        Button(error != nil ? "重试" : (searching ? "加载更多搜索结果" : "加载更多关注的 UP")) {
                            Task {
                                if searching { await model.loadSearch() }
                                else { await model.loadMore() }
                            }
                        }
                    } else if searching, model.searchOwners.isEmpty {
                        Text("未找到匹配的已关注 UP 主").foregroundStyle(.secondary)
                    } else if !searching, model.owners.isEmpty {
                        Text("暂无关注的 UP 主").foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: Binding(
                get: { searchText },
                set: { searchText = $0; model.updateSearchQuery($0) }
            ), prompt: "搜索全部已关注 UP 主")
            .navigationTitle("选择 UP 主")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .task { await model.loadInitial() }
            .task(id: model.searchQuery) {
                guard !model.searchQuery.isEmpty else { return }
                do {
                    try await Task.sleep(for: .milliseconds(300))
                } catch {
                    // A newer query or dismissing the sheet cancels the debounce.
                    return
                }
                await model.loadSearch()
            }
        }
        .presentationDetents([.large])
    }
}

@MainActor
final class DynamicUPSelectionModel: ObservableObject {
    @Published private(set) var owners: [VideoOwner]
    @Published private(set) var isLoading = false
    @Published private(set) var hasMore = true
    @Published private(set) var errorMessage: String?
    @Published private(set) var searchQuery = ""
    @Published private(set) var searchOwners: [VideoOwner] = []
    @Published private(set) var isSearching = false
    @Published private(set) var searchHasMore = true
    @Published private(set) var searchErrorMessage: String?
    private let api: BiliAPIClient
    private var identity: String?
    private var nextPage = 1
    private var nextSearchPage = 1
    private var searchRequestID: UUID?

    init(api: BiliAPIClient, recentOwners: [VideoOwner]) {
        self.api = api
        var seen = Set<Int>()
        owners = recentOwners.filter { $0.mid > 0 && seen.insert($0.mid).inserted }
    }

    func loadInitial() async {
        guard identity == nil else { return }
        let context = await api.dynamicFeedRequestContext()
        guard !Task.isCancelled else { return }
        identity = context.cookieHeader
        if let mid = context.currentUserMID, context.isLoggedIn {
            append([VideoOwner(mid: mid, name: "我", face: nil)])
        }
        await loadMore()
    }

    func loadMore() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await api.fetchDynamicFollowings(page: nextPage)
            try Task.checkCancellation()
            let context = await api.dynamicFeedRequestContext()
            guard context.cookieHeader == identity else { throw CancellationError() }
            append(page.list.map(\.owner))
            hasMore = !page.list.isEmpty && (page.total > 0 ? nextPage * 50 < page.total : page.list.count == 50)
            nextPage += 1
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateSearchQuery(_ text: String) {
        let keyword = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard keyword != searchQuery else { return }
        // Invalidate immediately, before the next debounced request starts.
        searchRequestID = nil
        searchQuery = keyword
        searchOwners = []
        nextSearchPage = 1
        searchHasMore = true
        searchErrorMessage = nil
        isSearching = !keyword.isEmpty
    }

    func loadSearch() async {
        guard !searchQuery.isEmpty, searchHasMore, searchRequestID == nil, !Task.isCancelled else { return }
        let keyword = searchQuery
        let requestID = UUID()
        searchRequestID = requestID
        isSearching = true
        searchErrorMessage = nil
        defer {
            if searchRequestID == requestID {
                searchRequestID = nil
                isSearching = false
            }
        }
        do {
            let context = await api.dynamicFeedRequestContext()
            guard identity == nil || context.cookieHeader == identity else { throw CancellationError() }
            guard searchRequestID == requestID, !Task.isCancelled else { return }
            let page = try await api.fetchDynamicFollowings(page: nextSearchPage, name: keyword)
            try Task.checkCancellation()
            let currentContext = await api.dynamicFeedRequestContext()
            guard currentContext.cookieHeader == context.cookieHeader,
                  searchRequestID == requestID, searchQuery == keyword else { return }
            var seen = Set(searchOwners.map(\.mid))
            searchOwners += page.list.map(\.owner).filter { $0.mid > 0 && seen.insert($0.mid).inserted }
            searchHasMore = !page.list.isEmpty && (page.total > 0 ? nextSearchPage * 50 < page.total : page.list.count == 50)
            nextSearchPage += 1
        } catch is CancellationError {
            return
        } catch {
            guard searchRequestID == requestID else { return }
            searchErrorMessage = error.localizedDescription
        }
    }

    private func append(_ incoming: [VideoOwner]) {
        var seen = Set(owners.map(\.mid))
        owners += incoming.filter { $0.mid > 0 && seen.insert($0.mid).inserted }
    }
}
