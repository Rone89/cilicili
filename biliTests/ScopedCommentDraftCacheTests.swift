import XCTest
@testable import bili

@MainActor
final class ScopedCommentDraftCacheTests: XCTestCase {
    func testRecoveredDraftKeepsRichTextImagesAndReplyTarget() {
        let cache = ScopedCommentDraftCache()
        let reply = DynamicCommentComposerTarget(rootID: 4, parentID: 5, authorName: "UP")
        let draft = RichCommentDraft(
            elements: [.text("hello"), .emote("[doge]")],
            images: [RichCommentImageDraft(sourceIdentifier: "photo", data: Data([1, 2]))],
            replyTarget: reply
        )
        cache.set(draft, for: key())
        XCTAssertEqual(cache.draft(for: key()), draft)
        cache.set(RichCommentDraft(), for: key())
        XCTAssertNil(cache.draft(for: key()))
    }

    func testAccountContentTypeAndReplyAreSeparateScopes() {
        let cache = ScopedCommentDraftCache()
        cache.set(RichCommentDraft(elements: [.text("A")]), for: key())
        XCTAssertNil(cache.draft(for: key(account: 2)))
        XCTAssertNil(cache.draft(for: key(oid: "other")))
        XCTAssertNil(cache.draft(for: key(type: 17)))
        XCTAssertNil(cache.draft(for: key(root: 1, parent: 2)))
        cache.set(RichCommentDraft(elements: [.text("B")]), for: key(account: 2))
        cache.remove(accountMID: 1)
        XCTAssertNil(cache.draft(for: key()))
        XCTAssertEqual(cache.draft(for: key(account: 2))?.serializedMessage, "B")
    }

    func testExpiryAndCapacityDoNotReviveOldDrafts() {
        var now = Date(timeIntervalSince1970: 1000)
        let cache = ScopedCommentDraftCache(maximumEntries: 2, retention: 60, now: { now })
        cache.set(RichCommentDraft(elements: [.text("A")]), for: key(oid: "A"))
        cache.set(RichCommentDraft(elements: [.text("B")]), for: key(oid: "B"))
        cache.set(RichCommentDraft(elements: [.text("C")]), for: key(oid: "C"))
        XCTAssertNil(cache.draft(for: key(oid: "A")))
        XCTAssertNotNil(cache.draft(for: key(oid: "B")))
        now = now.addingTimeInterval(60)
        XCTAssertNil(cache.draft(for: key(oid: "B")))
        XCTAssertNil(cache.draft(for: key(oid: "C")))
    }

    func testSoftByteBudgetEvictsOlderDraftBeforeCurrentLargeAttachment() {
        let cache = ScopedCommentDraftCache(byteBudget: 4)
        cache.set(RichCommentDraft(elements: [.text("old")]), for: key(oid: "old"))
        let current = RichCommentDraft(images: [RichCommentImageDraft(sourceIdentifier: nil, data: Data(repeating: 1, count: 8))])
        cache.set(current, for: key())
        XCTAssertNil(cache.draft(for: key(oid: "old")))
        XCTAssertEqual(cache.draft(for: key()), current)
    }

    private func key(
        account: Int = 1, oid: String = "video", type: Int = 1,
        root: Int? = nil, parent: Int? = nil
    ) -> ScopedCommentDraftKey {
        ScopedCommentDraftKey(accountMID: account, commentType: type, oid: oid, rootID: root, parentID: parent)
    }
}
