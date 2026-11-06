import SwiftUI

/// 分P（UGC）与分集（PGC 番剧）共用的紧凑选择数据。
/// UGC 的封面是视频级（详情封面），PGC 的封面是每集独立 `cover`。
struct VideoDetailCompactSelectionItem: Identifiable, Equatable {
    let id: Int
    let displayTitle: String
    let numberLabel: String?
    let durationText: String?
    let badgeText: String?
    let coverURLString: String?
    let isSelected: Bool
    let isSelectable: Bool
    let selectVideo: VideoItem?

    init(
        id: Int,
        displayTitle: String,
        numberLabel: String?,
        durationText: String?,
        badgeText: String?,
        coverURLString: String?,
        isSelected: Bool,
        isSelectable: Bool,
        selectVideo: VideoItem?
    ) {
        self.id = id
        self.displayTitle = displayTitle
        self.numberLabel = numberLabel
        self.durationText = durationText
        self.badgeText = badgeText
        self.coverURLString = coverURLString
        self.isSelected = isSelected
        self.isSelectable = isSelectable
        self.selectVideo = selectVideo
    }
}

extension VideoDetailCompactSelectionItem {
    init(page: VideoPage, isSelected: Bool, fallbackCoverURL: String?) {
        let number = "P\(page.page ?? 1)"
        let part = page.part?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.id = page.cid
        self.displayTitle = part.isEmpty ? number : part
        self.numberLabel = number
        self.durationText = page.duration.map { BiliFormatters.duration($0) }
        self.badgeText = nil
        self.coverURLString = fallbackCoverURL
        self.isSelected = isSelected
        self.isSelectable = true
        self.selectVideo = nil
    }
}

extension VideoDetailCompactSelectionItem {
    private static func seasonCover(_ season: PgcSeasonInfo) -> String? {
        let cover = season.cover?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (cover?.isEmpty ?? true) ? nil : cover?.normalizedBiliURL()
    }

    init(episode: PgcEpisode, season: PgcSeasonInfo, isSelected: Bool) {
        let video = episode.videoItem(in: season)
        self.id = episode.id
        self.displayTitle = episode.displayTitle
        self.numberLabel = nil
        self.durationText = episode.durationSeconds.map { BiliFormatters.duration($0) }
        let badge = episode.badge?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.badgeText = (badge?.isEmpty ?? true) ? nil : badge
        let episodeCover = episode.cover?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEpisodeCover = (episodeCover?.isEmpty ?? true) ? nil : episodeCover?.normalizedBiliURL()
        self.coverURLString = trimmedEpisodeCover ?? Self.seasonCover(season)
        self.isSelected = isSelected
        // 与旧分集瓦片一致：无 CID 或无封面（含季封面兜底）视为不可播放，置灰展示。
        self.isSelectable = video != nil && coverURLString != nil
        self.selectVideo = isSelectable ? video : nil
    }
}

/// 实验开关开启时的单行入口：区块名 + 当前选中项 + 总数，点按打开选择弹窗。
struct VideoDetailCompactEntryButton: View {
    let sectionTitle: String
    let countUnit: String
    let items: [VideoDetailCompactSelectionItem]
    let accessibilityIdentifier: String
    @Binding var showsSheet: Bool

    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    private var currentItem: VideoDetailCompactSelectionItem? {
        items.first { $0.isSelected } ?? items.first
    }

