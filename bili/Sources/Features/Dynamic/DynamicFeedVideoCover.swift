import SwiftUI

struct DynamicFeedVideoCover: View {
    let video: VideoItem
    let display: VideoCardDisplayModel
    @State private var loadedCoverIdentity: String?

    var body: some View {
        FixedAspectPreview(aspectRatio: 16 / 9) {
            ZStack {
                Color.clear

                AdaptiveVideoCoverImage(
                    display: display,
                    style: .maxSide,
                    onPhaseChange: { phase in
                        updateLoadedCoverIdentity(for: phase)
                    }
                )

                if isCurrentCoverLoaded {
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
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .mediaShadow(.control)
    }

    private var isCurrentCoverLoaded: Bool {
        loadedCoverIdentity == display.coverLoadIdentity
    }

    private func updateLoadedCoverIdentity(for phase: RemoteImageLoadingPhase) {
        switch phase {
        case .loaded:
            loadedCoverIdentity = display.coverLoadIdentity
        case .idle, .loading, .failed:
            if loadedCoverIdentity != display.coverLoadIdentity {
                loadedCoverIdentity = nil
            }
        }
    }
}
