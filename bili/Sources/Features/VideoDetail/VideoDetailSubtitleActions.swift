import Foundation

extension VideoDetailViewModel {
    /// AI 字幕实验开关关闭时清空字幕态；打开后仅在下次进入视频详情时生效。
    func loadSubtitleTracksIfEligible() async {
        guard libraryStore.aiSubtitleExperimentEnabled else {
            subtitleRenderStore.setTracks([])
            subtitleRenderStore.setSelectedLan(nil)
            subtitleRenderStore.setLoadErrorMessage(nil)
            return
        }
        guard let aid = detail.aid, let cid = selectedCID else { return }
        await loadSubtitleTracks(aid: aid, cid: cid, bvid: detail.bvid)
    }

    func loadSubtitleTracks(aid: Int, cid: Int, bvid: String?) async {
        let store = subtitleRenderStore
        guard !store.isLoadingTracks else { return }
        store.setIsLoadingTracks(true)
        store.setLoadErrorMessage(nil)
        defer { store.setIsLoadingTracks(false) }
        do {
            let tracks = try await api.fetchVideoSubtitleTracks(aid: aid, cid: cid, bvid: bvid)
            store.setTracks(tracks)
            if let lan = store.preferredTrackLan() {
                await selectSubtitleTrack(lan: lan)
            } else {
                store.setSelectedLan(nil)
            }
        } catch is CancellationError {
            return
        } catch {
            store.setLoadErrorMessage("字幕轨加载失败")
        }
    }

    func selectSubtitleTrack(lan: String?) async {
        let store = subtitleRenderStore
        guard let lan else {
            store.setSelectedLan(nil)
            return
        }
        store.setSelectedLan(lan)
        if store.cues(for: lan) != nil { return }
        guard let track = store.tracks.first(where: { $0.lan == lan }),
              let url = track.subtitleURLV2 ?? track.subtitleURL,
              !url.isEmpty
        else { return }
        do {
            let cues = try await api.fetchVideoSubtitleCues(subtitleURL: url)
            store.storeCues(cues, for: lan)
        } catch is CancellationError {
            return
        } catch {
            store.setLoadErrorMessage("字幕内容加载失败")
        }
    }

    func updateSubtitlePlaybackTime(_ time: TimeInterval) {
        subtitleRenderStore.updateCurrentCue(at: time)
    }
}
