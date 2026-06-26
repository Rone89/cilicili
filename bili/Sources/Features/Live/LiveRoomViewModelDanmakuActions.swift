import Foundation

extension LiveRoomViewModel {
    func toggleDanmaku() {
        isDanmakuEnabled.toggle()
        libraryStore.setDanmakuEnabled(isDanmakuEnabled)
        refreshLiveDanmakuDiagnosticsRenderState()
        if isDanmakuEnabled {
            resumeLiveDanmakuIfNeeded()
        } else {
            stopLiveDanmaku(clearItems: true)
        }
    }

    func toggleLiveDanmakuDiagnostics() {
        isLiveDanmakuDiagnosticsEnabled.toggle()
        refreshLiveDanmakuDiagnosticsRenderState(forcePublish: true)
        if isLiveDanmakuDiagnosticsEnabled {
            resumeLiveDanmakuIfNeeded()
        }
    }

    func suspendLiveDanmaku() {
        stopLiveDanmaku(clearItems: false)
    }

    func resumeLiveDanmakuIfNeeded() {
        guard isDanmakuEnabled, playerViewModel != nil, roomID > 0 else { return }
        startLiveDanmakuIfNeeded(roomID: roomID)
    }

    func applyGlobalDanmakuEnabled(_ isEnabled: Bool) {
        guard isDanmakuEnabled != isEnabled else { return }
        isDanmakuEnabled = isEnabled
        liveDanmakuRenderStore.updateEnabled(isEnabled)
        refreshLiveDanmakuDiagnosticsRenderState()
        if isEnabled {
            resumeLiveDanmakuIfNeeded()
        } else {
            stopLiveDanmaku(clearItems: true)
        }
    }

    func startLiveDanmakuIfNeeded(roomID: Int) {
        guard isDanmakuEnabled, liveDanmakuService == nil else { return }
        liveDanmakuStartDate = Date()
        liveDanmakuRenderStore.updatePlaybackTime(0)
        let service = LiveDanmakuService(
            roomID: roomID,
            api: api,
            onDiagnostics: { [weak self] event in
                self?.handleLiveDanmakuDiagnosticEvent(event)
            },
            onItems: { [weak self] items in
                self?.appendLiveDanmakuItems(items)
            }
        )
        liveDanmakuService = service
        service.start()
        startLiveDanmakuClock()
    }

    func scheduleLiveDanmakuStart(
        roomID: Int,
        playerViewModel: PlayerStateViewModel,
        generation: Int
    ) {
        liveDanmakuStartupTask?.cancel()
        guard isDanmakuEnabled else { return }
        liveDanmakuStartupTask = Task { [weak self, weak playerViewModel] in
            let pollIntervalNanoseconds: UInt64 = 150_000_000
            let maximumWaitNanoseconds: UInt64 = 1_800_000_000
            var waitedNanoseconds: UInt64 = 0

            while !Task.isCancelled, waitedNanoseconds < maximumWaitNanoseconds {
                let shouldStart = await MainActor.run { () -> Bool in
                    guard let self,
                          let playerViewModel,
                          self.isCurrentLoad(generation),
                          self.playerViewModel === playerViewModel
                    else { return false }
                    return playerViewModel.hasPresentedPlayback || playerViewModel.errorMessage != nil
                }
                if shouldStart { break }
                try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
                waitedNanoseconds += pollIntervalNanoseconds
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      let playerViewModel,
                      self.isCurrentLoad(generation),
                      self.playerViewModel === playerViewModel
                else { return }
                self.liveDanmakuStartupTask = nil
                self.startLiveDanmakuIfNeeded(roomID: roomID)
            }
        }
    }

    func stopLiveDanmaku(clearItems: Bool) {
        liveDanmakuStartupTask?.cancel()
        liveDanmakuStartupTask = nil
        liveDanmakuService?.stop()
        liveDanmakuService = nil
        liveDanmakuClockTask?.cancel()
        liveDanmakuClockTask = nil
        liveDanmakuStartDate = nil
        liveDanmakuRenderStore.updatePlaybackTime(0)
        if clearItems {
            liveDanmakuRenderStore.clearItems()
        }
        refreshLiveDanmakuDiagnosticsRenderState()
    }

    func startLiveDanmakuClock() {
        liveDanmakuClockTask?.cancel()
        liveDanmakuClockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, let liveDanmakuStartDate = self.liveDanmakuStartDate else { return }
                    self.liveDanmakuRenderStore.updatePlaybackTime(
                        max(0, Date().timeIntervalSince(liveDanmakuStartDate))
                    )
                }
            }
        }
    }

    func appendLiveDanmakuItems(_ items: [DanmakuItem]) {
        guard isDanmakuEnabled, !items.isEmpty else { return }
        liveDanmakuRenderStore.appendItems(items, retainingLimit: 240)
        if let liveDanmakuStartDate {
            liveDanmakuRenderStore.updatePlaybackTime(max(0, Date().timeIntervalSince(liveDanmakuStartDate)))
        }
        refreshLiveDanmakuDiagnosticsRenderState()
    }

    func handleLiveDanmakuDiagnosticEvent(_ event: LiveDanmakuDiagnosticEvent) {
        liveDanmakuDiagnosticsDraft.apply(event)
        applyCurrentRenderStateToDiagnosticsDraft()
        publishLiveDanmakuDiagnosticsIfNeeded()
    }

    func refreshLiveDanmakuDiagnosticsRenderState(forcePublish: Bool = false) {
        applyCurrentRenderStateToDiagnosticsDraft()
        publishLiveDanmakuDiagnosticsIfNeeded(force: forcePublish)
    }

    func applyCurrentRenderStateToDiagnosticsDraft() {
        liveDanmakuDiagnosticsDraft.apply(
            .renderState(
                isDanmakuEnabled: isDanmakuEnabled,
                overlayItemCount: liveDanmakuRenderStore.itemCount,
                hasPresentedPlayback: playerViewModel?.hasPresentedPlayback == true
            )
        )
    }

    func publishLiveDanmakuDiagnosticsIfNeeded(force: Bool = false) {
        guard force || isLiveDanmakuDiagnosticsEnabled else { return }
        liveDanmakuRenderStore.updateDiagnostics(liveDanmakuDiagnosticsDraft)
    }
}
