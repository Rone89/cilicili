import SwiftUI

struct VideoDetailRelatedSection: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.videoDetailStandardHorizontalInset) private var standardHorizontalInset
    @ObservedObject var store: VideoDetailRelatedRenderStore
    let layoutWidth: CGFloat
    let runtimeSettings: VideoDetailRuntimeSettingsSnapshot
    let retryRelated: () async -> Void
    @State private var preloadedRelatedVideos = Set<String>()
    #if DEBUG
    @State private var observedRelatedVideos = Set<String>()
    #endif

    var body: some View {
        let layout = VideoDetailRelatedListLayout(
            layoutWidth: layoutWidth,
            horizontalPadding: standardHorizontalInset
        )

        VideoDetailRelatedSectionContent(
            relatedItems: store.relatedItems,
            layout: layout,
            state: store.state,
            didTimeOut: store.lastLoadTimedOut,
            retryRelated: retryRelated,
            listActions: relatedListActions
        )
        .frame(width: layoutWidth, alignment: .leading)
        .padding(.top, VideoDetailRelatedStyle.sectionTopPadding)
        .padding(.bottom, VideoDetailRelatedStyle.sectionBottomPadding)
    }

    private var relatedListActions: VideoDetailRelatedListActions {
        VideoDetailRelatedListActions(beginPreload: beginRelatedPreloadIfNeeded)
    }

    private var preloadActions: VideoDetailRelatedPreloadActions {
        VideoDetailRelatedSectionPreloadActionsBuilder(
            preloadedVideoIDs: $preloadedRelatedVideos,
            api: dependencies.api,
            runtimeSettings: runtimeSettings
        )
        .actions
    }

    private func beginRelatedPreloadIfNeeded(_ video: VideoItem) async {
        #if DEBUG
        if observedRelatedVideos.insert(video.bvid).inserted {
            PlayerMetricsLog.diagnostic(
                "event=relatedRowVisible metricsID=\(video.bvid) cid=\(video.cid ?? 0)"
            )
        }
        #endif
        await preloadActions.beginPreloadIfNeeded(video)
    }
}
