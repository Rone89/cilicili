import SwiftUI
import UIKit

enum AppNavigationChrome {
    static func configureGlobalAppearance() {
        let appearance = standardAppearance()
        let navigationBar = UINavigationBar.appearance()
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.compactScrollEdgeAppearance = appearance
        navigationBar.isTranslucent = false
        navigationBar.tintColor = .label
    }

    static func applyStandard(to navigationBar: UINavigationBar) {
        let appearance = standardAppearance()
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.compactScrollEdgeAppearance = appearance
        navigationBar.isTranslucent = false
        navigationBar.tintColor = .label
        navigationBar.barStyle = .default
    }

    static func applyTopLevel(to navigationBar: UINavigationBar) {
        let appearance = topLevelAppearance()
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.compactScrollEdgeAppearance = appearance
        navigationBar.isTranslucent = true
        navigationBar.tintColor = .label
        navigationBar.barStyle = .default
        navigationBar.backgroundColor = .clear
        navigationBar.isOpaque = false
    }

    static func topLevelAppearance() -> UINavigationBarAppearance {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        appearance.backgroundColor = UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor.black.withAlphaComponent(0.18)
            }
            return UIColor.systemBackground.withAlphaComponent(0.34)
        }
        appearance.shadowColor = .separator.withAlphaComponent(0.16)
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor.label
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor.label
        ]
        return appearance
    }

    static func applyTransparent(to navigationBar: UINavigationBar) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.compactScrollEdgeAppearance = appearance
        navigationBar.isTranslucent = true
        navigationBar.tintColor = .label
    }

    private static func standardAppearance() -> UINavigationBarAppearance {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .systemBackground
        appearance.backgroundEffect = nil
        appearance.shadowColor = .separator.withAlphaComponent(0.22)
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor.label
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor.label
        ]
        return appearance
    }
}

struct VideoNavigationHostTransparency: UIViewControllerRepresentable {
    var suppressesNavigationBar = false

    func makeUIViewController(context _: Context) -> Controller {
        Controller(suppressesNavigationBar: suppressesNavigationBar)
    }

    func updateUIViewController(_ uiViewController: Controller, context _: Context) {
        uiViewController.suppressesNavigationBar = suppressesNavigationBar
        uiViewController.applyTransparency()
    }

    final class Controller: UIViewController {
        var suppressesNavigationBar: Bool

        init(suppressesNavigationBar: Bool) {
            self.suppressesNavigationBar = suppressesNavigationBar
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
            applySoon()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyTransparency()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            applyTransparency()
        }

        func applyTransparency() {
            view.backgroundColor = .clear
            view.isOpaque = false

            guard let navigationController = enclosingNavigationController() else {
                return
            }

            navigationController.view.backgroundColor = .clear
            navigationController.view.isOpaque = false
            navigationController.topViewController?.view.backgroundColor = .clear
            navigationController.topViewController?.view.isOpaque = false

            // Keep the hidden overlay bar stable during interactive pop. The
            // visible top-level pages install their own translucent chrome.
            AppNavigationChrome.applyStandard(to: navigationController.navigationBar)
        }

        private func applySoon() {
            DispatchQueue.main.async { [weak self] in
                self?.applyTransparency()
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

struct VideoNavigationTransitionObserver: UIViewControllerRepresentable {
    let isClosing: Bool
    let onTransitionCompleted: () -> Void

    func makeUIViewController(context _: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context _: Context) {
        uiViewController.onTransitionCompleted = onTransitionCompleted
        uiViewController.update(isClosing: isClosing)
    }

    final class Controller: UIViewController {
        var onTransitionCompleted: (() -> Void)?
        private var isScheduled = false

        override func loadView() {
            view = ClearPassthroughView()
        }

        func update(isClosing: Bool) {
            guard isClosing else {
                isScheduled = false
                return
            }
            guard !isScheduled else { return }
            isScheduled = true

            let finish: (Bool) -> Void = { [weak self] cancelled in
                guard let self else { return }
                self.isScheduled = false
                guard !cancelled else { return }
                self.onTransitionCompleted?()
            }

            if let coordinator = enclosingNavigationController()?.transitionCoordinator {
                coordinator.animate(alongsideTransition: nil) { context in
                    finish(context.isCancelled)
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
                    finish(false)
                }
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

final class ClearPassthroughView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
