import Combine
import SwiftUI
import UIKit

struct VideoDetailSplitSelectionSheetPayload: Identifiable {
    let id = UUID()
    let sectionTitle: String
    let items: [VideoDetailCompactSelectionItem]
    let selectItem: (VideoDetailCompactSelectionItem) -> Void
}

struct VideoDetailSplitCommentDialogPayload: Identifiable {
    let id = UUID()
    let rootComment: Comment
    let focusReply: Comment
    let store: VideoDetailCommentThreadRenderStore
    let loadDialog: (Comment, Comment) async -> Void
    let reloadDialog: (Comment, Comment) async -> Void
    let submitReply: (DynamicCommentComposerTarget, String, [DynamicCommentImage]?) async throws -> Void
}

struct VideoDetailSplitInlineComposerPayload {
    let ownerID: ObjectIdentifier
    let targetID: String
    let content: AnyView
    let onDismiss: () -> Void
}

/// Coordinates modal presentations scoped strictly to the right-hand detail/comments
/// column while `VideoDetailSwiftUIContainer` is in landscape `.twoColumnSplit`,
/// ensuring popups never cover the left-hand video player.
@MainActor
final class VideoDetailSplitColumnOverlayController: ObservableObject {
    @Published var isSplitColumnMode = false
    @Published var selectionSheet: VideoDetailSplitSelectionSheetPayload?
    @Published var commentDialogSheet: VideoDetailSplitCommentDialogPayload?
    @Published var inlineComposer: VideoDetailSplitInlineComposerPayload?
    /// Non-published snapshot of the maximum sheet detent height below the video player
    /// in stacked (portrait) mode, read at sheet presentation time without causing scroll re-renders.
    private(set) var stackedBelowPlayerSheetMaxHeight: CGFloat?

    var hasActiveOverlay: Bool {
        selectionSheet != nil || commentDialogSheet != nil || inlineComposer != nil
    }

    func updateStackedBelowPlayerSheetMaxHeight(_ height: CGFloat?) {
        stackedBelowPlayerSheetMaxHeight = height
    }

    func setSplitColumnMode(_ active: Bool) {
        guard isSplitColumnMode != active else { return }
        isSplitColumnMode = active
        if !active {
            dismissAll()
        }
    }

    func presentInlineComposer(
        ownerID: ObjectIdentifier,
        targetID: String,
        content: AnyView,
        onDismiss: @escaping () -> Void
    ) {
        inlineComposer = VideoDetailSplitInlineComposerPayload(
            ownerID: ownerID,
            targetID: targetID,
            content: content,
            onDismiss: onDismiss
        )
    }

    func dismissInlineComposerIfOwned(by ownerID: ObjectIdentifier) {
        guard inlineComposer?.ownerID == ownerID else { return }
        inlineComposer = nil
    }

    func dismissAll() {
        selectionSheet = nil
        commentDialogSheet = nil
        if let composer = inlineComposer {
            inlineComposer = nil
            composer.onDismiss()
        }
    }
}

extension EnvironmentValues {
    @Entry var videoDetailSplitColumnOverlay: VideoDetailSplitColumnOverlayController? = nil
    @Entry var videoDetailSplitSheetDismiss: (() -> Void)? = nil
}

/// Independent UIKit overlay container mounted strictly over `layout.contentFrame`
/// inside `VideoDetailSwiftUIContainerViewController`.
///
/// Hosting right-column sheets in a sibling UIKit child controller decouples sheet
/// presentation, Liquid Glass rendering (`UIGlassEffect`), and 120Hz pan gestures
/// from `VideoDetailSwiftUIContainer`'s live video player tree.
@MainActor
final class VideoDetailSplitColumnSheetContainerController: UIViewController {
    private let overlay: VideoDetailSplitColumnOverlayController
    private let viewModel: VideoDetailViewModel
    private let dependencies: AppDependencies
    private let submitReply: (DynamicCommentComposerTarget, String, [DynamicCommentImage]?) async throws -> Void
    private let onDismissCommentThreadRoute: () -> Void

    private var cancellables = Set<AnyCancellable>()
    private var selectionSheetPresenter: SplitLiquidGlassSheetPresenter?
    private var commentThreadPresenter: SplitLiquidGlassSheetPresenter?
    private var commentDialogPresenter: SplitLiquidGlassSheetPresenter?
    private var inlineComposerHost: UIHostingController<AnyView>?

