import XCTest
@testable import bili

final class VideoDefaultQualitySelectionTests: H264PlaybackTestCase {
    func testSelectsConfiguredQualityWhenAvailable() {
        let selected = VideoDetailViewModel.preferredPlayableVariant(
            in: [variant(quality: 112), variant(quality: 80)],
            preferredQuality: 112
        )

        XCTAssertEqual(selected?.quality, 112)
    }

    func testFallsBackOnlyToLowerAvailableQuality() {
        let selected = VideoDetailViewModel.preferredPlayableVariant(
            in: [variant(quality: 112), variant(quality: 64)],
            preferredQuality: 80
        )

        XCTAssertEqual(selected?.quality, 64)
    }

    func testDoesNotUpgradeWhenOnlyHigherQualityIsAvailable() {
        let selected = VideoDetailViewModel.preferredPlayableVariant(
            in: [variant(quality: 112)],
            preferredQuality: 80
        )

        XCTAssertNil(selected)
    }

    func testCodecFallbackContinuesPastLowerQualityResponse() throws {
        let lowerQualityData = try playURLData(quality: 32)

        XCTAssertTrue(
            BiliAPIClient.shouldContinueCodecFallback(
                for: lowerQualityData,
                requestedQuality: 112
            )
        )
    }

    func testCodecFallbackAcceptsRequestedQualityResponse() throws {
        let requestedQualityData = try playURLData(quality: 112)

        XCTAssertFalse(
            BiliAPIClient.shouldContinueCodecFallback(
                for: requestedQualityData,
                requestedQuality: 112
            )
        )
    }

    func testCodecFallbackContinuesWhenTargetQualityIsOnlyAdvertised() throws {
        let data = try advertisedHighQualityWithOnlyLowQualityMedia()

        XCTAssertFalse(data.hasPlayableMediaQuality(112))
        XCTAssertTrue(
            BiliAPIClient.shouldContinueCodecFallback(
                for: data,
                requestedQuality: 112
            )
        )
    }

    func testExplicitCodecFallbackStopsAtHighestExplicitlyAvailableLowerQuality() throws {
        let data = try playURLDataWithVideo(
            quality: 112,
            declaredQualities: [112, 80],
            frameRate: "30"
        )

        XCTAssertFalse(
            BiliAPIClient.shouldContinueCodecFallback(
                for: data,
                requestedQuality: 116,
                requestedCodecFamily: .h264,
                allowsUnavailableQualityFallback: true
            )
        )
    }

    func testAutomaticCodecFallbackKeepsProbingAtLowerQuality() throws {
        let data = try playURLDataWithVideo(
            quality: 112,
            declaredQualities: [112, 80],
            frameRate: "30"
        )

        XCTAssertTrue(
            BiliAPIClient.shouldContinueCodecFallback(
                for: data,
                requestedQuality: 116,
                requestedCodecFamily: .h264,
                allowsUnavailableQualityFallback: false
            )
        )
    }

    func testCodecFallbackContinuesWhenLowerQualityUsesAnotherCodec() throws {
        let data = try playURLDataWithVideo(
            quality: 112,
            declaredQualities: [112, 80],
            frameRate: "30"
        )

        XCTAssertTrue(
            BiliAPIClient.shouldContinueCodecFallback(
                for: data,
                requestedQuality: 116,
                requestedCodecFamily: .hevc,
                allowsUnavailableQualityFallback: true
            )
        )
    }

    func testCodecFallbackContinuesWhenHighestAdvertisedFallbackHasNoMedia() throws {
        let data = try playURLDataWithVideo(
            quality: 80,
            responseQuality: 116,
            declaredQualities: [112, 80],
            frameRate: "30"
        )

        XCTAssertTrue(
            BiliAPIClient.shouldContinueCodecFallback(
                for: data,
                requestedQuality: 116
            )
        )
    }

    func testExplicitQualityListCanDeclareTargetUnavailable() throws {
        let data = try explicitlyAdvertisedLowerQualities()

        XCTAssertTrue(data.hasExplicitlyUnavailableQuality(116))
        XCTAssertFalse(data.hasExplicitlyUnavailableQuality(80))
    }

    func testMissingQualityListDoesNotDeclareTargetUnavailable() throws {
        let data = try playURLData(quality: 80)

        XCTAssertFalse(data.hasExplicitlyUnavailableQuality(116))
    }

