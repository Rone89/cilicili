import Foundation
import SwiftUI
import UIKit

private extension Color {
    static let videoDetailSurface = Color(UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.115, green: 0.115, blue: 0.128, alpha: 1)
            : .systemBackground
    })

    static let videoDetailSecondarySurface = Color(UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1)
            : .secondarySystemGroupedBackground
    })
}

enum CommentSectionStyle: Equatable {
    case grouped
    case plain

    var horizontalPadding: CGFloat {
        switch self {
        case .grouped:
            return 11
        case .plain:
            return 13
        }
    }

    var showsReplyPreviewContainer: Bool {
        true
    }

    var usesGroupedFooter: Bool {
        self == .grouped
    }
}

struct PortraitCommentsSheet: View {
    @ObservedObject var store: VideoDetailCommentsRenderStore
    let threadStore: VideoDetailCommentThreadRenderStore
    let maximumHeight: CGFloat
    let beginInitialCommentsLoad: () -> Void
    let selectCommentSort: (CommentSort) async -> Void
    let retryComments: () async -> Void
    let loadMoreCommentsIfNeeded: (Comment) async -> Void
    let loadMoreComments: () async -> Void
    let loadReplies: (Comment) async -> Void
    let reloadReplies: (Comment) async -> Void
    let loadMoreReplies: (Comment) async -> Void
    let loadDialog: (Comment, Comment) async -> Void
    let reloadDialog: (Comment, Comment) async -> Void
    @State private var selectedDetent: PresentationDetent
    @State private var replySheetComment: Comment?

    init(
        store: VideoDetailCommentsRenderStore,
        threadStore: VideoDetailCommentThreadRenderStore,
        maximumHeight: CGFloat,
        beginInitialCommentsLoad: @escaping () -> Void,
        selectCommentSort: @escaping (CommentSort) async -> Void,
        retryComments: @escaping () async -> Void,
        loadMoreCommentsIfNeeded: @escaping (Comment) async -> Void,
        loadMoreComments: @escaping () async -> Void,
        loadReplies: @escaping (Comment) async -> Void,
        reloadReplies: @escaping (Comment) async -> Void,
        loadMoreReplies: @escaping (Comment) async -> Void,
        loadDialog: @escaping (Comment, Comment) async -> Void,
        reloadDialog: @escaping (Comment, Comment) async -> Void
    ) {
        self.store = store
        self.threadStore = threadStore
        self.maximumHeight = maximumHeight
        self.beginInitialCommentsLoad = beginInitialCommentsLoad
        self.selectCommentSort = selectCommentSort
        self.retryComments = retryComments
        self.loadMoreCommentsIfNeeded = loadMoreCommentsIfNeeded
        self.loadMoreComments = loadMoreComments
        self.loadReplies = loadReplies
        self.reloadReplies = reloadReplies
        self.loadMoreReplies = loadMoreReplies
        self.loadDialog = loadDialog
        self.reloadDialog = reloadDialog
        _selectedDetent = State(initialValue: .height(maximumHeight))
    }

