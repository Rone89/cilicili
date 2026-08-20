import AVFoundation
import XCTest
import Network
import CoreGraphics
import QuartzCore
@testable import bili

final class HLSBridgeRemoteFailureTests: XCTestCase {
    @MainActor
    func testHTTPStatusReasonMatrix() {
        assertHTTPStatus(
            401,
            category: .authDenied,
            isRecoverableByRebuild: false,
            allowsSameSourceRecovery: false,
            proxyStatusCode: 403
        )
        assertHTTPStatus(
            403,
            category: .authDenied,
            isRecoverableByRebuild: false,
            allowsSameSourceRecovery: false,
            proxyStatusCode: 403
        )
        assertHTTPStatus(
            404,
            category: .urlExpired,
            isRecoverableByRebuild: false,
            allowsSameSourceRecovery: false,
            proxyStatusCode: 410
        )
        assertHTTPStatus(
            410,
            category: .urlExpired,
            isRecoverableByRebuild: false,
            allowsSameSourceRecovery: false,
            proxyStatusCode: 410
        )
        assertHTTPStatus(
            412,
            category: .urlExpired,
            isRecoverableByRebuild: false,
            allowsSameSourceRecovery: false,
            proxyStatusCode: 410
        )
        assertHTTPStatus(
            416,
            category: .rangeUnsupported,
            isRecoverableByRebuild: true,
            allowsSameSourceRecovery: false,
            proxyStatusCode: 416
        )
        assertHTTPStatus(
            429,
            category: .rateLimited,
            isRecoverableByRebuild: false,
            allowsSameSourceRecovery: false,
            proxyStatusCode: 429
        )
        assertHTTPStatus(
            503,
            category: .serverUnavailable,
            isRecoverableByRebuild: true,
            allowsSameSourceRecovery: true,
            proxyStatusCode: 502
        )
    }

    @MainActor
    func testURLErrorReasonMatrix() {
        let cancelled = HLSBridgeRemoteFailure.reason(for: URLError(.cancelled))
        XCTAssertEqual(cancelled.category, .cancelled)
        XCTAssertFalse(cancelled.isRecoverableByRebuild)
        XCTAssertFalse(cancelled.shouldRecordSourceFailure)
        XCTAssertEqual(cancelled.proxyHTTPStatus.statusCode, 499)

        let timedOut = HLSBridgeRemoteFailure.reason(for: URLError(.timedOut))
        XCTAssertEqual(timedOut.category, .timeout)
        XCTAssertTrue(timedOut.isRecoverableByRebuild)
        XCTAssertTrue(timedOut.allowsSameSourceRecovery)
        XCTAssertEqual(timedOut.proxyHTTPStatus.statusCode, 504)
    }

    @MainActor
    func testUnknownErrorIsRecoverableByRebuild() {
        let reason = HLSBridgeRemoteFailure.reason(for: NSError(
            domain: "HLSBridgeRemoteFailureTests",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "boom"]
        ))
        XCTAssertEqual(reason.layer, .local)
        XCTAssertEqual(reason.category, .unknown)
        XCTAssertTrue(reason.isRecoverableByRebuild)
        XCTAssertTrue(reason.allowsSameSourceRecovery)
        XCTAssertFalse(reason.shouldRecordSourceFailure)
        XCTAssertEqual(reason.proxyHTTPStatus.statusCode, 502)
    }

    @MainActor
    func testAVFoundationDecodeFailuresSkipSameSourceRecovery() {
        let decoderNotFound = HLSBridgeRemoteFailure.reason(for: NSError(
            domain: AVFoundationErrorDomain,
            code: AVError.Code.decoderNotFound.rawValue
        ))
        XCTAssertEqual(decoderNotFound.layer, .avPlayerItem)
        XCTAssertEqual(decoderNotFound.category, .decoderFailed)
        XCTAssertTrue(decoderNotFound.isRecoverableByRebuild)
        XCTAssertFalse(decoderNotFound.allowsSameSourceRecovery)
        XCTAssertFalse(decoderNotFound.shouldRecordSourceFailure)

        let unsupportedFormat = HLSBridgeRemoteFailure.reason(for: NSError(
            domain: AVFoundationErrorDomain,
            code: AVError.Code.fileFormatNotRecognized.rawValue
        ))
        XCTAssertEqual(unsupportedFormat.layer, .avPlayerItem)
        XCTAssertEqual(unsupportedFormat.category, .codecUnsupported)
        XCTAssertTrue(unsupportedFormat.isRecoverableByRebuild)
        XCTAssertFalse(unsupportedFormat.allowsSameSourceRecovery)
    }

    @MainActor
    func testDecoderCategoriesPreferVariantFallbackOverSameSourceRecovery() {
        for category in [
            HLSBridgeRemoteFailureCategory.codecUnsupported,
            .hardwareDecodeRejected,
            .decoderFailed
        ] {
            let reason = HLSBridgeFailureReason(
                layer: .avPlayerItem,
                category: category,
                statusCode: nil,
                urlHost: nil,
                rangeDescription: nil,
                underlyingDescription: nil
            )

            XCTAssertTrue(reason.isRecoverableByRebuild, "\(category)")
            XCTAssertFalse(reason.allowsSameSourceRecovery, "\(category)")
        }
    }

    private func assertHTTPStatus(
        _ statusCode: Int,
        category: HLSBridgeRemoteFailureCategory,
        isRecoverableByRebuild: Bool,
        allowsSameSourceRecovery: Bool,
        proxyStatusCode: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let reason = HLSBridgeRemoteFailure.reason(forHTTPStatus: statusCode) else {
            XCTFail("Expected reason for HTTP \(statusCode)", file: file, line: line)
            return
        }
        XCTAssertEqual(reason.category, category, file: file, line: line)
        XCTAssertEqual(reason.isRecoverableByRebuild, isRecoverableByRebuild, file: file, line: line)
        XCTAssertEqual(reason.allowsSameSourceRecovery, allowsSameSourceRecovery, file: file, line: line)
        XCTAssertEqual(reason.proxyHTTPStatus.statusCode, proxyStatusCode, file: file, line: line)
    }
}

final class HLSRemoteRangeResponseValidatorTests: XCTestCase {
    @MainActor
    func testRejectsCDNResponseThatIgnoresNonZeroRange() throws {
        let url = try XCTUnwrap(URL(string: "https://upos.example.test/video.m4s"))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Length": "4096"]
        ))
        let range = HTTPByteRange(start: 1024, endInclusive: 2047)

        XCTAssertThrowsError(
            try HLSRemoteRangeResponseValidator.validate(response, requestedRange: range, url: url)
        ) { error in
            guard let failure = error as? HLSBridgeRemoteFailure else {
                return XCTFail("Expected HLSBridgeRemoteFailure, got \(error)")
            }
            XCTAssertEqual(failure.category, .rangeUnsupported)
            XCTAssertEqual(failure.statusCode, 200)
            XCTAssertEqual(failure.reason.rangeDescription, "1024-2047")
        }
    }

    @MainActor
    func testAllowsPartialContentRangeResponse() throws {
        let url = try XCTUnwrap(URL(string: "https://upos.example.test/video.m4s"))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 206,
            httpVersion: nil,
            headerFields: ["Content-Range": "bytes 1024-2047/4096"]
        ))

        XCTAssertNoThrow(try HLSRemoteRangeResponseValidator.validate(
            response,
            requestedRange: HTTPByteRange(start: 1024, endInclusive: 2047),
            url: url
        ))
    }

    @MainActor
    func testRejectsPartialContentWithoutContentRange() throws {
        let url = try XCTUnwrap(URL(string: "https://upos.example.test/video.m4s"))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 206,
            httpVersion: nil,
            headerFields: ["Content-Length": "1024"]
        ))

        XCTAssertThrowsError(try HLSRemoteRangeResponseValidator.validate(
            response,
            requestedRange: HTTPByteRange(start: 1024, endInclusive: 2047),
            url: url
        )) { error in
            guard let failure = error as? HLSBridgeRemoteFailure else {
                return XCTFail("Expected HLSBridgeRemoteFailure, got \(error)")
            }
            XCTAssertEqual(failure.category, .rangeUnsupported)
            XCTAssertEqual(failure.statusCode, 206)
            XCTAssertEqual(failure.reason.rangeDescription, "1024-2047")
        }
    }

    @MainActor
    func testRejectsPartialContentWithMismatchedRange() throws {
        let url = try XCTUnwrap(URL(string: "https://upos.example.test/video.m4s"))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 206,
            httpVersion: nil,
            headerFields: ["Content-Range": "bytes 0-1023/4096"]
        ))

        XCTAssertThrowsError(try HLSRemoteRangeResponseValidator.validate(
            response,
            requestedRange: HTTPByteRange(start: 1024, endInclusive: 2047),
            url: url
        )) { error in
            guard let failure = error as? HLSBridgeRemoteFailure else {
                return XCTFail("Expected HLSBridgeRemoteFailure, got \(error)")
            }
            XCTAssertEqual(failure.category, .rangeUnsupported)
            XCTAssertEqual(failure.statusCode, 206)
            XCTAssertEqual(failure.reason.rangeDescription, "1024-2047")
        }
    }
}

