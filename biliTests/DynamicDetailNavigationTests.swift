import Foundation
import XCTest

@testable import bili

final class DynamicDetailNavigationTests: XCTestCase {
    override func tearDown() {
        DynamicDetailURLProtocol.reset()
        super.tearDown()
    }

    @MainActor
    func testSupportsDetailNavigationForOriginalContentKinds() throws {
        let textOriginal = try decodeOriginal(
            #"{"id_str":"text","type":"DYNAMIC_TYPE_WORD","modules":{"module_dynamic":{"desc":{"text":"plain text"}}}}"#
        )
        XCTAssertTrue(DynamicFeedCardDisplayModel.supportsDetailNavigation(original: textOriginal))

        let imageOriginal = try decodeOriginal(
            #"{"id_str":"image","type":"DYNAMIC_TYPE_DRAW","modules":{"module_dynamic":{"major":{"draw":{"items":[{"src":"https://i.example.com/image.jpg","width":100,"height":100}]}}}}}"#
        )
        XCTAssertTrue(DynamicFeedCardDisplayModel.supportsDetailNavigation(original: imageOriginal))

        let videoOriginal = try decodeOriginal(
            #"{"id_str":"video","type":"DYNAMIC_TYPE_AV","modules":{"module_dynamic":{"major":{"archive":{"bvid":"BV1xx411c7mD","title":"video"}}}}}"#
        )
        XCTAssertFalse(DynamicFeedCardDisplayModel.supportsDetailNavigation(original: videoOriginal))

        let liveOriginal = try decodeOriginal(
            #"{"id_str":"live","type":"DYNAMIC_TYPE_LIVE_RCMD","modules":{"module_dynamic":{"major":{"live":{"room_id":123,"title":"live"}}}}}"#
        )
        XCTAssertFalse(DynamicFeedCardDisplayModel.supportsDetailNavigation(original: liveOriginal))
    }

    @MainActor
    func testFetchDynamicDetailUsesDetailRouteQueryAndDecodesItem() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let recorder = DynamicDetailRequestRecorder()
        let requestExpectation = expectation(description: "dynamic detail request captured")
        DynamicDetailURLProtocol.install { request in
            recorder.record(request)
            requestExpectation.fulfill()
            return dynamicDetailResponse(
                for: request,
                body: """
                {"code":0,"data":{"item":{"id_str":"dynamic-detail-123","type":"DYNAMIC_TYPE_WORD","modules":{"module_dynamic":{"desc":{"text":"decoded detail"}},"module_stat":{"like":{"count":42,"status":true}}}}}}
                """
            )
        }

        let api = try makeAPI()
        let item = try await api.fetchDynamicDetail(id: "dynamic-detail-123")

        await fulfillment(of: [requestExpectation], timeout: 2)

        XCTAssertEqual(item.idStr, "dynamic-detail-123")
        XCTAssertEqual(item.displayText, "decoded detail")
        XCTAssertTrue(item.isLiked)
        XCTAssertEqual(item.likeCount, 42)

