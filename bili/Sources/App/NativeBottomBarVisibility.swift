import SwiftUI
import UIKit

extension View {
    @ViewBuilder
    func coordinatesRootTabBarTransitions(
        isDetailPresented: Bool,
        isEnabled: Bool = true,
        onRootTabTap: (() -> Void)? = nil,
        capturesSearchReselection: Bool = false
    ) -> some View {
        if isEnabled {
            background(
                NativeRootTabBarTransitionSource(isDetailPresented: isDetailPresented, onRootTabTap: onRootTabTap, capturesSearchReselection: capturesSearchReselection)
            )
        } else {
            self
        }
    }
}

private struct NativeRootTabBarTransitionSource: UIViewControllerRepresentable {
    let isDetailPresented: Bool
    let onRootTabTap: (() -> Void)?
    let capturesSearchReselection: Bool

    func makeUIViewController(context _: Context) -> Controller {
        Controller(isDetailPresented: isDetailPresented, onRootTabTap: onRootTabTap, capturesSearchReselection: capturesSearchReselection)
    }

    func updateUIViewController(_ controller: Controller, context _: Context) {
        controller.onRootTabTap = onRootTabTap
        controller.capturesSearchReselection = capturesSearchReselection
        controller.installRootTabTap()
        controller.update(isDetailPresented: isDetailPresented)
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.removeRootTabTap()
    }

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        var onRootTabTap: (() -> Void)?
        var capturesSearchReselection: Bool
        private lazy var rootTabTap: UITapGestureRecognizer = {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleRootTabTap))
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            return recognizer
        }()
        private var isDetailPresented: Bool
        private var reconcileTask: Task<Void, Never>?

        init(isDetailPresented: Bool, onRootTabTap: (() -> Void)?, capturesSearchReselection: Bool) {
            self.isDetailPresented = isDetailPresented
            self.onRootTabTap = onRootTabTap
            self.capturesSearchReselection = capturesSearchReselection
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

        func update(isDetailPresented: Bool) {
            guard self.isDetailPresented != isDetailPresented else { return }
            self.isDetailPresented = isDetailPresented
            reconcileSoon()
        }

        func removeRootTabTap() {
            rootTabTap.view?.removeGestureRecognizer(rootTabTap)
        }

        // A minimized tab is a menu button: tapping it expands the bar without
        // calling the selection Binding. Unlike expanded tabs, the current menu
        // exposes an accessibility value. These tabs have no badge values.
        // Other tabs and search fields keep their normal path.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard onRootTabTap != nil, !isDetailPresented, viewIfLoaded?.window != nil,
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
                    guard isCollapsed || capturesSearchReselection else { return false }
                    // A re-tap of the selected Search button otherwise activates search.
                    // Search fields and ordinary tab changes never enter this branch.
                    rootTabTap.cancelsTouchesInView = capturesSearchReselection && !isCollapsed
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
            guard !isDetailPresented else { return }
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
                self.setRootTabBarHidden(self.isDetailPresented, animated: animated)
            }
        }

        private func reconcile(animated: Bool) {
            guard viewIfLoaded?.window != nil,
                  selectedNavigationController() != nil else { return }
            setRootTabBarHidden(isDetailPresented, animated: animated)
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
