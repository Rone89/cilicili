import SwiftUI

struct MinePlaybackSettingsView: View {
    @ObservedObject var libraryStore: LibraryStore
    @State var isProbingPlaybackCDN = false
    @State var playbackCDNProbeResults: [PlaybackCDNProbeResult] = []
    @State var playbackCDNProbeMessage: String?
    @State var playbackCDNProbeTask: Task<Void, Never>?
    @State var isShowingPlaybackCDNProbeDetails = false
    @State var playbackURLPreferenceSnapshots: [PlaybackURLPreferenceSnapshot] = []
    @State var isShowingPlaybackURLPreferenceDetails = false

    var body: some View {
        Form {
            MinePlaybackPreferenceSection(
                libraryStore: libraryStore,
                playbackPreferenceSummary: AnyView(playbackPreferenceSummary),
                playbackCDNProbeRefreshIntervalTitle: playbackCDNProbeRefreshIntervalTitle,
                isProbingPlaybackCDN: isProbingPlaybackCDN,
                playbackCDNProbeMessage: playbackCDNProbeMessage,
                probePlaybackCDN: probePlaybackCDN
            ) {
                playbackCDNProbeSummary
                playbackURLPreferenceSummary
            }

            MinePlaybackToolsSection(libraryStore: libraryStore)
        }
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
        .task {
            refreshPlaybackURLPreferenceSnapshots()
            refreshPlaybackCDNProbeIfNeeded()
        }
        .onDisappear {
            playbackCDNProbeTask?.cancel()
            playbackCDNProbeTask = nil
            isProbingPlaybackCDN = false
        }
    }

}
