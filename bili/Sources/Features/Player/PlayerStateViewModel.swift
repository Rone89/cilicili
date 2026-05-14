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

@MainActor
final class PlayerStateViewModel: NSObject, ObservableObject {
    let title: String

    @Published var currentTime: TimeInterval = 0
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

    private(set) var wantsAutoplay = true
    private let metricsID: String
    private let metricsStartTime = CACurrentMediaTime()
    private let streamSource: PlayerStreamSource
    private let durationHint: TimeInterval?
    private let resumeTime: TimeInterval
    private let startupResumePolicy: PlayerStartupResumePolicy
    private let engine: PlayerRenderingEngine
    private weak var surfaceView: VideoSurfaceContainerView?
    private weak var nativePlaybackController: AVPlayerViewController?
    private var timeObserver: Timer?
    private var didApplyResumeTime = false
    private var mediaPreparationTask: Task<Void, Never>?
    private var scrubSeekTask: Task<Void, Never>?
    private var startupResumeRetryTask: Task<Void, Never>?
    private var pictureInPictureController: AVPictureInPictureController?
    private var didConfigurePictureInPicture = false
    private var sponsorBlockSegments: [SponsorBlockSegment] = []
    private var skippedSponsorBlockIDs = Set<String>()
    private var sponsorBlockReportedIDs = Set<String>()
    private var ignoredStartupPlaybackTimeOutliers = 0
    private var didRecordFirstFrameEvent = false
    private var forcedPlaybackTimeGuard: ForcedPlaybackTimeGuard?
    private var sponsorBlockEnabled = false
    private var onSponsorBlockSegmentSkipped: (@Sendable (SponsorBlockSkipEvent) async -> Void)?
    private var hostFullscreenRequestHandler: (() -> Void)?
    private var isTerminated = false
    private var isStopping = false
    private let playbackStateRefreshInterval: TimeInterval = 1.0
    private let sponsorBlockPrerollTolerance: TimeInterval = 0.35
    private let sponsorBlockTailTolerance: TimeInterval = 0.12
    private let forcedPlaybackTimeGuardDuration: TimeInterval = 3.5
    private let forcedPlaybackTimeGuardTolerance: TimeInterval = 2.0