final class SIDXParserTests: XCTestCase {
    @MainActor
    func testParsesSegmentRangesDurationsAndStartTimes() throws {
        let data = makeSIDX(
            timescale: 1_000,
            earliestPresentationTime: 500,
            firstOffset: 10,
            references: [
                (size: 1_200, duration: 2_000),
                (size: 800, duration: 1_500)
            ]
        )

        let references = try SIDXParser.parseReferences(from: data, sidxStartOffset: 100)

        XCTAssertEqual(references.count, 2)
        XCTAssertEqual(references[0].range, HTTPByteRange(start: 166, endInclusive: 1_365))
        XCTAssertEqual(references[0].duration, 2.0, accuracy: 0.000_1)
        XCTAssertEqual(references[0].startTime, 0.5, accuracy: 0.000_1)
        XCTAssertEqual(references[0].startTimeTicks, 500)
        XCTAssertEqual(references[1].range, HTTPByteRange(start: 1_366, endInclusive: 2_165))
        XCTAssertEqual(references[1].duration, 1.5, accuracy: 0.000_1)
        XCTAssertEqual(references[1].startTime, 2.5, accuracy: 0.000_1)
        XCTAssertEqual(references[1].startTimeTicks, 2_500)
    }

    private func makeSIDX(
        timescale: UInt32,
        earliestPresentationTime: UInt32,
        firstOffset: UInt32,
        references: [(size: UInt32, duration: UInt32)]
    ) -> Data {
        var data = Data()
        let boxSize = UInt32(8 + 4 + 4 + 4 + 4 + 4 + 2 + 2 + references.count * 12)
        appendUInt32(boxSize, to: &data)
        data.append(contentsOf: [UInt8]("sidx".utf8))
        data.append(contentsOf: [0, 0, 0, 0])
        appendUInt32(1, to: &data)
        appendUInt32(timescale, to: &data)
        appendUInt32(earliestPresentationTime, to: &data)
        appendUInt32(firstOffset, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(UInt16(references.count), to: &data)
        for reference in references {
            appendUInt32(reference.size, to: &data)
            appendUInt32(reference.duration, to: &data)
            appendUInt32(0, to: &data)
        }
        return data
    }

    private func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8(value & 0xff))
    }

    private func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8((value >> 24) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8(value & 0xff))
    }
}

final class BiliHLSManifestBuilderHeaderTests: XCTestCase {
    @MainActor
    func testPlaybackHeadersIncludeCookieWhenProvided() {
        let headers = BiliHLSManifestBuilder.httpHeaders(
            referer: "https://www.bilibili.com/video/BV1xx",
            cookieHeader: "buvid3=abc; SESSDATA=def"
        )

        XCTAssertEqual(headers["Referer"], "https://www.bilibili.com/video/BV1xx")
        XCTAssertEqual(headers["Cookie"], "buvid3=abc; SESSDATA=def")
        XCTAssertNotNil(headers["User-Agent"])
    }
}

final class HLSPlaylistAttributeFormatterTests: XCTestCase {
    @MainActor
    func testFormatsFrameRateAttribute() {
        XCTAssertEqual(HLSPlaylistAttributeFormatter.frameRateAttribute(for: 60), ",FRAME-RATE=60")
        XCTAssertEqual(HLSPlaylistAttributeFormatter.frameRateAttribute(for: 29.97003), ",FRAME-RATE=29.97")
        XCTAssertEqual(HLSPlaylistAttributeFormatter.frameRateAttribute(for: nil), "")
        XCTAssertEqual(HLSPlaylistAttributeFormatter.frameRateAttribute(for: 0), "")
    }
}

final class HLSBridgePlaylistRenderingTests: XCTestCase {
    @MainActor
    func testRendersMasterMediaPlaylistsAndRangeRoutes() throws {
        let baseURL = try XCTUnwrap(URL(string: "http://127.0.0.1:49152"))
        let videoURL = try XCTUnwrap(URL(string: "https://upos.example.test/video-hevc.m4s"))
        let videoBackupURL = try XCTUnwrap(URL(string: "https://backup.example.test/video-hevc.m4s"))
        let audioURL = try XCTUnwrap(URL(string: "https://upos.example.test/audio-aac.m4s"))
        let plan = HLSBridgeRoutePlan(
            videoRenditions: [
                HLSRendition(
                    sourceURL: videoURL,
                    fallbackSourceURLs: [videoBackupURL],
                    mediaType: .video,
                    quality: 80,
                    initialization: HTTPByteRange(start: 0, endInclusive: 999),
                    initializationData: nil,
                    references: [
                        SIDXParser.Reference(
                            range: HTTPByteRange(start: 1_000, endInclusive: 1_999),
                            duration: 1.2,
                            startTime: 0,
                            startTimeTicks: 0,
                            timescale: 1_000
                        ),
                        SIDXParser.Reference(
                            range: HTTPByteRange(start: 2_000, endInclusive: 3_999),
                            duration: 2.4,
                            startTime: 1.2,
                            startTimeTicks: 1_200,
                            timescale: 1_000
                        )
                    ],
                    targetDuration: 2.4,
                    bandwidth: 1_800_000,
                    codec: "hvc1.1.6.L120.B0",
                    mediaTimeOffset: 0,
                    baseMediaDecodeTimeOffsetTicks: 0,
                    dynamicRange: .sdr,
                    dolbyVisionConfiguration: nil,
                    hlsBaseLayerCodec: nil,
                    dimensions: CGSize(width: 1920, height: 1080),
                    frameRate: 59.94
                )
            ],
            audioRendition: HLSRendition(
                sourceURL: audioURL,
                fallbackSourceURLs: [],
                mediaType: .audio,
                quality: 30280,
                initialization: HTTPByteRange(start: 0, endInclusive: 299),
                initializationData: nil,
                references: [
                    SIDXParser.Reference(
                        range: HTTPByteRange(start: 300, endInclusive: 699),
                        duration: 1,
                        startTime: 0,
                        startTimeTicks: 0,
                        timescale: 1_000
                    ),
                    SIDXParser.Reference(
                        range: HTTPByteRange(start: 700, endInclusive: 1_099),
                        duration: 1,
                        startTime: 1,
                        startTimeTicks: 1_000,
                        timescale: 1_000
                    )
                ],
                targetDuration: 1,
                bandwidth: 128_000,
                codec: "mp4a.40.2",
                mediaTimeOffset: 0,
                baseMediaDecodeTimeOffsetTicks: 0,
                dynamicRange: .sdr,
                dolbyVisionConfiguration: nil,
                hlsBaseLayerCodec: nil,
                dimensions: nil,
                frameRate: nil
            ),
            masterPlaylistVersion: 7
        )

        let rendered = LocalHLSBridge.renderPlaylists(from: plan, baseURL: baseURL)

        XCTAssertEqual(rendered.masterPlaylistURL.absoluteString, "http://127.0.0.1:49152/master.m3u8")
        XCTAssertEqual(Set(rendered.routes.keys), Set([
            "/master.m3u8",
            "/video.m3u8",
            "/audio.m3u8",
            "/media/video/init.mp4",
            "/media/video/segment-0.m4s",
            "/media/video/segment-1.m4s",
            "/media/audio/init.mp4",
            "/media/audio/segment-0.m4s",
            "/media/audio/segment-1.m4s"
        ]))

        let master = try dataRouteString("/master.m3u8", in: rendered.routes)
        XCTAssertEqual(master.contentType, "application/vnd.apple.mpegurl")
        XCTAssertTrue(master.playlist.contains("#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio\",NAME=\"audio\",DEFAULT=YES,AUTOSELECT=YES,URI=\"http://127.0.0.1:49152/audio.m3u8\""))
        XCTAssertTrue(master.playlist.contains("#EXT-X-STREAM-INF:BANDWIDTH=1800000,CODECS=\"hvc1.1.6.L120.B0,mp4a.40.2\",AUDIO=\"audio\",RESOLUTION=1920x1080,FRAME-RATE=59.94"))
        XCTAssertTrue(master.playlist.contains("http://127.0.0.1:49152/video.m3u8"))

        let video = try dataRouteString("/video.m3u8", in: rendered.routes)
        XCTAssertTrue(video.playlist.contains("#EXT-X-PLAYLIST-TYPE:VOD"))
        XCTAssertTrue(video.playlist.contains("#EXT-X-TARGETDURATION:3"))
        XCTAssertTrue(video.playlist.contains("#EXT-X-MAP:URI=\"http://127.0.0.1:49152/media/video/init.mp4\""))
        XCTAssertTrue(video.playlist.contains("#EXTINF:1.200000,\nhttp://127.0.0.1:49152/media/video/segment-0.m4s"))
        XCTAssertTrue(video.playlist.contains("#EXTINF:2.400000,\nhttp://127.0.0.1:49152/media/video/segment-1.m4s"))
        XCTAssertTrue(video.playlist.contains("#EXT-X-ENDLIST"))

        let audio = try dataRouteString("/audio.m3u8", in: rendered.routes)
        XCTAssertTrue(audio.playlist.contains("#EXT-X-MAP:URI=\"http://127.0.0.1:49152/media/audio/init.mp4\""))
        XCTAssertTrue(audio.playlist.contains("#EXTINF:1.000000,\nhttp://127.0.0.1:49152/media/audio/segment-0.m4s"))

        try assertRemoteRoute(
            "/media/video/init.mp4",
            in: rendered.routes,
            url: videoURL,
            fallbackURLs: [videoBackupURL],
            range: HTTPByteRange(start: 0, endInclusive: 999),
            contentType: "video/mp4"
        )
        try assertRemoteRoute(
            "/media/video/segment-1.m4s",
            in: rendered.routes,
            url: videoURL,
            fallbackURLs: [videoBackupURL],
            range: HTTPByteRange(start: 2_000, endInclusive: 3_999),
            contentType: "video/mp4"
        )
        try assertRemoteRoute(
            "/media/audio/segment-0.m4s",
            in: rendered.routes,
            url: audioURL,
            fallbackURLs: [],
            range: HTTPByteRange(start: 300, endInclusive: 699),
            contentType: "audio/mp4"
        )
    }

