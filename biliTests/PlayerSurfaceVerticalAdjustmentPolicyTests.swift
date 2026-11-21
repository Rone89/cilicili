import CoreGraphics
import XCTest
@testable import bili

final class PlayerSurfaceVerticalAdjustmentPolicyTests: XCTestCase {
    func testAxisPolicyRequiresClearDirectionalIntent() {
        XCTAssertEqual(
            PlayerSurfaceGestureAxisPolicy.axis(
                translation: CGSize(width: 12, height: 2),
                activationDistance: 8,
                dominanceRatio: 3
            ),
            .horizontal
        )
        XCTAssertEqual(
            PlayerSurfaceGestureAxisPolicy.axis(
                translation: CGSize(width: 2, height: -12),
                activationDistance: 8,
                dominanceRatio: 3
            ),
            .vertical
        )
        XCTAssertNil(
            PlayerSurfaceGestureAxisPolicy.axis(
                translation: CGSize(width: 12, height: 8),
                activationDistance: 8,
                dominanceRatio: 3
            )
        )
    }

    func testUsesLeftHalfForBrightnessAndRightHalfForVolume() {
        XCTAssertEqual(
            PlayerSurfaceVerticalAdjustmentPolicy.target(startLocationX: 0, width: 400),
            .brightness
        )
        XCTAssertEqual(
            PlayerSurfaceVerticalAdjustmentPolicy.target(startLocationX: 199, width: 400),
            .brightness
        )
        XCTAssertEqual(
            PlayerSurfaceVerticalAdjustmentPolicy.target(startLocationX: 200, width: 400),
            .volume
        )
        XCTAssertEqual(
            PlayerSurfaceVerticalAdjustmentPolicy.target(startLocationX: 400, width: 400),
            .volume
        )
    }

    func testRejectsLocationsOutsideUsableSurface() {
        XCTAssertNil(PlayerSurfaceVerticalAdjustmentPolicy.target(startLocationX: -1, width: 400))
        XCTAssertNil(PlayerSurfaceVerticalAdjustmentPolicy.target(startLocationX: 401, width: 400))
        XCTAssertNil(PlayerSurfaceVerticalAdjustmentPolicy.target(startLocationX: 0, width: 0))
    }

    func testRequiresClearlyVerticalMotion() {
        XCTAssertTrue(
            PlayerSurfaceVerticalAdjustmentPolicy.shouldBegin(
                translation: CGSize(width: 2, height: -12),
                activationDistance: 8,
                dominanceRatio: 3
            )
        )
        XCTAssertFalse(
            PlayerSurfaceVerticalAdjustmentPolicy.shouldBegin(
                translation: CGSize(width: 12, height: -2),
                activationDistance: 8,
                dominanceRatio: 3
            )
        )
        XCTAssertFalse(
            PlayerSurfaceVerticalAdjustmentPolicy.shouldBegin(
                translation: CGSize(width: 2, height: -7),
                activationDistance: 8,
                dominanceRatio: 3
            )
        )
    }

    func testMapsVerticalMovementToClampedSystemValue() {
        XCTAssertEqual(
            PlayerSurfaceVerticalAdjustmentPolicy.adjustedValue(
                initialValue: 0.5,
                verticalTranslation: -100,
                height: 200
            ),
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            PlayerSurfaceVerticalAdjustmentPolicy.adjustedValue(
                initialValue: 0.5,
                verticalTranslation: 50,
                height: 200
            ),
            0.25,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            PlayerSurfaceVerticalAdjustmentPolicy.adjustedValue(
                initialValue: 0.1,
                verticalTranslation: 100,
                height: 100
            ),
            0,
            accuracy: 0.0001
        )
    }

    func testPresentsHardwareVolumeChangeOutsideVerticalGesture() {
        XCTAssertTrue(
            PlayerSurfaceVerticalAdjustmentPolicy.shouldPresentHardwareVolumeIndicator(
                previousValue: 0.4,
                currentValue: 0.5,
                isVerticalAdjusting: false
            )
        )
    }

    func testDoesNotPresentUnchangedHardwareVolume() {
        XCTAssertFalse(
            PlayerSurfaceVerticalAdjustmentPolicy.shouldPresentHardwareVolumeIndicator(
                previousValue: 0.5,
                currentValue: 0.5,
                isVerticalAdjusting: false
            )
        )
    }

    func testDoesNotPresentHardwareVolumeDuringVerticalGesture() {
        XCTAssertFalse(
            PlayerSurfaceVerticalAdjustmentPolicy.shouldPresentHardwareVolumeIndicator(
                previousValue: 0.4,
                currentValue: 0.5,
                isVerticalAdjusting: true
            )
        )
    }

    func testThreeZoneActionSplitsWidthIntoThirdsWhenEnabled() {
        XCTAssertEqual(
            PlayerSurfaceVerticalAdjustmentPolicy.zoneAction(startLocationX: 50, width: 300, threeZoneEnabled: true),
            .brightness
        )
        XCTAssertEqual(
            PlayerSurfaceVerticalAdjustmentPolicy.zoneAction(startLocationX: 150, width: 300, threeZoneEnabled: true),
            .fullscreenToggle
        )
        XCTAssertEqual(
            PlayerSurfaceVerticalAdjustmentPolicy.zoneAction(startLocationX: 250, width: 300, threeZoneEnabled: true),
            .volume
        )
        XCTAssertEqual(
            PlayerSurfaceVerticalAdjustmentPolicy.zoneAction(startLocationX: 140, width: 300, threeZoneEnabled: false),
            .brightness
        )
        XCTAssertEqual(
            PlayerSurfaceVerticalAdjustmentPolicy.zoneAction(startLocationX: 160, width: 300, threeZoneEnabled: false),
            .volume
        )
    }

    func testFullscreenSwipeDirectionRespectsFullscreenStateAndThreshold() {
        XCTAssertEqual(
            PlayerSurfaceVerticalAdjustmentPolicy.fullscreenSwipeDirection(
                verticalTranslation: -40,
                isFullscreenActive: false
            ),
            .enterFullscreen
        )
        XCTAssertNil(
            PlayerSurfaceVerticalAdjustmentPolicy.fullscreenSwipeDirection(
                verticalTranslation: 40,
                isFullscreenActive: false
            )
        )
        XCTAssertEqual(
            PlayerSurfaceVerticalAdjustmentPolicy.fullscreenSwipeDirection(
                verticalTranslation: 40,
                isFullscreenActive: true
            ),
            .exitFullscreen
        )
        XCTAssertNil(
            PlayerSurfaceVerticalAdjustmentPolicy.fullscreenSwipeDirection(
                verticalTranslation: -40,
                isFullscreenActive: true
            )
        )
        XCTAssertNil(
            PlayerSurfaceVerticalAdjustmentPolicy.fullscreenSwipeDirection(
                verticalTranslation: -20,
                isFullscreenActive: false
            )
        )
    }
}
