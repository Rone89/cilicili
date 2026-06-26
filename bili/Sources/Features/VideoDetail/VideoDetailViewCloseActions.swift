import SwiftUI

@MainActor
struct VideoDetailViewCloseActions {
    let holder: VideoDetailViewModelHolder
    let fullscreenCoordinator: VideoDetailFullscreenCoordinator
    let dismiss: DismissAction
    let onRequestClose: (() -> Void)?

    func dismissVideoDetail(
        presentationState: Binding<VideoDetailViewPresentationState>
    ) {
        guard !presentationState.wrappedValue.isClosingDetail else { return }
        presentationState.wrappedValue.isClosingDetail = true
        fullscreenCoordinator.resetForDisappear()
        holder.viewModel?.stopPlaybackForNavigation()
        if let onRequestClose {
            onRequestClose()
        } else {
            dismiss()
        }
    }
}
