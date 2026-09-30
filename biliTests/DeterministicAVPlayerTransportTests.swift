import AVFoundation
import AudioToolbox
import CoreMedia
import CoreVideo
import Network
import UniformTypeIdentifiers
import XCTest
@testable import bili

final class DeterministicAVPlayerTransportTests: XCTestCase {
    @MainActor
    func testGeneratedAudioVideoFixtureDoesNotContactNetwork() async throws {
        let fixture = try await DeterministicDASHPlaybackFixture.make()
        defer { fixture.server.stop() }
        let requests = await fixture.server.requestSnapshot()
        XCTAssertTrue(requests.isEmpty)
    }

    @MainActor
    func testGeneratedDASHSourcePlaysThroughLocalHLSBridge() async {
        do {
            let fixture = try await DeterministicDASHPlaybackFixture.make()
            defer { fixture.server.stop() }
            let source = fixture.primarySource
            let engine = AVPlayerHLSBridgeEngine()
            let surfaceHost = PlaybackTestSurfaceHost()
            defer {
                engine.stop()
                surfaceHost.close()
            }
            engine.attachSurface(surfaceHost.surface)
            var didBecomeReady = false
            var didRenderFrame = false
            engine.onPlaybackStateChange = { state in
                if case .ready = state {
                    didBecomeReady = true
                }
            }
            engine.onFirstFrame = { _ in didRenderFrame = true }

            await LocalHLSBridge.clearWarmupCache(for: fixture.mediaURLStrings)
            try await engine.prepare(source: source)
            try await waitUntil("AVPlayer item becomes ready") { didBecomeReady }

            let item = try XCTUnwrap(engine.debugCurrentPlayerItem)
            let urlAsset = try XCTUnwrap(item.asset as? AVURLAsset)
            let tracks = try await item.asset.load(.tracks)
            let assetTrackTypes = tracks.map { $0.mediaType.rawValue }
            let itemTrackTypes = item.tracks.compactMap { $0.assetTrack?.mediaType.rawValue }
            XCTAssertTrue(
                assetTrackTypes.contains(AVMediaType.video.rawValue) || itemTrackTypes.contains(AVMediaType.video.rawValue),
                "No video track; asset=\(assetTrackTypes), item=\(itemTrackTypes)"
            )
            XCTAssertTrue(
                assetTrackTypes.contains(AVMediaType.audio.rawValue) || itemTrackTypes.contains(AVMediaType.audio.rawValue),
                "No audio track; asset=\(assetTrackTypes), item=\(itemTrackTypes)"
            )
            XCTAssertEqual(urlAsset.url.scheme, "http")
            XCTAssertNil(urlAsset.resourceLoader.delegate)
            XCTAssertTrue(engine.debugHasLocalBridgeSession)

            engine.play()
            try await waitUntil("AVPlayer renders a video frame", timeout: 12) { didRenderFrame }
            let initialTime = try XCTUnwrap(engine.snapshot(durationHint: source.durationHint).currentTime)
            XCTAssertGreaterThanOrEqual(initialTime, 0)

            try await verifyPauseResume(on: engine, duration: source.durationHint ?? 8)
            try await verifySeeking(on: engine, duration: source.durationHint ?? 8)

            let requestCounts = try XCTUnwrap(engine.debugLocalBridgeRequestCounts)
            XCTAssertGreaterThan(requestCounts.total, 3)
            XCTAssertEqual(requestCounts.manifests, 3)
            XCTAssertGreaterThan(requestCounts.total - requestCounts.manifests, 0)

            let recorded = await fixture.server.requestSnapshot()
            XCTAssertTrue(recorded.contains { $0.path == "/video.m4s" && $0.rangeHeader != nil })
            XCTAssertTrue(recorded.contains { $0.path == "/audio.m4s" && $0.rangeHeader != nil })
            let videoRanges = recorded.filter { $0.path == "/video.m4s" && $0.rangeHeader != nil }.count
            let audioRanges = recorded.filter { $0.path == "/audio.m4s" && $0.rangeHeader != nil }.count
            let report = [
                "Localhost manifest requests: \(requestCounts.manifests)",
                "Localhost media requests: \(requestCounts.total - requestCounts.manifests)",
                "Fixture upstream Range requests: video=\(videoRanges) audio=\(audioRanges)"
            ].joined(separator: "\n")
            let attachment = XCTAttachment(string: report)
            attachment.name = "Deterministic localhost bridge request counts"
            attachment.lifetime = .keepAlways
            add(attachment)

            let previousItemIdentity = engine.debugPlayerItemIdentity
            let oldPlaylistURL = try XCTUnwrap(URL(string: try XCTUnwrap(engine.diagnostics.localPlaylistURL)))
            engine.stop()
            XCTAssertNil(urlAsset.resourceLoader.delegate)
            XCTAssertNil(engine.debugPlayerItemIdentity)
            XCTAssertFalse(engine.debugHasLocalBridgeSession)
            XCTAssertNotNil(previousItemIdentity)
            await LocalHLSBridge.clearWarmupCache(for: fixture.mediaURLStrings)
            try await assertBridgeWasStopped(at: oldPlaylistURL)
        } catch {
            XCTFail("Deterministic playback scenario failed: \(error)")
        }
    }

