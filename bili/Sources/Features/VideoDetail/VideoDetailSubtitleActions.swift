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
        store.setLoadErrorMessage(nil)
        if store.cues(for: lan) == nil {
            guard let track = store.tracks.first(where: { $0.lan == lan }) else {
                subtitleLogger.info("select lan=\(lan, privacy: .public) track missing")
                return
            }
            // v2 地址优先（AI 多语言轨常见），失败或为空时回落旧地址。
            let candidates = [track.subtitleURLV2, track.subtitleURL]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            guard !candidates.isEmpty else {
                subtitleLogger.info("select lan=\(lan, privacy: .public) has no subtitle url")
                store.setLoadErrorMessage("该字幕轨没有可用的字幕地址")
                return
            }
            var loaded: [VideoSubtitleCue] = []
            var lastError: Error?
            for rawURL in candidates {
                do {
                    let cues = try await api.fetchVideoSubtitleCues(subtitleURL: rawURL)
                    subtitleLogger.info(
                        "cues loaded: lan=\(lan, privacy: .public) count=\(cues.count) host=\(URL(string: BiliAPIClient.normalizedSubtitleURL(rawURL))?.host ?? "?", privacy: .public)"
                    )
                    if !cues.isEmpty {
                        loaded = cues
                        break
                    }
                } catch is CancellationError {
                    return
                } catch {
                    lastError = error
                    subtitleLogger.error(
                        "cue fetch failed lan=\(lan, privacy: .public) host=\(URL(string: BiliAPIClient.normalizedSubtitleURL(rawURL))?.host ?? "?", privacy: .public): \(String(describing: error), privacy: .public)"
                    )
                }
            }
            if loaded.isEmpty, let lastError {
                store.setLoadErrorMessage("字幕内容加载失败")
                subtitleLogger.error("all cue urls failed lan=\(lan, privacy: .public): \(String(describing: lastError), privacy: .public)")
                return
            }
            store.storeCues(loaded, for: lan)
            if loaded.isEmpty {
                store.setLoadErrorMessage("该字幕轨内容为空")
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
            VideoSubtitleTrack(lan: "ai-zh", lanDoc: "中文", isAI: true),
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
        if ProcessInfo.processInfo.arguments.contains("--subtitle-fixture-auto-sheet") {
            // 用独立 Task：视图任务在播放器重绑时会被取消，不能让它吞掉弹窗触发。
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let self else { return }
                self.isShowingSubtitleSelection = true
                subtitleLogger.info("fixture auto sheet requested")
            }
        }
        await selectSubtitleTrack(lan: libraryStore.videoSubtitlePreference.preferredTrack(
            in: store.tracks,
            isMuted: false
        )?.lan)
        return true
    }
    #endif
}
