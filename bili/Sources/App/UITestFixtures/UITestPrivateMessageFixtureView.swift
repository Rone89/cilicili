#if DEBUG
import SwiftUI

/// Exercises the production conversation and service against an isolated, in-memory server.
struct UITestPrivateMessageFixtureView: View {
    @StateObject private var session: SessionStore
    @StateObject private var library: LibraryStore
    @StateObject private var model: AccountMessageCenterViewModel
    private let accessibilitySize: Bool
    private let dark: Bool
    @State private var completedMessageRequests = 0

    init() {
        let args = ProcessInfo.processInfo.arguments
        accessibilitySize = args.contains("--private-message-accessibility")
        dark = args.contains("--private-message-dark")
        let name = "PrivateMessageFixture.\(UUID().uuidString)"
        let session = SessionStore(keychain: KeychainStore(service: name))
        try? session.saveLoginCookies(["SESSDATA": "fixture", "bili_jct": "fixture", "DedeUserID": String(PrivateMessageFixtureState.senderID)], credentialKind: .web)
        let library = LibraryStore(userDefaults: UserDefaults(suiteName: name)!)
        library.setNativePrivateMessageConversationExperimentEnabled(args.contains("--private-message-native"))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PrivateMessageFixtureProtocol.self]
        let network = URLSession(configuration: config)
        let api = BiliAPIClient(session: network, sessionStore: session, libraryStore: library,
                                homeRecommendDiagnosticsStore: .shared)
        let service = AccountMessageService(sessionStore: session, api: api, session: network)
        _session = StateObject(wrappedValue: session)
        _library = StateObject(wrappedValue: library)
        _model = StateObject(wrappedValue: AccountMessageCenterViewModel(service: service, sessionStore: session))
    }

    var body: some View {
        NavigationStack {
            List {
                Toggle("原生私信会话界面", isOn: Binding(
                    get: { library.nativePrivateMessageConversationExperimentEnabled },
                    set: { library.setNativePrivateMessageConversationExperimentEnabled($0) }
                ))
                .accessibilityIdentifier("privateMessage.fixture.toggle")
                NavigationLink("打开私信") {
                    AccountPrivateMessageConversationView(
                        session: AccountPrivateMessageSession(talkerID: 1002,
                            actor: AccountMessageActor(mid: 1002, name: "测试联系人", avatarURLString: nil),
                            preview: "你好", timestamp: nil, unreadCount: 0, lastMessageSequence: nil,
                            isPinned: false, isMuted: false),
                        viewModel: model, onMarkedRead: {},
                        onConversationChanged: {
                            completedMessageRequests = PrivateMessageFixtureProtocol.messageRequestCount
                        }
                    )
                }
                Text("消息请求：\(completedMessageRequests)")
                    .accessibilityIdentifier("privateMessage.fixture.requests")
                    .accessibilityValue(String(completedMessageRequests))
            }
            .navigationTitle("私信测试")
        }
        .environmentObject(session)
        .environmentObject(library)
        .dynamicTypeSize(accessibilitySize ? .accessibility3 : .large)
        .preferredColorScheme(dark ? .dark : .light)
    }
}

nonisolated private final class PrivateMessageFixtureState: @unchecked Sendable {
    static let senderID = Int.random(in: 900_000_000 ... 999_999_999)
    private let lock = NSLock()
    private var sent = [String]()
    private var messageRequests = 0
    private var shouldFail = ProcessInfo.processInfo.arguments.contains("--private-message-fail-once")

    var messageRequestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return messageRequests
    }

    func response(_ request: URLRequest) -> Data {
        lock.lock(); defer { lock.unlock() }
        var data: [String: Any] = [:]
        switch request.url!.path {
        case "/x/web-interface/nav":
            data = ["wbi_img": ["img_url": "https://fixture.test/abcdef.png", "sub_url": "https://fixture.test/ghijkl.png"]]
        case "/svr_sync/v1/svr_sync/fetch_session_msgs":
            messageRequests += 1
            let refreshMarker = ProcessInfo.processInfo.arguments.contains("--private-message-refresh-marker") && messageRequests > 1
                ? ["消息刷新已完成"] : []
            let history = ProcessInfo.processInfo.arguments.contains("--private-message-long-history")
                ? (1...10).map { "历史消息 \($0)：用于验证滚动和下拉刷新。" } : []
            let texts = ["你好，这是第一条消息。", "同一组消息，中英文 Hello 😀", "收到，谢谢！", "这是一段较长的私信正文，用于检查气泡宽度和大字体布局。支持原有图片、链接、表情和失败重试功能。"] + history + sent + refreshMarker
            data = ["has_more": 0, "messages": texts.enumerated().map { index, text in
                ["sender_uid": index == 2 || index >= 4 ? Self.senderID : 1002, "receiver_id": Self.senderID,
                 "msg_type": 1, "msg_seqno": index + 1, "msg_key": index + 1,
                 "timestamp": 1_760_000_000 + (index < 3 ? index * 20 : 600 + index * 20),
                 "content": String(decoding: try! JSONSerialization.data(withJSONObject: ["content": text]), as: UTF8.self)] as [String: Any]
            }]
        case "/web_im/v1/web_im/send_msg":
            if shouldFail {
                shouldFail = false
                return try! JSONSerialization.data(withJSONObject: ["code": -1, "message": "测试发送失败，请重试"])
            }
            let form = String(decoding: bodyData(request), as: UTF8.self)
            let fields = URLComponents(string: "https://fixture.test/?" + form)?.queryItems ?? []
            if let content = fields.first(where: { $0.name == "msg[content]" })?.value,
               let json = try? JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: String],
               let text = json["content"] { sent.append(text) }
        default: break
        }
        return try! JSONSerialization.data(withJSONObject: ["code": 0, "data": data])
    }

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
}

nonisolated private final class PrivateMessageFixtureProtocol: URLProtocol {
    private static let state = PrivateMessageFixtureState()
    static var messageRequestCount: Int { state.messageRequestCount }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.state.response(request))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
