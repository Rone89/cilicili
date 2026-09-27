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
}