    @MainActor
    func testRendersNativeHDRVideoOnlyPlaylistWithoutAudioGroup() throws {
        let baseURL = try XCTUnwrap(URL(string: "http://127.0.0.1:50123"))
        let videoURL = try XCTUnwrap(URL(string: "https://upos.example.test/video-dv.m4s"))
        let rendition = HLSRendition(
            sourceURL: videoURL,
            fallbackSourceURLs: [],
            mediaType: .video,
            quality: 126,
            initialization: HTTPByteRange(start: 0, endInclusive: 999),
            initializationData: nil,
            references: [
                SIDXParser.Reference(
                    range: HTTPByteRange(start: 1_000, endInclusive: 1_999),
                    duration: 1,
                    startTime: 0,
                    startTimeTicks: 0,
                    timescale: 1_000
                )
            ],
            targetDuration: 1,
            bandwidth: 9_040_460,
            codec: "hvc1.2.4.H150.90",
            mediaTimeOffset: 0,
            baseMediaDecodeTimeOffsetTicks: 0,
            dynamicRange: .dolbyVision,
            dolbyVisionConfiguration: DolbyVisionCodecConfiguration(
                boxType: "dvvC",
                profile: 8,
                level: 7,
                rpuPresent: true,
                enhancementLayerPresent: false,
                baseLayerPresent: true,
                baseLayerSignalCompatibilityID: 4
            ),
            dolbyVisionRenderingPolicy: .appleNativeP8HLS,
            hlsBaseLayerCodec: "hvc1.2.4.H150.90",
            dimensions: CGSize(width: 3840, height: 2160),
            frameRate: 29.97003
        )

        let rendered = LocalHLSBridge.renderVideoOnlyPlaylists(
            rendition: rendition,
            masterPlaylistVersion: 10,
            baseURL: baseURL
        )

        XCTAssertEqual(Set(rendered.routes.keys), Set([
            "/master.m3u8",
            "/video.m3u8",
            "/media/video/init.mp4",
            "/media/video/segment-0.m4s"
        ]))
        let master = try dataRouteString("/master.m3u8", in: rendered.routes)
        XCTAssertFalse(master.playlist.contains("#EXT-X-MEDIA:TYPE=AUDIO"))
        XCTAssertFalse(master.playlist.contains("AUDIO=\"audio\""))
        XCTAssertTrue(master.playlist.contains("CODECS=\"hvc1.2.4.H150.90\""))
        XCTAssertTrue(master.playlist.contains("VIDEO-RANGE=HLG"))
        XCTAssertTrue(master.playlist.contains("SUPPLEMENTAL-CODECS=\"dvh1.08.07/db4h\""))
        XCTAssertTrue(master.playlist.contains("RESOLUTION=3840x2160"))
        XCTAssertTrue(master.playlist.contains("FRAME-RATE=29.97"))

        let video = try dataRouteString("/video.m3u8", in: rendered.routes)
        XCTAssertTrue(video.playlist.contains("#EXT-X-MAP:URI=\"http://127.0.0.1:50123/media/video/init.mp4\""))
        try assertRemoteRoute(
            "/media/video/segment-0.m4s",
            in: rendered.routes,
            url: videoURL,
            fallbackURLs: [],
            range: HTTPByteRange(start: 1_000, endInclusive: 1_999),
            contentType: "video/mp4"
        )
    }

    @MainActor
    func testRendersAudioOnlyPlaylistWithoutVideoRoutes() throws {
        let baseURL = try XCTUnwrap(URL(string: "http://127.0.0.1:50124"))
        let audioURL = try XCTUnwrap(URL(string: "https://upos.example.test/audio-aac.m4s"))
        let rendition = HLSRendition(
            sourceURL: audioURL,
            fallbackSourceURLs: [],
            mediaType: .audio,
            quality: 30280,
            initialization: HTTPByteRange(start: 0, endInclusive: 299),
            initializationData: nil,
            references: [
                SIDXParser.Reference(
                    range: HTTPByteRange(start: 300, endInclusive: 699),
                    duration: 1,
                    startTime: 0,
                    startTimeTicks: 0,
                    timescale: 1_000
                )
            ],
            targetDuration: 1,
            bandwidth: 128_000,
            codec: "mp4a.40.2",
            mediaTimeOffset: 0,
            baseMediaDecodeTimeOffsetTicks: 0,
            dynamicRange: .sdr,
            dolbyVisionConfiguration: nil,
            hlsBaseLayerCodec: nil,
            dimensions: nil,
            frameRate: nil
        )

        let rendered = LocalHLSBridge.renderAudioOnlyPlaylists(
            rendition: rendition,
            baseURL: baseURL
        )

        XCTAssertEqual(Set(rendered.routes.keys), Set([
            "/master.m3u8",
            "/audio.m3u8",
            "/media/audio/init.mp4",
            "/media/audio/segment-0.m4s"
        ]))
        XCTAssertFalse(rendered.routes.keys.contains(where: { $0.contains("video") }))

        let master = try dataRouteString("/master.m3u8", in: rendered.routes)
        XCTAssertTrue(master.playlist.contains("CODECS=\"mp4a.40.2\""))
        XCTAssertFalse(master.playlist.contains("RESOLUTION="))
        XCTAssertFalse(master.playlist.contains("#EXT-X-MEDIA:TYPE=AUDIO"))

        let audio = try dataRouteString("/audio.m3u8", in: rendered.routes)
        XCTAssertTrue(audio.playlist.contains("/media/audio/init.mp4"))
        try assertRemoteRoute(
            "/media/audio/segment-0.m4s",
            in: rendered.routes,
            url: audioURL,
            fallbackURLs: [],
            range: HTTPByteRange(start: 300, endInclusive: 699),
            contentType: "audio/mp4"
        )
    }

