import Combine
import SwiftUI
import UIKit

struct ZoomyImagePreviewItem: Identifiable, Equatable {
    let id: String
    let thumbnailURL: URL?
    let fallbackURL: URL?
    let viewerURL: URL?

    init(
        id: String,
        thumbnailURL: URL? = nil,
        fallbackURL: URL? = nil,
        viewerURL: URL? = nil
    ) {
        self.id = id
        self.thumbnailURL = thumbnailURL
        self.fallbackURL = fallbackURL
        self.viewerURL = viewerURL
    }

    var displayURL: URL? {
        viewerURL ?? fallbackURL ?? thumbnailURL
    }
}

enum ZoomyImageContentMode {
    case fit
    case fill

    fileprivate var uiViewContentMode: UIView.ContentMode {
        switch self {
        case .fit:
            return .scaleAspectFit
        case .fill:
            return .scaleAspectFill
        }
    }
}

enum ZoomyImageContentAlignment {
    case center
    case top
}

@MainActor
final class ZoomyImagePreviewGroup: ObservableObject {
    @Published var isPresented = false

    private struct AnchorEntry {
        weak var anchor: ZoomySourceAnchor?
    }

    private struct ImageEntry {
        weak var image: UIImage?
    }

    private var anchors: [String: AnchorEntry] = [:]
    private var images: [String: ImageEntry] = [:]

    init() {}

    func register(anchor: ZoomySourceAnchor, itemID: String) {
        anchors[itemID] = AnchorEntry(anchor: anchor)
    }

    func unregister(anchor: ZoomySourceAnchor, itemID: String) {
        guard anchors[itemID]?.anchor === anchor else { return }
        anchors[itemID] = nil
    }

    func sourceAnchor(for itemID: String) -> ZoomySourceAnchor? {
        guard let anchor = anchors[itemID]?.anchor else {
            anchors[itemID] = nil
            return nil
        }
        return anchor
    }

    func setImage(_ image: UIImage, for itemID: String) {
        images[itemID] = ImageEntry(image: image)
    }

    func image(for itemID: String) -> UIImage? {
        guard let image = images[itemID]?.image else {
            images[itemID] = nil
            return nil
        }
        return image
    }
}

/// Minimal in-app image viewer:
/// tap thumbnail to view, tap the full-screen image to exit, pinch only after entering.
struct ZoomyRemoteImage<Placeholder: View>: View {
    let url: URL?
    let fallbackURL: URL?
    let viewerURL: URL?
    let viewerItems: [ZoomyImagePreviewItem]
    let viewerItemID: String?
    let viewerGroup: ZoomyImagePreviewGroup?
    let targetPixelSize: Int?
    let viewerTargetPixelSize: Int
    let cornerRadius: CGFloat
    let contentMode: ZoomyImageContentMode
    let contentAlignment: ZoomyImageContentAlignment
    let onImageLoaded: ((UIImage) -> Void)?
    let onViewerPresentationChange: ((Bool) -> Void)?
    @ViewBuilder let placeholder: (RemoteImageLoadingPhase) -> Placeholder

    @StateObject private var loader = CachedRemoteImageLoader()
    @StateObject private var sourceAnchor = ZoomySourceAnchor()
    @State private var isViewerPresented = false
    @State private var isSourceContentHidden = false
    @State private var reportedImageIdentifier: ObjectIdentifier?
    @State private var prewarmedViewerIdentity: String?

    init(
        url: URL?,
        fallbackURL: URL? = nil,
        viewerURL: URL? = nil,
        viewerItems: [ZoomyImagePreviewItem] = [],
        viewerItemID: String? = nil,
        viewerGroup: ZoomyImagePreviewGroup? = nil,
        targetPixelSize: Int? = nil,
        viewerTargetPixelSize: Int = 2400,
        cornerRadius: CGFloat,
        contentMode: ZoomyImageContentMode = .fill,
        contentAlignment: ZoomyImageContentAlignment = .center,
        onImageLoaded: ((UIImage) -> Void)? = nil,
        onViewerPresentationChange: ((Bool) -> Void)? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.fallbackURL = fallbackURL
        self.viewerURL = viewerURL
        self.viewerItems = viewerItems
        self.viewerItemID = viewerItemID
        self.viewerGroup = viewerGroup
        self.targetPixelSize = targetPixelSize
        self.viewerTargetPixelSize = viewerTargetPixelSize
        self.cornerRadius = cornerRadius
        self.contentMode = contentMode
        self.contentAlignment = contentAlignment
        self.onImageLoaded = onImageLoaded
        self.onViewerPresentationChange = onViewerPresentationChange
        self.placeholder = { _ in placeholder() }
    }

