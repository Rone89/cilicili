import SwiftUI
import Combine

struct DynamicView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    @StateObject private var holder = DynamicViewModelHolder()

    var body: some View {
        Group {
            if let viewModel = holder.viewModel {
                content(viewModel)
            } else {
                ProgressView()
                    .task {
                        holder.configure(api: dependencies.api, libraryStore: libraryStore)
                    }
            }
        }
        .navigationTitle("动态")
        .navigationBarTitleDisplayMode(.large)
        .nativeTopNavigationChrome()
    }

    @ViewBuilder
    private func content(_ viewModel: DynamicViewModel) -> some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if viewModel.items.isEmpty && viewModel.state.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在加载动态")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 120)
                } else if viewModel.items.isEmpty {
                    EmptyStateView(
                        title: "暂无动态",
                        systemImage: "sparkles",
                        message: "登录后会显示你关注 UP 的动态。"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 110)
                } else {
                    ForEach(viewModel.items) { item in
                        DynamicFeedCard(item: item, api: dependencies.api)
                            .task {
                                await viewModel.loadMoreIfNeeded(current: item)
                            }
                    }

                    dynamicFooter(viewModel)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .nativeTopScrollEdgeEffect()
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.loadInitial()
        }
        .overlay {
            if case .failed(let message) = viewModel.state, viewModel.items.isEmpty {
                ErrorStateView(title: "动态加载失败", message: message) {
                    Task { await viewModel.refresh() }
                }
                .background(.background.opacity(0.96))
            }
        }
    }

    @ViewBuilder
    private func dynamicFooter(_ viewModel: DynamicViewModel) -> some View {
        if viewModel.state.isLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("加载更多动态")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        } else if viewModel.hasMoreItems {
            Button {
                Task { await viewModel.loadMore() }
            } label: {
                Label("加载更多", systemImage: "arrow.down.circle")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
            Text("没有更多动态了")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
    }
}

private struct DynamicFeedCard: View {
    let item: DynamicFeedItem
    let api: BiliAPIClient
    @State private var imageSelection: DynamicImageSelection?
    @State private var commentsTarget: DynamicFeedItem?
    @State private var isTextExpanded = false
    @State private var isLiked: Bool
    @State private var likeCount: Int

    init(item: DynamicFeedItem, api: BiliAPIClient) {
        self.item = item
        self.api = api
        _isLiked = State(initialValue: item.isLiked)
        _likeCount = State(initialValue: item.likeCount ?? 0)
    }

    private var video: VideoItem? {
        item.archive?.asVideoItem(author: item.author)
    }

    private var live: DynamicLive? {
        item.live
    }

    private var liveRoom: LiveRoom? {
        live?.asLiveRoom(author: item.author)
    }

    private var authorOwner: VideoOwner? {
        item.author?.owner
    }

    private var imageItems: [DynamicImageItem] {
        item.imageItems.filter { $0.normalizedURL != nil }
    }

    private var textSegments: [DynamicTextSegment] {
        item.textSegments
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            authorHeader

            if let text = DynamicTextSegment.displayText(from: textSegments), !text.isEmpty {
                dynamicText(segments: textSegments, displayText: text)
            }

            if let video {
                VideoRouteLink(video) {
                    DynamicArchivePreview(video: video)
                }
            }

            if let live {
                DynamicLiveRouteLink(room: liveRoom) {
                    DynamicLivePreview(live: live)
                }
            }

            if !imageItems.isEmpty {
                DynamicImageGrid(images: imageItems) { index in
                    imageSelection = DynamicImageSelection(index: index)
                }
            }

            if let original = item.original {
                DynamicOriginalPreview(item: original)
            } else if item.isForward {
                DynamicForwardUnavailableView()
            }

            actionBar
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(.separator).opacity(0.10), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .fullScreenCover(item: $imageSelection) { selection in
            DynamicImageViewer(images: imageItems, initialIndex: selection.index)
        }
        .sheet(item: $commentsTarget) { target in
            DynamicCommentsSheet(item: target, api: api)
        }
    }

    private var authorHeader: some View {
        HStack(spacing: 10) {
            if let authorOwner, authorOwner.mid > 0 {
                NavigationLink {
                    UploaderView(owner: authorOwner)
                } label: {
                    authorIdentity
                }
                .buttonStyle(.plain)
            } else {
                authorIdentity
            }

            Spacer(minLength: 0)
        }
    }

