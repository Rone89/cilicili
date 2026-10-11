#if DEBUG
import SwiftUI

/// No cookies or playback requests: capture the production card's selected route.
struct UITestDynamicPGCFixtureView: View {
    let api: BiliAPIClient
    @State private var selectedEpisodeID: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text(selectedEpisodeID.map(String.init) ?? "未选择")
                        .accessibilityIdentifier("pgc.fixture.episode")
                    ForEach(Self.items) { item in
                        DynamicFeedCard(item: item, api: api, allowsDetailNavigation: false, showsActionBar: false)
                        Divider()
                    }
                }
                .padding(20)
            }
        }
        .environment(\.openPgcSeasonRouteAction, { selectedEpisodeID = $0.episodeID })
    }

    private static let items: [DynamicFeedItem] = {
        let json = #"""
        [
          {"id_str":"100001","type":"DYNAMIC_TYPE_PGC_UNION","modules":{"module_author":{"mid":1,"name":"番剧测试"},"module_dynamic":{"major":{"pgc":{"title":"测试番剧第一集","epid":101,"duration_text":"24:00","badge":{"text":"会员"}}}}}},
          {"id_str":"100002","type":"DYNAMIC_TYPE_FORWARD","modules":{"module_dynamic":{"desc":{"text":"转发番剧"}}},"orig":{"id_str":"100003","type":"DYNAMIC_TYPE_PGC","modules":{"module_dynamic":{"major":{"pgc":{"title":"转发番剧第二集","epid":102}}}}}}
        ]
        """#
        return try! JSONDecoder.bili.decode([DynamicFeedItem].self, from: Data(json.utf8))
    }()
}
#endif
