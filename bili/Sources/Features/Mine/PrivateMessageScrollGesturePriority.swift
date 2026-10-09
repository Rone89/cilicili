import SwiftUI
import UIKit

/// Scopes back-gesture priority and refresh presentation to the message scroll view.
struct PrivateMessageScrollGesturePriority: UIViewRepresentable {
#if DEBUG
    /// Read by the offline navigation fixture to verify it reached a real refresh control.
    static var refreshPresentationSuspensions = 0
    static var refreshActionSubmissions = 0
#endif
    func makeUIView(context: Context) -> ProbeView { ProbeView() }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.prioritizeNavigationGestures()
    }

    static func dismantleUIView(_ uiView: ProbeView, coordinator: ()) {
        uiView.stopObservingNavigationGestures()
    }

    /// A refresh control can become visible during an interactive pop without submitting a refresh.
    /// Hide only its presentation until the navigation transition completes; never end a real refresh.
    final class RefreshPresentationLease {
        private weak var control: UIRefreshControl?
        private var previousAlpha: CGFloat = 1

        func suspend(_ refreshControl: UIRefreshControl?) {
            guard let refreshControl else { return }
            if control !== refreshControl {
                restore()
                control = refreshControl
                previousAlpha = refreshControl.alpha
            }
            refreshControl.alpha = 0
        }

        func restore() {
            control?.alpha = previousAlpha
            control = nil
        }
    }

    final class ProbeView: UIView {
        private weak var configuredScrollView: UIScrollView?
        private weak var navigation: UINavigationController?
        private var observedGestures = [UIGestureRecognizer]()
        private let refreshPresentation = RefreshPresentationLease()
        private var isNavigatingBack = false
        private var awaitsTransitionCompletion = false

        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { stopObservingNavigationGestures() }
            else { prioritizeNavigationGestures() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            prioritizeNavigationGestures()
        }

        func prioritizeNavigationGestures() {
            var ancestor = superview
            while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
            guard let scrollView = ancestor as? UIScrollView else { return }

            var responder: UIResponder? = self
            while let current = responder {
                if let controller = current as? UIViewController,
                   let navigation = controller.navigationController {
                    if configuredScrollView !== scrollView || self.navigation !== navigation {
                        stopObservingNavigationGestures()
                        configuredScrollView = scrollView
                        self.navigation = navigation
                    }
                    for gesture in [navigation.interactivePopGestureRecognizer,
                                    navigation.interactiveContentPopGestureRecognizer].compactMap({ $0 }) {
                        guard !observedGestures.contains(where: { $0 === gesture }) else { continue }
                        // An edge pop can succeed even when the full-width pop fails.
                        scrollView.panGestureRecognizer.require(toFail: gesture)
                        gesture.addTarget(self, action: #selector(backGestureChanged(_:)))
                        observedGestures.append(gesture)
                    }
                    if isNavigatingBack {
                        refreshPresentation.suspend(scrollView.refreshControl)
                    }
                    return
                }
                responder = current.next
            }
        }

        @objc private func backGestureChanged(_ gesture: UIGestureRecognizer) {
            switch gesture.state {
            case .began, .changed:
#if DEBUG
                if !isNavigatingBack, configuredScrollView?.refreshControl != nil,
                   ProcessInfo.processInfo.arguments.contains("--private-message-navigation-chain") {
                    Self.recordRefreshSuspension()
                }
#endif
                isNavigatingBack = true
                refreshPresentation.suspend(configuredScrollView?.refreshControl)
                restoreAfterTransition()
            case .ended, .cancelled, .failed:
                guard isNavigatingBack else { return }
                guard !observedGestures.contains(where: { $0.state == .began || $0.state == .changed }) else { return }
                if !restoreAfterTransition() && !awaitsTransitionCompletion {
                    finishNavigationTransition()
                }
            default: break
            }
        }

#if DEBUG
        private static func recordRefreshSuspension() {
            PrivateMessageScrollGesturePriority.refreshPresentationSuspensions += 1
        }
#endif

        @discardableResult
        private func restoreAfterTransition() -> Bool {
            if awaitsTransitionCompletion { return true }
            guard let transition = navigation?.transitionCoordinator else { return false }
            awaitsTransitionCompletion = transition.animate(alongsideTransition: nil) { [weak self] _ in
                // Covers both a completed pop and an interactive pop that was cancelled.
                self?.finishNavigationTransition()
            }
            return awaitsTransitionCompletion
        }

        private func finishNavigationTransition() {
            refreshPresentation.restore()
            isNavigatingBack = false
            awaitsTransitionCompletion = false
        }

        func stopObservingNavigationGestures() {
            for gesture in observedGestures {
                gesture.removeTarget(self, action: #selector(backGestureChanged(_:)))
            }
            observedGestures.removeAll()
            configuredScrollView = nil
            navigation = nil
            finishNavigationTransition()
        }
    }
}
