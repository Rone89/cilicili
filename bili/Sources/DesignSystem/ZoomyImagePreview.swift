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

@MainActor
final class ZoomyImagePreviewGroup: ObservableObject {
    @Published fileprivate var isPresented = false

    private struct AnchorEntry {
        weak var anchor: ZoomySourceAnchor?
    }

    private struct ImageEntry {
        weak var image: UIImage?
    }

    private var anchors: [String: AnchorEntry] = [:]
    private var images: [String: ImageEntry] = [:]

    init() {}

    fileprivate func register(anchor: ZoomySourceAnchor, itemID: String) {
        anchors[itemID] = AnchorEntry(anchor: anchor)
    }

    fileprivate func unregister(anchor: ZoomySourceAnchor, itemID: String) {
        guard anchors[itemID]?.anchor === anchor else { return }
        anchors[itemID] = nil
    }

    fileprivate func sourceAnchor(for itemID: String) -> ZoomySourceAnchor? {
        guard let anchor = anchors[itemID]?.anchor else {
            anchors[itemID] = nil
            return nil
        }
        return anchor
    }

    fileprivate func setImage(_ image: UIImage, for itemID: String) {
        images[itemID] = ImageEntry(image: image)
    }

    fileprivate func image(for itemID: String) -> UIImage? {
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
    let contentMode: UIView.ContentMode
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
        contentMode: UIView.ContentMode = .scaleAspectFill,
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
        contentMode: UIView.ContentMode = .scaleAspectFill,
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
                    contentMode: contentMode
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
                sourceContentMode: contentMode,
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

private struct ZoomySourceFrameReader: UIViewRepresentable {
    let onFrameChange: (UIView, CGRect) -> Void

    func makeUIView(context _: Context) -> FrameView {
        let view = FrameView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.onFrameChange = onFrameChange
        return view
    }

    func updateUIView(_ view: FrameView, context _: Context) {
        view.onFrameChange = onFrameChange
        view.reportFrame()
    }

    final class FrameView: UIView {
        var onFrameChange: ((UIView, CGRect) -> Void)?
        private var lastReportedFrame = CGRect.null

        override func layoutSubviews() {
            super.layoutSubviews()
            reportFrame()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            reportFrame()
        }

        func reportFrame() {
            guard let window, bounds.width > 1, bounds.height > 1 else { return }
            let frame = convert(bounds, to: window).integral
            guard frame != lastReportedFrame else { return }
            lastReportedFrame = frame
            DispatchQueue.main.async { [weak self] in
                guard let self, self.lastReportedFrame == frame else { return }
                self.onFrameChange?(self, frame)
            }
        }
    }
}

@MainActor
private final class ZoomySourceAnchor: ObservableObject {
    weak var view: UIView?
    private var windowFrame: CGRect = .zero

    func update(view: UIView, windowFrame: CGRect) {
        self.view = view
        self.windowFrame = windowFrame
    }

    func frame(in container: UIView) -> CGRect? {
        if let view,
           let viewWindow = view.window,
           let containerWindow = container.window,
           viewWindow === containerWindow,
           view.bounds.width > 1,
           view.bounds.height > 1 {
            let convertedFrame = view.convert(view.bounds, to: container).integral
            if isUsableSourceFrame(convertedFrame, in: container) {
                return convertedFrame
            }
        }

        guard windowFrame.width > 1, windowFrame.height > 1 else { return nil }
        let convertedFrame: CGRect
        if let window = container.window {
            convertedFrame = container.convert(windowFrame, from: window).integral
        } else {
            convertedFrame = windowFrame.integral
        }
        return isUsableSourceFrame(convertedFrame, in: container) ? convertedFrame : nil
    }

    private func isUsableSourceFrame(_ frame: CGRect, in container: UIView) -> Bool {
        frame.width > 1
            && frame.height > 1
            && frame.intersects(container.bounds.insetBy(dx: -40, dy: -40))
    }
}

private struct ZoomyThumbnailImageView: UIViewRepresentable {
    let image: UIImage?
    let cornerRadius: CGFloat
    let contentMode: UIView.ContentMode

    func makeUIView(context _: Context) -> UIImageView {
        let imageView = ZoomyThumbnailUIImageView()
        imageView.backgroundColor = .clear
        imageView.clipsToBounds = true
        imageView.isOpaque = false
        imageView.isUserInteractionEnabled = false
        imageView.contentMode = contentMode
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.layer.cornerCurve = .continuous
        imageView.layer.cornerRadius = cornerRadius
        return imageView
    }

    func updateUIView(_ imageView: UIImageView, context _: Context) {
        imageView.image = image
        imageView.contentMode = contentMode
        imageView.layer.cornerRadius = cornerRadius
    }
}

private final class ZoomyThumbnailUIImageView: UIImageView {
    override var intrinsicContentSize: CGSize {
        .zero
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

private struct ZoomyFullScreenImageViewer: View {
    let initialImage: UIImage?
    let url: URL?
    let items: [ZoomyImagePreviewItem]
    let initialItemID: String
    let viewerGroup: ZoomyImagePreviewGroup?
    let targetPixelSize: Int
    let onSelectedItemChanged: (ZoomyImagePreviewItem, UIImage?) -> Void
    let onDismissDragChanged: (CGFloat) -> Void
    let onImageUpdated: (UIImage) -> Void
    @Binding var isPresented: Bool
    @State private var selectedItemID: String
    @State private var dismissDragOffset: CGFloat = 0

    init(
        initialImage: UIImage?,
        url: URL?,
        items: [ZoomyImagePreviewItem],
        initialItemID: String,
        viewerGroup: ZoomyImagePreviewGroup?,
        targetPixelSize: Int,
        isPresented: Binding<Bool>,
        onSelectedItemChanged: @escaping (ZoomyImagePreviewItem, UIImage?) -> Void,
        onDismissDragChanged: @escaping (CGFloat) -> Void,
        onImageUpdated: @escaping (UIImage) -> Void
    ) {
        self.initialImage = initialImage
        self.url = url
        self.items = items
        self.initialItemID = initialItemID
        self.viewerGroup = viewerGroup
        self.targetPixelSize = targetPixelSize
        self.onSelectedItemChanged = onSelectedItemChanged
        self.onDismissDragChanged = onDismissDragChanged
        self.onImageUpdated = onImageUpdated
        _isPresented = isPresented
        _selectedItemID = State(initialValue: initialItemID)
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            ZStack {
                if items.count > 1 {
                    TabView(selection: $selectedItemID) {
                        ForEach(items) { item in
                            imagePage(for: item)
                                .tag(item.id)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                    .ignoresSafeArea()
                } else {
                    imagePage(for: items.first)
                        .ignoresSafeArea()
                }

                viewerChrome
            }
            .offset(y: dismissDragOffset)
        }
        .simultaneousGesture(dismissDragGesture)
        .onAppear {
            syncSelectedItemContext()
            prewarmNeighborImages()
        }
        .onChange(of: selectedItemID) { _, _ in
            syncSelectedItemContext()
            prewarmNeighborImages()
        }
        .statusBarHidden(true)
        .accessibilityLabel("图片预览")
    }

    private var backgroundOpacity: Double {
        let progress = min(max(abs(dismissDragOffset) / 260, 0), 1)
        return 1 - progress * 0.45
    }

    private var chromeOpacity: Double {
        let progress = min(max(abs(dismissDragOffset) / 180, 0), 1)
        return 1 - progress * 0.6
    }

    private var viewerChrome: some View {
        ZStack(alignment: .top) {
            if items.count > 1 {
                Text(counterText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(.black.opacity(0.46), in: Capsule())
                    .allowsHitTesting(false)
            }

            HStack {
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.black.opacity(0.46), in: Circle())
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.16), lineWidth: 0.7)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
            }
        }
        .padding(.top, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(chromeOpacity)
    }

    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                let verticalTravel = value.translation.height
                let horizontalTravel = abs(value.translation.width)
                guard verticalTravel > 0, verticalTravel > horizontalTravel * 1.15 else { return }
                dismissDragOffset = verticalTravel
                onDismissDragChanged(verticalTravel)
            }
            .onEnded { value in
                let verticalTravel = value.translation.height
                let horizontalTravel = abs(value.translation.width)
                let predictedTravel = value.predictedEndTranslation.height
                guard verticalTravel > 0, verticalTravel > horizontalTravel * 1.15 else {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
                        dismissDragOffset = 0
                        onDismissDragChanged(0)
                    }
                    return
                }
                if verticalTravel > 120 || predictedTravel > 220 {
                    onDismissDragChanged(verticalTravel)
                    isPresented = false
                } else {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
                        dismissDragOffset = 0
                        onDismissDragChanged(0)
                    }
                }
            }
    }