        let request = try XCTUnwrap(recorder.request)
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(url.host, "api.bilibili.com")
        XCTAssertEqual(url.path, "/x/polymer/web-dynamic/v1/detail")
        XCTAssertEqual(query["id"], "dynamic-detail-123")
        XCTAssertEqual(query["timezone_offset"], "-480")
        XCTAssertEqual(query["gaia_source"], "Athena")
        XCTAssertEqual(query["web_location"], "333.1330")
        XCTAssertEqual(
            query["x-bili-device-req-json"],
            #"{"platform":"web","device":"pc","spmid":"333.1330"}"#
        )
        XCTAssertEqual(
            query["features"],
            "itemOpusStyle,listOnlyfans,opusBigCover,onlyfansVote,decorationCard,onlyfansAssetsV2,forwardListHidden,ugcDelete"
        )
    }

    @MainActor
    func testCommentReloadKeepsLoadedCommentsWhenRefreshReturnsEmptyPage() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let responses = DynamicCommentsResponseSequence([
            .success(#"{"code":0,"data":{"replies":[{"rpid":101}],"top_replies":[],"cursor":{"is_end":true}}}"#),
            .success(#"{"code":0,"data":{"replies":[],"top_replies":[],"cursor":{"is_end":true}}}"#),
        ])
        DynamicCommentsURLProtocol.install { request in
            try responses.nextResponse(for: request)
        }
        defer { DynamicCommentsURLProtocol.reset() }

        let viewModel = DynamicCommentsViewModel(item: try makeCommentableItem(), api: try makeCommentsAPI())
        await viewModel.loadInitial()
        XCTAssertEqual(viewModel.comments.map(\.id), [101])

        await BiliAPIResponseMemoryCache.shared.clear()
        await viewModel.reload()

        XCTAssertEqual(viewModel.comments.map(\.id), [101])
        XCTAssertEqual(viewModel.state, .loaded)
    }

    @MainActor
    func testCommentReloadKeepsLoadedCommentsWhenRefreshFails() async throws {
        await BiliAPIResponseMemoryCache.shared.clear()

        let responses = DynamicCommentsResponseSequence([
            .success(#"{"code":0,"data":{"replies":[{"rpid":202}],"top_replies":[],"cursor":{"is_end":true}}}"#),
            .failure(URLError(.notConnectedToInternet)),
        ])
        DynamicCommentsURLProtocol.install { request in
            try responses.nextResponse(for: request)
        }
        defer { DynamicCommentsURLProtocol.reset() }

        let viewModel = DynamicCommentsViewModel(item: try makeCommentableItem(), api: try makeCommentsAPI())
        await viewModel.loadInitial()
        XCTAssertEqual(viewModel.comments.map(\.id), [202])

        await BiliAPIResponseMemoryCache.shared.clear()
        await viewModel.reload()

        XCTAssertEqual(viewModel.comments.map(\.id), [202])
        XCTAssertEqual(viewModel.state, .loaded)
    }

    @MainActor
    func testRegisterSubmittedCommentUpdatesDisplayedReplyCount() throws {
        let viewModel = DynamicCommentsViewModel(item: try makeCommentableItem(), api: try makeCommentsAPI())

        XCTAssertNil(viewModel.displayedReplyCount)
        viewModel.registerSubmittedComment()
        XCTAssertEqual(viewModel.displayedReplyCount, 1)
        viewModel.registerSubmittedComment()
        XCTAssertEqual(viewModel.displayedReplyCount, 2)
    }

    @MainActor
    func testReplyPaginationStopsAtServerTotalDespiteStaleParentCount() async throws {
        let responses = DynamicCommentsResponseSequence([
            .success(#"{"code":0,"data":{"page":{"num":1,"size":20,"count":3},"replies":[{"rpid":201},{"rpid":202},{"rpid":203}]}}"#),
        ])
        DynamicCommentsURLProtocol.install { try responses.nextResponse(for: $0) }
        defer { DynamicCommentsURLProtocol.reset() }
        let root = try JSONDecoder.bili.decode(Comment.self, from: Data(#"{"rpid":101,"rcount":99}"#.utf8))
        let store = DynamicCommentReplyStore(item: try makeCommentableItem(), api: try makeCommentsAPI(), blocksGoodsComments: false)
        await store.loadReplies(for: root)
        XCTAssertEqual(store.replies(for: root).map(\.id), [201, 202, 203])
        XCTAssertFalse(store.hasMoreReplies(for: root))
        await store.loadMoreReplies(for: root)
        XCTAssertEqual(store.replyState(for: root), .loaded)
    }

    @MainActor
    func testFailedReplyPageCanRetryWithoutLosingExistingReplies() async throws {
        let responses = DynamicCommentsResponseSequence([
            .success(#"{"code":0,"data":{"page":{"num":1,"size":1,"count":2},"replies":[{"rpid":201}]}}"#),
            .success(#"{"code":-400,"message":"分页请求失败"}"#),
            .success(#"{"code":0,"data":{"page":{"num":2,"size":1,"count":2},"replies":[{"rpid":202}]}}"#),
        ])
        DynamicCommentsURLProtocol.install { try responses.nextResponse(for: $0) }
        defer { DynamicCommentsURLProtocol.reset() }
        let root = try JSONDecoder.bili.decode(Comment.self, from: Data(#"{"rpid":101,"rcount":99}"#.utf8))
        let store = DynamicCommentReplyStore(item: try makeCommentableItem(), api: try makeCommentsAPI(), blocksGoodsComments: false)
        await store.loadReplies(for: root)
        XCTAssertTrue(store.hasMoreReplies(for: root))
        await store.loadMoreReplies(for: root)
        guard case .failed = store.replyState(for: root) else { return XCTFail("Expected a retryable failure") }
        XCTAssertEqual(store.replies(for: root).map(\.id), [201])
        XCTAssertTrue(store.hasMoreReplies(for: root))
        await store.loadMoreReplies(for: root)
        XCTAssertEqual(Set(store.replies(for: root).map(\.id)), [201, 202])
        XCTAssertFalse(store.hasMoreReplies(for: root))
        XCTAssertEqual(store.replyState(for: root), .loaded)
        XCTAssertEqual(responses.requestedPages, [1, 2, 2])
    }

    @MainActor
    func testDynamicNextReplyPageAppendsBelowLoadedRepliesAndDeduplicates() async throws {
        let responses = DynamicCommentsResponseSequence([
            .success(#"{"code":0,"data":{"page":{"num":1,"size":2,"count":3},"replies":[{"rpid":201},{"rpid":202}]}}"#),
            .success(#"{"code":0,"data":{"page":{"num":2,"size":2,"count":3},"replies":[{"rpid":202},{"rpid":203}]}}"#),
        ])
        DynamicCommentsURLProtocol.install { try responses.nextResponse(for: $0) }
        defer { DynamicCommentsURLProtocol.reset() }
        let root = try JSONDecoder.bili.decode(Comment.self, from: Data(#"{"rpid":101,"rcount":99}"#.utf8))
        let store = DynamicCommentReplyStore(item: try makeCommentableItem(), api: try makeCommentsAPI(), blocksGoodsComments: false)
        await store.loadReplies(for: root)
        XCTAssertEqual(store.repliesSnapshot(for: root).replyItems.map(\.id), [201, 202])
        await store.loadMoreReplies(for: root)
        XCTAssertEqual(store.repliesSnapshot(for: root).replyItems.map(\.id), [201, 202, 203])
        XCTAssertFalse(store.hasMoreReplies(for: root))
        XCTAssertEqual(responses.requestedPages, [1, 2])
    }

    @MainActor
    func testVideoReplyPaginationRetriesSamePageAndStopsAtServerTotal() async throws {
        let responses = DynamicCommentsResponseSequence([
            .success(#"{"code":0,"data":{"page":{"num":1,"size":1,"count":2},"replies":[{"rpid":201}]}}"#),
            .success(#"{"code":-400,"message":"分页请求失败"}"#),
            .success(#"{"code":0,"data":{"page":{"num":2,"size":1,"count":2},"replies":[{"rpid":202}]}}"#),
        ])
        DynamicCommentsURLProtocol.install { try responses.nextResponse(for: $0) }
        defer { DynamicCommentsURLProtocol.reset() }
        let root = try JSONDecoder.bili.decode(Comment.self, from: Data(#"{"rpid":101,"rcount":99}"#.utf8))
        let service = "VideoReplyPaginationTests.\(UUID().uuidString)"
        let viewModel = VideoDetailViewModel(
            seedVideo: VideoItem(bvid: "BV-replies", aid: 456, title: "Replies", pic: nil, desc: nil, duration: 60, pubdate: nil, owner: nil, stat: nil, cid: 11, pages: nil, dimension: nil),
            api: try makeCommentsAPI(),
            libraryStore: LibraryStore(userDefaults: UserDefaults(suiteName: service)!),
            sessionStore: SessionStore(keychain: KeychainStore.inMemory(service: service)),
            sponsorBlockService: SponsorBlockService(session: URLSession(configuration: .ephemeral))
        )
        await viewModel.loadReplies(for: root)
        XCTAssertTrue(viewModel.hasMoreReplies(for: root))
        await viewModel.loadMoreReplies(for: root)
        guard case .failed = viewModel.replyThreadStates[root.id] else { return XCTFail("Expected retryable failure") }
        XCTAssertEqual(viewModel.replies(for: root).map(\.id), [201])
        await viewModel.loadMoreReplies(for: root)
        XCTAssertEqual(viewModel.replies(for: root).map(\.id), [201, 202])
        XCTAssertFalse(viewModel.hasMoreReplies(for: root))
        XCTAssertEqual(responses.requestedPages, [1, 2, 2])
    }

    @MainActor
    func testRootPaginationUsesOpaqueOffsetAndRetriesFailedPage() async throws {
        let responses = DynamicCommentsResponseSequence([
            .success(#"{"code":0,"data":{"replies":[{"rpid":101}],"cursor":{"next":2,"pagination_reply":{"next_offset":"CAEiAggC"},"is_end":false}}}"#),
            .success(#"{"code":-400,"message":"暂时失败"}"#),
            .success(#"{"code":0,"data":{"replies":[{"rpid":102},{"rpid":102}],"cursor":{"is_end":true}}}"#),
        ])
        DynamicCommentsURLProtocol.install { try responses.nextResponse(for: $0) }
        defer { DynamicCommentsURLProtocol.reset() }
        let api = try makeCommentsAPI()
        let model = DynamicCommentsViewModel(item: try makeCommentableItem(), api: api)
        await model.loadInitial()
        await model.loadMore()
        XCTAssertEqual(model.comments.map(\.id), [101])
        XCTAssertTrue(model.hasMoreComments)
        guard case .failed = model.loadMoreState else { return XCTFail("Expected retry footer") }
        await model.loadMore()
        XCTAssertEqual(model.comments.map(\.id), [101, 102])
        XCTAssertFalse(model.hasMoreComments)
        XCTAssertEqual(responses.requestedOffsets, ["", "CAEiAggC", "CAEiAggC"])
    }

    @MainActor
    func testDuplicateAndEmptyPagesPauseWithoutEndingAndContinueFromLatestCursor() async throws {
        let responses = DynamicCommentsResponseSequence([
            .success(#"{"code":0,"data":{"replies":[{"rpid":101}],"cursor":{"next_offset":"a","is_end":false}}}"#),
            .success(#"{"code":0,"data":{"replies":[{"rpid":101}],"cursor":{"next_offset":"b","is_end":false}}}"#),
            .success(#"{"code":0,"data":{"replies":[],"cursor":{"next_offset":"c","is_end":false}}}"#),
            .success(#"{"code":0,"data":{"replies":[],"cursor":{"next_offset":"d","is_end":false}}}"#),
            .success(#"{"code":0,"data":{"replies":[{"rpid":102}],"cursor":{"is_end":true}}}"#),
        ])
        DynamicCommentsURLProtocol.install { try responses.nextResponse(for: $0) }
        defer { DynamicCommentsURLProtocol.reset() }
        let model = DynamicCommentsViewModel(item: try makeCommentableItem(), api: try makeCommentsAPI())
        await model.loadInitial()
        await model.loadMore()
        XCTAssertTrue(model.hasMoreComments)
        guard case .failed = model.loadMoreState else { return XCTFail("Automatic skips must stop with a manual continuation") }
        XCTAssertEqual(responses.requestedOffsets, ["", "a", "b", "c"])
        await model.loadMore()
        XCTAssertEqual(model.comments.map(\.id), [101, 102])
        XCTAssertEqual(responses.requestedOffsets.last, "d")
    }

    @MainActor
    func testStagnantCursorDoesNotLoopOrEndComments() async throws {
        let responses = DynamicCommentsResponseSequence([
            .success(#"{"code":0,"data":{"replies":[{"rpid":101}],"cursor":{"next_offset":"a","is_end":false}}}"#),
            .success(#"{"code":0,"data":{"replies":[{"rpid":101}],"cursor":{"next_offset":"a","is_end":false}}}"#),
        ])
        DynamicCommentsURLProtocol.install { try responses.nextResponse(for: $0) }
        defer { DynamicCommentsURLProtocol.reset() }
        let model = DynamicCommentsViewModel(item: try makeCommentableItem(), api: try makeCommentsAPI())
        await model.loadInitial()
        await model.loadMore()
        XCTAssertTrue(model.hasMoreComments)
        guard case .failed = model.loadMoreState else { return XCTFail("Stagnant cursor must pause") }
        XCTAssertEqual(responses.requestedOffsets, ["", "a"])
    }

    @MainActor
    func testFilterOffReloadsEvenWhenEveryCommentWasFiltered() async throws {
        let body = #"{"code":0,"data":{"replies":[{"rpid":101,"content":{"message":"商品","has_goods":true}}],"cursor":{"is_end":true}}}"#
        let responses = DynamicCommentsResponseSequence([.success(body), .success(body)])
        DynamicCommentsURLProtocol.install { try responses.nextResponse(for: $0) }
        defer { DynamicCommentsURLProtocol.reset() }
        let model = DynamicCommentsViewModel(item: try makeCommentableItem(), api: try makeCommentsAPI())
        await model.loadInitial()
        XCTAssertTrue(model.comments.isEmpty)
        model.setBlocksGoodsComments(false)
        for _ in 0..<200 where model.comments.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.comments.map(\.id), [101])
        XCTAssertEqual(responses.requestedOffsets, ["", ""])
    }

    @MainActor
    func testReplyFilterOffInvalidatesCachedStateAndReloadsFirstPage() async throws {
        let body = #"{"code":0,"data":{"replies":[{"rpid":201,"content":{"message":"商品","has_goods":true}}],"page":{"num":1,"size":20,"count":1}}}"#
        let responses = DynamicCommentsResponseSequence([.success(body), .success(body)])
        DynamicCommentsURLProtocol.install { try responses.nextResponse(for: $0) }
        defer { DynamicCommentsURLProtocol.reset() }
        let root = try JSONDecoder.bili.decode(Comment.self, from: Data(#"{"rpid":101,"rcount":1}"#.utf8))
        let store = DynamicCommentReplyStore(item: try makeCommentableItem(), api: try makeCommentsAPI(), blocksGoodsComments: true)
        await store.loadReplies(for: root)
        XCTAssertTrue(store.replies(for: root).isEmpty)
        let revision = store.contentRevision
        store.setBlocksGoodsComments(false)
        XCTAssertGreaterThan(store.contentRevision, revision)
        XCTAssertEqual(store.replyState(for: root), .idle)
        await store.loadReplies(for: root)
        XCTAssertEqual(store.replies(for: root).map(\.id), [201])
        XCTAssertEqual(responses.requestedPages, [1, 1])
    }

    @MainActor
    func testVideoPaginationRetryCancellationAndFilterPublication() async throws {
        let api = try makeCommentsAPI()
        let model = makeVideoCommentsModel(api: api)
        defer { model.stopPlaybackForNavigation() }
        let page = try JSONDecoder.bili.decode(CommentPage.self, from: Data(#"{"replies":[{"rpid":101}],"cursor":{"next":2,"next_offset":"opaque","is_end":false}}"#.utf8))
        model.applyLoadedCommentPage(page, isInitialPage: true)
        XCTAssertEqual(model.commentCursor, "opaque")
        model.failCommentPageLoad(URLError(.notConnectedToInternet), presentsErrors: false)
        XCTAssertFalse(model.commentsEnd)
        guard case .failed = model.commentLoadMoreState else { return XCTFail("Video pagination must remain retryable") }
        model.resetCommentStateAfterCancellation(isInitialPage: false, wasLoadingMore: true)
        XCTAssertFalse(model.commentsEnd)
        model.finishCommentPageLoadWithoutSkip(previousCount: 1, previousCursor: "opaque")
        XCTAssertFalse(model.commentsEnd)

        let goodsBody = #"{"code":0,"data":{"replies":[{"rpid":201,"content":{"message":"商品","has_goods":true}}],"cursor":{"is_end":true}}}"#
        let responses = DynamicCommentsResponseSequence([.success(goodsBody), .success(goodsBody)])
        DynamicCommentsURLProtocol.install { try responses.nextResponse(for: $0) }
        defer { DynamicCommentsURLProtocol.reset() }
        await model.loadInitialComments()
        XCTAssertTrue(model.comments.isEmpty)
        api.libraryStore.setBlocksGoodsComments(false)
        for task in Array(model.backgroundTasks.values) { await task.value }
        XCTAssertEqual(model.comments.map(\.id), [201], "Use the emitted filter value, not @Published's old stored value")
        XCTAssertGreaterThan(model.commentThreadRenderStore.contentRevision, 0)
    }

    @MainActor
    func testRetiredExperimentPreferenceCannotDisableCommentLoadingRecovery() throws {
        let suite = "CommentRecoveryGraduationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "cc.bili.content.commentLoadingRecoveryExperimentEnabled.v1")
        let model = makeVideoCommentsModel(api: try makeCommentsAPI(defaults: defaults))
        defer { model.stopPlaybackForNavigation() }
        let page = try JSONDecoder.bili.decode(CommentPage.self, from: Data(#"{"replies":[{"rpid":101}],"cursor":{"next":2,"next_offset":"opaque","is_end":false}}"#.utf8))
        model.applyLoadedCommentPage(page, isInitialPage: true)
        XCTAssertEqual(model.commentCursor, "opaque")
        model.failCommentPageLoad(URLError(.notConnectedToInternet), presentsErrors: false)
        XCTAssertFalse(model.commentsEnd)
        guard case .failed = model.commentLoadMoreState else { return XCTFail("Default pagination must remain retryable") }
    }


    @MainActor
    func testDynamicDialogRefreshFailureRetainsRepliesAndRetryReplacesThem() async throws {
        let responses = DynamicCommentsResponseSequence([
            .success(#"{"code":0,"data":{"replies":[{"rpid":201},{"rpid":202}]}}"#),
            .success(#"{"code":-400,"message":"刷新失败"}"#),
            .success(#"{"code":0,"data":{"replies":[{"rpid":203}]}}"#),
        ])
        DynamicCommentsURLProtocol.install { try responses.nextResponse(for: $0) }
        defer { DynamicCommentsURLProtocol.reset() }
        let root = try JSONDecoder.bili.decode(Comment.self, from: Data(#"{"rpid":101}"#.utf8))
        let reply = try JSONDecoder.bili.decode(Comment.self, from: Data(#"{"rpid":202,"dialog":201}"#.utf8))
        let store = DynamicCommentReplyStore(item: try makeCommentableItem(), api: try makeCommentsAPI(), blocksGoodsComments: false)

        await store.loadDialog(for: root, reply: reply)
        XCTAssertEqual(store.dialogSnapshot(for: root, reply: reply).items.map(\.id), [201, 202])
        await store.reloadDialog(for: root, reply: reply)
        XCTAssertEqual(store.dialogSnapshot(for: root, reply: reply).items.map(\.id), [201, 202])
        guard case .failed = store.dialogState(for: root, reply: reply) else { return XCTFail("Expected retryable failure") }
        await store.reloadDialog(for: root, reply: reply)
        XCTAssertEqual(store.dialogSnapshot(for: root, reply: reply).items.map(\.id), [203, 202])
        XCTAssertEqual(store.dialogState(for: root, reply: reply), .loaded)
    }

    @MainActor
    func testVideoDialogRefreshFailureRetainsRepliesAndRetryReplacesThem() async throws {
        let responses = DynamicCommentsResponseSequence([
            .success(#"{"code":0,"data":{"replies":[{"rpid":201},{"rpid":202}]}}"#),
            .success(#"{"code":-400,"message":"刷新失败"}"#),
            .success(#"{"code":0,"data":{"replies":[{"rpid":203}]}}"#),
        ])
        DynamicCommentsURLProtocol.install { try responses.nextResponse(for: $0) }
        defer { DynamicCommentsURLProtocol.reset() }
        let root = try JSONDecoder.bili.decode(Comment.self, from: Data(#"{"rpid":101}"#.utf8))
        let reply = try JSONDecoder.bili.decode(Comment.self, from: Data(#"{"rpid":202,"dialog":201}"#.utf8))
        let model = makeVideoCommentsModel(api: try makeCommentsAPI())
        defer { model.stopPlaybackForNavigation() }
        model.replyThreadStates[root.id] = .loaded

        await model.loadDialog(for: root, reply: reply)
        XCTAssertEqual(model.dialogReplies(for: root, reply: reply).map(\.id), [201, 202])
        await model.reloadDialog(for: root, reply: reply)
        XCTAssertEqual(model.dialogReplies(for: root, reply: reply).map(\.id), [201, 202])
        guard case .failed = model.dialogState(for: root, reply: reply) else { return XCTFail("Expected retryable failure") }
        await model.reloadDialog(for: root, reply: reply)
        XCTAssertEqual(model.dialogReplies(for: root, reply: reply).map(\.id), [203, 202])
        XCTAssertEqual(model.dialogState(for: root, reply: reply), .loaded)
    }


    @MainActor
    func testDynamicReplyRefreshFailurePreservesRepliesAndRetriesFirstPage() async throws {
        let responses = DynamicCommentsResponseSequence([
            .success(#"{"code":0,"data":{"page":{"num":1,"size":1,"count":2},"replies":[{"rpid":201}]}}"#),
            .success(#"{"code":0,"data":{"page":{"num":2,"size":1,"count":2},"replies":[{"rpid":202}]}}"#),
            .success(#"{"code":-400,"message":"刷新失败"}"#),
            .success(#"{"code":0,"data":{"page":{"num":1,"size":1,"count":2},"replies":[{"rpid":203}]}}"#),
            .success(#"{"code":0,"data":{"page":{"num":2,"size":1,"count":2},"replies":[{"rpid":204}]}}"#),
        ])
        DynamicCommentsURLProtocol.install { try responses.nextResponse(for: $0) }
        defer { DynamicCommentsURLProtocol.reset() }
        let root = try JSONDecoder.bili.decode(Comment.self, from: Data(#"{"rpid":101,"rcount":2}"#.utf8))
        let store = DynamicCommentReplyStore(item: try makeCommentableItem(), api: try makeCommentsAPI(), blocksGoodsComments: false)
        await store.loadReplies(for: root)
        await store.loadMoreReplies(for: root)
        await store.reloadReplies(for: root)
        XCTAssertEqual(store.replies(for: root).map(\.id), [201, 202])
        guard case .failed = store.replyState(for: root) else { return XCTFail("Expected retryable failure") }
        await store.loadMoreReplies(for: root)
        XCTAssertEqual(store.replies(for: root).map(\.id), [203])
        await store.loadMoreReplies(for: root)
        XCTAssertEqual(store.replies(for: root).map(\.id), [203, 204])
        XCTAssertEqual(responses.requestedPages, [1, 2, 1, 1, 2])
    }

    @MainActor
    func testVideoReplyRefreshFailurePreservesRepliesAndRetriesFirstPage() async throws {
        let responses = DynamicCommentsResponseSequence([
            .success(#"{"code":0,"data":{"page":{"num":1,"size":1,"count":2},"replies":[{"rpid":201}]}}"#),
            .success(#"{"code":0,"data":{"page":{"num":2,"size":1,"count":2},"replies":[{"rpid":202}]}}"#),
            .success(#"{"code":-400,"message":"刷新失败"}"#),
            .success(#"{"code":0,"data":{"page":{"num":1,"size":1,"count":2},"replies":[{"rpid":203}]}}"#),
            .success(#"{"code":0,"data":{"page":{"num":2,"size":1,"count":2},"replies":[{"rpid":204}]}}"#),
        ])
        DynamicCommentsURLProtocol.install { try responses.nextResponse(for: $0) }
        defer { DynamicCommentsURLProtocol.reset() }
        let root = try JSONDecoder.bili.decode(Comment.self, from: Data(#"{"rpid":101,"rcount":2}"#.utf8))
        let model = makeVideoCommentsModel(api: try makeCommentsAPI())
        defer { model.stopPlaybackForNavigation() }
        await model.loadReplies(for: root)
        await model.loadMoreReplies(for: root)
        await model.reloadReplies(for: root)
        XCTAssertEqual(model.replies(for: root).map(\.id), [201, 202])
        guard case .failed = model.replyState(for: root) else { return XCTFail("Expected retryable failure") }
        await model.loadMoreReplies(for: root)
        XCTAssertEqual(model.replies(for: root).map(\.id), [203])
        await model.loadMoreReplies(for: root)
        XCTAssertEqual(model.replies(for: root).map(\.id), [203, 204])
        XCTAssertEqual(responses.requestedPages, [1, 2, 1, 1, 2])
    }

    @MainActor
    private func makeVideoCommentsModel(api: BiliAPIClient) -> VideoDetailViewModel {
        VideoDetailViewModel(
            seedVideo: VideoItem(bvid: "BV-recovery", aid: 456, title: "Comments", pic: nil, desc: nil, duration: 60, pubdate: nil, owner: nil, stat: nil, cid: 11, pages: nil, dimension: nil),
            api: api, libraryStore: api.libraryStore, sessionStore: api.sessionStore,
            sponsorBlockService: SponsorBlockService(session: URLSession(configuration: .ephemeral))
        )
    }

    private func decodeOriginal(_ json: String) throws -> DynamicOriginalItem {
        try JSONDecoder.bili.decode(DynamicOriginalItem.self, from: Data(json.utf8))
    }

    private func makeCommentableItem() throws -> DynamicFeedItem {
        try JSONDecoder.bili.decode(
            DynamicFeedItem.self,
            from: Data(
                #"{"id_str":"commentable-dynamic","type":"DYNAMIC_TYPE_WORD","basic":{"comment_id_str":"456","comment_type":17},"modules":{"module_dynamic":{"desc":{"text":"commentable"}}}}"#.utf8
            )
        )
    }

    @MainActor
    private func makeAPI() throws -> BiliAPIClient {
        let service = "DynamicDetailNavigationTests.\(UUID().uuidString)"
        let keychain = KeychainStore.inMemory(service: service)
        let sessionStore = SessionStore(keychain: keychain)
        let libraryStore = LibraryStore(userDefaults: UserDefaults(suiteName: service)!)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DynamicDetailURLProtocol.self]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false

        return BiliAPIClient(
            session: URLSession(configuration: configuration),
            sessionStore: sessionStore,
            libraryStore: libraryStore,
            homeRecommendDiagnosticsStore: .shared
        )
    }

    @MainActor
    private func makeCommentsAPI(defaults: UserDefaults? = nil) throws -> BiliAPIClient {
        let service = "DynamicCommentsViewModelTests.\(UUID().uuidString)"
        let keychain = KeychainStore.inMemory(service: service)
        let sessionStore = SessionStore(keychain: keychain)
        let libraryStore = LibraryStore(userDefaults: defaults ?? UserDefaults(suiteName: service)!)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DynamicCommentsURLProtocol.self]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false

        return BiliAPIClient(
            session: URLSession(configuration: configuration),
            sessionStore: sessionStore,
            libraryStore: libraryStore,
            homeRecommendDiagnosticsStore: .shared
        )
    }
}

private func dynamicDetailResponse(
    for request: URLRequest,
    body: String
) -> (HTTPURLResponse, Data) {
    let url = request.url ?? URL(string: "https://api.bilibili.com")!
    let response = HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    )!
    return (response, Data(body.utf8))
}

private final class DynamicDetailRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequest: URLRequest?

    var request: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return storedRequest
    }

    func record(_ request: URLRequest) {
        lock.lock()
        storedRequest = request
        lock.unlock()
    }
}

private final class DynamicDetailURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let state = HandlerState()

    static func install(_ handler: @escaping Handler) {
        state.install(handler)
    }

    static func reset() {
        state.reset()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.bilibili.com"
            && request.url?.path == "/x/polymer/web-dynamic/v1/detail"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let result = try Self.currentHandler()(request)
            client?.urlProtocol(self, didReceive: result.0, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: result.1)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func currentHandler() throws -> Handler {
        try state.currentHandler()
    }

    private final class HandlerState: @unchecked Sendable {
        private let lock = NSLock()
        private var handler: Handler?

        func install(_ handler: @escaping Handler) {
            lock.lock()
            self.handler = handler
            lock.unlock()
        }

        func reset() {
            lock.lock()
            handler = nil
            lock.unlock()
        }

        func currentHandler() throws -> Handler {
            lock.lock()
            let handler = self.handler
            lock.unlock()
            guard let handler else {
                throw URLError(.badServerResponse)
            }
            return handler
        }
    }
}

private final class DynamicCommentsResponseSequence: @unchecked Sendable {
    enum Response {
        case success(String)
        case failure(Error)
    }

    private let lock = NSLock()
    private var responses: [Response]
    private var pages: [Int] = []
    private var offsets: [String] = []

    var requestedOffsets: [String] {
        lock.lock()
        defer { lock.unlock() }
        return offsets
    }

    var requestedPages: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return pages
    }

    init(_ responses: [Response]) {
        self.responses = responses
    }

    func nextResponse(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        lock.lock()
        if let url = request.url,
           let page = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "pn" })?.value.flatMap(Int.init) {
            pages.append(page)
        }
        if let url = request.url,
           let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "pagination_str" })?.value,
           let data = raw.data(using: .utf8),
           let pagination = try? JSONDecoder().decode([String: String].self, from: data) {
            offsets.append(pagination["offset"] ?? "")
        }
        let response = responses.isEmpty ? nil : responses.removeFirst()
        lock.unlock()

        switch response {
        case .success(let body):
            return dynamicDetailResponse(for: request, body: body)
        case .failure(let error):
            throw error
        case nil:
            throw URLError(.badServerResponse)
        }
    }
}

private final class DynamicCommentsURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let state = HandlerState()

    static func install(_ handler: @escaping Handler) {
        state.install(handler)
    }

    static func reset() {
        state.reset()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.bilibili.com"
            && ["/x/v2/reply/main", "/x/v2/reply/reply", "/x/v2/reply/dialog/cursor"].contains(request.url?.path ?? "")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let result = try Self.currentHandler()(request)
            client?.urlProtocol(self, didReceive: result.0, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: result.1)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func currentHandler() throws -> Handler {
        try state.currentHandler()
    }

    private final class HandlerState: @unchecked Sendable {
        private let lock = NSLock()
        private var handler: Handler?

        func install(_ handler: @escaping Handler) {
            lock.lock()
            self.handler = handler
            lock.unlock()
        }

        func reset() {
            lock.lock()
            handler = nil
            lock.unlock()
        }

        func currentHandler() throws -> Handler {
            lock.lock()
            let handler = self.handler
            lock.unlock()
            guard let handler else {
                throw URLError(.badServerResponse)
            }
            return handler
        }
    }
}
