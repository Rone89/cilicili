import SwiftUI

/// UGC 合集区块：数据来自详情响应自带的 `ugc_season`，无需额外请求。
/// 实验开启时用紧凑单行入口 + 共享单列弹窗；关闭时保持横滑瓦片形态。
/// 条目是独立视频，选集走 `selectUgcSeasonEpisode` 原地切换。
struct VideoDetailUgcSeasonSection: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let season: UgcSeason?
    let detail: VideoItem
    let selectEpisode: (VideoItem) -> Void

    @State private var isSeasonSheetPresented = false

    private var episodes: [UgcSeasonEpisode] {
        season?.episodes ?? []
    }

    private var compactItems: [VideoDetailCompactSelectionItem] {
        guard let season else { return [] }
        return episodes.map { episode in
            VideoDetailCompactSelectionItem(
                ugcSeasonEpisode: episode,
                season: season,
                isSelected: episode.matches(detail: detail)
            )
        }
    }

    var body: some View {
        if episodes.count > 1 {
            Group {
                if libraryStore.videoDetailCompactPageSelectorExperimentEnabled {
                    VideoDetailCompactEntryButton(
                        sectionTitle: "合集",
                        countUnit: "个",
                        items: compactItems,
                        accessibilityIdentifier: "video.detail.seasonMenu.compact",
                        showsSheet: $isSeasonSheetPresented
                    )
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        VideoDetailUgcSeasonHeader(
                            episodeCount: episodes.count,
                            showsSeasonSheet: $isSeasonSheetPresented
                        )

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 10) {
                                ForEach(compactItems) { item in
                                    VideoDetailUgcSeasonRoute(
                                        item: item,
                                        selectEpisode: selectEpisode
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, -16)
                        .contentMargins(.horizontal, 16, for: .scrollContent)
                        .frame(height: 54)
                    }
                    .accessibilityIdentifier("video.detail.seasonMenu")
                }
            }
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

private struct VideoDetailUgcSeasonHeader: View {
    let episodeCount: Int
    @Binding var showsSeasonSheet: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text("合集")
                .font(.headline)

            Text("\(episodeCount) 个")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                showsSeasonSheet = true
            } label: {
                Image(systemName: "triangle.fill")
                    .font(.caption.weight(.bold))
                    .rotationEffect(.degrees(180))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("展开全部合集")
        }
    }
}

private struct VideoDetailUgcSeasonRoute: View {
    let item: VideoDetailCompactSelectionItem
    let selectEpisode: (VideoItem) -> Void

    var body: some View {
        if item.isSelected || !item.isSelectable {
            VideoDetailUgcSeasonTile(item: item)
        } else {
            Button {
                guard let video = item.selectVideo else { return }
                selectEpisode(video)
            } label: {
                VideoDetailUgcSeasonTile(item: item)
            }
            .buttonStyle(.plain)
            // 标签放在 Button 层，避免与内层 tile 合并出重复标签（与共享弹窗行一致）。
            .accessibilityLabel(item.displayTitle)
            .accessibilityValue(item.isSelectable ? "" : "暂不可播放")
        }
    }
}

private struct VideoDetailUgcSeasonTile: View {
    let item: VideoDetailCompactSelectionItem

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            Text(item.displayTitle)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.9)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            HStack(spacing: 8) {
                if let durationText = item.durationText {
                    Text(durationText)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 124, height: 54, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: shape)
        .overlay {
            shape.strokeBorder(
                item.isSelected ? Color(.separator).opacity(0.4) : Color(.separator).opacity(0.16),
                lineWidth: item.isSelected ? 1.4 : 0.8
            )
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(item.isSelectable ? 1 : 0.55)
        .accessibilityLabel(item.displayTitle)
        .accessibilityValue(item.isSelected ? "当前播放" : (item.isSelectable ? "" : "暂不可播放"))
    }
}
