import XCTest
@testable import bili

@MainActor
final class LivePlaybackDiagnosticsTextBuilderTests: XCTestCase {
    func testCopyTextIncludesLiveExperimentAndPerformanceStateWithoutStreamURL() {
        LiveStreamStartupHealthMemory.shared.reset()
        defer { LiveStreamStartupHealthMemory.shared.reset() }
        let defaultsName = "LivePlaybackDiagnosticsTextBuilderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let viewModel = makeViewModel(defaults: defaults, keychainService: defaultsName)
        viewModel.streamCandidates = [
            LiveStreamURLCandidate(
                url: URL(string: "https://live.example.com/live.m3u8?token=secret")!,
                protocolName: "http_hls",
                formatName: "fmp4",
                codecName: "avc",
                currentQN: 10000,
                qualityTitle: "原画",
                source: "v2"
            ),
            LiveStreamURLCandidate(
                url: URL(string: "https://fallback.example.com/live-bvc/123/live.m3u8?token=other-secret")!,
                protocolName: "http_hls",
                formatName: "fmp4",
                codecName: "avc",
                currentQN: 10000,
                qualityTitle: "原画",
                source: "v2"
            )
        ]
        viewModel.slowStartupRouteSwitchStatus = "线路 1 首帧 7200ms"
        LiveStreamStartupHealthMemory.shared.recordStartupResult(
            for: viewModel.streamCandidates[0],
            firstFrameMilliseconds: 7_200
        )

        var performanceSession = PlayerPerformanceSession(id: "live-1")
        performanceSession.title = "测试直播间"
        performanceSession.firstFrameTotalMilliseconds = 820
        performanceSession.firstFramePlayerMilliseconds = 240
        performanceSession.playURLMilliseconds = 530

        let text = LivePlaybackDiagnosticsTextBuilder(
            viewModel: viewModel,
            performanceSession: performanceSession
        ).text

        XCTAssertTrue(text.contains("CiliCili 直播播放诊断"))
        XCTAssertTrue(text.contains("metricsID: live-1"))
        XCTAssertTrue(text.contains("sourceHost: live.example.com"))
        XCTAssertTrue(text.contains("直播优化:"))
        XCTAssertTrue(text.contains("parallelStartup: fixed"))
        XCTAssertTrue(text.contains("slowStartupRouteSwitch: fixed"))
        XCTAssertTrue(text.contains("rotationSurfaceAlignment: fixed"))
        XCTAssertTrue(text.contains("直播旋转:"))
        XCTAssertTrue(text.contains("candidates:"))
        XCTAssertTrue(text.contains("fallback.example.com"))
        XCTAssertTrue(text.contains("最近首帧 7200ms"))
        XCTAssertTrue(text.contains("播放性能测试结果"))
        XCTAssertFalse(text.contains("token=secret"))
        XCTAssertFalse(text.contains("token=other-secret"))
        XCTAssertFalse(text.contains("live.m3u8"))
    }

    private func makeViewModel(defaults: UserDefaults, keychainService: String) -> LiveRoomViewModel {
        let libraryStore = LibraryStore(userDefaults: defaults)
        let sessionStore = SessionStore(keychain: KeychainStore.inMemory(service: keychainService))
        let api = BiliAPIClient(
            session: URLSession(configuration: .ephemeral),
            sessionStore: sessionStore,
            libraryStore: libraryStore,
            homeRecommendDiagnosticsStore: .shared
        )
        return LiveRoomViewModel(
            seedRoom: LiveRoom(
                roomID: 1,
                title: "测试直播间",
                uname: "测试主播",
                uid: 1,
                face: nil,
                cover: nil,
                keyframe: nil,
                online: nil,
                areaName: nil,
                parentAreaName: nil,
                liveStatus: 1
            ),
            api: api,
            libraryStore: libraryStore
        )
    }
}
