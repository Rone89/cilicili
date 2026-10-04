#if DEBUG
import MetalKit
import XCTest
@testable import bili

@MainActor
final class DanmakuRendererDiagnosticsTests: XCTestCase {
    func testSceneEventsAreBoundedAndResetBetweenCaptures() {
        let diagnostics = DanmakuRendererDiagnostics()
        diagnostics.recordMetalSceneEvent("ignored", time: 1, before: 1, after: 0)
        XCTAssertTrue(diagnostics.metalSummary.sceneEvents.isEmpty)
        diagnostics.start()
        for index in 0..<25 {
            diagnostics.recordMetalSceneEvent("event-\(index)", time: Double(index), before: 10, after: 0)
        }
        diagnostics.recordMetalSceneEvent("invalid", time: .nan, before: 10, after: 0)
        XCTAssertEqual(diagnostics.metalSummary.sceneEvents.count, 20)
        XCTAssertTrue(diagnostics.metalSummary.sceneEvents.first?.contains("reason=event-5 ") == true)
        XCTAssertTrue(diagnostics.makeReport().contains("reason=event-24 active=10→0"))
        diagnostics.stop()
        diagnostics.recordMetalSceneEvent("after-stop", time: 30, before: 10, after: 0)
        XCTAssertEqual(diagnostics.metalSummary.sceneEvents.count, 20)
        diagnostics.start()
        XCTAssertTrue(diagnostics.metalSummary.sceneEvents.isEmpty)
    }

    func testRenderFailuresAndEmptyGlyphFramesAreCaptureIsolated() {
        let diagnostics = DanmakuRendererDiagnostics()
        diagnostics.start()
        let oldID = diagnostics.captureID
        diagnostics.recordMetalRenderFailure("encoder-unavailable", captureID: oldID)
        XCTAssertEqual(diagnostics.metalSummary.renderFailures["encoder-unavailable"], 1)
        for load in [(0, 0), (10, 0), (10, 100)] {
            diagnostics.recordMetalFrame(active: load.0, glyphs: load.1, drawCalls: 0, pages: 1,
                usedPixels: 1, capacityPixels: 100, rejected: 0, skipped: 0,
                preparationMs: 0, timestamp: 0, expectedInterval: 0, requestedFPS: 60, displayMaximumFPS: 120)
        }
        XCTAssertEqual(diagnostics.metalSummary.emptyGlyphFrames, 1)
        diagnostics.stop()
        diagnostics.recordMetalRenderFailure("after-stop")
        XCTAssertNil(diagnostics.metalSummary.renderFailures["after-stop"])
        diagnostics.start()
        diagnostics.recordMetalRenderFailure("old-command-error", captureID: oldID)
        XCTAssertTrue(diagnostics.metalSummary.renderFailures.isEmpty)
        XCTAssertEqual(diagnostics.metalSummary.emptyGlyphFrames, 0)
        XCTAssertTrue(diagnostics.makeReport().contains("Metal render failures: none"))
    }

    func testStoppedDurationUsesMonotonicClockAndRemainsFrozen() {
        let diagnostics = DanmakuRendererDiagnostics()
        diagnostics.start(at: 100)
        XCTAssertEqual(diagnostics.captureDuration(at: 105), 5)
        diagnostics.stop(at: 110)
        diagnostics.stop(at: 120)
        XCTAssertEqual(diagnostics.captureDuration(at: 999), 10)
        diagnostics.start(at: 200)
        XCTAssertEqual(diagnostics.captureDuration(at: 202), 2)
    }

