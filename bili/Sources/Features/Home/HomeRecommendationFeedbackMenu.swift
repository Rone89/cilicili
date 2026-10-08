import SwiftUI

struct HomeRecommendationFeedbackActions {
    let canSubmit: Bool
    let canSynchronizeBlock: Bool
    let isBusy: Bool
    let submit: (VideoItem, RecommendationFeedbackKind, RecommendationFeedbackReason) async -> Void
    let block: (VideoOwner, Bool) async -> Void
}

struct HomeRecommendationFeedbackMenu: ViewModifier {
    @EnvironmentObject private var libraryStore: LibraryStore
    let video: VideoItem
    let actions: HomeRecommendationFeedbackActions?
    let onTap: () -> Void
    let onPress: () -> Void
    @State private var showsBlockConfirmation = false
    @State private var showsFeedbackReasons = false

    func body(content: Content) -> some View {
        if libraryStore.homeRecommendationFeedbackContextMenuExperimentEnabled, let actions,
           (video.owner?.mid ?? 0) > 0 || (actions.canSubmit && video.recommendationFeedback?.hasReasons == true) {
            content.overlay {
                // The system lifts this transparent button, leaving the visible card in place.
                Button(action: onTap) { Color.clear }
                    .buttonStyle(PressPreloadButtonStyle(onPress: onPress))
                    .contentShape(Rectangle())
                    .contentShape(.contextMenuPreview, Path())
                    .contextMenu {
                        if actions.canSubmit, let feedback = video.recommendationFeedback, feedback.hasReasons {
                            Menu {
                                reasonMenu(feedback, actions: actions)
                            } label: {
                                Label("不感兴趣", systemImage: "hand.thumbsdown")
                            }
                            .disabled(actions.isBusy)
                        }
                        if let owner = video.owner, owner.mid > 0 {
                            Button {
                                showsBlockConfirmation = true
                            } label: {
                                Label("屏蔽该 UP", systemImage: "person.crop.circle.badge.xmark")
                            }
                            .disabled(actions.isBusy)
                        }
                    }
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityActions {
                if (video.owner?.mid ?? 0) > 0, !actions.isBusy {
                    Button("屏蔽该 UP") { showsBlockConfirmation = true }
                }
                if actions.canSubmit, !actions.isBusy, video.recommendationFeedback?.hasReasons == true {
                    Button("不感兴趣") { showsFeedbackReasons = true }
                }
            }
            .confirmationDialog(blockTitle, isPresented: $showsBlockConfirmation, titleVisibility: .visible) {
                if let owner = video.owner {
                    Button("仅在本机屏蔽", role: .destructive) {
                        Task { await actions.block(owner, false) }
                    }
                    if actions.canSynchronizeBlock {
                        Button("拉黑并同步到 Bilibili", role: .destructive) {
                            Task { await actions.block(owner, true) }
                        }
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("之后首页推荐将不再显示该 UP 的内容。")
            }
            .confirmationDialog("不感兴趣", isPresented: $showsFeedbackReasons, titleVisibility: .visible) {
                if let feedback = video.recommendationFeedback { reasonButtons(feedback, actions: actions) }
                Button("取消", role: .cancel) {}
            }
        } else {
            content
        }
    }

    private var blockTitle: String {
        let name = video.owner?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty || name == "Unknown" ? "屏蔽该 UP？" : "屏蔽「\(name)」？"
    }

    @ViewBuilder
    private func reasonMenu(_ feedback: HomeRecommendationFeedbackMetadata, actions: HomeRecommendationFeedbackActions) -> some View {
        ForEach([RecommendationFeedbackKind.dislike, .feedback], id: \.self) { kind in
            let reasons = feedback.reasons(for: kind)
            if !reasons.isEmpty {
                Section(kind == .dislike ? "不想看" : "反馈") {
                    ForEach(reasons) { reason in
                        Button(reason.name!) { Task { await actions.submit(video, kind, reason) } }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func reasonButtons(_ feedback: HomeRecommendationFeedbackMetadata, actions: HomeRecommendationFeedbackActions) -> some View {
        ForEach([RecommendationFeedbackKind.dislike, .feedback], id: \.self) { kind in
            ForEach(feedback.reasons(for: kind)) { reason in
                Button(reason.name!) { Task { await actions.submit(video, kind, reason) } }
            }
        }
    }
}
