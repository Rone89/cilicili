import SwiftUI

private struct CommentSheetPresentation: ViewModifier {
    @State private var selectedDetent: PresentationDetent = .medium

    func body(content: Content) -> some View {
        content
            .presentationDetents([.medium, .large], selection: $selectedDetent)
            .presentationContentInteraction(.resizes)
            .presentationDragIndicator(.visible)
    }
}

extension View {
    func commentSheetPresentation() -> some View {
        modifier(CommentSheetPresentation())
    }
}
