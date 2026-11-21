import SwiftUI

struct ArticleDetailDestination: View {
    let route: ArticleRoute

    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.openURL) private var openURL
    @State private var detail: ArticleDetail?
    @State private var loadErrorMessage: String?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let detail {
                ArticleDetailView(route: route, detail: detail, api: dependencies.api)
            } else if let loadErrorMessage {
                ErrorStateView(
                    title: "专栏加载失败",
                    message: loadErrorMessage,
                    retry: {
                        Task { await loadDetail() }
                    }
                )
                .overlay(alignment: .bottom) {
                    if let fallbackURL = route.webURL {
                        Button {
                            openURL(fallbackURL)
                        } label: {
                            Label("在浏览器中打开", systemImage: "safari")
                                .font(.subheadline.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                        .padding(.bottom, 32)
                    }
                }
            } else {
                DelayedLoadingContent {
                    ProgressView("正在加载专栏...")
                }
            }
        }
        .navigationTitle(detail?.title ?? route.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let owner = resolvedAuthorOwner {
                ToolbarItem(placement: .topBarTrailing) {
                    VideoOwnerRouteLink(owner: owner) {
                        AvatarRemoteImage(urlString: owner.face, pixelSize: 96) {
                            Image(systemName: "person.crop.circle.fill")
                                .foregroundStyle(.primary)
                        }
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("查看作者 \(owner.name)")
                }
            }
        }
        .task(id: route) {
            await loadDetail()
        }
    }

    private var resolvedAuthorOwner: VideoOwner? {
        guard let mid = detail?.authorMID ?? route.authorMID, mid > 0 else { return nil }
        let name = detail?.authorName ?? route.authorName ?? "UP主"
        let face = detail?.authorAvatarURL?.absoluteString ?? route.authorAvatarURL?.absoluteString ?? ""
        return VideoOwner(mid: mid, name: name, face: face)
    }

    @MainActor
    private func loadDetail() async {
        guard !isLoading else { return }
        isLoading = true
        loadErrorMessage = nil
        do {
            let loaded = try await dependencies.api.fetchArticleDetail(for: route)
            detail = loaded
        } catch {
            loadErrorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct ArticleDetailView: View {
    let route: ArticleRoute
    let detail: ArticleDetail
    let api: BiliAPIClient

    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var libraryStore: LibraryStore
    @StateObject private var commentsViewModel: DynamicCommentsViewModel
    @State private var replySheetComment: Comment?
    @State private var richCommentComposerTarget: DynamicCommentComposerTarget?
    @StateObject private var richCommentDrafts = RichCommentDraftStore()

    init(route: ArticleRoute, detail: ArticleDetail, api: BiliAPIClient) {
        self.route = route
        self.detail = detail
        self.api = api
        _commentsViewModel = StateObject(
            wrappedValue: DynamicCommentsViewModel(
                commentOID: detail.commentOID ?? route.commentOID,
                commentType: detail.commentType ?? route.commentType,
                replyCount: detail.stats?.replyCount,
                api: api
            )
        )
    }

    private var previewItems: [ZoomyImagePreviewItem] {
        var items: [ZoomyImagePreviewItem] = []
        if let coverURL = detail.coverURL, !bodyContainsImageURL(coverURL) {
            items.append(
                ZoomyImagePreviewItem(
                    id: coverURL.absoluteString,
                    thumbnailURL: coverURL,
                    viewerURL: coverURL
                )
            )
        }
        for block in detail.blocks {
            if case .image(_, let url, _, let width, let height) = block {
                let pixelSize: CGSize? = if let width, let height, width > 0, height > 0 {
                    CGSize(width: width, height: height)
                } else {
                    nil
                }
                let aspectRatio: CGFloat? = if let width, let height, width > 0, height > 0 {
                    width / height
                } else {
                    nil
                }
                items.append(
                    ZoomyImagePreviewItem(
                        id: url.absoluteString,
                        thumbnailURL: url,
                        viewerURL: url,
                        aspectRatio: aspectRatio,
                        originalPixelSize: pixelSize
                    )
                )
            }
        }
        return items
    }

    private func bodyContainsImageURL(_ url: URL) -> Bool {
        detail.blocks.contains { block in
            if case .image(_, let blockURL, _, _, _) = block {
                return blockURL.absoluteString == url.absoluteString
            }
            return false
        }
    }

    var body: some View {
        let allPreviewItems = previewItems

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let coverURL = detail.coverURL, !bodyContainsImageURL(coverURL) {
                    ArticleRemoteImageBlockView(
                        url: coverURL,
                        caption: nil,
                        width: nil,
                        height: nil,
                        aspectRatio: 16 / 9,
                        previewItems: allPreviewItems
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(detail.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)

                    if hasMetadata {
                        metadataRow
                    }
                }

                if detail.authorName != nil || detail.authorAvatarURL != nil {
                    authorRow
                }

                if let stats = detail.stats, hasStats(stats) {
                    statsBar(stats)
                }

                Divider()

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(detail.blocks) { block in
                        ArticleBlockView(
                            block: block,
                            previewItems: allPreviewItems,
                            onOpenURL: { openURL($0) }
                        )
                    }
                }

                if commentsViewModel.canLoadComments {
                    Divider()
                        .padding(.top, 8)

                    DynamicCommentsSheetContent(
                        viewModel: commentsViewModel,
                        highlightedCommentID: nil,
                        selectSort: { sort in
                            Task { await commentsViewModel.selectSort(sort) }
                        },
                        showReplies: { comment in
                            replySheetComment = comment
                        },
                        replyToComment: { root, parent in
                            richCommentComposerTarget = .reply(root: root, parent: parent)
                        }
                    )
                    .padding(.horizontal, -6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .adaptiveReadableWidth()
        }
        .defersRemoteImageLoadsDuringFastScroll()
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .nativeBottomScrollEdgeBlur()
        .nativeBottomScrollEdgeBlurVisibility(isHidden: richCommentComposerTarget != nil)
        .background(Color(.systemBackground))
        .toolbar {
            if richCommentComposerTarget == nil {
                ArticleDetailBottomInteractionBar(
                    api: api,
                    dynamicID: detail.dynamicID ?? route.dynamicID,
                    cvID: detail.cvID,
                    shareURL: detail.webURL ?? route.webURL,
                    shareTitle: detail.title,
                    initialIsLiked: detail.isLiked,
                    initialLikeCount: detail.stats?.likeCount ?? route.initialLikeCount ?? 0,
                    commentCount: commentsViewModel.displayedReplyCount ?? 0,
                    canComment: commentsViewModel.canLoadComments,
                    openComment: {
                        richCommentComposerTarget = .dynamic
                    }
                )
            }
        }
        .toolbar(
            richCommentComposerTarget != nil ? .hidden : .automatic,
            for: .bottomBar
        )
        .background {
            RichCommentComposerPresenter(
                target: $richCommentComposerTarget,
                draft: { target in
                    richCommentDrafts.binding(for: target)
                },
                api: api,
                contentTarget: CommentLikeTarget(
                    oid: detail.commentOID ?? route.commentOID,
                    type: detail.commentType ?? route.commentType,
                    referer: detail.webURL?.absoluteString ?? route.webURL?.absoluteString ?? ""
                ),
                submit: { submissionTarget, message, pictures in
                    try await submitComment(submissionTarget, message, pictures: pictures)
                }
            )
            .allowsHitTesting(false)
        }
        .environment(\.commentContentOwnerMID, detail.authorMID)
        .commentLikeTarget(
            oid: detail.commentOID ?? route.commentOID,
            type: detail.commentType ?? route.commentType,
            referer: detail.webURL?.absoluteString ?? route.webURL?.absoluteString ?? ""
        )
        .task(id: detail.commentOID ?? route.commentOID) {
            commentsViewModel.setBlocksGoodsComments(libraryStore.blocksGoodsComments)
            await commentsViewModel.loadInitial()
        }
        .onChange(of: libraryStore.blocksGoodsComments) { _, isEnabled in
            commentsViewModel.setBlocksGoodsComments(isEnabled)
        }
        .refreshable {
            await commentsViewModel.reload()
        }
        .sheet(item: $replySheetComment) { comment in
            DynamicCommentRepliesSheet(
                rootComment: comment,
                replyStore: commentsViewModel.replyStore,
                api: api,
                submitReply: { target, message, pictures in
                    try await submitComment(target, message, pictures: pictures)
                }
            )
            .environment(\.commentContentOwnerMID, detail.authorMID)
            .commentLikeTarget(
                oid: detail.commentOID ?? route.commentOID,
                type: detail.commentType ?? route.commentType,
                referer: detail.webURL?.absoluteString ?? route.webURL?.absoluteString ?? ""
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func submitComment(
        _ target: DynamicCommentComposerTarget,
        _ message: String,
        pictures: [DynamicCommentImage]? = nil
    ) async throws {
        guard let oid = detail.commentOID ?? route.commentOID,
              let type = detail.commentType ?? route.commentType else {
            throw BiliAPIError.missingPayload
        }
        try await api.addDynamicComment(
            oid: oid,
            type: type,
            message: message,
            root: target.rootID,
            parent: target.parentID,
            pictures: pictures
        )
        commentsViewModel.registerSubmittedComment()
        await commentsViewModel.reload()
    }

    private var hasMetadata: Bool {
        detail.categoryName != nil || detail.publishTime != nil || detail.wordCount != nil
    }

    @ViewBuilder
    private var metadataRow: some View {
        HStack(spacing: 8) {
            if let categoryName = detail.categoryName, !categoryName.isEmpty {
                Text(categoryName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.secondarySystemBackground), in: Capsule())
            }

            if let publishTime = detail.publishTime, publishTime > 0 {
                Text(Self.formatPublishDate(publishTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let wordCount = detail.wordCount, wordCount > 0 {
                Text("\(wordCount) 字")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var authorRow: some View {
        let owner = detail.authorMID.flatMap { mid -> VideoOwner? in
            guard mid > 0 else { return nil }
            return VideoOwner(
                mid: mid,
                name: detail.authorName ?? "UP主",
                face: detail.authorAvatarURL?.absoluteString ?? ""
            )
        }

        HStack(spacing: 10) {
            if let owner {
                VideoOwnerRouteLink(owner: owner) {
                    authorIdentity
                }
            } else {
                authorIdentity
            }

            Spacer(minLength: 0)
        }
    }

    private var authorIdentity: some View {
        HStack(spacing: 10) {
            AvatarRemoteImage(urlString: detail.authorAvatarURL?.absoluteString, pixelSize: 96) {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 34, height: 34)
            .clipShape(Circle())

            Text(detail.authorName ?? "UP主")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    private func hasStats(_ stats: ArticleStats) -> Bool {
        stats.viewCount != nil
            || stats.likeCount != nil
            || stats.coinCount != nil
            || stats.favoriteCount != nil
            || stats.replyCount != nil
    }

    private func statsBar(_ stats: ArticleStats) -> some View {
        HStack(spacing: 16) {
            if let viewCount = stats.viewCount {
                statChip(icon: "eye", value: viewCount)
            }
            if let likeCount = stats.likeCount {
                statChip(icon: "hand.thumbsup", value: likeCount)
            }
            if let coinCount = stats.coinCount {
                statChip(icon: "bitcoinsign.circle", value: coinCount)
            }
            if let favoriteCount = stats.favoriteCount {
                statChip(icon: "star", value: favoriteCount)
            }
            if let replyCount = stats.replyCount {
                statChip(icon: "bubble.right", value: replyCount)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func statChip(icon: String, value: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(Self.formatCount(value))
                .monospacedDigit()
        }
    }

    private static func formatCount(_ count: Int) -> String {
        if count >= 10_000 {
            return String(format: "%.1f万", Double(count) / 10_000.0)
        }
        return "\(count)"
    }

    private static func formatPublishDate(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct ArticleBlockView: View {
    let block: ArticleBlock
    let previewItems: [ZoomyImagePreviewItem]
    let onOpenURL: (URL) -> Void

    var body: some View {
        switch block {
        case .heading(_, let level, let text):
            Text(text)
                .font(headingFont(level: level))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(.top, level <= 2 ? 6 : 2)

        case .paragraph(_, let runs, let alignment):
            ArticleRunsText(runs: runs)
                .font(.body)
                .lineSpacing(5)
                .multilineTextAlignment(swiftUIAlignment(alignment))
                .frame(maxWidth: .infinity, alignment: frameAlignment(alignment))
                .textSelection(.enabled)

        case .blockquote(_, let runs):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: 3)

                ArticleRunsText(runs: runs)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(.secondarySystemBackground).opacity(0.65),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )

        case .list(_, let ordered, let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, runs in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ordered ? "\(index + 1)." : "•")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ArticleRunsText(runs: runs)
                            .font(.body)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                }
            }

        case .code(_, let language, let text):
            VStack(alignment: .leading, spacing: 6) {
                if let language, !language.isEmpty {
                    Text(language)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(text)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )

        case .image(_, let url, let caption, let width, let height):
            ArticleRemoteImageBlockView(
                url: url,
                caption: caption,
                width: width,
                height: height,
                aspectRatio: nil,
                previewItems: previewItems
            )

        case .divider:
            Divider()
                .padding(.vertical, 4)

        case .linkCard(_, let title, let subtitle, let coverURL, let url):
            let cardContent = HStack(spacing: 12) {
                if let coverURL {
                    CachedRemoteImage(url: coverURL, targetPixelSize: 160) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        BiliMediaPlaceholder(style: .image, iconSize: 16)
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(
                Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )

            if let url {
                let targetRoute = ArticleRoute(source: ArticleRoute.parseSource(from: url), title: title, webURL: url)
                if case .url = targetRoute.source {
                    Button {
                        onOpenURL(url)
                    } label: {
                        cardContent
                    }
                    .buttonStyle(.plain)
                } else {
                    NavigationLink(value: targetRoute) {
                        cardContent
                    }
                    .buttonStyle(.plain)
                }
            } else {
                cardContent
            }
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: return .title2.weight(.bold)
        case 2: return .title3.weight(.bold)
        case 3: return .headline.weight(.semibold)
        default: return .subheadline.weight(.semibold)
        }
    }

    private func swiftUIAlignment(_ alignment: ArticleTextAlignment) -> TextAlignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private func frameAlignment(_ alignment: ArticleTextAlignment) -> Alignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

private struct ArticleRunsText: View {
    let runs: [ArticleTextRun]

    var body: some View {
        Text(attributedText)
    }

    private var attributedText: AttributedString {
        var result = AttributedString()
        for run in runs {
            var segment = AttributedString(run.text)
            if run.isBold && run.isItalic {
                segment.font = .body.bold().italic()
            } else if run.isBold {
                segment.font = .body.bold()
            } else if run.isItalic {
                segment.font = .body.italic()
            } else if run.isCode {
                segment.font = .system(.callout, design: .monospaced)
                segment.backgroundColor = Color(.secondarySystemBackground)
            }
            if run.isStrikethrough {
                segment.strikethroughStyle = .single
            }
            if let linkURL = run.linkURL {
                segment.link = linkURL
            }
            result.append(segment)
        }
        return result
    }
}

private struct ArticleRemoteImageBlockView: View {
    let url: URL
    let caption: String?
    let width: CGFloat?
    let height: CGFloat?
    let aspectRatio: CGFloat?
    let previewItems: [ZoomyImagePreviewItem]

    @State private var isViewerPresented = false

    private var resolvedAspectRatio: CGFloat {
        if let aspectRatio, aspectRatio > 0 {
            return aspectRatio
        }
        if let width, let height, width > 0, height > 0 {
            return max(width / height, 0.2)
        }
        return 16 / 10
    }

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            DynamicImageCellRemoteContent(
                normalizedURLString: url.absoluteString,
                mediaBadgeText: nil,
                showsLongImage: false,
                previewItems: previewItems,
                previewItemID: url.absoluteString,
                previewGroup: nil,
                targetPixelSize: 1200,
                cornerRadius: 10,
                contentMode: .fit,
                contentAlignment: .center,
                onViewerPresentationChange: { presented in
                    isViewerPresented = presented
                }
            )
            .aspectRatio(resolvedAspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(isViewerPresented ? 0.99 : 1)

            if let caption, !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

private struct ArticleDetailBottomInteractionBar: ToolbarContent {
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.appThemeTintColor) private var appTintColor

    let api: BiliAPIClient
    let dynamicID: String?
    let cvID: Int?
    let shareURL: URL?
    let shareTitle: String
    let initialIsLiked: Bool
    let initialLikeCount: Int
    let commentCount: Int
    let canComment: Bool
    let openComment: () -> Void

    @State private var likeState: DynamicLikeDisplayState
    @State private var isMutatingLike = false
    @State private var errorMessage: String?

    init(
        api: BiliAPIClient,
        dynamicID: String?,
        cvID: Int?,
        shareURL: URL?,
        shareTitle: String,
        initialIsLiked: Bool,
        initialLikeCount: Int,
        commentCount: Int,
        canComment: Bool,
        openComment: @escaping () -> Void
    ) {
        self.api = api
        self.dynamicID = dynamicID
        self.cvID = cvID
        self.shareURL = shareURL
        self.shareTitle = shareTitle
        self.initialIsLiked = initialIsLiked
        self.initialLikeCount = initialLikeCount
        self.commentCount = commentCount
        self.canComment = canComment
        self.openComment = openComment
        _likeState = State(
            initialValue: DynamicLikeDisplayState(
                isLiked: initialIsLiked,
                likeCount: initialLikeCount
            )
        )
    }

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            likeButton
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            commentButton
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            shareButton
        }
    }

    private var canLike: Bool {
        let hasDynamicID = !(dynamicID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return hasDynamicID || (cvID ?? 0) > 0
    }

    private var likeButton: some View {
        Button(action: toggleLike) {
            Image(systemName: "hand.thumbsup")
                .font(.body)
        }
        .controlSize(.small)
        .imageScale(.medium)
        .foregroundStyle(likeState.isLiked ? appTintColor : .primary)
        .disabled(isMutatingLike || !canLike)
        .accessibilityLabel(likeState.isLiked ? "取消点赞" : "点赞")
        .accessibilityValue("\(likeState.isLiked ? "已点赞" : "未点赞")，\(likeState.likeCount) 个赞")
        .accessibilityAddTraits(likeState.isLiked ? .isSelected : [])
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "请稍后重试")
        }
    }

    private var commentButton: some View {
        Button(action: openComment) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "square.and.pencil")
                    .font(.body)
                Text("点击发送电波")
                    .font(.body)
            }
            .padding(.horizontal, 6)
        }
        .controlSize(.small)
        .imageScale(.medium)
        .foregroundStyle(.primary)
        .buttonBorderShape(.capsule)
        .accessibilityLabel("评论")
        .accessibilityValue("共 \(commentCount) 条")
        .disabled(!canComment)
    }

    @ViewBuilder
    private var shareButton: some View {
        if let shareURL {
            ShareLink(item: shareURL, subject: Text(shareTitle)) {
                Image(systemName: "square.and.arrow.up")
                    .font(.body)
            }
            .controlSize(.small)
            .imageScale(.medium)
            .foregroundStyle(.primary)
            .accessibilityLabel("分享专栏")
        } else {
            Button {} label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.body)
            }
            .controlSize(.small)
            .imageScale(.medium)
            .foregroundStyle(.primary)
            .disabled(true)
            .accessibilityLabel("分享专栏")
        }
    }

    private func toggleLike() {
        let account = sessionStore.credentialSnapshot(
            for: .interaction,
            multiAccountEnabled: libraryStore.multiAccountEnabled
        )
        guard account.isLoggedIn, !isMutatingLike else {
            errorMessage = account.isLoggedIn ? nil : "请先登录账号"
            return
        }

        let previousState = likeState
        let targetState = previousState.toggled()
        isMutatingLike = true
        likeState = targetState
        Task { @MainActor in
            do {
                if let dynamicID, !dynamicID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    try await api.setDynamicLike(dynamicID: dynamicID, liked: targetState.isLiked)
                } else if let cvID, cvID > 0 {
                    try await api.setArticleLike(cvID: cvID, liked: targetState.isLiked)
                }
                Haptics.success()
            } catch {
                likeState = previousState
                errorMessage = error.localizedDescription
            }
            isMutatingLike = false
        }
    }
}
