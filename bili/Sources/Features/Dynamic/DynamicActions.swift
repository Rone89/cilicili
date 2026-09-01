import SwiftUI

struct DynamicFeedActionBar: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var sessionStore: SessionStore
    let display: DynamicFeedCardDisplayModel
    let initialIsLiked: Bool
    let initialLikeCount: Int
    let onShowComments: () -> Void
    @State private var likeState: DynamicLikeDisplayState
    @State private var isMutatingLike = false
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
        _likeState = State(initialValue: DynamicLikeDisplayState(
            isLiked: initialIsLiked,
            likeCount: initialLikeCount
        ))
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
                    title: DynamicFeedCardDisplayModel.statTitle(count: likeState.likeCount, fallback: "点赞"),
                    systemImage: likeState.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
                    isSelected: likeState.isLiked,
                    isDisabled: isMutatingLike
                ) {
                    toggleLike()
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
        .onChange(of: sourceLikeState) { _, state in
            guard !isMutatingLike else { return }
            likeState = state
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

    private var sourceLikeState: DynamicLikeDisplayState {
        DynamicLikeDisplayState(isLiked: initialIsLiked, likeCount: initialLikeCount)
    }

    private func toggleLike() {
        playActionFeedback()
        let account = sessionStore.credentialSnapshot(
            for: .interaction,
            multiAccountEnabled: libraryStore.multiAccountExperimentEnabled
        )
        guard account.isLoggedIn else {
            showActionMessage("请先登录账号", playsFeedback: false)
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
                showActionMessage(targetState.isLiked ? "已点赞" : "已取消点赞", playsFeedback: false)
            } catch {
                withAnimation(.snappy(duration: 0.2)) {
                    likeState = previousState
                }
                showActionMessage("操作失败：\(error.localizedDescription)", playsFeedback: false)
            }
            isMutatingLike = false
        }
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

nonisolated struct DynamicLikeDisplayState: Equatable, Sendable {
    let isLiked: Bool
    let likeCount: Int

    func toggled() -> DynamicLikeDisplayState {
        DynamicLikeDisplayState(
            isLiked: !isLiked,
            likeCount: max(0, likeCount + (isLiked ? -1 : 1))
        )
    }
}

struct DynamicDetailActionBar: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.appThemeTintColor) private var appTintColor
    let display: DynamicFeedCardDisplayModel
    let initialIsLiked: Bool
    let initialLikeCount: Int
    @State private var likeState: DynamicLikeDisplayState
    @State private var isMutatingLike = false
    @State private var actionMessage: String?
    @State private var actionMessageTask: Task<Void, Never>?

    init(
        display: DynamicFeedCardDisplayModel,
        initialIsLiked: Bool,
        initialLikeCount: Int
    ) {
        self.display = display
        self.initialIsLiked = initialIsLiked
        self.initialLikeCount = initialLikeCount
        _likeState = State(initialValue: DynamicLikeDisplayState(
            isLiked: initialIsLiked,
            likeCount: initialLikeCount
        ))
    }

    var body: some View {
        HStack(spacing: 4) {
            shareButton
            iconButton(
                systemImage: likeState.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
                accessibilityLabel: likeState.isLiked ? "取消点赞" : "点赞",
                isSelected: likeState.isLiked,
                isDisabled: isMutatingLike,
                action: toggleLike
            )
            iconButton(
                systemImage: "star",
                accessibilityLabel: "收藏"
            ) {
                showActionMessage("动态收藏暂未接入")
            }

            Button {
                showActionMessage("评论回复功能即将开放")
            } label: {
                Label("评论回复", systemImage: "bubble.left")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
            .contentShape(Capsule())
            .accessibilityIdentifier("dynamic.detail.commentReplyPlaceholder")
        }
        .padding(6)
        .biliBottomTabGlassEffect(interactive: true, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        .overlay(alignment: .top) {
            if let actionMessage {
                DynamicActionFeedbackToast(message: actionMessage)
                    .offset(y: -42)
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottom)))
                    .allowsHitTesting(false)
            }
        }
        .onDisappear {
            actionMessageTask?.cancel()
            actionMessageTask = nil
        }
        .onChange(of: sourceLikeState) { _, state in
            guard !isMutatingLike else { return }
            likeState = state
        }
        .accessibilityIdentifier("dynamic.detail.bottomActionBar")
    }

    @ViewBuilder
    private var shareButton: some View {
        if let url = display.shareURL {
            ShareLink(
                item: url,
                subject: Text(display.shareTitle),
                message: Text(display.shareMessage)
            ) {
                actionIcon(systemImage: "square.and.arrow.up", isSelected: false)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { Haptics.light() })
            .accessibilityLabel("分享动态")
        } else {
            iconButton(systemImage: "square.and.arrow.up", accessibilityLabel: "分享动态") {
                showActionMessage("暂无可分享链接")
            }
        }
    }

    private func iconButton(
        systemImage: String,
        accessibilityLabel: String,
        isSelected: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            actionIcon(systemImage: systemImage, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
    }

    private func actionIcon(systemImage: String, isSelected: Bool) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(isSelected ? appTintColor : Color.primary)
            .frame(width: 40, height: 40)
            .contentShape(Circle())
    }

    private var sourceLikeState: DynamicLikeDisplayState {
        DynamicLikeDisplayState(isLiked: initialIsLiked, likeCount: initialLikeCount)
    }

    private func toggleLike() {
        Haptics.light()
        let account = sessionStore.credentialSnapshot(
            for: .interaction,
            multiAccountEnabled: libraryStore.multiAccountExperimentEnabled
        )
        guard account.isLoggedIn else {
            showActionMessage("请先登录账号", playsFeedback: false)
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
                showActionMessage(targetState.isLiked ? "已点赞" : "已取消点赞", playsFeedback: false)
            } catch {
                withAnimation(.snappy(duration: 0.2)) {
                    likeState = previousState
                }
                showActionMessage("操作失败：\(error.localizedDescription)", playsFeedback: false)
            }
            isMutatingLike = false
        }
    }

    private func showActionMessage(_ message: String, playsFeedback: Bool = true) {
        if playsFeedback {
            Haptics.light()
        }
        actionMessageTask?.cancel()
        withAnimation(.snappy(duration: 0.18)) {
            actionMessage = message
        }
        actionMessageTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.18)) {
                actionMessage = nil
            }
        }
    }
}
