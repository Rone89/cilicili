import SwiftUI
import XCTest

@testable import bili

@MainActor
final class RichCommentDraftTests: XCTestCase {
    func testBindingsCapturedBeforeHostRefreshReadTheCurrentSharedDraft() {
        let store = RichCommentDraftStore()
        let parentBinding = store.binding(for: .dynamic)
        let olderHostBinding = store.binding(for: .dynamic)
        parentBinding.wrappedValue = RichCommentDraft(elements: [.text("n")])
        let oldRender = olderHostBinding.wrappedValue
        let coordinator = RichCommentTextView.Coordinator(
            draft: olderHostBinding, onFocusChange: { _ in }, onHeightChange: { _ in }
        )
        let editor = RichCommentUIKitTextView()
        coordinator.applyIfNeeded(draft: oldRender, to: editor, emotes: [])
        editor.text = "native"
        editor.selectedRange = NSRange(location: 6, length: 0)
        coordinator.textViewDidChange(editor)
        coordinator.updateDraftBinding(parentBinding)
        coordinator.applyIfNeeded(draft: oldRender, to: editor, emotes: [])
        XCTAssertEqual(editor.text, "native")
        XCTAssertEqual(olderHostBinding.wrappedValue.serializedMessage, "native")
        XCTAssertEqual(store.binding(for: .dynamic).wrappedValue.serializedMessage, "native")
    }

    func testSharedStoreKeepsReplyTargetsSeparateAcrossHostRecreation() {
        let store = RichCommentDraftStore()
        let reply = DynamicCommentComposerTarget(rootID: 42, parentID: 43, authorName: "reply")
        store.binding(for: .dynamic).wrappedValue = RichCommentDraft(elements: [.text("root draft")])
        store.binding(for: reply).wrappedValue = RichCommentDraft(elements: [.text("reply draft")], replyTarget: reply)
        XCTAssertEqual(store.binding(for: .dynamic).wrappedValue.serializedMessage, "root draft")
        XCTAssertEqual(store.binding(for: reply).wrappedValue.serializedMessage, "reply draft")
        XCTAssertEqual(store.binding(for: reply).wrappedValue.replyTarget, reply)
    }

    func testSelectionCallbackBeforeTextChangeCannotRollBackNativeBuffer() {
        var draft = RichCommentDraft(elements: [.text("n")])
        let coordinator = RichCommentTextView.Coordinator(
            draft: Binding(get: { draft }, set: { draft = $0 }),
            onFocusChange: { _ in }, onHeightChange: { _ in }
        )
        let editor = RichCommentUIKitTextView()
        coordinator.applyIfNeeded(draft: draft, to: editor, emotes: [])
        XCTAssertTrue(coordinator.textView(editor, shouldChangeTextIn: NSRange(location: 1, length: 0), replacementText: "ative"))
        editor.text = "native"
        editor.selectedRange = NSRange(location: 6, length: 0)
        coordinator.textViewDidChangeSelection(editor)
        coordinator.applyIfNeeded(draft: draft, to: editor, emotes: [])
        XCTAssertEqual(editor.text, "native")
        coordinator.textViewDidChange(editor)
        XCTAssertEqual(draft.serializedMessage, "native")
        XCTAssertEqual(draft.selection?.nsRange, NSRange(location: 6, length: 0))
    }

    func testExternalReplacementStillReplacesCommittedNativeText() {
        var draft = RichCommentDraft(elements: [.text("native")])
        let coordinator = RichCommentTextView.Coordinator(
            draft: Binding(get: { draft }, set: { draft = $0 }),
            onFocusChange: { _ in }, onHeightChange: { _ in }
        )
        let editor = RichCommentUIKitTextView()
        coordinator.applyIfNeeded(draft: draft, to: editor, emotes: [])
        draft.elements = [.text("external replacement")]
        coordinator.applyIfNeeded(draft: draft, to: editor, emotes: [])
        XCTAssertEqual(editor.text, "external replacement")
        XCTAssertEqual(draft.serializedMessage, "external replacement")
    }

    func testStaleRenderSnapshotDoesNotReplaceNewerCommittedText() {
        var draft = RichCommentDraft(elements: [.text("na")])
        let coordinator = RichCommentTextView.Coordinator(
            draft: Binding(get: { draft }, set: { draft = $0 }),
            onFocusChange: { _ in }, onHeightChange: { _ in }
        )
        let textView = RichCommentUIKitTextView()
        coordinator.applyIfNeeded(draft: draft, to: textView, emotes: [])
        let staleSnapshot = draft
        textView.text = "native"
        textView.selectedRange = NSRange(location: 6, length: 0)
        coordinator.textViewDidChange(textView)
        coordinator.applyIfNeeded(draft: staleSnapshot, to: textView, emotes: [])
        XCTAssertEqual(textView.text, "native")
        XCTAssertEqual(draft.serializedMessage, "native")
    }

