import SwiftUI
import UIKit

extension View {
    func hidesRootTabBarOnPush(restoreDelay: UInt64 = 0) -> some View {
        background(NativeBottomBarOnPushHider(restoreDelay: restoreDelay))
    }

    func keepsRootTabBarHiddenDuringPresentation() -> some View {
        background(NativeBottomBarPresentationHider())
    }
}

@MainActor
private enum NativeBottomBarVisibilityCoordinator {
    private static var restoreTask: Task<Void, Never>?
    private static let imageViewerReturnDelay: UInt64 = 520_000_000

    static func hide(tabBarController: UITabBarController?, fallbackTabBar: UITabBar?, animated: Bool) {
        restoreTask?.cancel()
        restoreTask = nil
        setHidden(true, tabBarController: tabBarController, fallbackTabBar: fallbackTabBar, animated: animated)
    }

    static func restoreAfterImageViewerReturn(
        tabBarController: UITabBarController?,
        fallbackTabBar: UITabBar?,
        animated: Bool = false
    ) {
        restore(tabBarController: tabBarController, fallbackTabBar: fallbackTabBar, animated: animated, delay: imageViewerReturnDelay)
    }

    static func keepHiddenAfterImageViewerReturn(
        tabBarController: UITabBarController?,
        fallbackTabBar: UITabBar?
    ) {
        restoreTask?.cancel()
        restoreTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: imageViewerReturnDelay)
            guard !Task.isCancelled else { return }
            setHidden(true, tabBarController: tabBarController, fallbackTabBar: fallbackTabBar, animated: false)
        }
    }

    static func restore(
        tabBarController: UITabBarController?,
        fallbackTabBar: UITabBar?,
        animated: Bool,
        delay: UInt64
    ) {
        restoreTask?.cancel()
        guard tabBarController != nil || fallbackTabBar != nil else { return }
        restoreTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            setHidden(false, tabBarController: tabBarController, fallbackTabBar: fallbackTabBar, animated: animated)
        }
    }

    private static func setHidden(
        _ hidden: Bool,
        tabBarController: UITabBarController?,
        fallbackTabBar: UITabBar?,
        animated: Bool
    ) {
        if let tabBarController {
            guard tabBarController.isTabBarHidden != hidden else { return }
            tabBarController.setTabBarHidden(hidden, animated: animated)
        } else {
            fallbackTabBar?.isHidden = hidden
        }
    }

    static func isActuallyVisible(tabBarController: UITabBarController?, fallbackTabBar: UITabBar?) -> Bool {
        guard let tabBar = tabBarController?.tabBar ?? fallbackTabBar else { return true }
        guard !tabBar.isHidden, tabBar.alpha > 0.01, let superview = tabBar.superview else {
            return false
        }
        let frameInSuperview = tabBar.layer.presentation()?.frame ?? tabBar.frame
        let visibleHeight = frameInSuperview.intersection(superview.bounds).height
        return visibleHeight > 8
    }
}

private struct NativeBottomBarOnPushHider: UIViewControllerRepresentable {
    let restoreDelay: UInt64

    func makeUIViewController(context _: Context) -> Controller {
        Controller(restoreDelay: restoreDelay)
    }

    func updateUIViewController(_ uiViewController: Controller, context _: Context) {
        uiViewController.apply()
    }

    final class Controller: UIViewController {
        private let restoreDelay: UInt64

