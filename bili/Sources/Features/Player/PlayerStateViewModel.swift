import AVFoundation
import AVKit
import Combine
import OSLog
import UIKit

@MainActor
enum PlayerStartupResumePolicy {
    case deferred
    case immediate
}

private enum PlaybackRecoveryWatchdogReason: Sendable {
    case firstFrame
    case stall

    var delay: UInt64 {
        switch self {
        case .firstFrame:
            return 1_700_000_000
        case .stall:
            return 3_200_000_000
        }
    }

    var logTitle: String {
        switch self {
        case .firstFrame:
            return "first-frame"
        case .stall:
            return "stall"
        }
    }
}

private struct NavigationAudioSuspension {
    let volume: Float
    let isMuted: Bool
    let resumeTime: TimeInterval
    let shouldResumePlayback: Bool
}

@MainActor
final class PlayerPlaybackClock: ObservableObject {
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval?

    var progress: Double {
        guard let duration, duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    func update(time: TimeInterval? = nil, duration: TimeInterval? = nil, force: Bool = false) {
        let nextTime = max(time ?? currentTime, 0)
        let nextDuration = duration
        let durationChanged: Bool
        if let currentDuration = self.duration, let nextDuration {
            durationChanged = abs(currentDuration - nextDuration) >= 0.5
        } else {
            durationChanged = self.duration != nil || nextDuration != nil
        }

        if force || durationChanged {
            self.duration = nextDuration
        }
        if force || abs(currentTime - nextTime) >= 0.2 || (currentTime <= 0 && nextTime > 0) {
            currentTime = nextTime
        }
    }

    func reset() {
        currentTime = 0
        duration = nil
    }
}

@MainActor
final class PlayerStateViewModel: NSObject, ObservableObject {
    let title: String
    var onPlaybackFailure: ((String?) -> Void)?
    var onBufferingPressure: ((Int) -> Void)?
    var onFirstFramePresented: (@MainActor () -> Void)?

    private(set) var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval?
    @Published var isPlaying = false
    @Published var isSeekable = false
    @Published var playbackRate: BiliPlaybackRate = .x10
    @Published var isPreparing = true
    @Published var isBuffering = false
    @Published var errorMessage: String?
    @Published var isPictureInPictureActive = false
    @Published var volume: Float = 1
    @Published var isMuted = false
    @Published private(set) var loadingProgress = 0.08
    @Published private(set) var hasPresentedPlayback = false
    @Published private(set) var isPlaybackSurfaceReady = false
    @Published private(set) var activeSponsorBlockSegment: SponsorBlockSegment?
    @Published private(set) var prepareElapsedMilliseconds: Int?
    @Published private(set) var firstFrameElapsedMilliseconds: Int?
    @Published private(set) var bufferingCount = 0
    @Published private(set) var lastBufferingElapsedMilliseconds: Int?
    @Published private(set) var playbackPhase: PlayerPlaybackPhase = .idle
    @Published private(set) var recoveryAttemptCount = 0
    @Published private(set) var engineDiagnostics: PlayerEngineDiagnostics = .empty
    @Published private(set) var isUserSeeking = false
    private(set) var lastUserSeekAt: Date?

    let playbackClock = PlayerPlaybackClock()

    private(set) var wantsAutoplay = true
    private let metricsID: String
    private let metricsStartTime = CACurrentMediaTime()
    private let streamSource: PlayerStreamSource
    private let durationHint: TimeInterval?
    private let resumeTime: TimeInterval
    private let startupResumePolicy: PlayerStartupResumePolicy
    private var engine: PlayerRenderingEngine
    private weak var surfaceView: VideoSurfaceContainerView?
    private weak var nativePlaybackController: AVPlayerViewController?
    private var prefersNativePlaybackControls = true
    private var timeObserver: Timer?
    private var didApplyResumeTime = false
    private var mediaPreparationTask: Task<Void, Never>?
    private var mediaPreparationGeneration = 0
    private var startupMediaWarmupTask: Task<Void, Never>?
    private var scrubSeekTask: Task<Void, Never>?
    private var scrubSeekGeneration = 0
    private var startupResumeRetryTask: Task<Void, Never>?
    private var resumeRecoveryWatchdogTask: Task<Void, Never>?
    private var deferredBufferingIndicatorTask: Task<Void, Never>?
    private var scrubSeekUIReleaseTask: Task<Void, Never>?
    private var playbackRecoveryWatchdogTask: Task<Void, Never>?
    private var seekRecoveryWatchdogTask: Task<Void, Never>?
    private var speedBoostRecoveryTask: Task<Void, Never>?
    private var pictureInPictureController: AVPictureInPictureController?
    private var didConfigurePictureInPicture = false
    private var sponsorBlockSegments: [SponsorBlockSegment] = []
    private var sponsorBlockSearchIndex = 0
    private var skippedSponsorBlockIDs = Set<String>()
    private var sponsorBlockReportedIDs = Set<String>()
    private var ignoredStartupPlaybackTimeOutliers = 0
    private var didRecordFirstFrameEvent = false
    private var forcedPlaybackTimeGuard: ForcedPlaybackTimeGuard?
    private var pendingStartupResume: PendingStartupResume?
    private var pendingResumeRecoveryMetric: PendingStartupResumeRecoveryMetric?
    private var pendingSeekRecoveryMetric: PendingSeekRecoveryMetric?
    private var lastSeekBufferReadyMetricID: UUID?
    private var navigationAudioSuspension: NavigationAudioSuspension?
    private var sponsorBlockEnabled = false
    private var onSponsorBlockSegmentSkipped: (@Sendable (SponsorBlockSkipEvent) async -> Void)?
    private var hostFullscreenRequestHandler: (() -> Void)?
    private(set) var isTerminated = false
    private var isStopping = false
    private var lastBufferingPressureNotificationCount = 0
    private var lastPeriodicEngineDiagnosticsSyncTime: CFTimeInterval = 0
    private var playbackStateRefreshInterval: TimeInterval = 1.0
    private let sponsorBlockPrerollTolerance: TimeInterval = 0.35
    private let sponsorBlockTailTolerance: TimeInterval = 0.12
    private let forcedPlaybackTimeGuardDuration: TimeInterval = 3.5
    private let forcedPlaybackTimeGuardTolerance: TimeInterval = 2.0
    private let maximumPlaybackRecoveryAttempts = 2
    private let deferredBufferingIndicatorDelayNanoseconds: UInt64 = 750_000_000
    private let seekCoalescingDelayNanoseconds: UInt64 = 90_000_000
    private let seekUIReleaseDelayNanoseconds: UInt64 = 1_150_000_000
    private let resumeRecoveryWatchdogDelayNanoseconds: UInt64 = 2_400_000_000
    private let seekRecoveryWatchdogDelayNanoseconds: UInt64 = 2_400_000_000

    init(
        videoURL: URL?,
        audioURL: URL?,
        videoStream: DASHStream? = nil,
        audioStream: DASHStream? = nil,
        alternateVideoRenditions: [PlayerVideoRenditionSource] = [],
        title: String,
        referer: String,
        durationHint: TimeInterval? = nil,
        resumeTime: TimeInterval = 0,
        startupResumePolicy: PlayerStartupResumePolicy = .deferred,
        dynamicRange: BiliVideoDynamicRange = .sdr,
        cdnPreference: PlaybackCDNPreference = .automatic,
        metricsID: String? = nil,
        engine: PlayerRenderingEngine? = nil
    ) {
        let resolvedMetricsID = metricsID?.isEmpty == false ? metricsID! : UUID().uuidString
        self.title = title
        self.metricsID = resolvedMetricsID
        self.streamSource = PlayerStreamSource(
            metricsID: resolvedMetricsID,
            videoURL: videoURL,
            audioURL: audioURL,
            videoStream: videoStream,
            audioStream: audioStream,
            alternateVideoRenditions: alternateVideoRenditions,
            referer: referer,
            httpHeaders: BiliHLSManifestBuilder.httpHeaders(referer: referer),
            title: title,
            durationHint: durationHint,
            resumeTime: resumeTime,
            dynamicRange: dynamicRange,
            cdnPreference: cdnPreference
        )
        self.durationHint = durationHint
        self.duration = durationHint
        self.playbackClock.update(time: 0, duration: durationHint, force: true)
        self.resumeTime = resumeTime
        self.startupResumePolicy = startupResumePolicy
        self.engine = engine ?? DefaultPlayerRenderingEngine.make()
        super.init()
        bindEngine(self.engine, restoreVolumeState: false)
        PlayerMetricsLog.logger.info(
            "created id=\(self.metricsID, privacy: .public) title=\(PlayerMetricsLog.shortTitle(title), privacy: .public) hasAudio=\((audioURL != nil), privacy: .public) resume=\(resumeTime, privacy: .public)"
        )
        PlayerMetricsLog.record(.playerCreated, metricsID: self.metricsID, title: title)
        ActivePlaybackCoordinator.shared.register(self)
        rescheduleTimeObserverIfNeeded(force: true)
    }

    deinit {
        mediaPreparationTask?.cancel()
        startupMediaWarmupTask?.cancel()
        scrubSeekTask?.cancel()
        startupResumeRetryTask?.cancel()
        resumeRecoveryWatchdogTask?.cancel()
        playbackRecoveryWatchdogTask?.cancel()
        seekRecoveryWatchdogTask?.cancel()
        speedBoostRecoveryTask?.cancel()
        scrubSeekUIReleaseTask?.cancel()
        onPlaybackFailure = nil
        onFirstFramePresented = nil
        timeObserver?.invalidate()
        let engine = engine
        Task { @MainActor in
            engine.onPlaybackStateChange = nil
            engine.onPlaybackIntentChange = nil
            engine.onLoadingProgressChange = nil
            engine.onFirstFrame = nil
            engine.setViewModel(nil)
            engine.stop()
        }
    }

    var canSeek: Bool {
        isSeekable || (duration ?? durationHint ?? 0) > 0
    }

    var isPictureInPictureSupported: Bool {
        engine.supportsPictureInPicture
            || (AVPictureInPictureController.isPictureInPictureSupported()
                && (pictureInPictureController != nil || engine.pictureInPictureContentSource() != nil))
    }

    var usesNativePlaybackControls: Bool {
        engine.usesNativePlaybackControls
    }

    var displayDuration: TimeInterval? {
        duration ?? durationHint
    }

    var currentProgress: Double {
        playbackClock.progress
    }

    func makePlaybackTransitionSnapshotView() -> UIView? {
        if let image = engine.currentVideoFrameImage() {
            let imageView = UIImageView(image: image)
            imageView.backgroundColor = .black
            imageView.contentMode = .scaleAspectFit
            imageView.clipsToBounds = true
            imageView.isOpaque = true
            imageView.frame = surfaceView?.bounds ?? CGRect(origin: .zero, size: image.size)
            return imageView
        }
        return surfaceView?.makePlaybackTransitionSnapshotView()
    }

    func attachSurface(_ view: VideoSurfaceContainerView, prefersNativePlaybackControls: Bool = true) {
        self.prefersNativePlaybackControls = prefersNativePlaybackControls
        if ManualVideoFullscreenSession.isActive,
           let currentSurface = surfaceView,
           currentSurface !== view,
           currentSurface.isInManualFullscreen,
           !view.isInManualFullscreen {
            return
        }

        let isNewSurface = surfaceView !== view
        let usesNativePlaybackControls = engine.usesNativePlaybackControls && prefersNativePlaybackControls
        let shouldAttachDirectSurface = !usesNativePlaybackControls && nativePlaybackController != nil
        surfaceView = view
        view.setNativePlaybackControllerEnabled(usesNativePlaybackControls)
        if usesNativePlaybackControls {
            nativePlaybackController = view.nativePlayerViewController
            engine.attachNativePlaybackController(view.nativePlayerViewController)
        } else {
            if let nativePlaybackController {
                engine.detachNativePlaybackController(nativePlaybackController)
                self.nativePlaybackController = nil
            }
            engine.detachNativePlaybackController(view.nativePlayerViewController)
        }
        if isNewSurface || shouldAttachDirectSurface {
            engine.attachSurface(view.drawableView)
        }
        configurePictureInPictureIfNeeded()
        if (isNewSurface || shouldAttachDirectSurface), engine.hasMedia {
            engine.refreshSurfaceLayout()
        }
    }

