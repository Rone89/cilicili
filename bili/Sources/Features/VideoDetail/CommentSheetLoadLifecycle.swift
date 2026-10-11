import SwiftUI

private struct CommentSheetLoadLifecycleModifier: ViewModifier {
    let load: @MainActor () async -> Void
    let revision: Int

    func body(content: Content) -> some View {
        content
            .task(id: revision) {
                await load()
            }
    }
}

extension View {
    func commentSheetLoadLifecycle(
        revision: Int = 0,
        load: @escaping @MainActor () async -> Void
    ) -> some View {
        modifier(CommentSheetLoadLifecycleModifier(load: load, revision: revision))
    }
}
