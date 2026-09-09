#if DEBUG
import Combine
import Foundation
import QuartzCore

enum VideoDetailPlaybackDiagnosticSurfaceEvent {
    case attached(
        surfaceID: ObjectIdentifier,
        playerID: ObjectIdentifier?,
        playerItemID: ObjectIdentifier?
    )
    case detached(
        surfaceID: ObjectIdentifier,
        playerID: ObjectIdentifier?,
        playerItemID: ObjectIdentifier?
    )
}

@MainActor
final class VideoDetailPlaybackDiagnostics {
    private var cancellables = Set<AnyCancellable>()
    private weak var observedPlayer: PlayerStateViewModel?
    private var blackFrameProbeTask: Task<Void, Never>?
    private var pageStartedAt: CFTimeInterval?
    private var firstPlaybackAt: CFTimeInterval?
    private var firstFrameAt: CFTimeInterval?
    private var rotationStartedAt: CFTimeInterval?
    private var lastPlayerID: ObjectIdentifier?
    private var lastPlayerItemID: ObjectIdentifier?
    private var hasLoggedPageSummary = false

    func begin(metricsID: String, title: String?) {
        guard pageStartedAt == nil else { return }
        pageStartedAt = CACurrentMediaTime()
        let titleSummary = title.map(PlayerMetricsLog.shortTitle) ?? "-"
        record(
            "videoDetail.begin metricsID=\(metricsID) title=\(titleSummary)"
        )
    }

    func observe(player: PlayerStateViewModel?) {
        guard observedPlayer !== player else {
            sampleIdentities(from: player)
            return
        }
        observedPlayer?.onVideoDetailPlaybackDiagnosticSurfaceEvent = nil
        cancellables.removeAll()
        observedPlayer = player
        guard let player else {
            record("videoDetail.player detached")
            return
        }

        player.onVideoDetailPlaybackDiagnosticSurfaceEvent = { [weak self] event in
            self?.receiveSurfaceEvent(event)
        }
        sampleIdentities(from: player)
        record(
            "videoDetail.playerObserved viewModel=\(identifier(ObjectIdentifier(player)))"
        )

        player.$isPlaying
            .removeDuplicates()
            .sink { [weak self, weak player] isPlaying in
                guard let self, let player else { return }
                self.sampleIdentities(from: player)
                if isPlaying {
                    self.markFirstPlaybackIfNeeded()
                }
                self.record(
                    "videoDetail.playbackState isPlaying=\(isPlaying) viewModel=\(self.identifier(player.debugPlayerIdentity))"
                )
            }
            .store(in: &cancellables)

        player.$playbackPhase
            .removeDuplicates()
            .sink { [weak self, weak player] phase in
                guard let self, let player else { return }
                self.sampleIdentities(from: player)
                self.record(
                    "videoDetail.playbackPhase=\(String(describing: phase)) viewModel=\(self.identifier(player.debugPlayerIdentity))"
                )
            }
            .store(in: &cancellables)

        player.$isBuffering
            .removeDuplicates()
            .sink { [weak self, weak player] isBuffering in
                guard let self, let player else { return }
                self.sampleIdentities(from: player)
                self.record(
                    "videoDetail.buffering=\(isBuffering) viewModel=\(self.identifier(player.debugPlayerIdentity))"
                )
            }
            .store(in: &cancellables)

        player.$hasPresentedPlayback
            .removeDuplicates()
            .sink { [weak self, weak player] hasPresentedPlayback in
                guard let self, let player else { return }
                self.sampleIdentities(from: player)
                if hasPresentedPlayback {
                    self.markFirstFrameIfNeeded()
                }
                self.record(
                    "videoDetail.firstFramePresented=\(hasPresentedPlayback) viewModel=\(self.identifier(player.debugPlayerIdentity))"
                )
            }
            .store(in: &cancellables)

        player.$isCurrentPlaybackSurfaceReadyForDisplay
            .removeDuplicates()
            .sink { [weak self, weak player] isReady in
                guard let self, let player else { return }
                self.sampleIdentities(from: player)
                self.record(
                    "videoDetail.surfaceReady=\(isReady) viewModel=\(self.identifier(player.debugPlayerIdentity))"
                )
                if isReady {
                    self.finishBlackFrameProbeIfPossible(for: player)
                }
            }
            .store(in: &cancellables)

        if player.isPlaying {
            markFirstPlaybackIfNeeded()
        }
        if player.hasPresentedPlayback {
            markFirstFrameIfNeeded()
        }
    }

