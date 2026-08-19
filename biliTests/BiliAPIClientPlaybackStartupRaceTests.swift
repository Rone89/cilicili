import XCTest

@testable import bili

final class BiliAPIClientPlaybackStartupRaceTests: XCTestCase {
    func testAuthoritativeFallbackRequiresPlayableMedia() {
        let data = PlayURLData(
            code: 0,
            message: nil,
            durl: [],
            dash: nil,
            quality: 80,
            acceptQuality: [80, 32],
            acceptDescription: nil,
            supportFormats: [],
            lastPlayTime: nil,
            lastPlayCID: nil
        )

        XCTAssertFalse(
            BiliAPIClient.canUseUnavailablePreferredStartupFallback(
                data,
                requestedQuality: 116,
                isAuthoritativeSource: true
            )
        )
    }
}