    @ViewBuilder
    private func imagePage(for item: ZoomyImagePreviewItem?) -> some View {
        if let item {
            ZoomyViewerImagePage(
                item: item,
                initialImage: initialImage(for: item),
                targetPixelSize: targetPixelSize,
                isPresented: $isPresented,
                onImageUpdated: { itemID, image in
                    viewerGroup?.setImage(image, for: itemID)
                    if itemID == selectedItemID {
                        onImageUpdated(image)
                    }
                }
            )
        } else if let url {
            ZoomyViewerImagePage(
                item: ZoomyImagePreviewItem(id: url.absoluteString, viewerURL: url),
                initialImage: initialImage,
                targetPixelSize: targetPixelSize,
                isPresented: $isPresented,
                onImageUpdated: { _, image in
                    onImageUpdated(image)
                }
            )
        } else {
            ProgressView()
                .tint(.white)
        }
    }

    private var selectedIndex: Int {
        items.firstIndex { $0.id == selectedItemID } ?? 0
    }

    private var counterText: String {
        "\(selectedIndex + 1)/\(max(items.count, 1))"
    }

    private func initialImage(for item: ZoomyImagePreviewItem) -> UIImage? {
        if item.id == initialItemID {
            return initialImage ?? viewerGroup?.image(for: item.id)
        }
        return viewerGroup?.image(for: item.id)
    }

