import Combine
import Foundation
import SwiftUI

nonisolated struct ScopedCommentDraftKey: Hashable, Codable, Sendable {
    let accountMID: Int
    let commentType: Int
    let oid: String
    let rootID: Int?
    let parentID: Int?
}

/// Rich session recovery with debounced, account-scoped text/emote persistence.
@MainActor
final class ScopedCommentDraftCache: ObservableObject {
    static let shared: ScopedCommentDraftCache = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-test-fixture") {
            guard arguments.contains("--ui-test-persistent-comment-drafts") else {
                return ScopedCommentDraftCache()
            }
            return ScopedCommentDraftCache(persistence: CommentDraftDiskStore(
                directory: FileManager.default.temporaryDirectory.appendingPathComponent("UITestCommentDrafts"),
                resetsBeforeLoading: arguments.contains("--ui-test-clear-comment-drafts")
            ))
        }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return ScopedCommentDraftCache()
        }
        #endif
        return ScopedCommentDraftCache(persistence: CommentDraftDiskStore(
            directory: URL.applicationSupportDirectory.appendingPathComponent("CommentDrafts", isDirectory: true)
        ))
    }()

    private struct Entry {
        let draft: RichCommentDraft
        let updatedAt: Date
        let sequence: UInt64
        let bytes: Int
    }

    @Published private var entries: [ScopedCommentDraftKey: Entry] = [:]
    @Published private(set) var persistenceError: String?
    private var sequence: UInt64 = 0
    private var saveRevision: UInt64 = 0
    private let maximumEntries: Int
    private let byteBudget: Int
    private let retention: TimeInterval
    private let now: () -> Date
    private let persistence: CommentDraftDiskStore?
    @Published private(set) var didLoad = false
    private var loadTask: Task<[StoredCommentDraft], Error>?
    private var saveTask: Task<Void, Never>?
    private var changedBeforeLoad = Set<ScopedCommentDraftKey>()
    private var removedAccountsBeforeLoad = Set<Int>()

    init(
        maximumEntries: Int = 64,
        byteBudget: Int = 32 * 1024 * 1024,
        retention: TimeInterval = 24 * 60 * 60,
        now: @escaping () -> Date = Date.init,
        persistence: CommentDraftDiskStore? = nil
    ) {
        self.maximumEntries = max(1, maximumEntries)
        self.byteBudget = max(1, byteBudget)
        self.retention = max(0, retention)
        self.now = now
        self.persistence = persistence
    }

    func draft(for key: ScopedCommentDraftKey) -> RichCommentDraft? {
        guard let entry = entries[key], now().timeIntervalSince(entry.updatedAt) < retention else { return nil }
        return entry.draft
    }

    func set(_ draft: RichCommentDraft, for key: ScopedCommentDraftKey) {
        saveRevision &+= 1
        if !didLoad { changedBeforeLoad.insert(key) }
        let date = now()
        var next = entries.filter { date.timeIntervalSince($0.value.updatedAt) < retention }
        if draft.hasContent {
            sequence &+= 1
            next[key] = entry(draft, date: date)
        } else {
            next[key] = nil
        }
        trim(&next, preserving: key)
        entries = next
        scheduleSave()
    }

    func remove(accountMID: Int) {
        saveRevision &+= 1
        if !didLoad { removedAccountsBeforeLoad.insert(accountMID) }
        entries = entries.filter { $0.key.accountMID != accountMID }
        scheduleSave(immediate: true)
    }

    func load() async {
        guard !didLoad, let persistence else { didLoad = true; return }
        if loadTask == nil { loadTask = Task { try await persistence.load() } }
        do {
            let stored = try await loadTask!.value
            guard !didLoad else { return }
            var next = entries
            let date = now()
            for record in stored.sorted(by: { $0.updatedAt < $1.updatedAt }) {
                guard record.key.accountMID > 0, !record.key.oid.isEmpty,
                      !changedBeforeLoad.contains(record.key),
                      !removedAccountsBeforeLoad.contains(record.key.accountMID),
                      date.timeIntervalSince(record.updatedAt) >= 0,
                      date.timeIntervalSince(record.updatedAt) < retention,
                      record.parts.allSatisfy({ $0.kind == "text" || $0.kind == "emote" }) else { continue }
                let parts: [RichCommentDraftElement] = record.parts.map {
                    $0.kind == "emote" ? .emote($0.value) : .text($0.value)
                }
                var draft = RichCommentDraft(
                    elements: parts,
                    replyTarget: record.key.rootID == nil && record.key.parentID == nil && record.authorName == nil
                        ? nil : DynamicCommentComposerTarget(
                            rootID: record.key.rootID, parentID: record.key.parentID, authorName: record.authorName
                        ),
                    unavailableImageCount: min(max(record.imageCount, 0), 9)
                )
                if let location = record.selectionLocation, let length = record.selectionLength,
                   location >= 0, length >= 0, location <= draft.displayText.utf16.count,
                   length <= draft.displayText.utf16.count - location {
                    draft.selection = RichCommentSelection(NSRange(location: location, length: length))
                }
                guard draft.hasContent else { continue }
                sequence &+= 1
                next[record.key] = entry(draft, date: record.updatedAt)
            }
            // Hydration must never make older disk entries newer than input
            // already entered in this process, especially at the capacity limit.
            for (key, value) in entries.sorted(by: { $0.value.sequence < $1.value.sequence }) {
                sequence &+= 1
                next[key] = entry(value.draft, date: value.updatedAt)
            }
            trim(&next, preserving: nil)
            entries = next
        } catch {
            guard !didLoad else { return }
            persistenceError = "无法恢复本机草稿，当前输入仍会保留在本次使用中"
        }
        didLoad = true
        loadTask = nil
        changedBeforeLoad.removeAll()
        removedAccountsBeforeLoad.removeAll()
    }

    /// Composer dismissal/backgrounding bypasses the debounce.
    func flush() async {
        saveTask?.cancel()
        saveTask = nil
        guard let persistence else { return }
        await load()
        let date = now()
        let records = entries.compactMap { key, value -> StoredCommentDraft? in
            guard date.timeIntervalSince(value.updatedAt) < retention else { return nil }
            return StoredCommentDraft(
                key: key,
                parts: value.draft.elements.map {
                    switch $0 {
                    case .text(let value): return .init(kind: "text", value: value)
                    case .emote(let value): return .init(kind: "emote", value: value)
                    }
                },
                selectionLocation: value.draft.selection?.location,
                selectionLength: value.draft.selection?.length,
                authorName: value.draft.replyTarget?.authorName,
                imageCount: value.draft.images.count + value.draft.unavailableImageCount,
                updatedAt: value.updatedAt
            )
        }
        let revision = saveRevision
        do {
            try await persistence.save(records, revision: revision)
            persistenceError = nil
        } catch {
            persistenceError = "草稿暂未保存到本机，请保留此页面并稍后重试"
        }
    }

    private func scheduleSave(immediate: Bool = false) {
        guard persistence != nil else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            if !immediate {
                do { try await Task.sleep(for: .milliseconds(500)) }
                catch { return }
            }
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    private func entry(_ draft: RichCommentDraft, date: Date) -> Entry {
        Entry(
            draft: draft, updatedAt: date, sequence: sequence,
            bytes: draft.serializedMessage.utf8.count + draft.images.reduce(0) { $0 + $1.data.count }
        )
    }

    private func trim(_ next: inout [ScopedCommentDraftKey: Entry], preserving key: ScopedCommentDraftKey?) {
        var bytes = next.values.reduce(0) { $0 + $1.bytes }
        while next.count > maximumEntries || (bytes > byteBudget && next.count > 1) {
            guard let oldest = next.filter({ $0.key != key }).min(by: { $0.value.sequence < $1.value.sequence }) else { break }
            bytes -= oldest.value.bytes
            next[oldest.key] = nil
        }
    }
}

private struct ScopedCommentDraftPresentationID: Hashable {
    let key: ScopedCommentDraftKey?
    let credentialVersion: Int
}

struct ScopedRichCommentComposerView: View {
    @Environment(\.scenePhase) private var scenePhase
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
        Group {
            if key != nil && !cache.didLoad {
                ProgressView("正在恢复草稿")
            } else {
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
        }
        .task { await cache.load() }
        .onDisappear { Task { await cache.flush() } }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { await cache.flush() } }
        }
        .overlay(alignment: .top) {
            if let error = cache.persistenceError {
                Text(error).font(.footnote).padding(8).background(.regularMaterial, in: .rect(cornerRadius: 12))
                    .accessibilityIdentifier("comment.draft.persistenceError")
            }
        }
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
