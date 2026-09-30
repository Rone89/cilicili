import CoreGraphics
import Foundation
import XCTest
@testable import bili

@MainActor
final class HLSBridgeManifestTransportTests: XCTestCase {
    func testVirtualizationRejectsMissingOrMalformedMasterPlaylist() throws {
        let masterURL = try XCTUnwrap(URL(string: "http://127.0.0.1:49153/master.m3u8"))
        let virtualURLForPath: (String) -> URL? = { URL(string: "cilicili-hls://session/test\($0)") }

        XCTAssertThrowsError(try BiliHLSManifestTransportPlan.virtualizedManifests(
            manifestDataByPath: ["/video.m3u8": Data("#EXTM3U".utf8)],
            httpMasterURL: masterURL,
            virtualURLForPath: virtualURLForPath
        ))
        XCTAssertThrowsError(try BiliHLSManifestTransportPlan.virtualizedManifests(
            manifestDataByPath: ["/master.m3u8": Data([0xFF])],
            httpMasterURL: masterURL,
            virtualURLForPath: virtualURLForPath
        ))
    }

    func testVirtualizingMultipleVariantManifestsKeepsMediaURLsOnLoopback() throws {
        let baseURL = try XCTUnwrap(URL(string: "http://127.0.0.1:49153"))
        let videoHEVC = makeFixture(
            routePrefix: "video",
            sourceURL: try XCTUnwrap(URL(string: "https://media.example.test/video-hevc.m4s")),
            mediaType: .video,
            quality: 80,
            bandwidth: 1_800_000,
            codec: "hvc1.1.6.L120.B0",
            dimensions: CGSize(width: 1920, height: 1080),
            initializationRange: HTTPByteRange(start: 0, endInclusive: 49),
            segments: [
                SegmentFixture(range: HTTPByteRange(start: 100, endInclusive: 199), duration: 0.75),
                SegmentFixture(range: HTTPByteRange(start: 200, endInclusive: 399), duration: 1.25)
            ]
        )
        let videoAVC = makeFixture(
            routePrefix: "video-1",
            sourceURL: try XCTUnwrap(URL(string: "https://media.example.test/video-avc.m4s")),
            mediaType: .video,
            quality: 64,
            bandwidth: 1_200_000,
            codec: "avc1.64001F",
            dimensions: CGSize(width: 1280, height: 720),
            initializationRange: HTTPByteRange(start: 0, endInclusive: 49),
            segments: [
                SegmentFixture(range: HTTPByteRange(start: 1_000, endInclusive: 1_099), duration: 1),
                SegmentFixture(range: HTTPByteRange(start: 1_100, endInclusive: 1_299), duration: 2.25)
            ]
        )
        let audio = makeFixture(
            routePrefix: "audio",
            sourceURL: try XCTUnwrap(URL(string: "https://media.example.test/audio-aac.m4s")),
            mediaType: .audio,
            quality: 30_280,
            bandwidth: 128_000,
            codec: "mp4a.40.2",
            dimensions: nil,
            initializationRange: HTTPByteRange(start: 0, endInclusive: 49),
            segments: [
                SegmentFixture(range: HTTPByteRange(start: 50, endInclusive: 99), duration: 1),
                SegmentFixture(range: HTTPByteRange(start: 100, endInclusive: 149), duration: 0.5)
            ]
        )
        let plan = HLSBridgeRoutePlan(
            videoRenditions: [videoHEVC.rendition, videoAVC.rendition],
            audioRendition: audio.rendition,
            masterPlaylistVersion: 7
        )

        let rendered = LocalHLSBridge.renderPlaylists(from: plan, baseURL: baseURL)
        let manifestPaths = ["/master.m3u8", "/video.m3u8", "/video-1.m3u8", "/audio.m3u8"]
        var manifestDataByPath = [String: Data]()
        for path in manifestPaths {
            manifestDataByPath[path] = Data(try playlist(path, in: rendered.routes).utf8)
        }
        let virtualURLForPath: (String) -> URL? = { path in
            URL(string: "cilicili-hls://manifest\(path)")
        }
        let virtualized = try BiliHLSManifestTransportPlan.virtualizedManifests(
            manifestDataByPath: manifestDataByPath,
            httpMasterURL: rendered.masterPlaylistURL,
            virtualURLForPath: virtualURLForPath
        )
        XCTAssertEqual(Set(virtualized.keys), Set(manifestPaths))

        let virtualMasterData = try XCTUnwrap(virtualized["/master.m3u8"])
        let virtualMaster = try XCTUnwrap(String(data: virtualMasterData, encoding: .utf8))
        let virtualAudioURL = try XCTUnwrap(virtualURLForPath("/audio.m3u8"))
        let virtualVideoURLs = try ["/video.m3u8", "/video-1.m3u8"].map {
            try XCTUnwrap(virtualURLForPath($0)).absoluteString
        }
        XCTAssertTrue(virtualMaster.contains("URI=\"\(virtualAudioURL.absoluteString)\""))
        let virtualVideoLinks = virtualMaster.components(separatedBy: .newlines)
            .filter { $0.hasPrefix("cilicili-hls://") }
        XCTAssertEqual(Set(virtualVideoLinks), Set(virtualVideoURLs))
        XCTAssertEqual(virtualMaster.components(separatedBy: "cilicili-hls://").count - 1, 3)
        for path in manifestPaths where path != "/master.m3u8" {
            let sourcePlaylistURL = baseURL.appendingPathComponent(String(path.dropFirst()))
            XCTAssertFalse(virtualMaster.contains(sourcePlaylistURL.absoluteString))
        }

        var allVirtualizedPlaylists = [virtualMaster]
        for fixture in [videoHEVC, videoAVC, audio] {
            let path = "/\(fixture.routePrefix).m3u8"
            let data = try XCTUnwrap(virtualized[path])
            let mediaPlaylist = try XCTUnwrap(String(data: data, encoding: .utf8))
            allVirtualizedPlaylists.append(mediaPlaylist)

            let lines = mediaPlaylist.components(separatedBy: .newlines)
            let mapPrefix = "#EXT-X-MAP:URI=\""
            let mapLine = try XCTUnwrap(lines.first { $0.hasPrefix(mapPrefix) })
            let mapURLText = String(mapLine.dropFirst(mapPrefix.count).dropLast())
            let mapURL = try XCTUnwrap(URL(string: mapURLText))
            assertLoopbackHTTP(mapURL, baseURL: baseURL)
            let initializationPath = "/media/\(fixture.routePrefix)/init.mp4"
            XCTAssertEqual(mapURL.path, initializationPath)
            try assertRemoteRangeRoute(
                initializationPath,
                in: rendered.routes,
                sourceURL: fixture.sourceURL,
                range: fixture.initializationRange,
                contentType: fixture.contentType
            )

            let segmentURLs = lines.filter { !$0.isEmpty && !$0.hasPrefix("#") }
            XCTAssertEqual(segmentURLs.count, fixture.segments.count)
            for (index, rawURL) in segmentURLs.enumerated() {
                let segmentURL = try XCTUnwrap(URL(string: rawURL))
                assertLoopbackHTTP(segmentURL, baseURL: baseURL)
                let segmentPath = "/media/\(fixture.routePrefix)/segment-\(index).m4s"
                XCTAssertEqual(segmentURL.path, segmentPath)
                try assertRemoteRangeRoute(
                    segmentPath,
                    in: rendered.routes,
                    sourceURL: fixture.sourceURL,
                    range: fixture.segments[index].range,
                    contentType: fixture.contentType
                )
            }
        }
        XCTAssertTrue(allVirtualizedPlaylists.allSatisfy { !$0.contains("media.example.test") })
        XCTAssertTrue(allVirtualizedPlaylists.allSatisfy { !$0.contains("https://") })
    }

