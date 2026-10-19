import Foundation

nonisolated struct HomeFeedSnapshotContext: Hashable, Sendable {
    let mode: HomeFeedMode
    let guestModeEnabled: Bool
    let recommendSource: HomeRecommendFeedSourcePreference
    let accountIdentityKey: String
}

nonisolated protocol HomeFeedSnapshotStoring: Sendable {
    func save(videos: [VideoItem], context: HomeFeedSnapshotContext, lastSeenMarkerIndex: Int?)
    func load(context: HomeFeedSnapshotContext) async -> HomeFeedSnapshotRestore?
}

/// All mutable state and disk access are confined to one utility queue. Enqueueing
/// from the main actor preserves save/clear ordering without blocking UI work.
nonisolated final class HomeFeedSnapshotStorage: HomeFeedSnapshotStoring, @unchecked Sendable {
    static let shared = HomeFeedSnapshotStorage()

    private struct PendingSave {
        let revision: UInt64
        let videos: [VideoItem]
        let marker: Int?
    }

    private let queue = DispatchQueue(label: "cc.bili.home-snapshots", qos: .utility)
    private let delay: TimeInterval
    private let read: @Sendable (HomeFeedSnapshotContext) -> HomeFeedSnapshotRestore?
    private let write: @Sendable ([VideoItem], HomeFeedSnapshotContext, Int?) -> Void
    private let removeAll: @Sendable () -> Void
    private var revision: UInt64 = 0
    private var pending: [HomeFeedSnapshotContext: PendingSave] = [:]

    init(
        delay: TimeInterval = 0.3,
        read: @escaping @Sendable (HomeFeedSnapshotContext) -> HomeFeedSnapshotRestore? = { context in
            HomeFeedSnapshotCache.load(
                mode: context.mode, guestModeEnabled: context.guestModeEnabled,
                recommendSource: context.recommendSource, accountIdentityKey: context.accountIdentityKey
            )
        },
        write: @escaping @Sendable ([VideoItem], HomeFeedSnapshotContext, Int?) -> Void = { videos, context, marker in
            HomeFeedSnapshotCache.save(
                videos: videos, mode: context.mode, guestModeEnabled: context.guestModeEnabled,
                recommendSource: context.recommendSource, accountIdentityKey: context.accountIdentityKey,
                lastSeenMarkerIndex: marker
            )
        },
        removeAll: @escaping @Sendable () -> Void = { HomeFeedSnapshotCache.clearAll() }
    ) {
        self.delay = max(0, delay)
        self.read = read
        self.write = write
        self.removeAll = removeAll
    }

    func save(videos: [VideoItem], context: HomeFeedSnapshotContext, lastSeenMarkerIndex: Int?) {
        let boundedVideos = Array(videos.prefix(48))
        queue.async { [self] in
            revision &+= 1
            let savedRevision = revision
            pending[context] = PendingSave(revision: savedRevision, videos: boundedVideos, marker: lastSeenMarkerIndex)
            queue.asyncAfter(deadline: .now() + delay) { [self] in
                guard pending[context]?.revision == savedRevision else { return }
                flush(context: context)
            }
        }
    }

    func load(context: HomeFeedSnapshotContext) async -> HomeFeedSnapshotRestore? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                // A reader must see the latest submitted save, even within the debounce window.
                flush(context: context)
                continuation.resume(returning: read(context))
            }
        }
    }

    func clear() {
        queue.async { [self] in
            pending.removeAll()
            // Delayed callbacks hold unique revisions and cannot resurrect cleared data.
            removeAll()
        }
    }

    func flushPendingSaves() {
        queue.async { [self] in
            for context in Array(pending.keys) { flush(context: context) }
        }
    }

    /// Also provides a deterministic barrier for tests, without timers or sleeps.
    func waitForPendingOperations() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }

    private func flush(context: HomeFeedSnapshotContext) {
        guard let save = pending.removeValue(forKey: context) else { return }
        write(save.videos, context, save.marker)
    }
}
