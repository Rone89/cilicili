import Foundation

extension VideoDetailViewModel {
    /// 合集选集原地切换：合集条目是独立视频（不同 bvid），切完把合集数据带到新条目上，
    /// 再补拉完整详情元数据（stat/UP主/简介在合集条目里没有）。
    func selectUgcSeasonEpisode(_ video: VideoItem) {
        guard !isPlaybackTerminatedForNavigation else { return }
        // 合集条目按 bvid 唯一标识；当前视频的条目由行级 isSelected 拦截，这里兜底。
        guard video.bvid != detail.bvid else { return }
        captureVideoListenPlaybackIntentForContentSwitch()
        saveCurrentPlaybackProgressBeforeContentSwitch()

        isPlaybackInvalidatedForNavigation = false
        cancelBackgroundTasks()
        detail = video
        selectedCID = video.cid ?? video.pages?.first?.cid
        hasResolvedDetailMetadata = true
        manuallySelectedPageCID = nil
        didResolveCloudHistoryResume = false
        pendingPlaybackHistoryResumeTime = nil
        pendingPlaybackHistoryResumeCID = nil
        resumeDiagnostics = .none
        resetPlaybackStateForSelectedPage()
        resetInlineStateForContentSwitch()
        syncCommentsRenderStore()
        syncRelatedRenderStore()

        pageLoadingTask?.cancel()
        let token = UUID()
        pageLoadingToken = token
        pageLoadingTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            defer {
                self.clearPageLoadingTaskIfCurrent(token)
            }
            guard !Task.isCancelled,
                  !self.isPlaybackInvalidatedForNavigation,
                  self.pageLoadingToken == token,
                  self.detail.bvid == video.bvid,
                  self.selectedCID == (video.cid ?? video.pages?.first?.cid)
            else { return }
            await self.loadPlayURL()
        }

        let switchedBVID = video.bvid
        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            // 切换后元数据补拉；refreshDetailMetadata 自带 isCurrentVideoContext 防串。
            guard self.detail.bvid == switchedBVID else { return }
            await self.refreshDetailMetadata()
        }
    }
}
