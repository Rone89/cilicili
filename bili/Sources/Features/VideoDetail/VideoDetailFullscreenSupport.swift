import SwiftUI
import UIKit

struct FullscreenContainerGeometry {
    let size: CGSize
    let offset: CGSize
}

extension GeometryProxy {
    var fullscreenContainerGeometry: FullscreenContainerGeometry {
        if let window = UIApplication.shared.biliForegroundKeyWindow,
           let rootView = window.rootViewController?.view {
            let localFrame = frame(in: .global)
            let frameInWindow = rootView.convert(localFrame, from: nil)
            let resolvedSize = Self.resolvedFullscreenSize(
                windowSize: window.bounds.size,
                rootSize: rootView.bounds.size,
                orientation: window.windowScene?.effectiveGeometry.interfaceOrientation
            )
            return FullscreenContainerGeometry(
                size: resolvedSize,
                offset: CGSize(width: -frameInWindow.minX, height: -frameInWindow.minY)
            )
        }

        let expandedSize = CGSize(
            width: size.width + safeAreaInsets.leading + safeAreaInsets.trailing,
            height: size.height + safeAreaInsets.top + safeAreaInsets.bottom
        )
        return FullscreenContainerGeometry(
            size: expandedSize,
            offset: CGSize(width: -safeAreaInsets.leading, height: -safeAreaInsets.top)
        )
    }

    private static func resolvedFullscreenSize(
        windowSize: CGSize,
        rootSize: CGSize,
        orientation: UIInterfaceOrientation?
    ) -> CGSize {
        let candidates = [rootSize, windowSize].filter { $0.width > 1 && $0.height > 1 }
        guard let orientation else {
            return candidates.first ?? windowSize
        }

        if orientation.isLandscape {
            if let landscapeSize = candidates.first(where: { $0.width >= $0.height }) {
                return landscapeSize
            }
            let fallback = candidates.first ?? windowSize
            return CGSize(width: max(fallback.width, fallback.height), height: min(fallback.width, fallback.height))
        }

        if orientation.isPortrait {
            if let portraitSize = candidates.first(where: { $0.height >= $0.width }) {
                return portraitSize
            }
            let fallback = candidates.first ?? windowSize
            return CGSize(width: min(fallback.width, fallback.height), height: max(fallback.width, fallback.height))
        }

        return candidates.first ?? windowSize
    }
}

extension UIApplication {
    var videoDetailKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}

extension UIApplication {
    var biliForegroundKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}

struct VideoDetailChromeHiddenPreferenceKey: PreferenceKey {
    static var defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

struct StatusBarStyleBridge: UIViewControllerRepresentable {
    let style: UIStatusBarStyle
    let isHidden: Bool

    func makeUIViewController(context _: Context) -> Controller {
        Controller(style: style, isHidden: isHidden)
    }

    func updateUIViewController(_ uiViewController: Controller, context _: Context) {
        uiViewController.style = style
        uiViewController.isHidden = isHidden
    }

    final class Controller: UIViewController {
        var style: UIStatusBarStyle {
            didSet {
                requestChromeUpdate()
            }
        }
        var isHidden: Bool {
            didSet {
                requestChromeUpdate()
            }
        }

        init(style: UIStatusBarStyle, isHidden: Bool) {
            self.style = style
            self.isHidden = isHidden
            super.init(nibName: nil, bundle: nil)
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var preferredStatusBarStyle: UIStatusBarStyle {
            style
        }

        override var prefersStatusBarHidden: Bool {
            isHidden
        }

        override var prefersHomeIndicatorAutoHidden: Bool {
            isHidden
        }

        override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
            isHidden ? .all : []
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            requestChromeUpdate()
        }

        private func requestChromeUpdate() {
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
                controller.setNeedsStatusBarAppearanceUpdate()
                controller.setNeedsUpdateOfHomeIndicatorAutoHidden()
            }
        }
    }
}

struct VideoDetailLifecycleBridge: UIViewControllerRepresentable {
    let onWillDisappear: () -> Void
    let onDidAppear: () -> Void
    let onTransitionCompleted: (Bool) -> Void

    func makeUIViewController(context _: Context) -> Controller {
        let controller = Controller()
        controller.onWillDisappear = onWillDisappear
        controller.onDidAppear = onDidAppear
        controller.onTransitionCompleted = onTransitionCompleted
        return controller
    }

    func updateUIViewController(_ uiViewController: Controller, context _: Context) {
        uiViewController.onWillDisappear = onWillDisappear
        uiViewController.onDidAppear = onDidAppear
        uiViewController.onTransitionCompleted = onTransitionCompleted
    }

    final class Controller: UIViewController {
        var onWillDisappear: (() -> Void)?
        var onDidAppear: (() -> Void)?
        var onTransitionCompleted: ((Bool) -> Void)?
        private var isObservingTransition = false

        override func loadView() {
            view = ClearPassthroughView()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            guard !isObservingTransition else { return }
            guard let coordinator = transitionCoordinator else { return }
            guard isClosingNavigationTransition(coordinator) else { return }
            onWillDisappear?()
            isObservingTransition = true
            coordinator.animate(alongsideTransition: nil) { [weak self] context in
                guard let self else { return }
                self.isObservingTransition = false
                self.onTransitionCompleted?(context.isCancelled)
            }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            isObservingTransition = false
            onDidAppear?()
        }