    private func makeFixture(
        routePrefix: String,
        sourceURL: URL,
        mediaType: HLSBridgeTrack.MediaType,
        quality: Int,
        bandwidth: Int,
        codec: String,
        dimensions: CGSize?,
        initializationRange: HTTPByteRange,
        segments: [SegmentFixture]
    ) -> RenditionFixture {
        var startTime = 0.0
        let references = segments.map { segment in
            defer { startTime += segment.duration }
            return SIDXParser.Reference(
                range: segment.range,
                duration: segment.duration,
                startTime: startTime,
                startTimeTicks: UInt64((startTime * 1_000).rounded()),
                timescale: 1_000
            )
        }
        let contentType: String
        switch mediaType {
        case .audio:
            contentType = "audio/mp4"
        case .video:
            contentType = "video/mp4"
        }
        let rendition = HLSRendition(
            sourceURL: sourceURL,
            fallbackSourceURLs: [],
            mediaType: mediaType,
            quality: quality,
            initialization: initializationRange,
            initializationData: nil,
            references: references,
            targetDuration: segments.map(\.duration).max() ?? 0,
            bandwidth: bandwidth,
            codec: codec,
            mediaTimeOffset: 0,
            baseMediaDecodeTimeOffsetTicks: 0,
            dynamicRange: .sdr,
            dolbyVisionConfiguration: nil,
            hlsBaseLayerCodec: nil,
            dimensions: dimensions,
            frameRate: nil
        )
        return RenditionFixture(
            routePrefix: routePrefix,
            rendition: rendition,
            sourceURL: sourceURL,
            contentType: contentType,
            initializationRange: initializationRange,
            segments: segments
        )
    }

