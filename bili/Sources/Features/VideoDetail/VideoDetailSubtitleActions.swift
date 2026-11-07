import Foundation
import os

private let subtitleLogger = Logger(subsystem: "cc.bili", category: "Subtitle")

extension VideoDetailViewModel {
    /// 进入视频或切换分P后加载字幕轨，并按用户偏好应用默认选轨。
    func loadSubtitleTracksForCurrentVideo() async {
        #if DEBUG
        if await loadSubtitleFixtureIfRequested() {
            return
        }
        #endif
        guard let aid = detail.aid, let cid = selectedCID else {
            subtitleLogger.info("subtitle load skipped: aid=\(self.detail.aid.map(String.init) ?? "nil") cid=\(self.selectedCID.map(String.init) ?? "nil")")
            return
        }
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
            subtitleLogger.info("tracks loaded: count=\(tracks.count) lans=\(tracks.map(\.lan), privacy: .public) isLoggedInGate=aiTracksNeedLogin")
            await applySubtitlePreference()
        } catch is CancellationError {
            return
        } catch {
            store.setLoadErrorMessage("字幕轨加载失败")
            subtitleLogger.error("track fetch failed: \(String(describing: error), privacy: .public)")
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
        if store.cues(for: lan) == nil {
            guard let track = store.tracks.first(where: { $0.lan == lan }),
                  let url = track.subtitleURLV2 ?? track.subtitleURL,
                  !url.isEmpty
            else {
                subtitleLogger.info("select lan=\(lan, privacy: .public) has no subtitle url")
                return
            }
            do {
                let cues = try await api.fetchVideoSubtitleCues(subtitleURL: url)
                store.storeCues(cues, for: lan)
                subtitleLogger.info("cues loaded: lan=\(lan, privacy: .public) count=\(cues.count)")
            } catch is CancellationError {
                return
            } catch {
                store.setLoadErrorMessage("字幕内容加载失败")
                subtitleLogger.error("cue fetch failed lan=\(lan, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        } else {
            subtitleLogger.info("select lan=\(lan, privacy: .public) cached=true")
        }
        // 暂停时播放时钟不发 tick，选轨后立即按当前时间求值一次 cue，
        // 否则已暂停的画面上字幕毫无反馈，恢复播放前一直是空。
        if let player = stablePlayerViewModel {
            store.updateCurrentCue(at: player.playbackClock.currentTime)
        }
    }

    #if DEBUG
    /// `--subtitle-fixture` 启动参数：注入假字幕轨，验证按钮/弹层/渲染链路（无需登录态）。
    private func loadSubtitleFixtureIfRequested() async -> Bool {
        guard ProcessInfo.processInfo.arguments.contains("--subtitle-fixture") else {
            return false
        }
        let store = subtitleRenderStore
        store.setTracks([
            VideoSubtitleTrack(lan: "zh", lanDoc: "中文", isAI: false),
            VideoSubtitleTrack(lan: "ai-zh", lanDoc: "中文（AI）", isAI: true),
        ])
        store.storeCues(
            [
                VideoSubtitleCue(from: 0, to: 300, content: "字幕夹具第一句"),
                VideoSubtitleCue(from: 300, to: 600, content: "字幕夹具第二句"),
            ],
            for: "zh"
        )
        store.storeCues(
            [VideoSubtitleCue(from: 0, to: 600, content: "AI 夹具句")],
            for: "ai-zh"
        )
        store.setLoadErrorMessage(nil)
        subtitleLogger.info("subtitle fixture injected")
        await selectSubtitleTrack(lan: libraryStore.videoSubtitlePreference.preferredTrack(
            in: store.tracks,
            isMuted: false
        )?.lan)
        return true
    }
    #endif
}
