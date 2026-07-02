import XCTest
@testable import bili

final class DashStreamDispatcherTests: XCTestCase {
    func testAutoPrefersHEVCOverH264AndAV1() {
        let h264 = stream(codecs: "avc1.64002a", bandwidth: 8_000)
        let hevc = stream(codecs: "hev1.1.6.L120.90", bandwidth: 12_000)
        let av1 = stream(codecs: "av01.0.08M.08", bandwidth: 6_000)

        let selected = CoreVideoPlayerManager.selectBestStream(
            from: [h264, hevc, av1],
            preference: .auto,
            kernel: .ksPlayer
        )

        XCTAssertEqual(selected?.codecs, hevc.codecs)
    }

    func testAutoPrefersHEVCWhenAVPlayerKernelIsRequested() {
        let h264 = stream(codecs: "avc1.64002a", bandwidth: 8_000)
        let hevc = stream(codecs: "hev1.1.6.L120.90", bandwidth: 12_000)
        let av1 = stream(codecs: "av01.0.08M.08", bandwidth: 6_000)

        let selected = CoreVideoPlayerManager.selectBestStream(
            from: [h264, hevc, av1],
            preference: .auto,
            kernel: .avPlayer
        )

        XCTAssertEqual(selected?.codecs, hevc.codecs)
    }

    func testAV1IsNotSelectedWhenItIsTheOnlyStream() {
        let h264 = stream(codecs: "avc1.64002a")
        let av1 = stream(codecs: "av01.0.08M.08")

        let selected = CoreVideoPlayerManager.selectBestStream(
            from: [av1],
            preference: .auto
        )

        XCTAssertNil(selected)
        XCTAssertEqual(VideoCodecPreference.forceAV1.normalizedForPlayback, .auto)
        XCTAssertEqual(CoreVideoPlayerManager.selectBestStream(from: [h264, av1], preference: .forceAV1)?.codecs, h264.codecs)
    }

    func testForceHEVCRejectsOtherCodecs() {
        let h264 = stream(codecs: "avc1.64002a")
        let av1 = stream(codecs: "av01.0.08M.08")

        let selected = CoreVideoPlayerManager.selectBestStream(
            from: [av1, h264],
            preference: .forceHEVC
        )

        XCTAssertNil(selected)
    }

    func testForceH264RejectsOtherCodecs() {
        let hevc = stream(codecs: "hev1.1.6.L120.90")
        let av1 = stream(codecs: "av01.0.08M.08")

        let selected = CoreVideoPlayerManager.selectBestStream(
            from: [av1, hevc],
            preference: .forceH264
        )

        XCTAssertNil(selected)
    }

    func testSameCodecChoosesHigherBandwidth() {
        let lower = stream(codecs: "hev1.1.6.L120.90", bandwidth: 4_000)
        let higher = stream(codecs: "hev1.1.6.L120.90", bandwidth: 8_000)

        let selected = CoreVideoPlayerManager.selectBestStream(
            from: [lower, higher],
            preference: .auto
        )

        XCTAssertEqual(selected?.bandwidth, higher.bandwidth)
    }

    private func stream(
        codecs: String,
        bandwidth: Int = 1_000
    ) -> DashStream {
        DashStream(
            id: 80,
            url: URL(string: "https://upos.example.test/\(UUID().uuidString).m4s")!,
            bandwidth: bandwidth,
            codecs: codecs,
            width: 1920,
            height: 1080,
            mimeType: "video/mp4"
        )
    }
}
