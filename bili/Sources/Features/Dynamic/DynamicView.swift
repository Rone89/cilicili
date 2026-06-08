import SwiftUI
import Combine
import UIKit

struct DynamicView: View {
    @EnvironmentObject private var dependencies: AppDependencies

    var body: some View {
        DynamicContentRoot(
            api: dependencies.api,
            libraryStore: dependencies.libraryStore,
            sessionStore: dependencies.sessionStore
        )
        .navigationTitle("动态")
        .navigationBarTitleDisplayMode(.inline)
        .nativeTopNavigationChrome()
    }
}

private struct DynamicContentRoot: View {
    let api: BiliAPIClient
    let libraryStore: LibraryStore
    @ObservedObject var sessionStore: SessionStore
    @StateObject private var holder = DynamicViewModelHolder()

    var body: some View {
        Group {
            if let viewModel = holder.viewModel {
                content(viewModel, isLoggedIn: sessionStore.isLoggedIn)
            } else {
                initialContent(isLoggedIn: sessionStore.isLoggedIn)
                    .task {
                        holder.configure(
                            api: api,
                            libraryStore: libraryStore,
                            sessionStore: sessionStore
                        )
                    }
            }
        }
    }

    @ViewBuilder
    private func initialContent(isLoggedIn: Bool) -> some View {
        if isLoggedIn {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { index in
                        DynamicFeedSkeletonCard()

                        if index != 2 {
                            Divider()
                                .padding(.leading, 66)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
            }
            .rootFloatingTabBarContentPadding()
            .background(Color(.systemBackground))
        } else {
            dynamicLoginEmptyState
                .rootFloatingTabBarContentPadding()
                .background(Color(.systemBackground))
        }
    }

    @ViewBuilder
    private func content(_ viewModel: DynamicViewModel, isLoggedIn: Bool) -> some View {
        GeometryReader { proxy in
            let contentWidth = max(floor(proxy.size.width - 32), 0)

            ScrollView {
            LazyVStack(spacing: 0) {
                FollowedLiveStrip(rooms: viewModel.followedLiveRooms)

                if !isLoggedIn {
                    dynamicLoginEmptyState
                        .frame(maxWidth: .infinity)
                        .padding(.top, 110)
                } else if viewModel.items.isEmpty && viewModel.state.isLoading {
                    ForEach(0..<3, id: \.self) { index in
                        DynamicFeedSkeletonCard()
                            .allowsHitTesting(false)

                        if index != 2 {
                            Divider()
                                .padding(.leading, 66)
                        }
                    }
                } else if viewModel.items.isEmpty {
                    EmptyStateView(
                        title: "暂无动态",
                        systemImage: "sparkles",
                        message: "登录后会显示你关注 UP 的动态。"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 110)
                } else {
                    let items = viewModel.items
                    let lastItemID = items.last?.id
                    ForEach(items) { item in
                        VStack(spacing: 0) {
                            DynamicFeedCard(
                                item: item,
                                api: api,
                                contentWidth: contentWidth
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .dynamicLoadMoreTask(if: item.id == lastItemID, id: item.id) {
                                await viewModel.loadMoreIfNeeded(current: item)
                            }

                            if item.id != lastItemID {
                                Divider()
                                    .padding(.leading, 66)
                            }
                        }
                    }

                    dynamicFooter(viewModel)
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 18)
        }
        .rootFloatingTabBarContentPadding()
        .nativeTopScrollEdgeEffect()
        .background(Color(.systemBackground))
        .refreshable {
            await viewModel.refresh()
        }
        .task(id: isLoggedIn) {
            await viewModel.loadInitial()
        }
        .overlay {
            if isLoggedIn, case .failed(let message) = viewModel.state, viewModel.items.isEmpty {
                ErrorStateView(title: "动态加载失败", message: message) {
                    Task { await viewModel.refresh() }
                }
                .background(.background.opacity(0.96))
            }
        }
        }
    }

    private var dynamicLoginEmptyState: some View {
        EmptyStateView(
            title: "暂无动态",
            systemImage: "sparkles",
            message: "登录后会显示你关注 UP 的动态。"
        )
    }

    @ViewBuilder
    private func dynamicFooter(_ viewModel: DynamicViewModel) -> some View {
        if viewModel.state.isLoading {
            DynamicFeedSkeletonCard()
                .allowsHitTesting(false)
        } else if viewModel.hasMoreItems {
            Button {
                Task { await viewModel.loadMore() }
            } label: {
                Label("加载更多", systemImage: "chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(.pink)
            .padding(.top, 10)
        } else {
            Text("没有更多动态了")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
    }
}

private struct FollowedLiveStrip: View {
    let rooms: [LiveRoom]

    var body: some View {
        if !rooms.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("正在直播")
                    .font(.headline)
                    .padding(.horizontal, 2)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(rooms) { room in
                            NavigationLink(value: room) {
                                FollowedLiveAvatar(room: room)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
            .padding(.top, 4)
            .padding(.bottom, 14)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

private struct FollowedLiveAvatar: View {
    let room: LiveRoom

    var body: some View {
        VStack(spacing: 7) {
            ZStack(alignment: .bottom) {
                AvatarRemoteImage(urlString: room.face, pixelSize: 120) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 58, height: 58)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(Color.pink.opacity(0.72), lineWidth: 2)
                }
                .mediaShadow(.regular)

                Text("直播中")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .frame(height: 17)
                    .background(Color.pink, in: Capsule())
                    .offset(y: 5)
            }

            Text(anchorName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 66)
        }
        .frame(width: 70)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(anchorName) 正在直播")
    }

    private var anchorName: String {
        room.uname.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "UP 主"
    }
}

private struct DynamicFeedCard: View {
    let item: DynamicFeedItem
    let api: BiliAPIClient
    let contentWidth: CGFloat?
    private let display: DynamicFeedCardDisplayModel
    @State private var commentsTarget: DynamicFeedItem?
    @State private var isTextExpanded = false

    init(
        item: DynamicFeedItem,
        api: BiliAPIClient,
        contentWidth: CGFloat? = nil
    ) {
        self.item = item
        self.api = api
        self.contentWidth = contentWidth
        let display = DynamicFeedCardDisplayModel(item: item)
        self.display = display
    }

    var body: some View {
        Group {
            if let video = display.video, display.usesHomeVideoCardStyle {
                homeVideoCard(video)
            } else if display.usesSeparatedDynamicLayout {
                separatedDynamicContent
            } else {
                dynamicCardContent
            }
        }
        .sheet(item: $commentsTarget) { target in
            DynamicCommentsSheet(item: target, api: api)
        }
    }

    private func homeVideoCard(_ video: VideoItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            authorHeader
                .padding(.horizontal, 12)

            VideoRouteLink(video) {
                VStack(alignment: .leading, spacing: 9) {
                    VStack(alignment: .leading, spacing: 0) {
                        StableVideoTitleText(video.title, style: .feedHeadline, lineLimit: 3)
                    }
                    .padding(.horizontal, 12)

                    if let videoDisplay = display.videoDisplay {
                        dynamicVideoCover(video, display: videoDisplay)
                    }
                }
                .contentShape(Rectangle())
            }

            actionBar
        }
        .padding(.top, 5)
        .padding(.bottom, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("鐟欏棝顣?\(video.title)")
    }

    private func dynamicVideoCover(_ video: VideoItem, display: VideoCardDisplayModel) -> some View {
        FixedAspectPreview(aspectRatio: 16 / 9) {
            ZStack {
                Color.clear

                AdaptiveVideoCoverImage(display: display, style: .maxSide)

                DynamicVideoPlayBadge(size: 34, iconSize: 14)
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

                if video.duration != nil {
                    VideoCoverDurationBadge(BiliFormatters.duration(video.duration))
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .mediaShadow(.control)
    }

    private var dynamicCardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            authorHeader
                .padding(.horizontal, 12)

            topLevelText
                .padding(.horizontal, 12)

            if let video = display.video {
                VideoRouteLink(video) {
                    DynamicArchivePreview(video: video, style: .large, showsHeader: false)
                }
            }

            if let live = display.live {
                DynamicLiveRouteLink(room: display.liveRoom) {
                    DynamicLivePreview(live: live, style: .large)
                }
            }

            if !display.imageItems.isEmpty {
                DynamicImageThumbnailStrip(
                    images: display.imageItems,
                    availableWidth: contentWidth
                )
            }

            if let original = item.original {
                DynamicOriginalPreview(
                    item: original,
                    parentID: item.id,
                    contentWidth: horizontalInsetWidth(12)
                )
                .padding(.horizontal, 12)
            } else if item.isForward {
                DynamicForwardUnavailableView()
                    .padding(.horizontal, 12)
            }

            actionBar
        }
        .padding(.top, 5)
        .padding(.bottom, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var separatedDynamicContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            authorHeader
                .padding(.horizontal, 12)

            separatedStoryCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var separatedStoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            topLevelText

            if !display.imageItems.isEmpty {
                imageSquareGrid
            }

            if let original = item.original {
                DynamicOriginalPreview(
                    item: original,
                    parentID: item.id,
                    contentWidth: horizontalInsetWidth(12)
                )
            } else if item.isForward {
                DynamicForwardUnavailableView()
            }

            actionBar
        }
        .padding(.horizontal, 12)
        .padding(.top, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var imageSquareGrid: some View {
        DynamicImageThumbnailStrip(
            images: display.imageItems,
            horizontalBleed: 12,
            availableWidth: horizontalInsetWidth(12)
        )
    }

    private func horizontalInsetWidth(_ inset: CGFloat) -> CGFloat? {
        contentWidth.map { max(floor($0 - inset * 2), 0) }
    }

    private var authorHeader: some View {
        HStack(spacing: 9) {
            if let authorOwner = display.authorOwner, authorOwner.mid > 0 {
                NavigationLink {
                    UploaderView(owner: authorOwner)
                } label: {
                    authorIdentity
                }
                .buttonStyle(.plain)
            } else {
                authorIdentity
            }

            Spacer(minLength: 10)

            if !display.publishTimeText.isEmpty {
                Text(display.publishTimeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    private var authorIdentity: some View {
        HStack(spacing: 9) {
            AvatarRemoteImage(urlString: display.authorAvatarURLString, pixelSize: 96) {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
            .mediaShadow(.subtle)

            Text(display.authorName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var topLevelText: some View {
        if let text = display.topLevelDisplayText, !text.isEmpty {
            dynamicText(displayText: text)
        }
    }

    @ViewBuilder
    private func dynamicText(displayText _: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            DynamicRichTextView(
                input: isTextExpanded ? display.expandedTextInput : display.collapsedTextInput
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .transaction { transaction in
                transaction.animation = nil
            }

            if display.showsExpandButton {
                Button {
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        isTextExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(isTextExpanded ? "收起" : "展开")
                        Image(systemName: isTextExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.pink)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var actionBar: some View {
        DynamicFeedActionBar(
            display: display,
            initialIsLiked: item.isLiked,
            initialLikeCount: display.initialLikeCount
        ) {
            commentsTarget = item
        }
    }

}

private struct DynamicFeedActionBar: View {
    let display: DynamicFeedCardDisplayModel
    let initialIsLiked: Bool
    let initialLikeCount: Int
    let onShowComments: () -> Void
    @State private var isLiked: Bool
    @State private var likeCount: Int
    @State private var actionMessage: String?
    @State private var actionMessageTask: Task<Void, Never>?

    init(
        display: DynamicFeedCardDisplayModel,
        initialIsLiked: Bool,
        initialLikeCount: Int,
        onShowComments: @escaping () -> Void
    ) {
        self.display = display
        self.initialIsLiked = initialIsLiked
        self.initialLikeCount = initialLikeCount
        self.onShowComments = onShowComments
        _isLiked = State(initialValue: initialIsLiked)
        _likeCount = State(initialValue: initialLikeCount)
    }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                shareActionPill
                    .frame(maxWidth: .infinity)

                DynamicActionPill(
                    title: display.commentTitle,
                    systemImage: "bubble.left",
                    isSelected: false
                ) {
                    playActionFeedback()
                    onShowComments()
                }
                .frame(maxWidth: .infinity)

                DynamicActionPill(
                    title: DynamicFeedCardDisplayModel.statTitle(count: likeCount, fallback: "点赞"),
                    systemImage: isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
                    isSelected: isLiked
                ) {
                    toggleLocalLike()
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 3)
        .overlay(alignment: .bottomTrailing) {
            if let actionMessage {
                DynamicActionFeedbackToast(message: actionMessage)
                    .padding(.trailing, 12)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottomTrailing)))
                    .allowsHitTesting(false)
            }
        }
        .onDisappear {
            actionMessageTask?.cancel()
            actionMessageTask = nil
        }
    }

    @ViewBuilder
    private var shareActionPill: some View {
        if let url = display.shareURL {
            ShareLink(
                item: url,
                subject: Text(display.shareTitle),
                message: Text(display.shareMessage)
            ) {
                DynamicActionPillLabel(
                    title: display.repostTitle,
                    systemImage: "arrowshape.turn.up.right"
                )
            }
            .biliGlassButtonStyle()
            .controlSize(.small)
            .tint(.secondary)
            .frame(maxWidth: .infinity)
            .simultaneousGesture(TapGesture().onEnded { playActionFeedback() })
            .accessibilityLabel("分享动态")
        } else {
            DynamicActionPill(
                title: display.repostTitle,
                systemImage: "arrowshape.turn.up.right",
                isSelected: false
            ) {
                showActionMessage("暂无可分享链接")
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func toggleLocalLike() {
        playActionFeedback()
        let nextIsLiked = !isLiked
        withAnimation(.snappy(duration: 0.2)) {
            isLiked = nextIsLiked
            likeCount = max(0, likeCount + (nextIsLiked ? 1 : -1))
        }
        showActionMessage(nextIsLiked ? "已点赞" : "已取消点赞", playsFeedback: false)
    }

    private func playActionFeedback() {
        Haptics.light()
    }

    private func showActionMessage(_ message: String, playsFeedback: Bool = true) {
        if playsFeedback {
            playActionFeedback()
        }
        actionMessageTask?.cancel()
        withAnimation(.snappy(duration: 0.18)) {
            actionMessage = message
        }
        actionMessageTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.18)) {
                actionMessage = nil
            }
        }
    }
}

private struct DynamicFeedCardDisplayModel {
    let video: VideoItem?
    let videoDisplay: VideoCardDisplayModel?
    let live: DynamicLive?
    let liveRoom: LiveRoom?
    let authorOwner: VideoOwner?
    let authorAvatarURLString: String?
    let authorName: String
    let imageItems: [DynamicImageItem]
    let textSegments: [DynamicTextSegment]
    let collapsedTextInput: DynamicAttributedTextInput
    let expandedTextInput: DynamicAttributedTextInput
    let topLevelDisplayText: String?
    let publishTimeText: String
    let usesHomeVideoCardStyle: Bool
    let usesSeparatedDynamicLayout: Bool
    let showsExpandButton: Bool
    let initialLikeCount: Int
    let commentTitle: String
    let repostTitle: String
    let shareURL: URL?
    let shareTitle: String
    let shareMessage: String

    init(item: DynamicFeedItem) {
        let video = item.archive?.asVideoItem(author: item.author)
        let live = item.live
        let imageItems = item.imageItems.filter { $0.normalizedURL != nil }
        let textSegments = item.textSegments
        let topLevelDisplayText = DynamicTextSegment.displayText(from: textSegments)
        let authorName = item.author?.name ?? "Unknown"
        let isPureTextDynamic = video == nil
            && live == nil
            && imageItems.isEmpty
            && item.original == nil
            && !item.isForward
            && !(topLevelDisplayText?.isEmpty ?? true)

        self.video = video
        self.videoDisplay = video.map(VideoCardDisplayModel.init(video:))
        self.live = live
        self.liveRoom = live?.asLiveRoom(author: item.author)
        self.authorOwner = item.author?.owner
        self.authorAvatarURLString = item.author?.face?.normalizedBiliURL()
        self.authorName = authorName
        self.imageItems = imageItems
        self.textSegments = textSegments
        self.collapsedTextInput = Self.textInput(segments: textSegments, emoteSize: 23, maxLines: 6)
        self.expandedTextInput = Self.textInput(segments: textSegments, emoteSize: 23, maxLines: nil)
        self.topLevelDisplayText = topLevelDisplayText
        self.publishTimeText = Self.publishTime(for: item.author)
        self.usesHomeVideoCardStyle = video != nil && item.original == nil && !item.isForward
        self.usesSeparatedDynamicLayout = item.original != nil
            || item.isForward
            || (!imageItems.isEmpty && video == nil)
            || isPureTextDynamic
        self.showsExpandButton = Self.shouldShowExpandButton(for: topLevelDisplayText ?? "")
        self.initialLikeCount = item.likeCount ?? 0
        self.commentTitle = Self.statTitle(count: item.replyCount, fallback: "评论")
        self.repostTitle = Self.statTitle(count: item.repostCount, fallback: "转发")
        self.shareURL = Self.shareURL(item: item, video: video, live: live)
        self.shareTitle = Self.shareTitle(authorName: authorName, text: topLevelDisplayText, video: video, live: live)
        self.shareMessage = "\(authorName)：\(self.shareTitle)"
    }

    static func statTitle(count: Int?, fallback: String) -> String {
        guard let count, count > 0 else { return fallback }
        return BiliFormatters.compactCount(count)
    }

    static func textInput(
        segments: [DynamicTextSegment],
        emoteSize: CGFloat,
        maxLines: Int?
    ) -> DynamicAttributedTextInput {
        DynamicAttributedTextInput(
            segments: segments.isEmpty ? [.text(" ")] : segments,
            baseFont: StableVideoTitleText.Style.feedHeadline.uiFont,
            textColor: .label,
            emoteSize: emoteSize,
            maxLines: maxLines
        )
    }

    private static func publishTime(for author: DynamicAuthor?) -> String {
        if let timestamp = author?.pubTS, timestamp > 0 {
            return BiliFormatters.relativeTime(timestamp)
        }
        return author?.pubTime ?? ""
    }

    private static func shouldShowExpandButton(for text: String) -> Bool {
        if text.count > 120 {
            return true
        }

        var newlineCount = 0
        for character in text where character.isNewline {
            newlineCount += 1
            if newlineCount >= 4 {
                return true
            }
        }
        return false
    }

    private static func shareURL(item: DynamicFeedItem, video: VideoItem?, live: DynamicLive?) -> URL? {
        if let dynamicID = validShareID(item.idStr) {
            return URL(string: "https://t.bilibili.com/\(dynamicID)")
        }
        if let bvid = video?.bvid.trimmingCharacters(in: .whitespacesAndNewlines), !bvid.isEmpty {
            return URL(string: "https://www.bilibili.com/video/\(bvid)")
        }
        if let liveURL = live?.normalizedLinkURL {
            return liveURL
        }
        if let roomID = live?.roomID, roomID > 0 {
            return URL(string: "https://live.bilibili.com/\(roomID)")
        }
        return nil
    }

    private static func shareTitle(authorName: String, text: String?, video: VideoItem?, live: DynamicLive?) -> String {
        let candidates = [
            text,
            video?.title,
            live?.displayTitle
        ]
        return candidates.compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }.first ?? "\(authorName) 的动态"
    }

    private static func validShareID(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6, trimmed.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil else {
            return nil
        }
        return trimmed
    }
}

private struct DynamicActionButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(isSelected ? .pink : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct DynamicActionPill: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, minHeight: 28)
                .padding(.horizontal, 3)
        }
        .biliGlassButtonStyle(prominent: isSelected)
        .controlSize(.small)
        .tint(isSelected ? .pink : .secondary)
    }
}

private struct DynamicActionPillLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .allowsTightening(true)
            .frame(maxWidth: .infinity, minHeight: 28)
            .padding(.horizontal, 3)
    }
}

private struct DynamicActionFeedbackToast: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .glassEffect(.regular.tint(.white.opacity(0.18)).interactive(false), in: Capsule())
            .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
            .accessibilityLabel(message)
    }
}

private struct DynamicRichTextView: View {
    let segments: [DynamicTextSegment]
    let font: UIFont
    let textColor: Color
    let emoteSize: CGFloat
    let maxLines: Int?
    private let textInput: DynamicAttributedTextInput
    @Environment(\.openAppURLAction) private var openAppURL

    init(
        segments: [DynamicTextSegment],
        font: UIFont,
        textColor: Color,
        emoteSize: CGFloat,
        maxLines: Int?
    ) {
        self.segments = segments
        self.font = font
        self.textColor = textColor
        self.emoteSize = emoteSize
        self.maxLines = maxLines

        self.textInput = DynamicAttributedTextInput(
            segments: segments.isEmpty ? [.text(" ")] : segments,
            baseFont: font,
            textColor: UIColor(textColor),
            emoteSize: emoteSize,
            maxLines: maxLines
        )
    }

    init(input: DynamicAttributedTextInput) {
        self.segments = input.segments
        self.font = input.baseFont
        self.textColor = Color(input.textColor)
        self.emoteSize = input.emoteSize
        self.maxLines = input.maxLines
        self.textInput = input
    }

    var body: some View {
        DynamicAttributedTextLabel(
            input: textInput,
            onURLTap: { url in
                openAppURL?(url)
            }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DynamicAttributedTextInput: Equatable {
    let segments: [DynamicTextSegment]
    let baseFont: UIFont
    let textColor: UIColor
    let emoteSize: CGFloat
    let maxLines: Int?

    static func == (lhs: DynamicAttributedTextInput, rhs: DynamicAttributedTextInput) -> Bool {
        lhs.segments == rhs.segments
            && lhs.baseFont.fontName == rhs.baseFont.fontName
            && lhs.baseFont.pointSize == rhs.baseFont.pointSize
            && lhs.textColor == rhs.textColor
            && lhs.emoteSize == rhs.emoteSize
            && lhs.maxLines == rhs.maxLines
    }

    var cacheKey: String {
        let segmentKey = segments
            .map { segment -> String in
                switch segment {
                case .text(let text):
                    return "t:\(text)"
                case .emoji(let text, let url):
                    return "e:\(text):\(url ?? "")"
                case .link(let text, let url):
                    return "l:\(text):\(url)"
                case .mention(let text, let mid, let url):
                    return "m:\(text):\(mid.map(String.init) ?? ""):\(url ?? "")"
                }
            }
            .joined(separator: "\u{1f}")
        return [
            segmentKey,
            baseFont.fontName,
            "\(baseFont.pointSize)",
            "\(textColor.dynamicRGBAKey)",
            "\(emoteSize)",
            "\(maxLines ?? -1)"
        ].joined(separator: "\u{1e}")
    }

    func render() -> (attributedString: NSAttributedString, missingImageURLs: [URL]) {
        let result = NSMutableAttributedString()
        var missingImageURLs = [URL]()

        for segment in segments {
            switch segment {
            case .text(let text):
                result.append(attributedText(text))
            case .emoji(let text, let url):
                result.append(emoteAttachment(for: text, urlString: url, missingImageURLs: &missingImageURLs))
            case .link(let title, let rawURL):
                if let normalized = AppLinkRouter.normalizedHTTPURLString(rawURL),
                   let url = URL(string: normalized) {
                    result.append(BiliMentionTextRenderer.linkAttributedString(title: title, url: url, font: baseFont))
                } else {
                    result.append(attributedText(title))
                }
            case .mention(let text, let mid, let url):
                let mention = BiliMention(text: text, mid: mid, url: url)
                result.append(
                    BiliMentionTextRenderer.attributedString(
                        for: text,
                        baseColor: textColor,
                        font: baseFont,
                        mentions: [mention].compactMap { $0 }
                    )
                )
            }
        }

        if result.length == 0 {
            result.append(attributedText(" "))
        }

        result.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: result.length))
        return (result, Array(Set(missingImageURLs)))
    }

    private var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.lineBreakMode = .byWordWrapping
        return style
    }

    private func attributedText(_ text: String) -> NSAttributedString {
        BiliMentionTextRenderer.attributedString(
            for: text,
            baseColor: textColor,
            font: baseFont,
            mentions: []
        )
    }

    private func emoteAttachment(for token: String, urlString: String?, missingImageURLs: inout [URL]) -> NSAttributedString {
        guard let urlString, let url = URL(string: urlString) else {
            return attributedText(token)
        }

        let attachment = NSTextAttachment()
        if let image = BiliEmoteImageStore.shared.cachedImage(for: url) {
            attachment.image = image
        } else {
            attachment.image = BiliEmoteImageStore.shared.placeholderImage(size: emoteSize)
            missingImageURLs.append(url)
        }
        attachment.bounds = CGRect(
            x: 0,
            y: (baseFont.capHeight - emoteSize) / 2,
            width: emoteSize,
            height: emoteSize
        )
        return NSAttributedString(attachment: attachment)
    }
}

private struct DynamicAttributedTextLabel: UIViewRepresentable {
    let input: DynamicAttributedTextInput
    let onURLTap: (URL) -> Void
    private static let sharedRenderCache = DynamicAttributedTextRenderCache()

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> BiliInteractiveAttributedLabel {
        let label = BiliInteractiveAttributedLabel()
        label.backgroundColor = .clear
        label.adjustsFontForContentSizeCategory = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }

    func updateUIView(_ label: BiliInteractiveAttributedLabel, context: Context) {
        label.onLinkTap = onURLTap
        label.numberOfLines = input.maxLines ?? 0
        label.lineBreakMode = .byWordWrapping
        let renderResult = context.coordinator.render(input)
        if context.coordinator.appliedRenderKey != renderResult.key {
            label.attributedText = renderResult.attributedString
            label.invalidateIntrinsicContentSize()
            context.coordinator.appliedRenderKey = renderResult.key
        }
        context.coordinator.currentInput = input
        context.coordinator.loadMissingImages(renderResult.missingImageURLs, into: label)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: BiliInteractiveAttributedLabel, context: Context) -> CGSize? {
        guard let width = proposal.width ?? (uiView.bounds.width > 1 ? uiView.bounds.width : nil),
              width > 1
        else { return nil }
        uiView.preferredMaxLayoutWidth = width
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }

    final class Coordinator {
        var currentInput: DynamicAttributedTextInput?
        var appliedRenderKey: String?
        private var cachedInputKey: String?
        private var cachedRenderResult: DynamicAttributedTextRenderResult?
        private var imageTasks: [URL: Task<Void, Never>] = [:]

        func render(_ input: DynamicAttributedTextInput) -> DynamicAttributedTextRenderResult {
            if cachedInputKey == input.cacheKey, let cachedRenderResult {
                return cachedRenderResult
            }

            if let result = DynamicAttributedTextLabel.sharedRenderCache.result(for: input.cacheKey) {
                cachedInputKey = input.cacheKey
                cachedRenderResult = result
                return result
            }

            let result = input.render()
            let renderResult = DynamicAttributedTextRenderResult(
                key: input.cacheKey + "|" + result.missingImageURLs.map(\.absoluteString).sorted().joined(separator: ","),
                attributedString: result.attributedString,
                missingImageURLs: result.missingImageURLs
            )
            if result.missingImageURLs.isEmpty {
                DynamicAttributedTextLabel.sharedRenderCache.set(renderResult, for: input.cacheKey)
            }
            cachedInputKey = input.cacheKey
            cachedRenderResult = renderResult
            return renderResult
        }

        func loadMissingImages(_ urls: [URL], into label: BiliInteractiveAttributedLabel) {
            guard !urls.isEmpty else { return }

            for url in urls where imageTasks[url] == nil {
                imageTasks[url] = Task { [weak self, weak label] in
                    _ = await BiliEmoteImageStore.shared.image(for: url)

                    await MainActor.run {
                        guard let self else { return }
                        self.imageTasks[url] = nil
                        guard let label, let currentInput = self.currentInput else { return }
                        self.cachedInputKey = nil
                        let renderResult = self.render(currentInput)
                        if renderResult.missingImageURLs.isEmpty {
                            DynamicAttributedTextLabel.sharedRenderCache.set(renderResult, for: currentInput.cacheKey)
                        }
                        self.appliedRenderKey = renderResult.key
                        label.attributedText = renderResult.attributedString
                        label.invalidateIntrinsicContentSize()
                    }
                }
            }
        }

        deinit {
            imageTasks.values.forEach { $0.cancel() }
        }
    }
}

private final class DynamicAttributedTextRenderCache {
    private let cache = NSCache<NSString, DynamicAttributedTextRenderCacheEntry>()

    init() {
        cache.countLimit = 900
    }

    func result(for key: String) -> DynamicAttributedTextRenderResult? {
        cache.object(forKey: key as NSString)?.result
    }

    func set(_ result: DynamicAttributedTextRenderResult, for key: String) {
        cache.setObject(DynamicAttributedTextRenderCacheEntry(result: result), forKey: key as NSString)
    }
}

private final class DynamicAttributedTextRenderCacheEntry {
    let result: DynamicAttributedTextRenderResult

    init(result: DynamicAttributedTextRenderResult) {
        self.result = result
    }
}

private struct DynamicAttributedTextRenderResult {
    let key: String
    let attributedString: NSAttributedString
    let missingImageURLs: [URL]
}

private extension UIColor {
    var dynamicRGBAKey: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return "\(red),\(green),\(blue),\(alpha)"
    }
}

private struct DynamicCommentsSheet: View {
    let item: DynamicFeedItem
    @EnvironmentObject private var dependencies: AppDependencies
    @StateObject private var viewModel: DynamicCommentsViewModel
    @StateObject private var runtimeSettings = DynamicCommentsRuntimeSettingsStore()
    @State private var replySheetComment: Comment?

    init(item: DynamicFeedItem, api: BiliAPIClient) {
        self.item = item
        _viewModel = StateObject(wrappedValue: DynamicCommentsViewModel(item: item, api: api))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    commentsHeader
                        .padding(.horizontal, 14)
                        .padding(.top, 4)
                        .padding(.bottom, 6)

                    commentsContent
                }
            }
            .navigationTitle("评论")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                runtimeSettings.bind(dependencies.libraryStore)
                viewModel.setBlocksGoodsComments(runtimeSettings.blocksGoodsComments)
                await viewModel.loadInitial()
            }
        }
        .onChange(of: runtimeSettings.blocksGoodsComments) { _, isEnabled in
            viewModel.setBlocksGoodsComments(isEnabled)
        }
        .presentationDetents([.fraction(0.7)])
        .presentationDragIndicator(.visible)
        .sheet(item: $replySheetComment) { comment in
            DynamicCommentRepliesSheet(rootComment: comment, replyStore: viewModel.replyStore)
        }
    }

    private var commentsHeader: some View {
        HStack(spacing: 8) {
            Text("全部评论")
                .font(.headline.weight(.semibold))

            if let count = item.replyCount, count > 0 {
                Text(BiliFormatters.compactCount(count))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker(
                "评论排序",
                selection: Binding(
                    get: { viewModel.selectedSort },
                    set: { sort in
                        Task { await viewModel.selectSort(sort) }
                    }
                )
            ) {
                ForEach(CommentSort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 124)
            .controlSize(.small)
            .accessibilityLabel("评论排序")
        }
    }

    @ViewBuilder
    private var commentsContent: some View {
        if !viewModel.canLoadComments {
            EmptyStateView(title: "暂不支持评论", systemImage: "bubble.left", message: "这条动态没有返回评论入口。")
                .padding(16)
        } else if viewModel.comments.isEmpty && viewModel.state.isLoading {
            CommentLoadingSkeletonList(count: 4)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
        } else if viewModel.comments.isEmpty, case .failed(let message) = viewModel.state {
            DynamicCommentErrorView(message: message) {
                Task { await viewModel.reload() }
            }
            .padding(14)
        } else if viewModel.comments.isEmpty {
            EmptyStateView(title: "暂无评论", systemImage: "bubble.left", message: "这里还没有可展示的评论。")
                .padding(14)
        } else {
            let commentItems = viewModel.commentItems
            let lastCommentID = commentItems.last?.id
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(commentItems) { item in
                    DynamicCommentRow(item: item) {
                        replySheetComment = item.comment
                    }
                    .padding(.horizontal, 14)
                    .dynamicLoadMoreTask(if: item.id == lastCommentID, id: item.id) {
                        await viewModel.loadMoreIfNeeded(current: item.comment)
                    }

                    Divider()
                        .padding(.leading, 62)
                }

                commentsFooter
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
    }

    @ViewBuilder
    private var commentsFooter: some View {
        if viewModel.state.isLoading {
            CommentLoadingSkeletonRow()
                .padding(.vertical, 10)
        } else if case .failed(let message) = viewModel.state {
            DynamicCommentErrorView(message: message) {
                Task { await viewModel.loadMore() }
            }
        } else if viewModel.hasMoreComments {
            Button {
                Task { await viewModel.loadMore() }
            } label: {
                Label("加载更多评论", systemImage: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .dynamicCommentGlassButtonStyle()
            .controlSize(.small)
            .tint(.pink)
        } else {
            Text("没有更多评论了")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
    }
}

private extension View {
    @ViewBuilder
    func dynamicLoadMoreTask<ID: Equatable>(
        if condition: Bool,
        id: ID,
        action: @escaping () async -> Void
    ) -> some View {
        if condition {
            task(id: id) {
                await action()
            }
        } else {
            self
        }
    }

    func dynamicCommentGlassButtonStyle(prominent: Bool = false) -> some View {
        biliGlassButtonStyle(prominent: prominent)
    }

    @ViewBuilder
    func dynamicCommentGlassCard() -> some View {
        clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .biliGlassEffect(
                tint: Color(.secondarySystemBackground).opacity(0.18),
                interactive: false,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
    }
}

@MainActor
private final class DynamicCommentsViewModel: ObservableObject {
    private(set) var comments: [Comment] = [] {
        didSet {
            syncCommentItems()
        }
    }
    @Published private(set) var commentItems: [DynamicCommentRowItem] = []
    @Published var state: LoadingState = .idle
    @Published var selectedSort: CommentSort = .hot
    let replyStore: DynamicCommentReplyStore

    private let item: DynamicFeedItem
    private let api: BiliAPIClient
    private var blocksGoodsComments = true
    private var cursor = ""
    private var commentsEnd = false
    private var commentItemsSignature = DynamicCommentListSignature([])

    var canLoadComments: Bool {
        commentOID != nil && commentType != nil
    }

    var hasMoreComments: Bool {
        !commentsEnd
    }

    init(item: DynamicFeedItem, api: BiliAPIClient) {
        self.item = item
        self.api = api
        self.replyStore = DynamicCommentReplyStore(item: item, api: api, blocksGoodsComments: blocksGoodsComments)
    }

    func setBlocksGoodsComments(_ isEnabled: Bool) {
        guard blocksGoodsComments != isEnabled else { return }
        blocksGoodsComments = isEnabled
        replyStore.setBlocksGoodsComments(isEnabled)
        refilterLoadedComments()
    }

    func loadInitial() async {
        guard comments.isEmpty, state != .loading else { return }
        await reload()
    }

    func reload() async {
        cursor = ""
        commentsEnd = false
        comments = []
        await loadPage()
    }

    func selectSort(_ sort: CommentSort) async {
        guard selectedSort != sort else { return }
        selectedSort = sort
        await reload()
    }

    func loadMoreIfNeeded(current comment: Comment?) async {
        guard let comment, comments.last?.id == comment.id else { return }
        await loadMore()
    }

    func loadMore() async {
        guard !state.isLoading, !commentsEnd else { return }
        await loadPage()
    }

    private var commentOID: String? {
        item.commentOID
    }

    private var commentType: Int? {
        item.commentType
    }

    private func loadPage() async {
        guard let oid = commentOID, let type = commentType else {
            state = .failed("这条动态没有返回评论入口")
            commentsEnd = true
            return
        }

        state = .loading
        do {
            let page = try await api.fetchComments(oid: oid, type: type, cursor: cursor, sort: selectedSort)
            let pageComments = comments.isEmpty
                ? (page.topReplies ?? []) + (page.replies ?? [])
                : (page.replies ?? [])
            appendUniqueComments(filteredComments(pageComments))
            cursor = page.cursor?.next ?? ""
            commentsEnd = page.cursor?.isEnd ?? true
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func appendUniqueComments(_ more: [Comment]) {
        let existing = Set(comments.map(\.id))
        comments.append(contentsOf: more.filter { !existing.contains($0.id) })
    }

    private func syncCommentItems() {
        let nextSignature = DynamicCommentListSignature(comments)
        guard nextSignature != commentItemsSignature else { return }
        commentItemsSignature = nextSignature
        commentItems = comments.map(DynamicCommentRowItem.init)
    }

    private func filteredComments(_ values: [Comment]) -> [Comment] {
        guard blocksGoodsComments else { return values }
        return values.filter { !$0.containsGoodsPromotion }
    }

    func refilterLoadedComments() {
        guard !comments.isEmpty else { return }
        if blocksGoodsComments {
            comments = filteredComments(comments)
        } else {
            Task { await reload() }
        }
    }
}

private struct DynamicCommentRow: View {
    let item: DynamicCommentRowItem
    let showReplies: () -> Void

    private var comment: Comment {
        item.comment
    }

    private var display: DynamicCommentRowDisplayModel {
        item.display
    }

    init(item: DynamicCommentRowItem, showReplies: @escaping () -> Void) {
        self.item = item
        self.showReplies = showReplies
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            DynamicCommentAvatar(urlString: display.avatarURLString, size: 38)

            VStack(alignment: .leading, spacing: 6) {
                header

                BiliEmoteText(content: comment.content, font: .subheadline, textColor: .primary, emoteSize: 21)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)

                DynamicCommentImageGrid(images: display.pictures)

                if !display.replyPreviews.isEmpty {
                    Button(action: showReplies) {
                        DynamicCommentReplyPreviewContainer {
                            ForEach(display.replyPreviews) { reply in
                                DynamicReplyPreviewRow(reply: reply)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                if display.visibleReplyCount > 0 {
                    DynamicCommentInlineActionPill(
                        title: "\(display.visibleReplyCount) 条回复",
                        systemImage: "bubble.left.and.bubble.right",
                        action: showReplies
                    )
                    .padding(.top, 1)
                }
            }
        }
        .padding(.vertical, 10)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(display.authorName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if !display.timeText.isEmpty {
                Text(display.timeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            DynamicCommentMetricBadge(
                text: display.likeText,
                systemImage: display.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
                isHighlighted: display.isLiked
            )
        }
    }
}

private struct DynamicCommentRowItem: Identifiable, Equatable {
    let id: Int
    let comment: Comment
    let display: DynamicCommentRowDisplayModel

    init(comment: Comment) {
        id = comment.id
        self.comment = comment
        display = DynamicCommentRowDisplayModel(comment: comment)
    }
}

private struct DynamicCommentRowDisplayModel: Equatable {
    let authorName: String
    let avatarURLString: String?
    let timeText: String
    let likeText: String
    let isLiked: Bool
    let replyPreviews: [Comment]
    let visibleReplyCount: Int
    let pictures: [DynamicImageItem]

    init(comment: Comment) {
        authorName = comment.member?.uname?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Unknown"
        avatarURLString = comment.member?.avatar
        timeText = BiliFormatters.relativeTime(comment.ctime)
        likeText = BiliFormatters.compactCount(comment.like)
        isLiked = comment.likeState == 1
        replyPreviews = Array((comment.replies ?? []).prefix(2))
        visibleReplyCount = comment.replyCount ?? comment.replies?.count ?? 0
        pictures = comment.content?.pictures ?? []
    }
}

nonisolated private struct DynamicCommentListSignature: Equatable {
    let items: [DynamicCommentSignature]

    init(_ comments: [Comment]) {
        items = comments.map(DynamicCommentSignature.init)
    }
}

nonisolated private struct DynamicCommentSignature: Equatable {
    let id: Int
    let parentID: Int?
    let dialogID: Int?
    let authorName: String?
    let avatar: String?
    let message: String?
    let like: Int?
    let ctime: Int?
    let replyCount: Int?
    let likeState: Int?
    let pictureURLs: [String]
    let replyPreviews: [DynamicCommentReplyPreviewSignature]

    init(_ comment: Comment) {
        id = comment.id
        parentID = comment.parentID
        dialogID = comment.dialogID
        authorName = comment.member?.uname
        avatar = comment.member?.avatar
        message = comment.content?.message
        like = comment.like
        ctime = comment.ctime
        replyCount = comment.replyCount
        likeState = comment.likeState
        pictureURLs = (comment.content?.pictures ?? []).map(\.url)
        replyPreviews = (comment.replies ?? [])
            .prefix(2)
            .map(DynamicCommentReplyPreviewSignature.init)
    }
}

nonisolated private struct DynamicCommentReplyPreviewSignature: Equatable {
    let id: Int
    let authorName: String?
    let message: String?

    init(_ comment: Comment) {
        id = comment.id
        authorName = comment.member?.uname
        message = comment.content?.message
    }
}

private struct DynamicReplyPreviewRow: View {
    let reply: Comment

    var body: some View {
        BiliEmoteText(
            content: reply.content,
            font: .caption,
            textColor: .primary,
            emoteSize: 18,
            leadingName: reply.member?.uname ?? "Unknown",
            leadingNameColor: .secondary
        )
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct DynamicCommentReplyPreviewContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.pink.opacity(0.42))
                .frame(width: 3)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 5) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color(.secondarySystemGroupedBackground))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color(.separator).opacity(0.08), lineWidth: 0.6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct DynamicCommentMetricBadge: View {
    let text: String
    let systemImage: String
    let isHighlighted: Bool

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .foregroundStyle(isHighlighted ? .pink : .secondary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(isHighlighted ? Color.pink.opacity(0.14) : Color.secondary.opacity(0.10), lineWidth: 0.7)
            }
    }
}

private struct DynamicCommentInlineActionPill: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(Color.pink.opacity(0.08), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.pink.opacity(0.12), lineWidth: 0.7)
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.pink)
    }
}

private struct DynamicCommentRepliesSheet: View {
    let rootComment: Comment
    let replyStore: DynamicCommentReplyStore
    @State private var dialogReply: Comment?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DynamicCommentReplyRootView(comment: rootComment)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                    Divider()

                    DynamicCommentRepliesContent(rootComment: rootComment, replyStore: replyStore) { reply in
                        dialogReply = reply
                    }
                }
            }
            .navigationTitle("评论回复")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await replyStore.loadReplies(for: rootComment)
            }
        }
        .presentationDetents([.fraction(0.7)])
        .presentationDragIndicator(.visible)
        .sheet(item: $dialogReply) { reply in
            DynamicCommentDialogSheet(rootComment: rootComment, focusReply: reply, replyStore: replyStore)
        }
    }
}

private struct DynamicCommentRepliesContent: View {
    let rootComment: Comment
    @ObservedObject var replyStore: DynamicCommentReplyStore
    let showDialog: (Comment) -> Void

    @ViewBuilder
    var body: some View {
        let snapshot = replyStore.repliesSnapshot(for: rootComment)

        if snapshot.replies.isEmpty && snapshot.state.isLoading {
            CommentLoadingSkeletonList(count: 3)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        } else if snapshot.replies.isEmpty, case .failed(let message) = snapshot.state {
            DynamicCommentErrorView(message: message) {
                Task { await replyStore.reloadReplies(for: rootComment) }
            }
            .padding(16)
        } else if snapshot.replies.isEmpty {
            EmptyStateView(title: "暂无回复", systemImage: "bubble.left.and.bubble.right", message: "这条评论还没有可展示的回复。")
                .padding(16)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(snapshot.replyItems) { replyItem in
                    DynamicCommentReplyDetailRow(
                        item: replyItem,
                        showDialog: replyItem.canShowDialog ? {
                            showDialog(replyItem.reply)
                        } : nil
                    )
                    .padding(.horizontal, 16)

                    Divider()
                        .padding(.leading, 66)
                }

                repliesFooter(snapshot: snapshot)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
    }

    @ViewBuilder
    private func repliesFooter(snapshot: DynamicCommentRepliesSnapshot) -> some View {
        if snapshot.hasLoadedReplies, snapshot.state.isLoading {
            CommentLoadingSkeletonRow()
        } else if case .failed(let message) = snapshot.state {
            DynamicCommentErrorView(message: message) {
                Task { await replyStore.loadMoreReplies(for: rootComment) }
            }
        } else if snapshot.hasMoreReplies {
            Button {
                Task { await replyStore.loadMoreReplies(for: rootComment) }
            } label: {
                Label("查看更多回复", systemImage: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .dynamicCommentGlassButtonStyle()
            .controlSize(.small)
            .tint(.pink)
        }
    }
}

@MainActor
private final class DynamicCommentReplyStore: ObservableObject {
    @Published private var snapshot = DynamicCommentReplyStoreSnapshot()
    private var replyItemCache: [Int: DynamicCommentReplyItemCacheEntry] = [:]
    private var dialogItemCache: [String: DynamicCommentDialogItemCacheEntry] = [:]

    private let item: DynamicFeedItem
    private let api: BiliAPIClient
    private var blocksGoodsComments: Bool

    init(item: DynamicFeedItem, api: BiliAPIClient, blocksGoodsComments: Bool) {
        self.item = item
        self.api = api
        self.blocksGoodsComments = blocksGoodsComments
    }

    private func updateSnapshot(_ transform: (inout DynamicCommentReplyStoreSnapshot) -> Void) {
        var next = snapshot
        transform(&next)
        setSnapshot(next)
    }

    private func setSnapshot(_ next: DynamicCommentReplyStoreSnapshot) {
        guard next.changeSignature != snapshot.changeSignature else { return }
        snapshot = next
    }

    func setBlocksGoodsComments(_ isEnabled: Bool) {
        guard blocksGoodsComments != isEnabled else { return }
        blocksGoodsComments = isEnabled
        updateSnapshot { snapshot in
            if isEnabled {
                snapshot.replyThreads = snapshot.replyThreads.mapValues(filteredComments)
                snapshot.dialogThreads = snapshot.dialogThreads.mapValues(filteredComments)
            } else {
                snapshot.replyThreads = [:]
                snapshot.dialogThreads = [:]
                snapshot.replyPages = [:]
                snapshot.replyHasMore = [:]
            }
        }
        replyItemCache.removeAll()
        dialogItemCache.removeAll()
    }

    func replies(for comment: Comment) -> [Comment] {
        snapshot.replyThreads[comment.id] ?? comment.replies ?? []
    }

    func repliesSnapshot(for comment: Comment) -> DynamicCommentRepliesSnapshot {
        let replies = replies(for: comment)
        return DynamicCommentRepliesSnapshot(
            state: snapshot.replyStates[comment.id] ?? .idle,
            replies: replies,
            replyItems: replyItems(for: comment, replies: replies),
            hasMoreReplies: hasMoreReplies(for: comment, loadedCount: replies.count)
        )
    }

    func replyItems(for comment: Comment) -> [DynamicCommentReplyItem] {
        replyItems(for: comment, replies: replies(for: comment))
    }

    private func replyItems(for comment: Comment, replies: [Comment]) -> [DynamicCommentReplyItem] {
        let signature = DynamicCommentReplyItemSignature(rootComment: comment, replies: replies)
        if let cached = replyItemCache[comment.id], cached.signature == signature {
            return cached.items
        }

        let items = replies.map { DynamicCommentReplyItem(reply: $0, rootComment: comment) }
        replyItemCache[comment.id] = DynamicCommentReplyItemCacheEntry(signature: signature, items: items)
        return items
    }

    func hasMoreReplies(for comment: Comment) -> Bool {
        if let hasMore = snapshot.replyHasMore[comment.id] {
            return hasMore
        }
        let loadedCount = replies(for: comment).count
        return hasMoreReplies(for: comment, loadedCount: loadedCount)
    }

    private func hasMoreReplies(for comment: Comment, loadedCount: Int) -> Bool {
        if let hasMore = snapshot.replyHasMore[comment.id] {
            return hasMore
        }
        let totalCount = comment.replyCount ?? comment.replies?.count ?? loadedCount
        return loadedCount < totalCount
    }

    func replyState(for comment: Comment) -> LoadingState {
        snapshot.replyStates[comment.id] ?? .idle
    }

    func loadReplies(for comment: Comment) async {
        guard snapshot.replyThreads[comment.id] == nil else { return }
        updateSnapshot {
            $0.replyPages[comment.id] = 0
            $0.replyHasMore[comment.id] = true
        }
        await loadReplyPage(for: comment, reset: true)
    }

    func reloadReplies(for comment: Comment) async {
        updateSnapshot {
            $0.replyThreads[comment.id] = nil
            $0.replyPages[comment.id] = 0
            $0.replyHasMore[comment.id] = true
        }
        replyItemCache[comment.id] = nil
        await loadReplyPage(for: comment, reset: true)
    }

    func loadMoreReplies(for comment: Comment) async {
        guard snapshot.replyHasMore[comment.id] != false,
              !(snapshot.replyStates[comment.id]?.isLoading ?? false)
        else { return }
        await loadReplyPage(for: comment, reset: false)
    }

    func dialogItems(for root: Comment, reply: Comment) -> [DynamicCommentDialogItem] {
        let key = dialogKey(root: root, reply: reply)
        let replies = dialogReplies(for: root, reply: reply)
        return dialogItems(for: root, key: key, replies: replies)
    }

    private func dialogItems(for root: Comment, key: String, replies: [Comment]) -> [DynamicCommentDialogItem] {
        let signature = DynamicCommentReplyItemSignature(rootComment: root, replies: replies)
        if let cached = dialogItemCache[key], cached.signature == signature {
            return cached.items
        }

        let items = replies.map(DynamicCommentDialogItem.init)
        dialogItemCache[key] = DynamicCommentDialogItemCacheEntry(signature: signature, items: items)
        return items
    }

    func dialogState(for root: Comment, reply: Comment) -> LoadingState {
        snapshot.dialogStates[dialogKey(root: root, reply: reply)] ?? .idle
    }

    func dialogSnapshot(for root: Comment, reply: Comment) -> DynamicCommentDialogSnapshot {
        let key = dialogKey(root: root, reply: reply)
        let replies = dialogReplies(for: root, reply: reply)
        return DynamicCommentDialogSnapshot(
            state: snapshot.dialogStates[key] ?? .idle,
            items: dialogItems(for: root, key: key, replies: replies)
        )
    }

    func loadDialog(for root: Comment, reply: Comment) async {
        let key = dialogKey(root: root, reply: reply)
        guard snapshot.dialogThreads[key] == nil else { return }
        await loadDialogPage(for: root, reply: reply)
    }

    func reloadDialog(for root: Comment, reply: Comment) async {
        let key = dialogKey(root: root, reply: reply)
        updateSnapshot { $0.dialogThreads[key] = nil }
        dialogItemCache[key] = nil
        await loadDialogPage(for: root, reply: reply)
    }

    private var commentOID: String? {
        item.commentOID
    }

    private var commentType: Int? {
        item.commentType
    }

    private func loadReplyPage(for comment: Comment, reset: Bool) async {
        guard let oid = commentOID, let type = commentType else {
            updateSnapshot { $0.replyStates[comment.id] = .failed("这条动态没有返回评论入口") }
            return
        }

        updateSnapshot { $0.replyStates[comment.id] = .loading }
        do {
            let nextPage = reset ? 1 : (snapshot.replyPages[comment.id] ?? 1) + 1
            let page = try await api.fetchCommentReplies(oid: oid, type: type, root: comment.rpid, page: nextPage)
            let fetchedReplies = filteredComments(page.replies ?? [])
            let existingReplies = reset
                ? filteredComments(comment.replies ?? [])
                : filteredComments(snapshot.replyThreads[comment.id] ?? comment.replies ?? [])
            let replies = uniqueComments(existingReplies + fetchedReplies)
            let totalCount = comment.replyCount ?? Int.max
            updateSnapshot {
                $0.replyThreads[comment.id] = replies
                $0.replyPages[comment.id] = nextPage
                $0.replyHasMore[comment.id] = !fetchedReplies.isEmpty && replies.count < totalCount
                $0.replyStates[comment.id] = .loaded
            }
        } catch {
            updateSnapshot {
                if reset {
                    $0.replyThreads[comment.id] = filteredComments(comment.replies ?? [])
                }
                $0.replyStates[comment.id] = .failed(error.localizedDescription)
            }
        }
    }

    private func loadDialogPage(for root: Comment, reply: Comment) async {
        let key = dialogKey(root: root, reply: reply)
        guard let oid = commentOID, let type = commentType else {
            updateSnapshot { $0.dialogStates[key] = .failed("这条动态没有返回评论入口") }
            return
        }

        let fallbackReplies = filteredComments(localDialogReplies(root: root, reply: reply))

        guard let dialogID = reply.dialogID, dialogID > 0 else {
            updateSnapshot {
                $0.dialogThreads[key] = fallbackReplies
                $0.dialogStates[key] = .loaded
            }
            return
        }

        updateSnapshot { $0.dialogStates[key] = .loading }
        do {
            let page = try await api.fetchCommentDialog(oid: oid, type: type, root: root.rpid, dialog: dialogID)
            let replies = uniqueComments(filteredComments(page.replies ?? []) + fallbackReplies)
            updateSnapshot {
                $0.dialogThreads[key] = replies.isEmpty ? fallbackReplies : replies
                $0.dialogStates[key] = .loaded
            }
        } catch {
            updateSnapshot {
                $0.dialogThreads[key] = fallbackReplies
                $0.dialogStates[key] = .failed(error.localizedDescription)
            }
        }
    }

    private func dialogReplies(for root: Comment, reply: Comment) -> [Comment] {
        let key = dialogKey(root: root, reply: reply)
        return snapshot.dialogThreads[key] ?? localDialogReplies(root: root, reply: reply)
    }

    private func dialogKey(root: Comment, reply: Comment) -> String {
        let dialogID = reply.dialogID ?? 0
        if dialogID > 0 {
            return "\(root.id)-\(dialogID)"
        }
        let parentID = reply.parentID ?? 0
        if parentID > 0 {
            return "\(root.id)-p-\(parentID)-\(reply.id)"
        }
        return "\(root.id)-r-\(reply.id)"
    }

    private func localDialogReplies(root: Comment, reply: Comment) -> [Comment] {
        let siblings = replies(for: root)
        let dialogID = reply.dialogID ?? 0
        if dialogID > 0 {
            let matches = siblings.filter {
                $0.dialogID == dialogID || $0.id == dialogID || $0.parentID == dialogID
            }
            let merged = uniqueComments([reply] + matches)
            if merged.count > 1 {
                return merged
            }
        }

        let parentID = reply.parentID ?? 0
        if parentID > 0 {
            let matches = siblings.filter {
                $0.parentID == parentID || $0.id == parentID || $0.id == reply.id
            }
            let merged = uniqueComments([reply] + matches)
            if merged.count > 1 {
                return merged
            }
        }

        return [reply]
    }

    private func filteredComments(_ values: [Comment]) -> [Comment] {
        guard blocksGoodsComments else { return values }
        return values.filter { !$0.containsGoodsPromotion }
    }

    private func uniqueComments(_ comments: [Comment]) -> [Comment] {
        var seen = Set<Int>()
        return comments.filter { seen.insert($0.id).inserted }
    }
}

private struct DynamicCommentRepliesSnapshot: Equatable {
    let state: LoadingState
    let replies: [Comment]
    let replyItems: [DynamicCommentReplyItem]
    let hasMoreReplies: Bool

    var hasLoadedReplies: Bool {
        !replies.isEmpty
    }
}

private struct DynamicCommentDialogSnapshot: Equatable {
    let state: LoadingState
    let items: [DynamicCommentDialogItem]
}

private struct DynamicCommentReplyStoreSnapshot {
    var replyThreads: [Int: [Comment]] = [:]
    var replyStates: [Int: LoadingState] = [:]
    var replyPages: [Int: Int] = [:]
    var replyHasMore: [Int: Bool] = [:]
    var dialogThreads: [String: [Comment]] = [:]
    var dialogStates: [String: LoadingState] = [:]

    var changeSignature: DynamicCommentReplyStoreChangeSignature {
        DynamicCommentReplyStoreChangeSignature(
            replyThreadSignatures: replyThreads.mapValues(DynamicCommentListSignature.init),
            replyStates: replyStates,
            replyPages: replyPages,
            replyHasMore: replyHasMore,
            dialogThreadSignatures: dialogThreads.mapValues(DynamicCommentListSignature.init),
            dialogStates: dialogStates
        )
    }
}

nonisolated private struct DynamicCommentReplyStoreChangeSignature: Equatable {
    let replyThreadSignatures: [Int: DynamicCommentListSignature]
    let replyStates: [Int: LoadingState]
    let replyPages: [Int: Int]
    let replyHasMore: [Int: Bool]
    let dialogThreadSignatures: [String: DynamicCommentListSignature]
    let dialogStates: [String: LoadingState]
}

private struct DynamicCommentReplyItem: Identifiable, Equatable {
    let id: Int
    let reply: Comment
    let display: DynamicCommentRowDisplayModel
    let canShowDialog: Bool

    init(reply: Comment, rootComment: Comment) {
        id = reply.id
        self.reply = reply
        display = DynamicCommentRowDisplayModel(comment: reply)
        canShowDialog = Self.canShowDialog(for: reply, rootComment: rootComment)
    }

    private static func canShowDialog(for reply: Comment, rootComment: Comment) -> Bool {
        guard reply.id != rootComment.id else { return false }
        if let dialogID = reply.dialogID, dialogID > 0 {
            return true
        }
        if let parentID = reply.parentID, parentID > 0, parentID != rootComment.rpid {
            return true
        }
        return DynamicCommentTextBuilder.hasReplyTarget(in: reply.content?.message)
    }
}

private struct DynamicCommentDialogItem: Identifiable, Equatable {
    let id: Int
    let reply: Comment
    let display: DynamicCommentRowDisplayModel

    init(reply: Comment) {
        id = reply.id
        self.reply = reply
        display = DynamicCommentRowDisplayModel(comment: reply)
    }
}

nonisolated private struct DynamicCommentReplyItemSignature: Equatable {
    let rootID: Int
    let replies: [Reply]

    init(rootComment: Comment, replies: [Comment]) {
        rootID = rootComment.id
        self.replies = replies.map(Reply.init)
    }

    struct Reply: Equatable {
        let id: Int
        let parentID: Int?
        let dialogID: Int?
        let message: String?

        init(_ reply: Comment) {
            id = reply.id
            parentID = reply.parentID
            dialogID = reply.dialogID
            message = reply.content?.message
        }
    }
}

private struct DynamicCommentReplyItemCacheEntry {
    let signature: DynamicCommentReplyItemSignature
    let items: [DynamicCommentReplyItem]
}

private struct DynamicCommentDialogItemCacheEntry {
    let signature: DynamicCommentReplyItemSignature
    let items: [DynamicCommentDialogItem]
}

private struct DynamicCommentReplyRootView: View {
    let comment: Comment
    private let display: DynamicCommentRowDisplayModel

    init(comment: Comment) {
        self.comment = comment
        self.display = DynamicCommentRowDisplayModel(comment: comment)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            DynamicCommentAvatar(urlString: display.avatarURLString, size: 40)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(display.authorName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if !display.timeText.isEmpty {
                        Text(display.timeText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                BiliEmoteText(content: comment.content, font: .subheadline, textColor: .primary, emoteSize: 22)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                DynamicCommentImageGrid(images: display.pictures)
            }
        }
    }
}

private struct DynamicCommentReplyDetailRow: View {
    let item: DynamicCommentReplyItem
    let showDialog: (() -> Void)?

    private var reply: Comment {
        item.reply
    }

    private var display: DynamicCommentRowDisplayModel {
        item.display
    }

    init(item: DynamicCommentReplyItem, showDialog: (() -> Void)?) {
        self.item = item
        self.showDialog = showDialog
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            DynamicCommentAvatar(urlString: display.avatarURLString, size: 36)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(display.authorName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if !display.timeText.isEmpty {
                        Text(display.timeText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Label(display.likeText, systemImage: display.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(.caption)
                        .foregroundStyle(display.isLiked ? .pink : .secondary)
                        .labelStyle(.titleAndIcon)
                }

                BiliEmoteText(content: reply.content, font: .subheadline, textColor: .primary, emoteSize: 22)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                DynamicCommentImageGrid(images: display.pictures)

                if let showDialog {
                    Button(action: showDialog) {
                        Label("查看对话", systemImage: "text.bubble")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.pink)
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 12)
    }
}

private struct DynamicCommentDialogSheet: View {
    let rootComment: Comment
    let focusReply: Comment
    let replyStore: DynamicCommentReplyStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DynamicCommentReplyRootView(comment: rootComment)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                    Divider()

                    DynamicCommentDialogContent(rootComment: rootComment, focusReply: focusReply, replyStore: replyStore)
                }
            }
            .navigationTitle("查看对话")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await replyStore.loadDialog(for: rootComment, reply: focusReply)
            }
        }
        .presentationDetents([.fraction(0.7)])
        .presentationDragIndicator(.visible)
    }
}

private struct DynamicCommentDialogContent: View {
    let rootComment: Comment
    let focusReply: Comment
    @ObservedObject var replyStore: DynamicCommentReplyStore

    @ViewBuilder
    var body: some View {
        let snapshot = replyStore.dialogSnapshot(for: rootComment, reply: focusReply)

        if snapshot.items.isEmpty && snapshot.state.isLoading {
            CommentLoadingSkeletonList(count: 3)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        } else if snapshot.items.isEmpty, case .failed(let message) = snapshot.state {
            DynamicCommentErrorView(message: message) {
                Task { await replyStore.reloadDialog(for: rootComment, reply: focusReply) }
            }
            .padding(16)
        } else if snapshot.items.isEmpty {
            EmptyStateView(title: "暂无对话", systemImage: "text.bubble", message: "暂时没有找到这条回复的上下文。")
                .padding(16)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(snapshot.items) { item in
                    DynamicCommentDialogRow(item: item, isFocused: item.id == focusReply.id)
                        .padding(.horizontal, 16)

                    Divider()
                        .padding(.leading, 66)
                }

                if case .failed(let message) = snapshot.state {
                    DynamicCommentErrorView(message: message) {
                        Task { await replyStore.reloadDialog(for: rootComment, reply: focusReply) }
                    }
                    .padding(16)
                }
            }
        }
    }
}

private struct DynamicCommentDialogRow: View {
    let item: DynamicCommentDialogItem
    let isFocused: Bool

    private var reply: Comment {
        item.reply
    }

    private var display: DynamicCommentRowDisplayModel {
        item.display
    }

    init(item: DynamicCommentDialogItem, isFocused: Bool) {
        self.item = item
        self.isFocused = isFocused
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            DynamicCommentAvatar(urlString: display.avatarURLString, size: 36)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(display.authorName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if !display.timeText.isEmpty {
                        Text(display.timeText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Label(display.likeText, systemImage: display.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(.caption)
                        .foregroundStyle(display.isLiked ? .pink : .secondary)
                        .labelStyle(.titleAndIcon)
                }

                BiliEmoteText(content: reply.content, font: .subheadline, textColor: .primary, emoteSize: 22)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                DynamicCommentImageGrid(images: display.pictures)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, isFocused ? 10 : 0)
        .background(isFocused ? Color.pink.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private enum DynamicCommentTextBuilder {
    static func nameAndMessage(name: String, message: String, font: Font, contentColor: Color) -> AttributedString {
        var user = AttributedString("\(name)：")
        user.font = font.weight(.semibold)
        user.foregroundColor = .secondary

        return user + replyMessage(message, font: font, contentColor: contentColor)
    }

    static func replyMessage(_ message: String, font: Font, contentColor: Color) -> AttributedString {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let split = replyPrefixSplit(in: text) else {
            var content = AttributedString(text)
            content.font = font
            content.foregroundColor = contentColor
            return content
        }

        var verb = AttributedString("回复 ")
        verb.font = font
        verb.foregroundColor = contentColor

        var target = AttributedString(split.target)
        target.font = font.weight(.semibold)
        target.foregroundColor = .pink

        var separator = AttributedString(split.separator)
        separator.font = font
        separator.foregroundColor = contentColor

        var content = AttributedString(split.content)
        content.font = font
        content.foregroundColor = contentColor

        return verb + target + separator + content
    }

    static func hasReplyTarget(in message: String?) -> Bool {
        guard let message else { return false }
        return replyPrefixSplit(in: message.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    private static func replyPrefixSplit(in message: String) -> (target: String, separator: String, content: String)? {
        let supportedVerbs = ["回复", "回覆", "回復"]
        guard let verb = supportedVerbs.first(where: { message.hasPrefix($0) }) else { return nil }

        var cursor = message.index(message.startIndex, offsetBy: verb.count)
        while cursor < message.endIndex, message[cursor].isWhitespace {
            cursor = message.index(after: cursor)
        }

        guard cursor < message.endIndex, message[cursor] == "@" else { return nil }
        guard let colon = message[cursor...].firstIndex(where: { $0 == ":" || $0 == "：" }) else { return nil }

        let prefixEnd = message.index(after: colon)
        let target = String(message[cursor..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = String(message[colon..<prefixEnd])
        let content = String(message[prefixEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return nil }
        return (target, separator, content)
    }
}

private struct DynamicCommentAvatar: View {
    let urlString: String?
    let size: CGFloat

    var body: some View {
        let pixelSize = Int(size * 3)
        AvatarRemoteImage(urlString: urlString, pixelSize: pixelSize) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: size * 0.9))
                .foregroundStyle(.tertiary)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

private struct DynamicImageDisplayItem: Identifiable {
    let id: String
    let index: Int
    let image: DynamicImageItem
    let aspectRatio: CGFloat
}

private enum DynamicImageDisplayItems {
    static func make(from images: [DynamicImageItem], limit: Int? = nil) -> [DynamicImageDisplayItem] {
        let source = limit.map { Array(images.prefix($0)) } ?? images
        var seenIDs = [String: Int]()
        return source.enumerated().map { index, image in
            let normalizedURLString = image.normalizedURL
            let baseID = stableBaseID(
                for: image,
                normalizedURLString: normalizedURLString,
                fallbackIndex: index
            )
            let occurrence = seenIDs[baseID, default: 0]
            seenIDs[baseID] = occurrence + 1
            let id = occurrence == 0 ? baseID : "\(baseID)#\(occurrence)"
            return DynamicImageDisplayItem(
                id: id,
                index: index,
                image: image,
                aspectRatio: aspectRatio(for: image, normalizedURLString: normalizedURLString)
            )
        }
    }

    static func previewItems(from displayItems: [DynamicImageDisplayItem]) -> [ZoomyImagePreviewItem] {
        displayItems.compactMap { item in
            guard let normalizedURLString = item.image.normalizedURL,
                  let url = URL(string: normalizedURLString)
            else { return nil }
            return ZoomyImagePreviewItem(
                id: item.id,
                fallbackURL: url,
                viewerURL: url
            )
        }
    }

    private static func stableBaseID(
        for image: DynamicImageItem,
        normalizedURLString: String?,
        fallbackIndex: Int
    ) -> String {
        if let normalizedURLString {
            return normalizedURLString
        }
        let trimmedURL = image.url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedURL.isEmpty {
            return trimmedURL
        }
        return "image-\(fallbackIndex)"
    }

    private static func aspectRatio(for image: DynamicImageItem, normalizedURLString: String?) -> CGFloat {
        if let width = image.width, let height = image.height, width > 0, height > 0 {
            return max(CGFloat(width) / CGFloat(height), 0.1)
        }
        if let ratio = normalizedURLString?.biliImageURLAspectRatio {
            return max(CGFloat(ratio), 0.1)
        }
        return 1
    }
}

private struct DynamicCommentImageGrid: View {
    let images: [DynamicImageItem]

    var body: some View {
        CompactDynamicImageMosaicGrid(
            images: images,
            accessibilityName: "评论图片",
            placeholderFill: Color(.secondarySystemGroupedBackground)
        )
        .padding(.top, 2)
    }
}

private struct DynamicCommentErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                Text("评论加载失败")
                    .font(.subheadline.weight(.semibold))
            }

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Button(action: retry) {
                Label("重试", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
            }
            .dynamicCommentGlassButtonStyle()
            .controlSize(.small)
            .buttonBorderShape(.capsule)
            .tint(.pink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .dynamicCommentGlassCard()
    }
}

private struct DynamicOriginalPreview: View {
    let item: DynamicOriginalItem
    let parentID: String
    let contentWidth: CGFloat?
    private let video: VideoItem?
    private let live: DynamicLive?
    private let liveRoom: LiveRoom?
    private let authorOwner: VideoOwner?
    private let imageItems: [DynamicImageItem]
    private let textSegments: [DynamicTextSegment]
    private let textInput: DynamicAttributedTextInput
    private let topLevelDisplayText: String?

    init(
        item: DynamicOriginalItem,
        parentID: String,
        contentWidth: CGFloat? = nil
    ) {
        self.item = item
        self.parentID = parentID
        self.contentWidth = contentWidth
        self.video = item.archive?.asVideoItem(author: item.author)
        self.live = item.live
        self.liveRoom = item.live?.asLiveRoom(author: item.author)
        self.authorOwner = item.author?.owner
        self.imageItems = item.imageItems.filter { $0.normalizedURL != nil }
        self.textSegments = item.textSegments
        self.textInput = DynamicFeedCardDisplayModel.textInput(
            segments: item.textSegments,
            emoteSize: 20,
            maxLines: 5
        )
        self.topLevelDisplayText = DynamicTextSegment.displayText(from: item.textSegments)
    }

    var body: some View {
        originalContent
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground).opacity(0.78))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.pink.opacity(0.58))
                .frame(width: 3)
                .padding(.vertical, 10)
                .padding(.leading, 6)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator).opacity(0.10), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var originalContent: some View {
        if item.visible == false || !item.hasDisplayableContent {
            DynamicForwardUnavailableView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if let author = item.author {
                    if let authorOwner, authorOwner.mid > 0 {
                        NavigationLink {
                            UploaderView(owner: authorOwner)
                        } label: {
                            originalAuthorIdentity(author)
                        }
                        .buttonStyle(.plain)
                    } else {
                        originalAuthorIdentity(author)
                    }
                }

                if topLevelDisplayText?.isEmpty == false {
                    DynamicRichTextView(input: textInput)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let video {
                    VideoRouteLink(video) {
                        DynamicArchivePreview(video: video, style: .compact)
                    }
                }

                if let live {
                    DynamicLiveRouteLink(room: liveRoom) {
                        DynamicLivePreview(live: live, style: .compact)
                    }
                }

                if !imageItems.isEmpty {
                    DynamicImageThumbnailStrip(
                        images: imageItems,
                        availableWidth: contentWidth
                    )
                }
            }
        }
    }

    private func originalAuthorIdentity(_ author: DynamicAuthor) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "quote.opening")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.pink)

            Text("转发自")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text("@\(author.name ?? "Unknown")")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }

}

private struct DynamicForwardUnavailableView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.caption.weight(.semibold))
            Text("原动态不可见或已删除")
                .font(.footnote)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct DynamicImageHeroPreview: View {
    let images: [DynamicImageItem]
    var cornerRadius: CGFloat = 18
    var aspectRatio: CGFloat = 16 / 9

    private var firstImage: DynamicImageItem? {
        images.first
    }

    var body: some View {
        if let firstImage {
            DynamicImageButton(
                image: firstImage,
                displayMode: .hero(aspectRatio: aspectRatio, cornerRadius: cornerRadius),
            ) {
                heroOverlay
            }
            .accessibilityLabel(accessibilityTitle)
        }
    }

    @ViewBuilder
    private var heroOverlay: some View {
        if images.count > 1 {
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        .clear,
                        .black.opacity(0.46)
                    ],
                    startPoint: .center,
                    endPoint: .bottom
                )

                HStack(alignment: .bottom) {
                    VideoCoverGlassBadge {
                        Label("\(min(images.count, 9))图", systemImage: "photo.on.rectangle.angled")
                            .labelStyle(.titleAndIcon)
                    }

                    Spacer(minLength: 8)

                    VideoCoverGlassBadge {
                        Text("1/\(images.count)")
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(.white)
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    private var accessibilityTitle: String {
        images.count > 1 ? "查看 \(images.count) 张图片" : "查看图片"
    }
}

private struct DynamicImageThumbnailStrip: View {
    @StateObject private var previewGroup = ZoomyImagePreviewGroup()
    @State private var availableWidth: CGFloat = Self.defaultWidth
    let images: [DynamicImageItem]
    var horizontalBleed: CGFloat = 0
    let knownAvailableWidth: CGFloat?
    private let displayedImages: [DynamicImageDisplayItem]
    private let previewItems: [ZoomyImagePreviewItem]
    private static let defaultWidth: CGFloat = 330
    private static let singleImageMaxWidthRatio: CGFloat = 0.60
    private static let minSingleImageWidth: CGFloat = 96

    init(
        images: [DynamicImageItem],
        horizontalBleed: CGFloat = 0,
        availableWidth: CGFloat? = nil
    ) {
        self.images = images
        self.horizontalBleed = horizontalBleed
        self.knownAvailableWidth = availableWidth.map { floor($0) }.flatMap { $0 > 1 ? $0 : nil }
        let displayedImages = DynamicImageDisplayItems.make(from: images)
        self.displayedImages = displayedImages
        self.previewItems = DynamicImageDisplayItems.previewItems(from: displayedImages)
    }

    var body: some View {
        switch displayedImages.count {
        case 0:
            EmptyView()
        case 1:
            measuredContent {
                singleImageContent(width: resolvedWidth)
            }
        default:
            DynamicImageGrid(
                images: images,
                availableWidth: knownAvailableWidth.map { max($0 + horizontalBleed * 2, 1) }
            )
                .padding(.horizontal, -horizontalBleed)
        }
    }

    private var resolvedWidth: CGFloat {
        if let knownAvailableWidth {
            return knownAvailableWidth
        }
        guard availableWidth > 1 else { return Self.defaultWidth }
        return floor(availableWidth)
    }

    @ViewBuilder
    private func measuredContent<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if knownAvailableWidth != nil {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(widthReader)
                .onPreferenceChange(DynamicImageGridWidthPreferenceKey.self) { width in
                    updateAvailableWidth(width)
                }
        }
    }

    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: DynamicImageGridWidthPreferenceKey.self,
                    value: proxy.size.width
                )
        }
    }

    private func updateAvailableWidth(_ width: CGFloat) {
        let roundedWidth = floor(width)
        guard roundedWidth > 1, abs(availableWidth - roundedWidth) > 0.5 else { return }
        availableWidth = roundedWidth
    }

    @ViewBuilder
    private func singleImageContent(width: CGFloat) -> some View {
        if let item = displayedImages.first {
            let fullWidth = max(width + horizontalBleed * 2, 1)
            let imageWidth = floor(max(fullWidth * Self.singleImageMaxWidthRatio, Self.minSingleImageWidth))
            let aspectRatio = max(item.aspectRatio, 0.1)
            let imageHeight = ceil(imageWidth / aspectRatio)

            HStack {
                DynamicImageButton(
                    image: item.image,
                    previewItems: previewItems,
                    previewItemID: item.id,
                    previewGroup: previewGroup,
                    displayMode: .single
                )
                .frame(width: imageWidth, height: imageHeight)
                .accessibilityLabel(accessibilityTitle(for: item.index))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, horizontalBleed)
            .frame(width: fullWidth, height: imageHeight, alignment: .leading)
            .padding(.horizontal, -horizontalBleed)
        }
    }

    private func accessibilityTitle(for index: Int) -> String {
        images.count > 1 ? "查看第 \(index + 1) 张图片，共 \(images.count) 张" : "查看图片"
    }
}

private struct DynamicImageGrid: View {
    @StateObject private var previewGroup = ZoomyImagePreviewGroup()
    @State private var availableWidth: CGFloat = Self.defaultWidth
    let images: [DynamicImageItem]
    let knownAvailableWidth: CGFloat?
    private let displayedImages: [DynamicImageDisplayItem]
    private let layout: DynamicImageGridLayout
    private let previewItems: [ZoomyImagePreviewItem]
    private static let defaultWidth: CGFloat = 330
    private static let spacing: CGFloat = 4

    init(images: [DynamicImageItem], availableWidth: CGFloat? = nil) {
        self.images = images
        self.knownAvailableWidth = availableWidth.map { floor($0) }.flatMap { $0 > 1 ? $0 : nil }
        let displayedImages = DynamicImageDisplayItems.make(from: images, limit: 9)
        self.displayedImages = displayedImages
        self.layout = DynamicImageGridLayout(displayedImages: displayedImages)
        self.previewItems = DynamicImageDisplayItems.previewItems(
            from: DynamicImageDisplayItems.make(from: images)
        )
    }

    var body: some View {
        measuredContent {
            content(width: resolvedWidth)
        }
    }

    private var resolvedWidth: CGFloat {
        if let knownAvailableWidth {
            return knownAvailableWidth
        }
        guard availableWidth > 1 else { return Self.defaultWidth }
        return floor(availableWidth)
    }

    @ViewBuilder
    private func measuredContent<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if knownAvailableWidth != nil {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(widthReader)
                .onPreferenceChange(DynamicImageGridWidthPreferenceKey.self) { width in
                    updateAvailableWidth(width)
                }
        }
    }

    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: DynamicImageGridWidthPreferenceKey.self,
                    value: proxy.size.width
                )
        }
    }

    private func updateAvailableWidth(_ width: CGFloat) {
        let roundedWidth = floor(width)
        guard roundedWidth > 1, abs(availableWidth - roundedWidth) > 0.5 else { return }
        availableWidth = roundedWidth
    }

    @ViewBuilder
    private func content(width: CGFloat) -> some View {
        switch displayedImages.count {
        case 0:
            EmptyView()
        case 1:
            singleImageLayout(width: width)
        case 2:
            equalGrid(width: width, columns: 2)
        case 3:
            threeImageMosaic(width: width)
        case 4:
            equalGrid(width: width, columns: 2)
        case 5:
            fiveImageMosaic(width: width)
        case 6:
            equalGrid(width: width, columns: 3)
        case 7:
            sevenImageMosaic(width: width)
        case 8:
            eightImageMosaic(width: width)
        default:
            equalGrid(width: width, columns: 3)
        }
    }

    @ViewBuilder
    private func singleImageLayout(width: CGFloat) -> some View {
        if let item = displayedImages.first {
            let imageWidth = floor(width * 0.82)
            let aspectRatio = item.aspectRatio
            let imageHeight = min(max(imageWidth / aspectRatio, 150), 360)
            HStack {
                imageTile(item, displayMode: .single)
                .frame(width: imageWidth, height: imageHeight)
                Spacer(minLength: 0)
            }
            .frame(width: width, alignment: .leading)
        }
    }

    private func threeImageMosaic(width: CGFloat) -> some View {
        let smallSide = floor((width - Self.spacing * 2) / 3)
        let largeSide = smallSide * 2 + Self.spacing
        return HStack(spacing: Self.spacing) {
            if let first = layout.primaryTile {
                imageTile(first, cornerRadius: 10)
                .frame(width: largeSide, height: largeSide)
            }

            VStack(spacing: Self.spacing) {
                ForEach(layout.trailingTiles) { item in
                    imageTile(item)
                    .frame(width: smallSide, height: smallSide)
                }
            }
        }
        .frame(width: width, height: largeSide, alignment: .leading)
    }

    private func fiveImageMosaic(width: CGFloat) -> some View {
        let largeSide = floor((width - Self.spacing) / 2)
        let smallSide = tileSide(for: width, columns: 3)
        return VStack(spacing: Self.spacing) {
            HStack(spacing: Self.spacing) {
                ForEach(layout.topTiles) { item in
                    imageTile(item, cornerRadius: 10)
                        .frame(width: largeSide, height: largeSide)
                }
            }

            HStack(spacing: Self.spacing) {
                ForEach(layout.middleTiles) { item in
                    imageTile(item)
                        .frame(width: smallSide, height: smallSide)
                }
            }
        }
        .frame(width: width, height: largeSide + Self.spacing + smallSide, alignment: .topLeading)
    }

    private func sevenImageMosaic(width: CGFloat) -> some View {
        let smallSide = tileSide(for: width, columns: 3)
        let largeSide = smallSide * 2 + Self.spacing
        let footerSide = tileSide(for: width, columns: 4)
        return VStack(spacing: Self.spacing) {
            HStack(spacing: Self.spacing) {
                if let first = layout.primaryTile {
                    imageTile(first, cornerRadius: 10)
                        .frame(width: largeSide, height: largeSide)
                }

                VStack(spacing: Self.spacing) {
                    ForEach(layout.trailingTiles) { item in
                        imageTile(item)
                            .frame(width: smallSide, height: smallSide)
                    }
                }
            }

            HStack(spacing: Self.spacing) {
                ForEach(layout.bottomTiles) { item in
                    imageTile(item)
                        .frame(width: footerSide, height: footerSide)
                }
            }
        }
        .frame(width: width, height: largeSide + Self.spacing + footerSide, alignment: .topLeading)
    }

    private func eightImageMosaic(width: CGFloat) -> some View {
        let largeSide = floor((width - Self.spacing) / 2)
        let smallSide = tileSide(for: width, columns: 3)
        return VStack(spacing: Self.spacing) {
            HStack(spacing: Self.spacing) {
                ForEach(layout.topTiles) { item in
                    imageTile(item, cornerRadius: 10)
                        .frame(width: largeSide, height: largeSide)
                }
            }

            fixedRows(
                layout.eightImageRows,
                width: width,
                tileSide: smallSide
            )
        }
        .frame(width: width, height: largeSide + Self.spacing + smallSide * 2 + Self.spacing, alignment: .topLeading)
    }

    private func equalGrid(width: CGFloat, columns: Int) -> some View {
        let side = tileSide(for: width, columns: columns)
        return VStack(spacing: Self.spacing) {
            ForEach(layout.rows(for: columns)) { row in
                HStack(spacing: Self.spacing) {
                    ForEach(row.items) { item in
                        imageTile(item, cornerRadius: columns == 2 ? 10 : 8)
                            .frame(width: side, height: side)
                    }

                    if row.items.count < columns {
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    private func fixedRows(
        _ rows: [DynamicImageGridRow],
        width: CGFloat,
        tileSide: CGFloat
    ) -> some View {
        return VStack(spacing: Self.spacing) {
            ForEach(rows) { row in
                HStack(spacing: Self.spacing) {
                    ForEach(row.items) { item in
                        imageTile(item)
                            .frame(width: tileSide, height: tileSide)
                    }
                }
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    private func imageTile(
        _ item: DynamicImageDisplayItem,
        cornerRadius: CGFloat = 8
    ) -> some View {
        imageTile(item, displayMode: .square(cornerRadius: cornerRadius))
    }

    private func imageTile(
        _ item: DynamicImageDisplayItem,
        displayMode: DynamicImageCell.DisplayMode
    ) -> some View {
        DynamicImageButton(
            image: item.image,
            previewItems: previewItems,
            previewItemID: item.id,
            previewGroup: previewGroup,
            displayMode: displayMode
        ) {
            overflowOverlay(for: item)
        }
    }

    @ViewBuilder
    private func overflowOverlay(for item: DynamicImageDisplayItem) -> some View {
        if item.index == 8, images.count > 9 {
            ZStack {
                Color.clear
                Text("+\(images.count - 8)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .glassEffect(.regular.tint(.black.opacity(0.16)).interactive(false), in: Capsule())
            }
        }
    }

    private func tileSide(for width: CGFloat, columns: Int) -> CGFloat {
        floor((width - Self.spacing * CGFloat(max(columns - 1, 0))) / CGFloat(max(columns, 1)))
    }
}

private struct DynamicImageGridRow: Identifiable {
    let id: Int
    let items: [DynamicImageDisplayItem]
}

private struct DynamicImageGridLayout {
    let primaryTile: DynamicImageDisplayItem?
    let topTiles: [DynamicImageDisplayItem]
    let trailingTiles: [DynamicImageDisplayItem]
    let middleTiles: [DynamicImageDisplayItem]
    let bottomTiles: [DynamicImageDisplayItem]
    let eightImageRows: [DynamicImageGridRow]
    private let twoColumnRows: [DynamicImageGridRow]
    private let threeColumnRows: [DynamicImageGridRow]

    init(displayedImages: [DynamicImageDisplayItem]) {
        primaryTile = displayedImages.first
        topTiles = Self.slice(displayedImages, from: 0, count: 2)
        trailingTiles = Self.slice(displayedImages, from: 1, count: 2)
        middleTiles = Self.slice(displayedImages, from: 2, count: 3)
        bottomTiles = Self.slice(displayedImages, from: 3, count: 4)
        eightImageRows = Self.chunked(Self.slice(displayedImages, from: 2, count: 6), columns: 3)
        twoColumnRows = Self.chunked(displayedImages, columns: 2)
        threeColumnRows = Self.chunked(displayedImages, columns: 3)
    }

    func rows(for columns: Int) -> [DynamicImageGridRow] {
        columns == 2 ? twoColumnRows : threeColumnRows
    }

    private static func slice(
        _ items: [DynamicImageDisplayItem],
        from startIndex: Int,
        count: Int
    ) -> [DynamicImageDisplayItem] {
        guard startIndex < items.count, count > 0 else { return [] }
        let endIndex = min(startIndex + count, items.count)
        return Array(items[startIndex..<endIndex])
    }

    private static func chunked(
        _ items: [DynamicImageDisplayItem],
        columns: Int
    ) -> [DynamicImageGridRow] {
        let columnCount = max(columns, 1)
        return stride(from: 0, to: items.count, by: columnCount).map { startIndex in
            DynamicImageGridRow(
                id: startIndex / columnCount,
                items: Array(items[startIndex..<min(startIndex + columnCount, items.count)])
            )
        }
    }
}

private struct DynamicImageGridWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let nextValue = nextValue()
        if nextValue > 0 {
            value = nextValue
        }
    }
}

private struct DynamicImageButton<Overlay: View>: View {
    let image: DynamicImageItem
    let previewItems: [ZoomyImagePreviewItem]
    let previewItemID: String?
    let previewGroup: ZoomyImagePreviewGroup?
    let displayMode: DynamicImageCell.DisplayMode
    @ViewBuilder let overlay: () -> Overlay

    init(
        image: DynamicImageItem,
        previewItems: [ZoomyImagePreviewItem] = [],
        previewItemID: String? = nil,
        previewGroup: ZoomyImagePreviewGroup? = nil,
        displayMode: DynamicImageCell.DisplayMode,
        @ViewBuilder overlay: @escaping () -> Overlay
    ) {
        self.image = image
        self.previewItems = previewItems
        self.previewItemID = previewItemID
        self.previewGroup = previewGroup
        self.displayMode = displayMode
        self.overlay = overlay
    }

    var body: some View {
        DynamicImageCell(
            image: image,
            previewItems: previewItems,
            previewItemID: previewItemID,
            previewGroup: previewGroup,
            displayMode: displayMode
        )
            .overlay(overlay())
            .contentShape(RoundedRectangle(cornerRadius: displayMode.cornerRadius, style: .continuous))
    }
}

private extension DynamicImageButton where Overlay == EmptyView {
    init(
        image: DynamicImageItem,
        previewItems: [ZoomyImagePreviewItem] = [],
        previewItemID: String? = nil,
        previewGroup: ZoomyImagePreviewGroup? = nil,
        displayMode: DynamicImageCell.DisplayMode
    ) {
        self.init(
            image: image,
            previewItems: previewItems,
            previewItemID: previewItemID,
            previewGroup: previewGroup,
            displayMode: displayMode
        ) {
            EmptyView()
        }
    }
}

private struct DynamicImageCell: View {
    enum DisplayMode {
        case single
        case square(cornerRadius: CGFloat)
        case hero(aspectRatio: CGFloat, cornerRadius: CGFloat)
        case fixedHeight(height: CGFloat, cornerRadius: CGFloat)
    }

    let image: DynamicImageItem
    let previewItems: [ZoomyImagePreviewItem]
    let previewItemID: String?
    let previewGroup: ZoomyImagePreviewGroup?
    let displayMode: DisplayMode
    @State private var thumbnailShadowOpacityScale = 1.0
    private let normalizedURLString: String?
    private let imageAspectRatio: CGFloat

    init(
        image: DynamicImageItem,
        previewItems: [ZoomyImagePreviewItem] = [],
        previewItemID: String? = nil,
        previewGroup: ZoomyImagePreviewGroup? = nil,
        displayMode: DisplayMode
    ) {
        self.image = image
        self.previewItems = previewItems
        self.previewItemID = previewItemID
        self.previewGroup = previewGroup
        self.displayMode = displayMode
        let normalizedURLString = image.normalizedURL
        self.normalizedURLString = normalizedURLString
        self.imageAspectRatio = Self.aspectRatio(for: image, normalizedURLString: normalizedURLString)
    }

    var body: some View {
        switch displayMode {
        case .single:
            imageContent
                .aspectRatio(displayAspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .mediaShadow(.regular, opacityScale: thumbnailShadowOpacityScale)
        case .square(let cornerRadius):
            imageContent
                .aspectRatio(1, contentMode: .fill)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .mediaShadow(.subtle, opacityScale: thumbnailShadowOpacityScale)
        case .hero(let aspectRatio, let cornerRadius):
            imageContent
                .aspectRatio(aspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .mediaShadow(.regular, opacityScale: thumbnailShadowOpacityScale)
        case .fixedHeight(let height, let cornerRadius):
            imageContent
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .frame(height: height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .mediaShadow(.regular, opacityScale: thumbnailShadowOpacityScale)
        }
    }

    private var imageContent: some View {
        ZStack {
            BiliMediaPlaceholder(style: .image, iconSize: 19)

            ZoomyRemoteImage(
                url: normalizedURLString
                    .map { $0.biliImageThumbnailURL(maxSide: thumbnailMaxSide) }
                    .flatMap(URL.init(string:)),
                fallbackURL: normalizedURLString.flatMap(URL.init(string:)),
                viewerURL: normalizedURLString.flatMap(URL.init(string:)),
                viewerItems: previewItems,
                viewerItemID: previewItemID,
                viewerGroup: previewGroup,
                targetPixelSize: thumbnailMaxSide,
                cornerRadius: displayMode.cornerRadius,
                contentMode: thumbnailContentMode,
                onViewerPresentationChange: updateThumbnailShadowVisibility
            ) { phase in
                BiliMediaPlaceholder(
                    style: .image,
                    phase: phase,
                    iconSize: 19
                )
            }
        }
    }

    private func updateThumbnailShadowVisibility(isViewerPresented: Bool) {
        if isViewerPresented {
            thumbnailShadowOpacityScale = 0
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                thumbnailShadowOpacityScale = 1
            }
        }
    }

    private var thumbnailContentMode: UIView.ContentMode {
        switch displayMode {
        case .fixedHeight:
            return .scaleAspectFit
        case .single, .square, .hero:
            return .scaleAspectFill
        }
    }

    private var displayAspectRatio: CGFloat {
        switch displayMode {
        case .single:
            return imageAspectRatio
        case .square(_):
            return 1
        case .hero(let aspectRatio, _):
            return aspectRatio
        case .fixedHeight:
            return imageAspectRatio
        }
    }

    private var thumbnailMaxSide: Int {
        let usesCompactImages = PlaybackEnvironment.current.shouldPreferConservativePlayback
        switch displayMode {
        case .single, .hero(_, _):
            return usesCompactImages ? 960 : 1280
        case .square(_), .fixedHeight:
            return usesCompactImages ? 360 : 420
        }
    }

    private static func aspectRatio(for image: DynamicImageItem, normalizedURLString: String?) -> CGFloat {
        if let width = image.width, let height = image.height, width > 0, height > 0 {
            return max(CGFloat(width) / CGFloat(height), 0.1)
        }
        if let ratio = normalizedURLString?.biliImageURLAspectRatio {
            return max(CGFloat(ratio), 0.1)
        }
        return 1
    }
}

private extension DynamicImageCell.DisplayMode {
    var cornerRadius: CGFloat {
        switch self {
        case .single:
            return 8
        case .square(let cornerRadius), .hero(_, let cornerRadius), .fixedHeight(_, let cornerRadius):
            return cornerRadius
        }
    }
}

private struct DynamicArchivePreview: View {
    enum Style {
        case large
        case compact
    }

    private static let compactCoverSize = CGSize(width: 118, height: 66)

    let video: VideoItem
    let display: VideoCardDisplayModel
    var style: Style = .large
    var showsHeader = true

    init(video: VideoItem, style: Style = .large, showsHeader: Bool = true) {
        self.video = video
        self.display = VideoCardDisplayModel(video: video)
        self.style = style
        self.showsHeader = showsHeader
    }

    var body: some View {
        switch style {
        case .large:
            largeContent
        case .compact:
            compactContent
        }
    }

    private var largeContent: some View {
        YouTubeStyleVideoFeedCardView(
            display: display,
            showsMetadataSummary: false,
            showsPlayBadge: true,
            fixedCoverAspectRatio: 16 / 9,
            coverShadowLevel: .control
        )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("瑙嗛 \(video.title)")
    }

    private var compactContent: some View {
        HStack(spacing: 10) {
            cover(showsPlayGlyph: true, aspectRatio: 16 / 9, fixedSize: Self.compactCoverSize)
                .frame(width: Self.compactCoverSize.width, height: Self.compactCoverSize.height)

            VStack(alignment: .leading, spacing: 7) {
                Text(video.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                metadata
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func cover(showsPlayGlyph: Bool, aspectRatio: CGFloat, fixedSize: CGSize? = nil) -> some View {
        FixedAspectPreview(aspectRatio: aspectRatio) {
            ZStack {
                Color.clear

                AdaptiveVideoCoverImage(display: display, style: .exactCrop, fixedSize: fixedSize)

                if showsPlayGlyph {
                    DynamicVideoPlayBadge(size: 28, iconSize: 12)
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }

                if video.duration != nil {
                    VideoCoverDurationBadge(BiliFormatters.duration(video.duration))
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
        }
        .background(BiliMediaPlaceholder(style: .video, iconSize: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .mediaShadow(.control)
    }

    private var metadata: some View {
        HStack(spacing: 10) {
            if let ownerName = video.owner?.name, !ownerName.isEmpty {
                Text(ownerName)
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct FixedAspectPreview<Content: View>: View {
    let aspectRatio: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .clipped()
    }
}

private struct DynamicVideoPlayBadge: View {
    var size: CGFloat = 48
    var iconSize: CGFloat = 18

    var body: some View {
        VideoCoverPlayBadge(size: size, iconSize: iconSize)
    }
}

private struct DynamicLivePreview: View {
    enum Style {
        case large
        case compact
    }

    let live: DynamicLive
    var style: Style = .large

    var body: some View {
        switch style {
        case .large:
            largeContent
                .accessibilityElement(children: .combine)
                .accessibilityLabel("鐩存挱 \(live.displayTitle)")
        case .compact:
            compactContent
                .accessibilityElement(children: .combine)
                .accessibilityLabel("鐩存挱 \(live.displayTitle)")
        }
    }

    private var largeContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            cover(showsCenterBadge: false)

            Text(live.displayTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)

            metadata
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator).opacity(0.10), lineWidth: 0.5)
        }
    }

    private var compactContent: some View {
        HStack(spacing: 10) {
            cover(showsCenterBadge: false)
                .frame(width: 118, height: 118 * 9 / 16)

            VStack(alignment: .leading, spacing: 7) {
                Text(live.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                metadata
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func cover(showsCenterBadge: Bool) -> some View {
        FixedAspectPreview(aspectRatio: 16 / 9) {
            ZStack(alignment: .topLeading) {
                Color.clear

                let sourceURLString = live.normalizedCoverURL
                CachedRemoteImage(
                    url: sourceURLString.flatMap { URL(string: $0.biliCoverThumbnailURL(width: 420, height: 236)) },
                    fallbackURL: sourceURLString.flatMap(URL.init(string:)),
                    targetPixelSize: 420,
                    animatesAppearance: false
                ) { image in
                    image.resizable().scaledToFill()
                } phasePlaceholder: { phase, _ in
                    BiliMediaPlaceholder(
                        style: .video,
                        phase: phase,
                        iconSize: 17
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                if showsCenterBadge {
                    Label("直播中", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .glassEffect(.regular.tint(.black.opacity(0.16)).interactive(false), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }

                Text(live.statusText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.pink.opacity(0.92))
                    .clipShape(Capsule())
                    .padding(8)
            }
        }
        .background(BiliMediaPlaceholder(style: .video, iconSize: 17))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .mediaShadow(.regular)
    }

    private var metadata: some View {
        HStack(spacing: 10) {
            Label(live.statusText, systemImage: "dot.radiowaves.left.and.right")
                .foregroundStyle(.pink)

            if let viewerText = live.viewerText {
                Text(viewerText)
            }

            if let areaName = live.areaName, !areaName.isEmpty {
                Text(areaName)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

private struct DynamicLiveRouteLink<Label: View>: View {
    let room: LiveRoom?
    @ViewBuilder let label: () -> Label
    @State private var selectedRoom: LiveRoom?

    var body: some View {
        Button {
            selectedRoom = room
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .disabled(room == nil)
        .opacity(room == nil ? 0.72 : 1)
        .navigationDestination(item: $selectedRoom) { room in
            LiveRoomDetailView(seedRoom: room)
        }
    }
}

actor DynamicFeedWarmCache {
    static let shared = DynamicFeedWarmCache()

    private let freshnessInterval: TimeInterval = 90
    private var cachedPage: DynamicFeedData?
    private var cachedAt: Date?
    private var warmTask: Task<DynamicFeedData, Error>?

    func page(api: BiliAPIClient) async throws -> DynamicFeedData {
        if let cachedPage = freshCachedPage() {
            return cachedPage
        }
        if let warmTask {
            return try await warmTask.value
        }

        let task = Task(priority: .utility) {
            try await api.fetchDynamicFeed()
        }
        warmTask = task
        do {
            let page = try await task.value
            store(page)
            warmTask = nil
            return page
        } catch {
            warmTask = nil
            throw error
        }
    }

    func prewarm(api: BiliAPIClient) async {
        guard freshCachedPage() == nil else { return }
        _ = try? await page(api: api)
    }

    func store(_ page: DynamicFeedData) {
        cachedPage = page
        cachedAt = Date()
    }

    func clear() {
        warmTask?.cancel()
        warmTask = nil
        cachedPage = nil
        cachedAt = nil
    }

    private func freshCachedPage() -> DynamicFeedData? {
        guard let cachedPage,
              let cachedAt,
              Date().timeIntervalSince(cachedAt) < freshnessInterval
        else { return nil }
        return cachedPage
    }
}

@MainActor
final class DynamicViewModel: ObservableObject {
    @Published var items: [DynamicFeedItem] = [] {
        didSet {
            itemsRevision &+= 1
        }
    }
    @Published private(set) var followedLiveRooms: [LiveRoom] = [] {
        didSet {
            followedLiveRoomsRevision &+= 1
        }
    }
    @Published var state: LoadingState = .idle
    @Published private(set) var itemsRevision = 0
    @Published private(set) var followedLiveRoomsRevision = 0

    private let api: BiliAPIClient
    private let libraryStore: LibraryStore
    private let sessionStore: SessionStore
    private var rawItems: [DynamicFeedItem] = []
    private var offset = ""
    private var hasMore = true
    private var filterCancellable: AnyCancellable?
    private var imagePrefetchTask: Task<Void, Never>?
    private var playbackPreloadTask: Task<Void, Never>?
    private var followedLiveTask: Task<Void, Never>?
    private let resourcePrefetchDebouncer = TaskDebouncer()

    var hasMoreItems: Bool {
        hasMore
    }

    init(api: BiliAPIClient, libraryStore: LibraryStore, sessionStore: SessionStore) {
        self.api = api
        self.libraryStore = libraryStore
        self.sessionStore = sessionStore
        filterCancellable = libraryStore.$blocksAdDynamics
            .combineLatest(libraryStore.$blocksGoodsDynamics)
            .combineLatest(libraryStore.$blockedDynamicKeywords)
            .removeDuplicates { lhs, rhs in
                lhs.0.0 == rhs.0.0
                    && lhs.0.1 == rhs.0.1
                    && lhs.1 == rhs.1
            }
            .dropFirst()
            .sink { [weak self] _ in
                self?.applyCurrentFilter()
            }
    }

    deinit {
        imagePrefetchTask?.cancel()
        playbackPreloadTask?.cancel()
        followedLiveTask?.cancel()
    }

    func loadInitial() async {
        guard items.isEmpty else { return }
        guard sessionStore.isLoggedIn else {
            prepareLoggedOutState()
            return
        }
        state = .loading
        offset = ""
        hasMore = true
        refreshFollowedLiveRooms()
        do {
            let page = try await DynamicFeedWarmCache.shared.page(api: api)
            apply(page: page, prefetchDelay: 0.08)
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func refresh() async {
        guard sessionStore.isLoggedIn else {
            prepareLoggedOutState()
            return
        }
        state = .loading
        offset = ""
        hasMore = true
        refreshFollowedLiveRooms()
        do {
            let page = try await api.fetchDynamicFeed()
            await DynamicFeedWarmCache.shared.store(page)
            apply(page: page, prefetchDelay: 0.08)
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadMoreIfNeeded(current item: DynamicFeedItem?) async {
        guard let item, items.last?.id == item.id else { return }
        await loadMore()
    }

    func loadMore() async {
        guard sessionStore.isLoggedIn else {
            prepareLoggedOutState()
            return
        }
        guard hasMore, !state.isLoading else { return }
        state = .loading
        do {
            let page = try await api.fetchDynamicFeed(offset: offset)
            let moreItems = displayable(page.items)
            appendUniqueRaw(moreItems)
            applyCurrentFilter()
            scheduleResourcePrefetch(for: moreItems, initialDelay: 0.75)
            offset = page.offset ?? offset
            hasMore = page.hasMore ?? false
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func prepareLoggedOutState() {
        followedLiveTask?.cancel()
        followedLiveTask = nil
        rawItems = []
        items = []
        followedLiveRooms = []
        offset = ""
        hasMore = false
        state = .idle
    }

    private func apply(page: DynamicFeedData, prefetchDelay: TimeInterval) {
        rawItems = displayable(page.items)
        applyCurrentFilter()
        scheduleResourcePrefetch(for: items, initialDelay: prefetchDelay)
        offset = page.offset ?? ""
        hasMore = page.hasMore ?? false
    }

    private func displayable(_ items: [DynamicFeedItem]?) -> [DynamicFeedItem] {
        (items ?? []).filter { item in
            item.author != nil
                || item.displayText?.isEmpty == false
                || item.archive != nil
                || !item.imageItems.isEmpty
                || item.original?.hasDisplayableContent == true
        }
    }

    private func applyCurrentFilter() {
        var filteredItems = rawItems
        if libraryStore.blocksAdDynamics {
            filteredItems = filteredItems.filter { !$0.containsDynamicAdPromotion }
        }
        if libraryStore.blocksGoodsDynamics {
            filteredItems = filteredItems.filter { !$0.containsGoodsPromotion }
        }
        let blockedKeywords = libraryStore.blockedDynamicKeywords
        if !blockedKeywords.isEmpty {
            filteredItems = filteredItems.filter { !$0.matchesBlockedDynamicKeywords(blockedKeywords) }
        }
        items = filteredItems
    }

    private func appendUniqueRaw(_ more: [DynamicFeedItem]) {
        let existing = Set(rawItems.map(\.id))
        rawItems.append(contentsOf: more.filter { !existing.contains($0.id) })
    }

    private func refreshFollowedLiveRooms() {
        followedLiveTask?.cancel()
        followedLiveTask = Task { [weak self, api] in
            do {
                let rooms = try await api.fetchFollowedLiveRooms(page: 1, pageSize: 20)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.followedLiveRooms = Array(rooms.prefix(12))
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.followedLiveRooms = []
                }
            }
        }
    }

    private func scheduleResourcePrefetch(for items: [DynamicFeedItem], initialDelay: TimeInterval) {
        let environment = PlaybackEnvironment.current
        let snapshotLimit = environment.shouldPreferConservativePlayback ? 5 : 8
        let snapshot = Array(items.prefix(snapshotLimit))
        let adaptiveDelay = environment.shouldPreferConservativePlayback ? initialDelay + 0.45 : initialDelay + 0.2
        let delayMilliseconds = max(Int64((adaptiveDelay * 1000).rounded()), 120)
        resourcePrefetchDebouncer.schedule(delay: .milliseconds(delayMilliseconds)) { [weak self] in
            guard let self else { return }
            self.scheduleImagePrefetch(for: snapshot, initialDelay: 0)
            guard !environment.shouldPreferConservativePlayback else { return }
            self.schedulePlaybackPreload(for: snapshot, initialDelay: 0.45)
        }
    }

    private func scheduleImagePrefetch(for items: [DynamicFeedItem], initialDelay: TimeInterval) {
        imagePrefetchTask?.cancel()
        let environment = PlaybackEnvironment.current
        let prefetchPlan = dynamicImagePrefetchPlan(for: items, environment: environment)

        guard !prefetchPlan.avatarSources.isEmpty || !prefetchPlan.imageSources.isEmpty || !prefetchPlan.coverSources.isEmpty else { return }
        let avatarPrefetchSources = prefetchPlan.avatarSources
        let imagePrefetchSources = prefetchPlan.imageSources
        let coverPrefetchSources = prefetchPlan.coverSources
        let imageTargetPixelSize = environment.shouldPreferConservativePlayback ? 320 : 420
        let coverTargetPixelSize = environment.shouldPreferConservativePlayback ? 360 : 480
        imagePrefetchTask = Task(priority: .utility) {
            if initialDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(initialDelay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            async let avatars: Void = RemoteImageCache.shared.prefetch(
                avatarPrefetchSources,
                targetPixelSize: 96,
                maximumConcurrentLoads: 1
            )
            async let images: Void = RemoteImageCache.shared.prefetch(
                imagePrefetchSources,
                targetPixelSize: imageTargetPixelSize,
                maximumConcurrentLoads: environment.shouldPreferConservativePlayback ? 1 : 2
            )
            async let covers: Void = RemoteImageCache.shared.prefetch(
                coverPrefetchSources,
                targetPixelSize: coverTargetPixelSize,
                maximumConcurrentLoads: 1
            )
            _ = await (avatars, images, covers)
        }
    }

    private func dynamicImagePrefetchPlan(
        for items: [DynamicFeedItem],
        environment: PlaybackEnvironment
    ) -> (avatarSources: [RemoteImageSource], imageSources: [RemoteImageSource], coverSources: [RemoteImageSource]) {
        var avatarSources = [RemoteImageSource]()
        var imageSources = [RemoteImageSource]()
        var coverSources = [RemoteImageSource]()
        var seenURLs = Set<String>()

        let itemLimit = environment.shouldPreferConservativePlayback ? 5 : 8
        let imageLimit = environment.shouldPreferConservativePlayback ? 2 : 3
        let imageTargetPixelSize = environment.shouldPreferConservativePlayback ? 320 : 420
        let coverTargetPixelSize = environment.shouldPreferConservativePlayback ? 360 : 480
        for item in items.prefix(itemLimit) {
            if let source = item.author?.face?.normalizedBiliURL(),
               let avatarURL = URL(string: source.biliAvatarThumbnailURL(size: 96)),
               seenURLs.insert(source).inserted {
                avatarSources.append(RemoteImageSource(url: avatarURL, fallbackURL: URL(string: source)))
            }

            for image in item.imageItems.prefix(imageLimit) {
                guard let source = image.normalizedURL,
                      let url = URL(string: source.biliImageThumbnailURL(maxSide: imageTargetPixelSize)),
                      seenURLs.insert(source).inserted
                else { continue }
                imageSources.append(RemoteImageSource(url: url, fallbackURL: URL(string: source)))
            }

            if let video = item.archive?.asVideoItem(author: item.author),
               let source = video.pic?.normalizedBiliURL(),
               let coverURL = URL(string: source.biliCoverThumbnailURL(width: coverTargetPixelSize, height: Int(Double(coverTargetPixelSize) * 9 / 16))),
               seenURLs.insert(source).inserted {
                coverSources.append(RemoteImageSource(url: coverURL, fallbackURL: URL(string: source)))
            }
        }

        return (avatarSources, imageSources, coverSources)
    }

    private func schedulePlaybackPreload(for items: [DynamicFeedItem], initialDelay: TimeInterval) {
        playbackPreloadTask?.cancel()
        guard !PlaybackEnvironment.current.shouldPreferConservativePlayback else {
            playbackPreloadTask = nil
            return
        }

        let videos = items
            .compactMap { $0.archive?.asVideoItem(author: $0.author) }
            .filter { !$0.bvid.isEmpty }
        let playbackAdaptationProfile = PlayerPerformanceStore.shared.playbackAdaptationProfile(
            isEnabled: libraryStore.isPlaybackAutoOptimizationEnabled
        )
        let candidateLimit = max(0, min(2, playbackAdaptationProfile.backgroundPreloadLimit))
        guard candidateLimit > 0 else {
            playbackPreloadTask = nil
            return
        }
        let candidates = Array(videos.prefix(candidateLimit))
        guard !candidates.isEmpty else {
            playbackPreloadTask = nil
            return
        }

        let preferredQuality = libraryStore.preferredVideoQuality
        let cdnPreference = libraryStore.effectivePlaybackCDNPreference
        playbackPreloadTask = Task(priority: .background) { [api, cdnPreference] in
            if initialDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(initialDelay * 1_000_000_000))
            }
            await VideoPreloadCenter.shared.updatePlaybackPreferences(
                preferredQuality: preferredQuality,
                cdnPreference: cdnPreference,
                playbackAdaptationProfile: playbackAdaptationProfile
            )
            for (index, video) in candidates.enumerated() {
                guard !Task.isCancelled else { return }
                await VideoPreloadCenter.shared.preloadPlayInfo(
                    video,
                    api: api,
                    preferredQuality: preferredQuality,
                    cdnPreference: cdnPreference,
                    priority: .background,
                    warmsMedia: true,
                    mediaWarmupDelay: index == 0 ? 0.45 : 0.9,
                    playbackAdaptationProfile: playbackAdaptationProfile
                )
                if index < candidates.count - 1 {
                    try? await Task.sleep(nanoseconds: 650_000_000)
                }
            }
        }
    }
}

@MainActor
final class DynamicViewModelHolder: ObservableObject {
    @Published var viewModel: DynamicViewModel?
    private var cancellable: AnyCancellable?
    private var snapshotRefreshTask: Task<Void, Never>?
    private var lastSnapshot: DynamicRenderSnapshot?

    func configure(api: BiliAPIClient, libraryStore: LibraryStore, sessionStore: SessionStore) {
        if viewModel == nil {
            let viewModel = DynamicViewModel(api: api, libraryStore: libraryStore, sessionStore: sessionStore)
            self.viewModel = viewModel
            lastSnapshot = DynamicRenderSnapshot(viewModel)
            cancellable = viewModel.objectWillChange.sink { [weak self] _ in
                self?.scheduleSnapshotRefresh(for: viewModel)
            }
        }
    }

    private func scheduleSnapshotRefresh(for viewModel: DynamicViewModel) {
        guard snapshotRefreshTask == nil else { return }
        snapshotRefreshTask = Task { @MainActor [weak self, weak viewModel] in
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard let self, let viewModel, !Task.isCancelled else { return }
            self.snapshotRefreshTask = nil
            let snapshot = DynamicRenderSnapshot(viewModel)
            guard snapshot != self.lastSnapshot else { return }
            self.lastSnapshot = snapshot
            self.objectWillChange.send()
        }
    }

    deinit {
        snapshotRefreshTask?.cancel()
    }
}

private struct DynamicRenderSnapshot: Equatable {
    let state: LoadingState
    let hasMoreItems: Bool
    let followedLiveRoomsRevision: Int
    let itemCount: Int
    let firstItemID: String?
    let lastItemID: String?
    let itemsRevision: Int

    init(_ viewModel: DynamicViewModel) {
        state = viewModel.state
        hasMoreItems = viewModel.hasMoreItems
        followedLiveRoomsRevision = viewModel.followedLiveRoomsRevision
        itemCount = viewModel.items.count
        firstItemID = viewModel.items.first?.id
        lastItemID = viewModel.items.last?.id
        itemsRevision = viewModel.itemsRevision
    }
}

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