    private func playlist(
        _ path: String,
        in routes: [String: HLSProxyRoute],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        try dataRoute(path, in: routes, file: file, line: line).playlist
    }

    private func dataRoute(
        _ path: String,
        in routes: [String: HLSProxyRoute],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> (playlist: String, contentType: String) {
        let route = try XCTUnwrap(routes[path], "Missing route \(path)", file: file, line: line)
        guard case let .data(data, contentType) = route,
              let playlist = String(data: data, encoding: .utf8)
        else {
            XCTFail("Expected playlist data route at \(path)", file: file, line: line)
            throw TestFailure.unexpectedRoute
        }
        return (playlist, contentType)
    }

    private func assertLoopbackHTTP(_ url: URL, baseURL: URL, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(url.scheme, "http", file: file, line: line)
        XCTAssertEqual(url.host, "127.0.0.1", file: file, line: line)
        XCTAssertEqual(url.port, baseURL.port, file: file, line: line)
    }

    private func assertRemoteRangeRoute(
        _ path: String,
        in routes: [String: HLSProxyRoute],
        sourceURL: URL,
        range: HTTPByteRange,
        contentType: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let route = try XCTUnwrap(routes[path], "Missing media route \(path)", file: file, line: line)
        guard case let .remoteByteRange(url, fallbackURLs, routeRange, routeContentType, transform) = route else {
            XCTFail("Expected remote byte-range route at \(path)", file: file, line: line)
            return
        }
        XCTAssertEqual(url, sourceURL, file: file, line: line)
        XCTAssertTrue(fallbackURLs.isEmpty, file: file, line: line)
        XCTAssertEqual(routeRange, range, file: file, line: line)
        XCTAssertEqual(routeContentType, contentType, file: file, line: line)
        XCTAssertNil(transform, file: file, line: line)
    }

    private struct RenditionFixture {
        let routePrefix: String
        let rendition: HLSRendition
        let sourceURL: URL
        let contentType: String
        let initializationRange: HTTPByteRange
        let segments: [SegmentFixture]
    }

    private struct SegmentFixture {
        let range: HTTPByteRange
        let duration: TimeInterval
    }

    private enum TestFailure: Error {
        case unexpectedRoute
    }
}
