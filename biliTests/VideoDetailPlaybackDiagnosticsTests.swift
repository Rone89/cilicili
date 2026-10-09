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
        diagnostics.markRotationFinished(toLandscape: true, actualOrientation: "landscapeRight")

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
        diagnostics.markRotationFinished(toLandscape: true, actualOrientation: "landscapeRight")

        let record = try XCTUnwrap(diagnostics.completedRotationRecords.last)
        XCTAssertEqual(record.playbackState, "paused")
        XCTAssertFalse(record.isBuffering)
        viewModel.stop()
    }

    func testRotationRecordSeparatesSystemAndLayoutMilestones() throws {
        let diagnostics = VideoDetailPlaybackDiagnostics()
        diagnostics.begin(metricsID: "rotation-milestones", title: "Rotation")
        let surface = NSObject()
        diagnostics.markRotationStarted(toLandscape: true)
        diagnostics.recordLayoutEventForTesting(
            .surfaceGeometry(surfaceID: ObjectIdentifier(surface))
        )
        diagnostics.recordLayoutEventForTesting(.overlayGeometry)
        diagnostics.recordLayoutEventForTesting(.danmakuCanvasConfigured)
        diagnostics.markSystemTransitionEnded()
        diagnostics.markRotationFinished(toLandscape: true, actualOrientation: "landscapeLeft")

        let record = try XCTUnwrap(diagnostics.completedRotationRecords.last)
        XCTAssertEqual(record.sequence, 1)
        XCTAssertEqual(record.actualOrientation, "landscapeLeft")
        XCTAssertNotNil(record.durationMilliseconds)
        XCTAssertNotNil(record.systemTransitionDurationMilliseconds)
        XCTAssertNotNil(record.firstCorrectSurfaceGeometryMilliseconds)
        XCTAssertNotNil(record.firstOverlayGeometryMilliseconds)
        XCTAssertNotNil(record.danmakuCanvasConfiguredMilliseconds)
        XCTAssertEqual(record.surfaceIdentityChangeCount, 0)
    }

    func testRotationRecordCountsIdentityChangesDuringRotation() throws {
        let diagnostics = VideoDetailPlaybackDiagnostics()
        diagnostics.begin(metricsID: "rotation-identities", title: "Rotation")
        let firstSurface = NSObject()
        let secondSurface = NSObject()
        let firstPlayer = NSObject()
        let secondPlayer = NSObject()
        let firstItem = NSObject()
        let secondItem = NSObject()

        diagnostics.markRotationStarted(toLandscape: true)
        diagnostics.recordSurfaceEventForTesting(
            .attached(
                surfaceID: ObjectIdentifier(firstSurface),
                playerID: ObjectIdentifier(firstPlayer),
                playerItemID: ObjectIdentifier(firstItem)
            )
        )
        diagnostics.recordSurfaceEventForTesting(
            .attached(
                surfaceID: ObjectIdentifier(secondSurface),
                playerID: ObjectIdentifier(secondPlayer),
                playerItemID: ObjectIdentifier(secondItem)
            )
        )
        diagnostics.markRotationFinished(toLandscape: true, actualOrientation: "landscapeRight")

        let record = try XCTUnwrap(diagnostics.completedRotationRecords.last)
        XCTAssertEqual(record.playerIdentityChangeCount, 1)
        XCTAssertEqual(record.playerItemIdentityChangeCount, 1)
        XCTAssertEqual(record.surfaceIdentityChangeCount, 1)
        XCTAssertEqual(record.surfaceAttachCount, 2)
    }

    func testRotationRecordJSONContainsStructuredPlaybackFields() throws {
        var record = VideoDetailRotationDiagnosticRecord(
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
        record.sequence = 4
        record.systemTransitionDurationMilliseconds = 280
        record.blackFrameMeasurementStatus = "unavailableFrameUsableAtStart"
        record.firstCorrectSurfaceGeometryMilliseconds = 44
        record.firstOverlayGeometryMilliseconds = 61
        record.danmakuCanvasConfiguredMilliseconds = 59
        record.actualOrientation = "portrait"

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
        XCTAssertEqual(object["sequence"] as? Int, 4)
        XCTAssertEqual(object["actualOrientation"] as? String, "portrait")
        XCTAssertEqual(object["blackFrameMeasurementStatus"] as? String, "unavailableFrameUsableAtStart")
        XCTAssertNotNil(object["systemTransitionDurationMilliseconds"])
        XCTAssertNotNil(object["firstCorrectSurfaceGeometryMilliseconds"])
        XCTAssertNotNil(object["firstOverlayGeometryMilliseconds"])
        XCTAssertNotNil(object["danmakuCanvasConfiguredMilliseconds"])
    }
}
