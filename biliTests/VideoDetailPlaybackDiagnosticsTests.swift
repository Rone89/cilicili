import Foundation
import XCTest
@testable import bili

@MainActor
final class VideoDetailPlaybackDiagnosticsTests: XCTestCase {
    func testPlayerAndViewModelIdentitiesRemainStable() {
        let engine = AVPlayerHLSBridgeEngine()
        let viewModel = PlayerStateViewModel(
            videoURL: nil,
            audioURL: nil,
            title: "identity-test",
            referer: "https://www.bilibili.com",
            engine: engine
        )

        let viewModelIdentity = viewModel.debugPlayerIdentity
        let playerIdentity = viewModel.debugAVPlayerIdentity

        XCTAssertEqual(viewModelIdentity, viewModel.debugPlayerIdentity)
        XCTAssertEqual(playerIdentity, viewModel.debugAVPlayerIdentity)
        XCTAssertNil(viewModel.debugAVPlayerItemIdentity)
        viewModel.stop()
    }

    func testRotationRecordKeepsPlaybackIdentityAndSurfaceLifecycle() throws {
        let diagnostics = VideoDetailPlaybackDiagnostics()
        diagnostics.begin(metricsID: "diagnostic-test", title: "Rotation")

        let surface = NSObject()
        let player = NSObject()
        let item = NSObject()
        let surfaceID = ObjectIdentifier(surface)
        let playerID = ObjectIdentifier(player)
        let itemID = ObjectIdentifier(item)

        diagnostics.markRotationStarted(toLandscape: true)
        diagnostics.recordSurfaceEventForTesting(
            .attached(surfaceID: surfaceID, playerID: playerID, playerItemID: itemID)
        )
        diagnostics.recordSurfaceEventForTesting(
            .detached(surfaceID: surfaceID, playerID: playerID, playerItemID: itemID)
        )
        diagnostics.markRotationFinished(toLandscape: true)

        let record = try XCTUnwrap(diagnostics.completedRotationRecords.last)
        XCTAssertEqual(record.target, "landscape")
        XCTAssertEqual(record.surfaceAttachCount, 1)
        XCTAssertEqual(record.surfaceDetachCount, 1)
        XCTAssertEqual(record.avPlayerIdentity, String(describing: playerID))
        XCTAssertEqual(record.avPlayerItemIdentity, String(describing: itemID))
        XCTAssertEqual(record.surfaceIdentity, String(describing: surfaceID))
        XCTAssertNotNil(record.durationMilliseconds)
    }

    func testRotationRecordCapturesFinalPlaybackState() throws {
        let diagnostics = VideoDetailPlaybackDiagnostics()
        diagnostics.begin(metricsID: "playback-state-test", title: "Rotation")
        let viewModel = PlayerStateViewModel(
            videoURL: nil,
            audioURL: nil,
            title: "diagnostic-player",
            referer: "https://www.bilibili.com",
            engine: AVPlayerHLSBridgeEngine()
        )
        diagnostics.observe(player: viewModel)
        viewModel.isPlaying = true
        diagnostics.markRotationStarted(toLandscape: true)
        viewModel.isPlaying = false
        diagnostics.markRotationFinished(toLandscape: true)

        let record = try XCTUnwrap(diagnostics.completedRotationRecords.last)
        XCTAssertEqual(record.playbackState, "paused")
        XCTAssertFalse(record.isBuffering)
        viewModel.stop()
    }

    func testRotationRecordJSONContainsStructuredPlaybackFields() throws {
        let record = VideoDetailRotationDiagnosticRecord(
            target: "portrait",
            durationMilliseconds: 312.5,
            blackFrameDurationMilliseconds: 16.7,
            firstPlaybackLatencyMilliseconds: 820,
            firstFrameLatencyMilliseconds: 1_240,
            playerViewModelIdentity: "ObjectIdentifier(0x1)",
            avPlayerIdentity: "ObjectIdentifier(0x2)",
            avPlayerItemIdentity: "ObjectIdentifier(0x3)",
            surfaceIdentity: "ObjectIdentifier(0x4)",
            surfaceAttachCount: 0,
            surfaceDetachCount: 0,
            playbackState: "playing",
            isBuffering: false,
            recoveryReason: nil
        )

        let data = try JSONEncoder().encode(record)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(object["target"] as? String, "portrait")
        XCTAssertEqual(object["playbackState"] as? String, "playing")
        XCTAssertEqual(object["surfaceAttachCount"] as? Int, 0)
        XCTAssertNotNil(object["firstFrameLatencyMilliseconds"])
        XCTAssertNotNil(object["blackFrameDurationMilliseconds"])
        XCTAssertEqual(object["avPlayerItemIdentity"] as? String, "ObjectIdentifier(0x3)")
        XCTAssertEqual(object["surfaceIdentity"] as? String, "ObjectIdentifier(0x4)")
    }
}
