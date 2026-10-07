import XCTest
@testable import bili

final class VideoDetailCommentDeepLinkResolutionTests: XCTestCase {
    func testReplyPageUsesServerPaginationRatherThanVisibleReplyCount() throws {
        let page = try JSONDecoder.bili.decode(CommentPage.self, from: Data(#"{"page":{"num":1,"size":20,"count":21},"replies":[{"rpid":201}]}"#.utf8))
        XCTAssertTrue(page.hasMoreReplyPages(requestedPage: 1))
        XCTAssertFalse(page.hasMoreReplyPages(requestedPage: 2))
    }

    func testEmptyReplyPageIsTerminalEvenWithStaleServerCount() throws {
        let page = try JSONDecoder.bili.decode(CommentPage.self, from: Data(#"{"page":{"num":1,"size":20,"count":99},"replies":[]}"#.utf8))
        XCTAssertFalse(page.hasMoreReplyPages(requestedPage: 1))
    }

    func testLegacyReplyPageWithoutMetadataStopsOnShortPage() throws {
        let reply = try comment(id: 201)
        let short = CommentPage(replies: [reply], topReplies: nil, cursor: nil)
        XCTAssertFalse(short.hasMoreReplyPages(requestedPage: 1))
        let full = CommentPage(replies: Array(repeating: reply, count: 20), topReplies: nil, cursor: nil)
        XCTAssertTrue(full.hasMoreReplyPages(requestedPage: 1))
    }

    func testIncompletePageMetadataDoesNotBreakOtherCommentEndpoints() throws {
        let page = try JSONDecoder.bili.decode(CommentPage.self, from: Data(#"{"page":{"count":3},"replies":[{"rpid":201}]}"#.utf8))
        XCTAssertFalse(page.hasMoreReplyPages(requestedPage: 1))
    }

    func testTargetLookupSkipsExtraPagesWhenTheFirstPageAlreadyContainsTheReply() {
        XCTAssertEqual(
            VideoDetailCommentDeepLinkResolution.additionalPageNumbers(
                replyCount: 120,
                knownReplyIDs: [202],
                targetReplyID: 202
            ),
            []
        )
    }

    func testTargetLookupUsesBoundedFollowUpPages() {
        XCTAssertEqual(
            VideoDetailCommentDeepLinkResolution.additionalPageNumbers(
                replyCount: 60,
                knownReplyIDs: [101],
                targetReplyID: 202
            ),
            [2, 3]
        )
        XCTAssertEqual(
            VideoDetailCommentDeepLinkResolution.additionalPageNumbers(
                replyCount: 500,
                knownReplyIDs: [101],
                targetReplyID: 202
            ),
            Array(2...VideoDetailCommentDeepLinkResolution.maximumTargetSearchPages)
        )
    }

    func testFocusedReplyRequiresTheRequestedSecondaryReply() throws {
        let replies = [try comment(id: 202), try comment(id: 303)]

        XCTAssertEqual(
            VideoDetailCommentDeepLinkResolution.focusedReplyID(
                requestedReplyID: 202,
                rootID: 101,
                replies: replies
            ),
            202
        )
        XCTAssertNil(
            VideoDetailCommentDeepLinkResolution.focusedReplyID(
                requestedReplyID: 404,
                rootID: 101,
                replies: replies
            )
        )
        XCTAssertNil(
            VideoDetailCommentDeepLinkResolution.focusedReplyID(
                requestedReplyID: 101,
                rootID: 101,
                replies: replies
            )
        )
    }

    func testReplyAvailabilityKeepsTheThreadUntilAnEmptyPageIsReached() {
        XCTAssertTrue(
            VideoDetailCommentDeepLinkResolution.hasMoreReplies(
                replyCount: 42,
                loadedReplyCount: 20,
                reachedEmptyPage: false
            )
        )
        XCTAssertFalse(
            VideoDetailCommentDeepLinkResolution.hasMoreReplies(
                replyCount: 42,
                loadedReplyCount: 20,
                reachedEmptyPage: true
            )
        )
        XCTAssertFalse(
            VideoDetailCommentDeepLinkResolution.hasMoreReplies(
                replyCount: 20,
                loadedReplyCount: 20,
                reachedEmptyPage: false
            )
        )
    }

    private func comment(id: Int) throws -> Comment {
        try JSONDecoder().decode(
            Comment.self,
            from: Data(
                """
                {
                  "rpid": \(id),
                  "root": 101,
                  "member": { "uname": "回复者" },
                  "content": { "message": "回复内容" }
                }
                """.utf8
            )
        )
    }
}