    var body: some View {
        NavigationStack {
            List {
                sortPickerRow
                commentsListContent
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(.clear)
            .hiddenInlineNavigationTitle()
            .nativeTopScrollEdgeEffect()
            .refreshable {
                await retryComments()
            }
            .task {
                beginInitialCommentsLoad()
            }
        }
        .presentationDetents([.height(maximumHeight)], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .sheet(item: $replySheetComment) { comment in
            CommentRepliesSheet(
                rootComment: comment,
                store: threadStore,
                loadReplies: loadReplies,
                reloadReplies: reloadReplies,
                loadMoreReplies: loadMoreReplies,
                loadDialog: loadDialog,
                reloadDialog: reloadDialog
            )
        }
    }

    private var sortPickerRow: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(CommentSort.allCases) { sort in
                    Button {
                        Task { await selectCommentSort(sort) }
                    } label: {
                        Text(sort.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(store.selectedSort == sort ? .primary : .secondary)
                    .commentPlayerGlassCapsule()
                    .opacity(store.selectedSort == sort ? 1 : 0.72)
                    .accessibilityLabel(sort.title)
                    .accessibilityValue(store.selectedSort == sort ? "已选中" : "")
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 8, trailing: 14))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var commentsListContent: some View {
        if store.comments.isEmpty && (store.state.isLoading || store.state == .idle) {
            loadingRow
        } else if store.comments.isEmpty, case .failed(let message) = store.state {
            errorRow(message: message)
        } else if store.shouldShowEmptyCommentsState {
            emptyRow
        } else if store.shouldShowCommentReloadPrompt {
            errorRow(message: "评论暂时没有返回内容")
        } else {
            let commentItems = store.commentItems
            let loadMoreTriggerCommentID = commentItems.last?.id
            ForEach(commentItems) { item in
                CommentRow(
                    item: item,
                    style: .plain,
                    showReplies: {
                        replySheetComment = item.comment
                    }
                )
                .equatable()
                .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
                .listRowBackground(Color.clear)
                .commentLoadMoreTask(if: item.id == loadMoreTriggerCommentID, id: item.id) {
                    await loadMoreCommentsIfNeeded(item.comment)
                }
                .listRowSeparator(.hidden)

                Divider()
                    .padding(.leading, 58)
                    .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
                    .listRowBackground(Color.clear)
            }

            footerRow
        }
    }

    private var loadingRow: some View {
        CommentLoadingSkeletonList(count: 4)
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func errorRow(message: String) -> some View {
        CommentErrorView(message: message) {
            Task { await retryComments() }
        }
        .padding(.vertical, 18)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var emptyRow: some View {
        EmptyStateView(title: "暂无评论", systemImage: "bubble.left", message: "这里还没有可展示的评论。")
            .padding(.vertical, 28)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var footerRow: some View {
        if store.state.isLoading {
            CommentLoadingSkeletonRow()
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else if case .failed(let message) = store.state {
            errorRow(message: message)
        } else if store.hasMoreComments {
            Button {
                Task { await loadMoreComments() }
            } label: {
                Label("加载更多评论", systemImage: "arrow.down.circle")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .commentPlayerGlassCapsule()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else if !store.comments.isEmpty {
            Text("没有更多评论了")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }

}

struct CommentsSectionView: View {
    @ObservedObject var store: VideoDetailCommentsRenderStore
    let style: CommentSectionStyle
    var maxVisibleComments: Int?
    var autoLoads = true
    var showAllComments: (() -> Void)?
    let beginInitialCommentsLoad: () -> Void
    let selectCommentSort: (CommentSort) async -> Void
    let retryComments: () async -> Void
    let loadMoreCommentsIfNeeded: (Comment) async -> Void
    let loadMoreComments: () async -> Void
    let showReplies: (Comment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            commentsHeader
            commentsContent
        }
        .padding(.vertical, 9)
        .background(style == .grouped ? Color.videoDetailSurface : Color.clear)
        .task(id: commentsLoadTaskID) {
            guard autoLoads else { return }
            beginInitialCommentsLoad()
        }
    }

    private var commentsLoadTaskID: String {
        "\(store.detail?.aid ?? 0)-\(autoLoads)"
    }

    private var commentsHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("评论")
                .font(.headline)

            if let count = store.replyCountText {
                Text(count)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                ForEach(CommentSort.allCases) { sort in
                    Button {
                        Task { await selectCommentSort(sort) }
                    } label: {
                        Text(sort.title)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(store.selectedSort == sort ? Color.pink.opacity(0.14) : Color.clear)
                            .foregroundStyle(store.selectedSort == sort ? .pink : .secondary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, style.horizontalPadding)
    }

    @ViewBuilder
    private var commentsContent: some View {
        if store.comments.isEmpty && shouldShowLoadingPlaceholder {
            CommentsSkeletonContent(rowCount: 2, horizontalPadding: style.horizontalPadding)
        } else if store.comments.isEmpty, case .failed(let message) = store.state {
            CommentErrorView(message: message) {
                Task { await retryComments() }
            }
            .padding(.horizontal, style.horizontalPadding)
        } else if store.shouldShowEmptyCommentsState {
            EmptyStateView(title: "暂无评论", systemImage: "bubble.left", message: "评论加载后会显示在这里。")
                .padding(.horizontal, style.horizontalPadding)
        } else if store.shouldShowCommentReloadPrompt {
            CommentErrorView(message: "评论暂时没有返回内容") {
                Task { await retryComments() }
            }
            .padding(.horizontal, style.horizontalPadding)
        } else if store.comments.isEmpty {
            Color.clear
                .frame(height: 1)
        } else {
            let commentItems = visibleCommentItems
            let loadMoreTriggerCommentID = maxVisibleComments == nil ? commentItems.last?.id : nil
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(commentItems) { item in
                    CommentRow(
                        item: item,
                        style: style,
                        showReplies: {
                            showReplies(item.comment)
                        }
                    )
                    .equatable()
                    .padding(.horizontal, style.horizontalPadding)
                    .commentLoadMoreTask(if: item.id == loadMoreTriggerCommentID, id: item.id) {
                        await loadMoreCommentsIfNeeded(item.comment)
                    }

                    Divider()
                        .padding(.leading, 56)
                }

                Group {
                    if maxVisibleComments != nil {
                        commentPreviewFooter
                    } else {
                        commentFooter
                    }
                }
                .padding(.horizontal, style.horizontalPadding)
                .padding(.top, 8)
            }
        }
    }

    private var shouldShowLoadingPlaceholder: Bool {
        store.state.isLoading || (autoLoads && store.state == .idle)
    }

    private var visibleCommentItems: [VideoDetailCommentDisplayItem] {
        guard let maxVisibleComments else { return store.commentItems }
        return Array(store.commentItems.prefix(maxVisibleComments))
    }

    @ViewBuilder
    private var commentPreviewFooter: some View {
        if store.state.isLoading {
            InlineLoadingStateView(title: "加载评论")
        } else {
            Button {
                showAllComments?()
            } label: {
                Label("查看全部评论", systemImage: "bubble.left.and.bubble.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .commentPlayerGlassRoundedRectangle()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private var commentFooter: some View {
        if store.state.isLoading {
            InlineLoadingStateView(title: "加载更多评论")
        } else if case .failed(let message) = store.state {
            CommentErrorView(message: message) {
                Task { await retryComments() }
            }
        } else if store.hasMoreComments {
            Button {
                Task { await loadMoreComments() }
            } label: {
                if style.usesGroupedFooter {
                    Label("加载更多评论", systemImage: "arrow.down.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .commentPlayerGlassRoundedRectangle()
                } else {
                    Label("加载更多评论", systemImage: "arrow.down.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .commentPlayerGlassCapsule()
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
        } else {
            Text("没有更多评论了")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
    }

}

private extension View {
    @ViewBuilder
    func commentLoadMoreTask(
        if shouldAttachTask: Bool,
        id: Int,
        action: @escaping () async -> Void
    ) -> some View {
        if shouldAttachTask {
            task(id: id) {
                await action()
            }
        } else {
            self
        }
    }
}

struct InitialCommentsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text("评论")
                    .font(.headline)

                Spacer()

                HStack(spacing: 4) {
                    Text("最热")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.pink.opacity(0.14))
                        .foregroundStyle(.pink)
                        .clipShape(Capsule())
                    Text("最新")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, CommentSectionStyle.plain.horizontalPadding)

            CommentsSkeletonContent(rowCount: 2, horizontalPadding: CommentSectionStyle.plain.horizontalPadding)
        }
        .padding(.vertical, 10)
        .allowsHitTesting(false)
    }
}

private struct CommentsSkeletonContent: View {
    let rowCount: Int
    let horizontalPadding: CGFloat

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<rowCount, id: \.self) { _ in
                CommentSkeletonRow()
                    .padding(.horizontal, horizontalPadding)

                Divider()
                    .padding(.leading, 58)
            }
        }
        .redacted(reason: .placeholder)
        .overlay(alignment: .center) {
            NativeLoadingIndicator()
                .controlSize(.regular)
                .tint(.secondary)
                .accessibilityLabel("正在加载评论")
        }
    }
}

private struct CommentSkeletonRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.videoDetailSecondarySurface)
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.videoDetailSecondarySurface)
                        .frame(width: 132, height: 16)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.videoDetailSecondarySurface)
                        .frame(width: 82, height: 14)
                    Spacer(minLength: 8)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.videoDetailSecondarySurface)
                        .frame(width: 52, height: 14)
                }

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.videoDetailSecondarySurface)
                    .frame(height: 18)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.videoDetailSecondarySurface)
                    .frame(width: 230, height: 18)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.videoDetailSecondarySurface)
                    .frame(width: 136, height: 16)
            }
        }
        .padding(.vertical, 9)
    }
}

