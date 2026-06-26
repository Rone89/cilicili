import SwiftUI

private struct VideoDetailPlayerQualityControlLifecycleModifier: ViewModifier {
    let isShowingQualityDialog: Bool
    let actions: VideoDetailPlayerQualityControlLifecycleActions

    func body(content: Content) -> some View {
        content
            .onChange(of: isShowingQualityDialog) { _, isPresented in
                actions.handlePresentationChanged(isPresented)
            }
            .onDisappear(perform: actions.handleDisappear)
    }
}

extension View {
    func videoDetailPlayerQualityControlLifecycle(
        isShowingQualityDialog: Bool,
        onPresentationChange: @escaping (Bool) -> Void
    ) -> some View {
        modifier(
            VideoDetailPlayerQualityControlLifecycleModifier(
                isShowingQualityDialog: isShowingQualityDialog,
                actions: VideoDetailPlayerQualityControlLifecycleActions(
                    onPresentationChange: onPresentationChange
                )
            )
        )
    }
}
