import Combine
import SwiftUI

/// Deterministic incremental shortest-column masonry planner for Dynamic waterfall feeds.
///
/// Existing items keep their assigned column across `loadMore` pagination so cards
/// never jump horizontally when new pages append. Rebalancing only occurs when
/// `columnCount` changes or the feed resets/refreshes.
@MainActor
final class DynamicWaterfallLayoutPlanner: ObservableObject {
    private var assignedColumnByID: [String: Int] = [:]
    private var columnHeights: [CGFloat] = []
    private var lastColumnCount = 0
    private var lastCardWidth: CGFloat = 0
    private var lastFirstItemID: String?

    func columns(
        for items: [DynamicFeedItem],
        columnCount: Int,
        cardWidth: CGFloat,
        rowSpacing: CGFloat = 10
    ) -> [[DynamicFeedItem]] {
        let count = max(1, columnCount)
        guard !items.isEmpty else {
            reset(columnCount: count, cardWidth: cardWidth, firstItemID: nil)
            return Array(repeating: [], count: count)
        }

        let firstID = items.first?.id
        let needsFullReset =
            lastColumnCount != count
            || abs(lastCardWidth - cardWidth) > 2
            || (lastFirstItemID != nil && lastFirstItemID != firstID)
            || items.count < assignedColumnByID.count

        if needsFullReset {
            reset(columnCount: count, cardWidth: cardWidth, firstItemID: firstID)
        } else if lastFirstItemID == nil {
            lastFirstItemID = firstID
        }

        var buckets = Array(repeating: [DynamicFeedItem](), count: count)
        if columnHeights.count != count {
            columnHeights = Array(repeating: 0, count: count)
        }

        var activeIDs = Set<String>()
        activeIDs.reserveCapacity(items.count)

        for item in items {
            activeIDs.insert(item.id)
            let columnIndex: Int
            if let existing = assignedColumnByID[item.id], existing >= 0, existing < count {
                columnIndex = existing
            } else {
                columnIndex = shortestColumnIndex(in: columnHeights)
                assignedColumnByID[item.id] = columnIndex
                let itemHeight = Self.estimatedCardHeight(for: item, cardWidth: cardWidth)
                columnHeights[columnIndex] += itemHeight + rowSpacing
            }
            buckets[columnIndex].append(item)
        }

        if assignedColumnByID.count > activeIDs.count {
            assignedColumnByID = assignedColumnByID.filter { activeIDs.contains($0.key) }
        }

        return buckets
    }

    private func reset(columnCount: Int, cardWidth: CGFloat, firstItemID: String?) {
        assignedColumnByID.removeAll(keepingCapacity: true)
        columnHeights = Array(repeating: 0, count: columnCount)
        lastColumnCount = columnCount
        lastCardWidth = cardWidth
        lastFirstItemID = firstItemID
    }

    private func shortestColumnIndex(in heights: [CGFloat]) -> Int {
        var bestIndex = 0
        var bestHeight = heights.first ?? 0
        for index in 1..<heights.count where heights[index] < bestHeight {
            bestHeight = heights[index]
            bestIndex = index
        }
        return bestIndex
    }

    /// Computes a deterministic visual aspect ratio (width / height) clamped to
    /// Xiaohongshu-friendly bounds `[0.72, 1.55]` so tall images don't starve
    /// neighboring columns and loading causes zero vertical layout jump.
    static func visualAspectRatio(for item: DynamicFeedItem, display: DynamicFeedCardDisplayModel) -> CGFloat? {
        if let firstImage = primaryImageItem(for: item, display: display) {
            if let size = firstImage.originalPixelSize, size.height > 0 {
                let raw = size.width / size.height
                return min(max(raw, 0.72), 1.42)
            }
            return 0.85
        }
        if display.video != nil || display.pgc != nil || display.live != nil || display.paidVideo != nil {
            return 1.55
        }
        if item.article?.cover != nil || item.opusArticle?.cover != nil {
            return 1.33
        }
        if let original = item.original,
           original.archive?.cover != nil
               || original.live?.cover != nil
               || original.modules?.moduleDynamic?.major?.article?.cover != nil {
            return 1.55
        }
        return nil
    }

    static func primaryImageItem(
        for item: DynamicFeedItem,
        display: DynamicFeedCardDisplayModel
    ) -> DynamicImageItem? {
        if let own = display.imageItems.first {
            return own
        }
        if let original = item.original {
            return original.imageItems.first(where: { $0.normalizedURL != nil })
        }
        return nil
    }