private struct CommentRow: View, Equatable {
    let item: VideoDetailCommentDisplayItem
    let style: CommentSectionStyle
    let showReplies: () -> Void

    private var comment: Comment { item.comment }
    private var display: VideoDetailCommentDisplayModel { item.display }

    init(
        item: VideoDetailCommentDisplayItem,
        style: CommentSectionStyle,
        showReplies: @escaping () -> Void
    ) {
        self.item = item
        self.style = style
        self.showReplies = showReplies
    }

    static func == (lhs: CommentRow, rhs: CommentRow) -> Bool {
        lhs.item == rhs.item && lhs.style == rhs.style
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            avatar

            VStack(alignment: .leading, spacing: 5) {
                header

                BiliEmoteText(content: comment.content, font: .subheadline, textColor: .primary, emoteSize: 21)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)

                CommentImageButton(
                    images: display.pictures,
                    transitionScope: comment.id.description
                )

                if display.visibleReplyCount > 0 {
                    Button(action: showReplies) {
                        CommentReplyPreviewContainer(
                            replyCount: display.visibleReplyCount,
                            showsPreview: !display.replyPreviews.isEmpty
                        ) {
                            ForEach(display.replyPreviews) { reply in
                                ReplyPreviewRow(reply: reply)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!style.showsReplyPreviewContainer)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var avatar: some View {
        AvatarRemoteImage(urlString: display.avatarURLString, pixelSize: 96) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
        }
        .frame(width: 38, height: 38)
        .clipShape(Circle())
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
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

            CommentMetricBadge(
                text: display.likeText,
                systemImage: display.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
                isHighlighted: display.isLiked
            )
        }
    }
}

private typealias CommentRowDisplayModel = VideoDetailCommentDisplayModel

private struct ReplyPreviewRow: View {
    let reply: Comment

    var body: some View {
        BiliEmoteText(
            content: reply.content,
            font: .caption,
            textColor: .primary,
            emoteSize: 18,
            leadingName: reply.member?.uname ?? "Unknown",
            leadingNameColor: .secondary,
            showsLinkButtons: false
        )
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CommentReplyPreviewContainer<Content: View>: View {
    let replyCount: Int
    let showsPreview: Bool
    let content: Content

    init(replyCount: Int, showsPreview: Bool, @ViewBuilder content: () -> Content) {
        self.replyCount = replyCount
        self.showsPreview = showsPreview
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsPreview {
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.pink.opacity(0.42))
                        .frame(width: 3)
                        .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 6) {
                        content
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Label("\(replyCount) 条回复", systemImage: "bubble.left.and.bubble.right")
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.pink)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct CommentImageButton: View {
    private let visibleImages: [DynamicImageItem]

    init(images: [DynamicImageItem], transitionScope: String) {
        self.visibleImages = images.filter { $0.normalizedURL != nil }
        _ = transitionScope
    }

    var body: some View {
        if !visibleImages.isEmpty {
            CompactDynamicImageMosaicGrid(
                images: visibleImages,
                accessibilityName: "图片",
                placeholderFill: Color.videoDetailSecondarySurface
            )
            .padding(.top, 2)
        }
    }
}

private enum CommentTextBuilder {
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

private struct CommentErrorView: View {
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
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(.pink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Color.videoDetailSecondarySurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.separator).opacity(0.08), lineWidth: 0.6)
        }
    }
}

struct CommentRepliesSheet: View {
    let rootComment: Comment
    let store: VideoDetailCommentThreadRenderStore
    let loadReplies: (Comment) async -> Void
    let reloadReplies: (Comment) async -> Void
    let loadMoreReplies: (Comment) async -> Void
    let loadDialog: (Comment, Comment) async -> Void
    let reloadDialog: (Comment, Comment) async -> Void
    @State private var dialogReply: Comment?

    init(
        rootComment: Comment,
        store: VideoDetailCommentThreadRenderStore,
        loadReplies: @escaping (Comment) async -> Void,
        reloadReplies: @escaping (Comment) async -> Void,
        loadMoreReplies: @escaping (Comment) async -> Void,
        loadDialog: @escaping (Comment, Comment) async -> Void,
        reloadDialog: @escaping (Comment, Comment) async -> Void
    ) {
        self.rootComment = rootComment
        self.store = store
        self.loadReplies = loadReplies
        self.reloadReplies = reloadReplies
        self.loadMoreReplies = loadMoreReplies
        self.loadDialog = loadDialog
        self.reloadDialog = reloadDialog
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CommentReplyRootView(
                        comment: rootComment
                    )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                    Divider()

                    CommentRepliesContent(
                        rootComment: rootComment,
                        store: store,
                        reloadReplies: reloadReplies,
                        loadMoreReplies: loadMoreReplies
                    ) { reply in
                            dialogReply = reply
                    }
                }
            }
            .hiddenInlineNavigationTitle()
            .nativeTopScrollEdgeEffect()
            .task {
                await loadReplies(rootComment)
            }
        }
        .presentationDetents([.fraction(0.7)])
        .presentationDragIndicator(.visible)
        .sheet(item: $dialogReply) { reply in
            CommentDialogSheet(
                rootComment: rootComment,
                focusReply: reply,
                store: store,
                loadDialog: loadDialog,
                reloadDialog: reloadDialog
            )
        }
    }
}

