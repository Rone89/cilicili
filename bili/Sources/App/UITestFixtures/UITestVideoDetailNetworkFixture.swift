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
                payload = Self.video
            case "/x/emote/user/panel/web":
                payload = ["packages": [["emote": [["text": "[doge_金箍]",
                    "url": "https://ui-test.invalid/doge.png", "width": 32, "height": 32]]]]]
            case "/x/web-interface/wbi/index/top/feed/rcmd", "/x/web-interface/index/top/feed/rcmd":
                payload = ["item": (1...40).map { index -> [String: Any] in
                    var video = Self.video
                    video["bvid"] = "BVFixtureHome\(index)"
                    video["id"] = index
                    video["goto"] = "av"
                    return video
                }]
            case "/x/web-interface/archive/related":
                payload = (1...20).map { index -> [String: Any] in
                    var video = Self.video
                    video["bvid"] = "BVFixtureRelated\(index)"
                    video["title"] = "相关视频 \(index)"
                    return video
                }
            case let path where path.contains("playurl"):
                let quality = Int(query.first { $0.name == "qn" }?.value ?? "80") ?? 80
                payload = [
                    "quality": quality, "accept_quality": [80, 64],
                    "accept_description": ["1080P 高清", "720P 高清"],
                    "durl": [["url": "https://ui-test.invalid/video.mp4", "length": 120000]],
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
                payload = ["replies": (1...25).map { index in
                    ["rpid": index, "content": ["message": "详情评论 \(index)"],
                     "member": ["mid": "1001", "uname": "评论用户"]] as [String: Any]
                }, "cursor": ["is_end": true]]
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

    private static var video: [String: Any] {
        ["aid": 100, "bvid": "BV1xx411c7mD", "cid": 1001,
         "title": "固定视频详情回归", "desc": "视频详情测试正文", "duration": 120,
         "owner": ["mid": 1001, "name": "测试 UP"],
         "dimension": ["width": 1920, "height": 1080, "rotate": 0],
         "pages": [["cid": 1001, "page": 1, "part": "测试分 P", "duration": 120]],
         "stat": ["view": 1000, "like": 20, "reply": 25]]
    }
}
#endif
