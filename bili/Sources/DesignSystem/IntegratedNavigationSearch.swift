import SwiftUI
import UIKit

/// Keeps SwiftUI's search controller in the top navigation row on iPhone.
struct IntegratedNavigationSearch: UIViewControllerRepresentable {
    let isPresented: Bool

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.updateSearchPresentation(isPresented)
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.restorePlacement()
    }

    final class Controller: UIViewController {
        private weak var configuredItem: UINavigationItem?
        private var previousPlacement: UINavigationItem.SearchBarPlacement = .automatic
        private var previouslyAllowedToolbarIntegration = true
        private var previouslyHidSearchBarWhenScrolling = true
        private weak var configuredSearchController: UISearchController?
        private var isSearchPresented: Bool?
        private var needsPlacementUpdate = true
        private var searchControllerObservation: NSKeyValueObservation?
        private var correctionScheduled = false

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            needsPlacementUpdate = true
            applyPlacement()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            applyPlacement()
        }

        func updateSearchPresentation(_ isPresented: Bool) {
            if isSearchPresented != isPresented {
                isSearchPresented = isPresented
                scheduleCorrection()
            }
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
                        previouslyHidSearchBarWhenScrolling = item.hidesSearchBarWhenScrolling
                        // Observe controller replacement only. Observing placement and
                        // correcting it on every layout competes with UIKit's scroll chrome.
                        searchControllerObservation = item.observe(\.searchController, options: [.new]) { [weak self] observedItem, _ in
                            Task { @MainActor [weak self, weak observedItem] in
                                guard let self, let item = observedItem,
                                      self.configuredItem === item,
                                      self.configuredSearchController !== item.searchController else { return }
                                self.scheduleCorrection()
                            }
                        }
                    }
                    guard needsPlacementUpdate || configuredSearchController !== item.searchController else { return }
                    needsPlacementUpdate = false
                    configuredSearchController = item.searchController
                    if item.preferredSearchBarPlacement != .integrated {
                        item.preferredSearchBarPlacement = .integrated
                    }
                    if item.searchBarPlacementAllowsToolbarIntegration {
                        item.searchBarPlacementAllowsToolbarIntegration = false
                    }
                    if item.hidesSearchBarWhenScrolling {
                        item.hidesSearchBarWhenScrolling = false
                    }
                    return
                }
                owner = current.parent
            }
        }

        private func scheduleCorrection() {
            needsPlacementUpdate = true
            guard !correctionScheduled else { return }
            correctionScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.correctionScheduled = false
                guard self.configuredItem != nil else { return }
                self.needsPlacementUpdate = true
                self.applyPlacement()
            }
        }

        func restorePlacement() {
            searchControllerObservation = nil
            configuredSearchController = nil
            needsPlacementUpdate = true
            guard let item = configuredItem else { return }
            configuredItem = nil
            item.preferredSearchBarPlacement = previousPlacement
            item.searchBarPlacementAllowsToolbarIntegration = previouslyAllowedToolbarIntegration
            item.hidesSearchBarWhenScrolling = previouslyHidSearchBarWhenScrolling
        }
    }
}

extension View {
    func integratedNavigationSearch(isPresented: Bool) -> some View {
        background {
            IntegratedNavigationSearch(isPresented: isPresented)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}