    @MainActor
    func testRepeatedCreatePlayStopReleasesBridgeSession() async {
        do {
            let fixture = try await DeterministicDASHPlaybackFixture.make()
            defer { fixture.server.stop() }

            for iteration in 0..<10 {
                let source = fixture.primarySource
                let engine = AVPlayerHLSBridgeEngine()
                let surfaceHost = PlaybackTestSurfaceHost()
                defer {
                    engine.stop()
                    surfaceHost.close()
                }
                engine.attachSurface(surfaceHost.surface)
                var didBecomeReady = false
                var didRenderFrame = false
                engine.onPlaybackStateChange = { state in
                    if case .ready = state { didBecomeReady = true }
                }
                engine.onFirstFrame = { _ in didRenderFrame = true }

                await LocalHLSBridge.clearWarmupCache(for: fixture.mediaURLStrings)
                try await engine.prepare(source: source)
                try await waitUntil("iteration \(iteration) item ready") { didBecomeReady }
                let asset = try XCTUnwrap(engine.debugCurrentPlayerItem?.asset as? AVURLAsset)
                XCTAssertEqual(asset.url.scheme, "http")
                XCTAssertNil(asset.resourceLoader.delegate)
                engine.play()
                try await waitUntil("iteration \(iteration) renders a frame", timeout: 12) { didRenderFrame }
                let oldPlaylistURL = try XCTUnwrap(URL(string: try XCTUnwrap(engine.diagnostics.localPlaylistURL)))

                engine.stop()
                XCTAssertNil(asset.resourceLoader.delegate, "iteration \(iteration)")
                XCTAssertNil(engine.debugPlayerItemIdentity, "iteration \(iteration)")
                XCTAssertFalse(engine.debugHasLocalBridgeSession, "iteration \(iteration)")
                await LocalHLSBridge.clearWarmupCache(for: fixture.mediaURLStrings)
                try await assertBridgeWasStopped(at: oldPlaylistURL)
            }
        } catch {
            XCTFail("Repeated teardown scenario failed: \(error)")
        }
    }