    func testNextLowerQualityFollowsConfiguredQualityOrder() {
        XCTAssertEqual(BiliAPIClient.nextLowerVideoQuality(after: 116), 112)
        XCTAssertEqual(BiliAPIClient.nextLowerVideoQuality(after: 112), 80)
        XCTAssertNil(BiliAPIClient.nextLowerVideoQuality(after: 6))
    }

    func testPiliPlusStyleSelectionIgnoresUnavailableRequestedQualityEcho() throws {
        let data = try playURLDataWithVideo(
            quality: 112,
            responseQuality: 116,
            declaredQualities: [112, 80, 64],
            frameRate: "30"
        )

        XCTAssertTrue(data.hasExplicitlyUnavailableQuality(116))
        XCTAssertFalse(data.shouldRefetchForPreferredQuality(116))
        XCTAssertTrue(
            BiliAPIClient.canUseUnavailablePreferredStartupFallback(
                data,
                requestedQuality: 116,
                isAuthoritativeSource: true
            )
        )
    }

    func testPiliPlusStylePlayURLQueryMatchesReferenceShape() {
        let query = BiliAPIClient.piliPlusStylePlayURLQuery(
            bvid: "BVtest",
            cid: 123,
            qn: 116,
            tryLook: false
        )

        XCTAssertEqual(
            Set(query.keys),
            [
                "bvid", "cid", "qn", "fnval", "fourk", "fnver", "voice_balance",
                "gaia_source", "isGaiaAvoided", "web_location", "dm_img_list",
                "dm_img_str", "dm_cover_img_str", "dm_img_inter"
            ]
        )
        XCTAssertEqual(query["bvid"], "BVtest")
        XCTAssertEqual(query["cid"], "123")
        XCTAssertEqual(query["qn"], "116")
        XCTAssertNil(query["platform"])
        XCTAssertNil(query["high_quality"])
        XCTAssertNil(query["otype"])
        XCTAssertNil(query["video_codecid"])
        XCTAssertNil(query["try_look"])
    }

    func testPiliPlusStylePlayURLQueryAddsTryLookOnlyWhenRequested() {
        let query = BiliAPIClient.piliPlusStylePlayURLQuery(
            bvid: "BVtest",
            cid: 123,
            qn: 80,
            tryLook: true
        )

        XCTAssertEqual(query["try_look"], "1")
    }

    func testLoggedInPiliPlusCompatibilityQueryOmitsTryLook() {
        let query = BiliAPIClient.piliPlusCompatibilityPlayURLQuery(
            bvid: "BVtest",
            cid: 123,
            qn: 116,
            streamSource: .web,
            tryLook: false
        )

        XCTAssertNil(query["try_look"])
    }

    func testGuestPiliPlusCompatibilityQueryIncludesTryLook() {
        let query = BiliAPIClient.piliPlusCompatibilityPlayURLQuery(
            bvid: "BVtest",
            cid: 123,
            qn: 116,
            streamSource: .web,
            tryLook: true
        )

        XCTAssertEqual(query["try_look"], "1")
    }

    func testPiliPlusStyleDiagnosticReportsBaseQualityRequest() {
        let message = BiliAPIClient.piliPlusStylePlayURLDiagnosticMessage(
            result: "success",
            requestedQuality: 116,
            queryQuality: 80,
            selectedQuality: 112,
            requests: 1,
            keysElapsedMilliseconds: 0,
            requestElapsedMilliseconds: 120,
            selectionElapsedMilliseconds: 2,
            totalElapsedMilliseconds: 130
        )

        XCTAssertTrue(message.contains("route=baseQualityWBI"))
        XCTAssertTrue(
            message.contains("strategy=\(PiliPlusStylePlayURLSelectionExperiment.currentStrategyKey)")
        )
        XCTAssertTrue(message.contains("queryQ=80"))
        XCTAssertTrue(message.contains("selected=112"))
        XCTAssertTrue(message.contains("requests=1"))
    }

