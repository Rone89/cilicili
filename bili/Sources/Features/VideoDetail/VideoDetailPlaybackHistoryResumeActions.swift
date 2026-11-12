import Foundation
import OSLog

extension VideoDetailViewModel {
    func prepareHistoryResumeBeforeApplyingPlayURL(_ data: PlayURLData, cid: Int) async -> Bool {
        guard stablePlayerViewModel == nil else { return false }
        guard playbackOptions.resumesPlaybackHistory else { return false }
        if VideoDetailPlaybackHistorySelectionPolicy.preservesManualPage(
            manuallySelectedCID: manuallySelectedPageCID,
            currentCID: cid
        ) {
            if pendingPlaybackHistoryResumeTime == nil,
               let resumeTime = libraryStore.localPlaybackResumeTime(
                   for: detail,
                   cid: cid,
                   duration: resumeDurationHint(for: cid)
               ) {
                setPendingPlaybackHistoryResumeTime(resumeTime, cid: cid)
            }
            return false
        }
        if redirectToHistoryCIDIfNeeded(data.lastPlayCID, currentCID: cid) {
            return true
        }
        if usesMainAccountHistoryMetadata,
           redirectToHistoryCIDIfNeeded(detail.historyCID, currentCID: cid) {
            return true
        }
        let minimumProgress = playbackHistoryResumeMinimumProgress
        if let localProgress = libraryStore.localPlaybackProgress(
            for: detail,
            duration: historyResumeDurationHint
        ),
           redirectToHistoryCIDIfNeeded(localProgress.cid, currentCID: cid) {
            return true
        }
        if let resumeTime = libraryStore.localPlaybackResumeTime(
            for: detail,
            cid: cid,
            duration: historyResumeDurationHint
        ) {
            setPendingPlaybackHistoryResumeTime(resumeTime, cid: cid)
            return false
        }
        if let resumeTime = data.resumeTime(
            duration: historyResumeDurationHint,
            minimumProgress: minimumProgress
        ) {
            setPendingPlaybackHistoryResumeTime(resumeTime, cid: cid)
            return false
        }
        if usesMainAccountHistoryMetadata,
           let resumeTime = detail.historyResumeTime,
           resumeTime >= minimumProgress,
           detail.historyCID == nil || detail.historyCID == cid {
            setPendingPlaybackHistoryResumeTime(resumeTime, cid: cid)
            return false
        }
        guard pendingPlaybackHistoryResumeTime == nil else { return false }
        await prepareCloudHistoryResumeIfNeeded(currentCID: cid)
        return selectedCID != cid
    }

    func consumePendingPlaybackHistoryResumeTime(for cid: Int?) -> TimeInterval? {
        guard stablePlayerViewModel == nil,
              let resumeTime = pendingPlaybackHistoryResumeTime,
              resumeTime > 0.25
        else { return nil }
        if let pendingCID = pendingPlaybackHistoryResumeCID,
           let cid,
           pendingCID != cid {
            return nil
        }
        pendingPlaybackHistoryResumeTime = nil
        pendingPlaybackHistoryResumeCID = nil
        return resumeTime
    }

    private var historyResumeDurationHint: TimeInterval? {
        detail.duration.map(TimeInterval.init)
    }

    private var playbackHistoryResumeMinimumProgress: TimeInterval {
        TimeInterval(libraryStore.playbackHistorySyncThresholdSeconds)
    }

    private var usesMainAccountHistoryMetadata: Bool {
        let snapshot = sessionStore.credentialSnapshot(
            for: .historyRead,
            multiAccountEnabled: libraryStore.multiAccountEnabled
        )
        return snapshot.accountMID == sessionStore.mainAccountMID
    }

    private func prepareCloudHistoryResumeIfNeeded(currentCID: Int) async {
        guard !VideoDetailPlaybackHistorySelectionPolicy.preservesManualPage(
            manuallySelectedCID: manuallySelectedPageCID,
            currentCID: currentCID
        ) else { return }
        guard !didResolveCloudHistoryResume else { return }
        guard !libraryStore.incognitoModeEnabled,
              let aid = detail.aid
        else { return }
        let bvid = detail.bvid
        beginCloudHistoryResumeFetchIfNeeded()
        didResolveCloudHistoryResume = true
        guard let task = cloudHistoryResumeTask,
              cloudHistoryResumeTaskAid == aid
        else { return }
        // 限时等待：预算内拿到历史就按原语义恢复；拿不到先放行启动链路，
        // 历史晚到后再校正，避免 /x/v2/history 垫在首帧关键路径上。
        let grace = PlaybackEnvironment.current.preferredCloudHistoryStartupGrace
        let finishedInTime = await PendingTaskDeadline.finishes(task, within: grace)
        if cloudHistoryResumeTaskAid == aid {
            cloudHistoryResumeTask = nil
            cloudHistoryResumeTaskAid = nil
        }
        if finishedInTime {
            let history = await task.value
            applyResolvedCloudHistory(history, currentCID: currentCID, bvid: bvid)
        } else {
            PlayerMetricsLog.logger.info(
                "cloudHistoryResumeDeferred graceMs=\(grace / 1_000_000) aid=\(aid, privacy: .public)"
            )
            Task { @MainActor [weak self] in
                let history = await task.value
                self?.applyLateCloudHistory(history, currentCID: currentCID, bvid: bvid)
            }
        }
    }