    @MainActor
    func testPlaybackRatesRemainEffectiveAfterSeek() async {
        do {
            let fixture = try await DeterministicDASHPlaybackFixture.make()
            defer { fixture.server.stop() }

            let source = fixture.primarySource
            let engine = AVPlayerHLSBridgeEngine()
            let surfaceHost = PlaybackTestSurfaceHost()
            defer {
                engine.stop()
                surfaceHost.close()
            }
            engine.attachSurface(surfaceHost.surface)

            var didRenderFrame = false
            engine.onFirstFrame = { _ in didRenderFrame = true }
            await LocalHLSBridge.clearWarmupCache(for: fixture.mediaURLStrings)
            try await engine.prepare(source: source)
            engine.play()
            try await waitUntil("rate test first frame", timeout: 12) { didRenderFrame }

            for rate: Double in [1.0, 1.5, 2.0] {
                let seekTarget = 0.5
                XCTAssertEqual(engine.seek(toTime: seekTarget), seekTarget)
                try await waitUntil("seek before \(rate)x") {
                    guard let current = engine.snapshot(durationHint: source.durationHint).currentTime else { return false }
                    return abs(current - seekTarget) < 0.6
                }
                engine.pause()
                engine.setPlaybackRate(rate)
                XCTAssertEqual(engine.debugPlaybackRate, Float(rate), accuracy: 0.001)
                engine.play()
                try await waitUntil("AVPlayer applies \(rate)x") {
                    abs(engine.debugActualPlayerRate - Float(rate)) < 0.001
                }
                let startTime = try XCTUnwrap(engine.snapshot(durationHint: source.durationHint).currentTime)
                let startedAt = ContinuousClock.now
                try await Task.sleep(for: .milliseconds(800))
                let elapsed = seconds(since: startedAt)
                engine.pause()
                let endTime = try XCTUnwrap(engine.snapshot(durationHint: source.durationHint).currentTime)
                let mediaProgress = endTime - startTime
                XCTAssertEqual(
                    mediaProgress / elapsed,
                    rate,
                    accuracy: 0.55,
                    "Expected AVPlayer media time to advance at \(rate)x; measured \(mediaProgress)s in \(elapsed)s"
                )

                let restoreTarget = 1.25
                XCTAssertEqual(engine.seek(toTime: restoreTarget), restoreTarget)
                try await waitUntil("seek preserves \(rate)x") {
                    guard let current = engine.snapshot(durationHint: source.durationHint).currentTime else { return false }
                    return abs(current - restoreTarget) < 0.6
                }
                engine.play()
                try await waitUntil("AVPlayer retains \(rate)x after seek") {
                    abs(engine.debugActualPlayerRate - Float(rate)) < 0.001
                }
                let afterSeekStart = try XCTUnwrap(engine.snapshot(durationHint: source.durationHint).currentTime)
                try await Task.sleep(for: .milliseconds(250))
                engine.pause()
                let afterSeekEnd = try XCTUnwrap(engine.snapshot(durationHint: source.durationHint).currentTime)
                XCTAssertGreaterThan(afterSeekEnd - afterSeekStart, rate * 0.08)
                XCTAssertEqual(engine.debugPlaybackRate, Float(rate), accuracy: 0.001)
            }
        } catch {
            XCTFail("Playback rate scenario failed: \(error)")
        }
    }

    @MainActor
    private func verifyPauseResume(
        on engine: AVPlayerHLSBridgeEngine,
        duration: TimeInterval
    ) async throws {
        try await Task.sleep(for: .milliseconds(500))
        engine.pause()
        let pausedAt = try XCTUnwrap(engine.snapshot(durationHint: duration).currentTime)
        try await Task.sleep(for: .milliseconds(350))
        let afterPause = try XCTUnwrap(engine.snapshot(durationHint: duration).currentTime)
        XCTAssertLessThanOrEqual(abs(afterPause - pausedAt), 0.12)

        engine.play()
        try await waitUntil("playback resumes") {
            guard let current = engine.snapshot(durationHint: duration).currentTime else { return false }
            return current > afterPause + 0.25
        }
    }

    @MainActor
    private func verifySeeking(
        on engine: AVPlayerHLSBridgeEngine,
        duration: TimeInterval
    ) async throws {
        let forwardTarget = duration * 0.72
        XCTAssertEqual(engine.seek(toTime: forwardTarget), forwardTarget)
        try await waitUntil("forward seek completes") {
            guard let current = engine.snapshot(durationHint: duration).currentTime else { return false }
            return abs(current - forwardTarget) < 0.6
        }

        let backwardTarget = duration * 0.22
        XCTAssertEqual(engine.seek(toTime: backwardTarget), backwardTarget)
        try await waitUntil("backward seek completes") {
            guard let current = engine.snapshot(durationHint: duration).currentTime else { return false }
            return abs(current - backwardTarget) < 0.6
        }

        for fraction in [0.10, 0.70, 0.25, 0.85, 0.40] {
            _ = engine.seek(toTime: duration * fraction)
        }
        let finalTarget = duration * 0.40
        try await waitUntil("rapid seek settles at its final target") {
            guard let current = engine.snapshot(durationHint: duration).currentTime else { return false }
            return abs(current - finalTarget) < 0.65
        }
        try await waitUntil("video output resumes after seek") {
            guard let renderedTime = engine.currentRenderedVideoTime() else { return false }
            return abs(renderedTime - finalTarget) < 0.9
        }
    }

    @MainActor
    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 8,
        condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(timeout)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                XCTFail("Timed out waiting for \(description)")
                throw PlaybackFixtureError.timedOut(description)
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private func seconds(since instant: ContinuousClock.Instant) -> Double {
        let components = instant.duration(to: .now).components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }

    private func assertBridgeWasStopped(at playlistURL: URL) async throws {
        var request = URLRequest(url: playlistURL, timeoutInterval: 2)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            _ = try await URLSession.shared.data(for: request)
            XCTFail("The bridge server still answered after engine teardown")
        } catch {
            // A refused loopback connection is the expected teardown result.
        }
    }
}

