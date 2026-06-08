import XCTest
@testable import bili

final class ResourceLoadingServicesTests: XCTestCase {
    func testPlayURLCacheHonorsTTLAndKeyScope() async throws {
        let cache = PlayURLCache(capacity: 4, ttl: 0.05)
        let scope = loggedInScope(mid: 1001)
        let key = playURLKey(quality: 80)

        await cache.store(try playablePlayURLData(quality: 80), for: key, scope: scope)
        let cachedBeforeTTL = await cache.value(for: key, scope: scope)
        XCTAssertNotNil(cachedBeforeTTL)

        try await Task.sleep(nanoseconds: 80_000_000)
        let cachedAfterTTL = await cache.value(for: key, scope: scope)
        XCTAssertNil(cachedAfterTTL)
    }

    func testPlayURLCacheEvictsLeastRecentlyUsedEntry() async throws {
        let cache = PlayURLCache(capacity: 2, ttl: 60)
        let scope = loggedInScope(mid: 1001)
        let first = playURLKey(bvid: "BV1", cid: 1)
        let second = playURLKey(bvid: "BV2", cid: 2)
        let third = playURLKey(bvid: "BV3", cid: 3)

        await cache.store(try playablePlayURLData(quality: 80), for: first, scope: scope)
        await cache.store(try playablePlayURLData(quality: 80), for: second, scope: scope)
        _ = await cache.value(for: first, scope: scope)
        try await Task.sleep(nanoseconds: 2_000_000)
        await cache.store(try playablePlayURLData(quality: 80), for: third, scope: scope)

        let firstCached = await cache.value(for: first, scope: scope)
        let secondCached = await cache.value(for: second, scope: scope)
        let thirdCached = await cache.value(for: third, scope: scope)
        XCTAssertNotNil(firstCached)
        XCTAssertNil(secondCached)
        XCTAssertNotNil(thirdCached)
    }

    func testPlayURLCacheDistinguishesKeysAndInvalidates() async throws {
        let cache = PlayURLCache(capacity: 4, ttl: 60)
        let scope = loggedInScope(mid: 1001)
        let hdKey = playURLKey(bvid: "BV1", cid: 1, quality: 80)
        let fastStartKey = playURLKey(bvid: "BV1", cid: 1, quality: 64, fnval: "0", platform: "html5", fastStart: true)

        await cache.store(try playablePlayURLData(quality: 80), for: hdKey, scope: scope)

        let hdCached = await cache.value(for: hdKey, scope: scope)
        let fastStartCached = await cache.value(for: fastStartKey, scope: scope)
        XCTAssertNotNil(hdCached)
        XCTAssertNil(fastStartCached)

        await cache.invalidate(bvid: "BV1")
        let invalidatedCached = await cache.value(for: hdKey, scope: scope)
        XCTAssertNil(invalidatedCached)
    }

    func testPlayURLCacheRejectsGuestDataAndClearsForLoginChanges() async throws {
        let cache = PlayURLCache(capacity: 4, ttl: 60)
        let key = playURLKey()
        let guestScope = PlayURLCacheLoginScope(isLoggedIn: false, userMID: nil, guestModeEnabled: true)
        let loggedInScope = loggedInScope(mid: 1001)

        await cache.store(try playablePlayURLData(quality: 80), for: key, scope: guestScope)
        let guestCached = await cache.value(for: key, scope: guestScope)
        XCTAssertNil(guestCached)

        await cache.store(try playablePlayURLData(quality: 80), for: key, scope: loggedInScope)
        let loggedInCached = await cache.value(for: key, scope: loggedInScope)
        XCTAssertNotNil(loggedInCached)

        await cache.invalidateForLoginStateChange()
        let loginInvalidatedCached = await cache.value(for: key, scope: loggedInScope)
        XCTAssertNil(loginInvalidatedCached)
    }

