import Foundation
import XCTest
@testable import bili

@MainActor
final class PlaybackProgressStorageTests: XCTestCase {
    func testEncodingRunsOffMainAndWritesKeepSubmissionOrderAcrossStores() async throws {
        let suite = "PlaybackProgressStorageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "progress"
        let storage = PlaybackProgressStorage(defaults: defaults, key: key) { progress in
            XCTAssertFalse(Thread.isMainThread)
            return try JSONEncoder().encode(progress)
        }
        let replacement = PlaybackProgressStorage(defaults: defaults, key: key)
        for time in 1...120 { storage.save(["BV1": progress(time: Double(time))]) }
        replacement.save(["BV1": progress(time: 999)])
        await replacement.waitForPendingOperations()
        let restored = try JSONDecoder().decode([String: StoredPlaybackProgress].self,
            from: XCTUnwrap(defaults.data(forKey: key)))
        XCTAssertEqual(restored["BV1"]?.playbackTime, 999)
        replacement.save([:])
        await replacement.waitForPendingOperations()
        XCTAssertNil(defaults.data(forKey: key))
    }

    func testEncodingFailureKeepsPreviousSavedProgress() async throws {
        let suite = "PlaybackProgressStorageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = PlaybackProgressStorage(defaults: defaults, key: "progress")
        storage.save(["BV1": progress(time: 10)])
        await storage.waitForPendingOperations()
        let original = defaults.data(forKey: "progress")
        storage.save(["BV1": progress(time: .nan)])
        await storage.waitForPendingOperations()
        XCTAssertEqual(defaults.data(forKey: "progress"), original)
    }

    func testLibraryResumeRemainsImmediateAndPersistenceRestoresLatestProgress() async throws {
        let suite = "PlaybackProgressStorageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = LibraryStore(userDefaults: defaults)
        let video = try HomeFeedbackTestData.video()
        library.recordPlaybackProgress(video: video, cid: 123, progress: 45, duration: 300)
        XCTAssertEqual(library.localPlaybackResumeTime(for: video, cid: 123, duration: 300), 45)
        await library.playbackProgressStorage.waitForPendingOperations()
        let restored = LibraryStore(userDefaults: defaults)
        XCTAssertEqual(restored.localPlaybackResumeTime(for: video, cid: 123, duration: 300), 45)
        XCTAssertNil(restored.localPlaybackResumeTime(for: video, cid: 456, duration: 300))
    }

    private func progress(time: TimeInterval) -> StoredPlaybackProgress {
        StoredPlaybackProgress(bvid: "BV1", cid: 123, playbackTime: time,
                               playbackDuration: 3000, updatedAt: Date())
    }
}