    private func syncSelectedItemContext() {
        guard let item = items.first(where: { $0.id == selectedItemID }) else { return }
        let cachedImage = viewerGroup?.image(for: item.id)
        onSelectedItemChanged(item, cachedImage)
        if let cachedImage {
            onImageUpdated(cachedImage)
        }
    }

    private func prewarmNeighborImages() {
        guard items.count > 1 else { return }
        let neighborIndices = [selectedIndex - 1, selectedIndex + 1]
        let sources = neighborIndices.compactMap { index -> RemoteImageSource? in
            guard items.indices.contains(index),
                  let url = items[index].displayURL
            else { return nil }
            return RemoteImageSource(url: url)
        }
        guard !sources.isEmpty else { return }
        Task(priority: .utility) {
            await RemoteImageCache.shared.prefetch(
                sources,
                targetPixelSize: targetPixelSize,
                maximumConcurrentLoads: 2
            )
        }
    }

    func cancelLoading() {
    }
}

private struct ZoomyViewerImagePage: View {
    let item: ZoomyImagePreviewItem
    let initialImage: UIImage?
    let targetPixelSize: Int
    @Binding var isPresented: Bool
    let onImageUpdated: (String, UIImage) -> Void
    @StateObject private var loader: ZoomyViewerImageLoader

    init(
        item: ZoomyImagePreviewItem,
        initialImage: UIImage?,
        targetPixelSize: Int,
        isPresented: Binding<Bool>,
        onImageUpdated: @escaping (String, UIImage) -> Void
    ) {
        self.item = item
        self.initialImage = initialImage
        self.targetPixelSize = targetPixelSize
        _isPresented = isPresented
        self.onImageUpdated = onImageUpdated
        _loader = StateObject(wrappedValue: ZoomyViewerImageLoader(initialImage: initialImage))
    }

    var body: some View {
        ZStack {
            if let image = loader.image {
                ZoomyZoomableImageView(image: image) {
                    isPresented = false
                }
                .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: item.displayURL?.absoluteString ?? item.id) {
            await loader.load(url: item.displayURL, targetPixelSize: targetPixelSize)
        }
        .onAppear {
            if let image = loader.image {
                onImageUpdated(item.id, image)
            }
        }
        .onChange(of: loader.image) { _, image in
            if let image {
                onImageUpdated(item.id, image)
            }
        }
        .onDisappear {
            loader.cancel()
        }
    }
}

@MainActor
private final class ZoomyViewerImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    private var task: Task<Void, Never>?

