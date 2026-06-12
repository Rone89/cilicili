import AVKit
import SwiftUI
import UIKit

struct VideoSurfaceView: UIViewRepresentable {
    @ObservedObject var viewModel: PlayerStateViewModel
    let prefersNativePlaybackControls: Bool

    func makeUIView(context _: Context) -> VideoSurfaceContainerView {
        let view = VideoSurfaceContainerView()
        view.backgroundColor = .black
        view.onBoundsChange = { [weak viewModel] in
            viewModel?.refreshSurfaceLayout()
        }
        view.setPlayerViewModel(viewModel, prefersNativePlaybackControls: prefersNativePlaybackControls)
        viewModel.attachSurface(view, prefersNativePlaybackControls: prefersNativePlaybackControls)
        return view
    }

    func updateUIView(_ uiView: VideoSurfaceContainerView, context _: Context) {
        uiView.onBoundsChange = { [weak viewModel] in
            viewModel?.refreshSurfaceLayout()
        }
        uiView.setPlayerViewModel(viewModel, prefersNativePlaybackControls: prefersNativePlaybackControls)
        viewModel.attachSurface(uiView, prefersNativePlaybackControls: prefersNativePlaybackControls)
        uiView.setNeedsLayout()
        uiView.layoutIfNeeded()
        viewModel.refreshSurfaceLayout()
    }

    static func dismantleUIView(_ uiView: VideoSurfaceContainerView, coordinator _: ()) {
        uiView.detachPlayerSurfaceAfterCurrentTransitionIfNeeded()
    }
}

enum PlayerFullscreenMode: Equatable {
    case landscape(UIDeviceOrientation)
    case portrait

    var isLandscape: Bool {
        if case .landscape = self { return true }
        return false
    }

    var isPortrait: Bool {
        if case .portrait = self { return true }
        return false
    }
}

final class VideoSurfaceContainerView: UIView {
    let drawableView = UIView()
    let nativePlayerViewController = AVPlayerViewController()
    var onBoundsChange: (() -> Void)?

    private weak var playerViewModel: PlayerStateViewModel?
    private(set) var prefersNativePlaybackControls = true
    private var isNativePlaybackControllerEnabled = false
    private var lastReportedBounds = CGRect.null

    func setPlayerViewModel(_ viewModel: PlayerStateViewModel, prefersNativePlaybackControls: Bool) {
        playerViewModel = viewModel
        self.prefersNativePlaybackControls = prefersNativePlaybackControls
        if !prefersNativePlaybackControls {
            setNativePlaybackControllerEnabled(false)
        }
    }

    func makePlaybackTransitionSnapshotView() -> UIView? {
        drawableView.layoutIfNeeded()
        guard drawableView.bounds.width > 1, drawableView.bounds.height > 1 else { return nil }

        if let snapshotView = drawableView.snapshotView(afterScreenUpdates: false) {
            snapshotView.frame = CGRect(origin: .zero, size: drawableView.bounds.size)
            snapshotView.backgroundColor = .black
            snapshotView.isOpaque = true
            snapshotView.clipsToBounds = true
            return snapshotView
        }

        let renderer = UIGraphicsImageRenderer(bounds: drawableView.bounds)
        let image = renderer.image { context in
            drawableView.layer.render(in: context.cgContext)
        }
        let imageView = UIImageView(image: image)
        imageView.frame = CGRect(origin: .zero, size: drawableView.bounds.size)
        imageView.backgroundColor = .black
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.isOpaque = true
        return imageView
    }