    func testCoordinatorWritesToLatestDraftBindingWhenTargetChanges() {
        var first = RichCommentDraft(elements: [.text("first")])
        var second = RichCommentDraft(elements: [.text("second")])
        let coordinator = RichCommentTextView.Coordinator(
            draft: Binding(get: { first }, set: { first = $0 }),
            onFocusChange: { _ in }, onHeightChange: { _ in }
        )
        let textView = RichCommentUIKitTextView()
        coordinator.applyIfNeeded(draft: first, to: textView, emotes: [])
        coordinator.updateDraftBinding(Binding(get: { second }, set: { second = $0 }))
        coordinator.applyIfNeeded(draft: second, to: textView, emotes: [])
        textView.text = "new reply"
        coordinator.textViewDidChange(textView)
        XCTAssertEqual(first.serializedMessage, "first")
        XCTAssertEqual(second.serializedMessage, "new reply")
    }

    func testDeferredDraftRecoveryDoesNotOverwriteNewTyping() async {
        await verifyDeferredRecovery(replacement: "native", expected: "native")
    }

    func testDeferredDraftRecoveryDoesNotRestoreDeletedText() async {
        await verifyDeferredRecovery(replacement: "", expected: "")
    }

    func testDeferredDraftRecoveryRestoresUnchangedSnapshot() async {
        await verifyDeferredRecovery(replacement: nil, expected: "na")
    }

    private func verifyDeferredRecovery(replacement: String?, expected: String) async {
        var draft = RichCommentDraft(elements: [.text("na")])
        let coordinator = RichCommentTextView.Coordinator(
            draft: Binding(get: { draft }, set: { draft = $0 }),
            onFocusChange: { _ in },
            onHeightChange: { _ in }
        )
        let textView = RichCommentUIKitTextView()
        coordinator.applyIfNeeded(draft: draft, to: textView, emotes: [])
        // Reproduce an empty SwiftUI snapshot arriving after UIKit rendered text.
        draft = RichCommentDraft()
        coordinator.applyIfNeeded(draft: draft, to: textView, emotes: [])
        if let replacement {
            textView.text = replacement
            textView.selectedRange = NSRange(location: replacement.utf16.count, length: 0)
            coordinator.textViewDidChange(textView)
        }
        // Drain the same queue as recovery, without relying on elapsed time.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
        XCTAssertEqual(draft.serializedMessage, expected)
        XCTAssertEqual(textView.text, expected)
    }

    func testTextViewDelegateAllowsNativeIMEReplacementAndSyncsCommittedChineseText() {
        var draft = RichCommentDraft()
        let coordinator = RichCommentTextView.Coordinator(
            draft: Binding(
                get: { draft },
                set: { draft = $0 }
            ),
            onFocusChange: { _ in },
            onHeightChange: { _ in }
        )
        let textView = RichCommentUIKitTextView()
        textView.delegate = coordinator

        XCTAssertTrue(
            coordinator.textView(
                textView,
                shouldChangeTextIn: NSRange(location: 0, length: 0),
                replacementText: "你"
            )
        )

        textView.attributedText = NSAttributedString(
            string: "你好",
            attributes: [
                .font: textView.font ?? UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: UIColor.label
            ]
        )
        textView.selectedRange = NSRange(location: 2, length: 0)
        coordinator.textViewDidChange(textView)

        XCTAssertEqual(draft.serializedMessage, "你好")
        XCTAssertEqual(draft.selection, RichCommentSelection(NSRange(location: 2, length: 0)))
    }

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

    func testRichDraftRemovesItsOnlyEmote() {
        let draft = RichCommentDraft(elements: [.emote("[doge]")])

        let removed = draft.replacing(NSRange(location: 0, length: 1), with: [])

        XCTAssertTrue(removed.elements.isEmpty)
        XCTAssertEqual(removed.displayText, "")
        XCTAssertEqual(removed.serializedMessage, "")
    }

    func testRichDraftRejectsImageOnlySubmissionBecauseExistingAPIRequiresMessage() {
        let image = RichCommentImageDraft(sourceIdentifier: "photo-1", data: Data([1, 2, 3]))
        let draft = RichCommentDraft(images: [image])

        XCTAssertTrue(draft.hasContent)
        XCTAssertFalse(draft.canSubmitWithCurrentAPI)
    }
}
