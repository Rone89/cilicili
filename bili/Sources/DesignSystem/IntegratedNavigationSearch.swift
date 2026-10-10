import SwiftUI
import UIKit

/// Keeps SwiftUI's search controller in the top navigation row on iPhone.
struct IntegratedNavigationSearch: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.applyPlacement()
        // SwiftUI may install its search controller after this representable updates.
        DispatchQueue.main.async { [weak controller] in controller?.applyPlacement() }
    }

    final class Controller: UIViewController {
        private weak var configuredItem: UINavigationItem?
        private var previousPlacement: UINavigationItem.SearchBarPlacement = .automatic
        private var previouslyAllowedToolbarIntegration = true

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyPlacement()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            applyPlacement()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            restorePlacement()
        }

        func applyPlacement() {
            guard isViewLoaded, view.window != nil else { return }
            var owner: UIViewController? = parent
            while let current = owner {
                if let navigation = current.parent as? UINavigationController {
                    guard navigation.topViewController === current,
                          current.navigationItem.searchController != nil else { return }
                    let item = current.navigationItem
                    if configuredItem !== item {
                        restorePlacement()
                        configuredItem = item
                        previousPlacement = item.preferredSearchBarPlacement
                        previouslyAllowedToolbarIntegration = item.searchBarPlacementAllowsToolbarIntegration
                    }
                    if item.preferredSearchBarPlacement != .integrated {
                        item.preferredSearchBarPlacement = .integrated
                    }
                    if item.searchBarPlacementAllowsToolbarIntegration {
                        item.searchBarPlacementAllowsToolbarIntegration = false
                    }
                    return
                }
                owner = current.parent
            }
        }

        private func restorePlacement() {
            guard let item = configuredItem else { return }
            item.preferredSearchBarPlacement = previousPlacement
            item.searchBarPlacementAllowsToolbarIntegration = previouslyAllowedToolbarIntegration
            configuredItem = nil
        }
    }
}

extension View {
    func integratedNavigationSearch() -> some View {
        background {
            IntegratedNavigationSearch()
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}
