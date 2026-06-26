import SwiftUI

@MainActor
struct VideoDetailViewActions {
    let configuration: VideoDetailViewConfigurationActions
    let close: VideoDetailViewCloseActions

    func configureViewModel() {
        configuration.configureViewModel()
    }

    func dismissVideoDetail(
        presentationState: Binding<VideoDetailViewPresentationState>
    ) {
        close.dismissVideoDetail(presentationState: presentationState)
    }
}