    var body: some View {
        Button {
            showsSheet = true
        } label: {
            HStack(spacing: 10) {
                Text(sectionTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(currentText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Text("\(items.count) \(countUnit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Image(systemName: "triangle.fill")
                    .font(.caption2.weight(.bold))
                    .rotationEffect(.degrees(180))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: shape)
            .overlay {
                shape.strokeBorder(Color(.separator).opacity(0.16), lineWidth: 0.8)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("点按查看全部\(sectionTitle)")
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var currentText: String {
        guard let current = currentItem else { return "" }
        guard let numberLabel = current.numberLabel, current.displayTitle != numberLabel else {
            return current.displayTitle
        }
        return "\(numberLabel) · \(current.displayTitle)"
    }

    private var accessibilityText: String {
        guard let current = currentItem else { return sectionTitle }
        let numberPart = current.numberLabel.map { "\($0) " } ?? ""
        return "\(sectionTitle)，当前 \(numberPart)\(current.displayTitle)，共 \(items.count) \(countUnit)"
    }
}

/// 紧凑选择弹窗：单列一行一项，左侧封面、右侧信息，行间分割线；
/// 左上角收起、右上角正序/倒序，图标不用主题色。
struct VideoDetailCompactSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let sectionTitle: String
    let items: [VideoDetailCompactSelectionItem]
    let selectItem: (VideoDetailCompactSelectionItem) -> Void

    @State private var isReverseOrder = false

    private var displayedItems: [VideoDetailCompactSelectionItem] {
        isReverseOrder ? items.reversed() : items
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(displayedItems.enumerated()), id: \.element.id) { index, item in
                        VideoDetailCompactSelectionRow(
                            item: item,
                            select: { selectItem(item) }
                        )
                        if index < displayedItems.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 18)
            }
            .hiddenInlineNavigationTitle()
            .nativeTopScrollEdgeEffect()
            .scrollContentBackground(.hidden)
            .background(.clear)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .tint(.secondary)
                    .accessibilityLabel("关闭")
                    .accessibilityIdentifier("video.detail.pageSheet.close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.smooth(duration: 0.2)) {
                            isReverseOrder.toggle()
                        }
                    } label: {
                        Image(systemName: isReverseOrder ? "arrow.down" : "arrow.up")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .tint(.secondary)
                    .accessibilityLabel(isReverseOrder ? "正序" : "倒序")
                    .accessibilityIdentifier("video.detail.pageSheet.order")
                }
            }
        }
        .accessibilityIdentifier("video.detail.pageSheet")
        .presentationDetents([.fraction(0.7)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.clear)
    }
}

private struct VideoDetailCompactSelectionRow: View {
    @Environment(\.dismiss) private var dismiss
    let item: VideoDetailCompactSelectionItem
    let select: () -> Void

    private static let coverSize = CGSize(width: 108, height: 61)

    var body: some View {
        Button {
            // 不可播放条目保持旧瓦片语义：置灰且点按无动作，不收起弹窗。
            guard item.isSelectable else { return }
            dismiss()
            guard !item.isSelected else { return }
            select()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                cover
                    .frame(width: Self.coverSize.width, height: Self.coverSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .top, spacing: 6) {
                        Text(item.displayTitle)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if item.isSelected {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                                .padding(.top, 2)
                        }
                    }

                    HStack(spacing: 6) {
                        if let numberLabel = item.numberLabel, numberLabel != item.displayTitle {
                            Text(numberLabel)
                        }
                        if let durationText = item.durationText {
                            Text(durationText)
                        }
                        if let badgeText = item.badgeText, !badgeText.isEmpty {
                            SearchSoftPill(badgeText)
                        }
                        if item.isSelected {
                            Text("当前播放")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                .foregroundStyle(.primary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(item.isSelectable ? 1 : 0.55)
        .accessibilityLabel(rowLabel)
        .accessibilityValue(item.isSelected ? "当前播放" : (item.isSelectable ? "" : "暂不可播放"))
    }

    @ViewBuilder
    private var cover: some View {
        if let coverURLString = item.coverURLString, let url = URL(string: coverURLString) {
            CachedRemoteImage(
                url: url,
                animatesAppearance: false
            ) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                BiliMediaPlaceholder(style: .video, iconSize: 16)
            }
        } else {
            BiliMediaPlaceholder(style: .video, iconSize: 16)
        }
    }

    private var rowLabel: String {
        guard let numberLabel = item.numberLabel, numberLabel != item.displayTitle else {
            return item.displayTitle
        }
        return "\(numberLabel) \(item.displayTitle)"
    }
}
