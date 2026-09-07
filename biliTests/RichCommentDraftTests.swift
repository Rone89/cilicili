import XCTest

@testable import bili

@MainActor
final class RichCommentDraftTests: XCTestCase {
    func testRichDraftSerializesTextAndEmotesSeparatelyFromDisplayText() {
        let draft = RichCommentDraft(elements: [
            .text("你好"),
            .emote("[doge]"),
            .text("世界")
        ])

        XCTAssertEqual(draft.displayText, "你好\u{FFFC}世界")
        XCTAssertEqual(draft.serializedMessage, "你好[doge]世界")
        XCTAssertTrue(draft.hasContent)
    }

    func testRichDraftInsertsAtSelectionAndRemovesAnEmoteAsOneUnit() {
        var draft = RichCommentDraft(elements: [
            .text("前"),
            .emote("[doge]"),
            .text("后")
        ])
        draft.selection = RichCommentSelection(NSRange(location: 1, length: 0))

        let inserted = draft.replacing(draft.selection!.nsRange, with: [.text("中")])
        XCTAssertEqual(inserted.serializedMessage, "前中[doge]后")

        let removed = inserted.replacing(NSRange(location: 2, length: 1), with: [])
        XCTAssertEqual(removed.serializedMessage, "前中后")
    }

    func testRichDraftRejectsImageOnlySubmissionBecauseExistingAPIRequiresMessage() {
        let image = RichCommentImageDraft(sourceIdentifier: "photo-1", data: Data([1, 2, 3]))
        let draft = RichCommentDraft(images: [image])

        XCTAssertTrue(draft.hasContent)
        XCTAssertFalse(draft.canSubmitWithCurrentAPI)
    }
}
