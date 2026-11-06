#if DEBUG
import Foundation

/// Stable inputs for the production detail route, never selected by a normal launch.
enum UITestVideoDetailNetworkFixture {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-video-detail-network")
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VideoDetailFixtureURLProtocol.self]
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }
}

nonisolated private final class VideoDetailFixtureURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let url = request.url!
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let payload: Any
            switch url.path {
            case "/x/web-interface/view", "/x/web-interface/wbi/view":
                var video = Self.video
                if let aid = query.first(where: { $0.name == "aid" })?.value.flatMap(Int.init) {
                    video["aid"] = aid
                    video["bvid"] = "BVFixtureHome\(aid)"
                }
                if let bvid = query.first(where: { $0.name == "bvid" })?.value {
                    video["bvid"] = bvid
                }
                payload = video
            case "/pgc/view/web/season":
                payload = Self.season
            case "/x/emote/user/panel/web":
                payload = ["packages": [["emote": [["text": "[doge_金箍]",
                    "url": "https://ui-test.invalid/doge.png", "width": 32, "height": 32]]]]]
            case "/x/web-interface/wbi/index/top/feed/rcmd", "/x/web-interface/index/top/feed/rcmd":
                payload = ["item": (1...40).map { index -> [String: Any] in
                    var video = Self.video
                    video["bvid"] = "BVFixtureHome\(index)"
                    video["id"] = index
                    video["aid"] = index
                    video["goto"] = "av"
                    return video
                }]
            case "/x/web-interface/archive/related":
                payload = (1...20).map { index -> [String: Any] in
                    var video = Self.video
                    video["bvid"] = "BVFixtureRelated\(index)"
                    video["aid"] = index + 200
                    video["title"] = "相关视频 \(index)"
                    return video
                }
            case let path where path.contains("playurl"):
                let quality = Int(query.first { $0.name == "qn" }?.value ?? "80") ?? 80
                payload = [
                    "quality": quality, "accept_quality": [80, 64],
                    "accept_description": ["1080P 高清", "720P 高清"],
                    "durl": [["url": "https://ui-test.invalid/video.mp4", "length": Self.fixtureDuration * 1000]],
                    "support_formats": [
                        ["quality": 80, "new_description": "1080P 高清", "format": "mp4"],
                        ["quality": 64, "new_description": "720P 高清", "format": "mp4"],
                    ],
                ]
            case "/x/web-interface/nav":
                payload = ["isLogin": false, "wbi_img": [
                    "img_url": "https://ui-test.invalid/abcdefghijklmnopqrstuvwxyz012345.png",
                    "sub_url": "https://ui-test.invalid/012345abcdefghijklmnopqrstuvwxyz.png",
                ]]
            case "/x/v2/reply/main":
                payload = Self.commentRepliesPayload(query: query)
            default:
                payload = [:] as [String: Any]
            }
            let data = try JSONSerialization.data(withJSONObject: ["code": 0, "data": payload, "result": payload])
            client?.urlProtocol(self, didReceive: HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    /// `--ui-test-comment-pagination`：把评论接口切成每页 20 条、共 60 条的游标分页，
    /// 用于验证“下滑自动续载”不再依赖 SwiftUI 几何回调。
    private static var paginatesComments: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-comment-pagination")
    }

    private static var totalCommentCount: Int {
        paginatesComments ? 60 : 25
    }

    private static func commentRepliesPayload(query: [URLQueryItem]) -> [String: Any] {
        guard paginatesComments else {
            return [
                "replies": (1...totalCommentCount).map(commentPayload),
                "cursor": ["is_end": true],
            ]
        }
        let pageSize = 20
        let offset = commentPageOffset(query: query)
        let start = offset + 1
        let end = min(offset + pageSize, totalCommentCount)
        var cursor: [String: Any] = ["is_end": end >= totalCommentCount]
        if end < totalCommentCount {
            cursor["next"] = String(end)
        }
        return [
            "replies": (start...end).map(commentPayload),
            "cursor": cursor,
        ]
    }

    private static func commentPageOffset(query: [URLQueryItem]) -> Int {
        guard let pagination = query.first(where: { $0.name == "pagination_str" })?.value,
              let data = pagination.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let offset = object["offset"] as? String
        else { return 0 }
        return Int(offset) ?? 0
    }

    private static func commentPayload(_ index: Int) -> [String: Any] {
        // 每 4 条里有一条是长文本，制造参差行高（模拟真实评论区）。
        let filler = index % 4 == 0
            ? String(repeating: "这是一段用来撑高评论行的长文本内容，", count: 18)
            : ""
        return [
            "rpid": index,
            "content": ["message": "详情评论 \(index)\(filler)"],
            "member": ["mid": "1001", "uname": "评论用户"],
        ]
    }

    private static var fixtureDuration: Int {
        ProcessInfo.processInfo.arguments.contains("--ui-test-recovery-long-video") ? 600 : 120
    }

    /// `--ui-test-video-multi-page`：让详情接口返回三个分P，用于分P选择器回归。
    private static var usesMultiPage: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-video-multi-page")
    }

    private static var pages: [[String: Any]] {
        let firstPage: [String: Any] = [
            "cid": 1001, "page": 1, "part": "测试分 P", "duration": Self.fixtureDuration,
        ]
        guard usesMultiPage else { return [firstPage] }
        return [firstPage] + [
            ["cid": 1002, "page": 2, "part": "第二分 P", "duration": Self.fixtureDuration],
            ["cid": 1003, "page": 3, "part": "第三分 P", "duration": Self.fixtureDuration],
        ]
    }

    private static var video: [String: Any] {
        ["aid": 100, "bvid": "BV1xx411c7mD", "cid": 1001,
         "title": "固定视频详情回归", "desc": "视频详情测试正文", "duration": Self.fixtureDuration,
         "pubdate": 1700000000,
         "pic": "https://ui-test.invalid/pic.jpg",
         "owner": ["mid": 1001, "name": "测试 UP", "face": "https://ui-test.invalid/face.png"],
         "dimension": ["width": 1920, "height": 1080, "rotate": 0],
         "pages": Self.pages,
         "stat": ["view": 1000, "like": 20, "reply": Self.totalCommentCount]]
    }

    /// `--start-bvid ep3001`：番剧季信息，三集，用于分集选择器回归。
    private static var season: [String: Any] {
        ["season_id": 30, "media_id": 300, "title": "测试番剧", "season_title": "测试番剧",
         "cover": "https://ui-test.invalid/season.jpg",
         "episodes": (1...3).map { index in episodePayload(index) }]
    }

    private static func episodePayload(_ index: Int) -> [String: Any] {
        let id = 3000 + index
        var episode: [String: Any] = [
            "id": id, "aid": id, "cid": id, "ep_id": id,
            "title": "第\(index)话", "long_title": "分集标题\(index)",
            "cover": "https://ui-test.invalid/ep\(index).jpg",
            "duration": Self.fixtureDuration,
        ]
        episode["badge"] = index == 3 ? "预告" : ""
        return episode
    }
}
#endif
