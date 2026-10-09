import SwiftUI
import UIKit

/// Keeps the message scroll/refresh pan from running alongside either system back gesture.
/// Placed inside the scroll content so it configures only the message scroll view.
struct PrivateMessageScrollGesturePriority: UIViewRepresentable {
    func makeUIView(context: Context) -> ProbeView { ProbeView() }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.prioritizeNavigationGestures()
    }

    final class ProbeView: UIView {
        private weak var configuredScrollView: UIScrollView?
        private var configuredGestureIDs = Set<ObjectIdentifier>()

        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            prioritizeNavigationGestures()
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
                    if configuredScrollView !== scrollView {
                        configuredScrollView = scrollView
                        configuredGestureIDs.removeAll()
                    }
                    for gesture in [navigation.interactivePopGestureRecognizer,
                                    navigation.interactiveContentPopGestureRecognizer].compactMap({ $0 }) {
                        guard configuredGestureIDs.insert(ObjectIdentifier(gesture)).inserted else { continue }
                        // Waiting for full-width pop alone doesn't cover an edge pop when full-width pop fails.
                        scrollView.panGestureRecognizer.require(toFail: gesture)
                    }
                    return
                }
                responder = current.next
            }
        }
    }
}
