import SwiftUI

struct CommentSheetToolbarConfiguration {
    let onDismiss: () -> Void
    let onRefresh: () -> Void
}

private struct CommentSheetToolbarConfigurationKey: EnvironmentKey {
    static let defaultValue = CommentSheetToolbarConfiguration(onDismiss: {}, onRefresh: {})
}

// Preserve the app's resolved content appearance across presentation boundaries.
// Unlike colorScheme, this value is not replaced by a UIKit sheet/host trait.
private struct AppContentColorSchemeKey: EnvironmentKey {
    static let defaultValue: ColorScheme? = nil
}

extension EnvironmentValues {
    var appContentColorScheme: ColorScheme? {
        get { self[AppContentColorSchemeKey.self] }
        set { self[AppContentColorSchemeKey.self] = newValue }
    }

    var commentSheetToolbarConfiguration: CommentSheetToolbarConfiguration {
        get { self[CommentSheetToolbarConfigurationKey.self] }
        set { self[CommentSheetToolbarConfigurationKey.self] = newValue }
    }
}

private struct CommentSheetPresentation: ViewModifier {
    @Environment(\.colorScheme) private var inheritedColorScheme
    @Environment(\.appContentColorScheme) private var appContentColorScheme
    @State private var selectedDetent: PresentationDetent = .medium
    let onDismiss: () -> Void
    let onRefresh: () -> Void

    func body(content: Content) -> some View {
        let contentColorScheme = appContentColorScheme ?? inheritedColorScheme
        content
            .environment(\.colorScheme, contentColorScheme)
            // The video host can request dark status-bar contrast while its
            // content stays light. Keep this presentation's UIKit background
            // and its SwiftUI comment text on the same appearance.
            .preferredColorScheme(contentColorScheme)
            .presentationDetents([.medium, .large], selection: $selectedDetent)
            .presentationContentInteraction(.resizes)
            .presentationDragIndicator(.visible)
            .environment(
                \.commentSheetToolbarConfiguration,
                CommentSheetToolbarConfiguration(onDismiss: onDismiss, onRefresh: onRefresh)
            )
    }
}

extension View {
    func commentSheetPresentation(
        onDismiss: @escaping () -> Void = {},
        onRefresh: @escaping () -> Void = {}
    ) -> some View {
        modifier(CommentSheetPresentation(onDismiss: onDismiss, onRefresh: onRefresh))
    }
}
