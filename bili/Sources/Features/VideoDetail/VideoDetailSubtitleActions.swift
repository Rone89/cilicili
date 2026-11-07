import Foundation

extension VideoDetailViewModel {
    /// 进入视频或切换分P后加载字幕轨，并按用户偏好应用默认选轨。
    func loadSubtitleTracksForCurrentVideo() async {
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
            await applySubtitlePreference()
        } catch is CancellationError {
            return
        } catch {
            store.setLoadErrorMessage("字幕轨加载失败")
        }
    }

    /// 按当前偏好重新选轨；偏好为关闭或无匹配轨时清除选轨。
    func applySubtitlePreference() async {
        let isMuted: Bool
        if let player = stablePlayerViewModel {
            isMuted = player.isMuted || player.volume <= 0
        } else {
            isMuted = false
        }
        let lan = libraryStore.videoSubtitlePreference
            .preferredTrack(in: subtitleRenderStore.tracks, isMuted: isMuted)?
            .lan
        await selectSubtitleTrack(lan: lan)
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
}
