import Foundation

extension LiveRoomViewModel {
    func installPlayer(for candidate: LiveStreamURLCandidate, generation: Int) {
        guard isCurrentLoad(generation) else { return }
        startupWatchdogTask?.cancel()
        playbackStallWatchdogTask?.cancel()
        playerViewModel?.onPlaybackFailure = nil
        playerViewModel?.stop()

        let viewModel = PlayerStateViewModel(
            videoURL: candidate.url,
            audioURL: nil,
            videoStream: nil,
            audioStream: nil,
            title: title,
            referer: "https://live.bilibili.com/\(roomID)",
            metricsID: "live-\(roomID)-\(currentCandidateIndex)",
            engine: DefaultPlayerRenderingEngine.make()
        )
        viewModel.onPlaybackFailure = { [weak self] message in
            self?.handlePlaybackFailure(message: message, generation: generation)
        }
        playerViewModel = viewModel
        refreshLiveDanmakuDiagnosticsRenderState()
        updateStreamMenuItems()
        updateQualityMenuItems()
        scheduleStartupWatchdog(for: viewModel, generation: generation)
        schedulePlaybackStallWatchdog(for: viewModel, generation: generation)
    }

    func handlePlaybackFailure(message: String?, generation: Int) {
        guard isCurrentLoad(generation) else { return }
        startupWatchdogTask?.cancel()
        guard currentCandidateIndex + 1 < streamCandidates.count else {
            streamFallbackMessage = nil
            playerViewModel?.onPlaybackFailure = nil
            playerViewModel?.stop()
            playerViewModel = nil
            state = .failed(message ?? "这个直播流暂时无法播放")
            return
        }

        currentCandidateIndex += 1
        streamFallbackMessage = "正在切换到 \(currentStreamTitle ?? "备用直播源")"
        state = .loading
        installPlayer(for: streamCandidates[currentCandidateIndex], generation: generation)
        state = .loaded
        playerViewModel?.play()
    }

    func selectStreamCandidate(id: Int) {
        guard streamCandidates.indices.contains(id), id != currentCandidateIndex else { return }
        let generation = currentLoadGeneration
        currentCandidateIndex = id
        updateStreamMenuItems()
        streamFallbackMessage = "正在切换到 \(currentStreamTitle ?? "直播线路")"
        state = .loading
        installPlayer(for: streamCandidates[id], generation: generation)
        state = .loaded
        playerViewModel?.play()
    }

    func selectQuality(qn: Int) {
        guard qn > 0, qn != selectedQualityQN || currentQualityTitle == nil else { return }
        let generation = currentLoadGeneration
        qualitySwitchTask?.cancel()
        qualitySwitchTask = Task { [weak self] in
            await self?.switchQuality(to: qn, generation: generation)
        }
    }

    func switchQuality(to qn: Int, generation: Int) async {
        guard isCurrentLoad(generation), roomID > 0 else { return }
        let previousCandidate = streamCandidates.indices.contains(currentCandidateIndex)
            ? streamCandidates[currentCandidateIndex]
            : nil
        streamFallbackMessage = "正在切换到 \(LiveStreamQuality.defaultTitle(for: qn))"
        state = .loading
        do {
            let streamResult = try await api.fetchLiveStreamInfo(roomID: roomID, quality: qn)
            guard !Task.isCancelled, isCurrentLoad(generation) else { return }
            guard !streamResult.candidates.isEmpty else {
                streamFallbackMessage = "这个画质暂时不可用"
                state = .loaded
                return
            }
            streamCandidates = streamResult.candidates
            availableQualities = streamResult.playableQualities
            currentCandidateIndex = Self.preferredCandidateIndex(
                in: streamResult.candidates,
                preferredQuality: qn,
                preferredSource: previousCandidate
            )
            let selectedCandidate = streamCandidates[currentCandidateIndex]
            selectedQualityQN = qn
            updateStreamMenuItems()
            updateQualityMenuItems()
            if selectedCandidate.currentQN != qn {
                streamFallbackMessage = "该画质暂不可用，已切到 \(currentQualityTitle ?? "可用画质")"
            } else {
                streamFallbackMessage = nil
            }
            installPlayer(for: selectedCandidate, generation: generation)
            state = .loaded
            playerViewModel?.play()
        } catch {
            guard !Task.isCancelled, isCurrentLoad(generation) else { return }
            streamFallbackMessage = "画质切换失败：\(error.localizedDescription)"
            updateQualityMenuItems()
            state = playerViewModel == nil ? .failed(streamFallbackMessage ?? "画质切换失败") : .loaded
        }
    }