    private var activeSelectionID: UUID?
    private var activeCommentThreadID: UUID?
    private var activeCommentDialogID: UUID?
    private var activeInlineComposerTargetID: String?
    private var currentCommentThreadPresentation: VideoDetailCommentThreadSheetPresentation?
    private var currentSheetHeightFraction: CGFloat = 0.94

    var hasVisibleOverlay: Bool {
        selectionSheetPresenter != nil
            || commentThreadPresenter != nil
            || commentDialogPresenter != nil
            || inlineComposerHost != nil
    }

    init(
        overlay: VideoDetailSplitColumnOverlayController,
        viewModel: VideoDetailViewModel,
        dependencies: AppDependencies,
        submitReply: @escaping (DynamicCommentComposerTarget, String, [DynamicCommentImage]?) async throws -> Void,
        onDismissCommentThreadRoute: @escaping () -> Void
    ) {
        self.overlay = overlay
        self.viewModel = viewModel
        self.dependencies = dependencies
        self.submitReply = submitReply
        self.onDismissCommentThreadRoute = onDismissCommentThreadRoute
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let passthroughView = PassthroughSplitOverlayView()
        passthroughView.backgroundColor = .clear
        passthroughView.clipsToBounds = true
        view = passthroughView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        bindOverlayState()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        selectionSheetPresenter?.layout(in: bounds)
        commentThreadPresenter?.layout(in: bounds)
        commentDialogPresenter?.layout(in: bounds)
        inlineComposerHost?.view.frame = bounds
    }

    func updateGeometry(
        frame: CGRect,
        isSplitActive: Bool,
        sheetHeightFraction: CGFloat = 0.94
    ) {
        let fractionChanged = abs(currentSheetHeightFraction - sheetHeightFraction) > 0.005
        currentSheetHeightFraction = sheetHeightFraction
        if view.frame != frame || fractionChanged {
            view.frame = frame
            selectionSheetPresenter?.updateHeightFraction(sheetHeightFraction)
            commentThreadPresenter?.updateHeightFraction(sheetHeightFraction)
            commentDialogPresenter?.updateHeightFraction(sheetHeightFraction)
            view.setNeedsLayout()
        }
        view.isHidden = !isSplitActive
        overlay.setSplitColumnMode(isSplitActive)
        syncCommentThreadIfNeeded()
    }

    func updateCommentThreadPresentation(_ presentation: VideoDetailCommentThreadSheetPresentation?) {
        currentCommentThreadPresentation = presentation
        syncCommentThreadIfNeeded()
    }

