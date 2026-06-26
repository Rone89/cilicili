import SwiftUI
import UIKit

struct VideoDetailRotationLayoutBridge: UIViewControllerRepresentable {
    let supportedOrientations: UIInterfaceOrientationMask
    let hidesSystemChrome: Bool
    let onLayoutTransitionBegan: () -> Void
    let onLayoutTransition: () -> Void
    let onTransitionCompleted: () -> Void

    func makeUIViewController(context _: Context) -> Controller {
        let controller = Controller()
        controller.supportedOrientations = supportedOrientations
        controller.hidesSystemChrome = hidesSystemChrome
        controller.onLayoutTransitionBegan = onLayoutTransitionBegan
        controller.onLayoutTransition = onLayoutTransition
        controller.onTransitionCompleted = onTransitionCompleted
        return controller
    }

    func updateUIViewController(_ uiViewController: Controller, context _: Context) {
        uiViewController.supportedOrientations = supportedOrientations
        uiViewController.hidesSystemChrome = hidesSystemChrome
        uiViewController.onLayoutTransitionBegan = onLayoutTransitionBegan
        uiViewController.onLayoutTransition = onLayoutTransition
        uiViewController.onTransitionCompleted = onTransitionCompleted
    }

    final class Controller: UIViewController {
        var supportedOrientations: UIInterfaceOrientationMask = .portrait {
            didSet {
                guard supportedOrientations != oldValue else { return }
                requestInterfaceUpdate()
                syncAppOrientationLock()
            }
        }
        var hidesSystemChrome = false {
            didSet {
                guard hidesSystemChrome != oldValue else { return }
                requestInterfaceUpdate()
            }
        }
        var onLayoutTransitionBegan: (() -> Void)?
        var onLayoutTransition: (() -> Void)?
        var onTransitionCompleted: (() -> Void)?
        private var lastReportedLayoutSize: CGSize = .zero

        override func loadView() {
            view = ClearPassthroughView()
        }

        override var shouldAutorotate: Bool {
            true
        }

        override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
            supportedOrientations
        }

        override var preferredStatusBarStyle: UIStatusBarStyle {
            .lightContent
        }

        override var prefersStatusBarHidden: Bool {
            hidesSystemChrome
        }

        override var prefersHomeIndicatorAutoHidden: Bool {
            hidesSystemChrome
        }

        override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
            hidesSystemChrome ? .all : []
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            requestInterfaceUpdate()
            syncAppOrientationLock()
        }

        override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
            super.viewWillTransition(to: size, with: coordinator)
            onLayoutTransitionBegan?()
            reportLayoutTransitionIfNeeded(force: true)
            coordinator.animate(alongsideTransition: { [weak self] _ in
                self?.reportLayoutTransitionIfNeeded(force: true)
            }, completion: { [weak self] _ in
                self?.reportLayoutTransitionIfNeeded(force: true)
                self?.onTransitionCompleted?()
                self?.schedulePostTransitionLayoutInvalidations()
            })
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            reportLayoutTransitionIfNeeded()
        }

        private func reportLayoutTransitionIfNeeded(force: Bool = false) {
            let size = view.bounds.size
            guard size.width > 1, size.height > 1 else { return }
            guard force || !lastReportedLayoutSize.isNearlyEqual(to: size) else { return }
            lastReportedLayoutSize = size
            onLayoutTransition?()
        }

        private func schedulePostTransitionLayoutInvalidations() {
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.reportLayoutTransitionIfNeeded(force: true)
                try? await Task.sleep(nanoseconds: 80_000_000)
                self?.reportLayoutTransitionIfNeeded(force: true)
                try? await Task.sleep(nanoseconds: 180_000_000)
                self?.reportLayoutTransitionIfNeeded(force: true)
            }
        }

        private func requestInterfaceUpdate() {
            var controllers = [UIViewController]()
            var current: UIViewController? = self
            while let controller = current {
                controllers.append(controller)
                current = controller.parent
            }
            if let navigationController {
                controllers.append(navigationController)
            }
            if let tabBarController {
                controllers.append(tabBarController)
            }
            if let root = view.window?.rootViewController {
                controllers.append(root)
            }

            controllers.forEach { controller in
                controller.setNeedsUpdateOfSupportedInterfaceOrientations()
                controller.setNeedsStatusBarAppearanceUpdate()
                controller.setNeedsUpdateOfHomeIndicatorAutoHidden()
            }
        }

        private func syncAppOrientationLock() {
            AppOrientationLock.update(
                to: supportedOrientations,
                in: view.window?.windowScene,
                requestsGeometryUpdate: supportedOrientations == .portrait
            )
        }
    }
}

private extension CGSize {
    func isNearlyEqual(to other: CGSize) -> Bool {
        abs(width - other.width) < 0.5 && abs(height - other.height) < 0.5
    }
}
