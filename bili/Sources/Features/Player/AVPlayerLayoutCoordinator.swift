import AVFoundation
import AVKit
import UIKit

@MainActor
final class AVPlayerLayoutCoordinator {
    static let shared = AVPlayerLayoutCoordinator()

    private init() {}

    func apply(
        playerLayer: AVPlayerLayer?,
        in containerView: UIView?,
        gravity: AVLayerVideoGravity
    ) {
        guard let playerLayer, let containerView else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.videoGravity = gravity
        playerLayer.frame = containerView.bounds
        playerLayer.position = CGPoint(x: containerView.bounds.midX, y: containerView.bounds.midY)
        CATransaction.commit()
    }

    func apply(
        playerController: AVPlayerViewController,
        in containerView: UIView,
        gravity: AVLayerVideoGravity
    ) {
        apply(
            playerController: playerController,
            bounds: containerView.bounds,
            gravity: gravity
        )
    }

    func apply(
        playerController: AVPlayerViewController,
        bounds: CGRect,
        gravity: AVLayerVideoGravity
    ) {
        playerController.videoGravity = gravity
        playerController.view.bounds = CGRect(origin: .zero, size: bounds.size)
        playerController.view.center = CGPoint(x: bounds.midX, y: bounds.midY)
        playerController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        playerController.view.setNeedsLayout()
        playerController.view.layoutIfNeeded()
    }

    func transition(
        to _: CGSize,
        coordinator: UIViewControllerTransitionCoordinator,
        layout: @escaping @MainActor () -> Void
    ) {
        layout()
        coordinator.animate(alongsideTransition: { _ in
            Task { @MainActor in
                layout()
            }
        }, completion: { _ in
            Task { @MainActor in
                layout()
            }
        })
    }
}
