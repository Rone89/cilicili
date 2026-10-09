import SwiftUI
import UIKit

struct VideoDetailInitialPlaybackPage: View {
    let seedVideo: VideoItem
    @Binding var selectedContentTab: VideoDetailContentTab
    let runtimeSettings: VideoDetailRuntimeSettingsSnapshot

    var body: some View {
        GeometryReader { proxy in
            let layout = VideoDetailInitialPlaybackLayout(
                proxy: proxy,
                videoAspectRatio: VideoDetailInitialVideoGeometry.metadataAspectRatio(for: seedVideo)
                    ?? VideoDetailInitialVideoGeometry.defaultAspectRatio
            )

            VideoDetailInitialPlaybackStage(
                seedVideo: seedVideo,
                layout: layout,
                containerHeight: proxy.size.height,
                selectedContentTab: $selectedContentTab,
                runtimeSettings: runtimeSettings
            )
        }
    }
}