    private func dataRouteString(
        _ path: String,
        in routes: [String: HLSProxyRoute],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> (playlist: String, contentType: String) {
        guard let route = routes[path] else {
            XCTFail("Missing route \(path)", file: file, line: line)
            throw TestFailure.missingRoute
        }
        guard case let .data(data, contentType) = route,
              let playlist = String(data: data, encoding: .utf8)
        else {
            XCTFail("Expected data route at \(path)", file: file, line: line)
            throw TestFailure.unexpectedRoute
        }
        return (playlist, contentType)
    }

    private func assertRemoteRoute(
        _ path: String,
        in routes: [String: HLSProxyRoute],
        url: URL,
        fallbackURLs: [URL],
        range: HTTPByteRange,
        contentType: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard let route = routes[path] else {
            XCTFail("Missing route \(path)", file: file, line: line)
            throw TestFailure.missingRoute
        }
        guard case let .remoteByteRange(routeURL, routeFallbackURLs, routeRange, routeContentType, transform) = route else {
            XCTFail("Expected remote range route at \(path)", file: file, line: line)
            throw TestFailure.unexpectedRoute
        }
        XCTAssertEqual(routeURL, url, file: file, line: line)
        XCTAssertEqual(routeFallbackURLs, fallbackURLs, file: file, line: line)
        XCTAssertEqual(routeRange, range, file: file, line: line)
        XCTAssertEqual(routeContentType, contentType, file: file, line: line)
        XCTAssertNil(transform, file: file, line: line)
    }

    private enum TestFailure: Error {
        case missingRoute
        case unexpectedRoute
    }
}

final class HLSLoopbackEndpointPolicyTests: XCTestCase {
    @MainActor
    func testAllowsOnlyLoopbackHostPortEndpoints() throws {
        XCTAssertTrue(HLSLoopbackEndpointPolicy.allows(.hostPort(
            host: .ipv4(try XCTUnwrap(IPv4Address("127.0.0.1"))),
            port: try XCTUnwrap(NWEndpoint.Port(rawValue: 49152))
        )))
        XCTAssertTrue(HLSLoopbackEndpointPolicy.allows(.hostPort(
            host: .ipv6(try XCTUnwrap(IPv6Address("::1"))),
            port: try XCTUnwrap(NWEndpoint.Port(rawValue: 49152))
        )))
        XCTAssertTrue(HLSLoopbackEndpointPolicy.allows(.hostPort(
            host: .name("localhost", nil),
            port: try XCTUnwrap(NWEndpoint.Port(rawValue: 49152))
        )))
        XCTAssertFalse(HLSLoopbackEndpointPolicy.allows(.hostPort(
            host: .ipv4(try XCTUnwrap(IPv4Address("192.168.1.2"))),
            port: try XCTUnwrap(NWEndpoint.Port(rawValue: 49152))
        )))
    }

    @MainActor
    func testListenerParametersRequireIPv4LoopbackEndpoint() throws {
        let parameters = try HLSLoopbackEndpointPolicy.tcpListenerParameters()
        let endpoint = try XCTUnwrap(parameters.requiredLocalEndpoint)

        guard case let .hostPort(host, endpointPort) = endpoint else {
            return XCTFail("Expected host-port local endpoint")
        }
        XCTAssertEqual("\(host)", "127.0.0.1")
        XCTAssertEqual(endpointPort, .any)
    }

#if DEBUG
    @MainActor
    func testLocalLiveProxyUsesLoopbackEndpointPolicy() throws {
        let endpoint = try XCTUnwrap(LocalLiveHLSProxyTesting.listenerRequiredLocalEndpoint())

        guard case let .hostPort(host, endpointPort) = endpoint else {
            return XCTFail("Expected host-port local endpoint")
        }
        XCTAssertEqual("\(host)", "127.0.0.1")
        XCTAssertEqual(endpointPort, .any)
        XCTAssertTrue(LocalLiveHLSProxyTesting.allowsConnectionEndpoint(.hostPort(
            host: .ipv4(try XCTUnwrap(IPv4Address("127.0.0.1"))),
            port: try XCTUnwrap(NWEndpoint.Port(rawValue: 49152))
        )))
        XCTAssertFalse(LocalLiveHLSProxyTesting.allowsConnectionEndpoint(.hostPort(
            host: .ipv4(try XCTUnwrap(IPv4Address("192.168.1.2"))),
            port: try XCTUnwrap(NWEndpoint.Port(rawValue: 49152))
        )))
    }
#endif
}

@MainActor
final class PlayerPerformanceDiagnosticsPrivacyTests: XCTestCase {
    @MainActor
    func testCopyFormatterRedactsFailureHostToRegistrableSuffix() {
        XCTAssertEqual(
            PlayerPerformanceOverlayDiagnosticsCopyTextFormatter.redactedHost("upos-sz-mirror08c.bilivideo.com"),
            "*.bilivideo.com"
        )
        XCTAssertEqual(
            PlayerPerformanceOverlayDiagnosticsCopyTextFormatter.redactedHost("127.0.0.1"),
            "<redacted-ip>"
        )
        XCTAssertEqual(
            PlayerPerformanceOverlayDiagnosticsCopyTextFormatter.redactedHost(nil),
            "-"
        )
    }

    @MainActor
    func testCopyFormatterRedactsSourceHosts() {
        XCTAssertEqual(
            PlayerPerformanceOverlayDiagnosticsCopyTextFormatter.redactedSourceHosts(
                videoHost: "upos-sz-mirror08c.bilivideo.com",
                audioHost: "upos-hz-mirrorakam.akamaized.net"
            ),
            "video=*.bilivideo.com audio=*.akamaized.net"
        )
        XCTAssertEqual(
            PlayerPerformanceOverlayDiagnosticsCopyTextFormatter.redactedSourceHosts(
                videoHost: "upos-sz-mirror08c.bilivideo.com",
                audioHost: "upos-tf-all-js.bilivideo.com"
            ),
            "video=*.bilivideo.com"
        )
    }

    @MainActor
    func testFailureActionHintNamesDecodeFallback() {
        let reason = HLSBridgeFailureReason(
            layer: .avPlayerItem,
            category: .decoderFailed,
            statusCode: nil,
            urlHost: "upos-sz-mirror08c.bilivideo.com",
            rangeDescription: nil,
            underlyingDescription: nil
        )

        let hint = PlayerPerformanceOverlayDiagnosticsCopyTextFormatter.failureActionHint(for: reason)

        XCTAssertTrue(hint.contains("H.264"))
        XCTAssertTrue(hint.contains("SDR"))
    }

    @MainActor
    func testEngineDiagnosticsCompactDescriptionIncludesPlaybackPipeline() {
        let diagnostics = PlayerEngineDiagnostics(
            engineName: "AVPlayer",
            decodePath: .avPlayer,
            playbackPipeline: .dashLocalHLS,
            codec: "HEVC",
            videoCodecIdentifier: "hvc1.1.6.L120.B0",
            audioCodecIdentifier: "mp4a.40.2",
            videoCodecid: 12,
            audioCodecid: nil,
            resolution: "1920x1080",
            frameRate: "60",
            bandwidth: 2_400_000,
            dynamicRange: .sdr,
            isDASH: true,
            usesLocalHLSBridge: true,
            localPlaylistURL: "http://127.0.0.1:49152/master.m3u8",
            sourceVideoHost: "upos-sz-mirror08c.bilivideo.com",
            sourceAudioHost: "upos-tf-all-js.bilivideo.com",
            hlsVideoVariantCount: 2,
            hlsVideoVariantQualities: [80, 80],
            hlsVideoVariantDetails: ["q80 hvc1.1.6.L120.B0", "q80 avc1.640028"],
            preferredForwardBufferDuration: 1.2,
            maxBufferDuration: nil,
            asynchronousDecompressionEnabled: false,
            hardwareDecodeRequested: true,
            isHardwareDecodeCompatible: true,
            environmentSummary: nil
        )

        XCTAssertTrue(diagnostics.compactDescription.contains("本地 HLS"))
        XCTAssertTrue(diagnostics.compactDescription.contains("HLSBridge"))
        XCTAssertTrue(diagnostics.compactDescription.contains("hvc1.1.6.L120.B0"))
    }
}

final class HLSProxyFailureStoreTests: XCTestCase {
    @MainActor
    func testStoresRecentRemoteFailureReason() throws {
        let store = HLSProxyFailureStore()
        let url = try XCTUnwrap(URL(string: "https://upos.example.test/video.m4s"))

        store.record(HLSBridgeRemoteFailure.httpStatus(
            412,
            url: url,
            range: HTTPByteRange(start: 0, endInclusive: 99)
        ))
        let reason = try XCTUnwrap(store.recentReason())

        XCTAssertEqual(reason.category, .urlExpired)
        XCTAssertEqual(reason.statusCode, 412)
        XCTAssertEqual(reason.urlHost, "upos.example.test")
        XCTAssertEqual(reason.rangeDescription, "0-99")
    }

    @MainActor
    func testIgnoresStaleRemoteFailureReason() {
        let store = HLSProxyFailureStore()

        store.record(
            HLSBridgeRemoteFailure.httpStatus(403, url: nil, range: nil),
            now: Date(timeIntervalSince1970: 10)
        )

        XCTAssertNil(store.recentReason(maxAge: 1, now: Date(timeIntervalSince1970: 12)))
    }
}

final class HLSProxyHTTPResponseBuilderTests: XCTestCase {
    @MainActor
    func testRequestRangeParserSupportsOpenEndedAndSuffixRanges() {
        XCTAssertEqual(
            HTTPByteRange(httpHeaderValue: "bytes=1000-")?.clamped(toLength: 1_500),
            HTTPByteRange(start: 1_000, endInclusive: 1_499)
        )
        XCTAssertEqual(
            HTTPByteRange(httpHeaderValue: "bytes=-500")?.clamped(toLength: 1_500),
            HTTPByteRange(start: 1_000, endInclusive: 1_499)
        )
        XCTAssertEqual(
            HTTPByteRange(httpHeaderValue: "bytes=-2000")?.clamped(toLength: 1_500),
            HTTPByteRange(start: 0, endInclusive: 1_499)
        )
        XCTAssertNil(HTTPByteRange(rawValue: "1000-"))
        XCTAssertNil(HTTPByteRange(rawValue: "-500"))
    }

