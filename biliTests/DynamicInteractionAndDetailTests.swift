import Foundation
import XCTest

@testable import bili

@MainActor
final class DynamicInteractionAndDetailTests: XCTestCase {
    func testDynamicBodyUsesSeventeenPointRegularBodyRole() {
        let role = AppTypography.Role.dynamicBody

        XCTAssertEqual(role.pointSize, 17)
        XCTAssertEqual(role.nativeUITextStyle, .body)
        XCTAssertNil(role.nativeWeight)
    }

    func testRetiredTypographyExperimentKeysAreCleared() {
        let suiteName = "cc.bili.tests.retired-typography-experiments.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let retiredKeys = [
            "cc.bili.display.unifiedAppTypographyExperimentEnabled.v1",
            "cc.bili.experimental.dynamicFeedLargeTypography.v1",
            "cc.bili.experimental.systemTextStyle.v1",
            "cc.bili.experimental.dynamicFeedAccurateExpansion.v1",
            "cc.bili.experimental.dynamicFeedPiliPlusLineSpacing.v1",
            "cc.bili.experimental.dynamicBodySystemStyle.v1",
        ]
        retiredKeys.forEach { defaults.set(true, forKey: $0) }

        _ = LibraryStore(userDefaults: defaults)

        for key in retiredKeys {
            XCTAssertNil(defaults.object(forKey: key))
        }
    }

    func testRetiredMineSettingsSearchExperimentPreferenceIsCleared() {
        let suiteName = "cc.bili.tests.retired-mine-search-experiment.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "cc.bili.experimental.mineSettingsSearch.v1"
        defaults.set(false, forKey: key)

        _ = LibraryStore(userDefaults: defaults)

        XCTAssertNil(defaults.object(forKey: key))
    }

    func testDynamicCommentHitAreaVisualizationExperimentDefaultsOffAndPersists() {
        let suiteName = "cc.bili.tests.dynamic-comment-hit-area.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initialStore = LibraryStore(userDefaults: defaults)
        XCTAssertFalse(initialStore.dynamicCommentHitAreaVisualizationExperimentEnabled)

        initialStore.setDynamicCommentHitAreaVisualizationExperimentEnabled(true)
        XCTAssertTrue(
            LibraryStore(userDefaults: defaults).dynamicCommentHitAreaVisualizationExperimentEnabled
        )

        initialStore.setDynamicCommentHitAreaVisualizationExperimentEnabled(false)
        XCTAssertFalse(
            LibraryStore(userDefaults: defaults).dynamicCommentHitAreaVisualizationExperimentEnabled
        )
    }

    func testStandardPageInsetIsAlwaysTwentyPoints() {
        let suiteName = "cc.bili.tests.unified-page-inset-metrics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LibraryStore(userDefaults: defaults)
        XCTAssertEqual(store.standardPageHorizontalInset, 20)

        let metrics = HomeFeedLayoutMetrics(
            mode: .doubleColumn,
            containerWidth: 390,
            standardHorizontalInset: store.standardPageHorizontalInset
        )
        XCTAssertEqual(metrics.feedHorizontalPadding, 20)
        XCTAssertEqual(metrics.singleColumnHorizontalPadding, 20)
    }

    func testVideoDetailActionButtonStyleDefaultsPlainAndPersists() {
        let suiteName = "cc.bili.tests.video-detail-inline-actions-style.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initialStore = LibraryStore(userDefaults: defaults)
        XCTAssertEqual(initialStore.videoDetailActionButtonStyle, .plain)

        initialStore.setVideoDetailActionButtonStyle(.liquidGlass)
        XCTAssertEqual(LibraryStore(userDefaults: defaults).videoDetailActionButtonStyle, .liquidGlass)

        initialStore.setVideoDetailActionButtonStyle(.plain)
        XCTAssertEqual(LibraryStore(userDefaults: defaults).videoDetailActionButtonStyle, .plain)
    }

    func testVideoDetailInlineActionsPlainLayoutUsesExpandedTouchTarget() {
        let plainLayout = VideoDetailActionStripLayout(
            contentWidth: 390,
            usesPlainStyle: true
        )

        XCTAssertEqual(plainLayout.rowHeight, 44)
        XCTAssertEqual(plainLayout.actionLabelSide, 32)
        XCTAssertEqual(plainLayout.avatarImageSide, 44)
        XCTAssertEqual(plainLayout.columnWidth, 44)
        XCTAssertEqual(plainLayout.followColumnWidth, 64)
        XCTAssertEqual(plainLayout.columnSpacing, (390 - 44 * 5 - 64) / 5)
        XCTAssertGreaterThan(plainLayout.rowHeight, VideoDetailActionStrip.Metrics.rowHeight)
    }

    func testRetiredVideoDetailExperimentPreferencesAreCleared() {
        let suiteName = "cc.bili.tests.retired-video-detail-experiments.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let retiredKeys = [
            "cc.bili.experimental.videoDetailInteractiveScrollCollapse.v1",
            "cc.bili.experimental.videoDetailInitialAspectRatio.v1",
            "cc.bili.experimental.dynamicDetailHorizontalInset.v1",
            "cc.bili.experimental.videoDetailInlineActionsPlainStyle.v1",
        ]
        retiredKeys.forEach { defaults.set(true, forKey: $0) }

        _ = LibraryStore(userDefaults: defaults)

        for key in retiredKeys {
            XCTAssertNil(defaults.object(forKey: key))
        }
    }

    func testRetiredSocialExperimentPreferencesAreCleared() {
        let suiteName = "cc.bili.tests.retired-social-experiments.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let retiredKeys = [
            "cc.bili.experimental.videoDetailToolbarCommentComposer.v1",
            "cc.bili.experimental.commentSheetPrimaryAuthorName.v1",
            "cc.bili.dynamic.realLikeExperimentEnabled.v1",
            "cc.bili.comment.likeExperimentEnabled.v1",
            "cc.bili.dynamic.imageTextDetailExperimentEnabled.v1",
            "cc.bili.dynamic.commentPublishExperimentEnabled.v1",
            "cc.bili.dynamic.commentReplyPublishExperimentEnabled.v1",
            "cc.bili.experimental.dynamicDetailCommentSpacing.v1",
            "cc.bili.experimental.scrollMinimizingTabBar.v1",
            "cc.bili.experimental.videoDetailToolbarCommentComposer.v1",
            "cc.bili.experimental.commentSheetPrimaryAuthorName.v1",
        ]
        retiredKeys.forEach { defaults.set(false, forKey: $0) }

        _ = LibraryStore(userDefaults: defaults)

        for key in retiredKeys {
            XCTAssertNil(defaults.object(forKey: key))
        }
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

}
