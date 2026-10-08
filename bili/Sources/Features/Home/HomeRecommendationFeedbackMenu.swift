import SwiftUI
import UIKit

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
    @State private var isMenuPresented = false
    @State private var showsBlockConfirmation = false
    @State private var showsFeedbackReasons = false

    func body(content: Content) -> some View {
        if libraryStore.homeRecommendationFeedbackContextMenuExperimentEnabled, let actions,
           (video.owner?.mid ?? 0) > 0 || (actions.canSubmit && video.recommendationFeedback?.hasReasons == true) {
            content
            .overlay {
                HomeRecommendationMenuInteraction(
                    menu: { nativeMenu(actions: actions) },
                    onTap: onTap,
                    onPress: onPress,
                    onPresentationChange: { isMenuPresented = $0 }
                )
                .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(isMenuPresented ? "菜单已打开" : "")
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

    private func nativeMenu(actions: HomeRecommendationFeedbackActions) -> UIMenu {
        var items = [UIMenuElement]()
        let attributes: UIMenuElement.Attributes = actions.isBusy ? [.disabled] : []
        if actions.canSubmit, let feedback = video.recommendationFeedback, feedback.hasReasons {
            let groups = [RecommendationFeedbackKind.dislike, .feedback].compactMap { kind -> UIMenu? in
                let reasons = feedback.reasons(for: kind).map { reason in
                    UIAction(title: reason.name!, attributes: attributes) { _ in
                        Task { await actions.submit(video, kind, reason) }
                    }
                }
                guard !reasons.isEmpty else { return nil }
                return UIMenu(title: kind == .dislike ? "不想看" : "反馈", options: .displayInline, children: reasons)
            }
            items.append(UIMenu(title: "不感兴趣", image: UIImage(systemName: "hand.thumbsdown"), children: groups))
        }
        if let owner = video.owner, owner.mid > 0 {
            var blockActions: [UIMenuElement] = [
                UIAction(title: "仅在本机屏蔽", image: UIImage(systemName: "iphone"), attributes: attributes.union(.destructive)) { _ in
                    Task { await actions.block(owner, false) }
                }
            ]
            if actions.canSynchronizeBlock {
                blockActions.append(UIAction(title: "拉黑并同步到 Bilibili", image: UIImage(systemName: "person.crop.circle.badge.xmark"), attributes: attributes.union(.destructive)) { _ in
                    Task { await actions.block(owner, true) }
                })
            }
            items.append(UIMenu(title: "屏蔽该 UP", image: UIImage(systemName: "person.crop.circle.badge.xmark"), children: [
                UIMenu(title: blockTitle + "\n之后首页推荐将不再显示该 UP 的内容。", options: .displayInline, children: blockActions)
            ]))
        }
        return UIMenu(children: items)
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

/// The selected card preview stays above the system dimming surface.
/// No custom long-press recognizer or app-wide dimming overlay is used.
private struct HomeRecommendationMenuInteraction: UIViewRepresentable {
    let menu: () -> UIMenu
    let onTap: () -> Void
    let onPress: () -> Void
    let onPresentationChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .custom)
        button.backgroundColor = .clear
        button.isAccessibilityElement = false
        button.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
        button.addTarget(context.coordinator, action: #selector(Coordinator.press), for: .touchDown)
        button.addInteraction(UIContextMenuInteraction(delegate: context.coordinator))
        return button
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleUIView(_ button: UIButton, coordinator: Coordinator) {
        coordinator.removeHighlight()
    }

    final class Coordinator: NSObject, UIContextMenuInteractionDelegate {
        var parent: HomeRecommendationMenuInteraction
        private var isPresentingMenu = false
        private let previewImage = UIImageView()
        private let emptyPreview = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))

        init(_ parent: HomeRecommendationMenuInteraction) { self.parent = parent }
        @objc func tap() {
            guard !isPresentingMenu else { return }
            parent.onTap()
        }
        @objc func press() { parent.onPress() }

        func removeHighlight() {
            previewImage.removeFromSuperview()
            previewImage.image = nil
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
            isPresentingMenu = true
            captureCard(interaction)
            return UIContextMenuConfiguration(identifier: "homeRecommendation" as NSString, previewProvider: { [weak self] in
                guard let self else { return nil }
                let controller = UIViewController()
                controller.view.backgroundColor = .clear
                controller.preferredContentSize = self.previewImage.bounds.size
                return controller
            }) { [weak self] _ in
                self?.parent.menu()
            }
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configuration: UIContextMenuConfiguration, highlightPreviewForItemWithIdentifier identifier: NSCopying) -> UITargetedPreview? {
            cardPreview(interaction)
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configuration: UIContextMenuConfiguration, dismissalPreviewForItemWithIdentifier identifier: NSCopying) -> UITargetedPreview? {
            cardPreview(interaction)
        }

        private func captureCard(_ interaction: UIContextMenuInteraction) {
            guard let source = interaction.view, let window = source.window,
                  source.bounds.width > 0, source.bounds.height > 0 else { return }
            let rect = source.convert(source.bounds, to: window)
            let format = UIGraphicsImageRendererFormat()
            format.scale = source.traitCollection.displayScale
            previewImage.image = UIGraphicsImageRenderer(size: rect.size, format: format).image { context in
                context.cgContext.translateBy(x: -rect.minX, y: -rect.minY)
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
            }
            emptyPreview.frame = CGRect(origin: .zero, size: rect.size)
            previewImage.frame = rect
            previewImage.isUserInteractionEnabled = false
            previewImage.isAccessibilityElement = false
            previewImage.layer.cornerRadius = 18
            previewImage.layer.cornerCurve = .continuous
            previewImage.clipsToBounds = true
            previewImage.backgroundColor = .clear
        }

        private func cardPreview(_ interaction: UIContextMenuInteraction) -> UITargetedPreview? {
            guard let source = interaction.view, let window = source.window,
                  previewImage.image != nil else { return nil }
            let parameters = UIPreviewParameters()
            parameters.backgroundColor = .clear
            parameters.visiblePath = UIBezierPath(rect: CGRect(x: 0, y: 0, width: 1, height: 1))
            parameters.shadowPath = UIBezierPath()
            let center = source.convert(CGPoint(x: source.bounds.midX, y: source.bounds.midY), to: window)
            let target = UIPreviewTarget(container: window, center: center)
            return UITargetedPreview(view: emptyPreview, parameters: parameters, target: target)
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willDisplayMenuFor configuration: UIContextMenuConfiguration, animator: (any UIContextMenuInteractionAnimating)?) {
            parent.onPresentationChange(true)
            // Keep the selected card at its original position above the system dimming.
            // The menu has no content preview to lift, resize, or relocate.
            let showHighlight = { [weak self, weak interaction] in
                guard let self, let window = interaction?.view?.window else { return }
                window.addSubview(self.previewImage)
            }
            if let animator {
                animator.addCompletion(showHighlight)
            } else {
                showHighlight()
            }
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willEndFor configuration: UIContextMenuConfiguration, animator: (any UIContextMenuInteractionAnimating)?) {
            if let animator {
                animator.addCompletion { [weak self] in
                    self?.isPresentingMenu = false
                    self?.parent.onPresentationChange(false)
                    self?.removeHighlight()
                }
            } else {
                isPresentingMenu = false
                parent.onPresentationChange(false)
                removeHighlight()
            }
        }
    }
}
