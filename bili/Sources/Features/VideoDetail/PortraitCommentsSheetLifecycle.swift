import SwiftUI

private struct PortraitCommentsSheetLifecycleModifier: ViewModifier {
    let lifecycleActions: PortraitCommentsSheetLifecycleActions

    func body(content: Content) -> some View {
        content
            .refreshable {
                await lifecycleActions.retryComments()
            }
            .task {
                lifecycleActions.beginInitialCommentsLoad()
            }
    }
}

extension View {
    func portraitCommentsSheetLifecycle(
        actions: PortraitCommentsSheetActions
    ) -> some View {
        modifier(
            PortraitCommentsSheetLifecycleModifier(
                lifecycleActions: PortraitCommentsSheetLifecycleActions(actions: actions)
            )
        )
    }
}
