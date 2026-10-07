import SwiftUI
import UIKit

/// Local to one RootTabView; ordinary tab changes never issue this request.
struct RootTabScrollRequest: Equatable {
    private let id = UUID()
}

private struct RootTabScrollRequestKey: EnvironmentKey {
    static let defaultValue: RootTabScrollRequest? = nil
}

extension EnvironmentValues {
    var rootTabScrollRequest: RootTabScrollRequest? {
        get { self[RootTabScrollRequestKey.self] }
        set { self[RootTabScrollRequestKey.self] = newValue }
    }
}

extension View {
    /// Form does not respond to ScrollPosition on iOS 26.
    func formScrollsToTopOnRootTabReselection() -> some View {
        background(RootFormScrollToTopSource().frame(width: 0, height: 0))
    }

    /// For root containers without an existing programmatic scroll position.
    func scrollsToTopOnRootTabReselection() -> some View {
        modifier(RootTabScrollToTopModifier())
    }
}

private struct RootTabScrollToTopModifier: ViewModifier {
    @Environment(\.rootTabScrollRequest) private var request
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position = ScrollPosition()
    @State private var offset = Offset()

    private final class Offset {
        var current: CGFloat = 0
    }

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, value in offset.current = value }
            .onChange(of: request) { _, request in
                guard request != nil, offset.current > 0.5 else { return }
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.34)) {
                    position.scrollTo(edge: .top)
                }
            }
    }
}

private struct RootFormScrollToTopSource: UIViewRepresentable {
    @Environment(\.rootTabScrollRequest) private var request
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeUIView(context: Context) -> SourceView { SourceView(initialRequest: request) }

    func updateUIView(_ view: SourceView, context: Context) {
        view.scrollToTop(for: request, animated: !reduceMotion)
    }

    final class SourceView: UIView {
        private var lastRequest: RootTabScrollRequest?

        init(initialRequest: RootTabScrollRequest?) {
            lastRequest = initialRequest
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func scrollToTop(for request: RootTabScrollRequest?, animated: Bool) {
            guard lastRequest != request else { return }
            lastRequest = request
            guard request != nil, window != nil,
                  let scrollView = enclosingFormScrollView(),
                  scrollView.contentOffset.y + scrollView.adjustedContentInset.top > 0.5 else { return }
            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: -scrollView.adjustedContentInset.top),
                animated: animated
            )
        }

        private func enclosingFormScrollView() -> UIScrollView? {
            var ancestor = superview
            while let view = ancestor {
                if let scrollView = formScrollView(in: view) { return scrollView }
                ancestor = view.superview
            }
            return nil
        }

        private func formScrollView(in view: UIView) -> UIScrollView? {
            guard !view.isHidden else { return nil }
            if let collectionView = view as? UICollectionView { return collectionView }
            for child in view.subviews {
                if let scrollView = formScrollView(in: child) { return scrollView }
            }
            return nil
        }
    }
}
