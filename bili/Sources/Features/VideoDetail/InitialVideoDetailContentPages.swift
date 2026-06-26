import SwiftUI

struct InitialVideoDetailDetailContentPage: View {
    let seedVideo: VideoItem
    let layoutWidth: CGFloat

    private var contentWidth: CGFloat {
        VideoDetailContentPageMetrics.contentWidth(for: layoutWidth)
    }

    private var shouldShowInitialPageMenuPlaceholder: Bool {
        (seedVideo.pages?.count ?? 1) > 1
    }

    var body: some View {
        InitialVideoDetailControls(
            titleText: seedVideo.title,
            contentWidth: contentWidth
        )
        .padding(.horizontal, VideoDetailContentPageMetrics.horizontalPadding)

        if shouldShowInitialPageMenuPlaceholder {
            InitialPageMenuPlaceholder(pageCount: seedVideo.pages?.count)
                .padding(.horizontal, VideoDetailContentPageMetrics.horizontalPadding)
        }

        InitialRelatedSection(layoutWidth: layoutWidth)
    }
}