@MainActor
private final class PlaybackTestSurfaceHost {
    private let window: UIWindow
    let surface: UIView

    init() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { fatalError("Playback integration tests require an active UIWindowScene.") }
        window = UIWindow(windowScene: scene)
        let root = UIViewController()
        root.view.backgroundColor = .black
        window.rootViewController = root
        window.windowLevel = .normal + 1
        window.isHidden = false
        surface = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        surface.backgroundColor = .black
        root.view.addSubview(surface)
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
    }
}

private enum PlaybackFixtureError: LocalizedError {
    case failedToStartWriter
    case failedToCreateSampleBuffer
    case failedToCreatePixelBuffer
    case invalidFragmentedMovie
    case timedOut(String)
    case writer(String)

    var errorDescription: String? {
        switch self {
        case .failedToStartWriter: "AVAssetWriter could not start the fixture writer."
        case .failedToCreateSampleBuffer: "Could not create the fixture audio sample buffer."
        case .failedToCreatePixelBuffer: "Could not create a fixture video pixel buffer."
        case .invalidFragmentedMovie: "AVAssetWriter did not produce a usable fragmented MP4."
        case .timedOut(let description): "Timed out waiting for \(description)."
        case .writer(let message): "Fixture writer failed: \(message)"
        }
    }
}

private struct DeterministicDASHPlaybackFixture {
    let server: DeterministicRangeFixtureServer
    let primarySource: PlayerStreamSource
    let mediaURLStrings: Set<String>

    @MainActor
    static func make() async throws -> DeterministicDASHPlaybackFixture {
        let video = try await makeFragmentedTrack(mediaType: .video)
        let audio = try await makeFragmentedTrack(mediaType: .audio)
        let server = try DeterministicRangeFixtureServer(
            mediaByPath: ["/video.m4s": video.data, "/audio.m4s": audio.data]
        )
        try await server.start()

        let videoURL = server.url(path: "/video.m4s")
        let audioURL = server.url(path: "/audio.m4s")
        let videoStream = try decodeStream(
            url: videoURL,
            id: 80,
            bandwidth: 220_000,
            codecs: "avc1.64001F",
            codecid: 7,
            width: 160,
            height: 90,
            segmentBase: video.segmentBase
        )
        let audioStream = try decodeStream(
            url: audioURL,
            id: 30280,
            bandwidth: 64_000,
            codecs: "mp4a.40.2",
            codecid: nil,
            width: nil,
            height: nil,
            segmentBase: audio.segmentBase
        )
        let source = PlayerStreamSource(
            metricsID: "deterministic-playback-fixture",
            videoURL: videoURL,
            audioURL: audioURL,
            videoStream: videoStream,
            audioStream: audioStream,
            alternateVideoRenditions: [],
            referer: "https://www.bilibili.com",
            httpHeaders: [
                "User-Agent": "CiliCili-Deterministic-Playback-Test",
                "Referer": "https://www.bilibili.com"
            ],
            title: "Generated playback fixture",
            durationHint: 8,
            isLiveStream: false,
            isLiveHLS: false,
            liveHLSFormat: nil,
            resumeTime: 0,
            dynamicRange: .sdr,
            cdnPreference: .automatic
        )
        return DeterministicDASHPlaybackFixture(
            server: server,
            primarySource: source,
            mediaURLStrings: [videoURL.absoluteString, audioURL.absoluteString]
        )
    }

    private static func decodeStream(
        url: URL,
        id: Int,
        bandwidth: Int,
        codecs: String,
        codecid: Int?,
        width: Int?,
        height: Int?,
        segmentBase: FixtureSegmentBase
    ) throws -> DASHStream {
        var fields = [
            "\"id\":\(id)",
            "\"baseUrl\":\"\(url.absoluteString)\"",
            "\"bandwidth\":\(bandwidth)",
            "\"codecs\":\"\(codecs)\"",
            "\"mimeType\":\"\(codecs.hasPrefix("avc") ? "video" : "audio")/mp4\"",
            "\"SegmentBase\":{\"Initialization\":\"\(segmentBase.initialization)\",\"indexRange\":\"\(segmentBase.index)\"}"
        ]
        if let codecid { fields.append("\"codecid\":\(codecid)") }
        if let width { fields.append("\"width\":\(width)") }
        if let height { fields.append("\"height\":\(height)") }
        if width != nil, height != nil { fields.append("\"frameRate\":\"12\"") }
        let json = "{\(fields.joined(separator: ","))}"
        return try JSONDecoder().decode(DASHStream.self, from: Data(json.utf8))
    }