    func testPlayVariantsExposeAdvertisedLockedQualities() throws {
        let json = """
        {
            "quality": 112,
            "accept_quality": [129, 116, 112],
            "accept_description": ["HDR Vivid", "1080P 高帧率", "1080P 高码率"],
            "support_formats": [
                { "quality": 129, "new_description": "HDR Vivid" },
                { "quality": 116, "new_description": "1080P 高帧率" },
                { "quality": 112, "new_description": "1080P 高码率" }
            ],
            "dash": {
                "video": [
                    {
                        "id": 116,
                        "baseUrl": "https://example.com/video-116.m4s",
                        "bandwidth": 2200000,
                        "codecs": "avc1.64002a",
                        "width": 1920,
                        "height": 1080,
                        "frameRate": "60"
                    },
                    {
                        "id": 112,
                        "baseUrl": "https://example.com/video-112.m4s",
                        "bandwidth": 2600000,
                        "codecs": "avc1.640028",
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
        let data = try JSONDecoder().decode(PlayURLData.self, from: Data(json.utf8))
        let variants = data.playVariants
        let highFrameVariant = try XCTUnwrap(variants.first { $0.quality == 116 })
        let playableVariant = try XCTUnwrap(variants.first { $0.quality == 112 })
        let lockedVariant = try XCTUnwrap(variants.first { $0.quality == 129 })

        XCTAssertTrue(highFrameVariant.isPlayable)
        XCTAssertTrue(highFrameVariant.qualityMenuTitle.contains("流畅优先"))
        XCTAssertTrue(highFrameVariant.qualityMenuTitle.contains("帧率 60fps"))
        XCTAssertTrue(playableVariant.isPlayable)
        XCTAssertTrue(playableVariant.qualityMenuTitle.contains("细节优先"))
        XCTAssertTrue(playableVariant.qualityMenuTitle.contains("画质 1920x1080"))
        XCTAssertTrue(playableVariant.qualityMenuTitle.contains("帧率 30fps"))
        XCTAssertTrue(playableVariant.qualityMenuTitle.contains("码率 2.6 Mbps"))
        XCTAssertTrue(playableVariant.qualityMenuTitle.contains("编码 AVC"))
        XCTAssertFalse(lockedVariant.isPlayable)
        XCTAssertEqual(lockedVariant.title, "HDR Vivid")
        XCTAssertTrue(lockedVariant.isHDR)
        XCTAssertTrue(lockedVariant.qualityMenuTitle.contains("需要登录或权限"))
    }

    func testRelatedPlaybackPrefetchPolicyAllowsOnlyWifiHealthyPlayback() {
        let wifi = PlaybackEnvironment(networkClass: .wifi, isLowPowerModeEnabled: false, isThermallyConstrained: false, thermalPressure: .nominal)
        let cellular = PlaybackEnvironment(networkClass: .cellular, isLowPowerModeEnabled: false, isThermallyConstrained: false, thermalPressure: .nominal)
        let lowPower = PlaybackEnvironment(networkClass: .wifi, isLowPowerModeEnabled: true, isThermallyConstrained: false, thermalPressure: .nominal)

        XCTAssertEqual(RelatedPlaybackPrefetchPolicy.candidateLimit(environment: wifi, backgroundPreloadLimit: 4, isPlaying: true, isBuffering: false), 2)
        XCTAssertEqual(RelatedPlaybackPrefetchPolicy.candidateLimit(environment: wifi, backgroundPreloadLimit: 2, isPlaying: true, isBuffering: false), 0)
        XCTAssertEqual(RelatedPlaybackPrefetchPolicy.candidateLimit(environment: cellular, backgroundPreloadLimit: 4, isPlaying: true, isBuffering: false), 0)
        XCTAssertEqual(RelatedPlaybackPrefetchPolicy.candidateLimit(environment: lowPower, backgroundPreloadLimit: 4, isPlaying: true, isBuffering: false), 0)
        XCTAssertEqual(RelatedPlaybackPrefetchPolicy.candidateLimit(environment: wifi, backgroundPreloadLimit: 4, isPlaying: false, isBuffering: false), 0)
        XCTAssertEqual(RelatedPlaybackPrefetchPolicy.candidateLimit(environment: wifi, backgroundPreloadLimit: 4, isPlaying: true, isBuffering: true), 0)
    }

    func testSubtitleAndDanmakuCacheKeysAndCapacity() async {
        let cache = SubtitleDanmakuResourceCache(ttl: 60, subtitleLimit: 1, danmakuLimit: 2, byteCapacity: 4096)
        let firstSubtitle = SubtitleCueCacheKey(bvid: "BV1", cid: 1, subtitleId: "1", language: "zh-CN", urlHash: "a")
        let secondSubtitle = SubtitleCueCacheKey(bvid: "BV1", cid: 1, subtitleId: "1", language: "en", urlHash: "b")

        await cache.storeSubtitleData(Data("zh".utf8), for: firstSubtitle)
        await cache.storeSubtitleData(Data("en".utf8), for: secondSubtitle)

        let firstSubtitleData = await cache.subtitleData(for: firstSubtitle)
        let secondSubtitleData = await cache.subtitleData(for: secondSubtitle)
        XCTAssertNil(firstSubtitleData)
        XCTAssertEqual(secondSubtitleData, Data("en".utf8))

        await cache.storeDanmaku([danmakuItem("first")], for: 1, segmentIndex: 1)
        await cache.storeDanmaku([danmakuItem("second")], for: 1, segmentIndex: 2)
        await cache.storeDanmaku([danmakuItem("third")], for: 1, segmentIndex: 3)

        let firstDanmaku = await cache.danmaku(for: 1, segmentIndex: 1)
        let secondDanmaku = await cache.danmaku(for: 1, segmentIndex: 2)
        let thirdDanmaku = await cache.danmaku(for: 1, segmentIndex: 3)
        XCTAssertNil(firstDanmaku)
        XCTAssertEqual(secondDanmaku?.first?.text, "second")
        XCTAssertEqual(thirdDanmaku?.first?.text, "third")
    }

    func testProgressiveMediaSegmentCacheHonorsCapacityAndKeys() async {
        let cache = ProgressiveMediaSegmentCache(byteCapacity: 12, itemLimit: 2, maxEntryBytes: 8, ttl: 60)
        let firstKey = ProgressiveMediaCacheKey(url: "https://example.com/a.mp4", rangeHeader: "bytes=0-3")
        let secondKey = ProgressiveMediaCacheKey(url: "https://example.com/a.mp4", rangeHeader: "bytes=4-7")
        let thirdKey = ProgressiveMediaCacheKey(url: "https://example.com/b.mp4", rangeHeader: "bytes=0-3")

        await cache.store(progressiveResponse("1111"), for: firstKey)
        await cache.store(progressiveResponse("2222"), for: secondKey)
        _ = await cache.response(for: firstKey)
        await cache.store(progressiveResponse("3333"), for: thirdKey)

        let first = await cache.response(for: firstKey)
        let second = await cache.response(for: secondKey)
        let third = await cache.response(for: thirdKey)
        XCTAssertEqual(first?.data, Data("1111".utf8))
        XCTAssertNil(second)
        XCTAssertEqual(third?.data, Data("3333".utf8))
    }

    func testURLSessionConfigurationAndHeaders() {
        let apiSession = BiliURLSessionFactory.makeAPISession()
        XCTAssertEqual(apiSession.configuration.timeoutIntervalForRequest, 12)
        XCTAssertEqual(apiSession.configuration.timeoutIntervalForResource, 40)
        XCTAssertEqual(apiSession.configuration.httpMaximumConnectionsPerHost, 6)
        XCTAssertTrue(apiSession.configuration.waitsForConnectivity)
        XCTAssertNotNil(apiSession.configuration.urlCache)

        let playbackSession = BiliURLSessionFactory.makePlaybackResourceSession()
        XCTAssertEqual(playbackSession.configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(playbackSession.configuration.httpMaximumConnectionsPerHost, 4)
        XCTAssertNil(playbackSession.configuration.urlCache)

        let apiHeaders = BiliURLSessionFactory.apiHeaders(
            referer: "https://www.bilibili.com/video/BV1",
            userAgent: nil,
            cookieHeader: "SESSDATA=secret"
        )
        XCTAssertEqual(apiHeaders["Referer"], "https://www.bilibili.com/video/BV1")
        XCTAssertEqual(apiHeaders["Origin"], "https://www.bilibili.com")
        XCTAssertEqual(apiHeaders["Cookie"], "SESSDATA=secret")
        XCTAssertEqual(apiHeaders["Accept"], "application/json, text/plain, */*")

        let playbackHeaders = BiliURLSessionFactory.playbackHeaders(
            referer: "https://www.bilibili.com/video/BV1",
            cookieHeader: "SESSDATA=secret"
        )
        XCTAssertEqual(playbackHeaders["Referer"], "https://www.bilibili.com/video/BV1")
        XCTAssertEqual(playbackHeaders["Cookie"], "SESSDATA=secret")
        XCTAssertNil(playbackHeaders["Origin"])
    }

    private func playablePlayURLData(quality: Int) throws -> PlayURLData {
        let json = """
        {
            "durl": [
                {
                    "url": "https://example.com/video-\(quality).mp4"
                }
            ],
            "quality": \(quality),
            "accept_quality": [\(quality)],
            "accept_description": ["测试清晰度"]
        }
        """
        return try JSONDecoder().decode(PlayURLData.self, from: Data(json.utf8))
    }

    private func playURLKey(
        bvid: String = "BV1",
        cid: Int = 1,
        quality: Int = 80,
        fnval: String = "4048",
        fnver: String = "0",
        platform: String = "pc",
        fastStart: Bool = false,
        supplements: Bool = true
    ) -> PlayURLCacheKey {
        PlayURLCacheKey(
            bvid: bvid,
            cid: cid,
            requestedQuality: quality,
            audioLanguage: "default",
            fnval: fnval,
            fnver: fnver,
            platform: platform,
            prefersProgressiveFastStart: fastStart,
            supplementsQualities: supplements
        )
    }

    private func loggedInScope(mid: Int) -> PlayURLCacheLoginScope {
        PlayURLCacheLoginScope(isLoggedIn: true, userMID: mid, guestModeEnabled: false)
    }

    private func danmakuItem(_ text: String) -> DanmakuItem {
        DanmakuItem(
            id: text,
            time: 1,
            mode: 1,
            fontSize: 25,
            color: 0x00FF_FFFF,
            text: text
        )
    }

    private func progressiveResponse(_ text: String) -> ProgressiveMediaCacheResponse {
        let data = Data(text.utf8)
        return ProgressiveMediaCacheResponse(
            data: data,
            contentLength: Int64(data.count),
            mimeType: "video/mp4",
            isByteRangeAccessSupported: true
        )
    }
}
