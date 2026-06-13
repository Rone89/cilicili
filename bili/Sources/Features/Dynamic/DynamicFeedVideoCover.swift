import SwiftUI

struct DynamicFeedVideoCover: View {
    let video: VideoItem
    let display: VideoCardDisplayModel

    var body: some View {
        FixedAspectPreview(aspectRatio: 16 / 9) {
            ZStack {
                Color.clear

                AdaptiveVideoCoverImage(display: display, style: .maxSide)

                VideoCoverBottomScrim()

                DynamicVideoPlayBadge(size: 34, iconSize: 14)
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

                if video.duration != nil {
                    VideoCoverDurationBadge(BiliFormatters.duration(video.duration))
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .mediaShadow(.control)
    }
}