    @MainActor
    private static func makeFragmentedTrack(mediaType: FixtureMediaType) async throws -> FixtureFragmentedTrack {
        let writer = AVAssetWriter(contentType: .mpeg4Movie)
        let collector = FixtureSegmentCollector()
        writer.delegate = collector
        writer.outputFileTypeProfile = .mpeg4AppleHLS
        writer.preferredOutputSegmentInterval = CMTime(seconds: 8, preferredTimescale: 600)
        writer.initialSegmentStartTime = .zero

        switch mediaType {
        case .video:
            try await writeVideo(into: writer)
        case .audio:
            try await writeAudio(into: writer)
        }
        try await finish(writer)

        let (initialization, media) = try collector.segments()
        _ = try topLevelBoxes(in: initialization)
        do {
            _ = try topLevelBoxes(in: media)
        } catch {
            throw PlaybackFixtureError.writer(
                "invalid \(mediaType) media segment bytes=\(media.count) error=\(error)"
            )
        }
        let movie = initialization + media
        guard movie.count < 1_000_000 else { throw PlaybackFixtureError.invalidFragmentedMovie }
        return try FixtureFragmentedTrack(data: insertingSIDX(into: movie, duration: 8))
    }

    @MainActor
    private static func writeVideo(into writer: AVAssetWriter) async throws {
        let width = 160
        let height = 90
        let frameRate = 12
        let frameCount = 8 * frameRate
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoExpectedSourceFrameRateKey: frameRate,
                AVVideoMaxKeyFrameIntervalKey: frameRate,
                AVVideoAverageBitRateKey: 220_000
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.mediaTimeScale = 600
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )
        guard writer.canAdd(input) else { throw PlaybackFixtureError.failedToStartWriter }
        writer.add(input)
        guard writer.startWriting() else {
            throw PlaybackFixtureError.writer(writer.error?.localizedDescription ?? "start failed")
        }
        writer.startSession(atSourceTime: .zero)

        for frameIndex in 0..<frameCount {
            try await waitUntilReady(input, writer: writer, mediaType: "video")
            var pixelBuffer: CVPixelBuffer?
            let result = CVPixelBufferCreate(
                kCFAllocatorDefault,
                width,
                height,
                kCVPixelFormatType_32BGRA,
                [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary,
                &pixelBuffer
            )
            guard result == kCVReturnSuccess, let pixelBuffer else {
                throw PlaybackFixtureError.failedToCreatePixelBuffer
            }
            Self.fill(pixelBuffer, frameIndex: frameIndex)
            let time = CMTime(value: Int64(frameIndex), timescale: Int32(frameRate))
            guard adaptor.append(pixelBuffer, withPresentationTime: time) else {
                throw PlaybackFixtureError.writer(writer.error?.localizedDescription ?? "video append failed")
            }
        }
        input.markAsFinished()
    }

