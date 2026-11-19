import SwiftUI
import UIKit

extension View {
    /// Coordinates root `UITabBar` push/pop visibility via `UITabBarController.setTabBarHidden`.
    ///
    /// IMPORTANT: Do NOT add `.toolbarVisibility(.hidden, for: .tabBar)` or `.toolbar(.hidden, for: .tabBar)`
    /// on pushed secondary/detail views. Mixing declarative `.toolbarVisibility(.hidden, for: .tabBar)` with
    /// `setTabBarHidden` detaches `UITabBarController._observingScrollView` on pop (breaking scroll-minimization),
    /// while relying on `.toolbarVisibility(.hidden, for: .tabBar)` alone causes the TabBar to flash in abruptly
    /// after the pop transition completes.
    @ViewBuilder
    func coordinatesRootTabBarTransitions(
        isDetailPresented: Bool,
        isEnabled: Bool = true,
        hidesRootTabBar: Bool = false,
        onRootTabTap: (() -> Void)? = nil,
        capturesSelectedTabTap: Bool = false,
        isSearchTab: Bool = false
    ) -> some View {
        if isEnabled {
            background(
                NativeRootTabBarTransitionSource(isDetailPresented: isDetailPresented, hidesRootTabBar: hidesRootTabBar, onRootTabTap: onRootTabTap, capturesSelectedTabTap: capturesSelectedTabTap, isSearchTab: isSearchTab)
            )
        } else {
            self
        }
    }
}

private struct NativeRootTabBarTransitionSource: UIViewControllerRepresentable {
    let isDetailPresented: Bool
    let hidesRootTabBar: Bool
    let onRootTabTap: (() -> Void)?
    let capturesSelectedTabTap: Bool
    let isSearchTab: Bool

    func makeUIViewController(context _: Context) -> Controller {
        Controller(isDetailPresented: isDetailPresented, hidesRootTabBar: hidesRootTabBar, onRootTabTap: onRootTabTap, capturesSelectedTabTap: capturesSelectedTabTap, isSearchTab: isSearchTab)
    }

    func updateUIViewController(_ controller: Controller, context _: Context) {
        controller.onRootTabTap = onRootTabTap
        controller.capturesSelectedTabTap = capturesSelectedTabTap
        controller.isSearchTab = isSearchTab
        controller.installRootTabTap()
        controller.update(isDetailPresented: isDetailPresented, hidesRootTabBar: hidesRootTabBar)
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.removeRootTabTap()
    }

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        var onRootTabTap: (() -> Void)?
        var capturesSelectedTabTap: Bool
        var isSearchTab: Bool
        private lazy var rootTabTap: UITapGestureRecognizer = {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleRootTabTap))
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            return recognizer
        }()
        private var hidesRootTabBar: Bool
        private var isDetailPresented: Bool
        private var reconcileTask: Task<Void, Never>?

        init(isDetailPresented: Bool, hidesRootTabBar: Bool, onRootTabTap: (() -> Void)?, capturesSelectedTabTap: Bool, isSearchTab: Bool) {
            self.isDetailPresented = isDetailPresented
            self.hidesRootTabBar = hidesRootTabBar
            self.onRootTabTap = onRootTabTap
            self.capturesSelectedTabTap = capturesSelectedTabTap
            self.isSearchTab = isSearchTab
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func loadView() {
            let view = UIView(frame: .zero)
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
            self.view = view
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            reconcile(animated: false)
            installRootTabTap()
        }

        func installRootTabTap() {
            if onRootTabTap != nil, let tabBar = enclosingTabBarController()?.tabBar, rootTabTap.view !== tabBar {
                tabBar.addGestureRecognizer(rootTabTap)
            }
        }

        func update(isDetailPresented: Bool, hidesRootTabBar: Bool) {
            guard self.isDetailPresented != isDetailPresented || self.hidesRootTabBar != hidesRootTabBar else { return }
            self.isDetailPresented = isDetailPresented
            self.hidesRootTabBar = hidesRootTabBar
            reconcileSoon()
        }

        func removeRootTabTap() {
            rootTabTap.view?.removeGestureRecognizer(rootTabTap)
        }

        // A minimized tab is a menu button with a non-nil accessibility value:
        // let its first tap only expand the tab bar without triggering scroll-to-top.
        // Once expanded, capture taps that leave a menu-only page or would
        // activate a Search field instead of reselecting the tab.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard onRootTabTap != nil,
                  !isDetailPresented,
                  !hidesRootTabBar,
                  viewIfLoaded?.window != nil,
                  (selectedNavigationController()?.viewControllers.count ?? 1) <= 1,
                  let controller = enclosingTabBarController() else { return false }
            guard let selectedTitle = controller.selectedTab?.title
                ?? controller.selectedViewController?.tabBarItem.title
                ?? controller.tabBar.selectedItem?.title else { return false }
            let tabBar = controller.tabBar
            var touchedView = touch.view
            while let candidate = touchedView, candidate !== tabBar {
                if candidate.accessibilityLabel == selectedTitle,
                   candidate.accessibilityTraits.contains(.button) {
                    let isCollapsed = candidate.accessibilityValue != nil
                    if isCollapsed {
                        guard isSearchTab else { return false }
                        rootTabTap.cancelsTouchesInView = true
                        return true
                    }
                    guard capturesSelectedTabTap else { return false }
                    rootTabTap.cancelsTouchesInView = true
                    return true
                }
                touchedView = candidate.superview
            }
            return false
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        @objc private func handleRootTabTap() {
            guard !isDetailPresented, !hidesRootTabBar else { return }
            onRootTabTap?()
        }

        private func reconcileSoon() {
            reconcileTask?.cancel()
            reconcileTask = Task { @MainActor [weak self] in
                await Task.yield()
                guard !Task.isCancelled,
                      let self,
                      self.viewIfLoaded?.window != nil,
                      let navigationController = self.selectedNavigationController() else { return }
                let animated = navigationController.transitionCoordinator != nil
                self.setRootTabBarHidden(self.isDetailPresented || self.hidesRootTabBar, animated: animated)
            }
        }

        private func reconcile(animated: Bool) {
            guard viewIfLoaded?.window != nil,
                  selectedNavigationController() != nil else { return }
            setRootTabBarHidden(isDetailPresented || hidesRootTabBar, animated: animated)
        }

        private func setRootTabBarHidden(_ hidden: Bool, animated: Bool) {
            guard let tabBarController = enclosingTabBarController(),
                  tabBarController.isTabBarHidden != hidden else { return }
            tabBarController.setTabBarHidden(hidden, animated: animated)
        }

        private func enclosingTabBarController() -> UITabBarController? {
            if let tabBarController { return tabBarController }
            var responder: UIResponder? = view
            while let current = responder {
                if let tabBarController = current as? UITabBarController { return tabBarController }
                responder = current.next
            }
            return nil
        }

        private func selectedNavigationController() -> UINavigationController? {
            guard let selected = enclosingTabBarController()?.selectedViewController else { return nil }
            return navigationController(in: selected)
        }

        private func navigationController(in controller: UIViewController) -> UINavigationController? {
            if let navigationController = controller as? UINavigationController {
                return navigationController
            }
            for child in controller.children {
                if let navigationController = navigationController(in: child) {
                    return navigationController
                }
            }
            return nil
        }
    }
}