    func attachNativePlaybackController(_ controller: AVPlayerViewController) {
        nativePlaybackController = controller
        engine.attachNativePlaybackController(controller)
        configurePictureInPictureIfNeeded()
        if engine.hasMedia {
            engine.refreshSurfaceLayout()
        }
    }

    func detachNativePlaybackController(_ controller: AVPlayerViewController) {
        engine.detachNativePlaybackController(controller)
        if nativePlaybackController === controller {
            nativePlaybackController = nil
        }
    }

    func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        engine.setVideoGravity(gravity)
        engine.refreshSurfaceLayout()
    }

    func detachSurface(_ view: VideoSurfaceContainerView) {
        guard surfaceView === view else { return }
        engine.detachNativePlaybackController(view.nativePlayerViewController)
        engine.detachSurface(view.drawableView)
        view.setNativePlaybackControllerEnabled(false)
        surfaceView = nil
    }

    func refreshSurfaceLayout() {
        guard surfaceView != nil else { return }
        engine.refreshSurfaceLayout()
    }

    @discardableResult
    func enterManualFullscreen(
        mode: ManualVideoFullscreenMode,
        onExit: (() -> Void)?,
        animated: Bool
    ) -> Bool {
        guard let surfaceView else {
            PlayerMetricsLog.logger.error("manualFullscreenEnterFailed reason=noSurface")
            return false
        }
        surfaceView.setManualFullscreenMode(mode, onExit: onExit, animated: animated)
        let didEnter = surfaceView.isInManualFullscreen
        PlayerMetricsLog.logger.info("manualFullscreenEnterRequested didEnter=\(didEnter, privacy: .public)")
        return didEnter
    }

    func playbackSnapshot() -> PlayerPlaybackSnapshot {
        engine.snapshot(durationHint: duration ?? durationHint)
    }

    func preferVideoRenditionInCurrentItem(_ variant: PlayVariant) -> Bool {
        guard streamSource.audioURL == variant.audioURL,
              let videoURL = variant.videoURL,
              currentHLSVideoRenditionURLs.contains(videoURL),
              let bandwidth = variant.videoStream?.bandwidth ?? variant.bandwidth,
              bandwidth > 0
        else { return false }
        let multiplier = PlaybackEnvironment.current.shouldPreferConservativePlayback ? 0.96 : 1.08
        engine.setPreferredPeakBitRate(Double(bandwidth) * multiplier)
        PlayerMetricsLog.record(
            .qualitySupplement,
            metricsID: metricsID,
            title: title,
            message: "manualInPlace q\(variant.quality) peak=\(Int((Double(bandwidth) * multiplier).rounded()))"
        )
        return true
    }

    private var currentHLSVideoRenditionURLs: Set<URL> {
        var urls = Set<URL>()
        if let videoURL = streamSource.videoURL {
            urls.insert(videoURL)
        }
        streamSource.alternateVideoRenditions.forEach { urls.insert($0.videoURL) }
        return urls
    }

    func setHostFullscreenActive(_ isActive: Bool, exitTarget: PlayerHostFullscreenExitTarget? = nil) {
        engine.setHostFullscreenActive(isActive, exitTarget: exitTarget)
        engine.refreshSurfaceLayout()
    }

    func recoverSurfaceAfterHostFullscreenTransition() {
        guard surfaceView != nil else { return }
        engine.refreshSurfaceLayout()
        schedulePlaybackRecoveryWatchdog(reason: hasPresentedPlayback ? .stall : .firstFrame)
    }

    func setHostFullscreenRequestHandler(_ handler: (() -> Void)?) {
        hostFullscreenRequestHandler = handler
    }

    @discardableResult
    func requestHostFullscreen() -> Bool {
        guard let hostFullscreenRequestHandler else { return false }
        hostFullscreenRequestHandler()
        return true
    }

    func recoverPlaybackAfterAppResume() {
        guard !isTerminated else { return }
        guard ActivePlaybackCoordinator.shared.isActive(self) else { return }
        if timeObserver == nil {
            startTimeObserver()
        }
        engine.recoverSurface()
        refreshSurfaceLayout()
        configurePictureInPictureIfNeeded()
        invalidatePictureInPicturePlaybackState()
        schedulePlaybackRecoveryWatchdog(reason: hasPresentedPlayback ? .stall : .firstFrame)

        guard errorMessage == nil else { return }
        if engine.needsMediaRecovery {
            rebuildMediaAfterPlaybackInterruption()
            return
        }
        guard engine.hasMedia else {
            if wantsAutoplay {
                prepareMediaAndPlay()
            }
            return
        }
        if wantsAutoplay {
            startPreparedPlayback()
        } else {
            refreshPlaybackState()
        }
    }

    private func schedulePlaybackRecoveryWatchdog(reason: PlaybackRecoveryWatchdogReason) {
        guard !isTerminated,
              wantsAutoplay,
              engine.hasMedia,
              errorMessage == nil,
              ActivePlaybackCoordinator.shared.isActive(self)
        else { return }
        guard reason == .stall || !hasPresentedPlayback else { return }

        playbackRecoveryWatchdogTask?.cancel()
        let baselineTime = currentTime
        let baselineAttempt = recoveryAttemptCount
        playbackRecoveryWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: reason.delay)
            guard let self,
                  !Task.isCancelled,
                  !self.isTerminated,
                  self.wantsAutoplay,
                  self.engine.hasMedia,
                  self.errorMessage == nil,
                  ActivePlaybackCoordinator.shared.isActive(self)
            else { return }

            switch reason {
            case .firstFrame:
                guard !self.hasPresentedPlayback else { return }
            case .stall:
                guard self.isBuffering || self.playbackPhase == .recovering else { return }
                let snapshotTime = self.engine.snapshot(durationHint: self.durationHint).currentTime ?? self.currentTime
                guard abs(snapshotTime - baselineTime) < 0.25 else { return }
            }

