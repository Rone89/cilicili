import PhotosUI
import SwiftUI
import UIKit

enum DynamicCommentComposerState: Equatable {
    case idle
    case composing
    case replying(target: DynamicCommentComposerTarget)
    case sending
    case failed(message: String)
}

private enum DynamicDetailComposerPanel: Equatable {
    case emotes
    case photos
}

struct DynamicComposerLayout {
    let bottomSafeArea: CGFloat
    let isCompact: Bool
    let isComposing: Bool

    var usesCompactInsets: Bool {
        isCompact && !isComposing && bottomSafeArea > 0
    }

    var horizontalPadding: CGFloat { usesCompactInsets ? 26 : 8 }

    var bottomPadding: CGFloat {
        usesCompactInsets ? 8 + min(bottomSafeArea, 20) - bottomSafeArea : 8
    }
}

struct TelegramDynamicDetailInputLayout {
    let bottomSafeArea: CGFloat
    let isCompact: Bool

    let controlSize: CGFloat = 40
    let spacing: CGFloat = 6

    var usesCompactInsets: Bool {
        isCompact && bottomSafeArea > 0
    }

    var horizontalPadding: CGFloat { usesCompactInsets ? 26 : 8 }

    var bottomPadding: CGFloat {
        usesCompactInsets ? 8 + min(bottomSafeArea, 20) - bottomSafeArea : 8
    }
}

struct TelegramDynamicDetailInputStyleBar: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let bottomSafeArea: CGFloat

    private var layout: TelegramDynamicDetailInputLayout {
        TelegramDynamicDetailInputLayout(
            bottomSafeArea: bottomSafeArea,
            isCompact: horizontalSizeClass == .compact
        )
    }

    var body: some View {
        GlassEffectContainer(spacing: layout.spacing) {
            HStack(spacing: layout.spacing) {
                previewButton(systemImage: "paperclip", label: "附件按钮样式预览")

                Button {} label: {
                    HStack(spacing: 8) {
                        Text("输入消息")
                            .font(.system(size: 17))
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 0)

                        Image(systemName: "face.smiling")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: layout.controlSize)
                .glassEffect(.regular, in: Capsule())
                .accessibilityLabel("输入框样式预览")
                .accessibilityIdentifier("dynamic.detail.telegramStyle.input")

                previewButton(systemImage: "mic", label: "语音按钮样式预览")
            }
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.top, 3)
        .padding(.bottom, layout.bottomPadding)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dynamic.detail.telegramStyle.bottomBar")
    }

    private func previewButton(systemImage: String, label: String) -> some View {
        Button {} label: {
            ZStack {
                Circle()
                    .fill(.clear)
                Image(systemName: systemImage)
                    .font(.system(size: 24))
            }
            .contentShape(Circle())
            .frame(width: layout.controlSize, height: layout.controlSize)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: Circle())
        .foregroundStyle(.primary)
        .accessibilityLabel(label)
        .accessibilityIdentifier("dynamic.detail.telegramStyle.\(systemImage)")
    }
}

