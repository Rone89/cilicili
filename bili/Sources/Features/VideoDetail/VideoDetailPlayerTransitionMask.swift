import SwiftUI

struct VideoDetailPlayerTransitionMask: View {
    let snapshot: PlaybackTransitionSnapshot?
    let fallbackCoverURL: URL?
    let playerWidth: CGFloat?
    let playerHeight: CGFloat

    var body: some View {
        ZStack {
            if let image = snapshot?.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                CachedRemoteImage(
                    url: fallbackCoverURL,
                    targetPixelSize: 720,
                    animatesAppearance: false
                ) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    Color.clear
                }
            }
        }
        .background(snapshot == nil ? Color.clear : Color.black)
        .frame(width: playerWidth)
        .frame(height: playerHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
