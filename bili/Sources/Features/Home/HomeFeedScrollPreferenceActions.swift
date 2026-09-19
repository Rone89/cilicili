import SwiftUI

extension HomeFeedScrollPreferenceModifier {
    func updateFeedContainerWidth(_ width: CGFloat) {
        let updatedState = scrollActions.updateFeedContainerWidth(width, state: viewportState)
        guard updatedState != viewportState else { return }
        viewportState = updatedState
    }

    func updateViewportHeight(_ height: CGFloat) {
        let updatedState = scrollActions.updateViewportHeight(
            height,
            state: viewportState
        )
        guard updatedState != viewportState else { return }
        viewportState = updatedState
    }
}