    @MainActor
    func testBuildsPartialContentResponseForMediaRange() throws {
        let request = try XCTUnwrap(HLSProxyRequest(data: Data("""
        GET /media/video/segment-1.m4s HTTP/1.1\r
        Range: bytes=1000-1999\r
        Connection: close\r
        \r
        """.utf8)))

        let response = HLSProxyHTTPResponseBuilder.dataResponse(
            contentType: "video/mp4",
            request: request,
            responseLength: 1_000,
            totalLength: 4_000,
            servedRange: HTTPByteRange(start: 1_000, endInclusive: 1_999),
            closesConnection: true
        )

        XCTAssertEqual(response.statusLine, "HTTP/1.1 206 Partial Content")
        XCTAssertEqual(response.headers["Content-Type"], "video/mp4")
        XCTAssertEqual(response.headers["Content-Length"], "1000")
        XCTAssertEqual(response.headers["Accept-Ranges"], "bytes")
        XCTAssertEqual(response.headers["Content-Range"], "bytes 1000-1999/4000")
        XCTAssertEqual(response.headers["Cache-Control"], "public, max-age=3600")
        XCTAssertEqual(response.headers["Connection"], "close")
        let headerText = try XCTUnwrap(String(data: response.headerData, encoding: .utf8))
        XCTAssertTrue(headerText.hasPrefix("HTTP/1.1 206 Partial Content\r\n"))
        XCTAssertTrue(headerText.hasSuffix("\r\n\r\n"))
    }

    @MainActor
    func testBuildsNoCachePlaylistResponse() throws {
        let request = try XCTUnwrap(HLSProxyRequest(data: Data("""
        HEAD /master.m3u8 HTTP/1.1\r
        Connection: keep-alive\r
        \r
        """.utf8)))

        let response = HLSProxyHTTPResponseBuilder.dataResponse(
            contentType: "application/vnd.apple.mpegurl",
            request: request,
            responseLength: 256,
            closesConnection: false
        )

        XCTAssertEqual(response.statusLine, "HTTP/1.1 200 OK")
        XCTAssertEqual(response.headers["Content-Type"], "application/vnd.apple.mpegurl")
        XCTAssertEqual(response.headers["Content-Length"], "256")
        XCTAssertEqual(response.headers["Accept-Ranges"], "bytes")
        XCTAssertNil(response.headers["Content-Range"])
        XCTAssertEqual(response.headers["Cache-Control"], "no-cache")
        XCTAssertEqual(response.headers["Connection"], "keep-alive")
    }

    @MainActor
    func testBuildsPlainTextErrorResponse() throws {
        let error = HLSProxyHTTPResponseBuilder.errorResponse(statusCode: 410, reason: "Gone")

        XCTAssertEqual(error.response.statusLine, "HTTP/1.1 410 Gone")
        XCTAssertEqual(error.response.headers["Content-Type"], "text/plain; charset=utf-8")
        XCTAssertEqual(error.response.headers["Content-Length"], "4")
        XCTAssertEqual(error.response.headers["Connection"], "close")
        XCTAssertEqual(String(data: error.body, encoding: .utf8), "Gone")
    }
}

#if DEBUG
final class LocalHLSProxyServerIntegrationTests: XCTestCase {
    @MainActor
    func testParallelBridgesUseDistinctSystemAssignedPorts() async throws {
        let videoURL = try XCTUnwrap(URL(string: "https://upos.example.test/video.m4s"))
        let audioURL = try XCTUnwrap(URL(string: "https://upos.example.test/audio.m4s"))
        let plan = makeRoutePlan(videoURL: videoURL, audioURL: audioURL)

        async let first = LocalHLSBridge.makeForTesting(from: plan)
        async let second = LocalHLSBridge.makeForTesting(from: plan)
        let bridges = try await [first, second]
        defer { bridges.forEach { $0.stop() } }

        let ports = try bridges.map { try XCTUnwrap($0.masterPlaylistURL.port) }
        XCTAssertEqual(Set(ports).count, bridges.count)
    }

    @MainActor
    func testServesLocalPlaylistsAndTranslatesSegmentRangeRequests() async throws {
        let videoData = testData(byteCount: 512)
        let audioData = testData(byteCount: 128)
        let upstream = try TestHTTPRangeServer(routes: [
            "/video.m4s": .data(videoData, contentType: "video/mp4"),
            "/audio.m4s": .data(audioData, contentType: "audio/mp4")
        ])
        try await upstream.start()
        defer { upstream.stop() }

        let bridge = try await LocalHLSBridge.makeForTesting(
            from: makeRoutePlan(
                videoURL: upstream.url(path: "/video.m4s"),
                audioURL: upstream.url(path: "/audio.m4s")
            ),
            headers: [
                "User-Agent": "LocalHLSProxyServerIntegrationTests/1.0",
                "Referer": "https://www.bilibili.com/video/BV1",
                "Cookie": "SESSDATA=test"
            ],
            metricsID: "local-hls-proxy-test"
        )
        defer { bridge.stop() }

        let master = try await fetch(bridge.masterPlaylistURL)
        XCTAssertEqual(master.response.statusCode, 200)
        let masterPlaylist = try XCTUnwrap(String(data: master.data, encoding: .utf8))
        XCTAssertTrue(masterPlaylist.contains("#EXT-X-MEDIA:TYPE=AUDIO"))
        XCTAssertTrue(masterPlaylist.contains("#EXT-X-STREAM-INF:BANDWIDTH=1800000"))

        let videoPlaylistURL = bridge.masterPlaylistURL
            .deletingLastPathComponent()
            .appendingPathComponent("video.m3u8")
        let videoPlaylist = try await fetch(videoPlaylistURL)
        XCTAssertEqual(videoPlaylist.response.statusCode, 200)
        XCTAssertTrue(String(data: videoPlaylist.data, encoding: .utf8)?.contains("#EXT-X-MAP") == true)

        let segmentURL = bridge.masterPlaylistURL
            .deletingLastPathComponent()
            .appendingPathComponent("media/video/segment-0.m4s")
        let segment = try await fetch(segmentURL, rangeHeader: "bytes=2-5")

        XCTAssertEqual(segment.response.statusCode, 206)
        XCTAssertEqual(segment.response.value(forHTTPHeaderField: "Content-Range"), "bytes 2-5/10")
        XCTAssertEqual(segment.data, videoData.subdata(in: 102..<106))

        let requests = await upstream.recordedRequests()
        let videoRequest = try XCTUnwrap(requests.first { $0.path == "/video.m4s" })
        XCTAssertEqual(videoRequest.rangeHeader, "bytes=102-105")
        XCTAssertEqual(videoRequest.headers["user-agent"], "LocalHLSProxyServerIntegrationTests/1.0")
        XCTAssertEqual(videoRequest.headers["referer"], "https://www.bilibili.com/video/BV1")
        XCTAssertEqual(videoRequest.headers["cookie"], "SESSDATA=test")
    }

    @MainActor
    func testFallsBackToBackupURLWhenPrimarySegmentRequestFails() async throws {
        let primaryData = testData(byteCount: 128, seed: 3)
        let fallbackData = testData(byteCount: 128, seed: 7)
        let audioData = testData(byteCount: 64, seed: 11)
        let upstream = try TestHTTPRangeServer(routes: [
            "/video-primary.m4s": .status(503, reason: "Service Unavailable"),
            "/video-backup.m4s": .data(fallbackData, contentType: "video/mp4"),
            "/audio.m4s": .data(audioData, contentType: "audio/mp4")
        ])
        try await upstream.start()
        defer { upstream.stop() }

        let bridge = try await LocalHLSBridge.makeForTesting(
            from: makeRoutePlan(
                videoURL: upstream.url(path: "/video-primary.m4s"),
                videoFallbackURLs: [upstream.url(path: "/video-backup.m4s")],
                audioURL: upstream.url(path: "/audio.m4s"),
                videoReferenceRange: HTTPByteRange(start: 40, endInclusive: 49)
            ),
            headers: ["User-Agent": "LocalHLSProxyServerIntegrationTests/1.0"],
            metricsID: "local-hls-proxy-fallback-test"
        )
        defer { bridge.stop() }

        let segmentURL = bridge.masterPlaylistURL
            .deletingLastPathComponent()
            .appendingPathComponent("media/video/segment-0.m4s")
        let segment = try await fetch(segmentURL)

        XCTAssertEqual(segment.response.statusCode, 200)
        XCTAssertEqual(segment.data, fallbackData.subdata(in: 40..<50))
        XCTAssertNotEqual(segment.data, primaryData.subdata(in: 40..<50))

        let requests = await upstream.recordedRequests()
        XCTAssertTrue(requests.contains { $0.path == "/video-primary.m4s" && $0.rangeHeader == "bytes=40-49" })
        XCTAssertTrue(requests.contains { $0.path == "/video-backup.m4s" && $0.rangeHeader == "bytes=40-49" })
    }

