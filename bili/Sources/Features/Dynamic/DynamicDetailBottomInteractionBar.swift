import SwiftUI

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
    let submitComment: (String) async throws -> Void

    @State private var likeState: DynamicLikeDisplayState
    @State private var isMutatingLike = false
    @State private var isComposerPresented = false
    @State private var commentDraft = ""
    @State private var isSubmittingComment = false
    @State private var errorMessage: String?
    @FocusState private var isCommentFieldFocused: Bool

    init(
        display: DynamicFeedCardDisplayModel,
        initialIsLiked: Bool,
        initialLikeCount: Int,
        commentCount: Int,
        canComment: Bool,
        submitComment: @escaping (String) async throws -> Void
    ) {
        self.display = display
        self.initialIsLiked = initialIsLiked
        self.initialLikeCount = initialLikeCount
        self.commentCount = commentCount
        self.canComment = canComment
        self.submitComment = submitComment
        _likeState = State(initialValue: DynamicLikeDisplayState(
            isLiked: initialIsLiked,
            likeCount: initialLikeCount
        ))
    }

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        if isComposerPresented {
            ToolbarItem(placement: .bottomBar) {
                composer
            }
        } else {
            ToolbarItem(placement: .bottomBar) {
                likeButton
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                commentButton
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                favoriteButton
            }
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
        .alert("评论失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "请稍后重试")
        }
    }

    private var commentButton: some View {
        Button(action: openComposer) {
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

    private var favoriteButton: some View {
        Button {
            errorMessage = "动态收藏接口暂未提供"
        } label: {
            Image(systemName: "star")
                .font(.body)
        }
        .controlSize(.small)
        .imageScale(.medium)
        .foregroundStyle(.primary)
        .accessibilityLabel("收藏")
        .accessibilityValue("动态收藏不可用")
    }

    private var composer: some View {
        HStack {
            Button {
                isCommentFieldFocused = false
                isComposerPresented = false
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("取消评论")

            TextField("友善发言，理性讨论", text: $commentDraft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
                .focused($isCommentFieldFocused)
                .submitLabel(.send)
                .accessibilityLabel("评论内容")
                .onSubmit { submitCommentIfPossible() }

            Button(action: submitCommentIfPossible) {
                if isSubmittingComment {
                    ProgressView()
                } else {
                    Image(systemName: "paperplane.fill")
                }
            }
            .disabled(isSubmittingComment || commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("发送评论")
        }
    }

    private func openComposer() {
        guard canComment else { return }
        isComposerPresented = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard isComposerPresented else { return }
            isCommentFieldFocused = true
        }
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

    private func submitCommentIfPossible() {
        let message = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isSubmittingComment else { return }
        isSubmittingComment = true
        Task { @MainActor in
            do {
                try await submitComment(message)
                commentDraft = ""
                isCommentFieldFocused = false
                isComposerPresented = false
                Haptics.success()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmittingComment = false
        }
    }
}