        init(restoreDelay: UInt64) {
            self.restoreDelay = restoreDelay
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func loadView() {
            view = PassthroughView()
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            applySoon()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            apply()
            hideRootTabBar(animated: animated)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            apply()
            hideRootTabBar(animated: false)
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            restoreRootTabBarIfNeeded(animated: animated)
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            apply()
        }

        func apply() {
            guard let navigationController = enclosingNavigationController() else { return }

            if let pushedController = pushedController(in: navigationController) {
                pushedController.hidesBottomBarWhenPushed = true
            }

            navigationController.topViewController?.hidesBottomBarWhenPushed = true
        }

        private func applySoon() {
            DispatchQueue.main.async { [weak self] in
                self?.apply()
            }
        }

        private func enclosingNavigationController() -> UINavigationController? {
            if let navigationController {
                return navigationController
            }

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

        private func pushedController(in navigationController: UINavigationController) -> UIViewController? {
            var current: UIViewController? = parent
            var lastInsideNavigationStack: UIViewController?

            while let viewController = current {
                if viewController === navigationController {
                    break
                }
                lastInsideNavigationStack = viewController
                current = viewController.parent
            }

            return lastInsideNavigationStack
        }

        private func rootTabBar() -> UITabBar? {
            enclosingNavigationController()?.tabBarController?.tabBar
        }

        private func rootTabBarController() -> UITabBarController? {
            enclosingNavigationController()?.tabBarController
        }

        private func hideRootTabBar(animated: Bool) {
            setRootTabBarHidden(true, animated: animated)
        }

        private func restoreRootTabBarIfNeeded(animated: Bool) {
            guard shouldRevealRootTabBarOnDisappear() else {
                hideRootTabBar(animated: animated)
                return
            }

            let tabBarController = rootTabBarController()
            let fallbackTabBar = rootTabBar()
            NativeBottomBarVisibilityCoordinator.hide(
                tabBarController: tabBarController,
                fallbackTabBar: fallbackTabBar,
                animated: false
            )

            guard let coordinator = enclosingNavigationController()?.transitionCoordinator else {
                NativeBottomBarVisibilityCoordinator.restore(
                    tabBarController: tabBarController,
                    fallbackTabBar: fallbackTabBar,
                    animated: false,
                    delay: restoreDelay
                )
                return
            }

            coordinator.animate(alongsideTransition: nil) { context in
                Task { @MainActor in
                    if context.isCancelled {
                        NativeBottomBarVisibilityCoordinator.hide(
                            tabBarController: tabBarController,
                            fallbackTabBar: fallbackTabBar,
                            animated: false
                        )
                    } else {
                        NativeBottomBarVisibilityCoordinator.restore(
                            tabBarController: tabBarController,
                            fallbackTabBar: fallbackTabBar,
                            animated: false,
                            delay: self.restoreDelay
                        )
                    }
                }
            }
        }

        private func setRootTabBarHidden(_ hidden: Bool, animated: Bool) {
            if hidden {
                NativeBottomBarVisibilityCoordinator.hide(
                    tabBarController: rootTabBarController(),
                    fallbackTabBar: rootTabBar(),
                    animated: animated
                )
            } else {
                NativeBottomBarVisibilityCoordinator.restore(
                    tabBarController: rootTabBarController(),
                    fallbackTabBar: rootTabBar(),
                    animated: animated,
                    delay: 0
                )
            }
        }

        private func shouldRevealRootTabBarOnDisappear() -> Bool {
            guard let navigationController = enclosingNavigationController(),
                  let rootController = navigationController.viewControllers.first
            else {
                return false
            }

            if let coordinator = navigationController.transitionCoordinator,
               let targetController = coordinator.viewController(forKey: .to) {
                return isSameControllerTree(rootController, targetController)
            }

            return navigationController.topViewController === rootController
        }

        private func isSameControllerTree(_ lhs: UIViewController, _ rhs: UIViewController) -> Bool {
            lhs === rhs || isAncestor(lhs, of: rhs) || isAncestor(rhs, of: lhs)
        }

        private func isAncestor(_ ancestor: UIViewController, of child: UIViewController) -> Bool {
            var current = child.parent
            while let viewController = current {
                if viewController === ancestor {
                    return true
                }
                current = viewController.parent
            }
            return false
        }
    }

    private final class PassthroughView: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

}

private struct NativeBottomBarPresentationHider: UIViewControllerRepresentable {
    func makeUIViewController(context _: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context _: Context) {
        uiViewController.hideRootTabBar(animated: false)
    }

    final class Controller: UIViewController {
        private var capturedInitialVisibility: Bool?

        override func loadView() {
            view = PassthroughView()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            captureInitialVisibilityIfNeeded()
            hideRootTabBar(animated: animated)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            hideRootTabBar(animated: false)
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            hideRootTabBar(animated: false)
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            scheduleRestoreRootTabBar(animated: animated)
        }

        func hideRootTabBar(animated: Bool) {
            setRootTabBarHidden(true, animated: animated)
        }

        private func scheduleRestoreRootTabBar(animated: Bool) {
            let tabBarController = rootTabBarController()
            let fallbackTabBar = rootTabBar()
            if capturedInitialVisibility == false {
                NativeBottomBarVisibilityCoordinator.keepHiddenAfterImageViewerReturn(
                    tabBarController: tabBarController,
                    fallbackTabBar: fallbackTabBar
                )
            } else {
                NativeBottomBarVisibilityCoordinator.restoreAfterImageViewerReturn(
                    tabBarController: tabBarController,
                    fallbackTabBar: fallbackTabBar,
                    animated: true
                )
            }
            capturedInitialVisibility = nil
        }

        private func setRootTabBarHidden(_ hidden: Bool, animated: Bool) {
            if hidden {
                NativeBottomBarVisibilityCoordinator.hide(
                    tabBarController: rootTabBarController(),
                    fallbackTabBar: rootTabBar(),
                    animated: animated
                )
            } else {
                NativeBottomBarVisibilityCoordinator.restoreAfterImageViewerReturn(
                    tabBarController: rootTabBarController(),
                    fallbackTabBar: rootTabBar(),
                    animated: false
                )
            }
        }

        private func rootTabBar() -> UITabBar? {
            rootTabBarController()?.tabBar
        }

        private func captureInitialVisibilityIfNeeded() {
            guard capturedInitialVisibility == nil else { return }
            capturedInitialVisibility = NativeBottomBarVisibilityCoordinator.isActuallyVisible(
                tabBarController: rootTabBarController(),
                fallbackTabBar: rootTabBar()
            )
        }

        private func rootTabBarController() -> UITabBarController? {
            var responder: UIResponder? = self
            while let current = responder {
                if let viewController = current as? UIViewController,
                   let tabBarController = viewController.tabBarController {
                    return tabBarController
                }
                responder = current.next
            }
            return view.window?.rootViewController?.descendantTabBarController()
        }
    }

    private final class PassthroughView: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}

private extension UIViewController {
    func descendantTabBarController() -> UITabBarController? {
        if let tabBarController = self as? UITabBarController {
            return tabBarController
        }
        for child in children {
            if let tabBarController = child.descendantTabBarController() {
                return tabBarController
            }
        }
        if let presentedViewController,
           let tabBarController = presentedViewController.descendantTabBarController() {
            return tabBarController
        }
        return nil
    }
}