private struct CommentRepliesContent: View {
    let rootComment: Comment
    @ObservedObject var store: VideoDetailCommentThreadRenderStore
    let reloadReplies: (Comment) async -> Void
    let loadMoreReplies: (Comment) async -> Void
    let showDialog: (Comment) -> Void

    @ViewBuilder
    var body: some View {
        let snapshot = store.repliesSnapshot(for: rootComment)

        if snapshot.replies.isEmpty && snapshot.state.isLoading {
            CommentLoadingSkeletonList(count: 3)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        } else if snapshot.replies.isEmpty, case .failed(let message) = snapshot.state {
            CommentErrorView(message: message) {
                Task { await reloadReplies(rootComment) }
            }
            .padding(16)
        } else if snapshot.replies.isEmpty {
            EmptyStateView(title: "暂无回复", systemImage: "bubble.left.and.bubble.right", message: "这条评论还没有可展示的回复。")
                .padding(16)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(snapshot.replyDisplays) { replyDisplay in
                    CommentReplyDetailRow(
                        item: replyDisplay,
                        showDialog: replyDisplay.canShowDialog ? {
                            showDialog(replyDisplay.reply)
                        } : nil
                    )
                        .padding(.horizontal, 16)
                    Divider()
                        .padding(.leading, 62)
                }

                repliesFooter(snapshot: snapshot)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
    }

    @ViewBuilder
    private func repliesFooter(snapshot: VideoDetailCommentThreadRepliesSnapshot) -> some View {
        if snapshot.hasLoadedReplies, snapshot.state.isLoading {
            InlineLoadingStateView(title: "加载更多回复")
        } else if case .failed(let message) = snapshot.state {
            CommentErrorView(message: message) {
                Task { await loadMoreReplies(rootComment) }
            }
        } else if snapshot.hasMoreReplies {
            Button {
                Task { await loadMoreReplies(rootComment) }
            } label: {
                Label("查看更多回复", systemImage: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.pink)
        }
    }
}

private struct CommentReplyRootView: View {
    let comment: Comment
    private let display: CommentRowDisplayModel

    init(comment: Comment) {
        self.comment = comment
        self.display = CommentRowDisplayModel(comment: comment)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CommentAvatar(urlString: display.avatarURLString, size: 40)

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
                }

                BiliEmoteText(content: comment.content, font: .subheadline, textColor: .primary, emoteSize: 22)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)

                CommentImageButton(
                    images: display.pictures,
                    transitionScope: comment.id.description
                )
            }
        }
    }
}