        private func isClosingNavigationTransition(_ coordinator: UIViewControllerTransitionCoordinator) -> Bool {
            let fromViewController = coordinator.viewController(forKey: .from)
            let toViewController = coordinator.viewController(forKey: .to)
            let navController = fromViewController?.navigationController ?? navigationController

            if fromViewController?.isMovingFromParent == true
                || fromViewController?.isBeingDismissed == true
                || navController?.isBeingDismissed == true {
                return true
            }

            guard let fromViewController,
                  let toViewController,
                  let navController,
                  let toIndex = navController.viewControllers.firstIndex(where: { $0 === toViewController })
            else { return false }

            guard let fromIndex = navController.viewControllers.firstIndex(where: { $0 === fromViewController }) else {
                return true
            }
            return toIndex < fromIndex
        }
    }
}

struct VideoDetailRotationLayoutBridge: UIViewControllerRepresentable {
    let onLayoutTransition: () -> Void
    let onTransitionCompleted: () -> Void

    func makeUIViewController(context _: Context) -> Controller {
        let controller = Controller()
        controller.onLayoutTransition = onLayoutTransition
        controller.onTransitionCompleted = onTransitionCompleted
        return controller
    }

    func updateUIViewController(_ uiViewController: Controller, context _: Context) {
        uiViewController.onLayoutTransition = onLayoutTransition
        uiViewController.onTransitionCompleted = onTransitionCompleted
    }

    final class Controller: UIViewController {
        var onLayoutTransition: (() -> Void)?
        var onTransitionCompleted: (() -> Void)?

        override func loadView() {
            view = ClearPassthroughView()
        }

        override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
            super.viewWillTransition(to: size, with: coordinator)
            onLayoutTransition?()
            coordinator.animate(alongsideTransition: { [weak self] _ in
                self?.view.window?.layoutIfNeeded()
                self?.onLayoutTransition?()
            }, completion: { [weak self] _ in
                self?.view.window?.layoutIfNeeded()
                self?.onLayoutTransition?()
                self?.onTransitionCompleted?()
            })
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            onLayoutTransition?()
        }
    }
}

struct VideoDetailSystemBackGestureBridge: UIViewControllerRepresentable {
    let onNavigationGestureBegan: (() -> Void)?

    func makeUIViewController(context _: Context) -> Controller {
        Controller(onNavigationGestureBegan: onNavigationGestureBegan)
    }

    func updateUIViewController(_ uiViewController: Controller, context _: Context) {
        uiViewController.onNavigationGestureBegan = onNavigationGestureBegan
        uiViewController.restoreSystemBackGestures()
    }

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        private var configuredContentPopID: ObjectIdentifier?
        private var configuredScrollPanIDs = Set<ObjectIdentifier>()
        private weak var attachedNavigationController: UINavigationController?
        var onNavigationGestureBegan: (() -> Void)?

        init(onNavigationGestureBegan: (() -> Void)?) {
            self.onNavigationGestureBegan = onNavigationGestureBegan
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func loadView() {
            view = ClearPassthroughView()
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            restoreSoon()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            restoreSystemBackGestures()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            restoreSystemBackGestures()
        }

        func restoreSystemBackGestures() {
            guard let navigationController = enclosingNavigationController() else {
                return
            }
            attachedNavigationController = navigationController

            if let popGesture = navigationController.interactivePopGestureRecognizer {
                popGesture.isEnabled = true
                popGesture.delegate = self
            }

            guard let contentPopGesture = navigationController.interactiveContentPopGestureRecognizer else {
                return
            }
            contentPopGesture.isEnabled = true
            contentPopGesture.delegate = self
            prioritizeSystemContentPopGesture(contentPopGesture, in: navigationController.view)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let navigationController = attachedNavigationController ?? enclosingNavigationController(),
                  navigationController.viewControllers.count > 1,
                  navigationController.transitionCoordinator == nil
            else {
                return false
            }

            guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else {
                return true
            }

            let velocity = panGesture.velocity(in: navigationController.view)
            guard velocity.x > 0 && abs(velocity.x) > abs(velocity.y) else {
                return false
            }
            onNavigationGestureBegan?()
            return true
        }

        private func prioritizeSystemContentPopGesture(_ contentPopGesture: UIGestureRecognizer, in rootView: UIView) {
            let contentPopID = ObjectIdentifier(contentPopGesture)
            if configuredContentPopID != contentPopID {
                configuredContentPopID = contentPopID
                configuredScrollPanIDs.removeAll()
            }

            for scrollView in scrollViews(in: rootView) {
                let panGesture = scrollView.panGestureRecognizer
                let panID = ObjectIdentifier(panGesture)
                guard configuredScrollPanIDs.insert(panID).inserted else { continue }
                panGesture.require(toFail: contentPopGesture)
            }
        }

        private func scrollViews(in rootView: UIView) -> [UIScrollView] {
            var result = [UIScrollView]()
            var stack = rootView.subviews
            while let view = stack.popLast() {
                if let scrollView = view as? UIScrollView {
                    result.append(scrollView)
                }
                stack.append(contentsOf: view.subviews)
            }
            return result
        }

        private func restoreSoon() {
            DispatchQueue.main.async { [weak self] in
                self?.restoreSystemBackGestures()
            }
        }

        private func enclosingNavigationController() -> UINavigationController? {
            if let navigationController {
                return navigationController
            }

            var current = parent
            while let viewController = current {
                if let navigationController = viewController as? UINavigationController {
                    return navigationController
                }
                if let navigationController = viewController.navigationController {
                    return navigationController
                }
                current = viewController.parent
            }

            var responder: UIResponder? = view
            while let current = responder {
                if let viewController = current as? UIViewController,
                   let navigationController = viewController.navigationController {
                    return navigationController
                }
                responder = current.next
            }
            return nil
        }
    }
}
