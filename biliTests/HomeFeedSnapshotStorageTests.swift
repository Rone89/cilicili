import Foundation
import XCTest
@testable import bili

@MainActor
final class HomeFeedSnapshotStorageTests: XCTestCase {
    func testRapidSavesCoalesceToLatestAndAllIOStaysOffMainThread() async throws {
        let recorder = SnapshotIORecorder()
        let storage = recorder.storage()
        let context = context()
        for id in 1...20 {
            storage.save(videos: [try HomeFeedbackTestData.video(id: id)], context: context, lastSeenMarkerIndex: nil)
        }
        storage.flushPendingSaves()
        await storage.waitForPendingOperations()
        let loaded = await storage.load(context: context)
        XCTAssertEqual(loaded?.videos.map(\.bvid), ["BV20"])
        XCTAssertEqual(recorder.events, ["write:BV20", "read"])
        XCTAssertFalse(recorder.touchedMainThread)
    }

    func testAutomaticSaveCommitsWithoutAnExplicitFlush() async throws {
        let saved = expectation(description: "Debounced write")
        let storage = HomeFeedSnapshotStorage(delay: 0.02, read: { _ in nil }, write: { _, _, _ in
            XCTAssertFalse(Thread.isMainThread)
            saved.fulfill()
        }, removeAll: {})
        storage.save(videos: [try HomeFeedbackTestData.video()], context: context(), lastSeenMarkerIndex: nil)
        await fulfillment(of: [saved], timeout: 3)
    }

    func testReadInsideDebounceWindowSeesLatestSaveAndKeeps48ItemLimit() async throws {
        let recorder = SnapshotIORecorder()
        let storage = recorder.storage()
        let videos = try (1...60).map { try HomeFeedbackTestData.video(id: $0) }
        storage.save(videos: videos, context: context(), lastSeenMarkerIndex: 20)
        let restored = await storage.load(context: context())
        XCTAssertEqual(restored?.videos.map(\.bvid), Array(videos.prefix(48)).map(\.bvid))
        XCTAssertEqual(restored?.lastSeenMarkerIndex, 20)
        XCTAssertEqual(recorder.events, ["write:BV1", "read"])
    }

    func testClearDropsPendingWritesAndAllowsOnlyNewerSaves() async throws {
        let recorder = SnapshotIORecorder()
        let storage = recorder.storage()
        storage.save(videos: [try HomeFeedbackTestData.video(id: 1)], context: context(), lastSeenMarkerIndex: nil)
        storage.clear()
        let cleared = await storage.load(context: context())
        XCTAssertNil(cleared)
        storage.save(videos: [try HomeFeedbackTestData.video(id: 2)], context: context(), lastSeenMarkerIndex: nil)
        storage.flushPendingSaves()
        await storage.waitForPendingOperations()
        XCTAssertEqual(recorder.events, ["clear", "read", "write:BV2"])
        XCTAssertFalse(recorder.touchedMainThread)
    }

    func testCoalescingKeepsAccountsSourcesAndModesIndependent() async throws {
        let recorder = SnapshotIORecorder()
        let storage = recorder.storage()
        let contexts = [context(), context(identity: "account-B"), context(source: .app), context(mode: .popular), context(guest: true)]
        for (index, key) in contexts.enumerated() {
            storage.save(videos: [try HomeFeedbackTestData.video(id: index + 1)], context: key, lastSeenMarkerIndex: nil)
        }
        for (index, key) in contexts.enumerated() {
            let restored = await storage.load(context: key)
            XCTAssertEqual(restored?.videos.first?.bvid, "BV\(index + 1)")
        }
    }

    func testContextChangeDuringRestoreRejectsOldSnapshot() async throws {
        let gate = SuspendedSnapshotStorage()
        let (library, session) = stores()
        let coordinator = HomeFeedSnapshotCoordinator(libraryStore: library, sessionStore: session, storage: gate)
        let load = Task { await coordinator.load(mode: .recommend) }
        await gate.waitForRead()
        library.setHomeRecommendFeedSourcePreference(.app)
        await gate.finish(with: HomeFeedSnapshotRestore(videos: [try HomeFeedbackTestData.video()], lastSeenMarkerIndex: nil))
        let restored = await load.value
        XCTAssertNil(restored)
    }

    func testModeChangeDuringRestoreCannotPublishOldRows() async throws {
        let gate = SuspendedSnapshotStorage()
        let model = model(storage: gate)
        let restore = Task { await model.restoreCachedVideosIfAvailable() }
        await gate.waitForRead()
        model.mode = .popular
        model.requestRevision += 1
        await gate.finish(with: HomeFeedSnapshotRestore(videos: [try HomeFeedbackTestData.video()], lastSeenMarkerIndex: nil))
        await restore.value
        XCTAssertTrue(model.videos.isEmpty)
    }

