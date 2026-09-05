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
    @State private var showsEmotePanel = false
    @State private var message: String?
    @FocusState private var isEditorFocused: Bool

    init(
        display: DynamicFeedCardDisplayModel,
        initialIsLiked: Bool,
        initialLikeCount: Int,
        commentCount: Int,
        canComment: Bool,
        draft: Binding<String>,
        api: BiliAPIClient,
        submit: @escaping (String, [DynamicCommentImage]?) async throws -> Void
    ) {
        self.display = display
        self.initialIsLiked = initialIsLiked
        self.initialLikeCount = initialLikeCount
        self.commentCount = commentCount
        self.canComment = canComment
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
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .animation(.smooth, value: isComposing)
        .onChange(of: selectedPhotos) { _, items in
            loadSelectedPhotos(items)
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
        .accessibilityIdentifier("dynamic.detail.composer.bottomBar")
    }

    private var collapsedBar: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Button(action: beginComposing) {
                    Label("说点什么…", systemImage: "bubble.left")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .disabled(!canComment)
                .accessibilityLabel("发表评论")
                .accessibilityValue("共 \(commentCount) 条评论")

                likeButton
                favoriteButton
            }
        }
    }

    private var expandedComposer: some View {
        VStack(spacing: 8) {
            if showsEmotePanel {
                DynamicDetailComposerEmotePanel(
                    emotes: emotes,
                    onSelect: insertEmote,
                    onDismiss: dismissEmotePanel
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            attachmentPreview

            HStack(alignment: .bottom, spacing: 8) {
                Button(action: endComposing) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("收起评论输入")

                TextField("发表评论", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($isEditorFocused)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        Color(uiColor: .secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .accessibilityLabel("评论内容")
                    .accessibilityIdentifier("dynamic.detail.composer.editor")

                Button {
                    withAnimation(.smooth) {
                        showsEmotePanel.toggle()
                    }
                    isEditorFocused = false
                } label: {
                    Image(systemName: "face.smiling")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("选择表情")

                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: 9,
                    matching: .images,
                    preferredItemEncoding: .current
                ) {
                    Image(systemName: "photo")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .simultaneousGesture(TapGesture().onEnded {
                    showsEmotePanel = false
                    isEditorFocused = false
                })
                .accessibilityLabel("添加图片")

                Button(action: submitDraft) {
                    if composerState == .sending || isLoadingImages {
                        ProgressView()
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .disabled(!canSend)
                .accessibilityLabel(composerState == .sending ? "正在发送评论" : "发送评论")
                .accessibilityIdentifier("dynamic.detail.composer.send")
            }
        }
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
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .foregroundStyle(likeState.isLiked ? appTintColor : .primary)
        .disabled(isMutatingLike)
        .accessibilityLabel(likeState.isLiked ? "取消点赞" : "点赞")
        .accessibilityValue("\(likeState.isLiked ? "已点赞" : "未点赞")，\(likeState.likeCount) 个赞")
        .accessibilityAddTraits(likeState.isLiked ? .isSelected : [])
        .contentTransition(.symbolEffect(.replace))
    }

    private var favoriteButton: some View {
        Button {
            message = "动态收藏暂未接入"
        } label: {
            Image(systemName: "star")
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .foregroundStyle(.secondary)
        .accessibilityLabel("收藏")
        .accessibilityValue("动态收藏暂未接入")
    }

    private var sourceLikeState: DynamicLikeDisplayState {
        DynamicLikeDisplayState(isLiked: initialIsLiked, likeCount: initialLikeCount)
    }

    private func beginComposing() {
        guard canComment else { return }
        composerState = .composing
        showsEmotePanel = false
        Task { @MainActor in
            await Task.yield()
            isEditorFocused = true
        }
    }

    private func endComposing() {
        showsEmotePanel = false
        isEditorFocused = false
        if normalizedDraft.isEmpty && attachedImageDatas.isEmpty {
            composerState = .idle
        } else {
            composerState = .composing
        }
    }

    private func dismissEmotePanel() {
        withAnimation(.smooth) {
            showsEmotePanel = false
        }
        isEditorFocused = true
    }

    private func insertEmote(_ token: String) {
        draft += token
        dismissEmotePanel()
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
            showsEmotePanel = false
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
                showsEmotePanel = false
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

private struct DynamicDetailComposerEmotePanel: View {
    let emotes: [BiliInlineEmote]
    let onSelect: (String) -> Void
    let onDismiss: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(minimum: 44), spacing: 10), count: 5)

    var body: some View {
        ZStack(alignment: .bottom) {
            if emotes.isEmpty {
                ContentUnavailableView("暂无可用表情", systemImage: "face.smiling")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(emotes, id: \.token) { emote in
                            Button {
                                onSelect(emote.token)
                            } label: {
                                VStack(spacing: 5) {
                                    CachedRemoteImage(
                                        url: emote.displayURL.flatMap { URL(string: $0) },
                                        targetPixelSize: 88
                                    ) { image in
                                        image.resizable().scaledToFit()
                                    } placeholder: {
                                        Image(systemName: "face.smiling")
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(width: 38, height: 38)
                                    Text(emote.token)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, minHeight: 62)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }

            Button(action: onDismiss) {
                Image(systemName: "chevron.down")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .accessibilityLabel("收起表情选择器")
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .clipShape(.rect(cornerRadius: 28, style: .continuous))
    }
}
