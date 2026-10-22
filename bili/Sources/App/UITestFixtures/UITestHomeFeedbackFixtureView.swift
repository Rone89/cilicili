#if DEBUG
import SwiftUI

/// Uses the production card, menu, view model and API with deterministic transport.
struct UITestHomeFeedbackFixtureView: View {
    @StateObject private var library: LibraryStore
    @StateObject private var model: HomeViewModel
    @State private var path = [String]()
    @State private var viewport = HomeFeedViewportState()
    @StateObject private var scrollActions = HomeFeedScrollActions()
    @State private var noticeExpirationRequested = false
    private let controlsNoticeExpiration = ProcessInfo.processInfo.arguments.contains(
        "--feedback-controlled-notice-expiration"
    )
    private let nativeRefresh = HomeNativeRefreshActionStore()

    init() {
        let suite = "UITestHomeFeedback.\(UUID().uuidString)"
        let library = LibraryStore(userDefaults: UserDefaults(suiteName: suite)!)
        let keychain = KeychainStore.inMemory(service: suite)
        if !ProcessInfo.processInfo.arguments.contains("--feedback-anonymous") {
            try! keychain.save("fixture-access-key", for: "ACCESS_KEY")
            try! keychain.save("SESSDATA=fixture; DedeUserID=1001", for: "LOGIN_COOKIE_HEADER")
            try! keychain.save("fixture", for: "SESSDATA")
        }
        let session = SessionStore(keychain: keychain)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HomeFeedbackFixtureURLProtocol.self]
        let api = BiliAPIClient(session: URLSession(configuration: configuration), sessionStore: session, libraryStore: library, homeRecommendDiagnosticsStore: .shared)
        let model = HomeViewModel(api: api, libraryStore: library, sessionStore: session)
        model.updateFeed((1...16).map(Self.video))
        model.state = .loaded
        _library = StateObject(wrappedValue: library)
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack {
                GeometryReader { geometry in
                    HomeFeedScrollView(viewModel: model, viewportState: $viewport, scrollActions: scrollActions, nativeRefreshActionStore: nativeRefresh, layout: .borderedSingleColumn) {
                        LazyVStack(spacing: 12) {
                            ForEach(model.videoCells) { cell in
                                HomeFeedVideoCardButton(
                                    metrics: HomeFeedLayoutMetrics(mode: .borderedSingleColumn, containerWidth: geometry.size.width),
                                    video: cell.video, display: cell.display, actions: actions
                                )
                                .accessibilityIdentifier("fixture.feedback.card.\(cell.video.id)")
                            }
                        }.padding()
                    }.accessibilityIdentifier("fixture.feedback.scroll")
                }
            }
            .overlay(alignment: .top) {
                if let notice = model.recommendationFeedbackNotice {
                    HomeRecommendationFeedbackNoticeView(notice: notice)
                        .accessibilityIdentifier("fixture.feedback.message")
                        .allowsHitTesting(false)
                }
            }
            .task(id: model.recommendationFeedbackNotice) {
                guard !controlsNoticeExpiration else { return }
                guard model.recommendationFeedbackNotice != nil else { return }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                model.recommendationFeedbackNotice = nil
            }
            .overlay(alignment: .bottomTrailing) {
                if controlsNoticeExpiration, model.recommendationFeedbackNotice != nil {
                    Button("开始等待反馈提示消失") { noticeExpirationRequested = true }
                        .accessibilityIdentifier("fixture.feedback.expireNotice")
                }
            }
            .task(id: noticeExpirationRequested) {
                guard controlsNoticeExpiration, noticeExpirationRequested else { return }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                model.recommendationFeedbackNotice = nil
                noticeExpirationRequested = false
            }
            .navigationDestination(for: String.self) { id in
                Text("视频详情 \(id)").accessibilityIdentifier("fixture.feedback.detail")
            }
        }
        .environmentObject(library)
    }

    private var actions: HomeFeedContentActions {
        HomeFeedContentActions(
            onVideoSelect: nil, onVideoTap: { path.append($0.id) }, onVideoPress: { _ in },
            onCardAppear: { _, _ in }, onCardDisappear: { _ in }, onLoadMore: { _ in }, onRefreshFromLastSeenMarker: {},
            recommendationFeedback: HomeRecommendationFeedbackActions(
                canSubmit: model.canSubmitRecommendationFeedback,
                canSynchronizeBlock: model.canSynchronizeRecommendationBlock,
                isBusy: model.isSubmittingRecommendationFeedback,
                submit: model.performRecommendationFeedback, block: model.blockRecommendationUP
            )
        )
    }

    private static func video(_ index: Int) -> VideoItem {
        let sameUP = index == 1 || index == 3
        let owner = VideoOwner(mid: sameUP ? 123 : 456, name: sameUP ? "测试 UP" : "其他 UP", face: nil)
        return VideoItem(bvid: "fixture-\(index)", aid: index, title: "推荐视频 \(index)", pic: nil,
                         desc: nil, duration: 120, pubdate: nil, owner: owner, stat: nil,
                         cid: nil, pages: nil, dimension: nil, recommendationFeedback: metadata)
    }

    private static let metadata = try! JSONDecoder.bili.decode(HomeRecommendationFeedbackMetadata.self, from: Data(
        #"{"goto":"av","targetID":1001,"threePointV2":[{"type":"dislike","reasons":[{"id":7,"name":"不想看此类内容","toast":"将减少此类推荐"}]},{"type":"feedback","reasons":[{"id":8,"name":"看过了"}]}]}"#.utf8
    ))
}

nonisolated private final class HomeFeedbackFixtureURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let fails = ProcessInfo.processInfo.arguments.contains("--feedback-failure")
        let body = Data((fails ? #"{"code":-400,"message":"测试失败"}"# : #"{"code":0,"data":null}"#).utf8)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