    func scheduleStartupWatchdog(for viewModel: PlayerStateViewModel, generation: Int) {
        startupWatchdogTask = Task { [weak self, weak viewModel] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      let viewModel,
                      self.isCurrentLoad(generation),
                      self.playerViewModel === viewModel,
                      !viewModel.hasPresentedPlayback
                else { return }
                self.handlePlaybackFailure(message: "直播流首帧加载超时", generation: generation)
            }
        }
    }

    func schedulePlaybackStallWatchdog(for viewModel: PlayerStateViewModel, generation: Int) {
        playbackStallWatchdogTask = Task { [weak self, weak viewModel] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      let viewModel,
                      self.isCurrentLoad(generation),
                      self.playerViewModel === viewModel,
                      viewModel.hasPresentedPlayback
                else { return }
            }

            var lastTime = await MainActor.run { viewModel?.currentTime ?? 0 }
            var stalledChecks = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard !Task.isCancelled else { return }
                let shouldSwitch = await MainActor.run { () -> Bool in
                    guard let self,
                          let viewModel,
                          self.isCurrentLoad(generation),
                          self.playerViewModel === viewModel
                    else { return false }
                    if viewModel.errorMessage != nil {
                        return true
                    }
                    guard viewModel.wantsAutoplay else {
                        stalledChecks = 0
                        lastTime = viewModel.currentTime
                        return false
                    }
                    let currentTime = viewModel.currentTime
                    if viewModel.isBuffering || abs(currentTime - lastTime) < 0.1 {
                        stalledChecks += 1
                    } else {
                        stalledChecks = 0
                    }
                    lastTime = currentTime
                    return stalledChecks >= 2 && self.currentCandidateIndex + 1 < self.streamCandidates.count
                }
                guard shouldSwitch else { continue }
                await MainActor.run {
                    self?.handlePlaybackFailure(message: "直播流长时间无画面", generation: generation)
                }
                return
            }
        }
    }

    func updateStreamMenuItems() {
        streamMenuItems = streamCandidates.indices.map { index in
            LiveStreamMenuItem(
                id: index,
                title: Self.streamTitle(for: streamCandidates[index], index: index),
                isSelected: index == currentCandidateIndex
            )
        }
    }

    func updateQualityMenuItems() {
        let currentQN = streamCandidates.indices.contains(currentCandidateIndex)
            ? streamCandidates[currentCandidateIndex].currentQN
            : selectedQualityQN
        let qualities = availableQualities.isEmpty
            ? LiveStreamQuality.merged(
                streamCandidates.compactMap { candidate in
                    candidate.currentQN.map {
                        LiveStreamQuality(qn: $0, description: candidate.qualityTitle)
                    }
                }
            )
            : availableQualities
        qualityMenuItems = qualities.map { quality in
            LiveStreamQualityMenuItem(
                qn: quality.qn,
                title: quality.title,
                isSelected: quality.qn == currentQN || (currentQN == nil && quality.qn == selectedQualityQN)
            )
        }
        if let currentQN {
            currentQualityTitle = qualities.first(where: { $0.qn == currentQN })?.title
                ?? LiveStreamQuality.defaultTitle(for: currentQN)
        } else {
            currentQualityTitle = nil
        }
    }
}
