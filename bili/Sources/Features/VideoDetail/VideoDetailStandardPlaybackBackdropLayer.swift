import SwiftUI

struct VideoDetailStandardPlaybackBackdropLayer: View {
    let usesBlackBackdrop: Bool

    var body: some View {
        if usesBlackBackdrop {
            Color.black
                .ignoresSafeArea()
                .transition(.opacity)
        }
    }
}
