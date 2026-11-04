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

    func setTracks(_ tracks: [VideoSubtitleTrack]) {
        self.tracks = tracks
        if tracks.isEmpty {
            setSelectedLan(nil)
        }
    }

    func setIsLoadingTracks(_ loading: Bool) {
        isLoadingTracks = loading
    }

    func setLoadErrorMessage(_ message: String?) {
        loadErrorMessage = message
    }

    /// 默认轨优先级：中文 CC > 中文 AI > 第一条（对齐 PiliPlus 的中文优先排序）。
    func preferredTrackLan() -> String? {
        let zhCC = tracks.first { $0.lan.contains("zh") && !$0.isAI }
        let zhAI = tracks.first { $0.lan.contains("zh") && $0.isAI }
        return (zhCC ?? zhAI ?? tracks.first)?.lan
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
        guard let cues = cues(for: selectedLan), !cues.isEmpty else {
            if currentCue != nil { currentCue = nil }
            return
        }
        if let match = Self.cue(at: time, in: cues), match != currentCue {
            currentCue = match
        } else if match == nil, currentCue != nil {
            currentCue = nil
        }
    }

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

private extension Optional where Wrapped == [VideoSubtitleCue] {
    var isNilOrEmpty: Bool {
        self?.isEmpty ?? true
    }
}
