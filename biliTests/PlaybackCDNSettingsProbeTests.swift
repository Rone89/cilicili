import XCTest
@testable import bili

final class PlaybackCDNSettingsProbeTests: XCTestCase {
    func testUsesLatestRecordedVideoWithValidCID() {
        let progress = [
            item("BVold", cid: 1, time: 1),
            item("BVlatest", cid: 2, time: 2),
            item("BVmissing", cid: nil, time: 3),
            item(" ", cid: 4, time: 4),
            item("BVinvalid", cid: 0, time: 5),
        ]
        XCTAssertEqual(
            PlaybackCDNSettingsProbe.latestVideo(in: progress),
            PlaybackCDNProbeVideo(bvid: "BVlatest", cid: 2)
        )
        XCTAssertNil(PlaybackCDNSettingsProbe.latestVideo(in: []))
    }

    func testKeepsSignedURLsAndActualBackupsWithoutInventingHosts() throws {
        let urls = PlaybackCDNSettingsProbe.playbackURLs(in: try media())
        XCTAssertEqual(urls.map(\.absoluteString), [
            "https://video.example.test/v.m4s?deadline=2000000000&token=video",
            "https://backup.example.test/v.m4s?deadline=2000000000&token=backup",
            "https://audio.example.test/a.m4s?token=audio",
            "https://progressive.example.test/v.mp4?token=progressive",
        ])
    }

    func testFetchesVideoThenPassesRealURLsAndProtocolToProbe() async throws {
        let data = try media()
        let video = PlaybackCDNProbeVideo(bvid: "BVlatest", cid: 2)
        let expected = PlaybackCDNProbeSnapshot(
            probedAt: Date(timeIntervalSince1970: 123), recommendedPreference: nil, results: []
        )
        let result = try await PlaybackCDNSettingsProbe.run(
            video: video,
            addressFamilyPreference: .ipv4Only,
            fetchPlayURL: { input in
                XCTAssertEqual(input, video)
                return data
            },
            probe: { family, urls in
                XCTAssertEqual(family, .ipv4Only)
                XCTAssertEqual(urls, PlaybackCDNSettingsProbe.playbackURLs(in: data))
                XCTAssertFalse(urls.isEmpty)
                return expected
            }
        )
        XCTAssertEqual(result, expected)
    }

    func testEmptyMediaDoesNotFallBackToBareHostProbe() async throws {
        let data = try JSONDecoder().decode(PlayURLData.self, from: Data("{}".utf8))
        do {
            _ = try await PlaybackCDNSettingsProbe.run(
                video: PlaybackCDNProbeVideo(bvid: "BVempty", cid: 1),
                addressFamilyPreference: .automatic,
                fetchPlayURL: { _ in data },
                probe: { _, _ in
                    XCTFail("Empty media must not trigger a bare-host probe")
                    return PlaybackCDNProbeSnapshot(probedAt: Date(), recommendedPreference: nil, results: [])
                }
            )
            XCTFail("Expected unavailable media")
        } catch PlaybackCDNSettingsProbe.Failure.noPlayableURL {
        }
    }

    func testCancellationAfterFetchDoesNotStartProbe() async throws {
        let data = try media()
        let task = Task {
            try await PlaybackCDNSettingsProbe.run(
                video: PlaybackCDNProbeVideo(bvid: "BVcancel", cid: 1),
                addressFamilyPreference: .automatic,
                fetchPlayURL: { _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                    return data
                },
                probe: { _, _ in
                    XCTFail("Cancelled fetch must not start probing")
                    return PlaybackCDNProbeSnapshot(probedAt: Date(), recommendedPreference: nil, results: [])
                }
            )
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        }
    }

    @MainActor
    func testPreviouslyRecordedVideoIsAvailableAfterStoreRestoration() throws {
        let suite = "PlaybackCDNSettingsProbeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let progress = item("BVrestored", cid: 22, time: 1)
        defaults.set(
            try JSONEncoder().encode([progress.bvid: progress]),
            forKey: "cc.bili.playback.progressByBVID.v1"
        )
        let library = LibraryStore(userDefaults: defaults)
        XCTAssertEqual(library.recentPlaybackCDNProbeVideo, PlaybackCDNProbeVideo(bvid: "BVrestored", cid: 22))
    }

    private func item(_ bvid: String, cid: Int?, time: TimeInterval) -> StoredPlaybackProgress {
        StoredPlaybackProgress(
            bvid: bvid, cid: cid, playbackTime: 10, playbackDuration: 100,
            updatedAt: Date(timeIntervalSince1970: time)
        )
    }

    private func media() throws -> PlayURLData {
        try JSONDecoder().decode(PlayURLData.self, from: Data(#"""
        {
          "dash": {
            "video": [{"baseUrl":"https://video.example.test/v.m4s?deadline=2000000000&token=video",
              "backupUrl":["https://video.example.test/v.m4s?deadline=2000000000&token=video",
                "https://backup.example.test/v.m4s?deadline=2000000000&token=backup", "file:///tmp/not-media"]}],
            "audio": [{"baseUrl":"https://audio.example.test/a.m4s?token=audio"}]
          },
          "durl": [{"url":"https://progressive.example.test/v.mp4?token=progressive"}]
        }
        """#.utf8))
    }
}
