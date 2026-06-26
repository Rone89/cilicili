import SwiftUI
import UIKit

struct VideoDetailSystemBackGestureBridge: UIViewControllerRepresentable {
    let onNavigationGestureBegan: (() -> Void)?

    func makeUIViewController(context _: Context) -> Controller {
        Controller(onNavigationGestureBegan: onNavigationGestureBegan)
    }

    func updateUIViewController(_ uiViewController: Controller, context _: Context) {
        uiViewController.onNavigationGestureBegan = onNavigationGestureBegan
        if onNavigationGestureBegan == nil {
            uiViewController.detachFromSystemBackGestures()
        } else {
            uiViewController.restoreSystemBackGestures()
        }
    }

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        var configuredContentPopID: ObjectIdentifier?
        var configuredScrollPanIDs = Set<ObjectIdentifier>()
        weak var attachedNavigationController: UINavigationController?
        var onNavigationGestureBegan: (() -> Void)?

        init(onNavigationGestureBegan: (() -> Void)?) {
            self.onNavigationGestureBegan = onNavigationGestureBegan
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
            if parent == nil {
                detachFromSystemBackGestures()
                onNavigationGestureBegan = nil
            } else {
                restoreSoon()
            }
        }

        deinit {
            detachFromSystemBackGestures()
            onNavigationGestureBegan = nil
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            restoreSystemBackGestures()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            restoreSystemBackGestures()
        }

        private func restoreSoon() {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.parent != nil else { return }
                self.restoreSystemBackGestures()
            }
        }
    }
}
