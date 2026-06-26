import SwiftUI

struct VideoDetailPlayerSurfacePresentationActions {
    let state: Binding<VideoDetailPlayerSurfacePresentationState>

    func updateQualityControlPresentation(_ isPresented: Bool) {
        state.wrappedValue.isShowingQualityControls = isPresented
    }
}