    init(
        videoURL: URL?,
        audioURL: URL?,
        videoStream: DASHStream? = nil,
        audioStream: DASHStream? = nil,
        title: String,
        referer: String,
        durationHint: TimeInterval? = nil,
        resumeTime: TimeInterval = 0,
        startupResumePolicy: PlayerStartupResumePolicy = .deferred,
        dynamicRange: BiliVideoDynamicRange = .sdr,
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
            referer: referer,
            httpHeaders: BiliHLSManifestBuilder.httpHeaders(referer: referer),
            title: title,
            durationHint: durationHint,
            resumeTime: resumeTime,
            dynamicRange: dynamicRange
        )
        self.durationHint = durationHint
        self.duration = durationHint
        self.resumeTime = resumeTime
        self.startupResumePolicy = startupResumePolicy
        self.engine = engine ?? PillarboxPlayerRenderingEngine()
        super.init()
        self.volume = self.engine.volume
        self.isMuted = self.engine.isMuted
        self.engine.onPlaybackStateChange = { [weak self] state in
            self?.handleEnginePlaybackState(state)
        }
        self.engine.onPlaybackIntentChange = { [weak self] wantsPlayback in
            self?.handleEnginePlaybackIntentChange(wantsPlayback)
        }
        self.engine.onLoadingProgressChange = { [weak self] progress in
            self?.handleEngineLoadingProgress(progress)
        }
        self.engine.onFirstFrame = { [weak self] currentTime in
            self?.handleEngineFirstFrame(currentTime)
        }
        self.engine.setViewModel(self)
        PlayerMetricsLog.logger.info(
            "created id=\(self.metricsID, privacy: .public) title=\(PlayerMetricsLog.shortTitle(title), privacy: .public) hasAudio=\((audioURL != nil), privacy: .public) resume=\(resumeTime, privacy: .public)"
        )
        PlayerMetricsLog.record(.playerCreated, metricsID: self.metricsID, title: title)
        startTimeObserver()
    }

    deinit {
        mediaPreparationTask?.cancel()
        scrubSeekTask?.cancel()
        startupResumeRetryTask?.cancel()
        timeObserver?.invalidate()
        let engine = engine
        Task { @MainActor in
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
        guard let duration = displayDuration, duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    func attachSurface(_ view: VideoSurfaceContainerView, prefersNativePlaybackControls: Bool = true) {
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
        guard let surfaceView else { return false }
        surfaceView.setManualFullscreenMode(mode, onExit: onExit, animated: animated)
        return surfaceView.isInManualFullscreen
    }

    func playbackSnapshot() -> PlayerPlaybackSnapshot {
        engine.snapshot(durationHint: duration ?? durationHint)
    }

    func setHostFullscreenActive(_ isActive: Bool, exitTarget: PlayerHostFullscreenExitTarget? = nil) {
        engine.setHostFullscreenActive(isActive, exitTarget: exitTarget)
        engine.refreshSurfaceLayout()
    }

    func recoverSurfaceAfterHostFullscreenTransition() {
        guard surfaceView != nil else { return }
        engine.refreshSurfaceLayout()
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

    private func rebuildMediaAfterPlaybackInterruption() {
        guard !isTerminated else { return }
        guard mediaPreparationTask == nil else { return }
        let restoreTime = currentTime
        isPreparing = false
        mediaPreparationTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try await self.engine.prepare(source: self.streamSource)
                guard !Task.isCancelled, !self.isTerminated else { return }
                self.mediaPreparationTask = nil
                if restoreTime > 0, let time = self.engine.seek(toTime: restoreTime) {
                    self.updatePlaybackTime(time, force: true, countsAsNaturalPlayback: false)
                }
                if self.wantsAutoplay {
                    self.startPreparedPlayback()
                } else {
                    self.refreshPlaybackState()
                }
            } catch {
                guard !Task.isCancelled, !self.isTerminated else { return }
                self.mediaPreparationTask = nil
                self.errorMessage = error.localizedDescription
                self.isPreparing = false
            }
        }
    }

    func play() {
        guard !isTerminated else { return }
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
        play()
    }

    func pause() {
        guard !isTerminated else { return }
        wantsAutoplay = false
        engine.pause()
        isPlaying = false
        invalidatePictureInPicturePlaybackState()
    }

    func setPlaybackIntent(_ shouldAutoplay: Bool) {
        guard !isTerminated else { return }
        wantsAutoplay = shouldAutoplay
        if !shouldAutoplay {
            isPlaying = false
            isBuffering = false
        }
    }

    func suspendForNavigation() {
        guard !isTerminated else { return }
        mediaPreparationTask?.cancel()
        mediaPreparationTask = nil
        pause()
    }

    func stop(reason: PlayerStopReason = .navigation) {
        guard !isStopping else { return }
        if isTerminated {
            ActivePlaybackCoordinator.shared.deactivate(self)
            return
        }
        isStopping = true
        isTerminated = true
        mediaPreparationTask?.cancel()
        mediaPreparationTask = nil
        scrubSeekTask?.cancel()
        scrubSeekTask = nil
        startupResumeRetryTask?.cancel()
        startupResumeRetryTask = nil
        timeObserver?.invalidate()
        timeObserver = nil
        wantsAutoplay = false
        engine.setViewModel(nil)
        engine.stop()
        ActivePlaybackCoordinator.shared.deactivate(self)
        isPlaying = false
        isPreparing = false
        isBuffering = false
        errorMessage = nil
        loadingProgress = 0
        hasPresentedPlayback = false
        isPlaybackSurfaceReady = false
        forcedPlaybackTimeGuard = nil
        didRecordFirstFrameEvent = false
        invalidatePictureInPicturePlaybackState()
        isStopping = false
    }

    func togglePlayback() {
        guard !isTerminated else { return }
        let snapshot = engine.snapshot(durationHint: durationHint)
        if isPlaying || snapshot.isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to progress: Double) {
        guard !isTerminated else { return }
        guard engine.hasMedia else { return }
        if let time = engine.seek(toProgress: progress, duration: duration) {
            updatePlaybackTime(time, force: true, countsAsNaturalPlayback: false)
        }
        invalidatePictureInPicturePlaybackState()
    }

    func seekAfterUserScrub(to progress: Double) {
        guard !isTerminated else { return }
        guard engine.hasMedia else { return }
        wantsAutoplay = true
        scrubSeekTask?.cancel()
        scrubSeekTask = Task(priority: .userInitiated) { @MainActor [weak self] in
            guard let self else { return }
            let time = await self.engine.seekAfterUserScrub(toProgress: progress, duration: self.duration)
            guard !Task.isCancelled, !self.isTerminated else { return }
            if let time {
                self.updatePlaybackTime(time, force: true, countsAsNaturalPlayback: false)
            }
            self.startPreparedPlayback()
        }
    }

    func seek(by interval: TimeInterval) {
        guard !isTerminated else { return }
        guard engine.hasMedia else { return }
        if let time = engine.seek(by: interval, from: currentTime, duration: duration ?? durationHint) {
            updatePlaybackTime(time, force: true, countsAsNaturalPlayback: false)
        }
        invalidatePictureInPicturePlaybackState()
    }

    func setPlaybackRate(_ rate: BiliPlaybackRate) {
        playbackRate = rate
        engine.setPlaybackRate(rate.rawValue)
        invalidatePictureInPicturePlaybackState()
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
        PlayerMetricsLog.logger.info(
            "prepareRequested id=\(self.metricsID, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: self.metricsStartTime), format: .fixed(precision: 1), privacy: .public)"
        )
        PlayerMetricsLog.record(.prepareRequested, metricsID: metricsID, title: title, message: elapsedMessage())
        mediaPreparationTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try await self.engine.prepare(source: self.streamSource)
                guard !Task.isCancelled, !self.isTerminated else { return }
                PlayerMetricsLog.logger.info(
                    "prepareReturned id=\(self.metricsID, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: self.metricsStartTime), format: .fixed(precision: 1), privacy: .public)"
                )
                PlayerMetricsLog.record(.prepareReturned, metricsID: self.metricsID, title: self.title, message: self.elapsedMessage())
                self.mediaPreparationTask = nil
                self.loadingProgress = max(self.loadingProgress, 0.72)
                if self.startupResumePolicy == .immediate {
                    self.applyImmediateResumeTimeIfNeeded()
                }
                if self.wantsAutoplay {
                    self.startPreparedPlayback()
                } else {
                    self.isPreparing = false
                    self.refreshPlaybackState()
                }
            } catch {
                guard !Task.isCancelled, !self.isTerminated else { return }
                PlayerMetricsLog.logger.error(
                    "prepareFailed id=\(self.metricsID, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: self.metricsStartTime), format: .fixed(precision: 1), privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                PlayerMetricsLog.record(.failed, metricsID: self.metricsID, title: self.title, message: "\(self.elapsedMessage()) \(error.localizedDescription)")
                self.mediaPreparationTask = nil
                self.errorMessage = error.localizedDescription
                self.isPreparing = false
            }
        }
    }

    private func startPreparedPlayback() {
        guard !isTerminated else { return }
        guard engine.hasMedia else { return }
        guard ActivePlaybackCoordinator.shared.isActive(self) else { return }
        wantsAutoplay = true
        isPreparing = false
        isBuffering = !hasPresentedPlayback
        loadingProgress = max(loadingProgress, 0.78)
        isPlaying = true
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

    private func refreshPlaybackState() {
        guard !isTerminated else { return }
        guard ActivePlaybackCoordinator.shared.isActive(self) || !wantsAutoplay else { return }
        if let playbackErrorMessage = engine.playbackErrorMessage {
            errorMessage = playbackErrorMessage
            isPreparing = false
            isPlaying = false
            wantsAutoplay = false
            invalidatePictureInPicturePlaybackState()
            return
        }

        let snapshot = engine.snapshot(durationHint: durationHint)
        var acceptedSnapshotTime: TimeInterval?
        if let snapshotTime = snapshot.currentTime,
           updatePlaybackTime(snapshotTime) {
            acceptedSnapshotTime = currentTime
            if isPreparing {
                isPreparing = false
            }
            if isBuffering, snapshot.isPlaying || hasPresentedPlayback {
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
        if isSeekable != snapshot.isSeekable {
            isSeekable = snapshot.isSeekable
        }
        syncPictureInPictureState()
        if let snapshotTime = acceptedSnapshotTime {
            skipSponsorBlockSegmentIfNeeded(at: snapshotTime)
        }
    }

    private func applyResumeTimeIfNeeded() {
        guard !didApplyResumeTime, resumeTime > 0.25 else { return }
        didApplyResumeTime = true
        let milliseconds = Int32(min(resumeTime * 1000, Double(Int32.max)))
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let self,
                  !self.isTerminated,
                  ActivePlaybackCoordinator.shared.isActive(self)
            else { return }
            if let time = self.engine.seek(toTime: TimeInterval(milliseconds) / 1000) {
                self.updatePlaybackTime(time, force: true, countsAsNaturalPlayback: false)
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
        guard let time = engine.seek(toTime: resumeTime) else { return false }
        updatePlaybackTime(time, force: true, countsAsNaturalPlayback: false)
        PlayerMetricsLog.logger.info(
            "startupResumeSeek id=\(self.metricsID, privacy: .public) reason=\(reason, privacy: .public) target=\(self.resumeTime, format: .fixed(precision: 2), privacy: .public) applied=\(time, format: .fixed(precision: 2), privacy: .public)"
        )
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
            recordFirstFrameIfNeeded(currentTime: normalizedTime, source: "playbackTime")
        }
        if countsAsNaturalPlayback, normalizedTime > 0 {
            hasPresentedPlayback = true
            isPlaybackSurfaceReady = true
            isBuffering = false
            loadingProgress = 1
        }
        if force || (currentTime <= 0 && normalizedTime > 0) || abs(currentTime - normalizedTime) >= 0.2 {
            currentTime = normalizedTime
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
        markPlaybackSurfaceReady()
        recordFirstFrameIfNeeded(currentTime: time, source: "engine")
        if time > 0 {
            _ = updatePlaybackTime(time, force: currentTime <= 0, countsAsNaturalPlayback: false)
        }
    }

    private func recordFirstFrameIfNeeded(currentTime: TimeInterval, source: String) {
        guard !didRecordFirstFrameEvent else { return }
        didRecordFirstFrameEvent = true
        let normalizedTime = max(currentTime, 0)
        PlayerMetricsLog.logger.info(
            "firstFrame id=\(self.metricsID, privacy: .public) source=\(source, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: self.metricsStartTime), format: .fixed(precision: 1), privacy: .public) current=\(normalizedTime, format: .fixed(precision: 2), privacy: .public)"
        )
        PlayerMetricsLog.record(
            .firstFrame,
            metricsID: metricsID,
            title: title,
            message: "\(elapsedMessage()) source=\(source) time=\(String(format: "%.2f", normalizedTime))s"
        )
    }

    private func markPlaybackSurfaceReady() {
        isPlaybackSurfaceReady = true
        hasPresentedPlayback = true
        loadingProgress = 1
        isPreparing = false
        isBuffering = false
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
    }

    private func handleEnginePlaybackState(_ state: PlayerEnginePlaybackState) {
        guard !isTerminated else { return }
        switch state {
        case .idle:
            isBuffering = false
        case .preparing:
            isPreparing = true
            isBuffering = false
            if !hasPresentedPlayback {
                isPlaybackSurfaceReady = false
            }
            loadingProgress = max(loadingProgress, 0.18)
        case .ready:
            isPreparing = false
            isBuffering = false
            loadingProgress = max(loadingProgress, 0.86)
            errorMessage = nil
        case .buffering:
            isPreparing = false
            isBuffering = true
            loadingProgress = max(loadingProgress, 0.72)
            PlayerMetricsLog.record(.buffering, metricsID: metricsID, title: title, message: elapsedMessage())
        case .playing:
            markPlaybackSurfaceReady()
            isPlaying = true
            errorMessage = nil
        case .paused:
            isBuffering = false
            isPlaying = false
        case .ended:
            isPreparing = false
            isBuffering = false
            isPlaying = false
            wantsAutoplay = false
        case .failed(let message):
            isPreparing = false
            isBuffering = false
            isPlaying = false
            wantsAutoplay = false
            errorMessage = message ?? PlayerEngineError.unsupportedMedia.localizedDescription
            PlayerMetricsLog.record(.failed, metricsID: metricsID, title: title, message: errorMessage)
        }
    }

    private func handleEnginePlaybackIntentChange(_ wantsPlayback: Bool) {
        guard !isTerminated else { return }
        wantsAutoplay = wantsPlayback
        if !wantsPlayback {
            isPlaying = false
            isBuffering = false
            invalidatePictureInPicturePlaybackState()
        }
    }

    private func handleEngineLoadingProgress(_ progress: Double) {
        guard !isTerminated, !isPlaybackSurfaceReady else { return }
        let normalizedProgress = min(max(progress, 0), 0.98)
        guard normalizedProgress > loadingProgress + 0.01 else { return }
        loadingProgress = normalizedProgress
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

        guard let segment = sponsorBlockSegments.first(where: { segment in
            let startBoundary = max(segment.startTime - sponsorBlockPrerollTolerance, 0)
            let endBoundary = max(segment.endTime - sponsorBlockTailTolerance, startBoundary)
            return time >= startBoundary && time < endBoundary
        }) else {
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
        "\(Int(PlayerMetricsLog.elapsedMilliseconds(since: metricsStartTime).rounded()))ms"
    }
}

private struct ForcedPlaybackTimeGuard {
    let targetTime: TimeInterval
    let expiresAt: CFTimeInterval
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
