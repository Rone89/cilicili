import XCTest
@testable import bili

final class DanmakuSettingsTests: XCTestCase {
    @MainActor
    func testLegacySettingsDefaultToHidingDanmakuInPortrait() throws {
        let data = Data(
            """
            {
              "fontScale": 1.25,
              "opacity": 0.75,
              "displayArea": "topThreeQuarters",
              "fontWeight": "semibold",
              "loadFactor": 1,
              "allowsDanmakuOverlap": true
            }
            """.utf8
        )

        let settings = try JSONDecoder().decode(DanmakuSettings.self, from: data)

        XCTAssertTrue(settings.hidesInPortrait)
        XCTAssertTrue(settings.danmakuKit.allowsDanmakuOverlap)
        XCTAssertEqual(settings.danmakuKit.displayArea.fraction, 0.75)
        XCTAssertEqual(settings.danmakuKit.fontScale, 1.25)
        XCTAssertEqual(settings.danmakuKit.opacity, 0.75)
    }

    func testDanmakuKitSettingsPersistNestedConfiguration() throws {
        var settings = DanmakuSettings.default
        settings.danmakuKit.allowsDanmakuOverlap = true
        settings.danmakuKit.trackHeight = 36
        settings.danmakuKit.enablesTop = false

        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(DanmakuSettings.self, from: encoded)

        XCTAssertEqual(decoded.danmakuKit, settings.danmakuKit)
        XCTAssertTrue(decoded.danmakuKit.allowsDanmakuOverlap)
    }

    func testDisplayAreaReadsLegacyPresetAndWritesFraction() throws {
        let legacy = try JSONDecoder().decode(
            DanmakuDisplayArea.self,
            from: Data("\"topThreeQuarters\"".utf8)
        )
        XCTAssertEqual(legacy.fraction, 0.75)

        let encoded = try JSONEncoder().encode(legacy)
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), "0.75")
    }

    @MainActor
    func testMaxVisibleCountPersistsClampsAndFormatsUnlimitedTitle() throws {
        var settings = DanmakuSettings.default
        XCTAssertEqual(settings.danmakuKit.maxVisibleCount, 80)
        XCTAssertEqual(settings.danmakuKit.maxVisibleCountTitle, "80 条")
        XCTAssertFalse(settings.danmakuKit.isUnlimitedVisibleCount)

        settings.danmakuKit.maxVisibleCount = 150
        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(DanmakuSettings.self, from: encoded)
        XCTAssertEqual(decoded.danmakuKit.normalizedMaxVisibleCount, 150)
        XCTAssertEqual(decoded.danmakuKit.maxVisibleCountTitle, "150 条")

        var tooLow = DanmakuSettings.default
        tooLow.danmakuKit.maxVisibleCount = 5
        XCTAssertEqual(tooLow.normalized.danmakuKit.maxVisibleCount, 20)

        var unlimited = DanmakuSettings.default
        unlimited.danmakuKit.maxVisibleCount = 999
        XCTAssertEqual(unlimited.normalized.danmakuKit.maxVisibleCount, 210)
        XCTAssertTrue(unlimited.danmakuKit.isUnlimitedVisibleCount)
        XCTAssertEqual(unlimited.danmakuKit.maxVisibleCountTitle, "不限")

        let legacy = try JSONDecoder().decode(DanmakuSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.danmakuKit.maxVisibleCount, 80)
    }

    @MainActor
    func testMaximumActiveCountRespectsUserCapAndUnlimitedSetting() {
        let low = DanmakuSettings(danmakuKit: .init(maxVisibleCount: 30))
        let high = DanmakuSettings(danmakuKit: .init(maxVisibleCount: 180))
        let unlimited = DanmakuSettings(danmakuKit: .init(maxVisibleCount: 210))

        let lowLandscape = DanmakuRenderPolicy.maximumActiveCount(
            width: 852,
            settings: low,
            rate: 1.0,
            loadShedding: false
        )
        let highLandscape = DanmakuRenderPolicy.maximumActiveCount(
            width: 852,
            settings: high,
            rate: 1.0,
            loadShedding: false
        )
        let unlimitedLandscape = DanmakuRenderPolicy.maximumActiveCount(
            width: 852,
            settings: unlimited,
            rate: 1.0,
            loadShedding: false
        )

        XCTAssertGreaterThan(highLandscape, lowLandscape)
        XCTAssertGreaterThan(unlimitedLandscape, highLandscape)
        XCTAssertLessThanOrEqual(lowLandscape, 30)
        XCTAssertGreaterThanOrEqual(highLandscape, 140)
        XCTAssertGreaterThanOrEqual(unlimitedLandscape, 300)
    }
}