    func testPiliPlusStyleDiagnosticKeepsSingleRequestShape() {
        let message = BiliAPIClient.piliPlusStylePlayURLDiagnosticMessage(
            result: "success",
            requestedQuality: 116,
            queryQuality: 80,
            selectedQuality: 112,
            requests: 1,
            keysElapsedMilliseconds: 0,
            requestElapsedMilliseconds: 108,
            selectionElapsedMilliseconds: 2,
            totalElapsedMilliseconds: 120
        )

        XCTAssertTrue(message.contains("route=baseQualityWBI"))
        XCTAssertTrue(message.contains("queryQ=80"))
        XCTAssertTrue(message.contains("requests=1"))
        XCTAssertFalse(message.contains("rescue="))
        XCTAssertFalse(message.contains("winner="))
    }

    func testPiliPlusStyleFailureDiagnosticDoesNotExposeAPIDetail() {
        let message = BiliAPIClient.piliPlusStylePlayURLDiagnosticMessage(
            result: "failure",
            requestedQuality: 116,
            selectedQuality: nil,
            requests: 1,
            keysElapsedMilliseconds: 12.4,
            requestElapsedMilliseconds: 98.7,
            selectionElapsedMilliseconds: nil,
            totalElapsedMilliseconds: 112.2,
            error: BiliAPIError.api(
                code: -352,
                message: "https://example.test/playurl?token=secret"
            )
        )

        XCTAssertTrue(message.contains("result=failure"))
        XCTAssertTrue(message.contains("requests=1"))
        XCTAssertTrue(message.contains("keys=12ms"))
        XCTAssertTrue(message.contains("request=99ms"))
        XCTAssertTrue(message.contains("selection=-"))
        XCTAssertTrue(message.contains("reason=api-352"))
        XCTAssertFalse(message.contains("example.test"))
        XCTAssertFalse(message.contains("secret"))
    }

    func testPiliPlusWBIResponseDiagnosticReportsCountsAndCredentialPresence() {
        let data = PlayURLData(
            code: 0,
            message: nil,
            durl: [],
            dash: nil,
            quality: nil,
            acceptQuality: [116, 112],
            acceptDescription: nil,
            supportFormats: [],
            lastPlayTime: nil,
            lastPlayCID: nil
        )
        let response = BiliResponse(
            code: 0,
            message: nil,
            msg: nil,
            data: data,
            result: nil
        )

        let message = BiliAPIClient.piliPlusWBIResponseDiagnosticMessage(
            queryQuality: 116,
            response: response,
            isLoggedIn: true,
            hasSESSDATA: true,
            hasDedeUserID: true,
            hasAccessKey: false,
            accountPurposeEnabled: true
        )

        XCTAssertEqual(
            message,
            "q116:outer0:inner0:payload1:dashV0:dashA0:durl0:accept2:support0:loggedIn1:sess1:dede1:access0:purpose1"
        )
    }

    func testPiliPlusStyleDiagnosticReportsBaseResponseWithoutKeyRefresh() {
        let message = BiliAPIClient.piliPlusStylePlayURLDiagnosticMessage(
            result: "failure",
            requestedQuality: 116,
            queryQuality: 80,
            selectedQuality: nil,
            requests: 1,
            keysElapsedMilliseconds: 0,
            requestElapsedMilliseconds: 110,
            selectionElapsedMilliseconds: nil,
            totalElapsedMilliseconds: 180,
            targetResponseDiagnostic: "q80:outer0:payload1:dashV15:dashA3",
            error: BiliAPIError.emptyPlayURL
        )

        XCTAssertTrue(message.contains("baseResponse=q80:outer0:payload1:dashV15:dashA3"))
        XCTAssertFalse(message.contains("keyRefresh"))
    }

    func testPiliPlusFallbackDiagnosticReportsLegacyWinnerWithoutExposingErrorDetail() {
        let message = BiliAPIClient.piliPlusStartupFallbackDiagnosticMessage(
            result: "success",
            route: "legacy",
            requestedQuality: 116,
            selectedQuality: 116,
            legacyResult: "success",
            legacyElapsedMilliseconds: 180,
            webpageElapsedMilliseconds: nil,
            totalElapsedMilliseconds: 181,
            legacyError: BiliAPIError.api(
                code: -352,
                message: "https://example.test/playurl?token=secret"
            )
        )

        XCTAssertTrue(message.contains("result=success"))
        XCTAssertTrue(message.contains("route=legacy"))
        XCTAssertTrue(message.contains("target=116"))
        XCTAssertTrue(message.contains("selected=116"))
        XCTAssertTrue(message.contains("legacyResult=success"))
        XCTAssertTrue(message.contains("wbiResult=notStarted"))
        XCTAssertTrue(message.contains("legacy=180ms"))
        XCTAssertTrue(message.contains("webpage=-"))
        XCTAssertTrue(message.contains("legacyReason=api-352"))
        XCTAssertFalse(message.contains("example.test"))
        XCTAssertFalse(message.contains("secret"))
    }

