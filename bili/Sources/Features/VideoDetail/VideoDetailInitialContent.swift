import SwiftUI

struct VideoDetailInitialContent: View {
    let seedVideo: VideoItem
    @Binding var selectedContentTab: VideoDetailContentTab
    let runtimeSettings: VideoDetailRuntimeSettingsSnapshot

    var body: some View {
        VideoDetailInitialPlaybackPage(
            seedVideo: seedVideo,
            selectedContentTab: $selectedContentTab,
            runtimeSettings: runtimeSettings
        )
    }
}