private struct CommentReplyDetailRow: View {
    let item: VideoDetailCommentReplyDisplayItem
    let showDialog: (() -> Void)?

    private var reply: Comment { item.reply }
    private var display: VideoDetailCommentDisplayModel { item.display }

    init(item: VideoDetailCommentReplyDisplayItem, showDialog: (() -> Void)?) {
        self.item = item
        self.showDialog = showDialog
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CommentAvatar(urlString: display.avatarURLString, size: 36)

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

                    Spacer(minLength: 8)

                    CommentMetricBadge(
                        text: display.likeText,
                        systemImage: display.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
                        isHighlighted: display.isLiked
                    )
                }

                BiliEmoteText(content: reply.content, font: .subheadline, textColor: .primary, emoteSize: 22)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)

                CommentImageButton(
                    images: display.pictures,
                    transitionScope: reply.id.description
                )

                if let showDialog {
                    Button(action: showDialog) {
                        Label("查看对话", systemImage: "text.bubble")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 9)
                            .frame(height: 26)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.pink)
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 9)
    }
}

private struct CommentDialogSheet: View {
    let rootComment: Comment
    let focusReply: Comment
    let store: VideoDetailCommentThreadRenderStore
    let loadDialog: (Comment, Comment) async -> Void
    let reloadDialog: (Comment, Comment) async -> Void

