import SwiftUI

struct InitialVideoDetailDetailContentPage: View {
    @Environment(\.videoDetailStandardHorizontalInset) private var standardHorizontalInset
    let seedVideo: VideoItem
    let layoutWidth: CGFloat
    let mountsSecondaryContent: Bool

    private var contentWidth: CGFloat {
        PlaybackDetailContentMetrics.contentWidth(
            for: layoutWidth,
            horizontalInset: horizontalInset
        )
    }

    private var horizontalInset: CGFloat {
        PlaybackDetailContentMetrics.horizontalPadding(for: standardHorizontalInset)
    }

    private var shouldShowInitialPageMenuPlaceholder: Bool {
        !seedVideo.isPGCEpisode && (seedVideo.pages?.count ?? 1) > 1
    }

    var body: some View {
        InitialVideoDetailControls(
            titleText: seedVideo.title,
            contentWidth: contentWidth
        )
        .padding(.horizontal, horizontalInset)

        if shouldShowInitialPageMenuPlaceholder {
            InitialPageMenuPlaceholder(pageCount: seedVideo.pages?.count)
                .padding(.horizontal, horizontalInset)
        }

        if mountsSecondaryContent && !seedVideo.isPGCEpisode {
            InitialRelatedSection(layoutWidth: layoutWidth)
        }
    }
}
