import AVFoundation
import AVKit
import Combine
import UIKit

@MainActor
final class UITestPlayerFixtureController: ObservableObject {
    let engine: UITestPlayerRenderingEngine
    let player: PlayerStateViewModel
    @Published private(set) var didSuspendForNavigation = false

    init() {
        let engine = UITestPlayerRenderingEngine()
        self.engine = engine
        self.player = PlayerStateViewModel(
            videoURL: URL(string: "https://ui-test.invalid/video.mp4"),
            audioURL: nil,
            title: "UI Test Player",
            referer: "https://ui-test.invalid",
            durationHint: 120,
            startupResumePolicy: .immediate,
            engine: engine
        )
        engine.onNavigationSuspended = { [weak self] in
            self?.didSuspendForNavigation = true
        }
    }

    func simulateFailure() {
        engine.simulateFailure()
    }

    func retry() {
        player.play()
    }
}

@MainActor
final class UITestPlayerRenderingEngine: PlayerRenderingEngine {
    var onNavigationSuspended: (() -> Void)?
    private(set) var hasMedia = true
    private(set) var isPlaying = false
    private(set) var playbackErrorMessage: String?
    var needsMediaRecovery: Bool { false }
    var lastFailureReason: HLSBridgeFailureReason? { nil }
    var supportsPictureInPicture: Bool { false }
    var isPictureInPictureActive: Bool { false }
    var usesNativePlaybackControls: Bool { false }
    var diagnostics: PlayerEngineDiagnostics { .empty }
    var presentationSize: CGSize { CGSize(width: 1920, height: 1080) }
    private(set) var volume: Float = 1
    private(set) var isMuted = false
    var onPlaybackStateChange: (@MainActor (PlayerEnginePlaybackState) -> Void)?
    var onPlaybackIntentChange: (@MainActor (Bool) -> Void)?
    var onLoadingProgressChange: (@MainActor (Double) -> Void)?
    var onFirstFrame: (@MainActor (TimeInterval) -> Void)?

    func attachSurface(_: UIView) {}
    func detachSurface(_: UIView) {}
    func refreshSurfaceLayout() {}
    func recoverSurface() {}
    func setViewModel(_: PlayerStateViewModel?) {}
    func setVideoGravity(_: AVLayerVideoGravity) {}
    func attachNativePlaybackController(_: AVPlayerViewController) {}
    func detachNativePlaybackController(_: AVPlayerViewController) {}

    func prepare(source _: PlayerStreamSource) async throws {
        hasMedia = true
        onPlaybackStateChange?(.ready)
    }

    func play() {
        isPlaying = true
        playbackErrorMessage = nil
        onPlaybackIntentChange?(true)
        onPlaybackStateChange?(.playing)
        onFirstFrame?(0)
    }

    func pause() {
        isPlaying = false
        onPlaybackIntentChange?(false)
        onPlaybackStateChange?(.paused)
    }

    func pauseForNavigation() {
        onNavigationSuspended?()
        pause()
    }

    func stop() {
        isPlaying = false
        onPlaybackIntentChange?(false)
        onPlaybackStateChange?(.idle)
    }

    func setPlaybackRate(_: Double) {}
    func setPreferredPeakBitRate(_: Double?) {}
    func setVolume(_ volume: Float) { self.volume = volume }
    func setMuted(_ isMuted: Bool) { self.isMuted = isMuted }
    func seek(toTime time: TimeInterval) -> TimeInterval? { time }
    func seekToLiveEdge() -> TimeInterval? { nil }
    func seek(toProgress progress: Double, duration: TimeInterval?) -> TimeInterval? {
        guard let duration else { return nil }
        return progress * duration
    }
    func seek(by interval: TimeInterval, from currentTime: TimeInterval, duration: TimeInterval?) -> TimeInterval? {
        min(max(currentTime + interval, 0), duration ?? .greatestFiniteMagnitude)
    }
    func seekAfterUserScrub(toProgress progress: Double, duration: TimeInterval?) async -> TimeInterval? {
        seek(toProgress: progress, duration: duration)
    }
    func snapshot(durationHint: TimeInterval?) -> PlayerPlaybackSnapshot {
        PlayerPlaybackSnapshot(
            currentTime: 0,
            duration: durationHint,
            isPlaying: isPlaying,
            isSeekable: true,
            bufferedRanges: []
        )
    }
    func pictureInPictureContentSource() -> AVPictureInPictureController.ContentSource? { nil }
    func togglePictureInPicture() {}
    func invalidatePictureInPicturePlaybackState() {}

    func simulateFailure() {
        isPlaying = false
        let message = "UI Test Playback Failed"
        playbackErrorMessage = message
        onPlaybackIntentChange?(false)
        onPlaybackStateChange?(.failed(message))
    }
}