    init(
        rootComment: Comment,
        focusReply: Comment,
        store: VideoDetailCommentThreadRenderStore,
        loadDialog: @escaping (Comment, Comment) async -> Void,
        reloadDialog: @escaping (Comment, Comment) async -> Void
    ) {
        self.rootComment = rootComment
        self.focusReply = focusReply
        self.store = store
        self.loadDialog = loadDialog
        self.reloadDialog = reloadDialog
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CommentReplyRootView(
                        comment: rootComment
                    )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                    Divider()

                    CommentDialogContent(
                        rootComment: rootComment,
                        focusReply: focusReply,
                        store: store,
                        reloadDialog: reloadDialog
                    )
                }
            }
            .hiddenInlineNavigationTitle()
            .nativeTopScrollEdgeEffect()
            .task {
                await loadDialog(rootComment, focusReply)
            }
        }
        .presentationDetents([.fraction(0.7)])
        .presentationDragIndicator(.visible)
    }
}

private struct CommentDialogContent: View {
    let rootComment: Comment
    let focusReply: Comment
    @ObservedObject var store: VideoDetailCommentThreadRenderStore
    let reloadDialog: (Comment, Comment) async -> Void

    @ViewBuilder
    var body: some View {
        let snapshot = store.dialogSnapshot(for: rootComment, reply: focusReply)

        if snapshot.items.isEmpty && snapshot.state.isLoading {
            CommentLoadingSkeletonList(count: 3)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        } else if snapshot.items.isEmpty, case .failed(let message) = snapshot.state {
            CommentErrorView(message: message) {
                Task { await reloadDialog(rootComment, focusReply) }
            }
            .padding(16)
        } else if snapshot.items.isEmpty {
            EmptyStateView(title: "暂无对话", systemImage: "text.bubble", message: "暂时没有找到这条回复的上下文。")
                .padding(16)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(snapshot.items) { item in
                    CommentDialogRow(
                        item: item,
                        isFocused: item.id == focusReply.id
                    )
                        .padding(.horizontal, 16)
                    Divider()
                        .padding(.leading, 66)
                }

                if case .failed(let message) = snapshot.state {
                    CommentErrorView(message: message) {
                        Task { await reloadDialog(rootComment, focusReply) }
                    }
                    .padding(16)
                }
            }
        }
    }
}

private struct CommentDialogRow: View {
    let item: VideoDetailCommentDialogDisplayItem
    let isFocused: Bool

    private var reply: Comment { item.reply }
    private var display: VideoDetailCommentDisplayModel { item.display }

    init(item: VideoDetailCommentDialogDisplayItem, isFocused: Bool) {
        self.item = item
        self.isFocused = isFocused
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CommentAvatar(urlString: display.avatarURLString, size: 36)

            VStack(alignment: .leading, spacing: 11) {
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

                    CommentMetricBadge(
                        text: display.likeText,
                        systemImage: display.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
                        isHighlighted: display.isLiked
                    )
                }

                BiliEmoteText(content: reply.content, font: .subheadline, textColor: .primary, emoteSize: 22)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                CommentImageButton(
                    images: display.pictures,
                    transitionScope: reply.id.description
                )
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, isFocused ? 10 : 0)
        .background(isFocused ? Color.pink.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct CommentAvatar: View {
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

private struct CommentMetricBadge: View {
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
            .frame(height: 24)
    }
}

private extension View {
    @ViewBuilder
    func commentPlayerGlassCapsule(showsShadow: Bool = true) -> some View {
        let glass = biliPlayerClearGlass(interactive: false, in: Capsule())
        if showsShadow {
            glass.shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
        } else {
            glass
        }
    }

    @ViewBuilder
    func commentPlayerGlassRoundedRectangle(cornerRadius: CGFloat = 12, showsShadow: Bool = true) -> some View {
        let glass = biliPlayerClearGlass(
            interactive: false,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        if showsShadow {
            glass.shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 3)
        } else {
            glass
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
