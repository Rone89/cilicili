import Foundation
import XCTest

@testable import bili

@MainActor
final class DynamicInteractionAndDetailTests: XCTestCase {
    func testRetiredSocialExperimentPreferencesAreCleared() {
        let suiteName = "cc.bili.tests.retired-social-experiments.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let retiredKeys = [
            "cc.bili.dynamic.realLikeExperimentEnabled.v1",
            "cc.bili.comment.likeExperimentEnabled.v1",
            "cc.bili.dynamic.imageTextDetailExperimentEnabled.v1",
            "cc.bili.dynamic.commentPublishExperimentEnabled.v1",
            "cc.bili.dynamic.commentReplyPublishExperimentEnabled.v1"
        ]
        retiredKeys.forEach { defaults.set(false, forKey: $0) }

        _ = LibraryStore(userDefaults: defaults)

        for key in retiredKeys {
            XCTAssertNil(defaults.object(forKey: key))
        }
    }

    func testDynamicDetailBottomInteractionBarExperimentDefaultsOffAndPersists() {
        let suiteName = "cc.bili.tests.dynamic-detail-bottom-bar.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LibraryStore(userDefaults: defaults)
        XCTAssertFalse(store.dynamicDetailBottomInteractionBarExperimentEnabled)

        store.setDynamicDetailBottomInteractionBarExperimentEnabled(true)
        XCTAssertTrue(LibraryStore(userDefaults: defaults).dynamicDetailBottomInteractionBarExperimentEnabled)

        store.setDynamicDetailBottomInteractionBarExperimentEnabled(false)
        XCTAssertFalse(LibraryStore(userDefaults: defaults).dynamicDetailBottomInteractionBarExperimentEnabled)
    }


    func testOptimisticStateUpdatesLikeCountAndReturnsToOriginalState() {
        let original = DynamicLikeDisplayState(isLiked: false, likeCount: 7)
        let liked = original.toggled()

        XCTAssertEqual(liked, DynamicLikeDisplayState(isLiked: true, likeCount: 8))
        XCTAssertEqual(liked.toggled(), original)
    }

    func testCommentLikeOptimisticStateUpdatesAndClampsAtZero() {
        let original = CommentLikeDisplayState(isLiked: false, likeCount: 7)
        let liked = original.toggled()

        XCTAssertEqual(liked, CommentLikeDisplayState(isLiked: true, likeCount: 8))
        XCTAssertEqual(liked.toggled(), original)
        XCTAssertEqual(
            CommentLikeDisplayState(isLiked: true, likeCount: 0).toggled(),
            CommentLikeDisplayState(isLiked: false, likeCount: 0)
        )
    }

    func testDetailNavigationSupportsImageTextPureTextAndForwardDynamics() {
        XCTAssertTrue(
            DynamicFeedCardDisplayModel.supportsDetailNavigation(
                hasTopLevelText: false,
                imageCount: 1,
                isForward: false,
                hasVideo: false,
                hasLive: false,
                hasPaidContent: false
            )
        )
        XCTAssertTrue(
            DynamicFeedCardDisplayModel.supportsDetailNavigation(
                hasTopLevelText: true,
                imageCount: 0,
                isForward: false,
                hasVideo: false,
                hasLive: false,
                hasPaidContent: false
            )
        )
        XCTAssertTrue(
            DynamicFeedCardDisplayModel.supportsDetailNavigation(
                hasTopLevelText: false,
                imageCount: 0,
                isForward: true,
                hasVideo: true,
                hasLive: true,
                hasPaidContent: true
            )
        )
        XCTAssertFalse(
            DynamicFeedCardDisplayModel.supportsDetailNavigation(
                hasTopLevelText: true,
                imageCount: 1,
                isForward: false,
                hasVideo: true,
                hasLive: false,
                hasPaidContent: false
            )
        )
        XCTAssertFalse(
            DynamicFeedCardDisplayModel.supportsDetailNavigation(
                hasTopLevelText: true,
                imageCount: 1,
                isForward: false,
                hasVideo: false,
                hasLive: true,
                hasPaidContent: false
            )
        )
        XCTAssertFalse(
            DynamicFeedCardDisplayModel.supportsDetailNavigation(
                hasTopLevelText: true,
                imageCount: 1,
                isForward: false,
                hasVideo: false,
                hasLive: false,
                hasPaidContent: true
            )
        )
        XCTAssertFalse(
            DynamicFeedCardDisplayModel.supportsDetailNavigation(
                hasTopLevelText: false,
                imageCount: 0,
                isForward: false,
                hasVideo: false,
                hasLive: false,
                hasPaidContent: false
            )
        )
    }

    func testUnlikeNeverProducesNegativeCount() {
        let state = DynamicLikeDisplayState(isLiked: true, likeCount: 0)

        XCTAssertEqual(state.toggled(), DynamicLikeDisplayState(isLiked: false, likeCount: 0))
    }

    func testNativePullRefreshDefaultsOnAndPersists() {
        let suiteName = "cc.bili.tests.unified-pull-refresh.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LibraryStore(userDefaults: defaults)
        XCTAssertTrue(store.nativePullRefreshEnabled)

        store.setNativePullRefreshEnabled(false)

        XCTAssertFalse(
            LibraryStore(userDefaults: defaults).nativePullRefreshEnabled
        )
    }

    func testNativePullRefreshMigratesLegacyExperimentPreference() {
        let suiteName = "cc.bili.tests.native-pull-refresh-migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: "cc.bili.pullRefresh.unifiedDetailStyleExperimentEnabled.v1")

        let store = LibraryStore(userDefaults: defaults)

        XCTAssertFalse(store.nativePullRefreshEnabled)
        XCTAssertNil(
            defaults.object(forKey: "cc.bili.pullRefresh.unifiedDetailStyleExperimentEnabled.v1")
        )
        XCTAssertEqual(
            defaults.object(forKey: "cc.bili.home.nativePullRefreshEnabled.v1") as? Bool,
            false
        )
    }

}
