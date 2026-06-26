import SwiftUI

struct VideoDetailPlaybackFullscreenBackdrop: View {
    let usesFullscreenLayout: Bool

    var body: some View {
        if usesFullscreenLayout {
            Color.black
                .ignoresSafeArea()
        }
    }
}