    init(
        url: URL?,
        fallbackURL: URL? = nil,
        viewerURL: URL? = nil,
        viewerItems: [ZoomyImagePreviewItem] = [],
        viewerItemID: String? = nil,
        viewerGroup: ZoomyImagePreviewGroup? = nil,
        targetPixelSize: Int? = nil,
        viewerTargetPixelSize: Int = 2400,
        cornerRadius: CGFloat,
        contentMode: ZoomyImageContentMode = .fill,
        contentAlignment: ZoomyImageContentAlignment = .center,
        onImageLoaded: ((UIImage) -> Void)? = nil,
        onViewerPresentationChange: ((Bool) -> Void)? = nil,
        @ViewBuilder phasePlaceholder: @escaping (RemoteImageLoadingPhase) -> Placeholder
    ) {
        self.url = url
        self.fallbackURL = fallbackURL
        self.viewerURL = viewerURL
        self.viewerItems = viewerItems
        self.viewerItemID = viewerItemID
        self.viewerGroup = viewerGroup
        self.targetPixelSize = targetPixelSize
        self.viewerTargetPixelSize = viewerTargetPixelSize
        self.cornerRadius = cornerRadius
        self.contentMode = contentMode
        self.contentAlignment = contentAlignment
        self.onImageLoaded = onImageLoaded
        self.onViewerPresentationChange = onViewerPresentationChange
        self.placeholder = phasePlaceholder
    }