            guard self.recoveryAttemptCount == baselineAttempt else { return }
            self.performPlaybackRecovery(reason: reason, baselineTime: baselineTime)
        }
    }

    private func performPlaybackRecovery(reason: PlaybackRecoveryWatchdogReason, baselineTime: TimeInterval) {
        guard recoveryAttemptCount < maximumPlaybackRecoveryAttempts else {
            playbackRecoveryWatchdogTask = nil
            return
        }

        recoveryAttemptCount += 1
        playbackPhase = .recovering
        isPreparing = false
        isBuffering = true
        PlayerMetricsLog.logger.info(
            "playbackRecovery id=\(self.metricsID, privacy: .public) reason=\(reason.logTitle, privacy: .public) attempt=\(self.recoveryAttemptCount, privacy: .public) baseline=\(baselineTime, format: .fixed(precision: 2), privacy: .public)"
        )
        PlayerMetricsLog.record(
            .mediaPrepared,
            metricsID: metricsID,
            title: title,
            message: "recovery \(reason.logTitle) attempt=\(recoveryAttemptCount)"
        )

        engine.recoverSurface()
        refreshSurfaceLayout()
        configurePictureInPictureIfNeeded()
        engine.play()
        engine.setPlaybackRate(playbackRate.rawValue)

        schedulePlaybackRecoveryWatchdog(reason: reason)
    }

    private func acceptFirstFramePresentationFallback(
        currentTime playbackTime: TimeInterval?,
        source: String
    ) -> Bool {
        guard !isTerminated,
              !hasPresentedPlayback,
              !isPlaybackSurfaceReady,
              engine.hasMedia,
              errorMessage == nil
        else { return false }

        let resolvedTime = max(playbackTime ?? currentTime, 0)
        if resolvedTime > 0 {
            _ = updatePlaybackTime(resolvedTime, force: currentTime <= 0, countsAsNaturalPlayback: false)
        }
        markPlaybackSurfaceReady()
        recordFirstFrameIfNeeded(currentTime: resolvedTime, source: source)
        return true
    }

    private func scheduleDeferredBufferingIndicator() {
        guard deferredBufferingIndicatorTask == nil else { return }
        let baselineTime = currentTime
        let baselineAttempt = recoveryAttemptCount
        deferredBufferingIndicatorTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.deferredBufferingIndicatorDelayNanoseconds)
            guard !Task.isCancelled,
                  !self.isTerminated,
                  self.hasPresentedPlayback,
                  self.wantsAutoplay,
                  self.engine.hasMedia,
                  self.recoveryAttemptCount == baselineAttempt
            else {
                self.deferredBufferingIndicatorTask = nil
                return
            }

            let snapshot = self.engine.snapshot(durationHint: self.durationHint)
            if let snapshotTime = snapshot.currentTime,
               snapshotTime > baselineTime + 0.18 {
                _ = self.updatePlaybackTime(snapshotTime)
                self.playbackPhase = snapshot.isPlaying ? .playing : self.playbackPhase
                self.deferredBufferingIndicatorTask = nil
                return
            }

            if !self.isBuffering {
                self.bufferingCount += 1
                self.lastBufferingElapsedMilliseconds = self.elapsedMilliseconds()
                self.notifyBufferingPressureIfNeeded()
            }
            self.isPreparing = false
            self.isBuffering = true
            self.playbackPhase = .buffering
            PlayerMetricsLog.record(.buffering, metricsID: self.metricsID, title: self.title, message: self.elapsedMessage())
            self.schedulePlaybackRecoveryWatchdog(reason: .stall)
            self.deferredBufferingIndicatorTask = nil
        }
    }

    private func cancelDeferredBufferingIndicator() {
        deferredBufferingIndicatorTask?.cancel()
        deferredBufferingIndicatorTask = nil
    }

    private func clearMediaPreparationTaskIfCurrent(_ generation: Int) {
        guard generation == mediaPreparationGeneration else { return }
        mediaPreparationTask = nil
    }

    private func rebuildMediaAfterPlaybackInterruption() {
        guard !isTerminated else { return }
        guard mediaPreparationTask == nil else { return }
        let restoreTime = currentTime
        isPreparing = false
        mediaPreparationGeneration &+= 1
        let preparationGeneration = mediaPreparationGeneration
        mediaPreparationTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try await self.engine.prepare(source: self.streamSourceForPreparation())
                guard !Task.isCancelled,
                      !self.isTerminated,
                      preparationGeneration == self.mediaPreparationGeneration
                else {
                    self.clearMediaPreparationTaskIfCurrent(preparationGeneration)
                    return
                }
                self.clearMediaPreparationTaskIfCurrent(preparationGeneration)
                if restoreTime > 0, let time = self.engine.seek(toTime: restoreTime) {
                    self.updatePlaybackTime(time, force: true, countsAsNaturalPlayback: false)
                }
                if self.wantsAutoplay {
                    self.startPreparedPlayback()
                } else {
                    self.refreshPlaybackState()
                }
            } catch {
                guard !Task.isCancelled,
                      !self.isTerminated,
                      preparationGeneration == self.mediaPreparationGeneration
                else {
                    self.clearMediaPreparationTaskIfCurrent(preparationGeneration)
                    return
                }
                self.clearMediaPreparationTaskIfCurrent(preparationGeneration)
                self.errorMessage = error.localizedDescription
                self.isPreparing = false
            }
        }
    }

    func play() {
        guard !isTerminated else { return }
        restoreAudioAfterCancelledNavigation()
        ActivePlaybackCoordinator.shared.activate(self)
        wantsAutoplay = true
        errorMessage = nil
        guard streamSource.videoURL != nil else {
            errorMessage = PlayerEngineError.missingVideoURL.localizedDescription
            isPreparing = false
            return
        }

        if !engine.hasMedia {
            prepareMediaAndPlay()
            return
        }

        startPreparedPlayback()
    }

    func resumePlaybackAfterUserSeek() {
        guard !isTerminated else { return }
        wantsAutoplay = true
        errorMessage = nil
        guard engine.hasMedia else {
            play()
            return
        }
        resumePreparedPlaybackAfterSeek()
    }

    @discardableResult
    func applyStartupResumeTime(_ time: TimeInterval, reason: String) -> Bool {
        guard !isTerminated, time > 0.25 else { return false }
        PlayerMetricsLog.signpostEvent(
            "PlayerStartupResume",
            message: "request reason=\(reason) target=\(String(format: "%.2f", time))"
        )
        cancelStartupResumeRecoveryTracking()
        pendingStartupResume = PendingStartupResume(time: time, reason: reason)
        didApplyResumeTime = true
        startupResumeRetryTask?.cancel()
        startupResumeRetryTask = nil
        let didApply = applyPendingStartupResumeIfPossible()
        if !didApply {
            schedulePendingStartupResumeRetry()
        }
        PlayerMetricsLog.record(
            .resumeDecision,
            metricsID: metricsID,
            title: title,
            message: "player \(didApply ? "applied" : "queued") reason=\(reason) target=\(String(format: "%.2fs", time))"
        )
        return didApply
    }

    private func schedulePendingStartupResumeRetry() {
        startupResumeRetryTask?.cancel()
        startupResumeRetryTask = Task { @MainActor [weak self] in
            let retryDelays: [UInt64] = [
                90_000_000,
                180_000_000,
                320_000_000,
                520_000_000,
                850_000_000,
                1_300_000_000
            ]
            for delay in retryDelays {
                try? await Task.sleep(nanoseconds: delay)
                guard let self,
                      !Task.isCancelled,
                      !self.isTerminated,
                      ActivePlaybackCoordinator.shared.isActive(self)
                else { return }
                if self.applyPendingStartupResumeIfPossible() {
                    self.startupResumeRetryTask = nil
                    return
                }
            }
            self?.startupResumeRetryTask = nil
        }
    }

    func pause() {
        guard !isTerminated else { return }
        wantsAutoplay = false
        cancelDeferredBufferingIndicator()
        cancelStartupResumeRecoveryTracking()
        cancelSeekRecoveryTracking()
        playbackRecoveryWatchdogTask?.cancel()
        playbackRecoveryWatchdogTask = nil
        engine.pause()
        isPlaying = false
        isBuffering = false
        playbackPhase = .paused
        invalidatePictureInPicturePlaybackState()
        rescheduleTimeObserverIfNeeded()
    }

    func pauseForNavigation() {
        guard !isTerminated else { return }
        silenceAudioForNavigationIfNeeded()
        mediaPreparationTask?.cancel()
        mediaPreparationTask = nil
        mediaPreparationGeneration &+= 1
        wantsAutoplay = false
        cancelDeferredBufferingIndicator()
        cancelStartupResumeRecoveryTracking()
        cancelSeekRecoveryTracking()
        playbackRecoveryWatchdogTask?.cancel()
        playbackRecoveryWatchdogTask = nil
        engine.suspendForNavigation()
        isPlaying = false
        isBuffering = false
        playbackPhase = .paused
        invalidatePictureInPicturePlaybackState()
        rescheduleTimeObserverIfNeeded()
    }

    func prepareForVisualPlaybackTransition() {
        guard !isTerminated else { return }
        silenceAudioForNavigationIfNeeded()
        ActivePlaybackCoordinator.shared.deactivate(self)
        wantsAutoplay = false
        cancelDeferredBufferingIndicator()
        cancelStartupResumeRecoveryTracking()
        cancelSeekRecoveryTracking()
        playbackRecoveryWatchdogTask?.cancel()
        playbackRecoveryWatchdogTask = nil
        isPreparing = false
        isBuffering = false
        if engine.hasMedia {
            let snapshot = engine.snapshot(durationHint: durationHint)
            isPlaying = snapshot.isPlaying
            playbackPhase = snapshot.isPlaying ? .playing : .paused
        } else {
            isPlaying = false
            playbackPhase = .idle
        }
        invalidatePictureInPicturePlaybackState()
        rescheduleTimeObserverIfNeeded()
    }

    func restoreAudioAfterCancelledNavigation() {
        guard !isTerminated, let navigationAudioSuspension else { return }
        self.navigationAudioSuspension = nil
        engine.setVolume(navigationAudioSuspension.volume)
        engine.setMuted(navigationAudioSuspension.isMuted)
        if navigationAudioSuspension.resumeTime > 0.25 {
            applyStartupResumeTime(navigationAudioSuspension.resumeTime, reason: "cancelledNavigation")
        }
        if navigationAudioSuspension.shouldResumePlayback {
            wantsAutoplay = true
            if engine.hasMedia {
                resumePreparedPlaybackAfterSeek()
            }
        }
    }

    func setPlaybackIntent(_ shouldAutoplay: Bool) {
        guard !isTerminated else { return }
        wantsAutoplay = shouldAutoplay
        if !shouldAutoplay {
            cancelDeferredBufferingIndicator()
            cancelStartupResumeRecoveryTracking()
            cancelSeekRecoveryTracking()
            playbackRecoveryWatchdogTask?.cancel()
            playbackRecoveryWatchdogTask = nil
            isPlaying = false
            isBuffering = false
            playbackPhase = engine.hasMedia ? .paused : .idle
            rescheduleTimeObserverIfNeeded()
        }
    }

    func suspendForNavigation() {
        guard !isTerminated else { return }
        mediaPreparationTask?.cancel()
        mediaPreparationTask = nil
        startupMediaWarmupTask?.cancel()
        startupMediaWarmupTask = nil
        pauseForNavigation()
    }

    func stop(reason: PlayerStopReason = .navigation) {
        guard !isStopping else { return }
        if isTerminated {
            ActivePlaybackCoordinator.shared.deactivate(self)
            return
        }
        isStopping = true
        isTerminated = true
        mediaPreparationGeneration &+= 1
        cancelDeferredBufferingIndicator()
        mediaPreparationTask?.cancel()
        mediaPreparationTask = nil
        startupMediaWarmupTask?.cancel()
        startupMediaWarmupTask = nil
        scrubSeekTask?.cancel()
        scrubSeekTask = nil
        isUserSeeking = false
        cancelStartupResumeRecoveryTracking()
        cancelSeekRecoveryTracking()
        startupResumeRetryTask?.cancel()
        startupResumeRetryTask = nil
        playbackRecoveryWatchdogTask?.cancel()
        playbackRecoveryWatchdogTask = nil
        navigationAudioSuspension = nil
        timeObserver?.invalidate()
        timeObserver = nil
        wantsAutoplay = false
        onPlaybackFailure = nil
        onBufferingPressure = nil
        onFirstFramePresented = nil
        engine.onPlaybackStateChange = nil
        engine.onPlaybackIntentChange = nil
        engine.onLoadingProgressChange = nil
        engine.onFirstFrame = nil
        engine.setViewModel(nil)
        engine.stop()
        ActivePlaybackCoordinator.shared.unregister(self)
        isPlaying = false
        isPreparing = false
        isBuffering = false
        errorMessage = nil
        loadingProgress = 0
        hasPresentedPlayback = false
        isPlaybackSurfaceReady = false
        currentTime = 0
        playbackClock.reset()
        playbackPhase = .idle
        recoveryAttemptCount = 0
        lastBufferingPressureNotificationCount = 0
        forcedPlaybackTimeGuard = nil
        lastSeekBufferReadyMetricID = nil
        didRecordFirstFrameEvent = false
        invalidatePictureInPicturePlaybackState()
        isStopping = false
    }

    @discardableResult
    func togglePlayback() -> Bool {
        guard !isTerminated else { return false }
        let snapshot = engine.snapshot(durationHint: durationHint)
        let shouldPause = wantsAutoplay
            || isPlaying
            || (snapshot.isPlaying && playbackPhase != .paused)
        if shouldPause {
            pause()
            return false
        } else {
            play()
            return wantsAutoplay && errorMessage == nil
        }
    }

    func seek(to progress: Double) {
        guard !isTerminated else { return }
        guard engine.hasMedia else { return }
        markUserSeekIntent()
        let signpostState = PlayerMetricsLog.beginSignpostedInterval(
            "PlayerSeek",
            message: "mode=tap target=\(String(format: "%.3f", progress))"
        )
        let userSeekStart = CACurrentMediaTime()
        var signpostMessage = "mode=tap pending"
        defer {
            PlayerMetricsLog.endSignpostedInterval(
                "PlayerSeek",
                signpostState,
                message: signpostMessage
            )
        }
        if let time = engine.seek(toProgress: progress, duration: duration) {
            updatePlaybackTime(time, force: true, countsAsNaturalPlayback: false)
            beginSeekRecoveryTracking(
                reason: "tap",
                targetTime: time,
                targetProgress: progress,
                startedAt: userSeekStart,
                engineElapsedMilliseconds: nil
            )
            recordSeekTransition(
                reason: "tap",
                targetTime: time,
                targetProgress: progress,
                totalElapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: userSeekStart),
                engineElapsedMilliseconds: nil
            )
            signpostMessage = "mode=tap target=\(String(format: "%.3f", progress)) applied=\(String(format: "%.2f", time))"
        } else {
            signpostMessage = "mode=tap target=\(String(format: "%.3f", progress)) skipped"
        }
        invalidatePictureInPicturePlaybackState()
    }

    func seekAfterUserScrub(to progress: Double) {
        guard !isTerminated else { return }
        guard engine.hasMedia else { return }
        markUserSeekIntent()
        wantsAutoplay = true
        cancelStartupResumeCorrectionAfterUserSeek()
        scrubSeekGeneration &+= 1
        let generation = scrubSeekGeneration
        let targetProgress = min(max(progress, 0), 1)
        let userSeekStart = CACurrentMediaTime()
        let resolvedDuration = duration ?? durationHint ?? playbackClock.duration ?? engine.snapshot(durationHint: durationHint).duration ?? 0
        let optimisticTargetTime = resolvedDuration > 0 ? targetProgress * resolvedDuration : nil
        let signpostState = PlayerMetricsLog.beginSignpostedInterval(
            "PlayerSeek",
            message: "mode=scrub target=\(String(format: "%.3f", targetProgress))"
        )
        var signpostMessage = "mode=scrub waiting"
        isUserSeeking = true
        isBuffering = true
        loadingProgress = hasPresentedPlayback ? 0.22 : max(loadingProgress, 0.78)
        playbackPhase = .seeking
        if let optimisticTargetTime {
            _ = updatePlaybackTime(optimisticTargetTime, force: true, countsAsNaturalPlayback: false)
            beginSeekRecoveryTracking(
                reason: "scrub-optimistic",
                targetTime: optimisticTargetTime,
                targetProgress: targetProgress,
                startedAt: userSeekStart,
                engineElapsedMilliseconds: nil
            )
        }
        scheduleScrubSeekUIReleaseIfNeeded(
            generation: generation,
            targetTime: optimisticTargetTime,
            targetProgress: targetProgress,
            startedAt: userSeekStart
        )
        rescheduleTimeObserverIfNeeded(force: true)
        scrubSeekTask?.cancel()
        scrubSeekTask = Task(priority: .userInitiated) { @MainActor [weak self] in
            guard let self else {
                PlayerMetricsLog.endSignpostedInterval(
                    "PlayerSeek",
                    signpostState,
                    message: "mode=scrub cancelled"
                )
                return
            }
            defer {
                if self.scrubSeekGeneration == generation {
                    self.scrubSeekTask = nil
                    self.isUserSeeking = false
                    self.rescheduleTimeObserverIfNeeded(force: true)
                }
                PlayerMetricsLog.endSignpostedInterval(
                    "PlayerSeek",
                    signpostState,
                    message: signpostMessage
                )
            }
            try? await Task.sleep(nanoseconds: self.seekCoalescingDelayNanoseconds)
            guard !Task.isCancelled,
                  !self.isTerminated,
                  self.scrubSeekGeneration == generation
            else {
                signpostMessage = "mode=scrub cancelled"
                return
            }
            let engineSeekStart = CACurrentMediaTime()
            let time = await self.engine.seekAfterUserScrub(
                toProgress: targetProgress,
                duration: resolvedDuration > 0 ? resolvedDuration : self.duration
            )
            let totalElapsed = PlayerMetricsLog.elapsedMilliseconds(since: userSeekStart)
            let engineElapsed = PlayerMetricsLog.elapsedMilliseconds(since: engineSeekStart)
            guard !Task.isCancelled,
                  !self.isTerminated,
                  self.scrubSeekGeneration == generation
            else {
                signpostMessage = "mode=scrub cancelled"
                return
            }
            if let time {
                self.updatePlaybackTime(time, force: true, countsAsNaturalPlayback: false)
                self.beginSeekRecoveryTracking(
                    reason: "scrub",
                    targetTime: time,
                    targetProgress: targetProgress,
                    startedAt: userSeekStart,
                    engineElapsedMilliseconds: engineElapsed
                )
            }
            self.recordSeekTransition(
                reason: "scrub",
                targetTime: time,
                targetProgress: targetProgress,
                totalElapsedMilliseconds: totalElapsed,
                engineElapsedMilliseconds: engineElapsed
            )
            signpostMessage = "mode=scrub target=\(String(format: "%.3f", targetProgress)) applied=\(String(format: "%.2f", time ?? 0)) total=\(String(format: "%.1f", totalElapsed))ms engine=\(String(format: "%.1f", engineElapsed))ms"
            self.resumePlaybackAfterUserSeek()
        }
    }

    func seek(by interval: TimeInterval) {
        guard !isTerminated else { return }
        guard engine.hasMedia else { return }
        markUserSeekIntent()
        let signpostState = PlayerMetricsLog.beginSignpostedInterval(
            "PlayerSeek",
            message: "mode=step delta=\(String(format: "%.2f", interval))"
        )
        let userSeekStart = CACurrentMediaTime()
        var signpostMessage = "mode=step pending"
        defer {
            PlayerMetricsLog.endSignpostedInterval(
                "PlayerSeek",
                signpostState,
                message: signpostMessage
            )
        }
        if let time = engine.seek(by: interval, from: currentTime, duration: duration ?? durationHint) {
            updatePlaybackTime(time, force: true, countsAsNaturalPlayback: false)
            let reason = interval < 0 ? "step-back" : "step-forward"
            beginSeekRecoveryTracking(
                reason: reason,
                targetTime: time,
                targetProgress: nil,
                startedAt: userSeekStart,
                engineElapsedMilliseconds: nil
            )
            recordSeekTransition(
                reason: reason,
                targetTime: time,
                targetProgress: nil,
                totalElapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: userSeekStart),
                engineElapsedMilliseconds: nil
            )
            signpostMessage = "mode=step delta=\(String(format: "%.2f", interval)) applied=\(String(format: "%.2f", time))"
        } else {
            signpostMessage = "mode=step delta=\(String(format: "%.2f", interval)) skipped"
        }
        invalidatePictureInPicturePlaybackState()
    }

    func setPlaybackRate(_ rate: BiliPlaybackRate) {
        guard playbackRate != rate else { return }
        speedBoostRecoveryTask?.cancel()
        speedBoostRecoveryTask = nil
        playbackRate = rate
        engine.setPlaybackRate(rate.rawValue)
        rescheduleTimeObserverIfNeeded()
        invalidatePictureInPicturePlaybackState()
    }

    func recordSpeedBoostMetric(_ message: String) {
        PlayerMetricsLog.signpostEvent("PlayerSpeedBoost", message: message)
        PlayerMetricsLog.record(
            .speedBoost,
            metricsID: metricsID,
            title: title,
            message: message
        )
    }

    func stabilizePlaybackAfterSpeedBoost(restoredRate: BiliPlaybackRate, reason: String) {
        speedBoostRecoveryTask?.cancel()
        let initialSnapshot = engine.snapshot(durationHint: durationHint)
        let shouldKeepPlaying = wantsAutoplay
            || isPlaying
            || initialSnapshot.isPlaying
        recordSpeedBoostMetric("stabilize reason=\(reason) restore=\(restoredRate.title) keepPlaying=\(shouldKeepPlaying)")
        if shouldKeepPlaying, !initialSnapshot.isPlaying {
            engine.play()
        }
        engine.setPlaybackRate(restoredRate.rawValue)
        rescheduleTimeObserverIfNeeded(force: true)

        speedBoostRecoveryTask = Task { @MainActor [weak self] in
            let delays: [UInt64] = [180_000_000, 460_000_000]
            for delay in delays {
                try? await Task.sleep(nanoseconds: delay)
                guard let self,
                      !Task.isCancelled,
                      !self.isTerminated,
                      self.playbackRate == restoredRate,
                      ActivePlaybackCoordinator.shared.isActive(self)
                else { return }

                let snapshot = self.engine.snapshot(durationHint: self.durationHint)
                let shouldResume = self.wantsAutoplay || self.isPlaying || snapshot.isPlaying
                if shouldResume, !snapshot.isPlaying {
                    self.engine.play()
                }
                self.engine.setPlaybackRate(restoredRate.rawValue)
                if let snapshotTime = snapshot.currentTime {
                    _ = self.updatePlaybackTime(snapshotTime)
                }
            }
            self?.speedBoostRecoveryTask = nil
        }
    }

    func setVolume(_ value: Float) {
        let normalizedVolume = min(max(value, 0), 1)
        volume = normalizedVolume
        engine.setVolume(normalizedVolume)
        if normalizedVolume > 0, isMuted {
            isMuted = false
            engine.setMuted(false)
        }
        invalidatePictureInPicturePlaybackState()
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        engine.setMuted(muted)
        invalidatePictureInPicturePlaybackState()
    }

    private func silenceAudioForNavigationIfNeeded() {
        if navigationAudioSuspension == nil {
            let snapshot = engine.snapshot(durationHint: durationHint)
            let resumeTime = max(snapshot.currentTime ?? 0, currentTime)
            navigationAudioSuspension = NavigationAudioSuspension(
                volume: engine.volume,
                isMuted: engine.isMuted,
                resumeTime: resumeTime.isFinite ? max(resumeTime, 0) : 0,
                shouldResumePlayback: wantsAutoplay || isPlaying || snapshot.isPlaying
            )
        }
        engine.setTemporaryAudioSuppressed(true)
    }

    func setSponsorBlockSegments(
        _ segments: [SponsorBlockSegment],
        isEnabled: Bool,
        onSegmentSkipped: (@Sendable (SponsorBlockSkipEvent) async -> Void)? = nil
    ) {
        sponsorBlockSegments = segments
            .filter(\.isSkippable)
            .sorted { $0.startTime < $1.startTime }
        sponsorBlockEnabled = isEnabled
        self.onSponsorBlockSegmentSkipped = onSegmentSkipped
        skippedSponsorBlockIDs.removeAll()
        sponsorBlockReportedIDs.removeAll()
        sponsorBlockSearchIndex = 0
        activeSponsorBlockSegment = nil
    }

    func setSponsorBlockEnabled(_ isEnabled: Bool) {
        sponsorBlockEnabled = isEnabled
        if !isEnabled {
            activeSponsorBlockSegment = nil
        }
    }

    func togglePictureInPicture() {
        configurePictureInPictureIfNeeded()
        if pictureInPictureController == nil, engine.supportsPictureInPicture {
            engine.togglePictureInPicture()
            isPictureInPictureActive = engine.isPictureInPictureActive
            return
        }
        guard let pictureInPictureController else { return }
        if pictureInPictureController.isPictureInPictureActive {
            pictureInPictureController.stopPictureInPicture()
        } else {
            if pictureInPictureController.isPictureInPicturePossible {
                pictureInPictureController.startPictureInPicture()
            } else {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    guard let self else { return }
                    if self.pictureInPictureController?.isPictureInPicturePossible == true {
                        self.pictureInPictureController?.startPictureInPicture()
                    }
                }
            }
        }
    }

    private func prepareMediaAndPlay() {
        guard !isTerminated else { return }
        guard mediaPreparationTask == nil else { return }
        isPreparing = true
        loadingProgress = max(loadingProgress, 0.12)
        playbackPhase = .preparing
        recoveryAttemptCount = 0
        PlayerMetricsLog.logger.info(
            "prepareRequested id=\(self.metricsID, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: self.metricsStartTime), format: .fixed(precision: 1), privacy: .public)"
        )
        PlayerMetricsLog.record(.prepareRequested, metricsID: metricsID, title: title, message: elapsedMessage())
        mediaPreparationGeneration &+= 1
        let preparationGeneration = mediaPreparationGeneration
        let preparationSource = streamSourceForPreparation()
        startStartupMediaWarmup(for: preparationSource)
        mediaPreparationTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let signpostState = PlayerMetricsLog.beginSignpostedInterval(
                "PlayerPrepare",
                message: "id=\(self.metricsID) media=\(self.engine.hasMedia)"
            )
            var signpostMessage = "id=\(self.metricsID) preparing"
            defer {
                PlayerMetricsLog.endSignpostedInterval(
                    "PlayerPrepare",
                    signpostState,
                    message: signpostMessage
                )
            }
            do {
                try await self.engine.prepare(source: preparationSource)
                guard !Task.isCancelled,
                      !self.isTerminated,
                      preparationGeneration == self.mediaPreparationGeneration
                else {
                    self.clearMediaPreparationTaskIfCurrent(preparationGeneration)
                    return
                }
                PlayerMetricsLog.logger.info(
                    "prepareReturned id=\(self.metricsID, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: self.metricsStartTime), format: .fixed(precision: 1), privacy: .public)"
                )
                PlayerMetricsLog.record(.prepareReturned, metricsID: self.metricsID, title: self.title, message: self.elapsedMessage())
                self.prepareElapsedMilliseconds = self.elapsedMilliseconds()
                self.clearMediaPreparationTaskIfCurrent(preparationGeneration)
                self.loadingProgress = max(self.loadingProgress, 0.72)
                let didApplyPendingResume = self.applyPendingStartupResumeIfPossible()
                if didApplyPendingResume {
                    // A cloud/local resume arrived while the engine was preparing.
                } else if self.startupResumePolicy == .immediate {
                    self.applyImmediateResumeTimeIfNeeded()
                }
                if self.wantsAutoplay {
                    if !didApplyPendingResume {
                        self.startPreparedPlayback()
                    }
                } else {
                    self.isPreparing = false
                    self.refreshPlaybackState()
                }
                signpostMessage = "id=\(self.metricsID) success elapsed=\(self.elapsedMessage())"
            } catch {
                guard !Task.isCancelled,
                      !self.isTerminated,
                      preparationGeneration == self.mediaPreparationGeneration
                else {
                    self.clearMediaPreparationTaskIfCurrent(preparationGeneration)
                    return
                }
                PlayerMetricsLog.logger.error(
                    "prepareFailed id=\(self.metricsID, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: self.metricsStartTime), format: .fixed(precision: 1), privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                PlayerMetricsLog.record(.failed, metricsID: self.metricsID, title: self.title, message: "\(self.elapsedMessage()) \(error.localizedDescription)")
                self.prepareElapsedMilliseconds = self.elapsedMilliseconds()
                self.clearMediaPreparationTaskIfCurrent(preparationGeneration)
                self.errorMessage = error.localizedDescription
                self.isPreparing = false
                signpostMessage = "id=\(self.metricsID) failed \(error.localizedDescription)"
            }
        }
    }

    private func startStartupMediaWarmup(for source: PlayerStreamSource) {
        startupMediaWarmupTask?.cancel()
        startupMediaWarmupTask = nil
        let playbackTime = source.resumeTime > 0.25 ? source.resumeTime : nil
        guard let videoURL = source.videoURL,
              let audioURL = source.audioURL,
              let videoStream = source.videoStream,
              let audioStream = source.audioStream,
              videoStream.segmentBase?.indexByteRange != nil,
              audioStream.segmentBase?.indexByteRange != nil
        else { return }

        let videoTracks = [
            HLSBridgeTrack(
                url: videoURL,
                fallbackURLs: videoStream.backupPlayURLs(cdnPreference: source.cdnPreference),
                stream: videoStream,
                mediaType: .video,
                dynamicRange: source.dynamicRange
            )
        ]
        let audioTrack = HLSBridgeTrack(
            url: audioURL,
            fallbackURLs: audioStream.backupPlayURLs(cdnPreference: source.cdnPreference),
            stream: audioStream,
            mediaType: .audio
        )
        let headers = source.httpHeaders
        let metricsID = source.metricsID
        let title = source.title
        let targetDescription = playbackTime.map { String(format: "%.2fs", $0) } ?? "startup"
        PlayerMetricsLog.record(
            .manifestStage,
            metricsID: metricsID,
            title: title,
            message: "prepareWarm=queued target=\(targetDescription) video=\(videoTracks.count)"
        )

        startupMediaWarmupTask = Task.detached(priority: .utility) { [videoTracks, audioTrack, headers, metricsID, title, playbackTime] in
            let start = CACurrentMediaTime()
            let didWarm = await LocalHLSBridge.warmup(
                videoTracks: videoTracks,
                audioTrack: audioTrack,
                headers: headers,
                around: playbackTime
            )
            guard !Task.isCancelled else { return }
            let elapsed = PlayerMetricsLog.elapsedMilliseconds(since: start)
            await PlayerMetricsLog.record(
                .manifestStage,
                metricsID: metricsID,
                title: title,
                message: "prepareWarm=\(didWarm ? "ok" : "skip") target=\(targetDescription) elapsed=\(String(format: "%.0fms", elapsed))"
            )
        }
    }

    private func streamSourceForPreparation() -> PlayerStreamSource {
        let pendingResumeTime = pendingStartupResume?.time ?? 0
        let currentResumeTime = currentTime.isFinite ? max(currentTime, 0) : 0
        let resumeTarget: TimeInterval
        if currentResumeTime > 0.25 {
            resumeTarget = currentResumeTime
        } else if pendingResumeTime > 0.25 {
            resumeTarget = pendingResumeTime
        } else {
            resumeTarget = streamSource.resumeTime
        }
        guard resumeTarget.isFinite, resumeTarget > 0.25 else { return streamSource }
        return streamSource.withResumeTime(resumeTarget)
    }

    private func startPreparedPlayback() {
        guard !isTerminated else { return }
        guard engine.hasMedia else { return }
        guard ActivePlaybackCoordinator.shared.isActive(self) else { return }
        wantsAutoplay = true
        isPreparing = false
        isBuffering = !hasPresentedPlayback
        playbackPhase = hasPresentedPlayback ? .playing : .waitingForFirstFrame
        loadingProgress = max(loadingProgress, 0.78)
        isPlaying = true
        PlayerMetricsLog.signpostEvent(
            "PlayerPlayback",
            message: "id=\(metricsID) start hasPresented=\(hasPresentedPlayback)"
        )
        PlayerMetricsLog.logger.info(
            "playRequested id=\(self.metricsID, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: self.metricsStartTime), format: .fixed(precision: 1), privacy: .public)"
        )
        PlayerMetricsLog.record(.playRequested, metricsID: metricsID, title: title, message: elapsedMessage())
        engine.play()
        engine.setPlaybackRate(playbackRate.rawValue)
        if startupResumePolicy == .deferred {
            applyResumeTimeIfNeeded()
        } else {
            scheduleImmediateResumeCorrectionIfNeeded()
        }
        refreshPlaybackState()
        invalidatePictureInPicturePlaybackState()
        schedulePlaybackRecoveryWatchdog(reason: hasPresentedPlayback ? .stall : .firstFrame)
    }

    @discardableResult
    private func applyPendingStartupResumeIfPossible() -> Bool {
        guard let pendingResume = pendingStartupResume, engine.hasMedia else { return false }
        let signpostState = PlayerMetricsLog.beginSignpostedInterval(
            "PlayerStartupResume",
            message: "reason=\(pendingResume.reason) target=\(String(format: "%.2f", pendingResume.time))"
        )
        var signpostMessage = "reason=\(pendingResume.reason) pending"
        defer {
            PlayerMetricsLog.endSignpostedInterval(
                "PlayerStartupResume",
                signpostState,
                message: signpostMessage
            )
        }
        let snapshot = engine.snapshot(durationHint: durationHint)
        let currentPlaybackTime = max(snapshot.currentTime ?? 0, currentTime)
        guard pendingResume.time > currentPlaybackTime + forcedPlaybackTimeGuardTolerance
                || currentPlaybackTime <= forcedPlaybackTimeGuardTolerance
        else {
            PlayerMetricsLog.record(
                .resumeDecision,
                metricsID: metricsID,
                title: title,
                message: "player skipped reason=\(pendingResume.reason) target=\(String(format: "%.2fs", pendingResume.time)) current=\(String(format: "%.2fs", currentPlaybackTime))"
            )
            self.pendingStartupResume = nil
            signpostMessage = "reason=\(pendingResume.reason) skipped current=\(String(format: "%.2f", currentPlaybackTime))"
            return false
        }
        let seekStart = CACurrentMediaTime()
        guard let time = engine.seek(toTime: pendingResume.time) else {
            signpostMessage = "reason=\(pendingResume.reason) failed no-seek"
            return false
        }
        let seekElapsed = PlayerMetricsLog.elapsedMilliseconds(since: seekStart)
        self.pendingStartupResume = nil
        updatePlaybackTime(time, force: true, countsAsNaturalPlayback: false)
        beginStartupResumeRecoveryTracking(
            reason: pendingResume.reason,
            targetTime: pendingResume.time,
            appliedTime: time,
            startedAt: seekStart,
            engineElapsedMilliseconds: seekElapsed
        )
        PlayerMetricsLog.logger.info(
            "startupResumeSeek id=\(self.metricsID, privacy: .public) reason=\(pendingResume.reason, privacy: .public) target=\(pendingResume.time, format: .fixed(precision: 2), privacy: .public) applied=\(time, format: .fixed(precision: 2), privacy: .public) engineMs=\(seekElapsed, format: .fixed(precision: 1), privacy: .public)"
        )
        PlayerMetricsLog.record(
            .resumeDecision,
            metricsID: metricsID,
            title: title,
            message: "player applied reason=\(pendingResume.reason) target=\(String(format: "%.2fs", pendingResume.time)) applied=\(String(format: "%.2fs", time)) engine=\(String(format: "%.0fms", seekElapsed))"
        )
        signpostMessage = "reason=\(pendingResume.reason) applied=\(String(format: "%.2f", time)) engine=\(String(format: "%.1f", seekElapsed))ms"
        if wantsAutoplay {
            resumePreparedPlaybackAfterSeek()
        } else {
            refreshPlaybackState()
            invalidatePictureInPicturePlaybackState()
        }
        return true
    }

    private func resumePreparedPlaybackAfterSeek() {
        guard !isTerminated else { return }
        guard engine.hasMedia else { return }
        guard ActivePlaybackCoordinator.shared.isActive(self) else { return }
        wantsAutoplay = true
        isPreparing = false
        isPlaying = true
        if hasPresentedPlayback {
            playbackPhase = isBuffering ? .buffering : .playing
        } else {
            isBuffering = true
            loadingProgress = max(loadingProgress, 0.78)
            playbackPhase = .waitingForFirstFrame
        }
        engine.play()
        engine.setPlaybackRate(playbackRate.rawValue)
        refreshPlaybackState()
        invalidatePictureInPicturePlaybackState()
        if !hasPresentedPlayback {
            schedulePlaybackRecoveryWatchdog(reason: .firstFrame)
        } else if isBuffering {
            schedulePlaybackRecoveryWatchdog(reason: .stall)
        }
    }

    private func cancelStartupResumeCorrectionAfterUserSeek() {
        startupResumeRetryTask?.cancel()
        startupResumeRetryTask = nil
        cancelStartupResumeRecoveryTracking()
        if resumeTime > 0.25 {
            didApplyResumeTime = true
        }
    }

    private func beginStartupResumeRecoveryTracking(
        reason: String,
        targetTime: TimeInterval,
        appliedTime: TimeInterval,
        startedAt: CFTimeInterval,
        engineElapsedMilliseconds: Double?
    ) {
        guard targetTime > 0.25 else { return }
        cancelStartupResumeRecoveryTracking()
        let metric = PendingStartupResumeRecoveryMetric(
            reason: reason,
            targetTime: targetTime,
            appliedTime: appliedTime,
            startedAt: startedAt,
            engineElapsedMilliseconds: engineElapsedMilliseconds
        )
        pendingResumeRecoveryMetric = metric
        resumeRecoveryWatchdogTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.resumeRecoveryWatchdogDelayNanoseconds)
            guard !Task.isCancelled,
                  !self.isTerminated,
                  let pending = self.pendingResumeRecoveryMetric,
                  pending.id == metric.id
            else { return }
            let snapshot = self.engine.snapshot(durationHint: self.durationHint)
            if let snapshotTime = snapshot.currentTime,
               (snapshot.isPlaying || self.hasPresentedPlayback),
               self.isStartupResumeRecoveryMatch(currentTime: snapshotTime, pending: pending) {
                self.finishStartupResumeRecoveryMetric(
                    pending,
                    recovered: true,
                    currentTime: snapshotTime,
                    source: "watchdog"
                )
                return
            }
            self.finishStartupResumeRecoveryMetric(
                pending,
                recovered: false,
                currentTime: snapshot.currentTime ?? self.currentTime,
                source: "watchdog"
            )
        }
    }

    private func recordStartupResumeRecoveryIfNeeded(currentTime: TimeInterval, source: String) {
        guard let pending = pendingResumeRecoveryMetric else { return }
        guard isStartupResumeRecoveryMatch(currentTime: currentTime, pending: pending) else { return }
        finishStartupResumeRecoveryMetric(
            pending,
            recovered: true,
            currentTime: currentTime,
            source: source
        )
    }

    private func finishStartupResumeRecoveryMetric(
        _ pending: PendingStartupResumeRecoveryMetric,
        recovered: Bool,
        currentTime: TimeInterval,
        source: String
    ) {
        guard pendingResumeRecoveryMetric?.id == pending.id else { return }
        resumeRecoveryWatchdogTask?.cancel()
        resumeRecoveryWatchdogTask = nil
        pendingResumeRecoveryMetric = nil
        PlayerMetricsLog.record(
            .resumeRecovery,
            metricsID: metricsID,
            title: title,
            message: startupResumeRecoveryMessage(
                reason: pending.reason,
                targetTime: pending.targetTime,
                appliedTime: pending.appliedTime,
                elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: pending.startedAt),
                engineElapsedMilliseconds: pending.engineElapsedMilliseconds,
                currentTime: currentTime,
                recovered: recovered,
                source: source
            )
        )
    }

    private func startupResumeRecoveryMessage(
        reason: String,
        targetTime: TimeInterval,
        appliedTime: TimeInterval,
        elapsedMilliseconds: Double,
        engineElapsedMilliseconds: Double?,
        currentTime: TimeInterval,
        recovered: Bool,
        source: String
    ) -> String {
        var parts = [reason, "recovered=\(recovered)"]
        parts.append("target=\(String(format: "%.2fs", targetTime))")
        parts.append("applied=\(String(format: "%.2fs", appliedTime))")
        parts.append("current=\(String(format: "%.2fs", currentTime))")
        parts.append("total=\(String(format: "%.0fms", elapsedMilliseconds))")
        if let engineElapsedMilliseconds {
            parts.append("engine=\(String(format: "%.0fms", engineElapsedMilliseconds))")
        }
        parts.append("source=\(source)")
        return parts.joined(separator: " ")
    }

    private func isStartupResumeRecoveryMatch(currentTime: TimeInterval, pending: PendingStartupResumeRecoveryMetric) -> Bool {
        let targetTime = pending.targetTime
        let toleranceBefore = max(0.9, min(targetTime * 0.03, 1.8))
        let toleranceAfter = max(4.0, min(targetTime * 0.12, 10.0))
        return currentTime >= max(targetTime - toleranceBefore, 0)
            && currentTime <= targetTime + toleranceAfter
    }

    private func cancelStartupResumeRecoveryTracking() {
        resumeRecoveryWatchdogTask?.cancel()
        resumeRecoveryWatchdogTask = nil
        pendingResumeRecoveryMetric = nil
    }

    private func bindEngine(_ engine: PlayerRenderingEngine, restoreVolumeState: Bool) {
        if restoreVolumeState {
            engine.setVolume(volume)
            engine.setMuted(isMuted)
            engine.setPlaybackRate(playbackRate.rawValue)
        } else {
            volume = engine.volume
            isMuted = engine.isMuted
        }
        engine.onPlaybackStateChange = { [weak self] state in
            self?.handleEnginePlaybackState(state)
        }
        engine.onPlaybackIntentChange = { [weak self] wantsPlayback in
            self?.handleEnginePlaybackIntentChange(wantsPlayback)
        }
        engine.onLoadingProgressChange = { [weak self] progress in
            self?.handleEngineLoadingProgress(progress)
        }
        engine.onFirstFrame = { [weak self] currentTime in
            self?.handleEngineFirstFrame(currentTime)
        }
        engine.setViewModel(self)
        syncEngineDiagnostics(force: true)
    }

    private func startTimeObserver() {
        timeObserver?.invalidate()
        let timer = Timer(timeInterval: playbackStateRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPlaybackState()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        timeObserver = timer
    }

    private func rescheduleTimeObserverIfNeeded(force: Bool = false) {
        let desiredInterval = desiredPlaybackStateRefreshInterval()
        guard force || timeObserver == nil || abs(desiredInterval - playbackStateRefreshInterval) > 0.05 else { return }
        playbackStateRefreshInterval = desiredInterval
        startTimeObserver()
    }

    private func desiredPlaybackStateRefreshInterval() -> TimeInterval {
        if isPreparing || isBuffering || isUserSeeking || playbackPhase == .waitingForFirstFrame || playbackPhase == .recovering || playbackPhase == .seeking {
            return 0.35
        }
        if sponsorBlockEnabled, wantsAutoplay, engine.hasMedia {
            return 0.5
        }
        if wantsAutoplay || isPlaying {
            return playbackRate.rawValue > 1.15 ? 0.9 : 1.2
        }
        return 2.4
    }

    private func refreshPlaybackState() {
        guard !isTerminated else { return }
        guard ActivePlaybackCoordinator.shared.isActive(self) || !wantsAutoplay else { return }
        syncEngineDiagnosticsForPeriodicRefresh()
        if let playbackErrorMessage = engine.playbackErrorMessage {
            errorMessage = playbackErrorMessage
            isPreparing = false
            isPlaying = false
            wantsAutoplay = false
            playbackPhase = .failed(playbackErrorMessage)
            invalidatePictureInPicturePlaybackState()
            return
        }

        let snapshot = engine.snapshot(durationHint: durationHint)
        updateSeekBufferProgressIfNeeded(snapshot)
        var acceptedSnapshotTime: TimeInterval?
        if let snapshotTime = snapshot.currentTime,
           updatePlaybackTime(snapshotTime) {
            acceptedSnapshotTime = currentTime
            if isPreparing {
                isPreparing = false
            }
            if isBuffering, hasPresentedPlayback, snapshot.isPlaying {
                isBuffering = false
            }
        }
        if let snapshotDuration = snapshot.duration {
            updateDuration(snapshotDuration)
        }
        if wantsAutoplay, engine.hasMedia, !snapshot.isPlaying, errorMessage == nil {
            engine.play()
            engine.setPlaybackRate(playbackRate.rawValue)
            if !hasPresentedPlayback {
                isBuffering = true
            }
        }
        let shouldDisplayPlaying = snapshot.isPlaying || (wantsAutoplay && engine.hasMedia && errorMessage == nil)
        if isPlaying != shouldDisplayPlaying {
            isPlaying = shouldDisplayPlaying
        }
        updatePhaseFromSnapshot(snapshot)
        if isSeekable != snapshot.isSeekable {
            isSeekable = snapshot.isSeekable
        }
        syncPictureInPictureState()
        if let snapshotTime = acceptedSnapshotTime {
            skipSponsorBlockSegmentIfNeeded(at: snapshotTime)
        }
        rescheduleTimeObserverIfNeeded()
    }

    private func updatePhaseFromSnapshot(_ snapshot: PlayerPlaybackSnapshot) {
        guard errorMessage == nil else {
            playbackPhase = .failed(errorMessage)
            return
        }
        if isPreparing {
            playbackPhase = .preparing
        } else if playbackPhase == .recovering {
            if hasPresentedPlayback, snapshot.isPlaying {
                playbackPhase = .playing
            }
        } else if isBuffering {
            playbackPhase = hasPresentedPlayback ? .buffering : .waitingForFirstFrame
        } else if snapshot.isPlaying {
            playbackPhase = hasPresentedPlayback ? .playing : .waitingForFirstFrame
        } else if engine.hasMedia {
            playbackPhase = wantsAutoplay ? .ready : .paused
        } else {
            playbackPhase = .idle
        }
    }

    private func applyResumeTimeIfNeeded() {
        guard !didApplyResumeTime, resumeTime > 0.25 else { return }
        didApplyResumeTime = true
        let milliseconds = Int32(min(resumeTime * 1000, Double(Int32.max)))
        let signpostState = PlayerMetricsLog.beginSignpostedInterval(
            "PlayerStartupResume",
            message: "reason=deferredStartup target=\(String(format: "%.2f", resumeTime))"
        )
        Task { @MainActor [weak self] in
            guard let self else {
                PlayerMetricsLog.endSignpostedInterval(
                    "PlayerStartupResume",
                    signpostState,
                    message: "reason=deferredStartup cancelled"
                )
                return
            }
            var signpostMessage = "reason=deferredStartup waiting"
            defer {
                PlayerMetricsLog.endSignpostedInterval(
                    "PlayerStartupResume",
                    signpostState,
                    message: signpostMessage
                )
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !self.isTerminated,
                  ActivePlaybackCoordinator.shared.isActive(self)
            else {
                signpostMessage = "reason=deferredStartup cancelled"
                return
            }
            let seekStart = CACurrentMediaTime()
            if let time = self.engine.seek(toTime: TimeInterval(milliseconds) / 1000) {
                let seekElapsed = PlayerMetricsLog.elapsedMilliseconds(since: seekStart)
                self.updatePlaybackTime(time, force: true, countsAsNaturalPlayback: false)
                self.beginStartupResumeRecoveryTracking(
                    reason: "deferredStartup",
                    targetTime: self.resumeTime,
                    appliedTime: time,
                    startedAt: seekStart,
                    engineElapsedMilliseconds: seekElapsed
                )
                PlayerMetricsLog.record(
                    .resumeDecision,
                    metricsID: self.metricsID,
                    title: self.title,
                    message: "player applied reason=deferredStartup target=\(String(format: "%.2fs", self.resumeTime)) applied=\(String(format: "%.2fs", time)) engine=\(String(format: "%.0fms", seekElapsed))"
                )
                signpostMessage = "reason=deferredStartup applied=\(String(format: "%.2f", time)) engine=\(String(format: "%.1f", seekElapsed))ms"
            } else {
                signpostMessage = "reason=deferredStartup failed no-seek"
            }
            if self.wantsAutoplay {
                self.engine.play()
                self.engine.setPlaybackRate(self.playbackRate.rawValue)
            }
        }
    }

    private func applyImmediateResumeTimeIfNeeded() {
        guard !didApplyResumeTime, resumeTime > 0.25 else { return }
        didApplyResumeTime = true
        seekToStartupResumeTime(reason: "prepareReturned")
        scheduleImmediateResumeCorrectionIfNeeded()
    }

    private func scheduleImmediateResumeCorrectionIfNeeded() {
        guard startupResumePolicy == .immediate, resumeTime > 0.25 else { return }
        startupResumeRetryTask?.cancel()
        let targetTime = resumeTime
        startupResumeRetryTask = Task { @MainActor [weak self] in
            let retryDelays: [UInt64] = [
                90_000_000,
                180_000_000,
                320_000_000,
                520_000_000,
                850_000_000
            ]
            for delay in retryDelays {
                try? await Task.sleep(nanoseconds: delay)
                guard let self,
                      !Task.isCancelled,
                      !self.isTerminated,
                      ActivePlaybackCoordinator.shared.isActive(self)
                else { return }
                let snapshotTime = self.engine.snapshot(durationHint: self.durationHint).currentTime
                if let snapshotTime,
                   snapshotTime >= max(targetTime - 1.2, 0),
                   snapshotTime <= targetTime + 8 {
                    self.recordStartupResumeRecoveryIfNeeded(currentTime: snapshotTime, source: "retry")
                    PlayerMetricsLog.record(
                        .resumeDecision,
                        metricsID: self.metricsID,
                        title: self.title,
                        message: "player verified reason=retry target=\(String(format: "%.2fs", targetTime)) current=\(String(format: "%.2fs", snapshotTime))"
                    )
                    self.startupResumeRetryTask = nil
                    return
                }
                self.seekToStartupResumeTime(reason: "retry")
                if self.wantsAutoplay {
                    self.engine.play()
                    self.engine.setPlaybackRate(self.playbackRate.rawValue)
                }
            }
            self?.startupResumeRetryTask = nil
        }
    }

    @discardableResult
    private func seekToStartupResumeTime(reason: String) -> Bool {
        guard resumeTime > 0.25, engine.hasMedia else { return false }
        let signpostState = PlayerMetricsLog.beginSignpostedInterval(
            "PlayerStartupResume",
            message: "reason=\(reason) target=\(String(format: "%.2f", resumeTime))"
        )
        var signpostMessage = "reason=\(reason) pending"
        defer {
            PlayerMetricsLog.endSignpostedInterval(
                "PlayerStartupResume",
                signpostState,
                message: signpostMessage
            )
        }
        let seekStart = CACurrentMediaTime()
        guard let time = engine.seek(toTime: resumeTime) else {
            signpostMessage = "reason=\(reason) failed no-seek"
            return false
        }
        let seekElapsed = PlayerMetricsLog.elapsedMilliseconds(since: seekStart)
        updatePlaybackTime(time, force: true, countsAsNaturalPlayback: false)
        beginStartupResumeRecoveryTracking(
            reason: reason,
            targetTime: resumeTime,
            appliedTime: time,
            startedAt: seekStart,
            engineElapsedMilliseconds: seekElapsed
        )
        PlayerMetricsLog.logger.info(
            "startupResumeSeek id=\(self.metricsID, privacy: .public) reason=\(reason, privacy: .public) target=\(self.resumeTime, format: .fixed(precision: 2), privacy: .public) applied=\(time, format: .fixed(precision: 2), privacy: .public) engineMs=\(seekElapsed, format: .fixed(precision: 1), privacy: .public)"
        )
        PlayerMetricsLog.record(
            .resumeDecision,
            metricsID: metricsID,
            title: title,
            message: "player applied reason=\(reason) target=\(String(format: "%.2fs", resumeTime)) applied=\(String(format: "%.2fs", time)) engine=\(String(format: "%.0fms", seekElapsed))"
        )
        signpostMessage = "reason=\(reason) applied=\(String(format: "%.2f", time)) engine=\(String(format: "%.1f", seekElapsed))ms"
        return true
    }

    @discardableResult
    private func updatePlaybackTime(
        _ time: TimeInterval,
        force: Bool = false,
        countsAsNaturalPlayback: Bool = true
    ) -> Bool {
        let normalizedTime = max(time, 0)
        guard force || !shouldIgnoreStalePlaybackTimeAfterForcedSeek(normalizedTime) else {
            return false
        }
        guard force || !shouldIgnoreStartupPlaybackTimeOutlier(normalizedTime) else {
            return false
        }
        if countsAsNaturalPlayback, normalizedTime > 0 {
            cancelDeferredBufferingIndicator()
            if hasPresentedPlayback {
                isBuffering = false
                loadingProgress = 1
            }
            recordStartupResumeRecoveryIfNeeded(currentTime: normalizedTime, source: "playbackTime")
            recordSeekRecoveryIfNeeded(currentTime: normalizedTime, source: "playbackTime")
        }
        if force || (currentTime <= 0 && normalizedTime > 0) || abs(currentTime - normalizedTime) >= 0.2 {
            currentTime = normalizedTime
            playbackClock.update(time: normalizedTime, duration: displayDuration, force: force)
        } else if force {
            playbackClock.update(time: normalizedTime, duration: displayDuration, force: true)
        }
        if force {
            installForcedPlaybackTimeGuard(for: normalizedTime)
        } else {
            clearForcedPlaybackTimeGuardIfSatisfied(by: normalizedTime)
        }
        return true
    }

    private func handleEngineFirstFrame(_ time: TimeInterval) {
        guard !isTerminated else { return }
        syncEngineDiagnostics(force: true)
        markPlaybackSurfaceReady()
        recordFirstFrameIfNeeded(currentTime: time, source: "engine")
        recordStartupResumeRecoveryIfNeeded(currentTime: time, source: "engine")
        recordSeekRecoveryIfNeeded(currentTime: time, source: "engine")
        if time > 0 {
            _ = updatePlaybackTime(time, force: currentTime <= 0, countsAsNaturalPlayback: false)
        }
    }

    private func recordFirstFrameIfNeeded(currentTime: TimeInterval, source: String) {
        guard !didRecordFirstFrameEvent else { return }
        didRecordFirstFrameEvent = true
        let normalizedTime = max(currentTime, 0)
        PlayerMetricsLog.signpostEvent(
            "PlayerFirstFrame",
            message: "source=\(source) current=\(String(format: "%.2f", normalizedTime))"
        )
        PlayerMetricsLog.logger.info(
            "firstFrame id=\(self.metricsID, privacy: .public) source=\(source, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: self.metricsStartTime), format: .fixed(precision: 1), privacy: .public) current=\(normalizedTime, format: .fixed(precision: 2), privacy: .public)"
        )
        PlayerMetricsLog.record(
            .firstFrame,
            metricsID: metricsID,
            title: title,
            message: "\(elapsedMessage()) source=\(source) time=\(String(format: "%.2f", normalizedTime))s"
        )
        firstFrameElapsedMilliseconds = elapsedMilliseconds()
    }

    private func markPlaybackSurfaceReady() {
        let shouldNotifyFirstFrame = !hasPresentedPlayback
        cancelDeferredBufferingIndicator()
        playbackRecoveryWatchdogTask?.cancel()
        playbackRecoveryWatchdogTask = nil
        recoveryAttemptCount = 0
        isPlaybackSurfaceReady = true
        hasPresentedPlayback = true
        if shouldNotifyFirstFrame {
            onFirstFramePresented?()
        }
        loadingProgress = 1
        isPreparing = false
        isBuffering = false
        playbackPhase = .playing
    }

    private func installForcedPlaybackTimeGuard(for time: TimeInterval) {
        guard time > forcedPlaybackTimeGuardTolerance else {
            forcedPlaybackTimeGuard = nil
            return
        }
        forcedPlaybackTimeGuard = ForcedPlaybackTimeGuard(
            targetTime: time,
            expiresAt: CACurrentMediaTime() + forcedPlaybackTimeGuardDuration
        )
    }

    private func shouldIgnoreStalePlaybackTimeAfterForcedSeek(_ time: TimeInterval) -> Bool {
        guard let guardState = forcedPlaybackTimeGuard else { return false }
        guard CACurrentMediaTime() <= guardState.expiresAt else {
            forcedPlaybackTimeGuard = nil
            return false
        }
        if abs(time - guardState.targetTime) <= forcedPlaybackTimeGuardTolerance {
            forcedPlaybackTimeGuard = nil
            return false
        }
        guard abs(currentTime - guardState.targetTime) <= forcedPlaybackTimeGuardTolerance else {
            return false
        }
        PlayerMetricsLog.logger.info(
            "ignoredStalePlaybackTimeAfterSeek id=\(self.metricsID, privacy: .public) target=\(guardState.targetTime, format: .fixed(precision: 2), privacy: .public) current=\(self.currentTime, format: .fixed(precision: 2), privacy: .public) candidate=\(time, format: .fixed(precision: 2), privacy: .public)"
        )
        return true
    }

    private func clearForcedPlaybackTimeGuardIfSatisfied(by time: TimeInterval) {
        guard let guardState = forcedPlaybackTimeGuard else { return }
        if abs(time - guardState.targetTime) <= forcedPlaybackTimeGuardTolerance
            || CACurrentMediaTime() > guardState.expiresAt {
            forcedPlaybackTimeGuard = nil
        }
    }

    private func shouldIgnoreStartupPlaybackTimeOutlier(_ time: TimeInterval) -> Bool {
        guard resumeTime < 10,
              !didApplyResumeTime,
              currentTime < 2,
              time - currentTime > 8,
              PlayerMetricsLog.elapsedMilliseconds(since: metricsStartTime) < 15_000,
              ignoredStartupPlaybackTimeOutliers < 24
        else { return false }
        ignoredStartupPlaybackTimeOutliers += 1
        PlayerMetricsLog.logger.info(
            "ignoredStartupPlaybackTimeOutlier id=\(self.metricsID, privacy: .public) current=\(self.currentTime, format: .fixed(precision: 2), privacy: .public) candidate=\(time, format: .fixed(precision: 2), privacy: .public)"
        )
        return true
    }

    private func updateDuration(_ newDuration: TimeInterval) {
        guard newDuration > 0 else { return }
        if let duration, abs(duration - newDuration) < 0.5 {
            return
        }
        duration = newDuration
        playbackClock.update(time: currentTime, duration: displayDuration, force: true)
    }

    private func handleEnginePlaybackState(_ state: PlayerEnginePlaybackState) {
        guard !isTerminated else { return }
        syncEngineDiagnostics()
        switch state {
        case .idle:
            cancelDeferredBufferingIndicator()
            isBuffering = false
            playbackPhase = .idle
        case .preparing:
            cancelDeferredBufferingIndicator()
            isPreparing = true
            isBuffering = false
            if !hasPresentedPlayback {
                isPlaybackSurfaceReady = false
            }
            loadingProgress = max(loadingProgress, 0.18)
            playbackPhase = .preparing
        case .ready:
            cancelDeferredBufferingIndicator()
            isPreparing = false
            isBuffering = false
            loadingProgress = max(loadingProgress, 0.86)
            errorMessage = nil
            playbackPhase = hasPresentedPlayback ? .ready : .waitingForFirstFrame
            if wantsAutoplay {
                schedulePlaybackRecoveryWatchdog(reason: .firstFrame)
            }
        case .buffering:
            isPreparing = false
            loadingProgress = max(loadingProgress, isUserSeeking && hasPresentedPlayback ? 0.22 : 0.72)
            if hasPresentedPlayback {
                if isBuffering {
                    playbackPhase = .buffering
                    schedulePlaybackRecoveryWatchdog(reason: .stall)
                } else {
                    playbackPhase = .playing
                    scheduleDeferredBufferingIndicator()
                }
            } else {
                if !isBuffering {
                    bufferingCount += 1
                    lastBufferingElapsedMilliseconds = elapsedMilliseconds()
                    notifyBufferingPressureIfNeeded()
                }
                isBuffering = true
                playbackPhase = .waitingForFirstFrame
                PlayerMetricsLog.record(.buffering, metricsID: metricsID, title: title, message: elapsedMessage())
                schedulePlaybackRecoveryWatchdog(reason: .firstFrame)
            }
        case .playing:
            cancelDeferredBufferingIndicator()
            isPlaying = true
            errorMessage = nil
            isPreparing = false
            if hasPresentedPlayback {
                markPlaybackSurfaceReady()
            } else {
                isBuffering = true
                loadingProgress = max(loadingProgress, 0.86)
                playbackPhase = .waitingForFirstFrame
                schedulePlaybackRecoveryWatchdog(reason: .firstFrame)
            }
        case .paused:
            cancelDeferredBufferingIndicator()
            if isUserSeeking && wantsAutoplay {
                isBuffering = true
                isPlaying = true
                playbackPhase = .seeking
            } else {
                isBuffering = false
                isPlaying = false
                playbackPhase = .paused
            }
        case .ended:
            cancelDeferredBufferingIndicator()
            isPreparing = false
            isBuffering = false
            isPlaying = false
            wantsAutoplay = false
            playbackPhase = .ended
        case .failed(let message):
            cancelDeferredBufferingIndicator()
            isPreparing = false
            isBuffering = false
            isPlaying = false
            wantsAutoplay = false
            errorMessage = message ?? PlayerEngineError.unsupportedMedia.localizedDescription
            playbackPhase = .failed(errorMessage)
            PlayerMetricsLog.record(.failed, metricsID: metricsID, title: title, message: errorMessage)
            onPlaybackFailure?(errorMessage)
        }
        rescheduleTimeObserverIfNeeded()
    }

    private func notifyBufferingPressureIfNeeded() {
        guard bufferingCount >= 2,
              bufferingCount != lastBufferingPressureNotificationCount
        else { return }
        lastBufferingPressureNotificationCount = bufferingCount
        onBufferingPressure?(bufferingCount)
    }

    private func handleEnginePlaybackIntentChange(_ wantsPlayback: Bool) {
        guard !isTerminated else { return }
        if isUserSeeking, !wantsPlayback {
            return
        }
        wantsAutoplay = wantsPlayback
        if !wantsPlayback {
            cancelDeferredBufferingIndicator()
            cancelSeekRecoveryTracking()
            isPlaying = false
            isBuffering = false
            if playbackPhase != .idle, playbackPhase != .ended {
                playbackPhase = .paused
            }
            invalidatePictureInPicturePlaybackState()
        }
    }

    private func markUserSeekIntent() {
        lastUserSeekAt = Date()
    }

    private func beginSeekRecoveryTracking(
        reason: String,
        targetTime: TimeInterval?,
        targetProgress: Double?,
        startedAt: CFTimeInterval,
        engineElapsedMilliseconds: Double?
    ) {
        guard wantsAutoplay || isPlaying else { return }
        seekRecoveryWatchdogTask?.cancel()
        let metric = PendingSeekRecoveryMetric(
            reason: reason,
            targetTime: targetTime,
            targetProgress: targetProgress,
            startedAt: startedAt,
            engineElapsedMilliseconds: engineElapsedMilliseconds
        )
        pendingSeekRecoveryMetric = metric
        lastSeekBufferReadyMetricID = nil
        seekRecoveryWatchdogTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.seekRecoveryWatchdogDelayNanoseconds)
            guard !Task.isCancelled,
                  !self.isTerminated,
                  let pending = self.pendingSeekRecoveryMetric,
                  pending.id == metric.id
            else { return }
            let snapshot = self.engine.snapshot(durationHint: self.durationHint)
            if let snapshotTime = snapshot.currentTime,
               snapshot.isPlaying,
               self.isSeekRecoveryMatch(currentTime: snapshotTime, pending: pending) {
                self.finishSeekRecoveryMetric(
                    pending,
                    recovered: true,
                    currentTime: snapshotTime,
                    source: "watchdog"
                )
                return
            }
            self.finishSeekRecoveryMetric(
                pending,
                recovered: false,
                currentTime: snapshot.currentTime ?? self.currentTime,
                source: "watchdog"
            )
        }
    }

    private func recordSeekTransition(
        reason: String,
        targetTime: TimeInterval?,
        targetProgress: Double?,
        totalElapsedMilliseconds: Double,
        engineElapsedMilliseconds: Double?
    ) {
        PlayerMetricsLog.record(
            .seek,
            metricsID: metricsID,
            title: title,
            message: seekTransitionMessage(
                reason: reason,
                targetTime: targetTime,
                targetProgress: targetProgress,
                totalElapsedMilliseconds: totalElapsedMilliseconds,
                engineElapsedMilliseconds: engineElapsedMilliseconds
            )
        )
    }

    private func recordSeekRecoveryIfNeeded(currentTime: TimeInterval, source: String) {
        guard let pending = pendingSeekRecoveryMetric else { return }
        guard isSeekRecoveryMatch(currentTime: currentTime, pending: pending) else { return }
        finishSeekRecoveryMetric(
            pending,
            recovered: true,
            currentTime: currentTime,
            source: source
        )
    }

    private func finishSeekRecoveryMetric(
        _ pending: PendingSeekRecoveryMetric,
        recovered: Bool,
        currentTime: TimeInterval,
        source: String
    ) {
        guard pendingSeekRecoveryMetric?.id == pending.id else { return }
        seekRecoveryWatchdogTask?.cancel()
        seekRecoveryWatchdogTask = nil
        pendingSeekRecoveryMetric = nil
        lastSeekBufferReadyMetricID = nil
        PlayerMetricsLog.record(
            .seekRecovery,
            metricsID: metricsID,
            title: title,
            message: seekRecoveryMessage(
                reason: pending.reason,
                targetTime: pending.targetTime,
                targetProgress: pending.targetProgress,
                elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: pending.startedAt),
                engineElapsedMilliseconds: pending.engineElapsedMilliseconds,
                currentTime: currentTime,
                recovered: recovered,
                source: source
            )
        )
    }

    private func seekTransitionMessage(
        reason: String,
        targetTime: TimeInterval?,
        targetProgress: Double?,
        totalElapsedMilliseconds: Double,
        engineElapsedMilliseconds: Double?
    ) -> String {
        var parts = [reason]
        if let targetProgress {
            parts.append("progress=\(String(format: "%.3f", targetProgress))")
        }
        if let targetTime {
            parts.append("target=\(String(format: "%.2fs", targetTime))")
        }
        parts.append("total=\(String(format: "%.0fms", totalElapsedMilliseconds))")
        if let engineElapsedMilliseconds {
            parts.append("engine=\(String(format: "%.0fms", engineElapsedMilliseconds))")
        }
        return parts.joined(separator: " ")
    }

    private func seekRecoveryMessage(
        reason: String,
        targetTime: TimeInterval?,
        targetProgress: Double?,
        elapsedMilliseconds: Double,
        engineElapsedMilliseconds: Double?,
        currentTime: TimeInterval,
        recovered: Bool,
        source: String
    ) -> String {
        var parts = [reason, "recovered=\(recovered)"]
        if let targetProgress {
            parts.append("progress=\(String(format: "%.3f", targetProgress))")
        }
        if let targetTime {
            parts.append("target=\(String(format: "%.2fs", targetTime))")
        }
        parts.append("current=\(String(format: "%.2fs", currentTime))")
        parts.append("total=\(String(format: "%.0fms", elapsedMilliseconds))")
        if let engineElapsedMilliseconds {
            parts.append("engine=\(String(format: "%.0fms", engineElapsedMilliseconds))")
        }
        parts.append("source=\(source)")
        return parts.joined(separator: " ")
    }

    private func isSeekRecoveryMatch(currentTime: TimeInterval, pending: PendingSeekRecoveryMetric) -> Bool {
        guard let targetTime = pending.targetTime else {
            return currentTime > max(self.currentTime, 0) + 0.2
        }
        let toleranceBefore = max(0.9, min(targetTime * 0.03, 2.0))
        let toleranceAfter = max(4.5, min(targetTime * 0.12, 12.0))
        return currentTime >= max(targetTime - toleranceBefore, 0)
            && currentTime <= targetTime + toleranceAfter
    }

    private func cancelSeekRecoveryTracking() {
        seekRecoveryWatchdogTask?.cancel()
        seekRecoveryWatchdogTask = nil
        pendingSeekRecoveryMetric = nil
        lastSeekBufferReadyMetricID = nil
    }

    private func scheduleScrubSeekUIReleaseIfNeeded(
        generation: Int,
        targetTime: TimeInterval?,
        targetProgress: Double,
        startedAt: CFTimeInterval
    ) {
        scrubSeekUIReleaseTask?.cancel()
        scrubSeekUIReleaseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: self?.seekUIReleaseDelayNanoseconds ?? 1_150_000_000)
            guard let self,
                  !Task.isCancelled,
                  !self.isTerminated,
                  self.scrubSeekGeneration == generation,
                  self.isUserSeeking
            else { return }

            self.isUserSeeking = false
            if self.hasPresentedPlayback {
                self.isBuffering = true
                self.playbackPhase = .buffering
            }
            self.scrubSeekTask?.cancel()
            self.playbackRecoveryWatchdogTask?.cancel()
            self.playbackRecoveryWatchdogTask = nil
            if self.wantsAutoplay {
                self.engine.play()
                self.engine.setPlaybackRate(self.playbackRate.rawValue)
            }
            self.resumePlaybackAfterUserSeek()
            self.recordSeekTransition(
                reason: "scrub-timeout",
                targetTime: targetTime,
                targetProgress: targetProgress,
                totalElapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: startedAt),
                engineElapsedMilliseconds: nil
            )
            self.scrubSeekUIReleaseTask = nil
        }
    }

    private func handleEngineLoadingProgress(_ progress: Double) {
        let normalizedProgress = min(max(progress, 0), 0.98)
        guard !isTerminated else { return }
        updateSeekBufferProgressIfNeeded(engine.snapshot(durationHint: durationHint))
        guard isPreparing
            || isBuffering
            || isUserSeeking
            || playbackPhase == .seeking
            || playbackPhase == .buffering
            || playbackPhase == .recovering
            || !isPlaybackSurfaceReady
        else { return }
        guard normalizedProgress > loadingProgress + 0.01 else { return }
        loadingProgress = normalizedProgress
    }

    private func updateSeekBufferProgressIfNeeded(_ snapshot: PlayerPlaybackSnapshot) {
        guard let pending = pendingSeekRecoveryMetric,
              let targetTime = pending.targetTime,
              targetTime.isFinite,
              isUserSeeking || playbackPhase == .seeking || playbackPhase == .buffering || isBuffering
        else { return }

        let coverage = snapshot.bufferedCoverageProgress(around: targetTime)
        let seekProgress = min(max(0.22 + coverage * 0.76, 0.22), 0.98)
        if seekProgress > loadingProgress + 0.005 {
            loadingProgress = seekProgress
        }

        guard coverage >= 0.92, lastSeekBufferReadyMetricID != pending.id else { return }
        lastSeekBufferReadyMetricID = pending.id
        PlayerMetricsLog.record(
            .seek,
            metricsID: metricsID,
            title: title,
            message: "bufferReady reason=\(pending.reason) target=\(String(format: "%.2fs", targetTime)) coverage=\(String(format: "%.0f%%", coverage * 100))"
        )
    }

    private func skipSponsorBlockSegmentIfNeeded(at time: TimeInterval) {
        guard sponsorBlockEnabled,
              engine.hasMedia,
              wantsAutoplay,
              !sponsorBlockSegments.isEmpty
        else {
            activeSponsorBlockSegment = nil
            return
        }

        guard let segment = sponsorBlockSegment(at: time) else {
            activeSponsorBlockSegment = nil
            return
        }

        activeSponsorBlockSegment = segment
        guard !skippedSponsorBlockIDs.contains(segment.id) else { return }
        guard let skippedTo = engine.seek(toTime: segment.endTime) else { return }
        skippedSponsorBlockIDs.insert(segment.id)
        updatePlaybackTime(skippedTo, force: true, countsAsNaturalPlayback: false)
        PlayerMetricsLog.logger.info(
            "sponsorBlockSkipped id=\(self.metricsID, privacy: .public) category=\(segment.category, privacy: .public) from=\(time, format: .fixed(precision: 2), privacy: .public) to=\(skippedTo, format: .fixed(precision: 2), privacy: .public)"
        )

        if wantsAutoplay {
            guard ActivePlaybackCoordinator.shared.isActive(self) else { return }
            engine.play()
            engine.setPlaybackRate(playbackRate.rawValue)
        }
        invalidatePictureInPicturePlaybackState()
        reportSponsorBlockSkip(segment, from: time)
    }

    private func sponsorBlockSegment(at time: TimeInterval) -> SponsorBlockSegment? {
        if sponsorBlockSearchIndex >= sponsorBlockSegments.count {
            sponsorBlockSearchIndex = max(sponsorBlockSegments.count - 1, 0)
        }
        while sponsorBlockSearchIndex > 0,
              time < max(sponsorBlockSegments[sponsorBlockSearchIndex].startTime - sponsorBlockPrerollTolerance, 0) {
            sponsorBlockSearchIndex -= 1
        }

        while sponsorBlockSearchIndex < sponsorBlockSegments.count {
            let segment = sponsorBlockSegments[sponsorBlockSearchIndex]
            let startBoundary = max(segment.startTime - sponsorBlockPrerollTolerance, 0)
            let endBoundary = max(segment.endTime - sponsorBlockTailTolerance, startBoundary)
            if time < startBoundary {
                return nil
            }
            if time < endBoundary {
                return segment
            }
            sponsorBlockSearchIndex += 1
        }
        return nil
    }

    private func reportSponsorBlockSkip(_ segment: SponsorBlockSegment, from time: TimeInterval) {
        guard !sponsorBlockReportedIDs.contains(segment.id),
              let onSponsorBlockSegmentSkipped
        else { return }
        sponsorBlockReportedIDs.insert(segment.id)
        let event = SponsorBlockSkipEvent(segment: segment, fromTime: time, skippedAt: Date())
        Task {
            await onSponsorBlockSegmentSkipped(event)
        }
    }

    private func configurePictureInPictureIfNeeded() {
        guard !didConfigurePictureInPicture,
              !engine.supportsPictureInPicture,
              AVPictureInPictureController.isPictureInPictureSupported(),
              let contentSource = engine.pictureInPictureContentSource()
        else { return }

        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        pictureInPictureController = controller
        didConfigurePictureInPicture = true
    }

    private func invalidatePictureInPicturePlaybackState() {
        pictureInPictureController?.invalidatePlaybackState()
        engine.invalidatePictureInPicturePlaybackState()
        syncPictureInPictureState()
    }

    private func syncPictureInPictureState() {
        isPictureInPictureActive = pictureInPictureController?.isPictureInPictureActive == true
            || engine.isPictureInPictureActive
    }

    private func elapsedMessage() -> String {
        "\(elapsedMilliseconds())ms"
    }

    private func elapsedMilliseconds() -> Int {
        Int(PlayerMetricsLog.elapsedMilliseconds(since: metricsStartTime).rounded())
    }

    private func syncEngineDiagnostics(force: Bool = false) {
        if force {
            lastPeriodicEngineDiagnosticsSyncTime = CACurrentMediaTime()
        }
        let diagnostics = engine.diagnostics
        guard force || diagnostics != engineDiagnostics else { return }
        engineDiagnostics = diagnostics
    }

    private func syncEngineDiagnosticsForPeriodicRefresh() {
        if isPreparing || isBuffering || isUserSeeking || playbackPhase == .waitingForFirstFrame || playbackPhase == .recovering || playbackPhase == .seeking {
            syncEngineDiagnostics()
            return
        }

        let now = CACurrentMediaTime()
        let minimumInterval: TimeInterval = (wantsAutoplay || isPlaying) ? 2.5 : 4.0
        guard now - lastPeriodicEngineDiagnosticsSyncTime >= minimumInterval else { return }
        lastPeriodicEngineDiagnosticsSyncTime = now
        syncEngineDiagnostics()
    }
}

private struct ForcedPlaybackTimeGuard {
    let targetTime: TimeInterval
    let expiresAt: CFTimeInterval
}

private struct PendingStartupResume {
    let time: TimeInterval
    let reason: String
}

private struct PendingStartupResumeRecoveryMetric {
    let id = UUID()
    let reason: String
    let targetTime: TimeInterval
    let appliedTime: TimeInterval
    let startedAt: CFTimeInterval
    let engineElapsedMilliseconds: Double?
}

private struct PendingSeekRecoveryMetric {
    let id = UUID()
    let reason: String
    let targetTime: TimeInterval?
    let targetProgress: Double?
    let startedAt: CFTimeInterval
    let engineElapsedMilliseconds: Double?
}

extension PlayerStateViewModel: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            isPictureInPictureActive = true
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            isPictureInPictureActive = false
        }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in
            isPictureInPictureActive = false
            errorMessage = "画中画启动失败：\(error.localizedDescription)"
        }
    }
}
