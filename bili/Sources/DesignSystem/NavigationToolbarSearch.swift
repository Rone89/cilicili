import SwiftUI

/// An actual navigation-bar item; no UISearchController can move it into a drawer.
private struct NavigationToolbarSearch: ViewModifier {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let prompt: String
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
                            .accessibilityIdentifier("navigation.search.cancel")
                        }
                    }
                    // Reserve room for the native back button and trailing actions.
                    .frame(width: max(120, (pageWidth > 0 ? pageWidth : 360) - 144))
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .onDisappear { isFocused.wrappedValue = false }
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
        .frame(minHeight: 44)
        .background {
            if isFocused.wrappedValue {
                Capsule().fill(.clear).biliGlassEffect(in: Capsule())
            } else {
                Capsule().fill(Color(.secondarySystemBackground))
            }
        }
    }
}

extension View {
    func navigationToolbarSearch(
        text: Binding<String>,
        isFocused: FocusState<Bool>.Binding,
        prompt: String,
        onSubmit: @escaping () -> Void = {}
    ) -> some View {
        modifier(NavigationToolbarSearch(text: text, isFocused: isFocused, prompt: prompt, onSubmit: onSubmit))
    }
}
