import Foundation
import XCTest

@testable import bili

@MainActor
final class DynamicVideoFilterTests: XCTestCase {
    func testExperimentDefaultsOffAndPersistsWithoutChangingOtherSettings() {
        let suite = "DynamicVideoFilterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LibraryStore(userDefaults: defaults)
        XCTAssertFalse(store.dynamicVideoFilterExperimentEnabled)
        store.setFollowsSystemFontSize(false)
        store.setDynamicVideoFilterExperimentEnabled(true)
        XCTAssertTrue(LibraryStore(userDefaults: defaults).dynamicVideoFilterExperimentEnabled)
        store.setDynamicVideoFilterExperimentEnabled(false)
        let restored = LibraryStore(userDefaults: defaults)
        XCTAssertFalse(restored.dynamicVideoFilterExperimentEnabled)
        XCTAssertFalse(restored.followsSystemFontSize)
    }

    func testVideoFilterExcludesForwardedVideoLivePGCAndMissingArchive() throws {
        let data = Data(#"""
        [
          {"id_str":"video","type":"DYNAMIC_TYPE_AV","modules":{"module_dynamic":{"major":{"archive":{"bvid":"BV1test","title":"投稿"}}}}},
          {"id_str":"forward","type":"DYNAMIC_TYPE_FORWARD","orig":{"type":"DYNAMIC_TYPE_AV","modules":{"module_dynamic":{"major":{"archive":{"bvid":"BV1test"}}}}}},
          {"id_str":"live","type":"DYNAMIC_TYPE_LIVE_RCMD"},
          {"id_str":"pgc","type":"DYNAMIC_TYPE_PGC"},
          {"id_str":"text","type":"DYNAMIC_TYPE_WORD"},
          {"id_str":"missing","type":"DYNAMIC_TYPE_AV"}
        ]
        """#.utf8)
        let items = try JSONDecoder.bili.decode([DynamicFeedItem].self, from: data)
        XCTAssertEqual(items.filter { DynamicFeedKind.video.includes($0) }.map(\.id), ["video"])
        XCTAssertEqual(items.filter { DynamicFeedKind.all.includes($0) }.count, items.count)
    }

    func testSwitchingFeedsRetainsSeparateModelsAndAccountResetClearsBoth() async throws {
        let suite = "DynamicVideoFilterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LibraryStore(userDefaults: defaults)
        let session = SessionStore(keychain: KeychainStore(service: suite))
        let api = BiliAPIClient(sessionStore: session, libraryStore: store, homeRecommendDiagnosticsStore: .shared)
        let holder = DynamicViewModelHolder(api: api, libraryStore: store, sessionStore: session)
        let all = try XCTUnwrap(holder.viewModel)
        XCTAssertTrue(holder.topUploaderStripViewModel === all)
        holder.selectFeed(.video, api: api, libraryStore: store, sessionStore: session)
        let video = try XCTUnwrap(holder.viewModel)
        XCTAssertFalse(all === video)
        XCTAssertTrue(holder.topUploaderStripViewModel === all)
        await video.loadInitial()
        XCTAssertTrue(video.items.isEmpty)
        XCTAssertFalse(video.state.isLoading)
        XCTAssertFalse(video.hasMoreItems)
        holder.selectFeed(.all, api: api, libraryStore: store, sessionStore: session)
        XCTAssertTrue(holder.viewModel === all)
        holder.selectFeed(.video, api: api, libraryStore: store, sessionStore: session)
        XCTAssertTrue(holder.viewModel === video)
        holder.reconfigure(api: api, libraryStore: store, sessionStore: session)
        XCTAssertEqual(holder.viewModel?.feedKind, .all)
        XCTAssertFalse(holder.viewModel === all)
        let newStripModel = try XCTUnwrap(holder.topUploaderStripViewModel)
        XCTAssertTrue(newStripModel === holder.viewModel)
        XCTAssertFalse(newStripModel === all)
        holder.selectFeed(.video, api: api, libraryStore: store, sessionStore: session)
        XCTAssertFalse(holder.viewModel === video)
        XCTAssertTrue(holder.topUploaderStripViewModel === newStripModel)
    }
}