    static func estimatedCardHeight(for item: DynamicFeedItem, cardWidth: CGFloat) -> CGFloat {
        let safeWidth = max(cardWidth, 140)
        let display = DynamicFeedCardDisplayModel(item: item)
        let visualHeight: CGFloat
        if let ratio = visualAspectRatio(for: item, display: display), ratio > 0 {
            visualHeight = (safeWidth / ratio).rounded()
        } else {
            let excerptLength = (display.topLevelDisplayText ?? "").count
            visualHeight = excerptLength > 55 ? 128 : 104
        }
        let hasHeadline = !(headlineText(for: item, display: display).isEmpty)
        let textHeight: CGFloat = hasHeadline ? 38 : 0
        let footerHeight: CGFloat = 34
        return visualHeight + textHeight + footerHeight + 14
    }

    static func headlineText(
        for item: DynamicFeedItem,
        display: DynamicFeedCardDisplayModel
    ) -> String {
        if let title = display.video?.title.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }
        if let title = display.pgc?.title.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }
        if let title = display.live?.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }
        if let title = display.paidContent?.title.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }
        if let title = (item.article?.title ?? item.opusArticle?.title)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }
        if let text = display.topLevelDisplayText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }
        if let origText = item.original.flatMap({ DynamicTextSegment.displayText(from: $0.textSegments) })?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !origText.isEmpty {
            return origText
        }
        if let origTitle = item.original?.archive?.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !origTitle.isEmpty {
            return origTitle
        }
        return ""
    }
}

struct DynamicWaterfallFeedView: View {
    let api: BiliAPIClient
    @ObservedObject var viewModel: DynamicViewModel
    let items: [DynamicFeedItem]
    let contentWidth: CGFloat
    let columnCount: Int
    @StateObject private var planner = DynamicWaterfallLayoutPlanner()

    private let columnSpacing: CGFloat = 12
    private let rowSpacing: CGFloat = 12

    private var cardWidth: CGFloat {
        let count = CGFloat(max(1, columnCount))
        let totalSpacing = columnSpacing * max(0, count - 1)
        return max(floor((contentWidth - totalSpacing) / count), 120)
    }

    private var lastItemID: String? {
        items.last?.id
    }

    var body: some View {
        let columns = planner.columns(
            for: items,
            columnCount: columnCount,
            cardWidth: cardWidth,
            rowSpacing: rowSpacing
        )

        HStack(alignment: .top, spacing: columnSpacing) {
            ForEach(0..<columns.count, id: \.self) { columnIndex in
                LazyVStack(spacing: rowSpacing) {
                    ForEach(columns[columnIndex]) { item in
                        DynamicWaterfallCard(
                            item: item,
                            api: api,
                            cardWidth: cardWidth
                        )
                        .dynamicLoadMoreTask(if: item.id == lastItemID, id: item.id) {
                            await viewModel.loadMoreIfNeeded(current: item)
                        }
                    }
                }
                .frame(width: cardWidth)
            }
        }
        .frame(width: contentWidth, alignment: .top)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dynamic.feed.waterfall")
    }
}

enum DynamicUniformGridMetrics {
    static let videoAspectRatio: CGFloat = 16.0 / 9.0
    static let headlineLineAreaHeight: CGFloat = 36
    static let headlineTopPadding: CGFloat = 9
    static let headlineBottomPadding: CGFloat = 5
    static let headlineTotalHeight: CGFloat = headlineLineAreaHeight + headlineTopPadding + headlineBottomPadding

    static func mediaHeight(forCardWidth cardWidth: CGFloat) -> CGFloat {
        (max(cardWidth, 1) / videoAspectRatio).rounded()
    }

    static func textOnlyBodyHeight(forCardWidth cardWidth: CGFloat) -> CGFloat {
        mediaHeight(forCardWidth: cardWidth) + headlineTotalHeight
    }
}

struct DynamicUniformGridFeedView: View {
    let api: BiliAPIClient
    @ObservedObject var viewModel: DynamicViewModel
    let items: [DynamicFeedItem]
    let contentWidth: CGFloat
    let columnCount: Int

    private let columnSpacing: CGFloat = 10

    private var safeColumnCount: Int {
        max(1, columnCount)
    }

    private var cardWidth: CGFloat {
        let totalSpacing = columnSpacing * CGFloat(max(safeColumnCount - 1, 0))
        return max(floor((contentWidth - totalSpacing) / CGFloat(safeColumnCount)), 120)
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(cardWidth), spacing: columnSpacing, alignment: .top),
            count: safeColumnCount
        )
    }

    var body: some View {
        LazyVGrid(columns: gridColumns, alignment: .center, spacing: 10) {
            ForEach(items) { item in
                DynamicWaterfallCard(
                    item: item,
                    api: api,
                    cardWidth: cardWidth,
                    uniformVideoCardHeight: true
                )
                .onAppear {
                    Task { await viewModel.loadMoreIfNeeded(current: item) }
                }
            }
        }
        .padding(.top, 8)
        .accessibilityIdentifier("dynamic.feed.uniformGrid")
    }
}

