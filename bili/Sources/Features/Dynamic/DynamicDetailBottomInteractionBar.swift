import SwiftUI

struct DynamicDetailBottomInteractionBar: View {
    private enum Metrics {
        static let controlSide: CGFloat = 44
        static let groupSpacing: CGFloat = 8
    }

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

    var body: some View {
        GlassEffectContainer(spacing: Metrics.groupSpacing) {
            if isComposerPresented {
                composer
            } else {
                defaultActions
            }
        }
        .padding(.horizontal, 4)
        .animation(.smooth(duration: 0.22), value: isComposerPresented)
        .accessibilityIdentifier("dynamic.detail.experimental.bottom-interaction-bar")
        .alert("评论失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "请稍后重试")
        }
    }

    private var defaultActions: some View {
        HStack(spacing: Metrics.groupSpacing) {
            interactionButton(
                systemImage: likeState.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
                label: likeState.isLiked ? "点赞，已点赞" : "点赞，未点赞",
                value: "\(likeState.likeCount) 个赞",
                selected: likeState.isLiked,
                disabled: isMutatingLike,
                action: toggleLike
            )
            .buttonBorderShape(.circle)

            Button(action: openComposer) {
                Label(
                    commentCount > 0 ? BiliFormatters.compactCount(commentCount) : "评论",
                    systemImage: "bubble.left"
                )
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: Metrics.controlSide)
                .padding(.horizontal, 12)
            }
            .biliGlassButtonStyle()
            .buttonBorderShape(.capsule)
            .accessibilityLabel("评论")
            .accessibilityValue("共 \(commentCount) 条")
            .disabled(!canComment)

            Button {
                errorMessage = "动态收藏接口暂未提供"
            } label: {
                Image(systemName: "star")
                    .frame(width: Metrics.controlSide, height: Metrics.controlSide)
            }
            .biliGlassButtonStyle()
            .buttonBorderShape(.circle)
            .accessibilityLabel("收藏")
            .accessibilityValue("动态收藏不可用")
        }
    }

    private var composer: some View {
        HStack(spacing: Metrics.groupSpacing) {
            Button {
                isCommentFieldFocused = false
                isComposerPresented = false
            } label: {
                Image(systemName: "xmark")
                    .frame(width: Metrics.controlSide, height: Metrics.controlSide)
            }
            .buttonStyle(.plain)
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
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .frame(width: Metrics.controlSide, height: Metrics.controlSide)
            .disabled(isSubmittingComment || commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("发送评论")
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 56)
        .biliGlassButtonStyle()
        .glassEffectID("dynamic-comment-composer", in: composerNamespace)
    }

    @Namespace private var composerNamespace

    private func interactionButton(
        systemImage: String,
        label: String,
        value: String,
        selected: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: Metrics.controlSide, height: Metrics.controlSide)
        }
        .biliGlassButtonStyle()
        .foregroundStyle(selected ? appTintColor : .primary)
        .disabled(disabled)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