    @MainActor
    private static func writeAudio(into writer: AVAssetWriter) async throws {
        let sampleRate = 48_000
        let totalFrames = sampleRate * 8
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000
            ]
        )
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw PlaybackFixtureError.failedToStartWriter }
        writer.add(input)
        guard writer.startWriting() else {
            throw PlaybackFixtureError.writer(writer.error?.localizedDescription ?? "start failed")
        }
        writer.startSession(atSourceTime: .zero)

        var asbd = AudioStreamBasicDescription(
            mSampleRate: Double(sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var formatDescription: CMAudioFormatDescription?
        let formatStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else {
            throw PlaybackFixtureError.failedToCreateSampleBuffer
        }

        var frameOffset = 0
        while frameOffset < totalFrames {
            try await waitUntilReady(input, writer: writer, mediaType: "audio")
            let count = min(1_024, totalFrames - frameOffset)
            let sample = try Self.audioSampleBuffer(
                frameOffset: frameOffset,
                frameCount: count,
                sampleRate: sampleRate,
                formatDescription: formatDescription
            )
            guard input.append(sample) else {
                throw PlaybackFixtureError.writer(writer.error?.localizedDescription ?? "audio append failed")
            }
            frameOffset += count
        }
        input.markAsFinished()
    }

    @MainActor
    private static func waitUntilReady(
        _ input: AVAssetWriterInput,
        writer: AVAssetWriter,
        mediaType: String
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !input.isReadyForMoreMediaData {
            guard writer.status == .writing else {
                throw PlaybackFixtureError.writer(
                    "\(mediaType) input not ready; writer status=\(writer.status.rawValue), error=\(writer.error?.localizedDescription ?? "none")"
                )
            }
            guard ContinuousClock.now < deadline else {
                throw PlaybackFixtureError.writer(
                    "timed out waiting for \(mediaType) input; writer error=\(writer.error?.localizedDescription ?? "none")"
                )
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @MainActor
    private static func finish(_ writer: AVAssetWriter) async throws {
        writer.finishWriting {}
        let deadline = ContinuousClock.now + .seconds(10)
        while writer.status == .writing {
            guard ContinuousClock.now < deadline else {
                throw PlaybackFixtureError.writer(
                    "timed out finalizing writer; error=\(writer.error?.localizedDescription ?? "none")"
                )
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        guard writer.status == .completed else {
            throw PlaybackFixtureError.writer(writer.error?.localizedDescription ?? "finish failed")
        }
    }

    private static func fill(_ pixelBuffer: CVPixelBuffer, frameIndex: Int) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let pixels = baseAddress.assumingMemoryBound(to: UInt8.self)
        let blue = UInt8((frameIndex * 19) % 255)
        let red = 255 &- blue
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * rowBytes + x * 4
                pixels[offset] = blue
                pixels[offset + 1] = UInt8((x * 255) / max(width, 1))
                pixels[offset + 2] = red
                pixels[offset + 3] = 255
            }
        }
    }

    private static func audioSampleBuffer(
        frameOffset: Int,
        frameCount: Int,
        sampleRate: Int,
        formatDescription: CMAudioFormatDescription
    ) throws -> CMSampleBuffer {
        var pcm = Data(capacity: frameCount * MemoryLayout<Int16>.size)
        for index in 0..<frameCount {
            let time = Double(frameOffset + index) / Double(sampleRate)
            let value = Int16(sin(2 * Double.pi * 440 * time) * 4_000).littleEndian
            withUnsafeBytes(of: value) { pcm.append(contentsOf: $0) }
        }

        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: pcm.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: pcm.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard blockStatus == kCMBlockBufferNoErr, let blockBuffer else {
            throw PlaybackFixtureError.failedToCreateSampleBuffer
        }
        let copyStatus = pcm.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(
                with: bytes.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: pcm.count
            )
        }
        guard copyStatus == kCMBlockBufferNoErr else {
            throw PlaybackFixtureError.failedToCreateSampleBuffer
        }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: Int32(sampleRate)),
            presentationTimeStamp: CMTime(value: Int64(frameOffset), timescale: Int32(sampleRate)),
            decodeTimeStamp: .invalid
        )
        var sampleSize = MemoryLayout<Int16>.size
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: frameCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else {
            throw PlaybackFixtureError.failedToCreateSampleBuffer
        }
        return sampleBuffer
    }

    private static func insertingSIDX(into movie: Data, duration: TimeInterval) throws -> Data {
        let boxes = try topLevelBoxes(in: movie)
        guard let firstFragment = boxes.first(where: { $0.type == "moof" }),
              boxes.contains(where: { $0.type == "ftyp" }),
              boxes.contains(where: { $0.type == "moov" })
        else {
            throw PlaybackFixtureError.writer("unexpected AVAssetWriter boxes: \(boxes.map(\.type))")
        }
        let mediaOffset = firstFragment.offset
        let mediaLength = movie.count - mediaOffset
        guard mediaLength > 0, mediaLength < 0x7fff_ffff else {
            throw PlaybackFixtureError.writer("unexpected fixture media range length \(mediaLength)")
        }
        let index = makeSIDX(mediaLength: mediaLength, durationMilliseconds: UInt32((duration * 1_000).rounded()))
        var data = Data()
        data.append(movie.prefix(mediaOffset))
        data.append(index)
        data.append(movie.dropFirst(mediaOffset))
        return data
    }

    private static func makeSIDX(mediaLength: Int, durationMilliseconds: UInt32) -> Data {
        var payload = Data()
        payload.appendBigEndian(UInt32(1)) // reference_ID
        payload.appendBigEndian(UInt32(1_000)) // timescale
        payload.appendBigEndian(UInt32(0)) // earliest_presentation_time
        payload.appendBigEndian(UInt32(0)) // first_offset
        payload.appendBigEndian(UInt16(0)) // reserved
        payload.appendBigEndian(UInt16(1)) // reference_count
        payload.appendBigEndian(UInt32(mediaLength)) // reference_type=0, referenced_size
        payload.appendBigEndian(durationMilliseconds)
        payload.appendBigEndian(UInt32(0x9000_0000)) // starts with SAP type 1

        var box = Data()
        box.appendBigEndian(UInt32(payload.count + 12)) // box header + full-box header + payload
        box.append(contentsOf: "sidx".utf8)
        box.append(contentsOf: [0, 0, 0, 0]) // version and flags
        box.append(payload)
        return box
    }

    private static func topLevelBoxes(in data: Data) throws -> [FixtureMP4Box] {
        var boxes: [FixtureMP4Box] = []
        var offset = 0
        while offset + 8 <= data.count {
            let size32 = Int(data.readBigEndianUInt32(at: offset))
            let type = String(data: data[(offset + 4)..<(offset + 8)], encoding: .ascii) ?? ""
            let size: Int
            if size32 == 1 {
                guard offset + 16 <= data.count else { throw PlaybackFixtureError.writer("truncated extended MP4 box at \(offset)") }
                let extended = data.readBigEndianUInt64(at: offset + 8)
                guard let exact = Int(exactly: extended) else { throw PlaybackFixtureError.writer("oversized MP4 box at \(offset)") }
                size = exact
            } else if size32 == 0 {
                size = data.count - offset
            } else {
                size = size32
            }
            guard size >= 8, offset + size <= data.count else {
                throw PlaybackFixtureError.writer("invalid MP4 box type=\(type) size=\(size) offset=\(offset) length=\(data.count)")
            }
            boxes.append(FixtureMP4Box(type: type, offset: offset, size: size))
            offset += size
        }
        guard offset == data.count else { throw PlaybackFixtureError.writer("unparsed MP4 tail at \(offset) of \(data.count)") }
        return boxes
    }
}

