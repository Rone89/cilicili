import Combine
import SwiftUI

@MainActor
final class VideoDetailSubtitleStore: ObservableObject {
    @Published private(set) var tracks: [VideoSubtitleTrack] = []
    @Published private(set) var selectedLan: String?
    @Published private(set) var currentCue: VideoSubtitleCue?
    @Published private(set) var isLoadingTracks = false
    @Published private(set) var loadErrorMessage: String?

    private var cuesByLan: [String: [VideoSubtitleCue]] = [:]

    var hasTracks: Bool { !tracks.isEmpty }

    var selectedTrack: VideoSubtitleTrack? {
        tracks.first(where: { $0.lan == selectedLan })
    }

    func setTracks(_ tracks: [VideoSubtitleTrack]) {
        self.tracks = VideoSubtitlePreference.sortedTracks(tracks)
        if self.tracks.isEmpty {
            setSelectedLan(nil)
        }
    }

    func setIsLoadingTracks(_ loading: Bool) {
        isLoadingTracks = loading
    }

    func setLoadErrorMessage(_ message: String?) {
        loadErrorMessage = message
    }

    func cues(for lan: String) -> [VideoSubtitleCue]? {
        cuesByLan[lan]
    }

    func storeCues(_ cues: [VideoSubtitleCue], for lan: String) {
        cuesByLan[lan] = cues
        if selectedLan == lan {
            currentCue = nil
        }
    }

    func setSelectedLan(_ lan: String?) {
        selectedLan = lan
        currentCue = nil
    }

    func updateCurrentCue(at time: TimeInterval) {
        guard let lan = selectedLan, let cues = cues(for: lan), !cues.isEmpty else {
            if currentCue != nil { currentCue = nil }
            return
        }
        let match = Self.cue(at: time, in: cues)
        if match != currentCue {
            currentCue = match
        }
    }

    /// 二分定位当前时间所在的 cue；cue 按 from 升序下发。
    private static func cue(at time: TimeInterval, in cues: [VideoSubtitleCue]) -> VideoSubtitleCue? {
        var low = 0
        var high = cues.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let cue = cues[mid]
            if time < cue.from {
                high = mid - 1
            } else if time >= cue.to {
                low = mid + 1
            } else {
                return cue
            }
        }
        return nil
    }
}
