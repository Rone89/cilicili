import Combine
import Foundation
import SwiftUI

nonisolated struct ScopedCommentDraftKey: Hashable {
    let accountMID: Int
    let commentType: Int
    let oid: String
    let rootID: Int?
    let parentID: Int?
}

/// Session-only recovery. No text, cookies or image bytes are written to disk.
@MainActor
final class ScopedCommentDraftCache: ObservableObject {
    static let shared = ScopedCommentDraftCache()

    private struct Entry {
        let draft: RichCommentDraft
        let updatedAt: Date
        let sequence: UInt64
        let bytes: Int
    }

    @Published private var entries: [ScopedCommentDraftKey: Entry] = [:]
    private var sequence: UInt64 = 0
    private let maximumEntries: Int
    private let byteBudget: Int
    private let retention: TimeInterval
    private let now: () -> Date

    init(
        maximumEntries: Int = 64,
        byteBudget: Int = 32 * 1024 * 1024,
        retention: TimeInterval = 24 * 60 * 60,
        now: @escaping () -> Date = Date.init
    ) {
        self.maximumEntries = max(1, maximumEntries)
        self.byteBudget = max(1, byteBudget)
        self.retention = max(0, retention)
        self.now = now
    }

    func draft(for key: ScopedCommentDraftKey) -> RichCommentDraft? {
        guard let entry = entries[key], now().timeIntervalSince(entry.updatedAt) < retention else { return nil }
        return entry.draft
    }

    func set(_ draft: RichCommentDraft, for key: ScopedCommentDraftKey) {
        let date = now()
        var next = entries.filter { date.timeIntervalSince($0.value.updatedAt) < retention }
        if draft.hasContent {
            sequence &+= 1
            let bytes = draft.serializedMessage.utf8.count + draft.images.reduce(0) { $0 + $1.data.count }
            next[key] = Entry(draft: draft, updatedAt: date, sequence: sequence, bytes: bytes)
        } else {
            next[key] = nil
        }
        // Retain the newest draft even if its own attachments exceed the soft
        // budget. Never erase the text currently being edited to enforce a cap.
        var bytes = next.values.reduce(0) { $0 + $1.bytes }
        while next.count > maximumEntries || (bytes > byteBudget && next.count > 1) {
            guard let oldest = next.filter({ $0.key != key }).min(by: { $0.value.sequence < $1.value.sequence }) else { break }
            bytes -= oldest.value.bytes
            next[oldest.key] = nil
        }
        entries = next
    }

    func remove(accountMID: Int) {
        entries = entries.filter { $0.key.accountMID != accountMID }
    }
}

private struct ScopedCommentDraftPresentationID: Hashable {
    let key: ScopedCommentDraftKey?
    let credentialVersion: Int
}

struct ScopedRichCommentComposerView: View {
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var cache = ScopedCommentDraftCache.shared
    @Binding var localDraft: RichCommentDraft
    let target: DynamicCommentComposerTarget
    let contentTarget: CommentLikeTarget?
    let api: BiliAPIClient
    let horizontalPadding: CGFloat
    let submit: (DynamicCommentComposerTarget, String, [DynamicCommentImage]?) async throws -> Void
    let onDismiss: () -> Void

    var body: some View {
        let snapshot = api.requestSnapshot(purpose: .interaction)
        let key = draftKey(snapshot)
        RichCommentComposerView(
            draft: scopedBinding(key: key, snapshot: snapshot),
            target: target,
            api: api,
            submit: { target, message, pictures in
                if key != nil, !isCurrent(snapshot) { throw CancellationError() }
                try await submit(target, message, pictures)
            },
            horizontalPadding: horizontalPadding,
            onDismiss: onDismiss
        )
        .id(ScopedCommentDraftPresentationID(key: key, credentialVersion: snapshot.playbackCredentialVersion))
    }

    private func draftKey(_ snapshot: BiliAPIClient.RequestSnapshot) -> ScopedCommentDraftKey? {
        guard snapshot.isLoggedIn, snapshot.isAccountPurposeEnabled, !snapshot.guestModeEnabled,
              let mid = snapshot.currentUserMID, mid > 0, let contentTarget else { return nil }
        return ScopedCommentDraftKey(
            accountMID: mid, commentType: contentTarget.type, oid: contentTarget.oid,
            rootID: target.rootID, parentID: target.parentID
        )
    }

    private func scopedBinding(
        key: ScopedCommentDraftKey?,
        snapshot: BiliAPIClient.RequestSnapshot
    ) -> Binding<RichCommentDraft> {
        guard let key else { return $localDraft }
        return Binding(
            get: {
                guard isCurrent(snapshot) else { return RichCommentDraft(replyTarget: target) }
                return cache.draft(for: key) ?? RichCommentDraft(replyTarget: target)
            },
            set: { value in
                guard isCurrent(snapshot) else { return }
                cache.set(value, for: key)
            }
        )
    }

    private func isCurrent(_ snapshot: BiliAPIClient.RequestSnapshot) -> Bool {
        let current = api.requestSnapshot(purpose: .interaction)
        return current.isLoggedIn && current.isAccountPurposeEnabled && !current.guestModeEnabled
            && current.currentUserMID == snapshot.currentUserMID
            && current.playbackCredentialVersion == snapshot.playbackCredentialVersion
            && current.cookieHeader == snapshot.cookieHeader
    }
}
