import XCTest
@testable import bili

final class ResourceLoadingServicesTests: XCTestCase {
    private var previousCodecPreference: Any?

    override func setUp() {
        super.setUp()
        previousCodecPreference = UserDefaults.standard.object(
            forKey: VideoCodecPreference.storageKey
        )
        UserDefaults.standard.set(
            VideoCodecPreference.auto.rawValue,
            forKey: VideoCodecPreference.storageKey
        )
    }

    override func tearDown() {
        if let previousCodecPreference {
            UserDefaults.standard.set(
                previousCodecPreference,
                forKey: VideoCodecPreference.storageKey
            )
        } else {
            UserDefaults.standard.removeObject(forKey: VideoCodecPreference.storageKey)
        }
        super.tearDown()
    }

    func testWebPagePlayInfoStreamParserExtractsAcrossChunkBoundaries() throws {
        var parser = BiliWebPagePlayInfoStreamParser()
        let first = Data("<html><script>window.__playin".utf8)
        let second = Data("fo__={\"data\":{\"title\":\"brace } and escaped \\\" quote\",\"dash\":{\"video\":[1]}}".utf8)
        let third = Data("};window.__INITIAL_STATE__={}</script><body>rest</body>".utf8)

        XCTAssertNil(parser.append(first))
        XCTAssertNil(parser.append(second))
        let json = try XCTUnwrap(parser.append(third))

        XCTAssertEqual(
            json,
            "{\"data\":{\"title\":\"brace } and escaped \\\" quote\",\"dash\":{\"video\":[1]}}}"
        )
        XCTAssertLessThan(parser.buffer.count, first.count + second.count + third.count + 1)
    }

    func testWebPagePlayInfoStreamParserIgnoresBracesInsideStrings() throws {
        var parser = BiliWebPagePlayInfoStreamParser()
        let html = Data("prefix __playinfo__={\"value\":\"{nested}\",\"ok\":true};suffix".utf8)

        let json = try XCTUnwrap(parser.append(html))

        XCTAssertEqual(json, "{\"value\":\"{nested}\",\"ok\":true}")
    }

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
        let differentKey = playURLKey(bvid: "BV1", cid: 1, quality: 64, fnval: "0", platform: "html5")

        await cache.store(try playablePlayURLData(quality: 80), for: hdKey, scope: scope)

        let hdCached = await cache.value(for: hdKey, scope: scope)
        let differentCached = await cache.value(for: differentKey, scope: scope)
        XCTAssertNotNil(hdCached)
        XCTAssertNil(differentCached)

