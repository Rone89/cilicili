import SwiftUI

struct MinePlaybackSettingsView: View {
    enum Mode: Equatable {
        case user
        case developer
    }

    @ObservedObject var libraryStore: LibraryStore
    let mode: Mode
    @AppStorage("cc.bili.playback.showsAdvancedSettings.v1") var showsAdvancedPlaybackSettings = false
    @State var isProbingPlaybackCDN = false
    @State var playbackCDNProbeResults: [PlaybackCDNProbeResult] = []
    @State var playbackCDNProbeMessage: String?
    @State var playbackCDNProbeTask: Task<Void, Never>?
    @State var isShowingPlaybackCDNProbeDetails = false
    @State var playbackURLPreferenceSnapshots: [PlaybackURLPreferenceSnapshot] = []
    @State var isShowingPlaybackURLPreferenceDetails = false
    @State var playbackCustomCDNHostDraft = ""

    init(libraryStore: LibraryStore, mode: Mode = .user) {
        self.libraryStore = libraryStore
        self.mode = mode
    }

    var body: some View {
        Form {
            MinePlaybackPreferenceSection(
                libraryStore: libraryStore,
                showsBasicPreferences: mode == .user,
                showsAdvancedPreferences: mode == .developer,
                playbackPreferenceSummary: AnyView(playbackPreferenceSummary),
                playbackCDNProbeRefreshIntervalTitle: playbackCDNProbeRefreshIntervalTitle,
                isProbingPlaybackCDN: isProbingPlaybackCDN,
                playbackCDNProbeMessage: playbackCDNProbeMessage,
                probePlaybackCDN: probePlaybackCDN,
                showsAdvancedPlaybackSettings: $showsAdvancedPlaybackSettings,
                playbackCustomCDNHostDraft: $playbackCustomCDNHostDraft,
                commitPlaybackCustomCDNHost: commitPlaybackCustomCDNHost
            ) {
                playbackCDNProbeSummary
                playbackURLPreferenceSummary
            }

            MinePlaybackToolsSection(mode: mode, libraryStore: libraryStore)
        }
        .tint(libraryStore.appTintColor)
        .formStyle(.grouped)
        .standardPageHorizontalContentMargins(libraryStore.standardPageHorizontalInset)
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
        .task {
            guard mode == .developer else { return }
            playbackCustomCDNHostDraft = libraryStore.playbackCustomCDNHost ?? ""
            refreshPlaybackURLPreferenceSnapshots()
            refreshPlaybackCDNProbeIfNeeded()
        }
        .onChange(of: libraryStore.playbackCustomCDNHost) { _, host in
            playbackCustomCDNHostDraft = host ?? ""
        }
        .onDisappear {
            playbackCDNProbeTask?.cancel()
            playbackCDNProbeTask = nil
            isProbingPlaybackCDN = false
        }
    }

}

extension MinePlaybackSettingsView {
    func commitPlaybackCustomCDNHost() {
        let trimmedHost = playbackCustomCDNHostDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            playbackCustomCDNHostDraft = ""
            libraryStore.setPlaybackCustomCDNHost(nil)
            return
        }
        guard let normalizedHost = PlaybackCDNPreference.normalizedCustomHost(trimmedHost) else {
            return
        }
        playbackCustomCDNHostDraft = normalizedHost
        libraryStore.setPlaybackCustomCDNHost(normalizedHost)
        libraryStore.setPlaybackCDNPreference(.custom)
    }
}