    func testPiliPlusPrimaryProbeUsesNearestHighQuality() {
        XCTAssertEqual(
            BiliAPIClient.piliPlusPrimaryProbeQuality(requestedQuality: 116),
            112
        )
        XCTAssertEqual(
            BiliAPIClient.piliPlusPrimaryProbeQuality(requestedQuality: 112),
            112
        )
        XCTAssertEqual(
            BiliAPIClient.piliPlusPrimaryProbeQuality(requestedQuality: 64),
            64
        )
    }

    func testPiliPlusCompatibilityRescueUsesBaseQualityRequest() {
        XCTAssertEqual(
            BiliAPIClient.piliPlusCompatibilityRescueProbeQuality(
                requestedQuality: 116,
                baseQuality: 112
            ),
            80
        )
        XCTAssertEqual(
            BiliAPIClient.piliPlusCompatibilityRescueProbeQuality(
                requestedQuality: 112,
                baseQuality: 112
            ),
            80
        )
        XCTAssertNil(
            BiliAPIClient.piliPlusCompatibilityRescueProbeQuality(
                requestedQuality: 80,
                baseQuality: 80
            )
        )
    }

    func testPiliPlusStyleDiagnosticReportsConditionalWBIRescue() {
        let message = BiliAPIClient.piliPlusStylePlayURLDiagnosticMessage(
            result: "success",
            requestedQuality: 116,
            queryQuality: 112,
            selectedQuality: 112,
            requests: 2,
            keysElapsedMilliseconds: 0,
            requestElapsedMilliseconds: 105,
            selectionElapsedMilliseconds: 2,
            totalElapsedMilliseconds: 214,
            targetResponseDiagnostic: "q112:dashV0",
            rescueQueryQuality: 80,
            rescueRequestElapsedMilliseconds: 98,
            rescueResponseDiagnostic: "q80:dashV15"
        )

        XCTAssertTrue(message.contains("route=baseThenRescueWBI"))
        XCTAssertTrue(message.contains("queryQ=112"))
        XCTAssertTrue(message.contains("rescueQ=80"))
        XCTAssertTrue(message.contains("rescue=98ms"))
        XCTAssertTrue(message.contains("baseResponse=q112:dashV0"))
        XCTAssertTrue(message.contains("rescueResponse=q80:dashV15"))
    }

    func testPiliPlusFallbackDiagnosticReportsSkippedLegacyProbe() {
        let message = BiliAPIClient.piliPlusStartupFallbackDiagnosticMessage(
            result: "success",
            route: "standardWBI",
            requestedQuality: 116,
            selectedQuality: 112,
            legacyResult: "skipped",
            legacyElapsedMilliseconds: nil,
            standardWBIResult: "success",
            standardWBIQuality: 112,
            standardWBIElapsedMilliseconds: 109,
            webpageElapsedMilliseconds: nil,
            totalElapsedMilliseconds: 110
        )

        XCTAssertTrue(message.contains("strategy=\(PiliPlusStylePlayURLSelectionExperiment.currentStrategyKey)"))
        XCTAssertTrue(message.contains("legacyResult=skipped"))
        XCTAssertTrue(message.contains("legacy=-"))
        XCTAssertTrue(message.contains("wbiResult=success"))
        XCTAssertTrue(message.contains("wbi=109ms"))
    }

    func testAuthoritativeFallbackUsesHighestExplicitlyAdvertisedLowerQuality() throws {
        let data = try explicitlyAdvertisedLowerQualities()

        XCTAssertTrue(
            BiliAPIClient.canUseUnavailablePreferredStartupFallback(
                data,
                requestedQuality: 116,
                isAuthoritativeSource: true
            )
        )
    }

    func testAuthoritativeFallbackUsesExplicitQ64WhenHigherRungsAreUnavailable() throws {
        let data = try playURLDataWithVideo(
            quality: 64,
            responseQuality: 64,
            declaredQualities: [64, 32, 16],
            frameRate: "30"
        )

        XCTAssertTrue(
            BiliAPIClient.canUseUnavailablePreferredStartupFallback(
                data,
                requestedQuality: 116,
                isAuthoritativeSource: true
            )
        )
    }

