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
    func makeUIViewController(context _: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context _: Context) {
        uiViewController.applyTransparency()
    }

    final class Controller: UIViewController {
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

            var current: UIViewController? = self
            while let viewController = current {
                viewController.view.backgroundColor = .clear
                viewController.view.isOpaque = false
                if let navigationController = viewController as? UINavigationController {
                    navigationController.view.backgroundColor = .clear
                    navigationController.view.isOpaque = false
                    AppNavigationChrome.applyTransparent(to: navigationController.navigationBar)
                } else if let navigationController = viewController.navigationController {
                    AppNavigationChrome.applyTransparent(to: navigationController.navigationBar)
                }
                current = viewController.parent
            }
        }

        private func applySoon() {
            DispatchQueue.main.async { [weak self] in
                self?.applyTransparency()
            }
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