    private func applyResolvedCloudHistory(
        _ history: VideoHistoryProgress?,
        currentCID: Int,
        bvid: String
    ) {
        guard let history,
              !Task.isCancelled,
              !isPlaybackInvalidatedForNavigation,
              detail.bvid == bvid,
              selectedCID == currentCID
        else { return }

        let targetCID = matchingHistoryCID(history.lastPlayCid) ?? currentCID
        if let resumeTime = history.resumeTime(
            duration: historyResumeDurationHint,
            minimumProgress: playbackHistoryResumeMinimumProgress
        ) {
            setPendingPlaybackHistoryResumeTime(resumeTime, cid: targetCID)
        }
        if targetCID != currentCID {
            selectedCID = targetCID
        }
    }

    /// 历史晚到校正：播放器已创建时只校正同一分 P，且用户未手动 seek、
    /// 尚未看过历史位置才跳转；播放器未创建时写入正常待恢复路径。
    private func applyLateCloudHistory(
        _ history: VideoHistoryProgress?,
        currentCID: Int,
        bvid: String
    ) {
        guard let history,
              !isPlaybackInvalidatedForNavigation,
              detail.bvid == bvid,
              selectedCID == currentCID
        else { return }
        let targetCID = matchingHistoryCID(history.lastPlayCid) ?? currentCID
        let resumeTime = history.resumeTime(
            duration: historyResumeDurationHint,
            minimumProgress: playbackHistoryResumeMinimumProgress
        )
        guard let player = stablePlayerViewModel, !player.isTerminated else {
            if let resumeTime {
                setPendingPlaybackHistoryResumeTime(resumeTime, cid: targetCID)
            }
            if targetCID != currentCID {
                selectedCID = targetCID
                Task { @MainActor [weak self] in
                    await self?.loadPlayURL()
                }
            }
            return
        }
        guard targetCID == currentCID,
              let resumeTime,
              player.lastUserSeekAt == nil,
              player.currentTime < resumeTime
        else {
            PlayerMetricsLog.logger.info(
                "cloudHistoryLateResumeSkipped bvid=\(bvid, privacy: .public) targetCID=\(targetCID) currentCID=\(currentCID)"
            )
            return
        }
        Task { @MainActor [weak self, weak player] in
            // 播放器可能仍在准备：有界等待首帧后复查护栏再校正。
            let deadline = ContinuousClock.now + .seconds(2)
            while let player,
                  !player.isTerminated,
                  !player.hasPresentedPlayback,
                  ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard let self,
                  let player,
                  !player.isTerminated,
                  !self.isPlaybackInvalidatedForNavigation,
                  self.detail.bvid == bvid,
                  self.selectedCID == currentCID,
                  player.lastUserSeekAt == nil,
                  player.currentTime < resumeTime
            else { return }
            let duration = player.duration ?? self.historyResumeDurationHint ?? 0
            guard duration > 0 else { return }
            player.seek(to: min(max(resumeTime / duration, 0), 1))
            PlayerMetricsLog.logger.info(
                "cloudHistoryLateResumeApplied bvid=\(bvid, privacy: .public) target=\(resumeTime, format: .fixed(precision: 2))"
            )
        }
    }

    func beginCloudHistoryResumeFetchIfNeeded() {
        guard playbackOptions.resumesPlaybackHistory else { return }
        guard manuallySelectedPageCID == nil else { return }
        guard !didResolveCloudHistoryResume,
              pendingPlaybackHistoryResumeTime == nil,
              !libraryStore.incognitoModeEnabled,
              let aid = detail.aid,
              aid > 0
        else { return }
        guard cloudHistoryResumeTask == nil || cloudHistoryResumeTaskAid != aid else { return }

        cloudHistoryResumeTask?.cancel()
        cloudHistoryResumeTaskAid = aid
        let api = api
        // 加入 tap 时启动的共享预取；取消本页包装任务不会取消共享请求。
        cloudHistoryResumeTask = Task(priority: .userInitiated) {
            await VideoPreloadCenter.shared.cloudHistoryProgress(for: aid, api: api)
        }
    }

    private func redirectToHistoryCIDIfNeeded(_ rawCID: Int?, currentCID: Int) -> Bool {
        guard let targetCID = matchingHistoryCID(rawCID),
              targetCID != currentCID
        else { return false }
        selectedCID = targetCID
        return true
    }

    private func matchingHistoryCID(_ rawCID: Int?) -> Int? {
        guard let rawCID, rawCID > 0 else { return nil }
        guard let pages = detail.pages, !pages.isEmpty else { return rawCID }
        return pages.contains(where: { $0.cid == rawCID }) ? rawCID : nil
    }

    private func setPendingPlaybackHistoryResumeTime(
        _ resumeTime: TimeInterval,
        cid: Int?
    ) {
        pendingPlaybackHistoryResumeTime = resumeTime
        pendingPlaybackHistoryResumeCID = cid
    }
}
