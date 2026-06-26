import SwiftUI

struct BiliPlayerSurfaceChrome: View {
    let playbackSurface: AnyView
    let state: BiliPlayerSurfaceChromeState
    let playbackControls: AnyView

    var body: some View {
        ZStack(alignment: .bottom) {
            playbackSurface
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .background(.black)
                .zIndex(0)

            BiliPlayerSurfaceOverlayLayer(
                state: state
            )

            BiliPlayerControlsOverlayLayer(
                state: state,
                playbackControls: playbackControls,
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(.black)
    }
}
