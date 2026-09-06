import Foundation
import XCTest

@testable import bili

@MainActor
final class DynamicInteractionAndDetailTests: XCTestCase {
    func testCompactComposerMatchesReferenceInsets() {
        let layout = DynamicComposerLayout(bottomSafeArea: 34, isCompact: true, isComposing: false)
        XCTAssertEqual(layout.horizontalPadding, 26)
        XCTAssertEqual(34 + layout.bottomPadding, 28)
    }

    func testComposerPreservesKeyboardAndNonCompactInsets() {
        for layout in [
            DynamicComposerLayout(bottomSafeArea: 336, isCompact: true, isComposing: true),
            DynamicComposerLayout(bottomSafeArea: 21, isCompact: false, isComposing: false),
            DynamicComposerLayout(bottomSafeArea: 0, isCompact: true, isComposing: false)
        ] {
            XCTAssertEqual(layout.horizontalPadding, 8)
            XCTAssertEqual(layout.bottomPadding, 8)
        }
    }

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

    func testDynamicDetailComposerExperimentDefaultsOffAndPersists() {
        let suiteName = "cc.bili.tests.dynamic-detail-composer.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LibraryStore(userDefaults: defaults)
        XCTAssertFalse(store.dynamicDetailComposerExperimentEnabled)

        store.setDynamicDetailComposerExperimentEnabled(true)
        XCTAssertTrue(LibraryStore(userDefaults: defaults).dynamicDetailComposerExperimentEnabled)

        store.setDynamicDetailComposerExperimentEnabled(false)
        XCTAssertFalse(LibraryStore(userDefaults: defaults).dynamicDetailComposerExperimentEnabled)
    }

    func testDynamicCommentComposerStateRepresentsFailureWithoutDroppingReplyTarget() {
        let target = DynamicCommentComposerTarget(
            rootID: 101,
            parentID: 202,
            authorName: "评论作者"
        )

        XCTAssertEqual(
            DynamicCommentComposerState.replying(target: target),
            .replying(target: target)
        )
        XCTAssertEqual(
            DynamicCommentComposerState.failed(message: "网络错误"),
            .failed(message: "网络错误")
        )
    }

    func testDynamicCommentComposerTargetSeparatesTopLevelAndReplyDrafts() {
        let topLevel = DynamicCommentComposerTarget.dynamic
        let rootReply = DynamicCommentComposerTarget(
            rootID: 101,
            parentID: 101,
            authorName: "根评论作者"
        )
        let nestedReply = DynamicCommentComposerTarget(
            rootID: 101,
            parentID: 202,
            authorName: "楼中楼作者"
        )

        XCTAssertEqual(topLevel.id, "dynamic")
        XCTAssertEqual(rootReply.id, "reply:101:101")
        XCTAssertEqual(nestedReply.id, "reply:101:202")
        XCTAssertNotEqual(rootReply, nestedReply)
        XCTAssertEqual(nestedReply.title, "回复评论")
        XCTAssertEqual(nestedReply.prompt, "回复 @楼中楼作者")
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