    private var authorIdentity: some View {
        HStack(spacing: 10) {
            CachedRemoteImage(url: item.author?.face.flatMap { URL(string: $0.biliAvatarThumbnailURL(size: 96)) }) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(item.author?.name ?? "Unknown")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(publishTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private var publishTime: String {
        if let timestamp = item.author?.pubTS, timestamp > 0 {
            return BiliFormatters.relativeTime(timestamp)
        }
        return item.author?.pubTime ?? ""
    }

    @ViewBuilder
    private func dynamicText(segments: [DynamicTextSegment], displayText: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            DynamicRichTextView(
                segments: segments,
                font: .subheadline,
                textColor: .primary,
                emoteSize: 22,
                maxLines: isTextExpanded ? nil : 6
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            if shouldShowExpandButton(for: displayText) {
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
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
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.top, 2)

            HStack(spacing: 0) {
                DynamicActionButton(
                    title: statTitle(count: item.repostCount, fallback: "转发"),
                    systemImage: "arrowshape.turn.up.right",
                    isSelected: false
                ) {}

                DynamicActionButton(
                    title: commentTitle,
                    systemImage: "bubble.left",
                    isSelected: false
                ) {
                    commentsTarget = item
                }

                DynamicActionButton(
                    title: statTitle(count: likeCount, fallback: "点赞"),
                    systemImage: isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
                    isSelected: isLiked
                ) {
                    toggleLocalLike()
                }
            }
        }
        .padding(.top, 2)
    }

    private func shouldShowExpandButton(for text: String) -> Bool {
        text.count > 120 || text.filter(\.isNewline).count >= 4
    }

    private func statTitle(count: Int?, fallback: String) -> String {
        guard let count, count > 0 else { return fallback }
        return BiliFormatters.compactCount(count)
    }

    private var commentTitle: String {
        statTitle(count: item.replyCount, fallback: "评论")
    }

    private func toggleLocalLike() {
        withAnimation(.snappy(duration: 0.2)) {
            isLiked.toggle()
            likeCount = max(0, likeCount + (isLiked ? 1 : -1))
        }
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

private struct DynamicRichTextView: View {
    let segments: [DynamicTextSegment]
    let font: Font
    let textColor: Color
    let emoteSize: CGFloat
    let maxLines: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DynamicAttributedTextLabel(
                input: DynamicAttributedTextInput(
                    segments: textAndEmojiSegments,
                    baseFont: resolvedUIFont,
                    textColor: UIColor(textColor),
                    emoteSize: emoteSize,
                    maxLines: maxLines
                )
            )

            if !linkURLs.isEmpty {
                HStack(spacing: 6) {
                    ForEach(linkURLs.prefix(3), id: \.self) { url in
                        Link(destination: url) {
                            Label("查看链接", systemImage: "link")
                                .font(.caption.weight(.semibold))
                                .labelStyle(.titleAndIcon)
                                .padding(.horizontal, 9)
                                .frame(height: 24)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(.pink)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var textAndEmojiSegments: [DynamicTextSegment] {
        let filtered = segments.filter { segment in
            if case .link = segment {
                return false
            }
            return true
        }
        return filtered.isEmpty ? [.text(" ")] : filtered
    }

    private var linkURLs: [URL] {
        segments.compactMap { segment in
            guard case .link(_, let rawURL) = segment else { return nil }
            return URL(string: rawURL)
        }
    }

    private var resolvedUIFont: UIFont {
        let textStyle: UIFont.TextStyle = emoteSize <= 20 ? .footnote : .subheadline
        return UIFont.preferredFont(forTextStyle: textStyle)
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
            && lhs.baseFont.pointSize == rhs.baseFont.pointSize
            && lhs.textColor == rhs.textColor
            && lhs.emoteSize == rhs.emoteSize
            && lhs.maxLines == rhs.maxLines
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
            case .link:
                break
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
        style.lineBreakMode = maxLines == nil ? .byCharWrapping : .byTruncatingTail
        return style
    }

    private func attributedText(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: baseFont,
                .foregroundColor: textColor
            ]
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

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.backgroundColor = .clear
        label.adjustsFontForContentSizeCategory = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.numberOfLines = input.maxLines ?? 0
        label.lineBreakMode = input.maxLines == nil ? .byCharWrapping : .byTruncatingTail
        label.attributedText = input.render().attributedString
        label.invalidateIntrinsicContentSize()
        context.coordinator.currentInput = input
        context.coordinator.loadMissingImages(from: input, into: label)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        let width = max(proposal.width ?? uiView.bounds.width, 1)
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }

    final class Coordinator {
        var currentInput: DynamicAttributedTextInput?
        private var imageTasks: [URL: Task<Void, Never>] = [:]

        func loadMissingImages(from input: DynamicAttributedTextInput, into label: UILabel) {
            let urls = input.render().missingImageURLs
            guard !urls.isEmpty else { return }

            for url in urls where imageTasks[url] == nil {
                imageTasks[url] = Task { [weak self, weak label] in
                    _ = await BiliEmoteImageStore.shared.image(for: url)

                    await MainActor.run {
                        guard let self else { return }
                        self.imageTasks[url] = nil
                        guard let label, let currentInput = self.currentInput else { return }
                        label.attributedText = currentInput.render().attributedString
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

private struct DynamicCommentsSheet: View {
    let item: DynamicFeedItem
    @StateObject private var viewModel: DynamicCommentsViewModel
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
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 6)

                    commentsContent
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle("评论")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.loadInitial()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(item: $replySheetComment) { comment in
            DynamicCommentRepliesSheet(rootComment: comment, viewModel: viewModel)
        }
    }

    private var commentsHeader: some View {
        HStack(spacing: 8) {
            Text("全部评论")
                .font(.headline)

            if let count = item.replyCount, count > 0 {
                Text(BiliFormatters.compactCount(count))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                ForEach(CommentSort.allCases) { sort in
                    Button {
                        Task { await viewModel.selectSort(sort) }
                    } label: {
                        Text(sort.title)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(viewModel.selectedSort == sort ? Color.pink.opacity(0.13) : Color.clear)
                            .foregroundStyle(viewModel.selectedSort == sort ? .pink : .secondary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var commentsContent: some View {
        if !viewModel.canLoadComments {
            EmptyStateView(title: "暂不支持评论", systemImage: "bubble.left", message: "这条动态没有返回评论入口。")
                .padding(16)
        } else if viewModel.comments.isEmpty && viewModel.state.isLoading {
            VStack(spacing: 10) {
                ProgressView()
                Text("正在加载评论")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        } else if viewModel.comments.isEmpty, case .failed(let message) = viewModel.state {
            DynamicCommentErrorView(message: message) {
                Task { await viewModel.reload() }
            }
            .padding(16)
        } else if viewModel.comments.isEmpty {
            EmptyStateView(title: "暂无评论", systemImage: "bubble.left", message: "这里还没有可展示的评论。")
                .padding(16)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.comments) { comment in
                    DynamicCommentRow(comment: comment) {
                        replySheetComment = comment
                    }
                    .padding(.horizontal, 16)
                    .task {
                        await viewModel.loadMoreIfNeeded(current: comment)
                    }

                    Divider()
                        .padding(.leading, 66)
                }

                commentsFooter
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
    }

    @ViewBuilder
    private var commentsFooter: some View {
        if viewModel.state.isLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("加载更多评论")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
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
            .buttonStyle(.bordered)
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

@MainActor
private final class DynamicCommentsViewModel: ObservableObject {
    @Published var comments: [Comment] = []
    @Published var state: LoadingState = .idle
    @Published var selectedSort: CommentSort = .hot
    @Published private var replyThreads: [Int: [Comment]] = [:]
    @Published private var replyStates: [Int: LoadingState] = [:]
    @Published private var replyPages: [Int: Int] = [:]
    @Published private var replyHasMore: [Int: Bool] = [:]
    @Published private var dialogThreads: [String: [Comment]] = [:]
    @Published private var dialogStates: [String: LoadingState] = [:]

    private let item: DynamicFeedItem
    private let api: BiliAPIClient
    private var cursor = ""
    private var commentsEnd = false

    var canLoadComments: Bool {
        commentOID != nil && commentType != nil
    }

    var hasMoreComments: Bool {
        !commentsEnd
    }

    init(item: DynamicFeedItem, api: BiliAPIClient) {
        self.item = item
        self.api = api
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

    func replies(for comment: Comment) -> [Comment] {
        replyThreads[comment.id] ?? comment.replies ?? []
    }

    func hasMoreReplies(for comment: Comment) -> Bool {
        if let hasMore = replyHasMore[comment.id] {
            return hasMore
        }
        let loadedCount = replies(for: comment).count
        let totalCount = comment.replyCount ?? comment.replies?.count ?? loadedCount
        return loadedCount < totalCount
    }

    func replyState(for comment: Comment) -> LoadingState {
        replyStates[comment.id] ?? .idle
    }

    func loadReplies(for comment: Comment) async {
        guard replyThreads[comment.id] == nil else { return }
        replyPages[comment.id] = 0
        replyHasMore[comment.id] = true
        await loadReplyPage(for: comment, reset: true)
    }

    func reloadReplies(for comment: Comment) async {
        replyThreads[comment.id] = nil
        replyPages[comment.id] = 0
        replyHasMore[comment.id] = true
        await loadReplyPage(for: comment, reset: true)
    }

    func loadMoreReplies(for comment: Comment) async {
        guard replyHasMore[comment.id] != false,
              !(replyStates[comment.id]?.isLoading ?? false)
        else { return }
        await loadReplyPage(for: comment, reset: false)
    }

    func dialogReplies(for root: Comment, reply: Comment) -> [Comment] {
        let key = dialogKey(root: root, reply: reply)
        return dialogThreads[key] ?? localDialogReplies(root: root, reply: reply)
    }

    func dialogState(for root: Comment, reply: Comment) -> LoadingState {
        dialogStates[dialogKey(root: root, reply: reply)] ?? .idle
    }

    func loadDialog(for root: Comment, reply: Comment) async {
        let key = dialogKey(root: root, reply: reply)
        guard dialogThreads[key] == nil else { return }
        await loadDialogPage(for: root, reply: reply)
    }

    func reloadDialog(for root: Comment, reply: Comment) async {
        let key = dialogKey(root: root, reply: reply)
        dialogThreads[key] = nil
        await loadDialogPage(for: root, reply: reply)
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
            appendUniqueComments(pageComments)
            cursor = page.cursor?.next ?? ""
            commentsEnd = page.cursor?.isEnd ?? true
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func loadReplyPage(for comment: Comment, reset: Bool) async {
        guard let oid = commentOID, let type = commentType else {
            replyStates[comment.id] = .failed("这条动态没有返回评论入口")
            return
        }

        replyStates[comment.id] = .loading
        do {
            let nextPage = reset ? 1 : (replyPages[comment.id] ?? 1) + 1
            let page = try await api.fetchCommentReplies(oid: oid, type: type, root: comment.rpid, page: nextPage)
            let fetchedReplies = page.replies ?? []
            let existingReplies = reset ? (comment.replies ?? []) : (replyThreads[comment.id] ?? comment.replies ?? [])
            let replies = uniqueComments(existingReplies + fetchedReplies)
            replyThreads[comment.id] = replies
            replyPages[comment.id] = nextPage
            let totalCount = comment.replyCount ?? Int.max
            replyHasMore[comment.id] = !fetchedReplies.isEmpty && replies.count < totalCount
            replyStates[comment.id] = .loaded
        } catch {
            if reset {
                replyThreads[comment.id] = comment.replies ?? []
            }
            replyStates[comment.id] = .failed(error.localizedDescription)
        }
    }

    private func loadDialogPage(for root: Comment, reply: Comment) async {
        guard let oid = commentOID, let type = commentType else {
            dialogStates[dialogKey(root: root, reply: reply)] = .failed("这条动态没有返回评论入口")
            return
        }

        let key = dialogKey(root: root, reply: reply)
        let fallbackReplies = localDialogReplies(root: root, reply: reply)

        guard let dialogID = reply.dialogID, dialogID > 0 else {
            dialogThreads[key] = fallbackReplies
            dialogStates[key] = .loaded
            return
        }

        dialogStates[key] = .loading
        do {
            let page = try await api.fetchCommentDialog(oid: oid, type: type, root: root.rpid, dialog: dialogID)
            let replies = uniqueComments((page.replies ?? []) + fallbackReplies)
            dialogThreads[key] = replies.isEmpty ? fallbackReplies : replies
            dialogStates[key] = .loaded
        } catch {
            dialogThreads[key] = fallbackReplies
            dialogStates[key] = .failed(error.localizedDescription)
        }
    }

    private func appendUniqueComments(_ more: [Comment]) {
        let existing = Set(comments.map(\.id))
        comments.append(contentsOf: more.filter { !existing.contains($0.id) })
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

    private func uniqueComments(_ comments: [Comment]) -> [Comment] {
        var seen = Set<Int>()
        return comments.filter { seen.insert($0.id).inserted }
    }
}

private struct DynamicCommentRow: View {
    let comment: Comment
    let showReplies: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            DynamicCommentAvatar(urlString: comment.member?.avatar, size: 40)

            VStack(alignment: .leading, spacing: 8) {
                header

                BiliEmoteText(content: comment.content, font: .subheadline, textColor: .primary, emoteSize: 22)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !replyPreviews.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(replyPreviews.enumerated()), id: \.offset) { _, reply in
                            DynamicReplyPreviewRow(reply: reply)
                        }
                    }
                }

                if visibleReplyCount > 0 {
                    Button(action: showReplies) {
                        Label("\(visibleReplyCount) 条回复", systemImage: "bubble.left.and.bubble.right")
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

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(comment.member?.uname ?? "Unknown")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !timeText.isEmpty {
                Text(timeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Label(BiliFormatters.compactCount(comment.like), systemImage: comment.likeState == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
                .font(.caption)
                .foregroundStyle(comment.likeState == 1 ? .pink : .secondary)
                .labelStyle(.titleAndIcon)
        }
    }

    private var message: String {
        let text = comment.content?.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? " " : text
    }

    private var timeText: String {
        BiliFormatters.relativeTime(comment.ctime)
    }

    private var replyPreviews: [Comment] {
        Array((comment.replies ?? []).prefix(2))
    }

    private var visibleReplyCount: Int {
        comment.replyCount ?? comment.replies?.count ?? 0
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

private struct DynamicCommentRepliesSheet: View {
    let rootComment: Comment
    @ObservedObject var viewModel: DynamicCommentsViewModel
    @State private var dialogReply: Comment?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DynamicCommentReplyRootView(comment: rootComment)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                    Divider()

                    repliesContent
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle("评论回复")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.loadReplies(for: rootComment)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(item: $dialogReply) { reply in
            DynamicCommentDialogSheet(rootComment: rootComment, focusReply: reply, viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var repliesContent: some View {
        let state = viewModel.replyState(for: rootComment)
        let replies = viewModel.replies(for: rootComment)

        if replies.isEmpty && state.isLoading {
            VStack(spacing: 10) {
                ProgressView()
                Text("正在加载回复")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        } else if replies.isEmpty, case .failed(let message) = state {
            DynamicCommentErrorView(message: message) {
                Task { await viewModel.reloadReplies(for: rootComment) }
            }
            .padding(16)
        } else if replies.isEmpty {
            EmptyStateView(title: "暂无回复", systemImage: "bubble.left.and.bubble.right", message: "这条评论还没有可展示的回复。")
                .padding(16)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(replies) { reply in
                    DynamicCommentReplyDetailRow(
                        reply: reply,
                        showDialog: canShowDialog(for: reply) ? {
                            dialogReply = reply
                        } : nil
                    )
                    .padding(.horizontal, 16)

                    Divider()
                        .padding(.leading, 66)
                }

                repliesFooter(state: state)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
    }

    @ViewBuilder
    private func repliesFooter(state: LoadingState) -> some View {
        if !viewModel.replies(for: rootComment).isEmpty, state.isLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("加载更多回复")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        } else if case .failed(let message) = state {
            DynamicCommentErrorView(message: message) {
                Task { await viewModel.loadMoreReplies(for: rootComment) }
            }
        } else if viewModel.hasMoreReplies(for: rootComment) {
            Button {
                Task { await viewModel.loadMoreReplies(for: rootComment) }
            } label: {
                Label("查看更多回复", systemImage: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.pink)
        }
    }

    private func canShowDialog(for reply: Comment) -> Bool {
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

private struct DynamicCommentReplyRootView: View {
    let comment: Comment

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            DynamicCommentAvatar(urlString: comment.member?.avatar, size: 40)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(comment.member?.uname ?? "Unknown")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if !BiliFormatters.relativeTime(comment.ctime).isEmpty {
                        Text(BiliFormatters.relativeTime(comment.ctime))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                BiliEmoteText(content: comment.content, font: .subheadline, textColor: .primary, emoteSize: 22)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct DynamicCommentReplyDetailRow: View {
    let reply: Comment
    let showDialog: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            DynamicCommentAvatar(urlString: reply.member?.avatar, size: 36)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(reply.member?.uname ?? "Unknown")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if !BiliFormatters.relativeTime(reply.ctime).isEmpty {
                        Text(BiliFormatters.relativeTime(reply.ctime))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Label(BiliFormatters.compactCount(reply.like), systemImage: reply.likeState == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(.caption)
                        .foregroundStyle(reply.likeState == 1 ? .pink : .secondary)
                        .labelStyle(.titleAndIcon)
                }

                BiliEmoteText(content: reply.content, font: .subheadline, textColor: .primary, emoteSize: 22)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

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
    @ObservedObject var viewModel: DynamicCommentsViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DynamicCommentReplyRootView(comment: rootComment)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                    Divider()

                    dialogContent
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle("查看对话")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.loadDialog(for: rootComment, reply: focusReply)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var dialogContent: some View {
        let state = viewModel.dialogState(for: rootComment, reply: focusReply)
        let replies = viewModel.dialogReplies(for: rootComment, reply: focusReply)

        if replies.isEmpty && state.isLoading {
            VStack(spacing: 10) {
                ProgressView()
                Text("正在加载对话")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        } else if replies.isEmpty, case .failed(let message) = state {
            DynamicCommentErrorView(message: message) {
                Task { await viewModel.reloadDialog(for: rootComment, reply: focusReply) }
            }
            .padding(16)
        } else if replies.isEmpty {
            EmptyStateView(title: "暂无对话", systemImage: "text.bubble", message: "暂时没有找到这条回复的上下文。")
                .padding(16)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(replies) { reply in
                    DynamicCommentDialogRow(reply: reply, isFocused: reply.id == focusReply.id)
                        .padding(.horizontal, 16)

                    Divider()
                        .padding(.leading, 66)
                }

                if case .failed(let message) = state {
                    DynamicCommentErrorView(message: message) {
                        Task { await viewModel.reloadDialog(for: rootComment, reply: focusReply) }
                    }
                    .padding(16)
                }
            }
        }
    }
}

private struct DynamicCommentDialogRow: View {
    let reply: Comment
    let isFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            DynamicCommentAvatar(urlString: reply.member?.avatar, size: 36)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(reply.member?.uname ?? "Unknown")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if !BiliFormatters.relativeTime(reply.ctime).isEmpty {
                        Text(BiliFormatters.relativeTime(reply.ctime))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Label(BiliFormatters.compactCount(reply.like), systemImage: reply.likeState == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(.caption)
                        .foregroundStyle(reply.likeState == 1 ? .pink : .secondary)
                        .labelStyle(.titleAndIcon)
                }

                BiliEmoteText(content: reply.content, font: .subheadline, textColor: .primary, emoteSize: 22)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
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
        CachedRemoteImage(url: urlString.flatMap { URL(string: $0.biliAvatarThumbnailURL(size: Int(size * 3))) }) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: size * 0.9))
                .foregroundStyle(.tertiary)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
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
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct DynamicOriginalPreview: View {
    let item: DynamicOriginalItem
    @State private var imageSelection: DynamicImageSelection?

    private var video: VideoItem? {
        item.archive?.asVideoItem(author: item.author)
    }

    private var live: DynamicLive? {
        item.live
    }

    private var liveRoom: LiveRoom? {
        live?.asLiveRoom(author: item.author)
    }

    private var authorOwner: VideoOwner? {
        item.author?.owner
    }

    private var imageItems: [DynamicImageItem] {
        item.imageItems.filter { $0.normalizedURL != nil }
    }

    private var textSegments: [DynamicTextSegment] {
        item.textSegments
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.caption2.weight(.bold))
                Text("原动态")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.pink)

            originalContent
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground).opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.pink.opacity(0.18), lineWidth: 0.8)
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.pink.opacity(0.62))
                .frame(width: 3)
                .padding(.vertical, 12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .fullScreenCover(item: $imageSelection) { selection in
            DynamicImageViewer(images: imageItems, initialIndex: selection.index)
        }
    }

    @ViewBuilder
    private var originalContent: some View {
        if item.visible == false || !item.hasDisplayableContent {
            DynamicForwardUnavailableView()
        } else {
            VStack(alignment: .leading, spacing: 9) {
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

                if DynamicTextSegment.displayText(from: textSegments)?.isEmpty == false {
                    DynamicRichTextView(
                        segments: textSegments,
                        font: .footnote,
                        textColor: .primary,
                        emoteSize: 20,
                        maxLines: 5
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let video {
                    VideoRouteLink(video) {
                        DynamicArchivePreview(video: video)
                    }
                }

                if let live {
                    DynamicLiveRouteLink(room: liveRoom) {
                        DynamicLivePreview(live: live)
                    }
                }

                if !imageItems.isEmpty {
                    DynamicImageGrid(images: imageItems) { index in
                        imageSelection = DynamicImageSelection(index: index)
                    }
                }
            }
        }
    }

    private func originalAuthorIdentity(_ author: DynamicAuthor) -> some View {
        HStack(spacing: 8) {
            CachedRemoteImage(url: author.face.flatMap { URL(string: $0.biliAvatarThumbnailURL(size: 72)) }) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 24, height: 24)
            .clipShape(Circle())

            Text("@\(author.name ?? "Unknown")")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
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

private struct DynamicImageSelection: Identifiable {
    let index: Int

    var id: Int { index }
}

private struct DynamicImageGrid: View {
    let images: [DynamicImageItem]
    let openImage: (Int) -> Void
    private static let spacing: CGFloat = 4

    private var displayedImages: Array<(offset: Int, element: DynamicImageItem)> {
        Array(images.prefix(9).enumerated())
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            content(width: 520)
            content(width: 420)
            content(width: 330)
        }
    }

    @ViewBuilder
    private func content(width: CGFloat) -> some View {
        if displayedImages.count == 1, let image = displayedImages.first {
            let imageWidth = floor(width * 0.7)
            let aspectRatio = CGFloat(max(image.element.aspectRatio, 0.1))
            let imageHeight = imageWidth / aspectRatio
            HStack {
                Button {
                    openImage(image.offset)
                } label: {
                    DynamicImageCell(image: image.element, displayMode: .single)
                        .frame(width: imageWidth, height: imageHeight)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            .frame(width: width, alignment: .leading)
        } else {
            let columns = Array(
                repeating: GridItem(.flexible(), spacing: Self.spacing),
                count: columnCount
            )

            LazyVGrid(columns: columns, alignment: .leading, spacing: Self.spacing) {
                ForEach(displayedImages, id: \.offset) { index, image in
                    Button {
                        openImage(index)
                    } label: {
                        DynamicImageCell(image: image, displayMode: .square)
                            .overlay {
                                if index == 8, images.count > 9 {
                                    ZStack {
                                        Color.black.opacity(0.46)
                                        Text("+\(images.count - 8)")
                                            .font(.title3.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: width, alignment: .leading)
        }
    }

    private var columnCount: Int {
        switch displayedImages.count {
        case 0, 1:
            return 1
        case 2, 4:
            return 2
        default:
            return 3
        }
    }

}

private struct DynamicImageCell: View {
    enum DisplayMode {
        case single
        case square
    }

    let image: DynamicImageItem
    let displayMode: DisplayMode

    var body: some View {
        switch displayMode {
        case .single:
            imageContent
                .aspectRatio(displayAspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .square:
            GeometryReader { proxy in
                let side = proxy.size.width
                imageContent
                    .frame(width: side, height: side)
            }
            .aspectRatio(1, contentMode: .fit)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var imageContent: some View {
        ZStack {
            Color.gray.opacity(0.12)

            CachedRemoteImage(url: image.normalizedURL.flatMap(URL.init(string:))) { loadedImage in
                loadedImage
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Color.gray.opacity(0.12)
                    .overlay {
                        ProgressView()
                    }
            }
        }
    }

    private var displayAspectRatio: CGFloat {
        switch displayMode {
        case .single:
            return CGFloat(max(image.aspectRatio, 0.1))
        case .square:
            return 1
        }
    }
}

private struct DynamicImageViewer: View {
    let images: [DynamicImageItem]
    let initialIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int
    @State private var dragOffset: CGSize = .zero
    @State private var isPresented = false
    @State private var isClosing = false

    init(images: [DynamicImageItem], initialIndex: Int) {
        self.images = images
        self.initialIndex = initialIndex
        _selection = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                    DynamicViewerImage(image: image) {
                        close()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .automatic : .never))
            .offset(y: dragOffset.height)
            .scaleEffect(viewerScale * presentationScale)
            .opacity(presentationOpacity)

            if images.count > 1 {
                Text("\(selection + 1) / \(images.count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.44))
                    .clipShape(Capsule())
                    .padding(.bottom, 22)
                    .opacity(1 - dismissProgress)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(dragToDismissGesture)
        .animation(.smooth(duration: 0.2), value: isPresented)
        .animation(.smooth(duration: 0.16), value: isClosing)
        .animation(.interactiveSpring(duration: 0.24, extraBounce: 0.08), value: dragOffset)
        .onAppear {
            isPresented = true
        }
        .preferredColorScheme(.dark)
    }

    private var dismissProgress: CGFloat {
        min(abs(dragOffset.height) / 260, 1)
    }

    private var backgroundOpacity: Double {
        Double(presentationOpacity) * Double(1 - dismissProgress * 0.72)
    }

    private var viewerScale: CGFloat {
        1 - dismissProgress * 0.08
    }

    private var presentationOpacity: CGFloat {
        isClosing ? 0 : (isPresented ? 1 : 0)
    }

    private var presentationScale: CGFloat {
        isClosing ? 0.96 : (isPresented ? 1 : 0.96)
    }

    private func close() {
        guard !isClosing else { return }
        withAnimation(.smooth(duration: 0.16)) {
            isClosing = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            dismiss()
        }
    }

    private var dragToDismissGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                let vertical = abs(value.translation.height)
                let horizontal = abs(value.translation.width)
                guard vertical > horizontal * 1.1 else {
                    if dragOffset != .zero {
                        dragOffset = .zero
                    }
                    return
                }
                dragOffset = value.translation
            }
            .onEnded { value in
                let vertical = abs(value.translation.height)
                let horizontal = abs(value.translation.width)
                let predictedVertical = abs(value.predictedEndTranslation.height)
                let shouldDismiss = vertical > horizontal * 1.1
                    && (vertical > 150 || predictedVertical > 260)

                if shouldDismiss {
                    close()
                } else {
                    withAnimation(.interactiveSpring(duration: 0.26, extraBounce: 0.1)) {
                        dragOffset = .zero
                    }
                }
            }
    }
}

private struct DynamicViewerImage: View {
    let image: DynamicImageItem
    let close: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let imageWidth = proxy.size.width
            let imageHeight = max(imageWidth / CGFloat(max(image.aspectRatio, 0.1)), 1)
            let verticalInset = max((proxy.size.height - imageHeight) / 2, 0)

            ScrollView(.vertical) {
                imageContent(width: imageWidth, height: imageHeight)
                    .padding(.top, verticalInset)
                    .padding(.bottom, verticalInset)
            }
            .scrollIndicators(.hidden)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    @ViewBuilder
    private func imageContent(width: CGFloat, height: CGFloat) -> some View {
        CachedRemoteImage(url: image.normalizedURL.flatMap(URL.init(string:))) { loadedImage in
            loadedImage
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
        } placeholder: {
            ProgressView()
                .tint(.white)
                .frame(width: width, height: max(height, 220))
        }
    }
}

private struct DynamicArchivePreview: View {
    let video: VideoItem

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                CachedRemoteImage(url: video.pic.flatMap { URL(string: $0.biliCoverThumbnailURL(width: 480, height: 270)) }) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.14)
                }
                .frame(width: 118, height: 66)
                .clipped()

                Text(BiliFormatters.duration(video.duration))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.54))
                    .clipShape(Capsule())
                    .padding(5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 7) {
                Text(video.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Label(BiliFormatters.compactCount(video.stat?.view), systemImage: "play.rectangle")
                    Text(video.owner?.name ?? "")
                        .lineLimit(1)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DynamicLivePreview: View {
    let live: DynamicLive

    var body: some View {
        liveContent
        .accessibilityElement(children: .combine)
        .accessibilityLabel("直播 \(live.displayTitle)")
    }

    private var liveContent: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .topLeading) {
                CachedRemoteImage(url: live.normalizedCoverURL.flatMap { URL(string: $0.biliCoverThumbnailURL(width: 480, height: 270)) }) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.14)
                        .overlay {
                            Image(systemName: "play.tv")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                }
                .frame(width: 118, height: 66)
                .clipped()

                Text(live.statusText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.pink.opacity(0.92))
                    .clipShape(Capsule())
                    .padding(5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 7) {
                Text(live.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    if let viewerText = live.viewerText {
                        Label(viewerText, systemImage: "person.2")
                    }

                    if let areaName = live.areaName, !areaName.isEmpty {
                        Label(areaName, systemImage: "tag")
                            .lineLimit(1)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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

@MainActor
final class DynamicViewModel: ObservableObject {
    @Published var items: [DynamicFeedItem] = []
    @Published var state: LoadingState = .idle

    private let api: BiliAPIClient
    private let libraryStore: LibraryStore
    private var rawItems: [DynamicFeedItem] = []
    private var offset = ""
    private var hasMore = true
    private var filterCancellable: AnyCancellable?

    var hasMoreItems: Bool {
        hasMore
    }

    init(api: BiliAPIClient, libraryStore: LibraryStore) {
        self.api = api
        self.libraryStore = libraryStore
        filterCancellable = libraryStore.$blocksGoodsDynamics
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.applyCurrentFilter()
            }
    }

    func loadInitial() async {
        guard items.isEmpty else { return }
        await refresh()
    }

    func refresh() async {
        state = .loading
        offset = ""
        hasMore = true
        do {
            let page = try await api.fetchDynamicFeed()
            rawItems = displayable(page.items)
            applyCurrentFilter()
            offset = page.offset ?? ""
            hasMore = page.hasMore ?? false
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
        guard hasMore, !state.isLoading else { return }
        state = .loading
        do {
            let page = try await api.fetchDynamicFeed(offset: offset)
            appendUniqueRaw(displayable(page.items))
            applyCurrentFilter()
            offset = page.offset ?? offset
            hasMore = page.hasMore ?? false
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
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
        if libraryStore.blocksGoodsDynamics {
            items = rawItems.filter { !$0.containsGoodsPromotion }
        } else {
            items = rawItems
        }
    }

    private func appendUniqueRaw(_ more: [DynamicFeedItem]) {
        let existing = Set(rawItems.map(\.id))
        rawItems.append(contentsOf: more.filter { !existing.contains($0.id) })
    }
}

@MainActor
final class DynamicViewModelHolder: ObservableObject {
    @Published var viewModel: DynamicViewModel?
    private var cancellable: AnyCancellable?

    func configure(api: BiliAPIClient, libraryStore: LibraryStore) {
        if viewModel == nil {
            let viewModel = DynamicViewModel(api: api, libraryStore: libraryStore)
            self.viewModel = viewModel
            cancellable = viewModel.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
    }
}
