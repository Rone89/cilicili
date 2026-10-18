import XCTest
@testable import bili

final class DynamicFeedDiskSnapshotStoreTests: XCTestCase {
    func testSnapshotIsAccountScopedAndExpires() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "dynamic-feed-snapshot-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = DynamicFeedDiskSnapshotStore(
            directory: directory,
            freshnessInterval: 180,
            maximumSnapshotCount: 2
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let data = Data("{\"code\":0,\"data\":{}}".utf8)
        await store.store(data, for: "account-1")
        // Anchor reads to the written file timestamp, independent of runner scheduling.
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ).first)
        let writtenAt = try XCTUnwrap(file.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate)
        let storedData = await store.freshData(for: "account-1", now: writtenAt)
        let otherAccountData = await store.freshData(for: "account-2", now: writtenAt)

        XCTAssertEqual(storedData, data)
        XCTAssertNil(otherAccountData)

        let boundaryData = await store.freshData(for: "account-1", now: writtenAt.addingTimeInterval(180))
        XCTAssertEqual(boundaryData, data)
        let expiredData = await store.freshData(for: "account-1", now: writtenAt.addingTimeInterval(181))
        XCTAssertNil(expiredData)
    }
}
