import SwiftUI

/// UGC 合集区块：数据来自详情响应自带的 `ugc_season`，无需额外请求。
/// 紧凑单行入口 + 共享单列弹窗；条目是独立视频，选集走 `selectUgcSeasonEpisode` 原地切换。
struct VideoDetailUgcSeasonSection: View {
    let season: UgcSeason?
    let detail: VideoItem
    let selectEpisode: (VideoItem) -> Void

    @State private var isSeasonSheetPresented = false

    private var compactItems: [VideoDetailCompactSelectionItem] {
        guard let season, season.episodes.count > 1 else { return [] }
        return season.episodes.map { episode in
            VideoDetailCompactSelectionItem(
                ugcSeasonEpisode: episode,
                season: season,
                isSelected: episode.matches(detail: detail)
            )
        }
    }

    var body: some View {
        if !compactItems.isEmpty {
            VideoDetailCompactEntryButton(
                sectionTitle: "合集",
                countUnit: "个",
                items: compactItems,
                accessibilityIdentifier: "video.detail.seasonMenu.compact",
                showsSheet: $isSeasonSheetPresented
            )
            .sheet(isPresented: $isSeasonSheetPresented) {
                VideoDetailCompactSelectionSheet(
                    sectionTitle: "全部合集",
                    items: compactItems,
                    selectItem: { item in
                        guard let video = item.selectVideo else { return }
                        selectEpisode(video)
                    }
                )
            }
        }
    }
}

extension UgcSeasonEpisode {
    /// 合集条目按 bvid 匹配当前视频；无 bvid 的条目本就不可选。
    func matches(detail: VideoItem) -> Bool {
        bvid == detail.bvid
    }
}
