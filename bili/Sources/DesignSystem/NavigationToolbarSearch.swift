import SwiftUI
import UIKit

/// An actual navigation-bar item; no UISearchController can move it into a drawer.
private struct NavigationToolbarSearch: ViewModifier {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let prompt: String
    let hasBackButton: Bool
    let trailingButtonCount: Int
    let onSubmit: () -> Void
    @State private var pageWidth: CGFloat = 0
    @State private var isEditing = false

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _, width in
                pageWidth = width
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        inputField
                        if isEditing {
                            Button("取消") {
                                text = ""
                                isEditing = false
                                isFocused = false
                            }
                            .foregroundStyle(.primary)
                            .fixedSize()
                            .accessibilityIdentifier("navigation.search.cancel")
                        }
                    }
                    // Keep the input in this row; reserve space only for existing actions.
                    .frame(width: availableWidth)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .onDisappear { isEditing = false; isFocused = false }
    }

    private var availableWidth: CGFloat {
        let buttonCount = (hasBackButton ? 1 : 0) + max(0, trailingButtonCount)
        let horizontalMargins: CGFloat = 20 * 2
        let buttonWidthAndSpacing: CGFloat = 56
        return max(120, (pageWidth > 0 ? pageWidth : 360)
                   - horizontalMargins - CGFloat(buttonCount) * buttonWidthAndSpacing)
    }

    private var inputField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text, onEditingChanged: { editing in
                // Toolbar hosting can lag FocusState updates. Mirror the
                // field's actual editing session back to the shared binding.
                isEditing = editing
                isFocused = editing
            })
                .textFieldStyle(.plain)
                .focused($isFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit(onSubmit)
                .accessibilityIdentifier("navigation.search.field")
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索文字")
                .accessibilityIdentifier("navigation.search.clear")
            }
        }
        .font(.body)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 44)
        .biliRegularGlassEffect(interactive: true, in: Capsule())
        .background(SearchOutsideTapDismissalSource { isEditing = false; isFocused = false })
    }
}

/// Observe taps without consuming result/navigation actions. The exclusion
/// rect covers the whole input capsule, including its clear button and padding.
private struct SearchOutsideTapDismissalSource: UIViewRepresentable {
    let onDismiss: () -> Void

    func makeUIView(context: Context) -> SourceView {
        let view = SourceView(frame: .zero)
        view.onDismiss = onDismiss
        return view
    }

    func updateUIView(_ view: SourceView, context: Context) {
        view.onDismiss = onDismiss
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: SourceView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    static func dismantleUIView(_ view: SourceView, coordinator: ()) {
        view.removeRecognizer()
    }

    final class SourceView: UIView, UIGestureRecognizerDelegate {
        var onDismiss: (() -> Void)?
        private lazy var tap: UITapGestureRecognizer = {
            let tap = UITapGestureRecognizer(target: self, action: #selector(dismissEditing))
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            tap.delegate = self
            return tap
        }()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard tap.view !== window else { return }
            removeRecognizer()
            _ = window?.keyboardLayoutGuide
            window?.addGestureRecognizer(tap)
        }

        func removeRecognizer() { tap.view?.removeGestureRecognizer(tap) }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let window, !bounds.isEmpty else { return false }
            var ancestor: UIView? = self
            while let view = ancestor {
                guard !view.isHidden, view.alpha > 0 else { return false }
                ancestor = view.superview
            }
            let inputFrame = convert(bounds, to: window)
            guard let responder = firstResponder(in: window), responder is UITextField,
                  inputFrame.intersects(responder.convert(responder.bounds, to: window)) else { return false }
            let point = touch.location(in: window)
            return !inputFrame.contains(point) && !window.keyboardLayoutGuide.layoutFrame.contains(point)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        @objc private func dismissEditing() {
            // Let the touched control finish first (notably Cancel or a result
            // row). Do not dismiss a new responder opened by that action.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window,
                      let responder = self.firstResponder(in: window), responder is UITextField,
                      self.convert(self.bounds, to: window).intersects(
                        responder.convert(responder.bounds, to: window)
                      ) else { return }
                window.endEditing(true)
                self.onDismiss?()
            }
        }

        private func firstResponder(in view: UIView) -> UIView? {
            if view.isFirstResponder { return view }
            for child in view.subviews {
                if let responder = firstResponder(in: child) { return responder }
            }
            return nil
        }
    }
}

extension View {
    func navigationToolbarSearch(
        text: Binding<String>,
        isFocused: FocusState<Bool>.Binding,
        prompt: String,
        hasBackButton: Bool = false,
        trailingButtonCount: Int = 0,
        onSubmit: @escaping () -> Void = {}
    ) -> some View {
        modifier(NavigationToolbarSearch(
            text: text, isFocused: isFocused, prompt: prompt,
            hasBackButton: hasBackButton, trailingButtonCount: trailingButtonCount,
            onSubmit: onSubmit
        ))
    }
}
