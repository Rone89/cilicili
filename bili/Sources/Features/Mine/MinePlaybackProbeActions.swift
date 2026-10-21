import Foundation

extension MinePlaybackSettingsView {
    func probePlaybackCDN() {
        startPlaybackCDNProbe(isAutomatic: false)
    }

    func refreshPlaybackCDNProbeIfNeeded() {
        guard playbackCDNProbeTask == nil else { return }
        guard libraryStore.needsPlaybackCDNProbeRefresh else { return }
        startPlaybackCDNProbe(isAutomatic: true)
    }

    func startPlaybackCDNProbe(isAutomatic: Bool) {
        guard !isProbingPlaybackCDN else { return }
        guard let video = libraryStore.recentPlaybackCDNProbeVideo else {
            playbackCDNProbeMessage = "请先播放一个视频几秒，再返回这里测试 CDN。"
            return
        }
        let contextKey = libraryStore.currentPlaybackCDNProbeContextKey
        let addressFamilyPreference = libraryStore.playbackNetworkAddressFamilyPreference
        isProbingPlaybackCDN = true
        playbackCDNProbeMessage = "正在使用最近观看视频的播放地址测试 CDN…"
        if !isAutomatic {
            playbackCDNSettingsSnapshot = nil
            playbackCDNSettingsContextKey = nil
        }

        playbackCDNProbeTask?.cancel()
        playbackCDNProbeTask = Task { @MainActor in
            defer {
                if !Task.isCancelled {
                    isProbingPlaybackCDN = false
                    playbackCDNProbeTask = nil
                }
            }
            do {
                let snapshot = try await PlaybackCDNSettingsProbe.run(
                    video: video,
                    addressFamilyPreference: addressFamilyPreference,
                    fetchPlayURL: { [api] video in
                        try await api.fetchPlayURLUncached(bvid: video.bvid, cid: video.cid)
                    }
                )
                try Task.checkCancellation()
                guard contextKey == libraryStore.currentPlaybackCDNProbeContextKey else {
                    playbackCDNProbeMessage = "网络或协议设置已改变，请重新测试 CDN。"
                    return
                }
                playbackCDNSettingsSnapshot = snapshot
                playbackCDNSettingsContextKey = contextKey
                libraryStore.setPlaybackCDNProbeSnapshot(snapshot)
                if let preference = snapshot.recommendedPreference,
                   let elapsed = snapshot.result(for: preference)?.elapsedMilliseconds {
                    playbackCDNProbeMessage = "已使用最近观看视频测速：推荐 \(preference.title)，\(elapsed) ms"
                } else {
                    playbackCDNProbeMessage = "未找到可用 CDN，已保留当前设置"
                }
                refreshPlaybackURLPreferenceSnapshots()
            } catch {
                guard !Task.isCancelled else { return }
                playbackCDNProbeMessage = "CDN 测试未完成：\(error.localizedDescription)"
            }
        }
    }

    func refreshPlaybackURLPreferenceSnapshots() {
        playbackURLPreferenceSnapshots = PlaybackURLPreferenceStore.shared.rankedSnapshots(limit: 8)
    }
}