    @MainActor
    func testStartupHedgeUsesBackupWhenPrimaryFirstChunkIsSlow() async throws {
        let byteCount = 640 * 1024
        let primaryData = testData(byteCount: byteCount, seed: 13)
        let fallbackData = testData(byteCount: byteCount, seed: 17)
        let audioData = testData(byteCount: 64, seed: 19)
        let upstream = try TestHTTPRangeServer(routes: [
            "/video-primary.m4s": .data(
                primaryData,
                contentType: "video/mp4",
                responseDelayNanoseconds: 900_000_000
            ),
            "/video-backup.m4s": .data(fallbackData, contentType: "video/mp4"),
            "/audio.m4s": .data(audioData, contentType: "audio/mp4")
        ])
        try await upstream.start()
        defer { upstream.stop() }

        let cacheNonce = UUID().uuidString
        var primaryComponents = try XCTUnwrap(URLComponents(
            url: upstream.url(path: "/video-primary.m4s"),
            resolvingAgainstBaseURL: false
        ))
        primaryComponents.queryItems = [URLQueryItem(name: "test", value: cacheNonce)]
        let primaryURL = try XCTUnwrap(primaryComponents.url)
        var fallbackComponents = try XCTUnwrap(URLComponents(
            url: upstream.url(path: "/video-backup.m4s"),
            resolvingAgainstBaseURL: false
        ))
        fallbackComponents.queryItems = [URLQueryItem(name: "test", value: cacheNonce)]
        let fallbackURL = try XCTUnwrap(fallbackComponents.url)

        let bridge = try await LocalHLSBridge.makeForTesting(
            from: makeRoutePlan(
                videoURL: primaryURL,
                videoFallbackURLs: [fallbackURL],
                audioURL: upstream.url(path: "/audio.m4s"),
                videoReferenceRange: HTTPByteRange(start: 0, endInclusive: Int64(byteCount - 1))
            ),
            headers: ["User-Agent": "LocalHLSProxyServerIntegrationTests/1.0"],
            metricsID: "local-hls-proxy-hedge-test"
        )
        defer { bridge.stop() }

        let segmentURL = bridge.masterPlaylistURL
            .deletingLastPathComponent()
            .appendingPathComponent("media/video/segment-0.m4s")
        let start = CACurrentMediaTime()
        let segment = try await fetch(segmentURL)
        let elapsedMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: start)
        let requests = await upstream.recordedRequests()

        XCTAssertEqual(segment.response.statusCode, 200)
        XCTAssertEqual(
            segment.data,
            fallbackData,
            "elapsed=\(elapsedMilliseconds) requests=\(requests.map(\.path))"
        )
        XCTAssertLessThan(elapsedMilliseconds, 850, "requests=\(requests.map(\.path))")

        XCTAssertTrue(requests.contains { $0.path == "/video-primary.m4s" }, "requests=\(requests.map(\.path))")
        XCTAssertTrue(requests.contains { $0.path == "/video-backup.m4s" }, "requests=\(requests.map(\.path))")
    }

    private func makeRoutePlan(
        videoURL: URL,
        videoFallbackURLs: [URL] = [],
        audioURL: URL,
        videoReferenceRange: HTTPByteRange = HTTPByteRange(start: 100, endInclusive: 109),
        audioReferenceRange: HTTPByteRange = HTTPByteRange(start: 20, endInclusive: 29)
    ) -> HLSBridgeRoutePlan {
        HLSBridgeRoutePlan(
            videoRenditions: [
                HLSRendition(
                    sourceURL: videoURL,
                    fallbackSourceURLs: videoFallbackURLs,
                    mediaType: .video,
                    quality: 80,
                    initialization: HTTPByteRange(start: 0, endInclusive: 9),
                    initializationData: nil,
                    references: [
                        SIDXParser.Reference(
                            range: videoReferenceRange,
                            duration: 1,
                            startTime: 0,
                            startTimeTicks: 0,
                            timescale: 1_000
                        )
                    ],
                    targetDuration: 1,
                    bandwidth: 1_800_000,
                    codec: "hvc1.1.6.L120.B0",
                    mediaTimeOffset: 0,
                    baseMediaDecodeTimeOffsetTicks: 0,
                    dynamicRange: .sdr,
                    dolbyVisionConfiguration: nil,
                    hlsBaseLayerCodec: nil,
                    dimensions: CGSize(width: 1920, height: 1080),
                    frameRate: 30
                )
            ],
            audioRendition: HLSRendition(
                sourceURL: audioURL,
                fallbackSourceURLs: [],
                mediaType: .audio,
                quality: 30280,
                initialization: HTTPByteRange(start: 0, endInclusive: 9),
                initializationData: nil,
                references: [
                    SIDXParser.Reference(
                        range: audioReferenceRange,
                        duration: 1,
                        startTime: 0,
                        startTimeTicks: 0,
                        timescale: 1_000
                    )
                ],
                targetDuration: 1,
                bandwidth: 128_000,
                codec: "mp4a.40.2",
                mediaTimeOffset: 0,
                baseMediaDecodeTimeOffsetTicks: 0,
                dynamicRange: .sdr,
                dolbyVisionConfiguration: nil,
                hlsBaseLayerCodec: nil,
                dimensions: nil,
                frameRate: nil
            ),
            masterPlaylistVersion: 7
        )
    }

    private func fetch(_ url: URL, rangeHeader: String? = nil) async throws -> (data: Data, response: HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        if let rangeHeader {
            request.setValue(rangeHeader, forHTTPHeaderField: "Range")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, try XCTUnwrap(response as? HTTPURLResponse))
    }

    private func testData(byteCount: Int, seed: Int = 0) -> Data {
        Data((0..<byteCount).map { UInt8(($0 + seed) % 251) })
    }
}

private final class TestHTTPRangeServer: @unchecked Sendable {
    struct Route: Sendable {
        let data: Data?
        let statusCode: Int
        let reason: String
        let contentType: String
        let responseDelayNanoseconds: UInt64

        static func data(
            _ data: Data,
            contentType: String,
            responseDelayNanoseconds: UInt64 = 0
        ) -> Route {
            Route(
                data: data,
                statusCode: 200,
                reason: "OK",
                contentType: contentType,
                responseDelayNanoseconds: responseDelayNanoseconds
            )
        }

        static func status(_ statusCode: Int, reason: String) -> Route {
            Route(
                data: nil,
                statusCode: statusCode,
                reason: reason,
                contentType: "text/plain; charset=utf-8",
                responseDelayNanoseconds: 0
            )
        }
    }

    struct RecordedRequest: Sendable {
        let path: String
        let rangeHeader: String?
        let headers: [String: String]
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "cc.bili.tests.http-range-server")
    private var routes: [String: Route]
    private var requests: [RecordedRequest] = []
    private var connections: [NWConnection] = []
    private var baseURL: URL?

