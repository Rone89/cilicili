import SwiftUI

/// An actual navigation-bar item; no UISearchController can move it into a drawer.
private struct NavigationToolbarSearch: ViewModifier {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let prompt: String
    let hasBackButton: Bool
    let trailingButtonCount: Int
    let onSubmit: () -> Void
    @State private var pageWidth: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _, width in
                pageWidth = width
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        inputField
                        if isFocused.wrappedValue {
                            Button("取消") {
                                text = ""
                                isFocused.wrappedValue = false
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
            .onDisappear { isFocused.wrappedValue = false }
    }

    private var availableWidth: CGFloat {
        let buttonCount = (hasBackButton ? 1 : 0) + max(0, trailingButtonCount)
        let horizontalMargins: CGFloat = 32
        let buttonWidthAndSpacing: CGFloat = 56
        return max(120, (pageWidth > 0 ? pageWidth : 360)
                   - horizontalMargins - CGFloat(buttonCount) * buttonWidthAndSpacing)
    }

    private var inputField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focused(isFocused)
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
