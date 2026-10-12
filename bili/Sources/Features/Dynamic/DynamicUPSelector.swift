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
        NavigationStack {
            List {
                ForEach(model.owners.filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }, id: \.mid) { owner in
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
                if model.isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    if let error = model.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                    }
                    if model.hasMore || model.errorMessage != nil {
                        Button(model.errorMessage == nil ? "加载更多关注的 UP" : "重试") {
                            Task { await model.loadMore() }
                        }
                    } else if model.owners.isEmpty {
                        Text("暂无关注的 UP 主").foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索已加载的 UP 主")
            .navigationTitle("选择 UP 主")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .task { await model.loadInitial() }
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
    private let api: BiliAPIClient
    private var identity: String?
    private var nextPage = 1

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

    private func append(_ incoming: [VideoOwner]) {
        var seen = Set(owners.map(\.mid))
        owners += incoming.filter { $0.mid > 0 && seen.insert($0.mid).inserted }
    }
}