private struct DynamicWaterfallCard: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.appThemeTintColor) private var appTintColor
    @Environment(\.dynamicArticleFeedContext) private var articleFeedContext
    @Environment(\.dynamicDetailNavigationPath) private var detailNavigationPath
    @Environment(\.openVideoAction) private var openVideoAction
    @Environment(\.openLiveRoomAction) private var openLiveRoomAction
    @Environment(\.openPgcSeasonRouteAction) private var openPgcSeasonRouteAction
    @Environment(\.openVideoOwnerRouteAction) private var openVideoOwnerRouteAction

    let item: DynamicFeedItem
    let api: BiliAPIClient
    let cardWidth: CGFloat
    let uniformVideoCardHeight: Bool

    private let display: DynamicFeedCardDisplayModel
    @State private var likeState: DynamicLikeDisplayState
    @State private var isMutatingLike = false

    init(
        item: DynamicFeedItem,
        api: BiliAPIClient,
        cardWidth: CGFloat,
        uniformVideoCardHeight: Bool = false
    ) {
        self.item = item
        self.api = api
        self.cardWidth = cardWidth
        self.uniformVideoCardHeight = uniformVideoCardHeight
        let display = DynamicFeedCardDisplayModel(item: item)
        self.display = display
        _likeState = State(initialValue: DynamicLikeDisplayState(
            isLiked: item.isLiked,
            likeCount: display.initialLikeCount
        ))
    }

    private var headline: String {
        DynamicWaterfallLayoutPlanner.headlineText(for: item, display: display)
    }

    private var coverURL: URL? {
        if let image = DynamicWaterfallLayoutPlanner.primaryImageItem(for: item, display: display),
           let normalized = image.normalizedURL {
            return URL(string: normalized)
        }
        if let cover = display.video?.pic?.normalizedBiliURL() {
            return URL(string: cover)
        }
        if let cover = display.pgc?.cover?.normalizedBiliURL() {
            return URL(string: cover)
        }
        if let cover = display.live?.cover?.normalizedBiliURL() {
            return URL(string: cover)
        }
        if let cover = display.paidVideo?.pic?.normalizedBiliURL() {
            return URL(string: cover)
        }
        if let cover = (item.article?.cover ?? item.opusArticle?.cover)?.normalizedBiliURL() {
            return URL(string: cover)
        }
        if let cover = (item.original?.archive?.cover
            ?? item.original?.live?.cover
            ?? item.original?.modules?.moduleDynamic?.major?.article?.cover)?.normalizedBiliURL() {
            return URL(string: cover)
        }
        return nil
    }

    private var mediaAspectRatio: CGFloat? {
        if uniformVideoCardHeight {
            return coverURL != nil ? DynamicUniformGridMetrics.videoAspectRatio : nil
        }
        return DynamicWaterfallLayoutPlanner.visualAspectRatio(for: item, display: display)
    }

    private var topRightBadgeText: String? {
        if display.imageItems.count > 1 {
            return "1/\(display.imageItems.count)"
        }
        if let first = display.imageItems.first {
            if first.isLivePhotoFlag { return "实况" }
            if first.isAnimatedGIFFlag { return "GIF" }
        }
        if display.live != nil {
            return "直播中"
        }
        if display.pgc != nil {
            return "番剧"
        }
        if item.isForward || item.original != nil {
            return "转发"
        }
        if item.article != nil || (articleFeedContext && item.opusArticle != nil) {
            return "专栏"
        }
        return nil
    }

    private var bottomRightDurationText: String? {
        if let duration = display.videoDisplay?.durationText, !duration.isEmpty {
            return duration
        }
        if let text = display.pgc?.durationText, !text.isEmpty {
            return text
        }
        return nil
    }

    private let cardCornerRadius: CGFloat = 18

    private var coverShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: cardCornerRadius,
            topTrailingRadius: cardCornerRadius,
            style: .continuous
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: openCardDestination) {
                VStack(alignment: .leading, spacing: 0) {
                    mediaHeader

                    if uniformVideoCardHeight {
                        if coverURL != nil {
                            Text(headline.isEmpty ? " " : headline)
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: DynamicUniformGridMetrics.headlineLineAreaHeight,
                                    maxHeight: DynamicUniformGridMetrics.headlineLineAreaHeight,
                                    alignment: .topLeading
                                )
                                .padding(.horizontal, 10)
                                .padding(.top, DynamicUniformGridMetrics.headlineTopPadding)
                                .padding(.bottom, DynamicUniformGridMetrics.headlineBottomPadding)
                        }
                    } else if !headline.isEmpty, coverURL != nil {
                        Text(headline)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.top, 9)
                            .padding(.bottom, 5)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            footerRow
                .padding(.horizontal, 10)
                .padding(.top, uniformVideoCardHeight ? 4 : (coverURL == nil ? 8 : 4))
                .padding(.bottom, 10)
        }
        .frame(width: cardWidth, alignment: .leading)
        .videoCardBorderedSurface(
            cornerRadius: cardCornerRadius,
            showsShadow: libraryStore.showsDynamicMultiColumnCardShadow
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            uniformVideoCardHeight
                ? "dynamic.uniformGrid.card.\(display.dynamicID)"
                : "dynamic.waterfall.card.\(display.dynamicID)"
        )
    }

    @ViewBuilder
    private var mediaHeader: some View {
        if let coverURL, let ratio = mediaAspectRatio, ratio > 0 {
            let mediaHeight = (cardWidth / ratio).rounded()
            ZStack {
                Color(.tertiarySystemFill)
                CachedRemoteImage(
                    url: coverURL,
                    targetPixelSize: Int(max(cardWidth, mediaHeight) * 2),
                    animatesAppearance: false
                ) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Color(.tertiarySystemFill)
                }
            }
            .frame(width: cardWidth, height: mediaHeight)
            .clipped()
            .overlay(alignment: .topTrailing) {
                if let badge = topRightBadgeText {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(display.live != nil ? Color.pink.opacity(0.88) : Color.black.opacity(0.55))
                        )
                        .padding(7)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let duration = bottomRightDurationText {
                    Text(duration)
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.62))
                        )
                        .padding(7)
                }
            }
            .videoCardBorderedCover(in: coverShape)
        } else {
            // Pure-text / forward-without-image card styled cleanly inside the bordered card shell.
            VStack(alignment: .leading, spacing: 6) {
                if item.isForward || item.original != nil {
                    Text("转发动态")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                Text(headline.isEmpty ? "查看动态详情" : headline)
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(uniformVideoCardHeight ? nil : 5)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(11)
            .frame(
                width: cardWidth,
                height: uniformVideoCardHeight ? DynamicUniformGridMetrics.textOnlyBodyHeight(forCardWidth: cardWidth) : nil,
                alignment: .topLeading
            )
            .frame(minHeight: uniformVideoCardHeight ? nil : 96, alignment: .topLeading)
            .clipped()
            .background(Color(.tertiarySystemFill).opacity(0.55))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color(.separator).opacity(0.22))
                    .frame(height: 0.5)
            }
        }
    }

    private var footerRow: some View {
        HStack(spacing: 6) {
            Button {
                if let owner = display.authorOwner {
                    openVideoOwnerRouteAction?(owner)
                }
            } label: {
                HStack(spacing: 5) {
                    AvatarRemoteImage(urlString: display.authorAvatarURLString, pixelSize: 64) {
                        Circle()
                            .fill(Color(.tertiarySystemFill))
                    }
                    .frame(width: 18, height: 18)
                    .clipShape(Circle())

                    Text(display.authorName)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .disabled(display.authorOwner == nil)

            Spacer(minLength: 4)

            Button(action: toggleLike) {
                HStack(spacing: 3) {
                    Image(systemName: likeState.isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(likeState.isLiked ? appTintColor : Color.secondary)
                    if likeState.likeCount > 0 {
                        Text(BiliFormatters.compactCount(likeState.likeCount))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(likeState.isLiked ? appTintColor : Color.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isMutatingLike)
            .accessibilityLabel(likeState.isLiked ? "取消点赞" : "点赞")
        }
    }

    private func openCardDestination() {
        if let video = display.video ?? display.paidVideo {
            openVideoAction?(video)
            return
        }
        if let liveRoom = display.liveRoom {
            openLiveRoomAction?(liveRoom)
            return
        }
        if let pgc = display.pgc, let route = pgc.playbackRoute {
            openPgcSeasonRouteAction?(route)
            return
        }
        let article = item.article ?? (articleFeedContext ? item.opusArticle : nil)
        if !item.isForward,
           item.original == nil,
           let article,
           let route = article.route(from: item),
           route.supportsNativeReader,
           let detailNavigationPath {
            detailNavigationPath.wrappedValue.append(route)
            return
        }
        if let detailNavigationPath {
            detailNavigationPath.wrappedValue.append(DynamicDetailTarget.loaded(item))
        }
    }

    private func toggleLike() {
        let account = sessionStore.credentialSnapshot(
            for: .interaction,
            multiAccountEnabled: libraryStore.multiAccountEnabled
        )
        guard account.isLoggedIn, !isMutatingLike else { return }

        let previous = likeState
        let target = previous.toggled()
        isMutatingLike = true
        withAnimation(.snappy(duration: 0.2)) {
            likeState = target
        }

        Task { @MainActor in
            do {
                try await dependencies.api.setDynamicLike(
                    dynamicID: display.dynamicID,
                    liked: target.isLiked
                )
            } catch {
                withAnimation(.snappy(duration: 0.2)) {
                    likeState = previous
                }
            }
            isMutatingLike = false
        }
    }
}