    init(routes: [String: Route]) throws {
        self.routes = routes
        listener = try NWListener(using: .tcp, on: .any)
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                let continuationGate = ContinuationGate()
                self.listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        guard continuationGate.claim() else { return }
                        if let port = self.listener.port,
                           let url = URL(string: "http://127.0.0.1:\(port.rawValue)") {
                            self.baseURL = url
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: TestHTTPRangeServerError.missingPort)
                        }
                    case let .failed(error):
                        guard continuationGate.claim() else { return }
                        continuation.resume(throwing: error)
                    case .cancelled:
                        break
                    default:
                        break
                    }
                }
                self.listener.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection)
                }
                self.listener.start(queue: self.queue)
            }
        }
    }

    func stop() {
        queue.async {
            self.listener.cancel()
            self.connections.forEach { $0.cancel() }
            self.connections.removeAll(keepingCapacity: false)
        }
    }

    func url(path: String) -> URL {
        guard let baseURL else {
            preconditionFailure("TestHTTPRangeServer must be started before requesting URLs.")
        }
        return baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    func recordedRequests() async -> [RecordedRequest] {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.requests)
            }
        }
    }

    private func handle(_ connection: NWConnection) {
        connections.append(connection)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard case .cancelled = state,
                  let self,
                  let connection
            else { return }
            self.connections.removeAll { $0 === connection }
        }
        connection.start(queue: queue)
        receiveRequest(from: connection, accumulated: Data())
    }

    private func receiveRequest(from connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            guard error == nil else {
                connection.cancel()
                return
            }
            var requestData = accumulated
            if let data {
                requestData.append(data)
            }
            if requestData.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.respond(to: connection, requestData: requestData)
            } else if isComplete || requestData.count > 64 * 1024 {
                self.send(statusCode: 400, reason: "Bad Request", body: Data(), contentType: "text/plain", to: connection)
            } else {
                self.receiveRequest(from: connection, accumulated: requestData)
            }
        }
    }

    private func respond(to connection: NWConnection, requestData: Data) {
        guard let request = TestHTTPRangeRequest(data: requestData) else {
            send(statusCode: 400, reason: "Bad Request", body: Data(), contentType: "text/plain", to: connection)
            return
        }
        requests.append(RecordedRequest(
            path: request.path,
            rangeHeader: request.headers["range"],
            headers: request.headers
        ))
        guard let route = routes[request.path] else {
            send(statusCode: 404, reason: "Not Found", body: Data(), contentType: "text/plain", to: connection)
            return
        }
        guard let data = route.data else {
            send(statusCode: route.statusCode, reason: route.reason, body: Data(route.reason.utf8), contentType: route.contentType, to: connection)
            return
        }
        if let rangeHeader = request.headers["range"],
           let range = HTTPByteRange(httpHeaderValue: rangeHeader)?.clamped(toLength: Int64(data.count)) {
            let start = Int(range.start)
            let end = Int(range.endInclusive)
            let body = data.subdata(in: start..<(end + 1))
            send(
                statusCode: 206,
                reason: "Partial Content",
                body: body,
                contentType: route.contentType,
                responseDelayNanoseconds: route.responseDelayNanoseconds,
                extraHeaders: ["Content-Range": "bytes \(range.start)-\(range.endInclusive)/\(data.count)"],
                to: connection
            )
        } else {
            send(
                statusCode: 200,
                reason: "OK",
                body: data,
                contentType: route.contentType,
                responseDelayNanoseconds: route.responseDelayNanoseconds,
                to: connection
            )
        }
    }

    private func send(
        statusCode: Int,
        reason: String,
        body: Data,
        contentType: String,
        responseDelayNanoseconds: UInt64 = 0,
        extraHeaders: [String: String] = [:],
        to connection: NWConnection
    ) {
        var headers = [
            "Content-Type": contentType,
            "Content-Length": "\(body.count)",
            "Connection": "close",
            "Accept-Ranges": "bytes"
        ]
        extraHeaders.forEach { headers[$0.key] = $0.value }
        let headerText = (["HTTP/1.1 \(statusCode) \(reason)"] + headers.map { "\($0.key): \($0.value)" })
            .joined(separator: "\r\n") + "\r\n\r\n"
        var response = Data(headerText.utf8)
        response.append(body)
        let responseData = response
        let sendResponse: @Sendable () -> Void = {
            connection.send(content: responseData, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
        if responseDelayNanoseconds > 0 {
            queue.asyncAfter(
                deadline: .now() + .nanoseconds(Int(responseDelayNanoseconds)),
                execute: sendResponse
            )
        } else {
            sendResponse()
        }
    }

    private enum TestHTTPRangeServerError: Error {
        case missingPort
    }

    private final class ContinuationGate: @unchecked Sendable {
        private let lock = NSLock()
        private var isClaimed = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !isClaimed else { return false }
            isClaimed = true
            return true
        }
    }
}

private struct TestHTTPRangeRequest {
    let path: String
    let headers: [String: String]

    init?(data: Data) {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        let lines = raw.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }
        path = URLComponents(string: "http://127.0.0.1\(parts[1])")?.path ?? parts[1]
        var parsedHeaders = [String: String]()
        for line in lines.dropFirst() {
            let headerParts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard headerParts.count == 2 else { continue }
            parsedHeaders[headerParts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] =
                headerParts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        headers = parsedHeaders
    }
}
#endif

final class HLSVideoRenditionPlannerTests: XCTestCase {
    @MainActor
    func testAutoAddsSameQualityH264FallbackForHEVCStartup() throws {
        let data = try playURLDataWithHEVCAndH264()
        let startup = try XCTUnwrap(data.playVariants(cdnPreference: .automatic, codecPreference: .auto).first)

        let renditions = HLSVideoRenditionPlanner.codecFallbackRenditions(
            startupVariant: startup,
            playURLData: data,
            cdnPreference: .automatic,
            codecPreference: .auto,
            limit: 2
        )

        XCTAssertEqual(startup.videoStream?.videoCodecFamily, .hevc)
        XCTAssertEqual(renditions.count, 1)
        XCTAssertEqual(renditions.first?.videoStream.videoCodecFamily, .h264)
        XCTAssertEqual(renditions.first?.videoURL.absoluteString, "https://example.com/video-80-avc.m4s")
    }

    @MainActor
    func testForceHEVCKeepsH264OutOfAlternateRenditions() throws {
        let data = try playURLDataWithHEVCAndH264()
        let startup = try XCTUnwrap(data.playVariants(cdnPreference: .automatic, codecPreference: .forceHEVC).first)

        let renditions = HLSVideoRenditionPlanner.codecFallbackRenditions(
            startupVariant: startup,
            playURLData: data,
            cdnPreference: .automatic,
            codecPreference: .forceHEVC,
            limit: 2
        )

        XCTAssertTrue(renditions.isEmpty)
    }

    @MainActor
    func testDisabledCodecsStayOutOfPlayableVariants() throws {
        let data = try playURLDataWithHEVCAndH264()
        let preference = VideoCodecPreference(codecOrder: [.av1])

        let variants = data.playVariants(
            cdnPreference: .automatic,
            codecPreference: preference
        )

        XCTAssertFalse(variants.contains(where: \.isPlayable))
    }

    @MainActor
    func testCodecFallbackVariantKeepsQualityAndAudioButSwapsVideoCodec() throws {
        let data = try playURLDataWithHEVCAndH264()
        let startup = try XCTUnwrap(data.playVariants(cdnPreference: .automatic, codecPreference: .auto).first)

        let fallback = try XCTUnwrap(HLSVideoRenditionPlanner.codecFallbackVariant(
            startupVariant: startup,
            playURLData: data,
            cdnPreference: .automatic,
            codecPreference: .auto
        ))

        XCTAssertEqual(fallback.quality, startup.quality)
        XCTAssertEqual(fallback.title, startup.title)
        XCTAssertEqual(fallback.audioURL, startup.audioURL)
        XCTAssertEqual(fallback.audioStream, startup.audioStream)
        XCTAssertEqual(fallback.videoStream?.videoCodecFamily, .h264)
        XCTAssertEqual(fallback.videoURL?.absoluteString, "https://example.com/video-80-avc.m4s")
        XCTAssertNotEqual(fallback.id, startup.id)
        XCTAssertTrue(fallback.isPlayable)
    }

    @MainActor
    func testProgressiveFallbackVariantKeepsQualityAndUsesSingleStream() throws {
        let data = try playURLDataWithHEVCAndH264AndProgressive()
        let startup = try XCTUnwrap(
            data.playVariants(
                cdnPreference: .automatic,
                codecPreference: .auto,
                requiresHardwareDecode: true
            ).first
        )

        let fallback = try XCTUnwrap(HLSVideoRenditionPlanner.progressiveFallbackVariant(
            startupVariant: startup,
            playURLData: data,
            cdnPreference: .automatic,
            codecPreference: .auto
        ))

        XCTAssertEqual(fallback.quality, startup.quality)
        XCTAssertNil(fallback.audioURL)
        XCTAssertNil(fallback.videoStream)
        XCTAssertTrue(fallback.isProgressiveFastStart)
        XCTAssertEqual(fallback.videoURL?.absoluteString, "https://example.com/video-80-progressive.mp4")
        XCTAssertNotEqual(fallback.id, startup.id)
    }

    @MainActor
    func testProgressiveFallbackContextNamesSingleStreamSwitch() throws {
        let data = try playURLDataWithHEVCAndH264AndProgressive()
        let startup = try XCTUnwrap(
            data.playVariants(
                cdnPreference: .automatic,
                codecPreference: .auto,
                requiresHardwareDecode: true
            ).first
        )
        let fallback = try XCTUnwrap(HLSVideoRenditionPlanner.progressiveFallbackVariant(
            startupVariant: startup,
            playURLData: data,
            cdnPreference: .automatic,
            codecPreference: .auto
        ))

        let context = VideoDetailPlaybackFallbackContext(
            failedVariant: startup,
            fallbackVariant: fallback
        )

        XCTAssertEqual(context.kind, .progressiveStream)
        XCTAssertEqual(context.userMessage, "当前线路播放失败，已切换到 1080P 单流")
        XCTAssertTrue(context.metricParts.contains("fallbackKind=progressiveStream"))
        XCTAssertTrue(context.metricParts.contains("fallbackCodec=Progressive"))
        XCTAssertTrue(context.metricParts.contains("hardwareFallback=progressive"))
        XCTAssertTrue(context.logDescription.contains("toCodec=Progressive"))
    }