    func makePlaybackTransitionSnapshotImage() -> UIImage? {
        drawableView.layoutIfNeeded()
        guard drawableView.bounds.width > 1, drawableView.bounds.height > 1 else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(bounds: drawableView.bounds, format: format)
        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(drawableView.bounds)
            if !drawableView.drawHierarchy(in: drawableView.bounds, afterScreenUpdates: false) {
                drawableView.layer.render(in: context.cgContext)
            }
        }
    }

    func detachPlayerSurface() {
        playerViewModel?.detachSurface(self)
        setNativePlaybackControllerEnabled(false)
        playerViewModel = nil
    }

    func detachPlayerSurfaceAfterCurrentTransitionIfNeeded() {
        guard let coordinator = enclosingNavigationController()?.transitionCoordinator else {
            detachPlayerSurface()
            return
        }

        coordinator.animate(alongsideTransition: nil) { [weak self] context in
            guard let self, !context.isCancelled else { return }
            self.detachPlayerSurface()
        }
    }

    func setNativePlaybackControllerEnabled(_ isEnabled: Bool) {
        let resolvedIsEnabled = isEnabled && prefersNativePlaybackControls
        guard isNativePlaybackControllerEnabled != resolvedIsEnabled else {
            if resolvedIsEnabled {
                installNativePlayerViewControllerIfPossible()
            }
            return
        }

        isNativePlaybackControllerEnabled = resolvedIsEnabled
        if resolvedIsEnabled {
            configureNativePlayerViewController()
            installNativePlayerViewControllerIfPossible()
        } else {
            removeNativePlayerViewController()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isOpaque = true
        clipsToBounds = true
        drawableView.backgroundColor = .black
        drawableView.isOpaque = true
        drawableView.clipsToBounds = true
        addSubview(drawableView)
        configureNativePlayerViewController()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        drawableView.frame = bounds
        if isNativePlaybackControllerEnabled {
            installNativePlayerViewControllerIfPossible()
            applyNativePlayerLayout()
        }
        guard bounds.width > 1, bounds.height > 1 else { return }
        guard lastReportedBounds.size != bounds.size else { return }
        lastReportedBounds = bounds
        onBoundsChange?()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            removeNativePlayerViewController()
        } else if isNativePlaybackControllerEnabled {
            installNativePlayerViewControllerIfPossible()
        }
    }

    private func enclosingNavigationController() -> UINavigationController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let viewController = current as? UIViewController,
               let navigationController = viewController.navigationController {
                return navigationController
            }
            responder = current.next
        }
        return nil
    }

    private func configureNativePlayerViewController() {
        nativePlayerViewController.showsPlaybackControls = false
        nativePlayerViewController.videoGravity = .resizeAspect
        nativePlayerViewController.allowsPictureInPicturePlayback = true
        nativePlayerViewController.canStartPictureInPictureAutomaticallyFromInline = true
        nativePlayerViewController.requiresLinearPlayback = false
        nativePlayerViewController.updatesNowPlayingInfoCenter = false
        nativePlayerViewController.view.backgroundColor = .black
        nativePlayerViewController.view.isOpaque = true
    }

    private func installNativePlayerViewControllerIfPossible() {
        guard isNativePlaybackControllerEnabled else { return }
        guard let parentController = nearestViewController else { return }

        if nativePlayerViewController.parent !== parentController {
            removeNativePlayerViewController()
            parentController.addChild(nativePlayerViewController)
            drawableView.insertSubview(nativePlayerViewController.view, at: 0)
            nativePlayerViewController.didMove(toParent: parentController)
        } else if nativePlayerViewController.view.superview !== drawableView {
            nativePlayerViewController.view.removeFromSuperview()
            drawableView.insertSubview(nativePlayerViewController.view, at: 0)
        }

        applyNativePlayerLayout()
        nativePlayerViewController.view.isHidden = false
    }

    private func applyNativePlayerLayout() {
        AVPlayerLayoutCoordinator.shared.apply(
            playerController: nativePlayerViewController,
            in: drawableView,
            gravity: nativePlayerViewController.videoGravity
        )
    }

    private func removeNativePlayerViewController() {
        guard nativePlayerViewController.parent != nil || nativePlayerViewController.view.superview != nil else { return }
        nativePlayerViewController.willMove(toParent: nil)
        nativePlayerViewController.view.removeFromSuperview()
        nativePlayerViewController.removeFromParent()
    }
}

private extension UIView {
    var nearestViewController: UIViewController? {
        var responder: UIResponder? = self
        while let currentResponder = responder {
            if let viewController = currentResponder as? UIViewController {
                return viewController
            }
            responder = currentResponder.next
        }
        return nil
    }
}
