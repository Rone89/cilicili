import XCTest
@testable import bili

final class PlaybackConnectivityPolicyTests: XCTestCase {
    func testVirtualRouteDoesNotHideAllPhysicalRoutesDown() {
        XCTAssertEqual(PlaybackConnectivityPolicy.isUnavailable(
            primary: false, wifi: true, cellular: true, wired: true), true)
    }

    func testAnyAvailableOrUnresolvedPhysicalRoutePreventsSupplementalOfflineVerdict() {
        for route in 0..<3 {
            var flags: [Bool?] = [true, true, true]
            for value in [Optional(false), nil] {
                flags[route] = value
                XCTAssertEqual(PlaybackConnectivityPolicy.isUnavailable(
                    primary: false, wifi: flags[0], cellular: flags[1], wired: flags[2]), false)
            }
        }
        XCTAssertNil(PlaybackConnectivityPolicy.isUnavailable(
            primary: nil, wifi: nil, cellular: nil, wired: nil))
    }

    func testPrimaryStillAdvertisingPhysicalInterfaceDoesNotTriggerFallback() {
        XCTAssertEqual(PlaybackConnectivityPolicy.isUnavailable(
            primary: false, primaryHasPhysicalInterface: true,
            wifi: true, cellular: true, wired: true), false)
    }

    func testPrimaryPathFailureRemainsOfflineAndRecoveryClearsIt() {
        XCTAssertEqual(PlaybackConnectivityPolicy.isUnavailable(
            primary: true, wifi: false, cellular: false, wired: false), true)
        XCTAssertEqual(PlaybackConnectivityPolicy.isUnavailable(
            primary: false, wifi: false, cellular: true, wired: true), false)
    }
}