    func testCaptureIsolationAndDelayedCompletionsCannotPolluteNewCapture() {
        let kit = DanmakuRendererDiagnostics()
        let metal = DanmakuRendererDiagnostics()
        kit.start(at: 1)
        metal.start(at: 1)
        let oldID = metal.captureID
        kit.recordDanmakuKitCellDraw(identifier: "text", milliseconds: 2, captureID: kit.captureID)
        metal.recordMetalGPU(milliseconds: 3, captureID: oldID)
        XCTAssertEqual(kit.danmakuKitSummary.cellDrawCount, 1)
        XCTAssertEqual(metal.danmakuKitSummary.cellDrawCount, 0)
        XCTAssertEqual(kit.metalSummary.gpuSamples, 0)
        metal.stop(at: 2)
        metal.start(at: 3)
        metal.recordMetalGPU(milliseconds: 5, captureID: oldID)
        metal.recordDanmakuKitCellDraw(identifier: "old", milliseconds: 5, captureID: oldID)
        XCTAssertEqual(metal.metalSummary.gpuSamples, 0)
        XCTAssertEqual(metal.danmakuKitSummary.cellDrawCount, 0)
        metal.recordMetalGPU(milliseconds: 4, captureID: metal.captureID)
        XCTAssertEqual(metal.metalSummary.gpuAverageMs, 4)
    }

    func testTimingSamplesRejectInvalidValuesAndMissingIsNotZero() {
        var timing = DanmakuRendererDiagnostics.TimingSummary()
        XCTAssertNil(timing.average)
        XCTAssertEqual(timing.report, "-/- (n=0)")
        for value in [Double.nan, .infinity, -1] { timing.record(value) }
        XCTAssertEqual(timing.count, 0)
        timing.record(0)
        timing.record(4)
        XCTAssertEqual(timing.average, 2)
        XCTAssertEqual(timing.maximum, 4)
        XCTAssertEqual(timing.count, 2)
    }

    func testMetalStagesAndActualLoadHaveIndependentSamples() {
        let diagnostics = DanmakuRendererDiagnostics()
        diagnostics.start(at: 0)
        for index in 0..<2 {
            diagnostics.recordMetalFrame(active: 100 + index * 200, glyphs: 1000 + index * 2000,
                drawCalls: 1, pages: 1, usedPixels: 10, capacityPixels: 100,
                rejected: 0, skipped: 10 + index, preparationMs: 5, timestamp: Double(index) / 60,
                expectedInterval: 1.0 / 60, requestedFPS: 60, displayMaximumFPS: 120,
                scenePreparationMs: 1, drawableAcquisitionMs: 2, encodingMs: 1.5, commitMs: 0.5)
        }
        XCTAssertEqual(diagnostics.metalSummary.skippedFrames, 1)
        XCTAssertEqual(diagnostics.metalSummary.scenePreparation.average, 1)
        XCTAssertEqual(diagnostics.metalSummary.drawableAcquisition.average, 2)
        XCTAssertEqual(diagnostics.metalSummary.encoding.average, 1.5)
        XCTAssertEqual(diagnostics.metalSummary.commit.average, 0.5)
        XCTAssertEqual(diagnostics.metalSummary.activeLoad.minimum, 100)
        XCTAssertEqual(diagnostics.metalSummary.activeLoad.maximum, 300)
        XCTAssertEqual(diagnostics.metalSummary.activeLoad.total, 400)
        XCTAssertEqual(diagnostics.metalSummary.glyphLoad.maximum, 3000)
        XCTAssertEqual(diagnostics.metalSummary.drawCallLoad.maximum, 1)
        XCTAssertEqual(diagnostics.metalSummary.medianFPS ?? 0, 60, accuracy: 0.001)
    }

