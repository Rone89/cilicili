import SwiftUI
import UIKit

extension View {
    func hidesRootTabBarOnPush() -> some View {
        background(NativeBottomBarOnPushHider())
    }

    func keepsRootTabBarHiddenDuringPresentation() -> some View {
        background(NativeBottomBarPresentationHider())
    }
}

private struct NativeBottomBarOnPushHider: UIViewControllerRepresentable {
    func makeUIViewController(context _: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context _: Context) {
        uiViewController.apply()
    }

    final class Controller: UIViewController {
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
            setRootTabBarHidden(false, animated: animated)
        }

        private func setRootTabBarHidden(_ hidden: Bool, animated: Bool) {
            guard let tabBarController = rootTabBarController() else {
                rootTabBar()?.isHidden = hidden
                return
            }

            guard tabBarController.isTabBarHidden != hidden else { return }
            tabBarController.setTabBarHidden(hidden, animated: animated)
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
        private var restoreTask: Task<Void, Never>?

        override func loadView() {
            view = PassthroughView()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            restoreTask?.cancel()
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
            restoreTask?.cancel()
            restoreTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 260_000_000)
                self?.setRootTabBarHidden(false, animated: animated)
            }
        }

        private func setRootTabBarHidden(_ hidden: Bool, animated: Bool) {
            guard let tabBarController = rootTabBarController() else {
                rootTabBar()?.isHidden = hidden
                return
            }

            guard tabBarController.isTabBarHidden != hidden else { return }
            tabBarController.setTabBarHidden(hidden, animated: animated)
        }

        private func rootTabBar() -> UITabBar? {
            rootTabBarController()?.tabBar
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

        deinit {
            restoreTask?.cancel()
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