    func testAuthoritativeFallbackWithoutExplicitLadderDoesNotSkipNextRung() throws {
        let data = try playURLData(quality: 80)

        XCTAssertFalse(
            BiliAPIClient.canUseUnavailablePreferredStartupFallback(
                data,
                requestedQuality: 116,
                isAuthoritativeSource: true
            )
        )
    }

    func testPiliPlusCompatibilityRejectsQ80WhenQ112IsAdvertisedButMissing() throws {
        let data = try playURLDataWithVideo(
            quality: 80,
            responseQuality: 116,
            declaredQualities: [112, 80, 64],
            frameRate: "30"
        )

        XCTAssertFalse(
            BiliAPIClient.canUsePiliPlusCompatibilityResponse(
                data,
                requestedQuality: 116
            )
        )
    }

    func testAuthoritativeFallbackUsesTheNextLowerQualityWhenPresent() throws {
        let data = try playURLDataWithVideo(
            quality: 112,
            declaredQualities: [112, 80],
            frameRate: "30"
        )

        XCTAssertTrue(
            BiliAPIClient.canUseUnavailablePreferredStartupFallback(
                data,
                requestedQuality: 116,
                isAuthoritativeSource: true
            )
        )
        XCTAssertFalse(
            BiliAPIClient.canUseUnavailablePreferredStartupFallback(
                data,
                requestedQuality: 116,
                isAuthoritativeSource: false
            )
        )
        XCTAssertTrue(
            BiliAPIClient.canUsePiliPlusCompatibilityResponse(
                data,
                requestedQuality: 116
            )
        )
    }

    func testTargetQualityAvailabilitySummaryReportsNotAdvertisedQuality() throws {
        let summary = try explicitlyAdvertisedLowerQualities()
            .targetQualityAvailabilitySummary(116)

        XCTAssertTrue(summary.contains("targetAvailability target=116"))
        XCTAssertTrue(summary.contains("accept=80,32"))
        XCTAssertTrue(summary.contains("reason=notAdvertised"))
        XCTAssertFalse(summary.contains("https://"))
    }

    func testTargetQualityAvailabilitySummaryReportsNonHighFrameTarget() throws {
        let data = try playURLDataWithVideo(
            quality: 116,
            declaredQualities: [116, 112],
            frameRate: "30"
        )

        let summary = data.targetQualityAvailabilitySummary(116)

        XCTAssertTrue(summary.contains("accept=116,112"))
        XCTAssertTrue(summary.contains("dash=q116:"))
        XCTAssertTrue(summary.contains("reason=notHighFrameRate"))
    }

    func testStartupFallbackMustRefetchWhenTargetIsAdvertisedButMediaIsMissing() throws {
        let data = try advertisedHighQualityWithOnlyLowQualityMedia()

        XCTAssertFalse(
            BiliAPIClient.canUseUnavailablePreferredStartupFallback(
                data,
                requestedQuality: 112,
                isAuthoritativeSource: true
            )
        )
    }

    func testStartupCandidateQualityNeverUpgradesAboveRequestedQuality() throws {
        let exactTargetData = try playURLDataWithVideoQualities([120, 116, 112])
        let lowerFallbackData = try playURLDataWithVideoQualities([120, 112])
        let higherOnlyData = try playURLDataWithVideoQualities([120])

        XCTAssertEqual(
            BiliAPIClient.startupCandidateQuality(
                in: exactTargetData,
                requestedQuality: 116
            ),
            116
        )
        XCTAssertEqual(
            BiliAPIClient.startupCandidateQuality(
                in: lowerFallbackData,
                requestedQuality: 116
            ),
            112
        )
        XCTAssertNil(
            BiliAPIClient.startupCandidateQuality(
                in: higherOnlyData,
                requestedQuality: 116
            )
        )
    }

    func testStartupCandidateQualityTreatsNonHighFrameQ116AsUnavailable() throws {
        let data = try playURLDataWithVideoQualities([116, 112], frameRate: "30")

        XCTAssertEqual(
            BiliAPIClient.startupCandidateQuality(
                in: data,
                requestedQuality: 116
            ),
            112
        )
    }