        await cache.invalidate(bvid: "BV1")
        let invalidatedCached = await cache.value(for: hdKey, scope: scope)
        XCTAssertNil(invalidatedCached)
    }

    func testPlayURLCacheKeepsFallbackOutOfRequestedQualityHits() async throws {
        let cache = PlayURLCache(capacity: 4, ttl: 60)
        let scope = loggedInScope(mid: 1001)
        let targetKey = playURLKey(quality: 112)

        await cache.store(try playablePlayURLData(quality: 80), for: targetKey, scope: scope)

        let targetHit = await cache.value(
            for: targetKey,
            scope: scope,
            requiredQuality: 112
        )
        let fallback = await cache.playableFallback(
            bvid: targetKey.bvid,
            cid: targetKey.cid,
            scope: scope
        )

        XCTAssertNil(targetHit)
        XCTAssertEqual(fallback?.quality, 80)
    }

    func testPlayURLCacheReusesOnlyVerifiedUnavailableQualityFallback() async throws {
        let cache = PlayURLCache(capacity: 4, ttl: 60)
        let scope = loggedInScope(mid: 1001)
        let targetKey = playURLKey(quality: 112)

        await cache.store(try playablePlayURLData(quality: 80), for: targetKey, scope: scope)

        let strictHit = await cache.value(
            for: targetKey,
            scope: scope,
            requiredQuality: 112
        )
        let verifiedFallbackHit = await cache.value(
            for: targetKey,
            scope: scope,
            requiredQuality: 112,
            allowsVerifiedLowerQualityFallback: true
        )

        XCTAssertNil(strictHit)
        XCTAssertEqual(verifiedFallbackHit?.quality, 80)
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

    func testPlayURLCacheDoesNotReuseDataAcrossCredentialVersions() async throws {
        let cache = PlayURLCache(capacity: 4, ttl: 60)
        let key = playURLKey()
        let firstScope = PlayURLCacheLoginScope(
            isLoggedIn: true,
            userMID: 1001,
            guestModeEnabled: false,
            credentialVersion: 1
        )
        let refreshedScope = PlayURLCacheLoginScope(
            isLoggedIn: true,
            userMID: 1001,
            guestModeEnabled: false,
            credentialVersion: 2
        )

        await cache.store(try playablePlayURLData(quality: 80), for: key, scope: firstScope)

        let cachedAfterCredentialRefresh = await cache.value(for: key, scope: refreshedScope)
        XCTAssertNil(cachedAfterCredentialRefresh)
    }

    func testPlayURLMediaExpirationUsesEarliestMediaURLDeadline() throws {
        let storedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let videoDeadline = Int(storedAt.timeIntervalSince1970 + 600)
        let audioDeadline = String(Int(storedAt.timeIntervalSince1970 + 3_600), radix: 16)
        let json = """
        {
            "quality": 80,
            "dash": {
                "video": [
                    {
                        "id": 80,
                        "baseUrl": "https://upos.example.test/video.m4s?deadline=\(videoDeadline)",
                        "backupUrl": ["https://backup.example.test/video.m4s?wstime=\(audioDeadline)"],
                        "bandwidth": 1800000,
                        "codecs": "hev1.1.6.L120.90",
                        "codecid": 12
                    }
                ],
                "audio": [
                    {
                        "id": 30280,
                        "baseUrl": "https://upos.example.test/audio.m4s?wstime=\(audioDeadline)",
                        "bandwidth": 128000,
                        "codecs": "mp4a.40.2"
                    }
                ]
            }
        }
        """
        let data = try JSONDecoder().decode(PlayURLData.self, from: Data(json.utf8))

        let expiresAt = PlayURLMediaExpiration.expirationDate(for: data, storedAt: storedAt, fallbackTTL: 7_200)

        XCTAssertTrue(PlayURLMediaExpiration.usesMediaURLExpiration(for: data))
        XCTAssertEqual(
            expiresAt.timeIntervalSince1970,
            TimeInterval(videoDeadline) - PlayURLMediaExpiration.safetyMargin,
            accuracy: 0.001
        )
    }

    func testAuthoritativeUnavailablePreferredQualityUsesNextLowerStartupFallback() throws {
        let data = try playablePlayURLData(quality: 112)

        XCTAssertTrue(
            BiliAPIClient.canUseUnavailablePreferredStartupFallback(
                data,
                requestedQuality: 116,
                isAuthoritativeSource: true
            )
        )
    }

    func testAuthoritativeUnavailablePreferredQualityUsesHighestAdvertisedFallback() throws {
        let data = try playablePlayURLData(quality: 80)

        XCTAssertTrue(
            BiliAPIClient.canUseUnavailablePreferredStartupFallback(
                data,
                requestedQuality: 116,
                isAuthoritativeSource: true
            )
        )
    }

    func testWebPageUnavailablePreferredQualityDoesNotUseStartupFallback() throws {
        let data = try playablePlayURLData(quality: 80)

        XCTAssertFalse(
            BiliAPIClient.canUseUnavailablePreferredStartupFallback(
                data,
                requestedQuality: 116,
                isAuthoritativeSource: false
            )
        )
    }

    func testAdvertisedPreferredQualityDoesNotUseIncompleteStartupFallback() throws {
        let json = """
        {
            "quality": 80,
            "accept_quality": [116, 80],
            "accept_description": ["1080P 60帧", "1080P"],
            "durl": [
                {
                    "url": "https://example.com/video-80.mp4"
                }
            ]
        }
        """
        let data = try JSONDecoder().decode(PlayURLData.self, from: Data(json.utf8))

        XCTAssertFalse(
            BiliAPIClient.canUseUnavailablePreferredStartupFallback(
                data,
                requestedQuality: 116,
                isAuthoritativeSource: true
            )
        )
    }

    func testAdvertisedMissingQualityRequestsAnotherPlaybackResponse() throws {
        let defaults = UserDefaults.standard
        let previousCodecPreference = defaults.object(forKey: VideoCodecPreference.storageKey)
        defaults.set(
            VideoCodecPreference.forceH264.rawValue,
            forKey: VideoCodecPreference.storageKey
        )
        defer {
            if let previousCodecPreference {
                defaults.set(previousCodecPreference, forKey: VideoCodecPreference.storageKey)
            } else {
                defaults.removeObject(forKey: VideoCodecPreference.storageKey)
            }
        }

        let json = """
        {
            "quality": 32,
            "accept_quality": [112, 80, 32],
            "accept_description": ["1080P 高码率", "1080P 高清", "480P 标清"],
            "dash": {
                "video": [
                    {
                        "id": 32,
                        "baseUrl": "https://example.com/video-32.m4s",
                        "bandwidth": 320000,
                        "codecs": "avc1.64001e",
                        "width": 852,
                        "height": 480,
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

        XCTAssertTrue(data.shouldRefetchForPreferredQuality(112))
        XCTAssertTrue(data.shouldRefetchForPreferredQuality(80))
        XCTAssertFalse(data.shouldRefetchForPreferredQuality(32))
    }

    @MainActor
    func testSessionStorePreservesCurrentSESSDATAWhenCookiesArePartiallyUpdated() throws {
        let keychain = KeychainStore(service: "cc.bili.tests.session.\(UUID().uuidString)")
        let store = SessionStore(keychain: keychain)
        defer { try? store.logout() }

        try store.saveLoginCookies([
            "SESSDATA": "old-session",
            "DedeUserID": "1001",
            "bili_jct": "csrf"
        ])
        try store.saveSESSDATA("fresh-session")
        try store.saveLoginCookies([
            "bili_ticket": "ticket",
            "DedeUserID": "1001"
        ])

        let header = store.cookieHeader()
        XCTAssertTrue(store.isLoggedIn)
        XCTAssertTrue(header.contains("SESSDATA=fresh-session"))
        XCTAssertFalse(header.contains("SESSDATA=old-session"))
        XCTAssertEqual(header.components(separatedBy: "SESSDATA=").count - 1, 1)
        XCTAssertTrue(header.contains("bili_ticket=ticket"))
    }

    @MainActor
    func testSessionStoreDropsOldAccountCookiesWhenSESSDATAChanges() throws {
        let keychain = KeychainStore(service: "cc.bili.tests.session.\(UUID().uuidString)")
        let store = SessionStore(keychain: keychain)
        defer { try? store.logout() }

        try store.saveLoginCookies([
            "SESSDATA": "old-session",
            "DedeUserID": "1001",
            "bili_jct": "old-csrf",
            "bili_ticket": "old-ticket"
        ])
        try store.saveLoginCookies([
            "SESSDATA": "fresh-session",
            "DedeUserID": "2002"
        ])

        let header = store.cookieHeader()
        XCTAssertTrue(header.contains("SESSDATA=fresh-session"))
        XCTAssertTrue(header.contains("DedeUserID=2002"))
        XCTAssertFalse(header.contains("old-csrf"))
        XCTAssertFalse(header.contains("old-ticket"))
    }

    func testPlayVariantsExposeAdvertisedOnDemandQualities() throws {
        let json = """
        {
            "quality": 112,
            "accept_quality": [129, 116, 112],
            "accept_description": ["HDR Vivid", "1080P 高帧率", "1080P 高码率"],
            "support_formats": [
                { "quality": 129, "new_description": "HDR Vivid", "codecs": ["hev1.2.4.L153.90"] },
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
        let variants = data.playVariants(cdnPreference: .automatic, codecPreference: .auto)
        let highFrameVariant = try XCTUnwrap(variants.first { $0.quality == 116 })
        let playableVariant = try XCTUnwrap(variants.first { $0.quality == 112 })
        let onDemandVariant = try XCTUnwrap(variants.first { $0.quality == 129 })

        XCTAssertTrue(highFrameVariant.isPlayable)
        XCTAssertEqual(highFrameVariant.qualityMenuTitle, "1080P 高帧率")
        XCTAssertTrue(highFrameVariant.subtitle.contains("60fps"))
        XCTAssertTrue(playableVariant.isPlayable)
        XCTAssertEqual(playableVariant.qualityMenuTitle, "1080P 高码率")
        XCTAssertTrue(playableVariant.subtitle.contains("1920x1080"))
        XCTAssertTrue(playableVariant.subtitle.contains("30fps"))
        XCTAssertTrue(playableVariant.subtitle.contains("2.6 Mbps"))
        XCTAssertTrue(playableVariant.subtitle.contains("AVC"))
        XCTAssertFalse(onDemandVariant.isPlayable)
        XCTAssertTrue(onDemandVariant.isAvailabilityPending)
        XCTAssertTrue(onDemandVariant.isSelectableFromQualityMenu)
        XCTAssertEqual(onDemandVariant.title, "HDR Vivid")
        XCTAssertEqual(onDemandVariant.subtitle, "HEVC · HDR")
        XCTAssertTrue(onDemandVariant.isHDR)
        XCTAssertFalse(onDemandVariant.qualityMenuTitle.contains("需要登录或权限"))
    }

    func testDashAudioMergesDolbyAndPrefersAACForPlayback() throws {
        let json = """
        {
            "quality": 126,
            "accept_quality": [126],
            "accept_description": ["杜比视界"],
            "dash": {
                "video": [
                    {
                        "id": 126,
                        "baseUrl": "https://example.com/dolby-video.m4s",
                        "bandwidth": 8000000,
                        "codecs": "dvh1.08.06",
                        "width": 3840,
                        "height": 2160,
                        "frameRate": "30"
                    }
                ],
                "audio": [
                    {
                        "id": 30280,
                        "baseUrl": "https://example.com/audio-aac.m4s",
                        "bandwidth": 128000,
                        "codecs": "mp4a.40.2"
                    }
                ],
                "dolby": {
                    "audio": [
                        {
                            "id": 30250,
                            "baseUrl": "https://example.com/audio-dolby.m4s",
                            "bandwidth": 448000,
                            "codecs": "ec-3"
                        }
                    ]
                }
            }
        }
        """

        let data = try JSONDecoder().decode(PlayURLData.self, from: Data(json.utf8))
        XCTAssertEqual(data.dash?.audio?.count, 2)
        XCTAssertEqual(data.dash?.bestAudioStream?.codecs, "mp4a.40.2")
        XCTAssertTrue(data.rawPlayURLSummary.contains("dolbyAudio=1"))
    }

    func testHardwareDecodePreferenceFallsBackToProgressiveWhenNoHardwareVariantExists() throws {
        let data = try playablePlayURLData(quality: 80)

        let defaultVariants = data.playVariants(
            cdnPreference: .automatic,
            codecPreference: .auto,
            requiresHardwareDecode: false
        )
        let forcedVariants = data.playVariants(
            cdnPreference: .automatic,
            codecPreference: .auto,
            requiresHardwareDecode: true
        )

        XCTAssertTrue(defaultVariants.contains(where: \.isPlayable))
        XCTAssertFalse(defaultVariants.contains(where: \.isHardwareDecodingCompatible))
        XCTAssertTrue(forcedVariants.contains(where: \.isPlayable))
        XCTAssertTrue(forcedVariants.contains(where: \.isProgressiveFastStart))
        XCTAssertFalse(forcedVariants.contains(where: \.isHardwareDecodingCompatible))
    }

    func testHardwareDecodePreferenceKeepsHardwareDashBeforeProgressiveFallback() throws {
        let json = """
        {
            "durl": [
                {
                    "url": "https://example.com/video-progressive.mp4"
                }
            ],
            "quality": 80,
            "accept_quality": [80],
            "accept_description": ["1080P"],
            "dash": {
                "video": [
                    {
                        "id": 80,
                        "baseUrl": "https://upos.example.test/video-avc.m4s",
                        "bandwidth": 1800000,
                        "codecs": "avc1.640028",
                        "codecid": 7
                    }
                ],
                "audio": [
                    {
                        "id": 30280,
                        "baseUrl": "https://upos.example.test/audio-aac.m4s",
                        "bandwidth": 128000,
                        "codecs": "mp4a.40.2"
                    }
                ]
            }
        }
        """
        let data = try JSONDecoder().decode(PlayURLData.self, from: Data(json.utf8))

        let variants = data.playVariants(
            cdnPreference: .automatic,
            codecPreference: .auto,
            requiresHardwareDecode: true
        )

        XCTAssertTrue(variants.contains(where: \.isHardwareDecodingCompatible))
        XCTAssertFalse(variants.contains(where: \.isProgressiveFastStart))
    }

    func testDashPlaybackFixturePreservesSegmentBaseBackupAndCodecPriority() throws {
        let json = """
        {
            "quality": 80,
            "accept_quality": [80],
            "accept_description": ["1080P"],
            "dash": {
                "video": [
                    {
                        "id": 80,
                        "baseUrl": "https://upos.example.test/video-hevc.m4s",
                        "backupUrl": ["https://backup.example.test/video-hevc.m4s"],
                        "bandwidth": 1800000,
                        "codecs": "hev1.1.6.L120.90",
                        "codecid": 12,
                        "width": 1920,
                        "height": 1080,
                        "frameRate": "30000/1001",
                        "mimeType": "video/mp4",
                        "SegmentBase": {
                            "Initialization": "0-999",
                            "indexRange": "1000-1499"
                        }
                    },
                    {
                        "id": 80,
                        "baseUrl": "https://upos.example.test/video-avc.m4s",
                        "backupUrl": ["https://backup.example.test/video-avc.m4s"],
                        "bandwidth": 2400000,
                        "codecs": "avc1.640028",
                        "codecid": 7,
                        "width": 1920,
                        "height": 1080,
                        "frameRate": "30",
                        "mimeType": "video/mp4",
                        "SegmentBase": {
                            "Initialization": "0-899",
                            "indexRange": "900-1299"
                        }
                    }
                ],
                "audio": [
                    {
                        "id": 30280,
                        "baseUrl": "https://upos.example.test/audio-aac.m4s",
                        "backupUrl": ["https://backup.example.test/audio-aac.m4s"],
                        "bandwidth": 128000,
                        "codecs": "mp4a.40.2",
                        "mimeType": "audio/mp4",
                        "SegmentBase": {
                            "Initialization": "0-299",
                            "indexRange": "300-599"
                        }
                    }
                ]
            }
        }
        """

        let data = try JSONDecoder().decode(PlayURLData.self, from: Data(json.utf8))
        let variant = try XCTUnwrap(data.playVariants(cdnPreference: .automatic, codecPreference: .auto).first)
        let videoStream = try XCTUnwrap(variant.videoStream)
        let audioStream = try XCTUnwrap(variant.audioStream)

        XCTAssertEqual(videoStream.videoCodecFamily, .hevc)
        XCTAssertEqual(variant.videoURL?.absoluteString, "https://upos.example.test/video-hevc.m4s")
        XCTAssertEqual(videoStream.backupPlayURLs.map(\.absoluteString), ["https://backup.example.test/video-hevc.m4s"])
        XCTAssertEqual(videoStream.segmentBase?.initializationByteRange, HTTPByteRange(start: 0, endInclusive: 999))
        XCTAssertEqual(videoStream.segmentBase?.indexByteRange, HTTPByteRange(start: 1_000, endInclusive: 1_499))
        XCTAssertEqual(videoStream.displayFrameRate, "30")
        XCTAssertEqual(audioStream.codecs, "mp4a.40.2")
        XCTAssertEqual(audioStream.backupPlayURLs.map(\.absoluteString), ["https://backup.example.test/audio-aac.m4s"])
        XCTAssertEqual(audioStream.segmentBase?.initializationByteRange, HTTPByteRange(start: 0, endInclusive: 299))
        XCTAssertEqual(audioStream.segmentBase?.indexByteRange, HTTPByteRange(start: 300, endInclusive: 599))
    }

    func testDolbyVisionVariantCanUseDolbyAudioWhenAACIsAbsent() throws {
        let json = """
        {
            "quality": 126,
            "accept_quality": [126],
            "accept_description": ["杜比视界"],
            "dash": {
                "video": [
                    {
                        "id": 126,
                        "baseUrl": "https://example.com/dolby-video.m4s",
                        "bandwidth": 8000000,
                        "codecs": "dvh1.08.06",
                        "width": 3840,
                        "height": 2160,
                        "frameRate": "30"
                    }
                ],
                "dolby": {
                    "audio": [
                        {
                            "id": 30250,
                            "baseUrl": "https://example.com/audio-dolby.m4s",
                            "bandwidth": 448000,
                            "codecs": "ec-3"
                        }
                    ]
                }
            }
        }
        """

        let data = try JSONDecoder().decode(PlayURLData.self, from: Data(json.utf8))
        let variant = try XCTUnwrap(data.playVariants(cdnPreference: .automatic, codecPreference: .auto).first)

        XCTAssertTrue(data.hasMediaPayloadQuality(126))
        XCTAssertEqual(variant.dynamicRange, .dolbyVision)
        XCTAssertEqual(variant.audioURL?.absoluteString, "https://example.com/audio-dolby.m4s")
        XCTAssertEqual(variant.audioStream?.codecs, "ec-3")
        XCTAssertTrue(variant.audioStream?.isHardwareDecodingCompatibleAudio == true)
    }

    func testDashMergesNestedDolbyVideoPayload() throws {
        let json = """
        {
            "quality": 126,
            "accept_quality": [126],
            "accept_description": ["杜比视界"],
            "dash": {
                "audio": [
                    {
                        "id": 30280,
                        "baseUrl": "https://example.com/audio-aac.m4s",
                        "bandwidth": 128000,
                        "codecs": "mp4a.40.2"
                    }
                ],
                "dolby": {
                    "video": [
                        {
                            "id": 126,
                            "baseUrl": "https://example.com/dolby-video.m4s",
                            "bandwidth": 8000000,
                            "codecs": "dvh1.05.06",
                            "width": 3840,
                            "height": 2160,
                            "frameRate": "30"
                        }
                    ]
                }
            }
        }
        """

        let data = try JSONDecoder().decode(PlayURLData.self, from: Data(json.utf8))
        let variant = try XCTUnwrap(
            data.playVariants(cdnPreference: .automatic, codecPreference: .auto).first { $0.quality == 126 }
        )

        XCTAssertTrue(data.hasMediaPayloadQuality(126))
        XCTAssertEqual(data.dash?.video?.first?.codecs, "dvh1.05.06")
        XCTAssertEqual(variant.videoURL?.absoluteString, "https://example.com/dolby-video.m4s")
        XCTAssertEqual(variant.dynamicRange, .dolbyVision)
        XCTAssertEqual(variant.codec, "Dolby Vision")
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

    func testProgressiveMediaSegmentCacheInvalidatesOnlyMatchingURLs() async {
        let cache = ProgressiveMediaSegmentCache(byteCapacity: 32, itemLimit: 4, maxEntryBytes: 8, ttl: 60)
        let firstKey = ProgressiveMediaCacheKey(url: "https://example.com/a.mp4", rangeHeader: "bytes=0-3")
        let secondKey = ProgressiveMediaCacheKey(url: "https://example.com/b.mp4", rangeHeader: "bytes=0-3")

        await cache.store(progressiveResponse("1111"), for: firstKey)
        await cache.store(progressiveResponse("2222"), for: secondKey)
        await cache.invalidate(urls: [firstKey.url])

        let first = await cache.response(for: firstKey)
        let second = await cache.response(for: secondKey)
        XCTAssertNil(first)
        XCTAssertEqual(second?.data, Data("2222".utf8))
    }

    func testPlayURLDataCollectsPlaybackMediaURLs() throws {
        let json = """
        {
            "quality": 80,
            "dash": {
                "video": [{
                    "id": 80,
                    "baseUrl": "https://video.example.test/main.m4s",
                    "backupUrl": ["https://video.example.test/backup.m4s"],
                    "bandwidth": 1000,
                    "codecs": "avc1.640028"
                }],
                "audio": [{
                    "id": 30280,
                    "baseUrl": "https://audio.example.test/main.m4s",
                    "bandwidth": 128,
                    "codecs": "mp4a.40.2"
                }]
            }
        }
        """
        let data = try JSONDecoder().decode(PlayURLData.self, from: Data(json.utf8))

        XCTAssertEqual(
            data.playbackMediaURLStrings,
            [
                "https://video.example.test/main.m4s",
                "https://video.example.test/backup.m4s",
                "https://audio.example.test/main.m4s"
            ]
        )
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
        XCTAssertEqual(playbackSession.configuration.httpMaximumConnectionsPerHost, 6)
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
        platform: String = "pc"
    ) -> PlayURLCacheKey {
        PlayURLCacheKey(
            bvid: bvid,
            cid: cid,
            requestedQuality: quality,
            audioLanguage: "default",
            fnval: fnval,
            fnver: fnver,
            platform: platform
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
