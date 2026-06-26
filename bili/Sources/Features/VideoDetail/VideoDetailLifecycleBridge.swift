import SwiftUI
import UIKit

struct VideoDetailLifecycleBridge: UIViewControllerRepresentable {
    let onWillDisappear: () -> Void
    let onDidAppear: () -> Void
    let onTransitionCompleted: (Bool) -> Void

    func makeUIViewController(context _: Context) -> Controller {
        let controller = Controller()
        controller.onWillDisappear = onWillDisappear
        controller.onDidAppear = onDidAppear
        controller.onTransitionCompleted = onTransitionCompleted
        return controller
    }

    func updateUIViewController(_ uiViewController: Controller, context _: Context) {
        uiViewController.onWillDisappear = onWillDisappear
        uiViewController.onDidAppear = onDidAppear
        uiViewController.onTransitionCompleted = onTransitionCompleted
    }

    final class Controller: UIViewController {
        var onWillDisappear: (() -> Void)?
        var onDidAppear: (() -> Void)?
        var onTransitionCompleted: ((Bool) -> Void)?
        private var isObservingTransition = false

        override func loadView() {
            view = ClearPassthroughView()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            guard !isObservingTransition else { return }
            guard let coordinator = transitionCoordinator else { return }
            guard isClosingNavigationTransition(coordinator) else { return }
            onWillDisappear?()
            isObservingTransition = true
            coordinator.animate(alongsideTransition: nil) { [weak self] context in
                guard let self else { return }
                self.isObservingTransition = false
                self.onTransitionCompleted?(context.isCancelled)
            }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            isObservingTransition = false
            onDidAppear?()
        }
    }
}
