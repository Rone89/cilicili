#if DEBUG
import SwiftUI

/// Exercises the actual dynamic detail → replies sheet with two deterministic API pages.
struct UITestDynamicRepliesFixtureView: View {
    @State private var path = NavigationPath()
    private let api: BiliAPIClient

    init(dependencies: AppDependencies) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DynamicRepliesFixtureURLProtocol.self]
        api = BiliAPIClient(
            session: URLSession(configuration: configuration),
            sessionStore: dependencies.sessionStore,
            libraryStore: dependencies.libraryStore,
            homeRecommendDiagnosticsStore: dependencies.homeRecommendDiagnosticsStore
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            NavigationLink("打开动态详情", value: DynamicDetailTarget.loaded(Self.item))
                .dynamicDetailDestinations(path: $path, api: api)
        }
    }

    private static let item = try! JSONDecoder.bili.decode(DynamicFeedItem.self, from: Data(
        #"{"id_str":"reply-pagination-fixture","type":"DYNAMIC_TYPE_WORD","basic":{"comment_id_str":"456","comment_type":17},"modules":{"module_dynamic":{"desc":{"text":"动态回复分页验证"}}}}"#.utf8
    ))
}

nonisolated private final class DynamicRepliesFixtureURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let url = request.url!
            NSLog("[RepliesProbe] protocol request %@", url.absoluteString)
            let data: [String: Any]
            switch url.path {
            case "/x/v2/reply/main":
                data = ["replies": [Self.comment(id: 100, text: "@提及用户", replyCount: 14)],
                        "cursor": ["is_end": true]]
            case "/x/v2/reply/reply":
                let page = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                    .first(where: { $0.name == "pn" })?.value
                let indices = page == "1" ? Array(1...12) : Array(13...14)
                data = ["page": ["num": page == "1" ? 1 : 2, "size": 12, "count": 14],
                        "replies": indices.map { Self.comment(id: 100 + $0, text: "分页回复\($0)") }]
            default:
                data = [:]
            }
            let body = try JSONSerialization.data(withJSONObject: ["code": 0, "data": data])
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
            NSLog("[RepliesProbe] protocol finished %@", url.path)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func comment(id: Int, text: String, replyCount: Int = 0) -> [String: Any] {
        var content: [String: Any] = ["message": text]
        if id == 100 { content["at_name_to_mid"] = ["提及用户": 1002] }
        return ["rpid": id, "rcount": replyCount, "content": content,
                "member": ["mid": "1001", "uname": "分页用户\(id)"]]
    }
}
#endif