private enum FixtureMediaType {
    case video
    case audio
}

private final class FixtureSegmentCollector: NSObject, AVAssetWriterDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var initialization = Data()
    private var media = Data()

    func assetWriter(
        _ writer: AVAssetWriter,
        didOutputSegmentData segmentData: Data,
        segmentType: AVAssetSegmentType
    ) {
        lock.lock()
        defer { lock.unlock() }
        switch segmentType {
        case .initialization:
            initialization = Data(segmentData)
        case .separable:
            media.append(segmentData)
        @unknown default:
            break
        }
    }

    func segments() throws -> (initialization: Data, media: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard !initialization.isEmpty, !media.isEmpty else {
            throw PlaybackFixtureError.writer(
                "AVAssetWriter emitted initialization=\(initialization.count) media=\(media.count) bytes"
            )
        }
        return (Data(initialization), Data(media))
    }
}

private struct FixtureFragmentedTrack {
    let data: Data
    let segmentBase: FixtureSegmentBase

    init(data: Data) throws {
        let boxes = try DeterministicDASHPlaybackFixture.topLevelBoxesForFixture(data)
        guard let indexBox = boxes.first(where: { $0.type == "sidx" }),
              indexBox.offset + indexBox.size <= data.count,
              indexBox.offset > 0
        else { throw PlaybackFixtureError.writer("inserted SIDX not found in fixture boxes \(boxes.map(\.type))") }
        self.data = data
        segmentBase = FixtureSegmentBase(
            initialization: "0-\(indexBox.offset - 1)",
            index: "\(indexBox.offset)-\(indexBox.offset + indexBox.size - 1)"
        )
    }
}

private struct FixtureSegmentBase {
    let initialization: String
    let index: String
}

private struct FixtureMP4Box {
    let type: String
    let offset: Int
    let size: Int
}

private extension Data {
    mutating func appendBigEndian(_ value: UInt16) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }

    mutating func appendBigEndian(_ value: UInt32) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }

    func readBigEndianUInt32(at offset: Int) -> UInt32 {
        (UInt32(self[offset]) << 24)
            | (UInt32(self[offset + 1]) << 16)
            | (UInt32(self[offset + 2]) << 8)
            | UInt32(self[offset + 3])
    }

    func readBigEndianUInt64(at offset: Int) -> UInt64 {
        (UInt64(readBigEndianUInt32(at: offset)) << 32)
            | UInt64(readBigEndianUInt32(at: offset + 4))
    }
}

private extension DeterministicDASHPlaybackFixture {
    static func topLevelBoxesForFixture(_ data: Data) throws -> [FixtureMP4Box] {
        try topLevelBoxes(in: data)
    }
}

