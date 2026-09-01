import Foundation
import XCTest
@testable import bili

final class VideoDetailFormalPerformancePolicyTests: XCTestCase {
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
