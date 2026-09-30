import XCTest
@testable import bili

final class BiliHLSManifestResourceLoaderTests: XCTestCase {
    @MainActor
    func testVirtualURLsUseSessionUUIDAndManifestPath() throws {
        let sessionID = try XCTUnwrap(UUID(uuidString: "A1B2C3D4-1111-2222-3333-ABCDEF012345"))
        let loader = BiliHLSManifestResourceLoader(
            manifestsByPath: ["/master.m3u8": Data("#EXTM3U".utf8)],
            sessionID: sessionID
        )
        let videoURL = try XCTUnwrap(
            BiliHLSManifestResourceLoader.virtualURL(forPath: "/video.m3u8", sessionID: sessionID)
        )

        XCTAssertEqual(
            loader.assetURL.absoluteString,
            "cilicili-hls://session/a1b2c3d4-1111-2222-3333-abcdef012345/master.m3u8"
        )
        XCTAssertEqual(
            videoURL.absoluteString,
            "cilicili-hls://session/a1b2c3d4-1111-2222-3333-abcdef012345/video.m3u8"
        )
        XCTAssertEqual(
            BiliHLSManifestResourceLoader.manifestPath(from: videoURL, sessionID: sessionID),
            "/video.m3u8"
        )
    }

    @MainActor
    func testVirtualURLRejectsInvalidManifestPathsAndSessionMismatch() throws {
        let sessionID = try XCTUnwrap(UUID(uuidString: "A1B2C3D4-1111-2222-3333-ABCDEF012345"))
        for path in [
            "master.m3u8",
            "/../master.m3u8",
            "/folder//master.m3u8",
            "/segment.m4s",
            "/master.m3u8?token=secret"
        ] {
            XCTAssertNil(
                BiliHLSManifestResourceLoader.virtualURL(forPath: path, sessionID: sessionID),
                "Unexpected virtual URL for \(path)"
            )
        }

        let otherSessionID = try XCTUnwrap(UUID(uuidString: "B1B2C3D4-1111-2222-3333-ABCDEF012345"))
        let url = try XCTUnwrap(
            BiliHLSManifestResourceLoader.virtualURL(forPath: "/audio.m3u8", sessionID: sessionID)
        )
        XCTAssertNil(BiliHLSManifestResourceLoader.manifestPath(from: url, sessionID: otherSessionID))
        XCTAssertNil(
            BiliHLSManifestResourceLoader.manifestPath(
                from: try XCTUnwrap(URL(string: url.absoluteString + "?token=secret")),
                sessionID: sessionID
            )
        )
    }

    @MainActor
    func testResponseRangeHonorsCurrentOffsetAndRequestedEnd() {
        XCTAssertEqual(
            BiliHLSManifestResourceLoader.responseRange(
                resourceLength: 100,
                requestedOffset: 10,
                currentOffset: 15,
                requestedLength: 20,
                requestsAllDataToEndOfResource: false
            ),
            15..<30
        )
        XCTAssertEqual(
            BiliHLSManifestResourceLoader.responseRange(
                resourceLength: 100,
                requestedOffset: 10,
                currentOffset: 15,
                requestedLength: 20,
                requestsAllDataToEndOfResource: true
            ),
            15..<100
        )
        XCTAssertNil(
            BiliHLSManifestResourceLoader.responseRange(
                resourceLength: 100,
                requestedOffset: 10,
                currentOffset: 31,
                requestedLength: 20,
                requestsAllDataToEndOfResource: false
            )
        )
    }
}