private final class DeterministicRangeFixtureServer: @unchecked Sendable {
    struct Request: Sendable {
        let path: String
        let rangeHeader: String?
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "cc.bili.tests.deterministic-range-fixture")
    private let mediaByPath: [String: Data]
    private var connections: [NWConnection] = []
    private var requests: [Request] = []
    private var baseURL: URL?

    init(mediaByPath: [String: Data]) throws {
        self.mediaByPath = mediaByPath
        listener = try NWListener(using: .tcp, on: .any)
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = FixtureContinuationGate()
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard gate.claim() else { return }
                    guard let self,
                          let port = self.listener.port,
                          let url = URL(string: "http://127.0.0.1:\(port.rawValue)")
                    else {
                        continuation.resume(throwing: PlaybackFixtureError.writer("fixture listener did not expose a port"))
                        return
                    }
                    self.baseURL = url
                    continuation.resume()
                case .failed(let error):
                    guard gate.claim() else { return }
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
        }
    }

    func url(path: String) -> URL {
        queue.sync {
            guard let baseURL else { preconditionFailure("Fixture server has not started.") }
            return baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        }
    }

    func requestSnapshot() async -> [Request] {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.requests) }
        }
    }

    func stop() {
        queue.sync {
            listener.cancel()
            connections.forEach { $0.cancel() }
            connections.removeAll(keepingCapacity: false)
        }
    }

    private func handle(_ connection: NWConnection) {
        connections.append(connection)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard case .cancelled = state, let self, let connection else { return }
            self.connections.removeAll { $0 === connection }
        }
        connection.start(queue: queue)
        receiveRequest(from: connection, accumulated: Data())
    }

    private func receiveRequest(from connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, complete, error in
            guard let self, error == nil else {
                connection.cancel()
                return
            }
            var requestData = accumulated
            if let data { requestData.append(data) }
            if requestData.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.respond(to: connection, requestData: requestData)
            } else if complete || requestData.count > 64 * 1024 {
                self.send(Data("HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), to: connection)
            } else {
                self.receiveRequest(from: connection, accumulated: requestData)
            }
        }
    }

    private func respond(to connection: NWConnection, requestData: Data) {
        guard let text = String(data: requestData, encoding: .utf8),
              let firstLine = text.components(separatedBy: "\r\n").first
        else {
            send(Data("HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), to: connection)
            return
        }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            send(Data("HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), to: connection)
            return
        }
        let path = URLComponents(string: "http://127.0.0.1\(parts[1])")?.path ?? String(parts[1])
        let headers = text.components(separatedBy: "\r\n").dropFirst().compactMap { line -> (String, String)? in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            return (String(line[..<colon]).lowercased(), String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
        }
        let rangeHeader = headers.first(where: { $0.0 == "range" })?.1
        requests.append(Request(path: path, rangeHeader: rangeHeader))
        guard let media = mediaByPath[path] else {
            send(Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), to: connection)
            return
        }

        if let rangeHeader,
           let bounds = Self.byteRange(rangeHeader, length: media.count) {
            let body = media.subdata(in: bounds)
            let first = bounds.lowerBound
            let last = bounds.upperBound - 1
            let header = "HTTP/1.1 206 Partial Content\r\nContent-Type: video/mp4\r\nAccept-Ranges: bytes\r\nContent-Length: \(body.count)\r\nContent-Range: bytes \(first)-\(last)/\(media.count)\r\nConnection: close\r\n\r\n"
            send(Data(header.utf8) + body, to: connection)
        } else {
            let header = "HTTP/1.1 200 OK\r\nContent-Type: video/mp4\r\nAccept-Ranges: bytes\r\nContent-Length: \(media.count)\r\nConnection: close\r\n\r\n"
            send(Data(header.utf8) + media, to: connection)
        }
    }

    private func send(_ data: Data, to connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func byteRange(_ header: String, length: Int) -> Range<Int>? {
        guard header.lowercased().hasPrefix("bytes="),
              let separator = header.firstIndex(of: "-")
        else { return nil }
        let startText = header[header.index(header.startIndex, offsetBy: 6)..<separator]
        let endText = header[header.index(after: separator)...]
        guard let start = Int(startText), start >= 0, start < length else { return nil }
        let end = endText.isEmpty ? length - 1 : min(Int(endText) ?? -1, length - 1)
        guard end >= start else { return nil }
        return start..<(end + 1)
    }
}

private final class FixtureContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didClaim = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didClaim else { return false }
        didClaim = true
        return true
    }
}
