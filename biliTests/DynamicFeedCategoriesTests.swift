import Foundation
import XCTest

@testable import bili

@MainActor
final class DynamicFeedCategoriesTests: XCTestCase {
    func testExperimentDefaultsOffAndPersistsWithoutChangingOtherSettings() {
        let suite = "DynamicFeedCategoriesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LibraryStore(userDefaults: defaults)
        XCTAssertFalse(store.dynamicFeedCategoriesExperimentEnabled)
        store.setFollowsSystemFontSize(false)
        store.setDynamicFeedCategoriesExperimentEnabled(true)
        XCTAssertTrue(LibraryStore(userDefaults: defaults).dynamicFeedCategoriesExperimentEnabled)
        store.setDynamicFeedCategoriesExperimentEnabled(false)
        let restored = LibraryStore(userDefaults: defaults)
        XCTAssertFalse(restored.dynamicFeedCategoriesExperimentEnabled)
        XCTAssertFalse(restored.followsSystemFontSize)
        XCTAssertTrue(MineSearchCatalog.search("动态分类").contains { $0.route == .developerDiagnostics })
    }

    func testCategoryAndUPCachesKeepSeparateScrollPositionsAndEvictOldUP() throws {
        let suite = "DynamicFeedCategoriesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LibraryStore(userDefaults: defaults)
        store.setDynamicFeedCategoriesExperimentEnabled(true)
        let session = SessionStore(keychain: KeychainStore(service: suite))
        let api = BiliAPIClient(sessionStore: session, libraryStore: store, homeRecommendDiagnosticsStore: .shared)
        let holder = DynamicViewModelHolder(api: api, libraryStore: store, sessionStore: session)
        let all = try XCTUnwrap(holder.viewModel)
        all.savedScrollOffset = 80
        holder.selectFeed(.pgc, api: api, libraryStore: store, sessionStore: session)
        let pgc = try XCTUnwrap(holder.viewModel)
        pgc.savedScrollOffset = 160
        holder.selectFeed(.article, api: api, libraryStore: store, sessionStore: session)
        let article = try XCTUnwrap(holder.viewModel)
        article.savedScrollOffset = 240
        holder.selectFeed(.up, hostMID: 101, api: api, libraryStore: store, sessionStore: session)
        let firstUP = try XCTUnwrap(holder.viewModel)
        firstUP.savedScrollOffset = 320
        holder.selectFeed(.up, hostMID: 102, api: api, libraryStore: store, sessionStore: session)
        XCTAssertFalse(holder.viewModel === firstUP)
        holder.selectFeed(.up, hostMID: 101, api: api, libraryStore: store, sessionStore: session)
        XCTAssertTrue(holder.viewModel === firstUP)
        XCTAssertEqual(holder.viewModel?.savedScrollOffset, 320)
        for mid in [102, 103, 104] {
            holder.selectFeed(.up, hostMID: mid, api: api, libraryStore: store, sessionStore: session)
        }
        XCTAssertEqual(firstUP.savedScrollOffset, 0, "Eviction invalidates old account-bound data")
        holder.selectFeed(.up, hostMID: 101, api: api, libraryStore: store, sessionStore: session)
        XCTAssertFalse(holder.viewModel === firstUP)
        for (kind, expected, offset) in [(DynamicFeedKind.all, all, 80), (.pgc, pgc, 160), (.article, article, 240)] {
            holder.selectFeed(kind, api: api, libraryStore: store, sessionStore: session)
            XCTAssertTrue(holder.viewModel === expected)
            XCTAssertEqual(holder.viewModel?.savedScrollOffset, CGFloat(offset))
            XCTAssertTrue(holder.topUploaderStripViewModel === all)
        }
        holder.reconfigure(api: api, libraryStore: store, sessionStore: session)
        XCTAssertEqual(holder.viewModel?.feedKind, .all)
        XCTAssertFalse(holder.viewModel === all)
        XCTAssertEqual(all.savedScrollOffset, 0)
        XCTAssertEqual(article.savedScrollOffset, 0)
    }

    func testArticleMetadataAndOrdinaryOpusClassification() throws {
        let items = try JSONDecoder.bili.decode([DynamicFeedItem].self, from: Data(#"""
        [
          {"id_str":"legacy","type":"DYNAMIC_TYPE_ARTICLE","modules":{"module_dynamic":{"major":{"article":{"id":123,"title":"专栏标题","desc":"摘要","covers":["//i0.hdslb.com/cover.jpg"],"jump_url":"bilibili://article/123"}}}}},
          {"id_str":"100","type":"DYNAMIC_TYPE_ARTICLE","modules":{"module_dynamic":{"major":{"opus":{"opus_id":"200","title":"新版专栏","summary":{"text":"内容"},"jump_url":"//www.bilibili.com/opus/200"}}}}},
          {"id_str":"photo","type":"DYNAMIC_TYPE_DRAW","modules":{"module_dynamic":{"major":{"opus":{"title":"普通图文","summary":{"text":"图文内容"}}}}}},
          {"id_str":"pgc","type":"DYNAMIC_TYPE_PGC","modules":{"module_dynamic":{"major":{"pgc":{"title":"番剧","epid":101}}}}}
        ]
        """#.utf8))
        let legacy = try XCTUnwrap(items[0].article)
        XCTAssertEqual(legacy.title, "专栏标题")
        XCTAssertEqual(legacy.summary, "摘要")
        XCTAssertEqual(legacy.cover, "https://i0.hdslb.com/cover.jpg")
        XCTAssertEqual(legacy.url?.absoluteString, "https://www.bilibili.com/read/cv123")
        XCTAssertEqual(items[1].article?.url?.absoluteString, "https://www.bilibili.com/opus/200")
        XCTAssertNil(items[2].article, "A normal opus image post must not be classified as an article")
        XCTAssertNotNil(items[2].opusArticle, "The server article feed can explicitly render an opus as an article")
        XCTAssertEqual(items.filter { DynamicFeedKind.pgc.includes($0) }.map(\.id), ["pgc"])
        let suite = "DynamicFeedCategoriesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LibraryStore(userDefaults: defaults)
        store.setDynamicFeedCategoriesExperimentEnabled(true)
        let filter = DynamicFeedContentFilter(libraryStore: store)
        XCTAssertEqual(filter.displayable(items).map(\.id), items.map(\.id))
        XCTAssertEqual(filter.uniqueAppendItems([items[0], items[1], items[1]], to: [items[0]]).map(\.id), ["legacy", "100"])
    }
}
