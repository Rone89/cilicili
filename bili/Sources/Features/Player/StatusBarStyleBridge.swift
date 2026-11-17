import SwiftUI
import UIKit

struct StatusBarStyleBridge: UIViewControllerRepresentable {
    let style: UIStatusBarStyle
    let isHidden: Bool

    func makeUIViewController(context _: Context) -> Controller {
        Controller(style: style, isHidden: isHidden)
    }

    func updateUIViewController(_ uiViewController: Controller, context _: Context) {
        uiViewController.update(style: style, isHidden: isHidden)
    }

    final class Controller: UIViewController {
        private(set) var style: UIStatusBarStyle
        private(set) var isHidden: Bool
        private var isChromeActive = false
        private weak var styledNavigationBar: UINavigationBar?
        private var savedBarStyle: UIBarStyle?
        private var savedBarInterfaceStyle: UIUserInterfaceStyle?

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

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            isChromeActive = true
            applyNavigationBarStyleIfNeeded()
            requestChromeUpdate()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            isChromeActive = true
            applyNavigationBarStyleIfNeeded()
            requestChromeUpdate()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            isChromeActive = false
            restoreNavigationBarStyle()
            requestChromeUpdate()
            transitionCoordinator?.notifyWhenInteractionChanges { [weak self] context in
                guard let self, context.isCancelled else { return }
                self.isChromeActive = true
                self.applyNavigationBarStyleIfNeeded()
                self.requestChromeUpdate()
            }
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            if parent == nil {
                isChromeActive = false
                restoreNavigationBarStyle()
                requestChromeUpdate()
            } else if isChromeActive {
                applyNavigationBarStyleIfNeeded()
                requestChromeUpdate()
            }
        }

        func update(style: UIStatusBarStyle, isHidden: Bool) {
            let changed = self.style != style || self.isHidden != isHidden
            self.style = style
            self.isHidden = isHidden
            if isChromeActive && style == .lightContent && !isHidden {
                applyNavigationBarStyleIfNeeded()
            } else {
                restoreNavigationBarStyle()
            }
            if changed {
                requestChromeUpdate()
            }
        }

        private func applyNavigationBarStyleIfNeeded() {
            guard isChromeActive,
                  style == .lightContent,
                  !isHidden,
                  let bar = navigationController?.navigationBar,
                  !bar.isHidden
            else {
                return
            }
            if styledNavigationBar !== bar {
                restoreNavigationBarStyle()
                styledNavigationBar = bar
                savedBarStyle = bar.barStyle
                savedBarInterfaceStyle = bar.overrideUserInterfaceStyle
            }
            if bar.barStyle != .black {
                bar.barStyle = .black
            }
            if bar.overrideUserInterfaceStyle != .dark {
                bar.overrideUserInterfaceStyle = .dark
            }
        }

        private func restoreNavigationBarStyle() {
            guard let bar = styledNavigationBar else { return }
            if let savedBarStyle {
                bar.barStyle = savedBarStyle
            }
            if let savedBarInterfaceStyle {
                bar.overrideUserInterfaceStyle = savedBarInterfaceStyle
            }
            styledNavigationBar = nil
            savedBarStyle = nil
            savedBarInterfaceStyle = nil
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

            var updatedControllers = Set<ObjectIdentifier>()
            controllers.forEach { controller in
                guard updatedControllers.insert(ObjectIdentifier(controller)).inserted else { return }
                controller.setNeedsStatusBarAppearanceUpdate()
                controller.setNeedsUpdateOfHomeIndicatorAutoHidden()
                controller.setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
            }
        }
    }
}
