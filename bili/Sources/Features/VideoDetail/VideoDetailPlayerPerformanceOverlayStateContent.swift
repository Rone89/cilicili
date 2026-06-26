import SwiftUI

struct PlayerPerformanceOverlayLoadedContent: View {
    let session: PlayerPerformanceSession
    let playerViewModel: PlayerStateViewModel?

    var body: some View {
        PlayerPerformanceOverlayMetricsGrid(session: session)
        PlayerPerformanceOverlaySamplesSection(samples: session.recentStartupSamples)
        PlayerPerformanceOverlayStartupWaterfallSection(session: session)
        PlayerPerformanceOverlayDiagnosticsSection(
            session: session,
            playerViewModel: playerViewModel
        )
        PlayerPerformanceOverlayCountersRow(session: session)
        PlayerPerformanceOverlayTerminalSection(session: session)
    }
}