    @MainActor
    func testSDRCodecFallbackContextNamesCodecSwitch() throws {
        let data = try playURLDataWithHEVCAndH264()
        let startup = try XCTUnwrap(data.playVariants(cdnPreference: .automatic, codecPreference: .auto).first)
        let fallback = try XCTUnwrap(HLSVideoRenditionPlanner.codecFallbackVariant(
            startupVariant: startup,
            playURLData: data,
            cdnPreference: .automatic,
            codecPreference: .auto
        ))

        let context = VideoDetailPlaybackFallbackContext(
            failedVariant: startup,
            fallbackVariant: fallback
        )

        XCTAssertEqual(context.kind, .sameQualityCodec)
        XCTAssertEqual(context.userMessage, "HEVC 当前不可播放，已切换到 H.264 / SDR")
        XCTAssertTrue(context.metricParts.contains("fallbackKind=sameQualityCodec"))
        XCTAssertTrue(context.metricParts.contains("fallbackCodec=H.264"))
        XCTAssertTrue(context.metricParts.contains("hardwareFallback=sameQualityCodec"))
        XCTAssertTrue(context.logDescription.contains("fromCodec=HEVC"))
        XCTAssertTrue(context.logDescription.contains("toCodec=H.264"))
    }

    @MainActor
    func testHDRCodecFallbackIsOptInForRecoveryOnly() throws {
        let data = try playURLDataWithHDRHEVCAndH264()
        let startup = try XCTUnwrap(data.playVariants(cdnPreference: .automatic, codecPreference: .auto).first)

        let startupRenditions = HLSVideoRenditionPlanner.codecFallbackRenditions(
            startupVariant: startup,
            playURLData: data,
            cdnPreference: .automatic,
            codecPreference: .auto,
            limit: 2
        )
        let recoveryRenditions = HLSVideoRenditionPlanner.codecFallbackRenditions(
            startupVariant: startup,
            playURLData: data,
            cdnPreference: .automatic,
            codecPreference: .auto,
            limit: 2,
            allowsHDRStartupFallback: true
        )

        XCTAssertEqual(startup.dynamicRange, .hdr10)
        XCTAssertTrue(startupRenditions.isEmpty)
        XCTAssertEqual(recoveryRenditions.count, 1)
        XCTAssertEqual(recoveryRenditions.first?.videoStream.videoCodecFamily, .h264)
        XCTAssertEqual(recoveryRenditions.first?.dynamicRange, .sdr)
        XCTAssertEqual(recoveryRenditions.first?.videoURL.absoluteString, "https://example.com/video-125-avc.m4s")
    }

    @MainActor
    func testHDRCodecFallbackVariantKeepsQualityAndAudioButSwapsVideoCodec() throws {
        let data = try playURLDataWithHDRHEVCAndH264()
        let startup = try XCTUnwrap(data.playVariants(cdnPreference: .automatic, codecPreference: .auto).first)

        let fallback = try XCTUnwrap(HLSVideoRenditionPlanner.codecFallbackVariant(
            startupVariant: startup,
            playURLData: data,
            cdnPreference: .automatic,
            codecPreference: .auto,
            allowsHDRStartupFallback: true
        ))

        XCTAssertEqual(fallback.quality, startup.quality)
        XCTAssertEqual(fallback.title, startup.title)
        XCTAssertEqual(fallback.audioURL, startup.audioURL)
        XCTAssertEqual(fallback.audioStream, startup.audioStream)
        XCTAssertEqual(fallback.videoStream?.videoCodecFamily, .h264)
        XCTAssertEqual(fallback.dynamicRange, .sdr)
        XCTAssertFalse(fallback.isHDR)
        XCTAssertEqual(fallback.videoURL?.absoluteString, "https://example.com/video-125-avc.m4s")
        XCTAssertNotEqual(fallback.id, startup.id)
    }

    @MainActor
    func testHDRCodecFallbackContextUsesSDRCodecTarget() throws {
        let data = try playURLDataWithHDRHEVCAndH264()
        let startup = try XCTUnwrap(data.playVariants(cdnPreference: .automatic, codecPreference: .auto).first)
        let fallback = try XCTUnwrap(HLSVideoRenditionPlanner.codecFallbackVariant(
            startupVariant: startup,
            playURLData: data,
            cdnPreference: .automatic,
            codecPreference: .auto,
            allowsHDRStartupFallback: true
        ))

        let context = VideoDetailPlaybackFallbackContext(
            failedVariant: startup,
            fallbackVariant: fallback
        )

        XCTAssertEqual(context.kind, .sameQualityCodec)
        XCTAssertEqual(context.userMessage, "HDR 当前不可播放，已切换到 H.264 / SDR")
        XCTAssertTrue(context.metricParts.contains("fallbackRange=sdr"))
        XCTAssertTrue(context.metricParts.contains("fallbackKind=sameQualityCodec"))
        XCTAssertTrue(context.logDescription.contains("fromRange=hdr10"))
        XCTAssertTrue(context.logDescription.contains("toRange=sdr"))
    }

    private func playURLDataWithHEVCAndH264() throws -> PlayURLData {
        let json = """
        {
            "quality": 80,
            "accept_quality": [80],
            "accept_description": ["1080P"],
            "dash": {
                "video": [
                    {
                        "id": 80,
                        "baseUrl": "https://example.com/video-80-hevc.m4s",
                        "bandwidth": 1800000,
                        "codecs": "hev1.1.6.L120.90",
                        "codecid": 12,
                        "width": 1920,
                        "height": 1080,
                        "frameRate": "30"
                    },
                    {
                        "id": 80,
                        "baseUrl": "https://example.com/video-80-avc.m4s",
                        "bandwidth": 2400000,
                        "codecs": "avc1.640028",
                        "codecid": 7,
                        "width": 1920,
                        "height": 1080,
                        "frameRate": "30"
                    }
                ],
                "audio": [
                    {
                        "id": 30280,
                        "baseUrl": "https://example.com/audio.m4s",
                        "bandwidth": 128000,
                        "codecs": "mp4a.40.2"
                    }
                ]
            }
        }
        """
        return try JSONDecoder().decode(PlayURLData.self, from: Data(json.utf8))
    }

    private func playURLDataWithHEVCAndH264AndProgressive() throws -> PlayURLData {
        let json = """
        {
            "durl": [
                {
                    "url": "https://example.com/video-80-progressive.mp4"
                }
            ],
            "quality": 80,
            "accept_quality": [80],
            "accept_description": ["1080P"],
            "dash": {
                "video": [
                    {
                        "id": 80,
                        "baseUrl": "https://example.com/video-80-hevc.m4s",
                        "bandwidth": 1800000,
                        "codecs": "hev1.1.6.L120.90",
                        "codecid": 12,
                        "width": 1920,
                        "height": 1080,
                        "frameRate": "30"
                    },
                    {
                        "id": 80,
                        "baseUrl": "https://example.com/video-80-avc.m4s",
                        "bandwidth": 2400000,
                        "codecs": "avc1.640028",
                        "codecid": 7,
                        "width": 1920,
                        "height": 1080,
                        "frameRate": "30"
                    }
                ],
                "audio": [
                    {
                        "id": 30280,
                        "baseUrl": "https://example.com/audio.m4s",
                        "bandwidth": 128000,
                        "codecs": "mp4a.40.2"
                    }
                ]
            }
        }
        """
        return try JSONDecoder().decode(PlayURLData.self, from: Data(json.utf8))
    }

    private func playURLDataWithHDRHEVCAndH264() throws -> PlayURLData {
        let json = """
        {
            "quality": 125,
            "accept_quality": [125],
            "accept_description": ["HDR 真彩"],
            "dash": {
                "video": [
                    {
                        "id": 125,
                        "baseUrl": "https://example.com/video-125-hevc.m4s",
                        "bandwidth": 3200000,
                        "codecs": "hev1.2.4.L150.B0",
                        "codecid": 12,
                        "width": 1920,
                        "height": 1080,
                        "frameRate": "30"
                    },
                    {
                        "id": 125,
                        "baseUrl": "https://example.com/video-125-avc.m4s",
                        "bandwidth": 4200000,
                        "codecs": "avc1.64002a",
                        "codecid": 7,
                        "width": 1920,
                        "height": 1080,
                        "frameRate": "30"
                    }
                ],
                "audio": [
                    {
                        "id": 30280,
                        "baseUrl": "https://example.com/audio.m4s",
                        "bandwidth": 128000,
                        "codecs": "mp4a.40.2"
                    }
                ]
            }
        }
        """
        return try JSONDecoder().decode(PlayURLData.self, from: Data(json.utf8))
    }
}