    private func bindOverlayState() {
        overlay.$selectionSheet
            .receive(on: RunLoop.main)
            .sink { [weak self] payload in
                self?.syncSelectionSheet(payload)
            }
            .store(in: &cancellables)

        overlay.$commentDialogSheet
            .receive(on: RunLoop.main)
            .sink { [weak self] payload in
                self?.syncCommentDialog(payload)
            }
            .store(in: &cancellables)

        overlay.$inlineComposer
            .receive(on: RunLoop.main)
            .sink { [weak self] payload in
                self?.syncInlineComposer(payload)
            }
            .store(in: &cancellables)

        overlay.$isSplitColumnMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncCommentThreadIfNeeded()
            }
            .store(in: &cancellables)
    }

    private var videoReferer: String {
        let bvid = viewModel.detail.bvid.trimmingCharacters(in: .whitespacesAndNewlines)
        return bvid.isEmpty ? "https://www.bilibili.com" : "https://www.bilibili.com/video/\(bvid)"
    }

    private func wrappedEnvironment<V: View>(_ content: V, onDismiss: @escaping () -> Void) -> AnyView {
        AnyView(
            content
                .environmentObject(dependencies)
                .environmentObject(dependencies.libraryStore)
                .environmentObject(dependencies.sessionStore)
                .environment(\.appThemeTintColor, dependencies.libraryStore.appTintColor)
                .environment(\.videoDetailSplitColumnOverlay, overlay)
                .environment(\.videoDetailSplitSheetDismiss, onDismiss)
                .environment(
                    \.videoDetailStandardHorizontalInset,
                    dependencies.libraryStore.standardPageHorizontalInset
                )
                .environment(\.commentContentOwnerMID, viewModel.detail.owner?.mid)
                .commentLikeTarget(
                    oid: viewModel.commentTarget?.oid,
                    type: viewModel.commentTarget?.type,
                    referer: videoReferer
                )
                .scrollEdgeEffectStyle(.soft, for: .top)
        )
    }

    private func syncSelectionSheet(_ payload: VideoDetailSplitSelectionSheetPayload?) {
        guard overlay.isSplitColumnMode, let payload else {
            activeSelectionID = nil
            selectionSheetPresenter?.dismiss(animated: true)
            selectionSheetPresenter = nil
            return
        }
        guard payload.id != activeSelectionID else { return }
        activeSelectionID = payload.id
        selectionSheetPresenter?.dismiss(animated: false)

        let onDismiss: () -> Void = { [weak self] in
            self?.overlay.selectionSheet = nil
        }
        let root = wrappedEnvironment(
            VideoDetailCompactSelectionSheet(
                sectionTitle: payload.sectionTitle,
                items: payload.items,
                selectItem: payload.selectItem
            ),
            onDismiss: onDismiss
        )
        let presenter = SplitLiquidGlassSheetPresenter(
            parent: self,
            rootView: root,
            heightFraction: currentSheetHeightFraction,
            onDismissRequest: onDismiss
        )
        selectionSheetPresenter = presenter
        presenter.present(in: view, animated: true)
        reorderOverlayLayers()
    }

    private func syncCommentThreadIfNeeded() {
        guard overlay.isSplitColumnMode, let presentation = currentCommentThreadPresentation else {
            activeCommentThreadID = nil
            commentThreadPresenter?.dismiss(animated: true)
            commentThreadPresenter = nil
            return
        }
        guard presentation.id != activeCommentThreadID else { return }
        activeCommentThreadID = presentation.id
        commentThreadPresenter?.dismiss(animated: false)

        let onDismiss: () -> Void = { [weak self] in
            guard let self else { return }
            self.overlay.commentDialogSheet = nil
            self.viewModel.clearDeepLinkCommentThreadAnchor()
            self.onDismissCommentThreadRoute()
        }
        let actions = VideoDetailSheetActions(viewModel: viewModel)
        let comment = presentation.rootComment
        let inner: AnyView
        if let replyID = presentation.secondaryID,
           let reply = viewModel.replies(for: comment).first(where: { $0.id == replyID }) {
            inner = wrappedEnvironment(
                CommentDialogSheet(
                    rootComment: comment,
                    focusReply: reply,
                    store: viewModel.commentThreadRenderStore,
                    loadDialog: actions.replies.loadDialog,
                    reloadDialog: actions.replies.reloadDialog,
                    submitReply: submitReply
                ),
                onDismiss: onDismiss
            )
        } else {
            inner = wrappedEnvironment(
                VideoDetailReplySheetHost(
                    rootComment: comment,
                    viewModel: viewModel,
                    initialReplyID: nil,
                    actions: actions.replies,
                    submitReply: submitReply
                ),
                onDismiss: onDismiss
            )
        }

        let presenter = SplitLiquidGlassSheetPresenter(
            parent: self,
            rootView: inner,
            heightFraction: currentSheetHeightFraction,
            onDismissRequest: onDismiss
        )
        commentThreadPresenter = presenter
        presenter.present(in: view, animated: true)
        reorderOverlayLayers()
    }

    private func syncCommentDialog(_ payload: VideoDetailSplitCommentDialogPayload?) {
        guard overlay.isSplitColumnMode, let payload else {
            activeCommentDialogID = nil
            commentDialogPresenter?.dismiss(animated: true)
            commentDialogPresenter = nil
            return
        }
        guard payload.id != activeCommentDialogID else { return }
        activeCommentDialogID = payload.id
        commentDialogPresenter?.dismiss(animated: false)

        let onDismiss: () -> Void = { [weak self] in
            self?.overlay.commentDialogSheet = nil
        }
        let root = wrappedEnvironment(
            CommentDialogSheet(
                rootComment: payload.rootComment,
                focusReply: payload.focusReply,
                store: payload.store,
                loadDialog: payload.loadDialog,
                reloadDialog: payload.reloadDialog,
                submitReply: payload.submitReply
            ),
            onDismiss: onDismiss
        )
        let presenter = SplitLiquidGlassSheetPresenter(
            parent: self,
            rootView: root,
            heightFraction: currentSheetHeightFraction,
            onDismissRequest: onDismiss
        )
        commentDialogPresenter = presenter
        presenter.present(in: view, animated: true)
        reorderOverlayLayers()
    }

    private func syncInlineComposer(_ payload: VideoDetailSplitInlineComposerPayload?) {
        guard overlay.isSplitColumnMode, let payload else {
            activeInlineComposerTargetID = nil
            removeInlineComposerHost()
            return
        }
        let wrapped = wrappedEnvironment(payload.content, onDismiss: payload.onDismiss)
        if let existing = inlineComposerHost, activeInlineComposerTargetID == payload.targetID {
            existing.rootView = wrapped
            reorderOverlayLayers()
            return
        }
        removeInlineComposerHost()
        activeInlineComposerTargetID = payload.targetID
        let host = UIHostingController(rootView: wrapped)
        host.view.backgroundColor = .clear
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
        inlineComposerHost = host
        reorderOverlayLayers()
    }

    private func removeInlineComposerHost() {
        guard let host = inlineComposerHost else { return }
        inlineComposerHost = nil
        host.willMove(toParent: nil)
        host.view.removeFromSuperview()
        host.removeFromParent()
    }

    private func reorderOverlayLayers() {
        if let container = selectionSheetPresenter?.containerView {
            view.bringSubviewToFront(container)
        }
        if let container = commentThreadPresenter?.containerView {
            view.bringSubviewToFront(container)
        }
        if let container = commentDialogPresenter?.containerView {
            view.bringSubviewToFront(container)
        }
        if let composerView = inlineComposerHost?.view {
            view.bringSubviewToFront(composerView)
        }
    }
}

