import Foundation
import SwiftUI

struct VideoDetailPerformanceOverlayContainer: View {
    @ObservedObject var store: VideoDetailNetworkDiagnosticsRenderStore
    let panelWidth: CGFloat
    let maximumHeight: CGFloat

    var body: some View {
        PlayerPerformanceOverlay(
            metricsID: store.metricsID,
            playerViewModel: store.playerViewModel,
            panelWidth: panelWidth,
            maximumHeight: maximumHeight
        )
    }
}

struct PlayerPerformanceOverlay: View {
    @StateObject private var sessionObserver: PlayerPerformanceSessionObserver
    let metricsID: String
    let playerViewModel: PlayerStateViewModel?
    let panelWidth: CGFloat
    let maximumHeight: CGFloat

    init(
        metricsID: String,
        playerViewModel: PlayerStateViewModel?,
        panelWidth: CGFloat = 300,
        maximumHeight: CGFloat = 420
    ) {
        self.metricsID = metricsID
        self.playerViewModel = playerViewModel
        self.panelWidth = panelWidth
        self.maximumHeight = maximumHeight
        _sessionObserver = StateObject(
            wrappedValue: PlayerPerformanceSessionObserver(metricsID: metricsID)
        )
    }

    private var session: PlayerPerformanceSession? {
        sessionObserver.session
    }

    var body: some View {
        PlayerPerformanceOverlayContent(
            metricsID: metricsID,
            session: session,
            playerViewModel: playerViewModel,
            panelWidth: panelWidth,
            maximumHeight: maximumHeight
        )
        .playerPerformanceOverlayLifecycle(
            metricsID: metricsID,
            sessionObserver: sessionObserver
        )
    }
}