    private func variant(quality: Int) -> PlayVariant {
        PlayVariant(
            quality: quality,
            title: BiliVideoQuality.title(for: quality),
            videoURL: URL(string: "https://example.test/video-\(quality).mp4"),
            audioURL: nil,
            videoStream: nil,
            audioStream: nil,
            codec: "avc1",
            resolution: nil,
            frameRate: "30",
            bandwidth: 1_000_000,
            isHDR: false,
            badge: nil
        )
    }

    private func playURLData(quality: Int) throws -> PlayURLData {
        let json = """
        {
            "quality": \(quality),
            "durl": [
                {
                    "url": "https://example.test/video-\(quality).mp4"
                }
            ]
        }
        """
        return try JSONDecoder().decode(PlayURLData.self, from: Data(json.utf8))
    }

    private func playURLDataWithVideo(
        quality: Int,
        responseQuality: Int? = nil,
        declaredQualities: [Int],
        frameRate: String
    ) throws -> PlayURLData {
        let responseQuality = responseQuality ?? quality
        let json = """
        {
            "quality": \(responseQuality),
            "accept_quality": [\(declaredQualities.map(String.init).joined(separator: ","))],
            "accept_description": ["1080P 高帧率", "1080P 高码率"],
            "dash": {
                "video": [
                    {
                        "id": \(quality),
                        "baseUrl": "https://example.test/video-\(quality).m4s",
                        "bandwidth": 2200000,
                        "codecs": "avc1.640028",
                        "width": 1920,
                        "height": 1080,
                        "frameRate": "\(frameRate)"
                    }
                ],
                "audio": [
                    {
                        "id": 30280,
                        "baseUrl": "https://example.test/audio.m4s",
                        "bandwidth": 128000,
                        "codecs": "mp4a.40.2"
                    }
                ]
            }
        }
        """
        return try JSONDecoder().decode(PlayURLData.self, from: Data(json.utf8))
    }

    private func playURLDataWithVideoQualities(
        _ qualities: [Int],
        frameRate: String = "60"
    ) throws -> PlayURLData {
        let videoStreams = qualities.map { quality in
            """
            {
                "id": \(quality),
                "baseUrl": "https://example.test/video-\(quality).m4s",
                "bandwidth": 2200000,
                "codecs": "avc1.640028",
                "width": 1920,
                "height": 1080,
                "frameRate": "\(frameRate)"
            }
            """
        }.joined(separator: ",")
        let qualityList = qualities.map(String.init).joined(separator: ",")
        let json = """
        {
            "quality": \(qualities.first ?? 80),
            "accept_quality": [\(qualityList)],
            "dash": {
                "video": [\(videoStreams)],
                "audio": [
                    {
                        "id": 30280,
                        "baseUrl": "https://example.test/audio.m4s",
                        "bandwidth": 128000,
                        "codecs": "mp4a.40.2"
                    }
                ]
            }
        }
        """
        return try JSONDecoder().decode(PlayURLData.self, from: Data(json.utf8))
    }

    private func advertisedHighQualityWithOnlyLowQualityMedia() throws -> PlayURLData {
        let json = """
        {
            "quality": 32,
            "accept_quality": [112, 32],
            "accept_description": ["1080P 高码率", "480P 标清"],
            "dash": {
                "video": [
                    {
                        "id": 32,
                        "baseUrl": "https://example.test/video-32.m4s",
                        "bandwidth": 320000,
                        "codecs": "avc1.64001F",
                        "width": 852,
                        "height": 480,
                        "frameRate": "30"
                    }
                ],
                "audio": [
                    {
                        "id": 30280,
                        "baseUrl": "https://example.test/audio.m4s",
                        "bandwidth": 128000,
                        "codecs": "mp4a.40.2"
                    }
                ]
            }
        }
        """
        return try JSONDecoder().decode(PlayURLData.self, from: Data(json.utf8))
    }

    private func explicitlyAdvertisedLowerQualities() throws -> PlayURLData {
        let json = """
        {
            "quality": 80,
            "accept_quality": [80, 32],
            "accept_description": ["1080P", "480P"],
            "durl": [
                {
                    "url": "https://example.test/video-80.mp4"
                }
            ]
        }
        """
        return try JSONDecoder().decode(PlayURLData.self, from: Data(json.utf8))
    }
}