/// Passthrough view that lets all touches fall through when no split overlay is mounted.
private final class PassthroughSplitOverlayView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, !subviews.isEmpty else { return nil }
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

/// Presents a single native iOS 26/27 Liquid Glass sheet (`UIGlassEffect`) strictly
/// inside the right-hand split column, driven by UIKit `UIPanGestureRecognizer`
/// and `UIViewPropertyAnimator` spring physics (120Hz, zero SwiftUI drag relayout).
@MainActor
private final class SplitLiquidGlassSheetPresenter: NSObject, UIGestureRecognizerDelegate {
    private weak var parent: UIViewController?
    private var heightFraction: CGFloat
    private let onDismissRequest: () -> Void

    let containerView = UIView()
    private let backdropView = UIView()
    private let shadowWrapperView = UIView()
    private let glassView: UIVisualEffectView
    private let grabberHandleView = UIView()
    private let grabberPillView = UIView()
    private let hostingController: UIHostingController<AnyView>

    private var activeAnimator: UIViewPropertyAnimator?
    private var isDismissing = false
    private var cardHeight: CGFloat = 320

    init(
        parent: UIViewController,
        rootView: AnyView,
        heightFraction: CGFloat,
        onDismissRequest: @escaping () -> Void
    ) {
        self.parent = parent
        self.heightFraction = heightFraction
        self.onDismissRequest = onDismissRequest
        self.hostingController = UIHostingController(rootView: rootView)

        let glassEffect = UIGlassEffect(style: .regular)
        glassEffect.isInteractive = false
        self.glassView = UIVisualEffectView(effect: glassEffect)
        super.init()
        configureViews()
    }