    var body: some View {
        Button {
            guard loader.image != nil || resolvedViewerItems.contains(where: { $0.displayURL != nil }) else { return }
            prewarmViewerImage(delayNanoseconds: 0)
            onViewerPresentationChange?(true)
            viewerGroup?.isPresented = true
            isSourceContentHidden = true
            isViewerPresented = true
        } label: {
            ZStack {
                ZoomyThumbnailImageView(
                    image: loader.image,
                    cornerRadius: cornerRadius,
                    contentMode: contentMode.uiViewContentMode,
                    contentAlignment: contentAlignment
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

                if loader.image == nil {
                    placeholder(loader.phase)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(shouldHideSourceContent ? 0 : 1)
            .animation(nil, value: shouldHideSourceContent)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(
                ZoomySourceFrameReader { view, frame in
                    sourceAnchor.update(view: view, windowFrame: frame)
                }
            )
        }
        .buttonStyle(.plain)
        .task(id: cacheIdentity) {
            registerWithViewerGroup()
            await loader.load(url: url, fallbackURL: fallbackURL, scale: 1, targetPixelSize: targetPixelSize)
            reportLoadedImageIfNeeded()
        }
        .onAppear {
            registerWithViewerGroup()
        }
        .onChange(of: loader.image) { _, _ in
            reportLoadedImageIfNeeded()
        }
        .onDisappear {
            loader.cancel()
            unregisterFromViewerGroup()
            isSourceContentHidden = false
            viewerGroup?.isPresented = false
            onViewerPresentationChange?(false)
            if loader.image == nil {
                loader.reset()
            }
        }
        .background(
            ZoomyImageViewerPresenter(
                isPresented: $isViewerPresented,
                initialImage: loader.image,
                url: viewerURL ?? url,
                items: resolvedViewerItems,
                initialItemID: resolvedViewerItemID,
                viewerGroup: viewerGroup,
                targetPixelSize: viewerTargetPixelSize,
                sourceAnchor: sourceAnchor,
                sourceCornerRadius: cornerRadius,
                sourceContentMode: contentMode.uiViewContentMode,
                onDismissed: {
                    isSourceContentHidden = false
                    viewerGroup?.isPresented = false
                    onViewerPresentationChange?(false)
                }
            )
            .frame(width: 0, height: 0)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityAddTraits(.isImage)
    }

    private var shouldHideSourceContent: Bool {
        isSourceContentHidden || (viewerGroup?.isPresented == true)
    }

    private var cacheIdentity: String {
        [url, fallbackURL]
            .compactMap { $0?.absoluteString }
            .joined(separator: "|") + "|\(targetPixelSize ?? 0)"
    }

    private var resolvedViewerItemID: String {
        if let viewerItemID {
            return viewerItemID
        }
        return (viewerURL ?? fallbackURL ?? url)?.absoluteString ?? "single-image"
    }

    private var resolvedViewerItems: [ZoomyImagePreviewItem] {
        if !viewerItems.isEmpty {
            return viewerItems
        }
        return [
            ZoomyImagePreviewItem(
                id: resolvedViewerItemID,
                thumbnailURL: url,
                fallbackURL: fallbackURL,
                viewerURL: viewerURL ?? fallbackURL ?? url
            )
        ]
    }

    private func registerWithViewerGroup() {
        guard let viewerGroup else { return }
        viewerGroup.register(anchor: sourceAnchor, itemID: resolvedViewerItemID)
        if let image = loader.image {
            viewerGroup.setImage(image, for: resolvedViewerItemID)
        }
    }

    private func unregisterFromViewerGroup() {
        guard let viewerGroup else { return }
        viewerGroup.unregister(anchor: sourceAnchor, itemID: resolvedViewerItemID)
    }

    private func reportLoadedImageIfNeeded() {
        guard let image = loader.image else { return }
        let identifier = ObjectIdentifier(image)
        guard reportedImageIdentifier != identifier else { return }
        reportedImageIdentifier = identifier
        viewerGroup?.setImage(image, for: resolvedViewerItemID)
        onImageLoaded?(image)
        prewarmViewerImage(delayNanoseconds: 420_000_000)
    }

    private func prewarmViewerImage(delayNanoseconds: UInt64) {
        guard let viewerURL = viewerURL ?? fallbackURL ?? url else { return }
        let identity = "\(viewerURL.absoluteString)|\(viewerTargetPixelSize)"
        guard prewarmedViewerIdentity != identity else { return }
        prewarmedViewerIdentity = identity
        Task(priority: .utility) {
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            await RemoteImageCache.shared.prefetch(
                [RemoteImageSource(url: viewerURL)],
                targetPixelSize: viewerTargetPixelSize,
                maximumConcurrentLoads: 1
            )
        }
    }
}

private struct ZoomyImageViewerPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let initialImage: UIImage?
    let url: URL?
    let items: [ZoomyImagePreviewItem]
    let initialItemID: String
    let viewerGroup: ZoomyImagePreviewGroup?
    let targetPixelSize: Int
    let sourceAnchor: ZoomySourceAnchor
    let sourceCornerRadius: CGFloat
    let sourceContentMode: UIView.ContentMode
    let onDismissed: () -> Void

    func makeUIViewController(context: Context) -> PresenterViewController {
        let controller = PresenterViewController()
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ controller: PresenterViewController, context: Context) {
        context.coordinator.update(
            isPresented: isPresented,
            initialImage: initialImage,
            url: url,
            items: items,
            initialItemID: initialItemID,
            viewerGroup: viewerGroup,
            targetPixelSize: targetPixelSize,
            sourceAnchor: sourceAnchor,
            sourceCornerRadius: sourceCornerRadius,
            sourceContentMode: sourceContentMode,
            onDismissed: onDismissed,
            from: controller,
            binding: $isPresented
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class PresenterViewController: UIViewController {}

    final class Coordinator {
        private weak var presentedController: UIViewController?
        private var presentedURL: URL?
        private var transitionDelegate: ZoomyImageViewerTransitioningDelegate?
        private var currentItemID: String?

        @MainActor
        func update(
            isPresented: Bool,
            initialImage: UIImage?,
            url: URL?,
            items: [ZoomyImagePreviewItem],
            initialItemID: String,
            viewerGroup: ZoomyImagePreviewGroup?,
            targetPixelSize: Int,
            sourceAnchor: ZoomySourceAnchor,
            sourceCornerRadius: CGFloat,
            sourceContentMode: UIView.ContentMode,
            onDismissed: @escaping () -> Void,
            from presenter: UIViewController,
            binding: Binding<Bool>
        ) {
            if isPresented {
                if presentedController != nil {
                    transitionDelegate?.sourceAnchor = sourceAnchor
                    transitionDelegate?.sourceCornerRadius = sourceCornerRadius
                    transitionDelegate?.sourceContentMode = sourceContentMode
                    if let initialImage {
                        transitionDelegate?.currentImage = initialImage
                    }
                    return
                }
                let resolvedItems = Self.resolvedItems(items: items, fallbackURL: url, fallbackItemID: initialItemID)
                let resolvedInitialItemID = resolvedItems.contains(where: { $0.id == initialItemID })
                    ? initialItemID
                    : (resolvedItems.first?.id ?? initialItemID)
                let transitionDelegate = ZoomyImageViewerTransitioningDelegate(
                    sourceAnchor: sourceAnchor,
                    sourceAnchorProvider: { itemID in
                        viewerGroup?.sourceAnchor(for: itemID)
                    },
                    currentItemID: resolvedInitialItemID,
                    sourceCornerRadius: sourceCornerRadius,
                    sourceContentMode: sourceContentMode,
                    image: initialImage
                )
                let viewer = ZoomyFullScreenImageViewer(
                    initialImage: initialImage,
                    url: url,
                    items: resolvedItems,
                    initialItemID: resolvedInitialItemID,
                    viewerGroup: viewerGroup,
                    targetPixelSize: targetPixelSize,
                    isPresented: binding,
                    onSelectedItemChanged: { [weak transitionDelegate] item, image in
                        transitionDelegate?.currentItemID = item.id
                        transitionDelegate?.currentImage = image
                    },
                    onDismissDragChanged: { [weak transitionDelegate] offset in
                        transitionDelegate?.dismissDragOffset = offset
                    },
                    onImageUpdated: { [weak transitionDelegate] image in
                        transitionDelegate?.currentImage = image
                    }
                )
                let hostingController = UIHostingController(rootView: viewer)
                hostingController.view.backgroundColor = .clear
                hostingController.modalPresentationStyle = .custom
                hostingController.transitioningDelegate = transitionDelegate
                hostingController.isModalInPresentation = false
                presentedURL = url
                presentedController = hostingController
                currentItemID = resolvedInitialItemID
                self.transitionDelegate = transitionDelegate
                presenter.present(hostingController, animated: !UIAccessibility.isReduceMotionEnabled)
            } else if let presentedController {
                self.presentedController = nil
                presentedURL = nil
                currentItemID = nil
                (presentedController as? UIHostingController<ZoomyFullScreenImageViewer>)?.rootView.cancelLoading()
                presentedController.dismiss(animated: !UIAccessibility.isReduceMotionEnabled) { [weak self] in
                    self?.transitionDelegate = nil
                    onDismissed()
                }
            }
        }

        private static func resolvedItems(
            items: [ZoomyImagePreviewItem],
            fallbackURL: URL?,
            fallbackItemID: String
        ) -> [ZoomyImagePreviewItem] {
            if !items.isEmpty {
                return items
            }
            return [
                ZoomyImagePreviewItem(
                    id: fallbackItemID,
                    thumbnailURL: fallbackURL,
                    fallbackURL: fallbackURL,
                    viewerURL: fallbackURL
                )
            ]
        }
    }
}

private final class ZoomyImageViewerTransitioningDelegate: NSObject, UIViewControllerTransitioningDelegate {
    var sourceAnchor: ZoomySourceAnchor
    var sourceAnchorProvider: (String) -> ZoomySourceAnchor?
    var currentItemID: String
    var sourceCornerRadius: CGFloat
    var sourceContentMode: UIView.ContentMode
    var currentImage: UIImage?
    var dismissDragOffset: CGFloat = 0

    init(
        sourceAnchor: ZoomySourceAnchor,
        sourceAnchorProvider: @escaping (String) -> ZoomySourceAnchor?,
        currentItemID: String,
        sourceCornerRadius: CGFloat,
        sourceContentMode: UIView.ContentMode,
        image: UIImage?
    ) {
        self.sourceAnchor = sourceAnchor
        self.sourceAnchorProvider = sourceAnchorProvider
        self.currentItemID = currentItemID
        self.sourceCornerRadius = sourceCornerRadius
        self.sourceContentMode = sourceContentMode
        self.currentImage = image
    }

    func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        ZoomyImageViewerAnimator(
            mode: .presenting,
            sourceAnchor: currentSourceAnchor,
            sourceCornerRadius: sourceCornerRadius,
            sourceContentMode: sourceContentMode,
            image: currentImage
        )
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        ZoomyImageViewerAnimator(
            mode: .dismissing,
            sourceAnchor: currentSourceAnchor,
            sourceCornerRadius: sourceCornerRadius,
            sourceContentMode: sourceContentMode,
            image: currentImage,
            initialDismissTranslationY: dismissDragOffset
        )
    }

    func presentationController(
        forPresented presented: UIViewController,
        presenting: UIViewController?,
        source: UIViewController
    ) -> UIPresentationController? {
        ZoomyOverlayPresentationController(
            presentedViewController: presented,
            presenting: presenting ?? source
        )
    }

    private var currentSourceAnchor: ZoomySourceAnchor {
        sourceAnchorProvider(currentItemID) ?? sourceAnchor
    }
}

private final class ZoomyOverlayPresentationController: UIPresentationController {
    override var shouldRemovePresentersView: Bool {
        false
    }

    override var frameOfPresentedViewInContainerView: CGRect {
        containerView?.bounds ?? .zero
    }

    override func containerViewDidLayoutSubviews() {
        super.containerViewDidLayoutSubviews()
        presentedView?.frame = frameOfPresentedViewInContainerView
    }
}

private final class ZoomyImageViewerAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    enum Mode {
        case presenting
        case dismissing
    }

    private let mode: Mode
    private let sourceAnchor: ZoomySourceAnchor
    private let sourceCornerRadius: CGFloat
    private let sourceContentMode: UIView.ContentMode
    private let image: UIImage?
    private let initialDismissTranslationY: CGFloat

    init(
        mode: Mode,
        sourceAnchor: ZoomySourceAnchor,
        sourceCornerRadius: CGFloat,
        sourceContentMode: UIView.ContentMode,
        image: UIImage?,
        initialDismissTranslationY: CGFloat = 0
    ) {
        self.mode = mode
        self.sourceAnchor = sourceAnchor
        self.sourceCornerRadius = sourceCornerRadius
        self.sourceContentMode = sourceContentMode
        self.image = image
        self.initialDismissTranslationY = initialDismissTranslationY
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        switch mode {
        case .presenting:
            return 0.34
        case .dismissing:
            return 0.28
        }
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let container = transitionContext.containerView
        guard let image,
              sourceAnchor.frame(in: container) != nil
        else {
            animateFadeTransition(using: transitionContext)
            return
        }

        switch mode {
        case .presenting:
            animatePresenting(using: transitionContext, image: image)
        case .dismissing:
            animateDismissing(using: transitionContext, image: image)
        }
    }

    private func animatePresenting(
        using transitionContext: UIViewControllerContextTransitioning,
        image: UIImage
    ) {
        guard let toView = transitionContext.view(forKey: .to),
              let toViewController = transitionContext.viewController(forKey: .to)
        else {
            transitionContext.completeTransition(false)
            return
        }

        let container = transitionContext.containerView
        toView.frame = transitionContext.finalFrame(for: toViewController)
        toView.alpha = 0
        container.addSubview(toView)
        toView.layoutIfNeeded()

        let backgroundView = UIView(frame: container.bounds)
        backgroundView.backgroundColor = .black
        backgroundView.alpha = 0

        let imageView = transitionImageView(image: image)
        imageView.contentMode = sourceContentMode
        imageView.frame = sourceAnchor.frame(in: container) ?? fallbackSourceFrame(in: container)
        imageView.layer.cornerRadius = sourceCornerRadius

        container.addSubview(backgroundView)
        container.addSubview(imageView)

        let endFrame = aspectFitFrame(for: image, in: container.bounds)
        let animator = UIViewPropertyAnimator(
            duration: transitionDuration(using: transitionContext),
            dampingRatio: 0.86
        ) {
            backgroundView.alpha = 1
            imageView.frame = endFrame
            imageView.layer.cornerRadius = 0
        }
        animator.addAnimations({
            imageView.contentMode = .scaleAspectFit
        }, delayFactor: 0.62)
        animator.addCompletion { position in
            let completed = position == .end && !transitionContext.transitionWasCancelled
            toView.alpha = completed ? 1 : 0
            backgroundView.removeFromSuperview()
            imageView.removeFromSuperview()
            transitionContext.completeTransition(completed)
        }
        animator.startAnimation()
    }

    private func animateDismissing(
        using transitionContext: UIViewControllerContextTransitioning,
        image: UIImage
    ) {
        guard let fromView = transitionContext.view(forKey: .from) else {
            transitionContext.completeTransition(false)
            return
        }

        let container = transitionContext.containerView
        let backgroundView = UIView(frame: container.bounds)
        backgroundView.backgroundColor = .black
        backgroundView.alpha = dismissBackgroundStartAlpha

        let imageView = transitionImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.frame = aspectFitFrame(for: image, in: container.bounds)
            .offsetBy(dx: 0, dy: initialDismissTranslationY)
        imageView.layer.cornerRadius = 0

        container.addSubview(backgroundView)
        container.addSubview(imageView)
        fromView.alpha = 0

        let endFrame = sourceAnchor.frame(in: container) ?? fallbackSourceFrame(in: container)
        let animator = UIViewPropertyAnimator(
            duration: transitionDuration(using: transitionContext),
            dampingRatio: 0.92
        ) {
            backgroundView.alpha = 0
            imageView.frame = endFrame
            imageView.layer.cornerRadius = self.sourceCornerRadius
        }
        animator.addAnimations({
            imageView.contentMode = self.sourceContentMode
        }, delayFactor: 0.15)
        animator.addCompletion { position in
            let completed = position == .end && !transitionContext.transitionWasCancelled
            if completed {
                fromView.removeFromSuperview()
            } else {
                fromView.alpha = 1
            }
            backgroundView.removeFromSuperview()
            imageView.removeFromSuperview()
            transitionContext.completeTransition(completed)
        }
        animator.startAnimation()
    }

    private func animateFadeTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let container = transitionContext.containerView
        let duration = transitionDuration(using: transitionContext)

        switch mode {
        case .presenting:
            guard let toView = transitionContext.view(forKey: .to) else {
                transitionContext.completeTransition(false)
                return
            }
            toView.frame = container.bounds
            toView.alpha = 0
            container.addSubview(toView)
            UIView.animate(withDuration: duration) {
                toView.alpha = 1
            } completion: { finished in
                transitionContext.completeTransition(finished && !transitionContext.transitionWasCancelled)
            }
        case .dismissing:
            guard let fromView = transitionContext.view(forKey: .from) else {
                transitionContext.completeTransition(false)
                return
            }
            UIView.animate(withDuration: duration) {
                fromView.alpha = 0
            } completion: { finished in
                fromView.removeFromSuperview()
                transitionContext.completeTransition(finished && !transitionContext.transitionWasCancelled)
            }
        }
    }

    private func transitionImageView(image: UIImage) -> UIImageView {
        let imageView = UIImageView(image: image)
        imageView.backgroundColor = .clear
        imageView.clipsToBounds = true
        imageView.layer.cornerCurve = .continuous
        return imageView
    }

    private func fallbackSourceFrame(in container: UIView) -> CGRect {
        let side: CGFloat = 2
        return CGRect(
            x: container.bounds.midX - side / 2,
            y: container.bounds.midY - side / 2,
            width: side,
            height: side
        )
    }

    private var dismissBackgroundStartAlpha: CGFloat {
        guard initialDismissTranslationY > 0 else { return 1 }
        let progress = min(max(abs(initialDismissTranslationY) / 260, 0), 1)
        return max(0.55, 1 - progress * 0.45)
    }

    private func aspectFitFrame(for image: UIImage, in bounds: CGRect) -> CGRect {
        guard image.size.width > 0, image.size.height > 0 else { return bounds }
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        ).integral
    }
}
