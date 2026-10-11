import Foundation
import XCTest
@testable import bili

final class VideoDetailFormalPerformancePolicyTests: XCTestCase {
    @MainActor
    func testNativeToolbarPickerDefaultsOffAndPersistsWithoutChangingOtherSettings() {
        let suiteName = "VideoDetailNativeToolbarPickerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        // A retired switch must not implicitly opt users into this new experiment.
        defaults.set(true, forKey: "cc.bili.experimental.videoDetailToolbarSegmentedPicker.v1")
        let store = LibraryStore(userDefaults: defaults)
        XCTAssertFalse(store.videoDetailNativeToolbarPickerExperimentEnabled)
        store.setFollowsSystemFontSize(false)
        store.setVideoDetailNativeToolbarPickerExperimentEnabled(true)
        let restored = LibraryStore(userDefaults: defaults)
        XCTAssertTrue(restored.videoDetailNativeToolbarPickerExperimentEnabled)
        XCTAssertFalse(restored.followsSystemFontSize)
        restored.setVideoDetailNativeToolbarPickerExperimentEnabled(false)
        XCTAssertFalse(LibraryStore(userDefaults: defaults).videoDetailNativeToolbarPickerExperimentEnabled)
    }

    @MainActor
    func testFormalPolicyDefersSecondaryContentAndReportsStableTraceGroup() {
        let runtimeSettings = VideoDetailRuntimeSettingsStore()
        runtimeSettings.bind(
            LibraryStore(
                userDefaults: UserDefaults(
                    suiteName: "VideoDetailFormalPerformancePolicyTests.\(UUID().uuidString)"
                )!
            )
        )

        XCTAssertTrue(runtimeSettings.defersVideoDetailSecondaryContent)
        XCTAssertEqual(
            VideoDetailFormalPerformancePolicy.navigationTraceDetail,
            "group=formal transition=1 freeze=1 deferred=1"
        )
    }
}