    func markRotationStarted(toLandscape: Bool) {
        rotationStartedAt = CACurrentMediaTime()
        blackFrameProbeTask?.cancel()
        blackFrameProbeTask = nil
        record(
            "videoDetail.rotationStart target=\(toLandscape ? "landscape" : "portrait") \(identitySummary)"
        )

        guard let player = observedPlayer else {
            record("videoDetail.blackFrameDuration=unavailable reason=noPlayer")
            return
        }
        guard let hasUsableVideoFrame = player.debugHasUsableVideoFrame else {
            record("videoDetail.blackFrameDuration=unavailable reason=noFrameSnapshot \(identitySummary)")
            return
        }
        guard !hasUsableVideoFrame else {
            record("videoDetail.blackFrameDuration=notObserved \(identitySummary)")
            return
        }
        let startedAt = CACurrentMediaTime()
        blackFrameProbeTask = Task { @MainActor [weak self, weak player] in
            for _ in 0..<180 {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: 16_000_000)
                guard let self, let player, !Task.isCancelled else { return }
                if player.debugHasUsableVideoFrame == true {
                    self.record(
                        "videoDetail.blackFrameDuration=\(self.milliseconds(CACurrentMediaTime() - startedAt)) \(self.identitySummary)"
                    )
                    self.blackFrameProbeTask = nil
                    return
                }
            }
            guard let self, !Task.isCancelled else { return }
            self.record("videoDetail.blackFrameDuration=unresolved \(self.identitySummary)")
            self.blackFrameProbeTask = nil
        }
    }

    func markRotationFinished(toLandscape: Bool) {
        guard let startedAt = rotationStartedAt else {
            record(
                "videoDetail.rotationFinished target=\(toLandscape ? "landscape" : "portrait") duration=unavailable"
            )
            return
        }
        record(
            "videoDetail.rotationFinished target=\(toLandscape ? "landscape" : "portrait") duration=\(milliseconds(CACurrentMediaTime() - startedAt)) \(identitySummary)"
        )
        rotationStartedAt = nil
    }

    func markRotationRecovered(reason: String) {
        guard rotationStartedAt != nil else {
            record("videoDetail.rotationRecovered reason=\(reason) duration=unavailable")
            return
        }
        record(
            "videoDetail.rotationRecovered reason=\(reason) duration=\(milliseconds(CACurrentMediaTime() - (rotationStartedAt ?? CACurrentMediaTime()))) \(identitySummary)"
        )
        rotationStartedAt = nil
    }

    func markPageDisappeared() {
        guard !hasLoggedPageSummary else { return }
        hasLoggedPageSummary = true
        blackFrameProbeTask?.cancel()
        blackFrameProbeTask = nil
        observedPlayer?.onVideoDetailPlaybackDiagnosticSurfaceEvent = nil
        record(
            "videoDetail.end firstPlayback=\(elapsed(from: pageStartedAt, to: firstPlaybackAt)) firstFrame=\(elapsed(from: pageStartedAt, to: firstFrameAt)) \(identitySummary)"
        )
        cancellables.removeAll()
    }

    private func receiveSurfaceEvent(_ event: VideoDetailPlaybackDiagnosticSurfaceEvent) {
        switch event {
        case let .attached(surfaceID, playerID, playerItemID):
            record(
                "videoDetail.surfaceAttach surface=\(identifier(surfaceID)) player=\(identifier(playerID)) item=\(identifier(playerItemID))"
            )
        case let .detached(surfaceID, playerID, playerItemID):
            record(
                "videoDetail.surfaceDetach surface=\(identifier(surfaceID)) player=\(identifier(playerID)) item=\(identifier(playerItemID))"
            )
        }
    }

    private func sampleIdentities(from player: PlayerStateViewModel?) {
        guard let player else { return }
        let playerID = player.debugAVPlayerIdentity
        let playerItemID = player.debugAVPlayerItemIdentity
        guard playerID != lastPlayerID || playerItemID != lastPlayerItemID else { return }
        lastPlayerID = playerID
        lastPlayerItemID = playerItemID
        record(
            "videoDetail.identity viewModel=\(identifier(player.debugPlayerIdentity)) player=\(identifier(playerID)) item=\(identifier(playerItemID))"
        )
    }

    private func markFirstPlaybackIfNeeded() {
        guard firstPlaybackAt == nil else { return }
        firstPlaybackAt = CACurrentMediaTime()
        record(
            "videoDetail.firstPlaybackLatency=\(elapsed(from: pageStartedAt, to: firstPlaybackAt)) \(identitySummary)"
        )
    }

    private func markFirstFrameIfNeeded() {
        guard firstFrameAt == nil else { return }
        firstFrameAt = CACurrentMediaTime()
        record(
            "videoDetail.firstFrameLatency=\(elapsed(from: pageStartedAt, to: firstFrameAt)) \(identitySummary)"
        )
    }

    private func finishBlackFrameProbeIfPossible(for player: PlayerStateViewModel) {
        guard player.debugHasUsableVideoFrame == true else { return }
        blackFrameProbeTask?.cancel()
        blackFrameProbeTask = nil
    }

    private var identitySummary: String {
        "player=\(identifier(lastPlayerID)) item=\(identifier(lastPlayerItemID))"
    }

    private func record(_ message: String) {
        PlayerMetricsLog.diagnostic(message)
    }

    private func identifier(_ identifier: ObjectIdentifier?) -> String {
        identifier.map { String(describing: $0) } ?? "nil"
    }

    private func milliseconds(_ duration: CFTimeInterval) -> String {
        String(format: "%.1fms", max(duration, 0) * 1000)
    }

    private func elapsed(from start: CFTimeInterval?, to end: CFTimeInterval?) -> String {
        guard let start, let end else { return "unavailable" }
        return milliseconds(end - start)
    }
}
#else
@MainActor
final class VideoDetailPlaybackDiagnostics {
    func begin(metricsID _: String, title _: String?) {}
    func observe(player _: PlayerStateViewModel?) {}
    func markRotationStarted(toLandscape _: Bool) {}
    func markRotationFinished(toLandscape _: Bool) {}
    func markRotationRecovered(reason _: String) {}
    func markPageDisappeared() {}
}
#endif
