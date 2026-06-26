import Foundation

extension VideoDetailViewModel {
    func temporarilyAvoidCurrentAutomaticPlaybackCDN(reason: String) {
        guard libraryStore.playbackCDNPreference == .automatic else { return }
        let currentPreference = libraryStore.effectivePlaybackCDNPreference
        guard currentPreference != .automatic,
              libraryStore.temporarilyAvoidAutomaticPlaybackCDN(currentPreference)
        else { return }
        PlayerMetricsLog.record(
            .network,
            metricsID: detail.bvid,
            title: detail.title,
            message: "automaticCDNAvoided cdn=\(currentPreference.rawValue) reason=\(diagnosticToken(reason))"
        )
    }
}
