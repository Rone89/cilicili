import XCTest

@testable import bili

final class BiliAPIClientStateTests: XCTestCase {
    func testPendingRequestClearOnlyRemovesMatchingID() async {
        let state = BiliAPIClientState()
        let key = makeRequestKey(bvid: "BVpending")
        let first = PendingPlayURLRequest(id: UUID(), task: pendingTask())
        let second = PendingPlayURLRequest(id: UUID(), task: pendingTask())
        defer {
            first.task.cancel()
            second.task.cancel()
        }

        let existing = await state.insertPendingPlayURLRequestIfAbsent(first, for: key)
        XCTAssertNil(existing)
        let retainedRequest = await state.insertPendingPlayURLRequestIfAbsent(second, for: key)
        XCTAssertEqual(retainedRequest?.id, first.id)

        await state.clearPendingPlayURLRequest(for: key, id: second.id)
        let requestAfterMismatchedClear = await state.pendingPlayURLRequest(for: key)
        XCTAssertEqual(requestAfterMismatchedClear?.id, first.id)

        await state.clearPendingPlayURLRequest(for: key, id: first.id)
        let requestAfterMatchingClear = await state.pendingPlayURLRequest(for: key)
        XCTAssertNil(requestAfterMatchingClear)
    }

    func testClearingOneVideoCancelsOnlyMatchingPlayURLTasks() async {
        let state = BiliAPIClientState()
        let matchingRequest = PendingPlayURLRequest(id: UUID(), task: pendingTask())
        let unrelatedRequest = PendingPlayURLRequest(id: UUID(), task: pendingTask())
        let matchingStage = PendingPlayURLStageRequest(id: UUID(), task: pendingTask())
        let unrelatedStage = PendingPlayURLStageRequest(id: UUID(), task: pendingTask())

        _ = await state.insertPendingPlayURLRequestIfAbsent(
            matchingRequest,
            for: makeRequestKey(bvid: "BVmatch")
        )
        _ = await state.insertPendingPlayURLRequestIfAbsent(
            unrelatedRequest,
            for: makeRequestKey(bvid: "BVother")
        )
        _ = await state.insertPlayURLStageTaskIfAbsent(
            matchingStage,
            for: "play|BVmatch|stage"
        )
        _ = await state.insertPlayURLStageTaskIfAbsent(
            unrelatedStage,
            for: "play|BVother|stage"
        )

        await state.clearPlayURLFailuresAndTasks(containing: "BVmatch")

        XCTAssertTrue(matchingRequest.task.isCancelled)
        XCTAssertTrue(matchingStage.task.isCancelled)
        XCTAssertFalse(unrelatedRequest.task.isCancelled)
        XCTAssertFalse(unrelatedStage.task.isCancelled)

        await state.clearAllPlayURLFailuresAndTasks()
        XCTAssertTrue(unrelatedRequest.task.isCancelled)
        XCTAssertTrue(unrelatedStage.task.isCancelled)
    }

    private func makeRequestKey(bvid: String) -> PendingPlayURLRequestKey {
        PendingPlayURLRequestKey(
            cacheKey: PlayURLCacheKey(
                bvid: bvid,
                cid: 1,
                requestedQuality: 80,
                audioLanguage: "",
                fnval: "4048",
                fnver: "0",
                platform: "web"
            ),
            scope: PlayURLCacheLoginScope(
                isLoggedIn: false,
                userMID: nil,
                guestModeEnabled: false
            )
        )
    }

    private func pendingTask() -> Task<PlayURLData, Error> {
        Task {
            try await Task.sleep(for: .seconds(60))
            throw CancellationError()
        }
    }
}
