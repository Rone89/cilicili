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

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.restorePlacement()
    }

    final class Controller: UIViewController {
        private weak var configuredItem: UINavigationItem?
        private var previousPlacement: UINavigationItem.SearchBarPlacement = .automatic
        private var previouslyAllowedToolbarIntegration = true
        private var placementObservation: NSKeyValueObservation?
        private var integrationObservation: NSKeyValueObservation?
        private var searchControllerObservation: NSKeyValueObservation?
        private var correctionScheduled = false

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
                        // Search presentation and SwiftUI updates can rewrite the same
                        // navigation item without laying out this zero-sized bridge.
                        placementObservation = item.observe(\.preferredSearchBarPlacement, options: [.new]) { [weak self] _, _ in
                            Task { @MainActor [weak self] in self?.scheduleCorrection() }
                        }
                        integrationObservation = item.observe(\.searchBarPlacementAllowsToolbarIntegration, options: [.new]) { [weak self] _, _ in
                            Task { @MainActor [weak self] in self?.scheduleCorrection() }
                        }
                        searchControllerObservation = item.observe(\.searchController, options: [.new]) { [weak self] _, _ in
                            Task { @MainActor [weak self] in self?.scheduleCorrection() }
                        }
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

        private func scheduleCorrection() {
            guard !correctionScheduled else { return }
            correctionScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.correctionScheduled = false
                guard self.configuredItem != nil else { return }
                self.applyPlacement()
            }
        }

        func restorePlacement() {
            placementObservation = nil
            integrationObservation = nil
            searchControllerObservation = nil
            guard let item = configuredItem else { return }
            configuredItem = nil
            item.preferredSearchBarPlacement = previousPlacement
            item.searchBarPlacementAllowsToolbarIntegration = previouslyAllowedToolbarIntegration
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
