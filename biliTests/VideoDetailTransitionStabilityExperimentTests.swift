import Foundation
import XCTest
@testable import bili

final class VideoDetailFormalPerformancePolicyTests: XCTestCase {
    @MainActor
    func testRetiredNativeToolbarPickerSettingIsRemovedWithoutChangingOtherSettings() {
        let suiteName = "VideoDetailNativeToolbarPickerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "cc.bili.videoDetail.nativeToolbarPickerExperimentEnabled.v1"
        for previousValue in [false, true] {
            defaults.set(previousValue, forKey: key)
            let store = LibraryStore(userDefaults: defaults)
            XCTAssertNil(defaults.object(forKey: key))
            store.setFollowsSystemFontSize(false)
            XCTAssertFalse(LibraryStore(userDefaults: defaults).followsSystemFontSize)
        }
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
