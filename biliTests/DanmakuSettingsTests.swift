import XCTest
@testable import bili

final class DanmakuSettingsTests: XCTestCase {
    @MainActor
    func testLegacySettingsDefaultToShowingDanmakuInPortrait() throws {
        let data = Data(
            """
            {
              "fontScale": 1,
              "opacity": 0.92,
              "displayArea": "topHalf",
              "fontWeight": "semibold",
              "loadFactor": 1
            }
            """.utf8
        )

        let settings = try JSONDecoder().decode(DanmakuSettings.self, from: data)

        XCTAssertFalse(settings.hidesInPortrait)
    }

    @MainActor
    func testLibraryStoreMigratesFormerPortraitHiddenDefault() throws {
        let suiteName = "cc.bili.tests.danmaku-portrait-default-migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let oldSettings = DanmakuSettings(
            fontScale: 1,
            opacity: 0.92,
            displayArea: .topHalf,
            fontWeight: .semibold,
            hidesInPortrait: true
        )
        defaults.set(
            try JSONEncoder().encode(oldSettings),
            forKey: "cc.bili.playback.danmakuSettings.v1"
        )

        let migrated = LibraryStore(userDefaults: defaults)
        XCTAssertFalse(migrated.danmakuSettings.hidesInPortrait)
        XCTAssertFalse(LibraryStore(userDefaults: defaults).danmakuSettings.hidesInPortrait)

        var explicitSettings = migrated.danmakuSettings
        explicitSettings.hidesInPortrait = true
        migrated.setDanmakuSettings(explicitSettings)
        XCTAssertTrue(LibraryStore(userDefaults: defaults).danmakuSettings.hidesInPortrait)
    }
}
