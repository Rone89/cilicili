import SwiftUI

struct VideoDetailStandardPlaybackPageContextBuilder {
    let config: VideoDetailStandardPlaybackPageConfig
    let selectedPlayVariant: PlayVariant?
    let selectedCID: Int?
    let pages: [VideoPage]
    let qualityMenuItems: [VideoDetailPlaybackQualityMenuItem]
    let selectedContentTab: VideoDetailContentTab
    let scrollState: VideoDetailStandardPlaybackScrollState

    var context: VideoDetailStandardPlaybackPageContext {
        VideoDetailStandardPlaybackPageContext(
            renderContext: renderContext,
            layout: layout
        )
    }

    private var renderContext: VideoDetailStandardPlaybackRenderContext {
        VideoDetailStandardPlaybackRenderContext(
            selectedPlayVariant: selectedPlayVariant,
            selectedCID: selectedCID,
            pages: pages,
            qualityMenuItems: qualityMenuItems
        )
    }

    private var layout: VideoDetailStandardPlaybackPageLayout {
        VideoDetailStandardPlaybackPageLayout(
            hidesPortraitContent: config.isFullscreen,
            usesBlackBackdrop: config.isFullscreen || config.isLandscape,
            headerLayout: headerLayout,
            selectedScrollOffset: scrollState.offset(for: selectedContentTab)
        )
    }

    private var headerLayout: VideoDetailPinnedDynamicPlayerHeaderLayout {
        VideoDetailPinnedDynamicPlayerHeaderLayout(
            screenSize: config.screenSize,
            standardHeight: config.standardHeight,
            isPortraitVideo: renderContext.isPortraitVideo,
            isEnabled: !config.isFullscreen
        )
    }
}
