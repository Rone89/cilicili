import SwiftUI

struct VideoDetailActionStripOwnerAvatar: View {
    let owner: VideoOwner?
    let side: CGFloat

    init(owner: VideoOwner?, side: CGFloat = VideoDetailActionStrip.Metrics.avatarImageSide) {
        self.owner = owner
        self.side = side
    }

    var body: some View {
        PlaybackDetailOwnerAvatar(
            owner: owner,
            side: side,
            pixelSize: VideoDetailActionStrip.Metrics.avatarPixelSize,
            showsShadow: false,
            showsBorder: false
        )
    }
}