struct DynamicDetailBottomInteractionBar: ToolbarContent {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.appThemeTintColor) private var appTintColor

    let display: DynamicFeedCardDisplayModel
    let initialIsLiked: Bool
    let initialLikeCount: Int
    let commentCount: Int
    let canComment: Bool
    let openComment: () -> Void

    @State private var likeState: DynamicLikeDisplayState
    @State private var isMutatingLike = false
    @State private var errorMessage: String?

    init(
        display: DynamicFeedCardDisplayModel,
        initialIsLiked: Bool,
        initialLikeCount: Int,
        commentCount: Int,
        canComment: Bool,
        openComment: @escaping () -> Void
    ) {
        self.display = display
        self.initialIsLiked = initialIsLiked
        self.initialLikeCount = initialLikeCount
        self.commentCount = commentCount
        self.canComment = canComment
        self.openComment = openComment
        _likeState = State(initialValue: DynamicLikeDisplayState(
            isLiked: initialIsLiked,
            likeCount: initialLikeCount
        ))
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

    private var likeButton: some View {
        Button(action: toggleLike) {
            Image(systemName: likeState.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                .font(.body)
        }
        .controlSize(.small)
        .imageScale(.medium)
        .foregroundStyle(likeState.isLiked ? appTintColor : .primary)
        .disabled(isMutatingLike)
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
                Image(systemName: "bubble.left")
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

    private var shareButton: some View {
        ShareLink(item: dynamicShareURL) {
            Image(systemName: "square.and.arrow.up")
                .font(.body)
        }
        .controlSize(.small)
        .imageScale(.medium)
        .foregroundStyle(.primary)
        .accessibilityLabel("分享动态")
    }

    private var dynamicShareURL: URL {
        URL(string: "https://t.bilibili.com/\(display.dynamicID)")!
    }

    private func toggleLike() {
        let account = sessionStore.credentialSnapshot(
            for: .interaction,
            multiAccountEnabled: libraryStore.multiAccountExperimentEnabled
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
                try await dependencies.api.setDynamicLike(
                    dynamicID: display.dynamicID,
                    liked: targetState.isLiked
                )
                Haptics.success()
            } catch {
                likeState = previousState
                errorMessage = error.localizedDescription
            }
            isMutatingLike = false
        }
    }

}

struct DynamicDetailComposerBottomBar: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.appThemeTintColor) private var appTintColor
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let bottomSafeArea: CGFloat

    let display: DynamicFeedCardDisplayModel
    let initialIsLiked: Bool
    let initialLikeCount: Int
    let commentCount: Int
    let canComment: Bool
    @Binding var draft: String
    let api: BiliAPIClient
    let submit: (String, [DynamicCommentImage]?) async throws -> Void

    @State private var composerState = DynamicCommentComposerState.idle
    @State private var likeState: DynamicLikeDisplayState
    @State private var isMutatingLike = false
    @State private var selectedPhotos = [PhotosPickerItem]()
    @State private var attachedImageDatas = [Data]()
    @State private var isLoadingImages = false
    @State private var emotes = [BiliInlineEmote]()
    @State private var activePanel: DynamicDetailComposerPanel?
    @State private var showsFullPhotoPicker = false
    @State private var message: String?
    @FocusState private var isEditorFocused: Bool

    init(
        display: DynamicFeedCardDisplayModel,
        initialIsLiked: Bool,
        initialLikeCount: Int,
        commentCount: Int,
        canComment: Bool,
        bottomSafeArea: CGFloat = 0,
        draft: Binding<String>,
        api: BiliAPIClient,
        submit: @escaping (String, [DynamicCommentImage]?) async throws -> Void
    ) {
        self.display = display
        self.initialIsLiked = initialIsLiked
        self.initialLikeCount = initialLikeCount
        self.commentCount = commentCount
        self.canComment = canComment
        self.bottomSafeArea = bottomSafeArea
        self._draft = draft
        self.api = api
        self.submit = submit
        _likeState = State(initialValue: DynamicLikeDisplayState(
            isLiked: initialIsLiked,
            likeCount: initialLikeCount
        ))
    }

    private var isComposing: Bool {
        switch composerState {
        case .idle:
            return false
        case .composing, .replying, .sending, .failed:
            return true
        }
    }

    private var normalizedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !normalizedDraft.isEmpty && composerState != .sending && !isLoadingImages
    }

    private var layout: DynamicComposerLayout {
        DynamicComposerLayout(
            bottomSafeArea: bottomSafeArea,
            isCompact: horizontalSizeClass == .compact,
            isComposing: isComposing
        )
    }

    var body: some View {
        VStack(spacing: 8) {
            if isComposing {
                expandedComposer
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                collapsedBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.top, 3)
        .padding(.bottom, layout.bottomPadding)
        .animation(.smooth, value: isComposing)
        .onChange(of: selectedPhotos) { _, items in
            loadSelectedPhotos(items)
        }
        .onChange(of: isEditorFocused) { _, isFocused in
            guard isFocused else {
                collapseIfPossible()
                return
            }
            activePanel = nil
        }
        .task {
            guard emotes.isEmpty else { return }
            emotes = (try? await api.fetchCommentEmotes()) ?? []
        }
        .onChange(of: sourceLikeState) { _, state in
            guard !isMutatingLike else { return }
            likeState = state
        }
        .alert("操作提示", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("好", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "请稍后重试")
        }
        .photosPicker(
            isPresented: $showsFullPhotoPicker,
            selection: $selectedPhotos,
            maxSelectionCount: 9,
            matching: .images,
            preferredItemEncoding: .current
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dynamic.detail.composer.bottomBar")
    }

    private var collapsedBar: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(alignment: .center, spacing: 6) {
                likeButton

                Button(action: beginComposing) {
                    Label("说点什么…", systemImage: "bubble.left")
                        .font(.body)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Capsule())
                .disabled(!canComment)
                .accessibilityLabel("发表评论")
                .accessibilityValue("共 \(commentCount) 条评论")

                favoriteButton
            }
        }
    }

    private var expandedComposer: some View {
        VStack(spacing: 8) {
            attachmentPreview

            GlassEffectContainer(spacing: 6) {
                HStack(alignment: .bottom, spacing: 6) {
                    editorSurface
                    sendButton
                }
            }

            if activePanel == .emotes {
                DynamicInlineCommentEmotePicker(
                    emotes: emotes,
                    onSelect: insertEmote,
                    onDismiss: dismissActivePanel
                )
                .frame(height: 300)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if activePanel == .photos {
                DynamicInlinePhotoPickerPanel(
                    selection: $selectedPhotos,
                    showsFullPicker: $showsFullPhotoPicker,
                    onDismiss: dismissActivePanel
                )
                .frame(height: 300)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var editorSurface: some View {
        HStack(alignment: .bottom, spacing: 2) {
            TextField("发表评论", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($isEditorFocused)
                .textFieldStyle(.plain)
                .padding(.leading, 12)
                .padding(.vertical, 11)
                .accessibilityLabel("评论内容")
                .accessibilityIdentifier("dynamic.detail.composer.editor")

            Button {
                togglePanel(.photos)
            } label: {
                Image(systemName: activePanel == .photos ? "photo.fill" : "photo")
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(activePanel == .photos ? appTintColor : .secondary)
            .accessibilityLabel(activePanel == .photos ? "收起照片选择器" : "添加图片")

            Button {
                togglePanel(.emotes)
            } label: {
                Image(systemName: activePanel == .emotes ? "face.smiling.inverse" : "face.smiling")
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(activePanel == .emotes ? appTintColor : .secondary)
            .accessibilityLabel(activePanel == .emotes ? "收起表情选择器" : "选择表情")
        }
        .padding(.trailing, 2)
        .frame(minHeight: 40)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    private var sendButton: some View {
        Button(action: submitDraft) {
            Group {
                if composerState == .sending || isLoadingImages {
                    ProgressView()
                } else {
                    Image(systemName: "paperplane.fill")
                }
            }
            .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(appTintColor).interactive(), in: Circle())
        .disabled(!canSend)
        .accessibilityLabel(composerState == .sending ? "正在发送评论" : "发送评论")
        .accessibilityIdentifier("dynamic.detail.composer.send")
    }

    @ViewBuilder
    private var attachmentPreview: some View {
        if !attachedImageDatas.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "photo.stack")
                    .foregroundStyle(.secondary)
                Text("已选择 \(attachedImageDatas.count) 张图片")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Button {
                    selectedPhotos = []
                    attachedImageDatas = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("移除图片")
            }
            .padding(.horizontal, 8)
        }
    }

    private var likeButton: some View {
        Button(action: toggleLike) {
            Image(systemName: likeState.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                .font(.body)
                .frame(width: 40, height: 40)
                .contentShape(Circle().inset(by: -2))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .foregroundStyle(likeState.isLiked ? appTintColor : .primary)
        .disabled(isMutatingLike)
        .accessibilityLabel(likeState.isLiked ? "取消点赞" : "点赞")
        .accessibilityValue("\(likeState.isLiked ? "已点赞" : "未点赞")，\(likeState.likeCount) 个赞")
        .accessibilityAddTraits(likeState.isLiked ? .isSelected : [])
        .accessibilityIdentifier("dynamic.detail.composer.like")
        .contentTransition(.symbolEffect(.replace))
    }

    private var favoriteButton: some View {
        Button {
            message = "动态收藏暂未接入"
        } label: {
            Image(systemName: "star")
                .font(.body)
                .frame(width: 40, height: 40)
                .contentShape(Circle().inset(by: -2))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .foregroundStyle(.secondary)
        .accessibilityLabel("收藏")
        .accessibilityValue("动态收藏暂未接入")
        .accessibilityIdentifier("dynamic.detail.composer.favorite")
    }

    private var sourceLikeState: DynamicLikeDisplayState {
        DynamicLikeDisplayState(isLiked: initialIsLiked, likeCount: initialLikeCount)
    }

    private func beginComposing() {
        guard canComment else { return }
        composerState = .composing
        activePanel = nil
        Task { @MainActor in
            await Task.yield()
            isEditorFocused = true
        }
    }

    private func dismissActivePanel() {
        withAnimation(.smooth) {
            activePanel = nil
        }
        isEditorFocused = true
    }

    private func insertEmote(_ token: String) {
        draft += token
    }

    private func togglePanel(_ panel: DynamicDetailComposerPanel) {
        let shouldPresent = activePanel != panel
        isEditorFocused = false
        withAnimation(.smooth) {
            activePanel = shouldPresent ? panel : nil
        }
        if !shouldPresent {
            isEditorFocused = true
        }
    }

    private func collapseIfPossible() {
        guard activePanel == nil,
              normalizedDraft.isEmpty,
              attachedImageDatas.isEmpty,
              composerState != .sending
        else { return }
        composerState = .idle
    }

    private func loadSelectedPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else {
            isLoadingImages = false
            return
        }
        isLoadingImages = true
        Task { @MainActor in
            var imageDatas = [Data]()
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let jpegData = image.jpegData(compressionQuality: 0.9)
                else { continue }
                imageDatas.append(jpegData)
            }
            attachedImageDatas = imageDatas
            isLoadingImages = false
            activePanel = nil
            isEditorFocused = true
        }
    }

    private func submitDraft() {
        let messageText = normalizedDraft
        guard !messageText.isEmpty, composerState != .sending, !isLoadingImages else { return }
        composerState = .sending
        Task { @MainActor in
            do {
                var pictures: [DynamicCommentImage]?
                if !attachedImageDatas.isEmpty {
                    pictures = []
                    for imageData in attachedImageDatas {
                        pictures?.append(try await api.uploadDynamicCommentImage(imageData))
                    }
                }
                try await submit(messageText, pictures)
                draft = ""
                selectedPhotos = []
                attachedImageDatas = []
                activePanel = nil
                isEditorFocused = false
                composerState = .idle
                Haptics.success()
            } catch {
                composerState = .failed(message: error.localizedDescription)
                message = error.localizedDescription
            }
        }
    }

    private func toggleLike() {
        let account = sessionStore.credentialSnapshot(
            for: .interaction,
            multiAccountEnabled: libraryStore.multiAccountExperimentEnabled
        )
        guard account.isLoggedIn else {
            message = "请先登录账号"
            return
        }
        guard !isMutatingLike else { return }

        let previousState = likeState
        let targetState = previousState.toggled()
        isMutatingLike = true
        withAnimation(.snappy(duration: 0.2)) {
            likeState = targetState
        }
        Task { @MainActor in
            do {
                try await dependencies.api.setDynamicLike(
                    dynamicID: display.dynamicID,
                    liked: targetState.isLiked
                )
                Haptics.success()
            } catch {
                withAnimation(.snappy(duration: 0.2)) {
                    likeState = previousState
                }
                message = error.localizedDescription
            }
            isMutatingLike = false
        }
    }
}
