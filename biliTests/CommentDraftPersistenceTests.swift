import XCTest
@testable import bili

@MainActor
final class CommentDraftPersistenceTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        try await super.tearDown()
    }

    func testRelaunchRestoresStructuredTextReplyAndSelectionWithoutImageBytes() async throws {
        let store = CommentDraftDiskStore(directory: directory)
        let cache = ScopedCommentDraftCache(persistence: store)
        let reply = DynamicCommentComposerTarget(rootID: 8, parentID: 9, authorName: "author")
        let draft = RichCommentDraft(
            elements: [.text("中文"), .emote("[doge]"), .text(" draft")],
            selection: RichCommentSelection(NSRange(location: 1, length: 0)),
            images: [RichCommentImageDraft(sourceIdentifier: "private-photo-id", data: Data("PRIVATE_IMAGE_BYTES".utf8))],
            replyTarget: reply
        )
        cache.set(draft, for: key(root: 8, parent: 9))
        await cache.flush()
        XCTAssertNil(cache.persistenceError)
        let restored = ScopedCommentDraftCache(persistence: CommentDraftDiskStore(directory: directory))
        await restored.load()
        let result = try XCTUnwrap(restored.draft(for: key(root: 8, parent: 9)))
        XCTAssertEqual(result.elements, draft.elements)
        XCTAssertEqual(result.selection, draft.selection)
        XCTAssertEqual(result.replyTarget, reply)
        XCTAssertTrue(result.images.isEmpty)
        XCTAssertEqual(result.unavailableImageCount, 1)
        let data = try Data(contentsOf: directory.appendingPathComponent("drafts-v1.json"))
        let raw = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(raw.contains("PRIVATE_IMAGE_BYTES"))
        XCTAssertFalse(raw.contains("private-photo-id"))
        XCTAssertEqual(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    func testClearCannotReviveAStoredDraftOnReload() async {
        let cache = makeCache()
        cache.set(RichCommentDraft(elements: [.text("old")]), for: key())
        await cache.flush()
        let next = makeCache()
        next.set(RichCommentDraft(), for: key())
        await next.flush()
        let restarted = makeCache()
        await restarted.load()
        XCTAssertNil(restarted.draft(for: key()))
    }

    func testTypingBeforeLoadWinsOverOlderDiskContent() async {
        let cache = makeCache()
        cache.set(RichCommentDraft(elements: [.text("old")]), for: key())
        await cache.flush()
        let next = makeCache()
        next.set(RichCommentDraft(elements: [.text("new")]), for: key())
        await next.load()
        XCTAssertEqual(next.draft(for: key())?.serializedMessage, "new")
        await next.flush()
        let restarted = makeCache()
        await restarted.load()
        XCTAssertEqual(restarted.draft(for: key())?.serializedMessage, "new")
    }

    func testAccountRemovalBeforeLoadDoesNotReviveItsDraftOrClearOtherAccounts() async {
        let cache = makeCache()
        cache.set(RichCommentDraft(elements: [.text("A")]), for: key())
        cache.set(RichCommentDraft(elements: [.text("B")]), for: key(account: 2))
        await cache.flush()
        let next = makeCache()
        next.remove(accountMID: 1)
        await next.flush()
        let restarted = makeCache()
        await restarted.load()
        XCTAssertNil(restarted.draft(for: key()))
        XCTAssertEqual(restarted.draft(for: key(account: 2))?.serializedMessage, "B")
        XCTAssertNil(restarted.draft(for: key(account: 2, oid: "other")))
        XCTAssertNil(restarted.draft(for: key(account: 2, type: 17)))
        XCTAssertNil(restarted.draft(for: key(account: 2, root: 1, parent: 2)))
    }

    func testExpiredDraftsStayExpiredAcrossRestartAndCapacityIsBounded() async {
        var date = Date(timeIntervalSince1970: 1000)
        let cache = ScopedCommentDraftCache(maximumEntries: 2, retention: 60, now: { date },
                                           persistence: CommentDraftDiskStore(directory: directory))
        for oid in ["A", "B", "C"] {
            cache.set(RichCommentDraft(elements: [.text(oid)]), for: key(oid: oid))
        }
        await cache.flush()
        let next = ScopedCommentDraftCache(maximumEntries: 2, retention: 60, now: { date },
                                          persistence: CommentDraftDiskStore(directory: directory))
        await next.load()
        XCTAssertNil(next.draft(for: key(oid: "A")))
        XCTAssertNotNil(next.draft(for: key(oid: "B")))
        date = date.addingTimeInterval(60)
        let expired = ScopedCommentDraftCache(retention: 60, now: { date },
                                             persistence: CommentDraftDiskStore(directory: directory))
        await expired.load()
        XCTAssertNil(expired.draft(for: key(oid: "B")))
        XCTAssertNil(expired.draft(for: key(oid: "C")))
    }

    func testCorruptArchiveDoesNotEraseCurrentInputAndCanBeReplaced() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("corrupt".utf8).write(to: directory.appendingPathComponent("drafts-v1.json"))
        let cache = makeCache()
        cache.set(RichCommentDraft(elements: [.text("new")]), for: key())
        await cache.load()
        XCTAssertNotNil(cache.persistenceError)
        XCTAssertEqual(cache.draft(for: key())?.serializedMessage, "new")
        await cache.flush()
        XCTAssertNil(cache.persistenceError)
        let next = makeCache()
        await next.load()
        XCTAssertEqual(next.draft(for: key())?.serializedMessage, "new")
    }

    func testWriteFailureIsVisibleAndKeepsSessionDraft() async {
        let cache = ScopedCommentDraftCache(persistence: CommentDraftDiskStore(directory: directory, maximumBytes: 1))
        cache.set(RichCommentDraft(elements: [.text("keep me")]), for: key())
        await cache.flush()
        XCTAssertNotNil(cache.persistenceError)
        XCTAssertEqual(cache.draft(for: key())?.serializedMessage, "keep me")
    }

    func testDebouncedSaveEventuallyPersistsLatestTyping() async throws {
        let cache = makeCache()
        for index in 0...20 {
            cache.set(RichCommentDraft(elements: [.text("edit \(index)")]), for: key())
        }
        let reader = CommentDraftDiskStore(directory: directory)
        var value: String?
        for _ in 0..<150 {
            value = try await reader.load().first?.parts.first?.value
            if value == "edit 20" { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(value, "edit 20")
    }

    func testInvalidCursorIsIgnoredAndUnknownPartsDoNotRestore() async throws {
        let store = CommentDraftDiskStore(directory: directory)
        try await store.save([
            StoredCommentDraft(key: key(), parts: [.init(kind: "text", value: "valid")],
                               selectionLocation: Int.max, selectionLength: Int.max,
                               authorName: nil, imageCount: 0, updatedAt: Date()),
            StoredCommentDraft(key: key(oid: "bad"), parts: [.init(kind: "future", value: "unknown")],
                               selectionLocation: nil, selectionLength: nil,
                               authorName: nil, imageCount: 0, updatedAt: Date()),
        ])
        let cache = makeCache()
        await cache.load()
        XCTAssertEqual(cache.draft(for: key())?.serializedMessage, "valid")
        XCTAssertNil(cache.draft(for: key())?.selection)
        XCTAssertNil(cache.draft(for: key(oid: "bad")))
    }

    func testLateOlderWriteCannotReviveDeletedDraft() async throws {
        let store = CommentDraftDiskStore(directory: directory)
        let record = StoredCommentDraft(
            key: key(), parts: [.init(kind: "text", value: "old")],
            selectionLocation: nil, selectionLength: nil,
            authorName: nil, imageCount: 0, updatedAt: Date()
        )
        try await store.save([record], revision: 1)
        try await store.save([], revision: 3)
        try await store.save([record], revision: 2)
        let remaining = try await store.load()
        XCTAssertTrue(remaining.isEmpty)
    }

    private func makeCache() -> ScopedCommentDraftCache {
        ScopedCommentDraftCache(persistence: CommentDraftDiskStore(directory: directory))
    }

    private func key(account: Int = 1, oid: String = "video", type: Int = 1,
                     root: Int? = nil, parent: Int? = nil) -> ScopedCommentDraftKey {
        ScopedCommentDraftKey(accountMID: account, commentType: type, oid: oid, rootID: root, parentID: parent)
    }
}
