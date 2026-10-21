import Foundation

nonisolated struct PlaybackCDNProbeVideo: Equatable, Sendable {
    let bvid: String
    let cid: Int
}

nonisolated enum PlaybackCDNSettingsProbe {
    enum Failure: LocalizedError {
        case noPlayableURL

        var errorDescription: String? {
            "最近观看的视频暂无可用播放地址，请播放另一个视频后重试。"
        }
    }

    static func latestVideo(in progress: [StoredPlaybackProgress]) -> PlaybackCDNProbeVideo? {
        progress.sorted { $0.updatedAt > $1.updatedAt }.compactMap { item -> PlaybackCDNProbeVideo? in
            let bvid = item.bvid.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bvid.isEmpty, let cid = item.cid, cid > 0 else { return nil }
            return PlaybackCDNProbeVideo(bvid: bvid, cid: cid)
        }.first
    }

    static func playbackURLs(in data: PlayURLData) -> [URL] {
        // Probe actual API URLs without applying a manual CDN rewrite or codec
        // selection. The one-byte request does not decode or start playback.
        var addresses = [String]()
        for stream in [data.dash?.video?.first, data.dash?.audio?.first].compactMap({ $0 }) {
            addresses += [stream.baseURL] + (stream.backupURL ?? [])
        }
        if let progressive = data.durl?.first {
            addresses += [progressive.url] + (progressive.backupURL ?? [])
        }
        var seen = Set<URL>()
        return addresses.compactMap(URL.init(string:)).filter {
            ["http", "https"].contains($0.scheme?.lowercased() ?? "")
                && $0.host != nil && seen.insert($0).inserted
        }
    }

    static func run(
        video: PlaybackCDNProbeVideo,
        addressFamilyPreference: PlaybackNetworkAddressFamilyPreference,
        fetchPlayURL: @Sendable (PlaybackCDNProbeVideo) async throws -> PlayURLData,
        probe: @Sendable (PlaybackNetworkAddressFamilyPreference, [URL]) async -> PlaybackCDNProbeSnapshot = {
            await PlaybackCDNProbeService.recommendedSnapshot(addressFamilyPreference: $0, playbackURLs: $1)
        }
    ) async throws -> PlaybackCDNProbeSnapshot {
        try Task.checkCancellation()
        let data = try await fetchPlayURL(video)
        try Task.checkCancellation()
        let urls = playbackURLs(in: data)
        guard !urls.isEmpty else { throw Failure.noPlayableURL }
        let snapshot = await probe(addressFamilyPreference, urls)
        try Task.checkCancellation()
        return snapshot
    }
}
