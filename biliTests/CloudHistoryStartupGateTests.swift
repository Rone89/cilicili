import XCTest
@testable import bili

/// 启动链路云端历史门控回归：无本地历史时，url 阶段不得被 /x/v2/history
/// 的完整耗时阻塞；预算内拿到按原语义恢复，晚到则走延迟校正。
@MainActor
final class CloudHistoryStartupGateTests: XCTestCase {
    func testSlowCloudHistoryDoesNotBlockStartupGate() async throws {
        let aid = Int.random(in: 1_000_000...9_000_000)
        let cid = Int.random(in: 100_000...999_999)
        let dependencies = AppDependencies()
        let vm = try makeDetailVM(dependencies: dependencies, aid: aid, cid: cid)
        let history = try makeHistory(progress: 500, cid: cid)
        await VideoPreloadCenter.shared.prefetchCloudHistoryProgress(aid: aid) {
            try? await Task.sleep(nanoseconds: 800_000_000)
            return history
        }
        let data = emptyPlayURLData()

        let start = CACurrentMediaTime()
        let redirected = await vm.prepareHistoryResumeBeforeApplyingPlayURL(data, cid: cid)
        let elapsed = CACurrentMediaTime() - start

        XCTAssertFalse(redirected)
        XCTAssertLessThan(
            elapsed, 0.5,
            "Startup gate must time-box the cloud history wait instead of blocking on the full request."
        )
        XCTAssertNil(vm.pendingPlaybackHistoryResumeTime)

        // 晚到的历史仍要生效：播放器未创建时写入待恢复路径。
        let deadline = ContinuousClock.now + .seconds(2)
        while vm.pendingPlaybackHistoryResumeTime == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(vm.pendingPlaybackHistoryResumeTime, 500)
        XCTAssertEqual(vm.pendingPlaybackHistoryResumeCID, cid)
    }

    func testFastCloudHistoryResumesWithinGate() async throws {
        let aid = Int.random(in: 1_000_000...9_000_000)
        let cid = Int.random(in: 100_000...999_999)
        let dependencies = AppDependencies()
        let vm = try makeDetailVM(dependencies: dependencies, aid: aid, cid: cid)
        let history = try makeHistory(progress: 300, cid: cid)
        await VideoPreloadCenter.shared.prefetchCloudHistoryProgress(aid: aid) {
            try? await Task.sleep(nanoseconds: 10_000_000)
            return history
        }

        let redirected = await vm.prepareHistoryResumeBeforeApplyingPlayURL(emptyPlayURLData(), cid: cid)

        XCTAssertFalse(redirected)
        XCTAssertEqual(vm.pendingPlaybackHistoryResumeTime, 300)
        XCTAssertEqual(vm.pendingPlaybackHistoryResumeCID, cid)
    }

    func testSharedHistoryPrefetchDedupsAndCaches() async throws {
        let aid = Int.random(in: 1_000_000...9_000_000)
        let cid = Int.random(in: 100_000...999_999)
        let history = try makeHistory(progress: 120, cid: cid)
        let counter = FetchCounter()

        await VideoPreloadCenter.shared.prefetchCloudHistoryProgress(aid: aid) {
            await counter.bump()
            try? await Task.sleep(nanoseconds: 50_000_000)
            return history
        }
        // 第二次预取必须加入同一任务，而不是再发一次请求。
        await VideoPreloadCenter.shared.prefetchCloudHistoryProgress(aid: aid) {
            await counter.bump()
            return nil
        }
        let first = await VideoPreloadCenter.shared.cloudHistoryProgress(for: aid) {
            await counter.bump()
            return nil
        }
        XCTAssertEqual(first?.progress, 120)
        // 命中短 TTL 缓存：即使注入失败闭包也不得再请求。
        let second = await VideoPreloadCenter.shared.cloudHistoryProgress(for: aid) {
            await counter.bump()
            return nil
        }
        XCTAssertEqual(second?.progress, 120)
        let count = await counter.value
        XCTAssertEqual(count, 1)
    }

    private func makeDetailVM(
        dependencies: AppDependencies,
        aid: Int,
        cid: Int
    ) throws -> VideoDetailViewModel {
        let json = """
        {"bvid":"BV1Gate\(aid)","title":"Cloud history gate probe","cid":\(cid),"aid":\(aid)}
        """
        let video = try JSONDecoder.bili.decode(VideoItem.self, from: Data(json.utf8))
        return VideoDetailViewModel(
            seedVideo: video,
            api: dependencies.api,
            libraryStore: dependencies.libraryStore,
            sessionStore: dependencies.sessionStore,
            sponsorBlockService: dependencies.sponsorBlockService
        )
    }

    private func makeHistory(progress: Double, cid: Int) throws -> VideoHistoryProgress {
        let json = #"{"progress":\#(progress),"last_play_cid":\#(cid)}"#
        return try JSONDecoder().decode(VideoHistoryProgress.self, from: Data(json.utf8))
    }

    private func emptyPlayURLData() -> PlayURLData {
        PlayURLData(
            code: 0,
            message: nil,
            durl: [],
            dash: nil,
            quality: 80,
            acceptQuality: [80, 32],
            acceptDescription: nil,
            supportFormats: [],
            lastPlayTime: nil,
            lastPlayCID: nil
        )
    }
}

private actor FetchCounter {
    private(set) var value = 0
    func bump() {
        value += 1
    }
}