    private func configureViews() {
        containerView.backgroundColor = .clear
        containerView.accessibilityIdentifier = "video.detail.splitSheet"

        backdropView.backgroundColor = UIColor.black.withAlphaComponent(0.24)
        backdropView.alpha = 0
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleBackdropTap))
        backdropView.addGestureRecognizer(tap)
        containerView.addSubview(backdropView)

        shadowWrapperView.backgroundColor = .clear
        shadowWrapperView.layer.shadowColor = UIColor.black.cgColor
        shadowWrapperView.layer.shadowOpacity = 0.20
        shadowWrapperView.layer.shadowRadius = 22
        shadowWrapperView.layer.shadowOffset = CGSize(width: 0, height: -4)
        containerView.addSubview(shadowWrapperView)

        glassView.clipsToBounds = true
        glassView.layer.cornerRadius = 28
        glassView.layer.cornerCurve = .continuous
        glassView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        shadowWrapperView.addSubview(glassView)

        hostingController.view.backgroundColor = .clear
        hostingController.safeAreaRegions = []
        glassView.contentView.addSubview(hostingController.view)

        grabberHandleView.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        grabberHandleView.addGestureRecognizer(pan)
        glassView.contentView.addSubview(grabberHandleView)

        grabberPillView.backgroundColor = UIColor.label.withAlphaComponent(0.26)
        grabberPillView.layer.cornerRadius = 2.5
        grabberPillView.isUserInteractionEnabled = false
        grabberHandleView.addSubview(grabberPillView)
    }

    func present(in hostView: UIView, animated: Bool) {
        guard let parent else { return }
        parent.addChild(hostingController)
        containerView.frame = hostView.bounds
        hostView.addSubview(containerView)
        hostingController.didMove(toParent: parent)
        layout(in: hostView.bounds)

        if animated {
            shadowWrapperView.transform = CGAffineTransform(translationX: 0, y: cardHeight + 24)
            backdropView.alpha = 0
            let animator = UIViewPropertyAnimator(duration: 0.36, dampingRatio: 0.88) { [weak self] in
                guard let self else { return }
                self.shadowWrapperView.transform = .identity
                self.backdropView.alpha = 1
            }
            activeAnimator = animator
            animator.startAnimation()
        } else {
            shadowWrapperView.transform = .identity
            backdropView.alpha = 1
        }
    }

    func updateHeightFraction(_ fraction: CGFloat) {
        heightFraction = fraction
    }

    func layout(in bounds: CGRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        containerView.frame = bounds
        let topMargin: CGFloat = heightFraction >= 0.99 ? 0 : 12
        let maxAvailable = max(bounds.height - topMargin, 0)
        let targetHeight = (bounds.height * heightFraction).rounded()
        cardHeight = min(maxAvailable, max(min(220, maxAvailable), targetHeight))
        let topY = max(0, bounds.height - cardHeight)
        backdropView.frame = bounds

        let previousTransform = shadowWrapperView.transform
        shadowWrapperView.transform = .identity
        shadowWrapperView.frame = CGRect(x: 0, y: topY, width: bounds.width, height: cardHeight)
        glassView.frame = shadowWrapperView.bounds
        grabberHandleView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 22)
        grabberPillView.frame = CGRect(x: (bounds.width - 36) * 0.5, y: 8, width: 36, height: 5)
        hostingController.view.frame = CGRect(
            x: 0,
            y: 18,
            width: bounds.width,
            height: max(0, cardHeight - 18)
        )
        shadowWrapperView.transform = previousTransform
    }

    func dismiss(animated: Bool) {
        guard !isDismissing else { return }
        isDismissing = true
        activeAnimator?.stopAnimation(true)
        activeAnimator = nil

        let teardown: () -> Void = { [weak self] in
            guard let self else { return }
            self.hostingController.willMove(toParent: nil)
            self.containerView.removeFromSuperview()
            self.hostingController.removeFromParent()
        }

        guard animated else {
            teardown()
            return
        }

        let targetOffset = cardHeight + 32
        let animator = UIViewPropertyAnimator(duration: 0.24, dampingRatio: 0.94) { [weak self] in
            guard let self else { return }
            self.shadowWrapperView.transform = CGAffineTransform(translationX: 0, y: targetOffset)
            self.backdropView.alpha = 0
        }
        animator.addCompletion { _ in
            teardown()
        }
        activeAnimator = animator
        animator.startAnimation()
    }

    @objc private func handleBackdropTap() {
        onDismissRequest()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translationY = max(0, gesture.translation(in: containerView).y)
        let velocityY = gesture.velocity(in: containerView).y

        switch gesture.state {
        case .began:
            activeAnimator?.stopAnimation(true)
            activeAnimator = nil
        case .changed:
            shadowWrapperView.transform = CGAffineTransform(translationX: 0, y: translationY)
            let progress = min(1, translationY / max(cardHeight, 1))
            backdropView.alpha = max(0.15, 1 - progress * 0.85)
        case .ended, .cancelled:
            if translationY > 96 || velocityY > 650 {
                onDismissRequest()
            } else {
                let animator = UIViewPropertyAnimator(duration: 0.28, dampingRatio: 0.86) { [weak self] in
                    guard let self else { return }
                    self.shadowWrapperView.transform = .identity
                    self.backdropView.alpha = 1
                }
                activeAnimator = animator
                animator.startAnimation()
            }
        default:
            break
        }
    }
}