    func testNewRequestInSameModeRejectsPendingRestore() async throws {
        let gate = SuspendedSnapshotStorage()
        let model = model(storage: gate)
        let restore = Task { await model.restoreCachedVideosIfAvailable() }
        await gate.waitForRead()
        model.requestRevision += 1
        await gate.finish(with: HomeFeedSnapshotRestore(videos: [try HomeFeedbackTestData.video()], lastSeenMarkerIndex: nil))
        await restore.value
        XCTAssertTrue(model.videos.isEmpty)
    }

    func testCredentialChangeDuringRestoreRejectsOldSnapshot() async throws {
        let gate = SuspendedSnapshotStorage()
        let (library, session) = stores()
        let coordinator = HomeFeedSnapshotCoordinator(libraryStore: library, sessionStore: session, storage: gate)
        let load = Task { await coordinator.load(mode: .recommend) }
        await gate.waitForRead()
        try session.saveLoginCookies(["SESSDATA": "test-new-session", "DedeUserID": "9999"], credentialKind: .web)
        await gate.finish(with: HomeFeedSnapshotRestore(videos: [try HomeFeedbackTestData.video()], lastSeenMarkerIndex: nil))
        let restored = await load.value
        XCTAssertNil(restored)
    }

    func testFreshContentArrivingDuringRestoreIsNotOverwritten() async throws {
        let gate = SuspendedSnapshotStorage()
        let model = model(storage: gate)
        let restore = Task { await model.restoreCachedVideosIfAvailable() }
        await gate.waitForRead()
        model.updateFeed([try HomeFeedbackTestData.video(id: 2)])
        await gate.finish(with: HomeFeedSnapshotRestore(videos: [try HomeFeedbackTestData.video(id: 1)], lastSeenMarkerIndex: nil))
        await restore.value
        XCTAssertEqual(model.videos.map(\.bvid), ["BV2"])
    }

    private func context(
        identity: String = "account-A", source: HomeRecommendFeedSourcePreference = .web,
        mode: HomeFeedMode = .recommend, guest: Bool = false
    ) -> HomeFeedSnapshotContext {
        HomeFeedSnapshotContext(mode: mode, guestModeEnabled: guest, recommendSource: source, accountIdentityKey: identity)
    }

    private func stores() -> (LibraryStore, SessionStore) {
        let name = "HomeFeedSnapshotTests.\(UUID().uuidString)"
        let library = LibraryStore(userDefaults: UserDefaults(suiteName: name)!)
        library.setHomeRecommendFeedSourcePreference(.web)
        return (library, SessionStore(keychain: .inMemory(service: name)))
    }

    private func model(storage: any HomeFeedSnapshotStoring) -> HomeViewModel {
        let (library, session) = stores()
        let api = BiliAPIClient(sessionStore: session, libraryStore: library, homeRecommendDiagnosticsStore: .shared)
        return HomeViewModel(api: api, libraryStore: library, sessionStore: session, snapshotStorage: storage)
    }
}

private nonisolated final class SnapshotIORecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [HomeFeedSnapshotContext: HomeFeedSnapshotRestore] = [:]
    private var recordedEvents: [String] = []
    private var usedMainThread = false
    var events: [String] { lock.withLock { recordedEvents } }
    var touchedMainThread: Bool { lock.withLock { usedMainThread } }

    func storage() -> HomeFeedSnapshotStorage {
        HomeFeedSnapshotStorage(delay: 60, read: { [self] context in
            lock.withLock {
                usedMainThread = usedMainThread || Thread.isMainThread
                recordedEvents.append("read")
                return snapshots[context]
            }
        }, write: { [self] videos, context, marker in
            lock.withLock {
                usedMainThread = usedMainThread || Thread.isMainThread
                recordedEvents.append("write:\(videos.first?.bvid ?? "empty")")
                snapshots[context] = HomeFeedSnapshotRestore(videos: videos, lastSeenMarkerIndex: marker)
            }
        }, removeAll: { [self] in
            lock.withLock {
                usedMainThread = usedMainThread || Thread.isMainThread
                recordedEvents.append("clear")
                snapshots.removeAll()
            }
        })
    }
}

private actor SuspendedSnapshotStorage: HomeFeedSnapshotStoring {
    private var continuation: CheckedContinuation<HomeFeedSnapshotRestore?, Never>?
    private var readWaiter: CheckedContinuation<Void, Never>?
    nonisolated func save(videos: [VideoItem], context: HomeFeedSnapshotContext, lastSeenMarkerIndex: Int?) {}
    func load(context: HomeFeedSnapshotContext) async -> HomeFeedSnapshotRestore? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            readWaiter?.resume()
            readWaiter = nil
        }
    }
    func waitForRead() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { readWaiter = $0 }
    }
    func finish(with snapshot: HomeFeedSnapshotRestore) {
        continuation?.resume(returning: snapshot)
        continuation = nil
    }
}
