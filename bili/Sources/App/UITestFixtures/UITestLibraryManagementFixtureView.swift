#if DEBUG
import SwiftUI
import Foundation
import UIKit

struct UITestLibraryManagementFixtureView: View {
    @StateObject private var session: SessionStore
    @StateObject private var library: LibraryStore
    @StateObject private var model: MineViewModel
    @State private var openedTitle = ""
    @State private var copiedLinkForTest = ""
    @State private var composerTarget: DynamicCommentComposerTarget?
    @State private var draft = RichCommentDraft()
    @State private var draftContentID = "fixture-A"
    @State private var composerGeneration = 0
    private let favorites: Bool
    private let showsDetailMenu: Bool
    private let showsCommentComposer: Bool

    init() {
        let args = ProcessInfo.processInfo.arguments
        favorites = args.contains("--library-favorites")
        showsDetailMenu = args.contains("--library-detail-menu")
        showsCommentComposer = args.contains("--library-comment-composer")
        let name = "LibraryManagementFixture.\(UUID().uuidString)"
        let session = SessionStore(keychain: KeychainStore.inMemory(service: name))
        if !args.contains("--library-logged-out") {
            try? session.saveLoginCookies(["SESSDATA":"fixture", "bili_jct":"fixture", "DedeUserID":"1001"], credentialKind: .web)
        }
        let defaults = UserDefaults(suiteName: name)!
        if args.contains("--library-formerly-disabled") {
            defaults.set(false, forKey: "cc.bili.experimental.accountLibraryManagement.v1")
        }
        let library = LibraryStore(userDefaults: defaults)
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
                            VideoDetailMoreMenu(api: model.libraryManagement.api, aid: 1,
                                shareURL: URL(string: "https://www.bilibili.com/video/BVfixture1"),
                                shareSubject: "测试视频 1", shareMessage: "分享测试视频")
                        }
                        ToolbarItem(placement: .bottomBar) {
                            VideoDetailToolbarCommentAction(
                                onComment: {
                                    openedTitle = "发表评论"
                                    if showsCommentComposer { composerTarget = .dynamic }
                                })
                        }
                    }
                    if ProcessInfo.processInfo.arguments.contains("--library-comment-shared-drafts") {
                        ToolbarItem(placement: .bottomBar) {
                            Menu("草稿测试") {
                                Button("重建评论入口") {
                                    draft = RichCommentDraft()
                                    composerGeneration += 1
                                }
                                Button("切换评论目标") {
                                    draftContentID = draftContentID == "fixture-A" ? "fixture-B" : "fixture-A"
                                    draft = RichCommentDraft()
                                    composerGeneration += 1
                                }
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Text(openedTitle.isEmpty ? "未打开视频" : openedTitle)
                            .accessibilityIdentifier("library.fixture.openedVideo")
                            .accessibilityValue(copiedLinkForTest)
                    }
                }
                .background {
                    RichCommentComposerPresenter(
                        target: $composerTarget, draft: { _ in $draft },
                        api: model.libraryManagement.api,
                        contentTarget: ProcessInfo.processInfo.arguments.contains("--library-comment-shared-drafts")
                            ? CommentLikeTarget(oid: draftContentID, type: 1, referer: "") : nil,
                        submit: { _, _, _ in
                            if ProcessInfo.processInfo.arguments.contains("--library-comment-delayed-submit") {
                                try await Task.sleep(for: .seconds(8))
                            }
                        }
                    )
                    .id(composerGeneration)
                    .allowsHitTesting(false)
                }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            guard showsDetailMenu else { return }
            copiedLinkForTest = UIPasteboard.general.string ?? ""
        }
        .environmentObject(session)
        .environmentObject(library)
    }
}

