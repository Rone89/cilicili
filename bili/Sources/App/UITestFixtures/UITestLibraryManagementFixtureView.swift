#if DEBUG
import SwiftUI
import Foundation

struct UITestLibraryManagementFixtureView: View {
    @StateObject private var session: SessionStore
    @StateObject private var library: LibraryStore
    @StateObject private var model: MineViewModel
    @State private var openedTitle = ""
    private let favorites: Bool
    private let showsDetailMenu: Bool

    init() {
        let args = ProcessInfo.processInfo.arguments
        favorites = args.contains("--library-favorites")
        showsDetailMenu = args.contains("--library-detail-menu")
        let name = "LibraryManagementFixture.\(UUID().uuidString)"
        let session = SessionStore(keychain: KeychainStore(service: name))
        if !args.contains("--library-logged-out") {
            try? session.saveLoginCookies(["SESSDATA":"fixture", "bili_jct":"fixture", "DedeUserID":"1001"], credentialKind: .web)
        }
        let library = LibraryStore(userDefaults: UserDefaults(suiteName: name)!)
        library.setAccountLibraryManagementExperimentEnabled(!args.contains("--library-off"))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LibraryManagementFixtureProtocol.self]
        let api = BiliAPIClient(session: URLSession(configuration: config), sessionStore: session,
                                libraryStore: library, homeRecommendDiagnosticsStore: .shared)
        _session = StateObject(wrappedValue: session)
        _library = StateObject(wrappedValue: library)
        _model = StateObject(wrappedValue: MineViewModel(api: api, sessionStore: session))
    }

    var body: some View {
        NavigationStack {
            AccountLibraryListPage(kind: favorites ? .favorites : .watchLater, viewModel: model)
                .navigationTitle(favorites ? "收藏夹" : "稍后再看")
                .environment(\.openVideoAction, { openedTitle = $0.title })
                .toolbar {
                    if showsDetailMenu {
                        ToolbarItem(placement: .topBarTrailing) {
                            if library.accountLibraryManagementExperimentEnabled {
                                VideoDetailMoreMenu(api: model.libraryManagement.api, aid: 1,
                                    shareURL: URL(string: "https://www.bilibili.com/video/BVfixture1"),
                                    shareSubject: "测试视频 1", shareMessage: "分享测试视频")
                            } else {
                                VideoDetailActionStripShareButton(
                                    shareURL: URL(string: "https://www.bilibili.com/video/BVfixture1"),
                                    shareSubject: "测试视频 1", shareMessage: "分享测试视频", onShareTap: {})
                                    .accessibilityIdentifier("video.detail.share")
                            }
                        }
                        ToolbarItem(placement: .bottomBar) {
                            VideoDetailToolbarCommentAction(
                                onComment: { openedTitle = "发表评论" },
                                onRefresh: { openedTitle = "刷新评论区" })
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Text(openedTitle.isEmpty ? "未打开视频" : openedTitle)
                            .accessibilityIdentifier("library.fixture.openedVideo")
                    }
                }
        }
        .environmentObject(session)
        .environmentObject(library)
    }
}

nonisolated private final class LibraryManagementFixtureState: @unchecked Sendable {
    private let lock = NSLock()
    private var watchIDs = [1, 2, 3]
    private var folderVideos = [9: [1, 2, 3], 10: [Int]()]
    private func bodyData(_ request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
    func response(_ request: URLRequest) -> Data {
        lock.lock(); defer { lock.unlock() }
        let path = request.url!.path
        let fields = URLComponents(string: "https://fixture/?" + String(data: bodyData(request), encoding: .utf8)!)?.queryItems ?? []
        let body = Dictionary(fields.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
        let resources = body["resources"]?.split(separator: ",").compactMap { Int($0.split(separator: ":")[0]) } ?? []
        let video: (Int) -> [String: Any] = { ["aid": $0, "bvid": "BVfixture\($0)", "title": "测试视频 \($0)", "duration": 120] }
        var data: [String: Any] = [:]
        switch path {
        case "/x/v2/history/toview": data = ["list": watchIDs.map(video)]
        case "/x/v2/history/toview/add":
            if let aid = Int(body["aid"] ?? ""), !watchIDs.contains(aid) { watchIDs.append(aid) }
        case "/x/v2/history/toview/v2/dels": watchIDs.removeAll { resources.contains($0) }
        case "/x/v2/history/toview/clear": watchIDs = []
        case "/x/v3/fav/folder/created/list-all":
            data = ["list": [9,10].map { ["id": $0, "mid": 1001, "attr": 2, "title": $0 == 9 ? "来源收藏夹" : "目标收藏夹", "media_count": folderVideos[$0]?.count ?? 0] }]
        case "/x/v3/fav/resource/list":
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
            let id = Int(query?.first { $0.name == "media_id" }?.value ?? "9") ?? 9
            data = ["medias": (folderVideos[id] ?? []).map(video), "has_more": false]
        case "/x/v3/fav/resource/batch-deal":
            if let add = Int(body["add_media_ids"] ?? "") { folderVideos[add] = Array(Set((folderVideos[add] ?? []) + resources)).sorted() }
            if let remove = Int(body["del_media_ids"] ?? "") { folderVideos[remove]?.removeAll { resources.contains($0) } }
        default: break
        }
        return try! JSONSerialization.data(withJSONObject: ["code": 0, "data": data])
    }
}

nonisolated private final class LibraryManagementFixtureProtocol: URLProtocol {
    private static let state = LibraryManagementFixtureState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.state.response(request))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
