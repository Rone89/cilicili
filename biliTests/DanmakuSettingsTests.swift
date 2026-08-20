import XCTest
@testable import bili

final class DanmakuSettingsTests: XCTestCase {
    @MainActor
    func testLegacySettingsDefaultToHidingDanmakuInPortrait() throws {
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

        XCTAssertTrue(settings.hidesInPortrait)
    }
}