nonisolated private final class LibraryManagementFixtureState: @unchecked Sendable {
    private let lock = NSLock()
    private var didFailWatchBatch = false
    private var didFailMoveRemoval = false
    private var watchIDs = ProcessInfo.processInfo.arguments.contains("--library-batch-progress") ? Array(1...25) : [1, 2, 3]
    private var folderVideos = [9: ProcessInfo.processInfo.arguments.contains("--library-paginated") ? Array(1...30) : [1, 2, 3], 10: [Int]()]
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
        let video: (Int) -> [String: Any] = { id in
            var item: [String: Any] = [
                "aid": id, "bvid": "BVfixture\(id)", "title": "测试视频 \(id)",
                "duration": ProcessInfo.processInfo.arguments.contains("--library-sorting") ? id * 60 : 120,
            ]
            if ProcessInfo.processInfo.arguments.contains("--library-watch-status") {
                if id == 1 { item["progress"] = 30 }
                if id == 2 { item["progress"] = -1 }
                // The third entry deliberately has no progress metadata.
            }
            return item
        }
        var data: [String: Any] = [:]
        switch path {
        case "/x/v2/history/toview": data = ["list": watchIDs.map(video)]
        case "/x/v2/history/toview/add":
            if let aid = Int(body["aid"] ?? ""), !watchIDs.contains(aid) { watchIDs.append(aid) }
        case "/x/v2/history/toview/v2/dels":
            if ProcessInfo.processInfo.arguments.contains("--library-single-removal-failure") {
                return try! JSONSerialization.data(withJSONObject: ["code": -400, "message": "测试移除失败"])
            }
            let retryFixture = ProcessInfo.processInfo.arguments.contains("--library-batch-retry")
            if retryFixture, resources.contains(where: { !watchIDs.contains($0) }) {
                return try! JSONSerialization.data(withJSONObject: ["code": -400, "message": "重复处理了已完成的项目"])
            }
            if ProcessInfo.processInfo.arguments.contains("--library-batch-failure"), resources.contains(21),
               !retryFixture || !didFailWatchBatch {
                didFailWatchBatch = true
                return try! JSONSerialization.data(withJSONObject: ["code": -400, "message": "测试批次失败"])
            }
            watchIDs.removeAll { resources.contains($0) }
        case "/x/v2/history/toview/clear": watchIDs = []
        case "/x/v3/fav/folder/created/list-all":
            data = ["list": [9,10].map { ["id": $0, "mid": 1001, "attr": 2, "title": $0 == 9 ? "来源收藏夹" : "目标收藏夹", "media_count": folderVideos[$0]?.count ?? 0] }]
        case "/x/v3/fav/resource/list":
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
            let id = Int(query?.first { $0.name == "media_id" }?.value ?? "9") ?? 9
            let videos = folderVideos[id] ?? []
            let paginated = ProcessInfo.processInfo.arguments.contains("--library-paginated") && id == 9
            let page = Int(query?.first { $0.name == "pn" }?.value ?? "1") ?? 1
            if paginated {
                let pageVideos = page == 1 ? Array(videos.prefix(20)) : Array(videos.dropFirst(20))
                data = ["medias": pageVideos.map(video), "has_more": page == 1 && videos.count > 20]
            } else {
                data = ["medias": videos.map(video), "has_more": false]
            }
        case "/x/v3/fav/resource/batch-deal":
            let retryFixture = ProcessInfo.processInfo.arguments.contains("--library-move-retry")
            if let add = Int(body["add_media_ids"] ?? "") {
                if retryFixture, resources.contains(where: { (folderVideos[add] ?? []).contains($0) }) {
                    return try! JSONSerialization.data(withJSONObject: ["code": -400, "message": "重复加入目标收藏夹"])
                }
                folderVideos[add] = Array(Set((folderVideos[add] ?? []) + resources)).sorted()
            }
            if let remove = Int(body["del_media_ids"] ?? "") {
                if ProcessInfo.processInfo.arguments.contains("--library-single-removal-failure") {
                    return try! JSONSerialization.data(withJSONObject: ["code": -400, "message": "测试移除失败"])
                }
                if retryFixture, !didFailMoveRemoval {
                    didFailMoveRemoval = true
                    return try! JSONSerialization.data(withJSONObject: ["code": -400, "message": "来源移除暂时失败"])
                }
                folderVideos[remove]?.removeAll { resources.contains($0) }
            }
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
        if request.httpMethod == "POST",
           ProcessInfo.processInfo.arguments.contains("--library-batch-progress") {
            // Simulate a slow server so both sequential batches are observable.
            Thread.sleep(forTimeInterval: 4)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.state.response(request))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