    init(initialImage: UIImage?) {
        image = initialImage
    }

    func load(url: URL?, targetPixelSize: Int) async {
        task?.cancel()
        guard let url else { return }

        task = Task(priority: .userInitiated) { [weak self] in
            if let cachedImage = await RemoteImageCache.shared.image(for: url, scale: 1, targetPixelSize: targetPixelSize) {
                await MainActor.run {
                    self?.image = cachedImage
                }
                return
            }

            try? await Task.sleep(nanoseconds: 90_000_000)
            guard !Task.isCancelled else { return }
            guard let loadedImage = await RemoteImageCache.shared.load(
                url: url,
                scale: 1,
                targetPixelSize: targetPixelSize
            ),
                !Task.isCancelled
            else { return }

            await MainActor.run {
                self?.image = loadedImage
            }
        }
        await task?.value
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

private struct ZoomyZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let onTapExit: () -> Void

    func makeUIView(context _: Context) -> ZoomyZoomableImageHostView {
        let view = ZoomyZoomableImageHostView()
        view.onTapExit = onTapExit
        return view
    }

    func updateUIView(_ view: ZoomyZoomableImageHostView, context _: Context) {
        view.onTapExit = onTapExit
        view.setImage(image)
    }
}

private final class ZoomyZoomableImageHostView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    var onTapExit: (() -> Void)?

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private var currentImageIdentifier: ObjectIdentifier?
    private var lastLayoutSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false

        scrollView.backgroundColor = .clear
        scrollView.isOpaque = false
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        addSubview(scrollView)

        imageView.backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        scrollView.addSubview(imageView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        tap.numberOfTapsRequired = 1
        tap.delegate = self

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        tap.require(toFail: doubleTap)

        scrollView.addGestureRecognizer(doubleTap)
        scrollView.addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setImage(_ image: UIImage) {
        let identifier = ObjectIdentifier(image)
        guard currentImageIdentifier != identifier else { return }
        currentImageIdentifier = identifier
        imageView.image = image
        resetZoomLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        guard bounds.size != lastLayoutSize else {
            centerImage()
            return
        }
        lastLayoutSize = bounds.size
        resetZoomLayout()
    }

    func viewForZooming(in _: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_: UIScrollView) {
        centerImage()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer is UITapGestureRecognizer || otherGestureRecognizer is UITapGestureRecognizer
    }

    @objc private func handleSingleTap() {
        onTapExit?()
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard imageView.image != nil else { return }
        let targetScale: CGFloat
        if scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01 {
            targetScale = min(scrollView.maximumZoomScale, max(scrollView.minimumZoomScale * 2.4, 2.4))
        } else {
            targetScale = scrollView.minimumZoomScale
        }

        if targetScale <= scrollView.minimumZoomScale + 0.01 {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            let location = recognizer.location(in: imageView)
            scrollView.zoom(to: zoomRect(for: targetScale, centeredAt: location), animated: true)
        }
    }

    private func resetZoomLayout() {
        guard let image = imageView.image,
              bounds.width > 1,
              bounds.height > 1,
              image.size.width > 0,
              image.size.height > 0
        else { return }

        scrollView.zoomScale = 1
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5

        let fittedSize = aspectFitSize(imageSize: image.size, boundsSize: bounds.size)
        imageView.frame = CGRect(origin: .zero, size: fittedSize)
        scrollView.contentSize = fittedSize
        centerImage()
    }

    private func centerImage() {
        let horizontalInset = max((bounds.width - scrollView.contentSize.width) * 0.5, 0)
        let verticalInset = max((bounds.height - scrollView.contentSize.height) * 0.5, 0)
        scrollView.contentInset = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
    }

    private func aspectFitSize(imageSize: CGSize, boundsSize: CGSize) -> CGSize {
        let scale = min(boundsSize.width / imageSize.width, boundsSize.height / imageSize.height)
        return CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
    }

    private func zoomRect(for scale: CGFloat, centeredAt center: CGPoint) -> CGRect {
        let width = scrollView.bounds.width / scale
        let height = scrollView.bounds.height / scale
        return CGRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        )
    }
}
