import Combine
import SwiftUI
import UIKit

@MainActor
final class RootHomeViewModelHolder: ObservableObject {
    @Published var viewModel: HomeViewModel?

    func configure(
        api: BiliAPIClient,
        libraryStore: LibraryStore,
        sessionStore: SessionStore,
        initialMode: HomeFeedMode
    ) {
        if viewModel == nil {
            let viewModel = HomeViewModel(
                api: api,
                libraryStore: libraryStore,
                sessionStore: sessionStore,
                initialMode: initialMode
            )
            self.viewModel = viewModel
        }
    }
}

enum BottomTabMode {
    case root
    case video
}

extension Notification.Name {
    static let biliPauseActiveVideoPlaybackForNavigation = Notification.Name("cc.bili.pauseActiveVideoPlaybackForNavigation")
    static let biliResumeActiveVideoPlaybackAfterCancelledNavigation = Notification.Name("cc.bili.resumeActiveVideoPlaybackAfterCancelledNavigation")
    static let biliStopActiveVideoPlayback = Notification.Name("cc.bili.stopActiveVideoPlayback")
}

extension View {
    func videoDestinations() -> some View {
        navigationDestination(for: VideoItem.self) { video in
            VideoDetailView(seedVideo: video)
        }
        .navigationDestination(for: VideoOwner.self) { owner in
            UploaderView(owner: owner)
        }
        .navigationDestination(for: LiveRoom.self) { room in
            LiveRoomDetailView(seedRoom: room)
        }
    }
}

struct NavigationChromeInstaller: UIViewControllerRepresentable {
    let isStandardChromeEnabled: Bool

    func makeUIViewController(context _: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context _: Context) {
        uiViewController.isStandardChromeEnabled = isStandardChromeEnabled
        uiViewController.apply()
    }

    final class Controller: UIViewController {
        var isStandardChromeEnabled = false

        override func loadView() {
            view = ClearPassthroughView()
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            applySoon()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            apply()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            apply()
        }

        func apply() {
            guard isStandardChromeEnabled else { return }
            guard let navigationController = enclosingNavigationController() else { return }
            AppNavigationChrome.applyStandard(to: navigationController.navigationBar)
        }

        private func applySoon() {
            DispatchQueue.main.async { [weak self] in
                self?.apply()
            }
        }

        private func enclosingNavigationController() -> UINavigationController? {
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
    }
}

struct RootTabBarAppearanceInstaller: UIViewControllerRepresentable {
    func makeUIViewController(context _: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context _: Context) {
        controller.applySoon()
    }

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyAppearance()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            applyAppearance()
        }

        func applySoon() {
            DispatchQueue.main.async { [weak self] in
                self?.applyAppearance()
            }
        }

        private func applyAppearance() {
            guard let tabBar = tabBarController?.tabBar ?? enclosingTabBarController()?.tabBar else { return }

            let appearance = UITabBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
            appearance.backgroundColor = UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark
                    ? UIColor.black.withAlphaComponent(0.18)
                    : UIColor.systemBackground.withAlphaComponent(0.16)
            }
            appearance.shadowColor = UIColor.label.withAlphaComponent(0.04)

            let normalColor = UIColor.secondaryLabel.withAlphaComponent(0.82)
            let selectedColor = UIColor.systemPink
            configure(appearance.stackedLayoutAppearance, normalColor: normalColor, selectedColor: selectedColor)
            configure(appearance.inlineLayoutAppearance, normalColor: normalColor, selectedColor: selectedColor)
            configure(appearance.compactInlineLayoutAppearance, normalColor: normalColor, selectedColor: selectedColor)

            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
            tabBar.tintColor = selectedColor
            tabBar.unselectedItemTintColor = normalColor
            tabBar.isTranslucent = true
            tabBar.backgroundColor = .clear
            tabBar.layer.shadowColor = UIColor.black.cgColor
            tabBar.layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.14 : 0.05
            tabBar.layer.shadowRadius = 14
            tabBar.layer.shadowOffset = CGSize(width: 0, height: -2)
        }

        private func configure(
            _ itemAppearance: UITabBarItemAppearance,
            normalColor: UIColor,
            selectedColor: UIColor
        ) {
            itemAppearance.normal.iconColor = normalColor
            itemAppearance.normal.titleTextAttributes = [
                .foregroundColor: normalColor,
                .font: UIFont.systemFont(ofSize: 11.5, weight: .semibold)
            ]
            itemAppearance.selected.iconColor = selectedColor
            itemAppearance.selected.titleTextAttributes = [
                .foregroundColor: selectedColor,
                .font: UIFont.systemFont(ofSize: 11.5, weight: .bold)
            ]
        }

        private func enclosingTabBarController() -> UITabBarController? {
            var responder: UIResponder? = view
            while let current = responder {
                if let tabBarController = current as? UITabBarController {
                    return tabBarController
                }
                responder = current.next
            }
            return nil
        }
    }
}

enum RootTab: String, Hashable {
    case home
    case search
    case dynamic
    case live
    case mine

    init?(argumentValue: String) {
        guard let tab = RootTab(rawValue: argumentValue.lowercased()) else {
            return nil
        }
        self = tab
    }

    var appTab: AppTab {
        switch self {
        case .home:
            return .home
        case .search:
            return .search
        case .dynamic:
            return .dynamic
        case .live:
            return .live
        case .mine:
            return .mine
        }
    }

    var title: String {
        appTab.title
    }

    var systemImage: String {
        appTab.systemImage
    }
}