    func testManualRefreshHasSeparateTimingAndDoesNotPolluteAutomaticCadence() {
        let diagnostics = DanmakuRendererDiagnostics()
        diagnostics.start(at: 0)
        func record(at time: Double, manual: Bool, acquisition: Double) {
            diagnostics.recordMetalFrame(active: 10, glyphs: 100, drawCalls: 1, pages: 1,
                usedPixels: 10, capacityPixels: 100, rejected: 0, skipped: 0,
                preparationMs: acquisition, timestamp: time, expectedInterval: 1.0 / 60,
                requestedFPS: 60, displayMaximumFPS: 120, drawableAcquisitionMs: acquisition,
                isManualRefresh: manual)
        }
        record(at: 0, manual: false, acquisition: 2)
        record(at: 0.005, manual: true, acquisition: 8)
        record(at: 1, manual: false, acquisition: 4)
        record(at: 1 + 1.0 / 60, manual: false, acquisition: 3)
        XCTAssertEqual(diagnostics.metalSummary.automaticFrames, 3)
        XCTAssertEqual(diagnostics.metalSummary.manualRefreshFrames, 1)
        XCTAssertEqual(diagnostics.metalSummary.automaticDrawableAcquisition.average, 3)
        XCTAssertEqual(diagnostics.metalSummary.manualDrawableAcquisition.average, 8)
        XCTAssertEqual(diagnostics.metalSummary.intervals.count, 1)
        XCTAssertEqual(diagnostics.metalSummary.medianFPS ?? 0, 60, accuracy: 0.001)
        XCTAssertEqual(diagnostics.metalSummary.callbackGaps, 0)
        XCTAssertTrue(diagnostics.makeReport().contains("Metal frame source automatic/manual refresh: 3/1"))
        diagnostics.stop()
        diagnostics.start(at: 2)
        XCTAssertEqual(diagnostics.metalSummary.automaticFrames, 0)
        XCTAssertEqual(diagnostics.metalSummary.manualRefreshFrames, 0)
        XCTAssertNil(diagnostics.metalSummary.manualDrawableAcquisition.average)
    }

    func testBenchmarkMetadataAndKitFrameLoadsResetForEachCapture() {
        let diagnostics = DanmakuRendererDiagnostics()
        diagnostics.startBenchmark(.init(renderer: "DanmakuKit", density: 300, requestedFPS: 60,
            playbackRate: 1, viewport: CGSize(width: 390, height: 600)))
        diagnostics.recordDanmakuKitFrameLoad(100)
        diagnostics.recordDanmakuKitFrameLoad(300)
        XCTAssertEqual(diagnostics.kitLoad.total, 400)
        let report = diagnostics.makeReport()
        XCTAssertTrue(report.contains("DanmakuKit/300/60/1.0/390x600"))
        XCTAssertTrue(report.contains("callback Hz is not presented FPS"))
        XCTAssertTrue(report.contains("Metal scene preparation avg/max ms: -/-"))
        XCTAssertTrue(report.contains("loop media time 7s → 1s"))
        diagnostics.stop()
        diagnostics.start()
        XCTAssertNil(diagnostics.benchmarkConfiguration)
        XCTAssertEqual(diagnostics.kitLoad.samples, 0)
    }

    func testHostPropagatesLocalDiagnosticsAndRequestedRateAcrossRendererSwitch() throws {
        let diagnostics = DanmakuRendererDiagnostics()
        let host = DanmakuRendererHostView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        host.debugDiagnostics = diagnostics
        host.debugPreferredFramesPerSecond = 60
        defer { host.stop() }
        host.selectRenderer(metalEnabled: false)
        let kit = try XCTUnwrap(host.subviews.first as? DanmakuKitOverlayView)
        XCTAssertTrue(kit.debugDiagnostics === diagnostics)
        XCTAssertEqual(kit.debugPreferredFramesPerSecond, 60)
        XCTAssertEqual(diagnostics.rendererType, "DanmakuKit")
        host.selectRenderer(metalEnabled: true)
        guard host.usesMetal else { throw XCTSkip("Metal unavailable") }
        let metal = try XCTUnwrap(host.subviews.first as? MetalDanmakuView)
        XCTAssertTrue(metal.debugDiagnostics === diagnostics)
        XCTAssertTrue(metal.debugRenderer.debugDiagnostics === diagnostics)
        XCTAssertEqual(metal.debugPreferredFramesPerSecond, 60)
        XCTAssertLessThanOrEqual(metal.metalView.preferredFramesPerSecond, 60)
        XCTAssertGreaterThanOrEqual(metal.metalView.preferredFramesPerSecond, 30)
        XCTAssertEqual(diagnostics.rendererType, "Metal")
        XCTAssertEqual(host.subviews.count, 1)
    }
}
#endif
