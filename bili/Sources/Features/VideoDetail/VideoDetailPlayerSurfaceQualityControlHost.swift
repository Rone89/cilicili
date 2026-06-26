import SwiftUI

struct VideoDetailPlayerSurfaceQualityControlHost: View {
    @ObservedObject var store: VideoDetailQualityControlRenderStore
    let selectPlayVariant: (PlayVariant) -> Void
    let onPresentationChange: (Bool) -> Void

    var body: some View {
        VideoDetailPlayerQualityControl(
            store: store,
            selectPlayVariant: selectPlayVariant,
            onPresentationChange: onPresentationChange
        )
    }
}
