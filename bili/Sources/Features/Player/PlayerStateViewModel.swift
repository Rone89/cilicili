import AVFoundation
import AVKit
import Combine
import OSLog
import SwiftUI
import UIKit

struct PlaybackTransitionSnapshot {
    let image: UIImage
    let isVideoFrame: Bool

    init(image: UIImage, isVideoFrame: Bool = true) {
        self.image = image
        self.isVideoFrame = isVideoFrame
    }
}

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
    var onPlaybackFailureWithReason: ((String?, HLSBridgeFailureReason?) -> Void)?
    var onBufferingPressure: ((Int) -> Void)?
    var onFirstFramePresented: (@MainActor () -> Void)?
    var restoreUserInterfaceForPictureInPictureStop: (() async -> Bool)?

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
    @Published private(set) var isCurrentPlaybackSurfaceReadyForDisplay = false
    @Published private(set) var activeSponsorBlockSegment: SponsorBlockSegment?
    @Published private(set) var prepareElapsedMilliseconds: Int?
    @Published private(set) var firstFrameElapsedMilliseconds: Int?
    @Published private(set) var bufferingCount = 0
    @Published private(set) var lastBufferingElapsedMilliseconds: Int?
    @Published private(set) var playbackPhase: PlayerPlaybackPhase = .idle
    @Published private(set) var recoveryAttemptCount = 0
    @Published private(set) var engineDiagnostics: PlayerEngineDiagnostics = .empty
    @Published private(set) var lastFailureReason: HLSBridgeFailureReason?
    @Published private(set) var isUserSeeking = false
    private(set) var surfaceLayoutGeneration = 0
    var isCurrentPlaybackSurfaceReady: Bool {
        isCurrentPlaybackSurfaceReadyForDisplay
    }

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
    private var engineCallbackGeneration = 0
    private weak var surfaceView: VideoSurfaceContainerView?
    private var surfaceAttachmentGeneration = 0
    private weak var nativePlaybackController: AVPlayerViewController?
    private var prefersNativePlaybackControls = true
    private var timeObserver: Timer?
    private var didApplyResumeTime = false
    private var mediaPreparationTask: Task<Void, Never>?
    private var mediaPreparationGeneration = 0
    private var startupMediaWarmupTask: Task<Void, Never>?
    private var scrubSeekTask: Task<Void, Never>?
    private var scrubSeekGeneration = 0
    private var deferredStartupResumeTask: Task<Void, Never>?
    private var startupResumeRetryTask: Task<Void, Never>?
    private var startupResumeRetryGeneration = 0
    private var resumeRecoveryWatchdogTask: Task<Void, Never>?
    private var deferredBufferingIndicatorTask: Task<Void, Never>?
    private var scrubSeekUIReleaseTask: Task<Void, Never>?
    private var playbackRecoveryWatchdogTask: Task<Void, Never>?
    private var seekRecoveryWatchdogTask: Task<Void, Never>?
    private var speedBoostRecoveryTask: Task<Void, Never>?
    private var surfaceReadinessResetTask: Task<Void, Never>?
    private var shouldResumeAfterTransientSystemOverlay = false
    private var surfaceReadinessConfirmationTask: Task<Void, Never>?
    private var surfaceLayoutStabilizationTask: Task<Void, Never>?
    private var surfaceMigrationTask: Task<Void, Never>?
    private var isSurfaceMigrating = false
    private var currentPlaybackSurfaceReadyGeneration: Int?
    private var pictureInPictureStartRetryTask: Task<Void, Never>?
    private var pictureInPictureStartRetryGeneration = 0
    private var sponsorBlockSkipReportTasks: [UUID: Task<Void, Never>] = [:]
    private var pictureInPictureController: AVPictureInPictureController?
    private var didConfigurePictureInPicture = false
    private var sponsorBlockSegments: [SponsorBlockSegment] = []
    private var sponsorBlockSearchIndex = 0
    private var skippedSponsorBlockIDs = Set<String>()
    private var sponsorBlockReportedIDs = Set<String>()
    private var ignoredStartupPlaybackTimeOutliers = 0
    private var didRecordFirstFrameEvent = false
    private var pendingEngineFirstFrameTime: TimeInterval?
    private var forcedPlaybackTimeGuard: ForcedPlaybackTimeGuard?
    private var pendingStartupResume: PendingStartupResume?
    private var pendingResumeRecoveryMetric: PendingStartupResumeRecoveryMetric?
    private var pendingSeekRecoveryMetric: PendingSeekRecoveryMetric?
    private var lastSeekBufferReadyMetricID: UUID?
    private var navigationAudioSuspension: NavigationAudioSuspension?
    private var lastUsablePlaybackSnapshotImage: UIImage?
    private var currentSurfaceRevealHoldUntilNanoseconds: UInt64 = 0
    private var sponsorBlockEnabled = false
    private var onSponsorBlockSegmentSkipped: (@Sendable (SponsorBlockSkipEvent) async -> Void)?
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
    private let seekUIReleaseDelayNanoseconds: UInt64 = 420_000_000
    private let resumeRecoveryWatchdogDelayNanoseconds: UInt64 = 2_400_000_000
    private let seekRecoveryWatchdogDelayNanoseconds: UInt64 = 1_100_000_000
    private static let currentSurfaceReadinessConfirmationDelays: [UInt64] = [
        34_000_000,
        90_000_000,
        180_000_000
    ]
    private static let surfaceLayoutStabilizationDelays: [UInt64] = [
        0,
        16_000_000,
        34_000_000,
        84_000_000,
        160_000_000
    ]
    private static let surfaceHandoffReadinessResetDelayNanoseconds: UInt64 = 240_000_000
    private static let surfaceMigrationHoldNanoseconds: UInt64 = 700_000_000
    private static let currentSurfaceRevealSettleDelayNanoseconds: UInt64 = 380_000_000

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
        isTerminated = true
        engineCallbackGeneration &+= 1
        mediaPreparationTask?.cancel()
        mediaPreparationTask = nil
        startupMediaWarmupTask?.cancel()
        startupMediaWarmupTask = nil
        scrubSeekTask?.cancel()
        scrubSeekTask = nil
        deferredStartupResumeTask?.cancel()
        deferredStartupResumeTask = nil
        deferredBufferingIndicatorTask?.cancel()
        deferredBufferingIndicatorTask = nil
        startupResumeRetryTask?.cancel()
        startupResumeRetryTask = nil
        startupResumeRetryGeneration &+= 1
        resumeRecoveryWatchdogTask?.cancel()
        resumeRecoveryWatchdogTask = nil
        playbackRecoveryWatchdogTask?.cancel()
        playbackRecoveryWatchdogTask = nil
        seekRecoveryWatchdogTask?.cancel()
        seekRecoveryWatchdogTask = nil
        speedBoostRecoveryTask?.cancel()
        speedBoostRecoveryTask = nil
        surfaceReadinessResetTask?.cancel()
        surfaceReadinessResetTask = nil
        surfaceReadinessConfirmationTask?.cancel()
        surfaceReadinessConfirmationTask = nil
        surfaceLayoutStabilizationTask?.cancel()
        surfaceLayoutStabilizationTask = nil
        surfaceMigrationTask?.cancel()
        surfaceMigrationTask = nil
        scrubSeekUIReleaseTask?.cancel()
        scrubSeekUIReleaseTask = nil
        pictureInPictureStartRetryTask?.cancel()
        pictureInPictureStartRetryTask = nil
        pictureInPictureStartRetryGeneration &+= 1
        sponsorBlockSkipReportTasks.values.forEach { $0.cancel() }
        sponsorBlockSkipReportTasks.removeAll()
        onPlaybackFailure = nil
        onPlaybackFailureWithReason = nil
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

    func makePlaybackTransitionSnapshot() -> PlaybackTransitionSnapshot? {
        guard !isTerminated else { return nil }
        if let image = firstUsablePlaybackSnapshotImage(
            currentVideoFrameSnapshotImage(),
            currentSurfaceSnapshotImage()
        ) {
            rememberUsablePlaybackSnapshotImage(image)
            return PlaybackTransitionSnapshot(image: image, isVideoFrame: true)
        }
        guard let image = firstUsablePlaybackSnapshotImage(
            surfaceView?.makePlaybackTransitionSnapshotImage(),
            lastUsablePlaybackSnapshotImage
        ) else { return nil }
        rememberUsablePlaybackSnapshotImage(image)
        return PlaybackTransitionSnapshot(image: image, isVideoFrame: false)
    }

    func makeCurrentVideoFrameTransitionSnapshot() -> PlaybackTransitionSnapshot? {
        guard !isTerminated else { return nil }
        if let image = firstUsablePlaybackSnapshotImage(
            currentVideoFrameSnapshotImage(),
            currentSurfaceSnapshotImage()
        ) {
            rememberUsablePlaybackSnapshotImage(image)
            return PlaybackTransitionSnapshot(image: image, isVideoFrame: true)
        }
        guard let image = firstUsablePlaybackSnapshotImage(
            surfaceView?.makePlaybackTransitionSnapshotImage(),
            lastUsablePlaybackSnapshotImage
        ) else { return nil }
        rememberUsablePlaybackSnapshotImage(image)
        return PlaybackTransitionSnapshot(image: image, isVideoFrame: false)
    }

    func makeCurrentVisibleSurfaceTransitionSnapshot() -> PlaybackTransitionSnapshot? {
        guard !isTerminated else { return nil }
        guard let image = firstUsablePlaybackSnapshotImage(
            currentSurfaceSnapshotImage(),
            surfaceView?.makePlaybackTransitionSnapshotImage()
        ) else { return nil }
        rememberUsablePlaybackSnapshotImage(image)
        return PlaybackTransitionSnapshot(image: image, isVideoFrame: false)
    }

    func makePlaybackTransitionSnapshotView() -> UIView? {
        guard !isTerminated else { return nil }
        if let imageView = makeCurrentVideoFrameSnapshotView() {
            imageView.frame = surfaceView?.bounds ?? CGRect(origin: .zero, size: imageView.bounds.size)
            return imageView
        }
        return surfaceView?.makePlaybackTransitionSnapshotView()
    }

    func makeCurrentVideoFrameSnapshotView() -> UIView? {
        guard !isTerminated else { return nil }
        guard let image = firstUsablePlaybackSnapshotImage(
            currentVideoFrameSnapshotImage(),
            currentSurfaceSnapshotImage()
        )
        else { return nil }
        rememberUsablePlaybackSnapshotImage(image)
        let imageView = UIImageView(image: image)
        imageView.backgroundColor = .black
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.isOpaque = true
        imageView.frame = CGRect(origin: .zero, size: image.size)
        return imageView
    }

    private func currentVideoFrameSnapshotImage() -> UIImage? {
        guard !isTerminated else { return nil }
        return engine.currentVideoFrameImage()
    }

    private func currentSurfaceSnapshotImage() -> UIImage? {
        guard !isTerminated else { return nil }
        return engine.currentSurfaceSnapshotImage()
    }

    private func firstUsablePlaybackSnapshotImage(_ images: UIImage?...) -> UIImage? {
        for image in images {
            guard let image, !image.biliLooksLikeBlackFrame else { continue }
            return image
        }
        return nil
    }

    private func hasVisibleSeekRecoveryFrame(
        pending: PendingSeekRecoveryMetric,
        snapshot: PlayerPlaybackSnapshot
    ) -> Bool {
        if let renderedVideoTime = snapshot.renderedVideoTime {
            guard isSeekRecoveryMatch(currentTime: renderedVideoTime, pending: pending) else {
                return false
            }
            return hasVisibleSeekRecoveryFrame()
        }

        if snapshot.requiresRenderedVideoTimeForRecovery {
            return false
        }

        return hasVisibleSeekRecoveryFrame()
    }

    private func hasVisibleSeekRecoveryFrame() -> Bool {
        let surfaceImage = currentSurfaceSnapshotImage()
        if let image = firstUsablePlaybackSnapshotImage(surfaceImage) {
            rememberUsablePlaybackSnapshotImage(image)
            return true
        }

        // If the current drawable surface is capturable but black, do not trust the
        // cached video frame: it may still be the frame from before the seek.
        guard surfaceImage == nil else { return false }

        if let image = firstUsablePlaybackSnapshotImage(
            surfaceView?.makePlaybackTransitionSnapshotImage(),
            currentVideoFrameSnapshotImage()
        ) {
            rememberUsablePlaybackSnapshotImage(image)
            return true
        }
        return false
    }

    private func rememberUsablePlaybackSnapshotImage(_ image: UIImage) {
        guard !image.biliLooksLikeBlackFrame else { return }
        lastUsablePlaybackSnapshotImage = image
    }

    func attachSurface(
        _ view: VideoSurfaceContainerView,
        prefersNativePlaybackControls: Bool = true,
        preservesReadinessDuringSurfaceHandoff: Bool = false
    ) {
        guard !isTerminated else {
            view.setNativePlaybackControllerEnabled(false)
            return
        }
        self.prefersNativePlaybackControls = prefersNativePlaybackControls
        surfaceReadinessResetTask?.cancel()
        surfaceReadinessResetTask = nil
        let isNewSurface = surfaceView !== view
        let usesNativePlaybackControls = engine.usesNativePlaybackControls && prefersNativePlaybackControls
        let shouldAttachDirectSurface = !usesNativePlaybackControls && nativePlaybackController != nil
        if isNewSurface || shouldAttachDirectSurface {
            PlayerMetricsLog.diagnostic(
                "surface attach view=\(ObjectIdentifier(view).hashValue) isNew=\(isNewSurface) preserve=\(preservesReadinessDuringSurfaceHandoff) hasPresented=\(hasPresentedPlayback) ready=\(isPlaybackSurfaceReady) currentReady=\(isCurrentPlaybackSurfaceReadyForDisplay) engineHasMedia=\(engine.hasMedia)"
            )
            surfaceAttachmentGeneration &+= 1
            if shouldPreservePlaybackReadinessDuringSurfaceHandoff(preservesReadinessDuringSurfaceHandoff) {
                currentPlaybackSurfaceReadyGeneration = surfaceAttachmentGeneration
                isCurrentPlaybackSurfaceReadyForDisplay = true
            } else {
                currentPlaybackSurfaceReadyGeneration = nil
                isCurrentPlaybackSurfaceReadyForDisplay = false
            }
        }
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
        markSurfaceLayoutRefreshed()
        if isNewSurface || shouldAttachDirectSurface {
            scheduleCurrentSurfaceReadinessConfirmationIfNeeded(generation: surfaceAttachmentGeneration)
            schedulePendingEngineFirstFrameConsumptionIfNeeded(generation: surfaceAttachmentGeneration)
            schedulePlaybackActivationAfterSurfaceAttachIfNeeded(generation: surfaceAttachmentGeneration)
            stabilizeSurfaceLayoutAfterGeometryChange()
        }
    }

    func attachNativePlaybackController(_ controller: AVPlayerViewController) {
        guard !isTerminated else { return }
        nativePlaybackController = controller
        engine.attachNativePlaybackController(controller)
        configurePictureInPictureIfNeeded()
        if engine.hasMedia {
            engine.refreshSurfaceLayout()
        }
    }

    func detachNativePlaybackController(_ controller: AVPlayerViewController) {
        if !isTerminated {
            engine.detachNativePlaybackController(controller)
        }
        if nativePlaybackController === controller {
            nativePlaybackController = nil
        }
    }

    func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        guard !isTerminated else { return }
        engine.setVideoGravity(gravity)
        engine.refreshSurfaceLayout()
        markSurfaceLayoutRefreshed()
    }

    func setContentOverlay(_ overlay: AnyView?) {
        guard !isTerminated else { return }
        engine.setContentOverlay(overlay)
        engine.refreshSurfaceLayout()
        markSurfaceLayoutRefreshed()
    }

    func setDanmakuControls(
        isEnabled: Bool,
        onToggle: (() -> Void)?,
        onShowSettings: (() -> Void)?
    ) {
        guard !isTerminated else { return }
        engine.setDanmakuControls(
            isEnabled: isEnabled,
            onToggle: onToggle,
            onShowSettings: onShowSettings
        )
    }

    func setQualityControls(_ controls: PlayerQualityControls?) {
        guard !isTerminated else { return }
        engine.setQualityControls(controls)
    }

    private func installPlaybackHandoffSnapshot(
        on hostView: UIView,
        fallbackView: UIView?,
        fadeDelay: TimeInterval,
        fadeDuration: TimeInterval
    ) {
        guard let snapshotView = makePlaybackHandoffSnapshotView(fallbackView: fallbackView) else { return }
        snapshotView.frame = hostView.bounds
        snapshotView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        snapshotView.isUserInteractionEnabled = false
        snapshotView.alpha = 1
        snapshotView.backgroundColor = .black
        hostView.addSubview(snapshotView)
        hostView.bringSubviewToFront(snapshotView)

        let delayNanoseconds = UInt64(max(fadeDelay, 0) * 1_000_000_000)
        Task { @MainActor [weak snapshotView] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard let snapshotView, snapshotView.superview != nil else { return }
            UIView.animate(withDuration: fadeDuration, delay: 0, options: [.curveEaseOut]) {
                snapshotView.alpha = 0
            } completion: { _ in
                snapshotView.removeFromSuperview()
            }
        }
    }

    private func makePlaybackHandoffSnapshotView(fallbackView: UIView?) -> UIView? {
        if let imageView = makeCurrentVideoFrameSnapshotView() {
            return imageView
        }

        guard let fallbackView,
              let snapshotView = fallbackView.snapshotView(afterScreenUpdates: false)
        else { return nil }
        snapshotView.backgroundColor = .black
        snapshotView.isOpaque = true
        return snapshotView
    }

    func detachSurface(
        _ view: VideoSurfaceContainerView,
        preservesReadinessDuringSurfaceHandoff: Bool = false
    ) {
        guard surfaceView === view else { return }
        PlayerMetricsLog.diagnostic(
            "surface detach view=\(ObjectIdentifier(view).hashValue) preserve=\(preservesReadinessDuringSurfaceHandoff) hasPresented=\(hasPresentedPlayback) ready=\(isPlaybackSurfaceReady) currentReady=\(isCurrentPlaybackSurfaceReadyForDisplay) engineHasMedia=\(engine.hasMedia)"
        )
        surfaceAttachmentGeneration &+= 1
        surfaceReadinessConfirmationTask?.cancel()
        surfaceReadinessConfirmationTask = nil
        surfaceLayoutStabilizationTask?.cancel()
        surfaceLayoutStabilizationTask = nil
        if shouldPreservePlaybackReadinessDuringSurfaceHandoff(preservesReadinessDuringSurfaceHandoff) {
            currentPlaybackSurfaceReadyGeneration = surfaceAttachmentGeneration
            isCurrentPlaybackSurfaceReadyForDisplay = true
            scheduleSurfaceReadinessResetIfNeeded(
                generation: surfaceAttachmentGeneration,
                delayNanoseconds: Self.surfaceHandoffReadinessResetDelayNanoseconds
            )
        } else {
            currentPlaybackSurfaceReadyGeneration = nil
            isCurrentPlaybackSurfaceReadyForDisplay = false
            scheduleSurfaceReadinessResetIfNeeded(generation: surfaceAttachmentGeneration)
        }
        playbackRecoveryWatchdogTask?.cancel()
        playbackRecoveryWatchdogTask = nil
        scrubSeekUIReleaseTask?.cancel()
        scrubSeekUIReleaseTask = nil
        if !isTerminated {
            engine.setContentOverlay(nil)
            engine.setDanmakuControls(isEnabled: false, onToggle: nil, onShowSettings: nil)
            engine.setQualityControls(nil)
            engine.detachNativePlaybackController(view.nativePlayerViewController)
            engine.detachSurface(view.drawableView)
        }
        view.setNativePlaybackControllerEnabled(false)
        if nativePlaybackController === view.nativePlayerViewController {
            nativePlaybackController = nil
        }
        surfaceView = nil
    }

    func beginSurfaceMigrationHold() {
        guard !isTerminated, hasPresentedPlayback, engine.hasMedia else { return }
        isSurfaceMigrating = true
        surfaceMigrationTask?.cancel()
        surfaceMigrationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.surfaceMigrationHoldNanoseconds)
            guard let self, !Task.isCancelled else { return }
            self.isSurfaceMigrating = false
            self.surfaceMigrationTask = nil
        }
    }

    func endSurfaceMigrationHold() {
        surfaceMigrationTask?.cancel()
        surfaceMigrationTask = nil
        isSurfaceMigrating = false
    }

    private func shouldPreservePlaybackReadinessDuringSurfaceHandoff(_ requested: Bool) -> Bool {
        requested
            && hasPresentedPlayback
            && isPlaybackSurfaceReady
            && engine.hasMedia
            && errorMessage == nil
            && !isTerminated
    }

    private func scheduleSurfaceReadinessResetIfNeeded(
        generation: Int,
        delayNanoseconds: UInt64 = 180_000_000
    ) {
        surfaceReadinessResetTask?.cancel()
        guard hasPresentedPlayback, isPlaybackSurfaceReady else {
            isPlaybackSurfaceReady = false
            currentPlaybackSurfaceReadyGeneration = nil
            isCurrentPlaybackSurfaceReadyForDisplay = false
            surfaceReadinessResetTask = nil
            return
        }
        surfaceReadinessResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard let self,
                  !Task.isCancelled,
                  !self.isTerminated,
                  self.surfaceAttachmentGeneration == generation,
                  self.surfaceView == nil
            else { return }
            self.isPlaybackSurfaceReady = false
            self.currentPlaybackSurfaceReadyGeneration = nil
            self.isCurrentPlaybackSurfaceReadyForDisplay = false
            self.surfaceReadinessResetTask = nil
        }
    }

    private func scheduleCurrentSurfaceReadinessConfirmationIfNeeded(generation: Int) {
        surfaceReadinessConfirmationTask?.cancel()
        guard hasPresentedPlayback,
              isPlaybackSurfaceReady,
              hasCurrentSurface(generation: generation)
        else {
            surfaceReadinessConfirmationTask = nil
            return
        }

        if confirmCurrentSurfaceReady(generation: generation) {
            surfaceReadinessConfirmationTask = nil
            return
        }

        surfaceReadinessConfirmationTask = Task { @MainActor [weak self] in
            defer { self?.clearSurfaceReadinessConfirmationTaskIfCurrent(generation: generation) }
            for delay in Self.currentSurfaceReadinessConfirmationDelays {
                try? await Task.sleep(nanoseconds: delay)
                guard let self,
                      !Task.isCancelled,
                      !self.isTerminated,
                      self.hasCurrentSurface(generation: generation),
                      self.hasPresentedPlayback,
                      self.isPlaybackSurfaceReady
                else { return }

                self.refreshSurfaceLayout()
                if self.confirmCurrentSurfaceReady(generation: generation) {
                    return
                }
            }

            guard let self,
                  !Task.isCancelled,
                  !self.isTerminated,
                  self.hasCurrentSurface(generation: generation),
                  self.hasPresentedPlayback,
                  self.isPlaybackSurfaceReady
            else { return }
            self.refreshSurfaceLayout()
            _ = self.confirmCurrentSurfaceReady(generation: generation)
        }
    }

    private func confirmCurrentSurfaceReady(generation: Int) -> Bool {
        guard hasCurrentSurface(generation: generation) else { return false }
        if let image = firstUsablePlaybackSnapshotImage(
            currentSurfaceSnapshotImage(),
            surfaceView?.makePlaybackTransitionSnapshotImage(),
            currentVideoFrameSnapshotImage()
        ) {
            rememberUsablePlaybackSnapshotImage(image)
        } else if canTrustCurrentPlaybackSurfaceWithoutSnapshot(generation: generation) {
            PlayerMetricsLog.diagnostic(
                "surface ready trustedWithoutSnapshot generation=\(generation) hasPresented=\(hasPresentedPlayback) ready=\(isPlaybackSurfaceReady) phase=\(playbackPhase)"
            )
        } else {
            return false
        }
        currentPlaybackSurfaceReadyGeneration = generation
        isCurrentPlaybackSurfaceReadyForDisplay = true
        return true
    }

    private func canTrustCurrentPlaybackSurfaceWithoutSnapshot(generation: Int) -> Bool {
        hasCurrentSurface(generation: generation)
            && hasPresentedPlayback
            && isPlaybackSurfaceReady
            && engine.hasMedia
            && errorMessage == nil
            && !isPreparing
            && playbackPhase != .waitingForFirstFrame
    }

    @discardableResult
    func validateCurrentPlaybackSurfaceReadyForDisplay() -> Bool {
        guard !isTerminated, surfaceView != nil else {
            currentPlaybackSurfaceReadyGeneration = nil
            isCurrentPlaybackSurfaceReadyForDisplay = false
            return false
        }
        if confirmCurrentSurfaceReady(generation: surfaceAttachmentGeneration) {
            return true
        }
        currentPlaybackSurfaceReadyGeneration = nil
        isCurrentPlaybackSurfaceReadyForDisplay = false
        return false
    }

    func validateCurrentPlaybackSurfaceReadyForReveal() -> Bool {
        guard !isTerminated, surfaceView != nil else { return false }
        if makeCurrentVisibleSurfaceTransitionSnapshot() != nil {
            currentPlaybackSurfaceReadyGeneration = surfaceAttachmentGeneration
            isCurrentPlaybackSurfaceReadyForDisplay = true
            PlayerMetricsLog.diagnostic(
                "surface reveal visibleSnapshot generation=\(surfaceAttachmentGeneration) layoutGeneration=\(surfaceLayoutGeneration)"
            )
            return true
        }

        guard canTrustCurrentPlaybackSurfaceWithoutSnapshot(generation: surfaceAttachmentGeneration) else {
            return false
        }

        let now = DispatchTime.now().uptimeNanoseconds
        guard now >= currentSurfaceRevealHoldUntilNanoseconds else {
            return false
        }

        currentPlaybackSurfaceReadyGeneration = surfaceAttachmentGeneration
        isCurrentPlaybackSurfaceReadyForDisplay = true
        PlayerMetricsLog.diagnostic(
            "surface reveal trustedAfterSettle generation=\(surfaceAttachmentGeneration) layoutGeneration=\(surfaceLayoutGeneration) phase=\(playbackPhase)"
        )
        return true
    }

    private func clearSurfaceReadinessConfirmationTaskIfCurrent(generation: Int) {
        guard hasCurrentSurface(generation: generation) else { return }
        surfaceReadinessConfirmationTask = nil
    }

    func refreshSurfaceLayout() {
        guard !isTerminated, surfaceView != nil else { return }
        engine.refreshSurfaceLayout()
        markSurfaceLayoutRefreshed()
    }

    func stabilizeSurfaceLayoutAfterGeometryChange() {
        guard !isTerminated, surfaceView != nil else { return }
        holdCurrentSurfaceRevealForGeometrySettle()
        surfaceLayoutStabilizationTask?.cancel()
        let generation = surfaceAttachmentGeneration
        surfaceLayoutStabilizationTask = Task { @MainActor [weak self] in
            defer {
                if self?.surfaceAttachmentGeneration == generation {
                    self?.surfaceLayoutStabilizationTask = nil
                }
            }
            for delay in Self.surfaceLayoutStabilizationDelays {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                } else {
                    await Task.yield()
                }
                guard let self,
                      !Task.isCancelled,
                      !self.isTerminated,
                      self.hasCurrentSurface(generation: generation)
                else { return }
                self.refreshSurfaceLayout()
            }
        }
    }

    private func holdCurrentSurfaceRevealForGeometrySettle() {
        let holdUntil = DispatchTime.now().uptimeNanoseconds
            + Self.currentSurfaceRevealSettleDelayNanoseconds
        currentSurfaceRevealHoldUntilNanoseconds = max(
            currentSurfaceRevealHoldUntilNanoseconds,
            holdUntil
        )
    }

    private func hasCurrentSurface(generation: Int) -> Bool {
        surfaceAttachmentGeneration == generation && surfaceView != nil
    }

    private func canActivatePlayback() -> Bool {
        !isTerminated
            && surfaceView != nil
            && ActivePlaybackCoordinator.shared.isActive(self)
    }

    private func canActivatePlayback(generation: Int) -> Bool {
        !isTerminated
            && hasCurrentSurface(generation: generation)
            && ActivePlaybackCoordinator.shared.isActive(self)
    }

    private func markSurfaceLayoutRefreshed() {
        guard surfaceView != nil else { return }
        surfaceLayoutGeneration &+= 1
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

    func recoverPlaybackAfterAppResume() {
        guard !isTerminated else { return }
        guard ActivePlaybackCoordinator.shared.isActive(self) else { return }
        let baselineSurfaceGeneration = surfaceAttachmentGeneration
        if timeObserver == nil {
            startTimeObserver()
        }
        if hasCurrentSurface(generation: baselineSurfaceGeneration) {
            engine.recoverSurface()
            refreshSurfaceLayout()
        }
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

    func preservePlaybackThroughTransientSystemOverlay() {
        guard !isTerminated else { return }
        guard ActivePlaybackCoordinator.shared.isActive(self) else { return }
        let snapshot = playbackSnapshot()
        let shouldResume = wantsAutoplay || isPlaying || snapshot.isPlaying
        shouldResumeAfterTransientSystemOverlay = shouldResumeAfterTransientSystemOverlay || shouldResume
        guard shouldResume else { return }
        wantsAutoplay = true
        if engine.hasMedia, !snapshot.isPlaying {
            engine.play()
        }
    }

    func recoverPlaybackAfterTransientSystemOverlayIfNeeded() {
        let shouldResume = shouldResumeAfterTransientSystemOverlay
        shouldResumeAfterTransientSystemOverlay = false
        guard shouldResume else { return }
        wantsAutoplay = true
        recoverPlaybackAfterAppResume()
    }

    func cancelTransientSystemOverlayPlaybackPreservation() {
        shouldResumeAfterTransientSystemOverlay = false
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
        let baselineMediaPreparationGeneration = mediaPreparationGeneration
        let baselineSurfaceGeneration = surfaceAttachmentGeneration
        playbackRecoveryWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: reason.delay)
            guard let self,
                  !Task.isCancelled,
                  !self.isTerminated,
                  self.wantsAutoplay,
                  self.engine.hasMedia,
                  self.errorMessage == nil,
                  self.mediaPreparationGeneration == baselineMediaPreparationGeneration,
                  self.hasCurrentSurface(generation: baselineSurfaceGeneration),
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
            self.performPlaybackRecovery(
                reason: reason,
                baselineTime: baselineTime,
                surfaceGeneration: baselineSurfaceGeneration
            )
        }
    }

    private func performPlaybackRecovery(
        reason: PlaybackRecoveryWatchdogReason,
        baselineTime: TimeInterval,
        surfaceGeneration: Int
    ) {
        guard canActivatePlayback(generation: surfaceGeneration) else {
            playbackRecoveryWatchdogTask = nil
            return
        }
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
            .playbackRecovery,
            metricsID: metricsID,
            title: title,
            message: "stage=surfaceRecover status=started reason=\(reason.logTitle) attempt=\(recoveryAttemptCount) baseline=\(String(format: "%.2fs", baselineTime))"
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
              errorMessage == nil,
              surfaceView != nil,
              ActivePlaybackCoordinator.shared.isActive(self)
        else { return false }

        guard let image = firstUsablePlaybackSnapshotImage(
            currentSurfaceSnapshotImage(),
            surfaceView?.makePlaybackTransitionSnapshotImage()
        ) else { return false }
        rememberUsablePlaybackSnapshotImage(image)

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
        let baselineMediaPreparationGeneration = mediaPreparationGeneration
        let baselineSurfaceGeneration = surfaceAttachmentGeneration
        deferredBufferingIndicatorTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.deferredBufferingIndicatorDelayNanoseconds)
            guard !Task.isCancelled,
                  !self.isTerminated,
                  self.hasPresentedPlayback,
                  self.wantsAutoplay,
                  self.engine.hasMedia,
                  self.recoveryAttemptCount == baselineAttempt,
                  self.mediaPreparationGeneration == baselineMediaPreparationGeneration,
                  self.hasCurrentSurface(generation: baselineSurfaceGeneration)
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
        let baselineSurfaceGeneration = surfaceAttachmentGeneration
        guard hasCurrentSurface(generation: baselineSurfaceGeneration),
              ActivePlaybackCoordinator.shared.isActive(self)
        else { return }
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
                      preparationGeneration == self.mediaPreparationGeneration,
                      self.hasCurrentSurface(generation: baselineSurfaceGeneration),
                      ActivePlaybackCoordinator.shared.isActive(self)
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
                      preparationGeneration == self.mediaPreparationGeneration,
                      self.hasCurrentSurface(generation: baselineSurfaceGeneration),
                      ActivePlaybackCoordinator.shared.isActive(self)
                else {
                    self.clearMediaPreparationTaskIfCurrent(preparationGeneration)
                    return
                }
                self.clearMediaPreparationTaskIfCurrent(preparationGeneration)
                self.recordPlaybackFailure(message: error.localizedDescription, reason: self.engine.lastFailureReason)
                self.isPreparing = false
                self.onPlaybackFailureWithReason?(self.errorMessage, self.lastFailureReason)
                self.onPlaybackFailure?(self.errorMessage)
            }
        }
    }

    func play() {
        guard !isTerminated else { return }
        restoreAudioAfterCancelledNavigation()
        ActivePlaybackCoordinator.shared.activate(self)
        wantsAutoplay = true
        errorMessage = nil
        lastFailureReason = nil
        guard streamSource.videoURL != nil else {
            recordPlaybackFailure(
                message: PlayerEngineError.missingVideoURL.localizedDescription,
                reason: nil
            )
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
        guard canActivatePlayback() else { return }
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
        cancelStartupResumeRetryTask()
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
        cancelStartupResumeRetryTask()
        let retryGeneration = advanceStartupResumeRetryGeneration()
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
                      self.startupResumeRetryGeneration == retryGeneration,
                      self.canActivatePlayback()
                else { return }
                if self.applyPendingStartupResumeIfPossible() {
                    self.clearStartupResumeRetryTaskIfCurrent(retryGeneration)
                    return
                }
            }
            self?.clearStartupResumeRetryTaskIfCurrent(retryGeneration)
        }
    }

    func pause() {
        guard !isTerminated else { return }
        cancelScrubSeekTasks(resetUserSeeking: true)
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
        cancelScrubSeekTasks(resetUserSeeking: true)
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
        cancelScrubSeekTasks(resetUserSeeking: true)
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
        guard surfaceView != nil else { return }
        ActivePlaybackCoordinator.shared.activate(self)
        engine.setVolume(navigationAudioSuspension.volume)
        engine.setMuted(navigationAudioSuspension.isMuted)
        if navigationAudioSuspension.resumeTime > 0.25 {
            applyStartupResumeTime(navigationAudioSuspension.resumeTime, reason: "cancelledNavigation")
        }
        if navigationAudioSuspension.shouldResumePlayback {
            wantsAutoplay = true
            if engine.hasMedia, canActivatePlayback() {
                resumePreparedPlaybackAfterSeek()
            }
        }
    }

    func setPlaybackIntent(_ shouldAutoplay: Bool) {
        guard !isTerminated else { return }
        wantsAutoplay = shouldAutoplay
        if !shouldAutoplay {
            cancelScrubSeekTasks(resetUserSeeking: true)
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
        deferredStartupResumeTask?.cancel()
        deferredStartupResumeTask = nil
        cancelTransientInteractionTasks()
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
        engineCallbackGeneration &+= 1
        mediaPreparationGeneration &+= 1
        cancelScrubSeekTasks(resetUserSeeking: true)
        cancelDeferredBufferingIndicator()
        mediaPreparationTask?.cancel()
        mediaPreparationTask = nil
        startupMediaWarmupTask?.cancel()
        startupMediaWarmupTask = nil
        deferredStartupResumeTask?.cancel()
        deferredStartupResumeTask = nil
        cancelTransientInteractionTasks()
        cancelStartupResumeRecoveryTracking()
        cancelSeekRecoveryTracking()
        cancelStartupResumeRetryTask()
        playbackRecoveryWatchdogTask?.cancel()
        playbackRecoveryWatchdogTask = nil
        cancelPictureInPictureStartRetryTask()
        sponsorBlockSkipReportTasks.values.forEach { $0.cancel() }
        sponsorBlockSkipReportTasks.removeAll()
        navigationAudioSuspension = nil
        timeObserver?.invalidate()
        timeObserver = nil
        wantsAutoplay = false
        onPlaybackFailure = nil
        onPlaybackFailureWithReason = nil
        onBufferingPressure = nil
        onFirstFramePresented = nil
        onSponsorBlockSegmentSkipped = nil
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
        currentPlaybackSurfaceReadyGeneration = nil
        isCurrentPlaybackSurfaceReadyForDisplay = false
        currentTime = 0
        playbackClock.reset()
        playbackPhase = .idle
        recoveryAttemptCount = 0
        lastBufferingPressureNotificationCount = 0
        forcedPlaybackTimeGuard = nil
        lastSeekBufferReadyMetricID = nil
        didRecordFirstFrameEvent = false
        pendingEngineFirstFrameTime = nil
        invalidatePictureInPicturePlaybackState()
        isStopping = false
    }

    private func cancelTransientInteractionTasks() {
        scrubSeekUIReleaseTask?.cancel()
        scrubSeekUIReleaseTask = nil
        speedBoostRecoveryTask?.cancel()
        speedBoostRecoveryTask = nil
    }

    private func cancelScrubSeekTasks(resetUserSeeking: Bool) {
        scrubSeekGeneration &+= 1
        scrubSeekTask?.cancel()
        scrubSeekTask = nil
        scrubSeekUIReleaseTask?.cancel()
        scrubSeekUIReleaseTask = nil
        if resetUserSeeking, isUserSeeking {
            isUserSeeking = false
        }
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
            var appliedTime = await self.engine.seekAfterUserScrub(
                toProgress: targetProgress,
                duration: resolvedDuration > 0 ? resolvedDuration : self.duration
            )
            var seekReason = "scrub"
            if appliedTime == nil,
               let fallbackTarget = optimisticTargetTime ?? (self.currentTime > 0 ? self.currentTime : nil) {
                appliedTime = self.engine.seek(toTime: fallbackTarget)
                if appliedTime != nil {
                    seekReason = "scrub-fallback"
                }
            }
            let totalElapsed = PlayerMetricsLog.elapsedMilliseconds(since: userSeekStart)
            let engineElapsed = PlayerMetricsLog.elapsedMilliseconds(since: engineSeekStart)
            guard !Task.isCancelled,
                  !self.isTerminated,
                  self.scrubSeekGeneration == generation
            else {
                signpostMessage = "mode=scrub cancelled"
                return
            }
            if let appliedTime {
                self.updatePlaybackTime(appliedTime, force: true, countsAsNaturalPlayback: false)
                self.isUserSeeking = false
                self.isBuffering = self.hasPresentedPlayback && self.wantsAutoplay
                self.beginSeekRecoveryTracking(
                    reason: seekReason,
                    targetTime: appliedTime,
                    targetProgress: targetProgress,
                    startedAt: userSeekStart,
                    engineElapsedMilliseconds: engineElapsed
                )
            }
            self.recordSeekTransition(
                reason: seekReason,
                targetTime: appliedTime,
                targetProgress: targetProgress,
                totalElapsedMilliseconds: totalElapsed,
                engineElapsedMilliseconds: engineElapsed
            )
            signpostMessage = "mode=scrub target=\(String(format: "%.3f", targetProgress)) applied=\(String(format: "%.2f", appliedTime ?? 0)) total=\(String(format: "%.1f", totalElapsed))ms engine=\(String(format: "%.1f", engineElapsed))ms reason=\(seekReason)"
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
        guard !isTerminated else { return }
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
        if shouldKeepPlaying,
           !initialSnapshot.isPlaying,
           canActivatePlayback() {
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
                      self.canActivatePlayback()
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
        guard !isTerminated else { return }
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
        guard !isTerminated else { return }
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
            cancelPictureInPictureStartRetryTask()
            pictureInPictureController.stopPictureInPicture()
        } else {
            if pictureInPictureController.isPictureInPicturePossible {
                pictureInPictureController.startPictureInPicture()
            } else {
                cancelPictureInPictureStartRetryTask()
                let retryGeneration = advancePictureInPictureStartRetryGeneration()
                let controller = pictureInPictureController
                pictureInPictureStartRetryTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    guard let self,
                          !Task.isCancelled,
                          !self.isTerminated,
                          self.pictureInPictureStartRetryGeneration == retryGeneration,
                          self.pictureInPictureController === controller,
                          ActivePlaybackCoordinator.shared.isActive(self)
                    else { return }
                    if controller.isPictureInPicturePossible {
                        controller.startPictureInPicture()
                    }
                    self.clearPictureInPictureStartRetryTaskIfCurrent(retryGeneration)
                }
            }
        }
    }

    private func prepareMediaAndPlay() {
        guard !isTerminated else { return }
        guard mediaPreparationTask == nil else { return }
        let baselineSurfaceGeneration = surfaceAttachmentGeneration
        guard hasCurrentSurface(generation: baselineSurfaceGeneration),
              ActivePlaybackCoordinator.shared.isActive(self)
        else { return }
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
        pendingEngineFirstFrameTime = nil
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
                      preparationGeneration == self.mediaPreparationGeneration,
                      self.hasCurrentSurface(generation: baselineSurfaceGeneration),
                      ActivePlaybackCoordinator.shared.isActive(self)
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
                      preparationGeneration == self.mediaPreparationGeneration,
                      self.hasCurrentSurface(generation: baselineSurfaceGeneration),
                      ActivePlaybackCoordinator.shared.isActive(self)
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
                self.recordPlaybackFailure(message: error.localizedDescription, reason: self.engine.lastFailureReason)
                self.isPreparing = false
                self.onPlaybackFailureWithReason?(self.errorMessage, self.lastFailureReason)
                self.onPlaybackFailure?(self.errorMessage)
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

    private func seekRecoveryPreparationSource(targetTime: TimeInterval?) -> PlayerStreamSource {
        guard let targetTime,
              targetTime.isFinite,
              targetTime > 0.25
        else {
            return streamSourceForPreparation()
        }
        return streamSourceForPreparation().withResumeTime(targetTime)
    }

    private func startPreparedPlayback() {
        guard !isTerminated else { return }
        guard engine.hasMedia else { return }
        guard canActivatePlayback() else { return }
        wantsAutoplay = true
        isPreparing = false
        isBuffering = !hasPresentedPlayback
        playbackPhase = hasPresentedPlayback ? .playing : .waitingForFirstFrame
        loadingProgress = max(loadingProgress, 0.78)
        isPlaying = true
        if !hasPresentedPlayback {
            engine.setTemporaryAudioSuppressed(true)
        }
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
        guard canActivatePlayback() else { return false }
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
        guard canActivatePlayback() else { return }
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
        engine.recoverSurface()
        refreshSurfaceLayout()
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
        deferredStartupResumeTask?.cancel()
        deferredStartupResumeTask = nil
        cancelStartupResumeRetryTask()
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
        let baselineSurfaceGeneration = surfaceAttachmentGeneration
        resumeRecoveryWatchdogTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.resumeRecoveryWatchdogDelayNanoseconds)
            guard !Task.isCancelled,
                  !self.isTerminated,
                  let pending = self.pendingResumeRecoveryMetric,
                  pending.id == metric.id,
                  self.hasCurrentSurface(generation: baselineSurfaceGeneration)
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
        engineCallbackGeneration &+= 1
        let callbackGeneration = engineCallbackGeneration
        if restoreVolumeState {
            engine.setVolume(volume)
            engine.setMuted(isMuted)
            engine.setPlaybackRate(playbackRate.rawValue)
        } else {
            volume = engine.volume
            isMuted = engine.isMuted
        }
        engine.onPlaybackStateChange = { [weak self] state in
            guard let self, self.isCurrentEngineCallbackGeneration(callbackGeneration) else { return }
            self.handleEnginePlaybackState(state)
        }
        engine.onPlaybackIntentChange = { [weak self] wantsPlayback in
            guard let self, self.isCurrentEngineCallbackGeneration(callbackGeneration) else { return }
            self.handleEnginePlaybackIntentChange(wantsPlayback)
        }
        engine.onLoadingProgressChange = { [weak self] progress in
            guard let self, self.isCurrentEngineCallbackGeneration(callbackGeneration) else { return }
            self.handleEngineLoadingProgress(progress)
        }
        engine.onFirstFrame = { [weak self] currentTime in
            guard let self, self.isCurrentEngineCallbackGeneration(callbackGeneration) else { return }
            self.handleEngineFirstFrame(currentTime)
        }
        engine.setViewModel(self)
        syncEngineDiagnostics(force: true)
    }

    private func isCurrentEngineCallbackGeneration(_ generation: Int) -> Bool {
        !isTerminated && engineCallbackGeneration == generation
    }

    private func startTimeObserver() {
        timeObserver?.invalidate()
        let timer = Timer(timeInterval: playbackStateRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      !self.isTerminated
                else { return }
                let baselineSurfaceGeneration = self.surfaceAttachmentGeneration
                guard self.hasCurrentSurface(generation: baselineSurfaceGeneration) else { return }
                self.refreshPlaybackState()
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
        let baselineSurfaceGeneration = surfaceAttachmentGeneration
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
        if !hasPresentedPlayback,
           snapshot.isPlaying,
           hasCurrentSurface(generation: baselineSurfaceGeneration),
           acceptFirstFramePresentationFallback(
               currentTime: snapshot.currentTime,
               source: "snapshot"
           ) {
            acceptedSnapshotTime = snapshot.currentTime ?? currentTime
        }
        if wantsAutoplay,
           engine.hasMedia,
           !snapshot.isPlaying,
           errorMessage == nil,
           hasCurrentSurface(generation: baselineSurfaceGeneration) {
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
        let generation = mediaPreparationGeneration
        let baselineSurfaceGeneration = surfaceAttachmentGeneration
        let signpostState = PlayerMetricsLog.beginSignpostedInterval(
            "PlayerStartupResume",
            message: "reason=deferredStartup target=\(String(format: "%.2f", resumeTime))"
        )
        deferredStartupResumeTask?.cancel()
        deferredStartupResumeTask = Task { @MainActor [weak self] in
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
                if self.mediaPreparationGeneration == generation {
                    self.deferredStartupResumeTask = nil
                }
                PlayerMetricsLog.endSignpostedInterval(
                    "PlayerStartupResume",
                    signpostState,
                    message: signpostMessage
                )
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled,
                  !self.isTerminated,
                  self.mediaPreparationGeneration == generation,
                  self.hasCurrentSurface(generation: baselineSurfaceGeneration),
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
            if self.wantsAutoplay,
               self.canActivatePlayback(generation: baselineSurfaceGeneration) {
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
        cancelStartupResumeRetryTask()
        let targetTime = resumeTime
        let retryGeneration = advanceStartupResumeRetryGeneration()
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
                      self.startupResumeRetryGeneration == retryGeneration,
                      self.canActivatePlayback()
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
                    self.clearStartupResumeRetryTaskIfCurrent(retryGeneration)
                    return
                }
                self.seekToStartupResumeTime(reason: "retry")
                if self.wantsAutoplay,
                   self.canActivatePlayback() {
                    self.engine.play()
                    self.engine.setPlaybackRate(self.playbackRate.rawValue)
                }
            }
            self?.clearStartupResumeRetryTaskIfCurrent(retryGeneration)
        }
    }

    @discardableResult
    private func seekToStartupResumeTime(reason: String) -> Bool {
        guard resumeTime > 0.25, engine.hasMedia else { return false }
        guard canActivatePlayback() else { return false }
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
        guard surfaceView != nil else {
            pendingEngineFirstFrameTime = max(time, 0)
            return
        }
        acceptEngineFirstFrame(time, source: "engine")
    }

    private func consumePendingEngineFirstFrameIfPossible() {
        guard let pendingEngineFirstFrameTime,
              !isTerminated,
              surfaceView != nil,
              engine.hasMedia,
              errorMessage == nil
        else { return }
        self.pendingEngineFirstFrameTime = nil
        acceptEngineFirstFrame(pendingEngineFirstFrameTime, source: "engine-deferred")
    }

    private func schedulePendingEngineFirstFrameConsumptionIfNeeded(generation: Int) {
        guard pendingEngineFirstFrameTime != nil else { return }
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                  !self.isTerminated,
                  self.hasCurrentSurface(generation: generation)
            else { return }
            self.consumePendingEngineFirstFrameIfPossible()
        }
    }

    private func schedulePlaybackActivationAfterSurfaceAttachIfNeeded(generation: Int) {
        guard wantsAutoplay else { return }
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                  !self.isTerminated,
                  self.hasCurrentSurface(generation: generation),
                  self.wantsAutoplay,
                  self.errorMessage == nil,
                  ActivePlaybackCoordinator.shared.isActive(self)
            else { return }
            if self.engine.hasMedia {
                self.startPreparedPlayback()
            } else {
                self.prepareMediaAndPlay()
            }
        }
    }

    private func acceptEngineFirstFrame(_ time: TimeInterval, source: String) {
        syncEngineDiagnostics(force: true)
        markPlaybackSurfaceReady()
        recordFirstFrameIfNeeded(currentTime: time, source: source)
        recordStartupResumeRecoveryIfNeeded(currentTime: time, source: source)
        recordSeekRecoveryIfNeeded(currentTime: time, source: source)
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
        if surfaceView == nil {
            currentPlaybackSurfaceReadyGeneration = nil
            isCurrentPlaybackSurfaceReadyForDisplay = false
        } else {
            currentPlaybackSurfaceReadyGeneration = surfaceAttachmentGeneration
            isCurrentPlaybackSurfaceReadyForDisplay = true
        }
        surfaceReadinessConfirmationTask?.cancel()
        surfaceReadinessConfirmationTask = nil
        hasPresentedPlayback = true
        if shouldNotifyFirstFrame {
            if startupMediaWarmupTask == nil {
                startStartupMediaWarmup(for: streamSourceForPreparation())
            }
            onFirstFramePresented?()
        }
        engine.setTemporaryAudioSuppressed(false)
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

    private func recordPlaybackFailure(message: String, reason: HLSBridgeFailureReason?) {
        errorMessage = message
        lastFailureReason = reason
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
            errorMessage = nil
            lastFailureReason = nil
            isPreparing = true
            isBuffering = false
            if !hasPresentedPlayback {
                isPlaybackSurfaceReady = false
                currentPlaybackSurfaceReadyGeneration = nil
                isCurrentPlaybackSurfaceReadyForDisplay = false
            }
            loadingProgress = max(loadingProgress, 0.18)
            playbackPhase = .preparing
        case .ready:
            cancelDeferredBufferingIndicator()
            isPreparing = false
            isBuffering = false
            loadingProgress = max(loadingProgress, 0.86)
            errorMessage = nil
            lastFailureReason = nil
            playbackPhase = hasPresentedPlayback ? .ready : .waitingForFirstFrame
            if wantsAutoplay {
                schedulePlaybackRecoveryWatchdog(reason: .firstFrame)
            }
        case .buffering:
            guard !isSurfaceMigrating else {
                isPreparing = false
                isBuffering = false
                isPlaying = true
                playbackPhase = .playing
                return
            }
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
            lastFailureReason = nil
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
            guard !isSurfaceMigrating else {
                isPreparing = false
                isBuffering = false
                isPlaying = wantsAutoplay
                playbackPhase = wantsAutoplay ? .playing : .paused
                return
            }
            if shouldPreservePlaybackDuringTransientSystemOverlay {
                cancelDeferredBufferingIndicator()
                isPreparing = false
                isBuffering = false
                isPlaying = true
                playbackPhase = .playing
                engine.play()
                return
            }
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
            recordPlaybackFailure(
                message: message ?? PlayerEngineError.unsupportedMedia.localizedDescription,
                reason: engine.lastFailureReason
            )
            playbackPhase = .failed(errorMessage)
            PlayerMetricsLog.record(.failed, metricsID: metricsID, title: title, message: errorMessage)
            onPlaybackFailureWithReason?(errorMessage, lastFailureReason)
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
        if !wantsPlayback, shouldPreservePlaybackDuringTransientSystemOverlay {
            wantsAutoplay = true
            if engine.hasMedia {
                engine.play()
            }
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

    private var shouldPreservePlaybackDuringTransientSystemOverlay: Bool {
        shouldResumeAfterTransientSystemOverlay
            && wantsAutoplay
            && UIApplication.shared.applicationState != .active
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
        let baselineSurfaceGeneration = surfaceAttachmentGeneration
        seekRecoveryWatchdogTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.seekRecoveryWatchdogDelayNanoseconds)
            guard !Task.isCancelled,
                  !self.isTerminated,
                  let pending = self.pendingSeekRecoveryMetric,
                  pending.id == metric.id,
                  self.hasCurrentSurface(generation: baselineSurfaceGeneration)
            else { return }
            let snapshot = self.engine.snapshot(durationHint: self.durationHint)
            if let snapshotTime = snapshot.currentTime,
               snapshot.isPlaying,
               self.isSeekRecoveryMatch(currentTime: snapshotTime, pending: pending),
               self.hasVisibleSeekRecoveryFrame(pending: pending, snapshot: snapshot) {
                self.finishSeekRecoveryMetric(
                    pending,
                    recovered: true,
                    currentTime: snapshot.renderedVideoTime ?? snapshotTime,
                    source: "watchdog"
                )
                return
            }
            if self.retryStalledSeekIfNeeded(
                pending: pending,
                snapshot: snapshot,
                baselineSurfaceGeneration: baselineSurfaceGeneration
            ) {
                return
            }
            if self.rebuildStalledSeekIfNeeded(
                pending: pending,
                snapshot: snapshot,
                baselineSurfaceGeneration: baselineSurfaceGeneration
            ) {
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
        let snapshot = engine.snapshot(durationHint: durationHint)
        guard hasVisibleSeekRecoveryFrame(pending: pending, snapshot: snapshot) else { return }
        finishSeekRecoveryMetric(
            pending,
            recovered: true,
            currentTime: snapshot.renderedVideoTime ?? currentTime,
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

    private func retryStalledSeekIfNeeded(
        pending: PendingSeekRecoveryMetric,
        snapshot: PlayerPlaybackSnapshot,
        baselineSurfaceGeneration: Int
    ) -> Bool {
        guard !pending.reason.contains("-recovery"),
              wantsAutoplay,
              errorMessage == nil,
              engine.hasMedia,
              hasCurrentSurface(generation: baselineSurfaceGeneration),
              canActivatePlayback(generation: baselineSurfaceGeneration)
        else { return false }

        let recoveryStart = CACurrentMediaTime()
        let resolvedTargetTime = pending.targetTime
            ?? snapshot.currentTime
            ?? (currentTime > 0 ? currentTime : nil)

        playbackPhase = .recovering
        isPreparing = false
        isBuffering = true
        loadingProgress = max(loadingProgress, 0.28)
        engine.recoverSurface()
        refreshSurfaceLayout()

        var appliedTargetTime = resolvedTargetTime
        if let resolvedTargetTime,
           let seekTime = engine.seek(toTime: resolvedTargetTime) {
            appliedTargetTime = seekTime
            _ = updatePlaybackTime(seekTime, force: true, countsAsNaturalPlayback: false)
        }

        engine.play()
        engine.setPlaybackRate(playbackRate.rawValue)
        schedulePlaybackRecoveryWatchdog(reason: .stall)

        let recoveryReason = "\(pending.reason)-recovery"
        let recoveryElapsedMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: recoveryStart)
        recordSeekTransition(
            reason: recoveryReason,
            targetTime: appliedTargetTime,
            targetProgress: pending.targetProgress,
            totalElapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: pending.startedAt),
            engineElapsedMilliseconds: recoveryElapsedMilliseconds
        )
        beginSeekRecoveryTracking(
            reason: recoveryReason,
            targetTime: appliedTargetTime,
            targetProgress: pending.targetProgress,
            startedAt: recoveryStart,
            engineElapsedMilliseconds: recoveryElapsedMilliseconds
        )
        return true
    }

    private func rebuildStalledSeekIfNeeded(
        pending: PendingSeekRecoveryMetric,
        snapshot: PlayerPlaybackSnapshot,
        baselineSurfaceGeneration: Int
    ) -> Bool {
        guard pending.reason.contains("-recovery"),
              !pending.reason.contains("-rebuild"),
              wantsAutoplay,
              errorMessage == nil,
              mediaPreparationTask == nil,
              hasCurrentSurface(generation: baselineSurfaceGeneration),
              canActivatePlayback(generation: baselineSurfaceGeneration),
              ActivePlaybackCoordinator.shared.isActive(self)
        else { return false }

        let rebuildStart = CACurrentMediaTime()
        let resolvedTargetTime = pending.targetTime
            ?? snapshot.currentTime
            ?? (currentTime > 0 ? currentTime : nil)
        let preparationSource = seekRecoveryPreparationSource(targetTime: resolvedTargetTime)

        playbackPhase = .recovering
        isPreparing = true
        isBuffering = true
        loadingProgress = max(loadingProgress, 0.18)
        pendingEngineFirstFrameTime = nil
        if let resolvedTargetTime {
            _ = updatePlaybackTime(resolvedTargetTime, force: true, countsAsNaturalPlayback: false)
        }
        PlayerMetricsLog.record(
            .playbackRecovery,
            metricsID: metricsID,
            title: title,
            message: "stage=mediaRebuild status=started reason=\(pending.reason) target=\(String(format: "%.2fs", resolvedTargetTime ?? currentTime))"
        )

        mediaPreparationGeneration &+= 1
        let preparationGeneration = mediaPreparationGeneration
        startStartupMediaWarmup(for: preparationSource)
        mediaPreparationTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try await self.engine.prepare(source: preparationSource)
                guard !Task.isCancelled,
                      !self.isTerminated,
                      preparationGeneration == self.mediaPreparationGeneration,
                      self.hasCurrentSurface(generation: baselineSurfaceGeneration),
                      ActivePlaybackCoordinator.shared.isActive(self)
                else {
                    self.clearMediaPreparationTaskIfCurrent(preparationGeneration)
                    return
                }

                self.clearMediaPreparationTaskIfCurrent(preparationGeneration)
                var appliedTargetTime = resolvedTargetTime
                if let resolvedTargetTime,
                   let seekTime = self.engine.seek(toTime: resolvedTargetTime) {
                    appliedTargetTime = seekTime
                    self.updatePlaybackTime(seekTime, force: true, countsAsNaturalPlayback: false)
                }

                let rebuildReason = "\(pending.reason)-rebuild"
                let rebuildElapsedMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: rebuildStart)
                self.recordSeekTransition(
                    reason: rebuildReason,
                    targetTime: appliedTargetTime,
                    targetProgress: pending.targetProgress,
                    totalElapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: pending.startedAt),
                    engineElapsedMilliseconds: rebuildElapsedMilliseconds
                )
                self.beginSeekRecoveryTracking(
                    reason: rebuildReason,
                    targetTime: appliedTargetTime,
                    targetProgress: pending.targetProgress,
                    startedAt: rebuildStart,
                    engineElapsedMilliseconds: rebuildElapsedMilliseconds
                )

                if self.wantsAutoplay {
                    self.startPreparedPlayback()
                } else {
                    self.isPreparing = false
                    self.refreshPlaybackState()
                }
            } catch {
                guard !Task.isCancelled,
                      !self.isTerminated,
                      preparationGeneration == self.mediaPreparationGeneration,
                      self.hasCurrentSurface(generation: baselineSurfaceGeneration),
                      ActivePlaybackCoordinator.shared.isActive(self)
                else {
                    self.clearMediaPreparationTaskIfCurrent(preparationGeneration)
                    return
                }

                self.clearMediaPreparationTaskIfCurrent(preparationGeneration)
                self.finishSeekRecoveryMetric(
                    pending,
                    recovered: false,
                    currentTime: resolvedTargetTime ?? snapshot.currentTime ?? self.currentTime,
                    source: "rebuild"
                )
                self.recordPlaybackFailure(message: error.localizedDescription, reason: self.engine.lastFailureReason)
                self.isPreparing = false
                self.onPlaybackFailureWithReason?(self.errorMessage, self.lastFailureReason)
                self.onPlaybackFailure?(self.errorMessage)
            }
        }
        return true
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

    @discardableResult
    private func advanceStartupResumeRetryGeneration() -> Int {
        startupResumeRetryGeneration &+= 1
        return startupResumeRetryGeneration
    }

    private func cancelStartupResumeRetryTask() {
        startupResumeRetryTask?.cancel()
        startupResumeRetryTask = nil
        advanceStartupResumeRetryGeneration()
    }

    private func clearStartupResumeRetryTaskIfCurrent(_ generation: Int) {
        guard startupResumeRetryGeneration == generation else { return }
        startupResumeRetryTask = nil
    }

    @discardableResult
    private func advancePictureInPictureStartRetryGeneration() -> Int {
        pictureInPictureStartRetryGeneration &+= 1
        return pictureInPictureStartRetryGeneration
    }

    private func cancelPictureInPictureStartRetryTask() {
        pictureInPictureStartRetryTask?.cancel()
        pictureInPictureStartRetryTask = nil
        advancePictureInPictureStartRetryGeneration()
    }

    private func clearPictureInPictureStartRetryTaskIfCurrent(_ generation: Int) {
        guard pictureInPictureStartRetryGeneration == generation else { return }
        pictureInPictureStartRetryTask = nil
    }

    private func scheduleScrubSeekUIReleaseIfNeeded(
        generation: Int,
        targetTime: TimeInterval?,
        targetProgress: Double,
        startedAt: CFTimeInterval
    ) {
        scrubSeekUIReleaseTask?.cancel()
        let baselineSurfaceGeneration = surfaceAttachmentGeneration
        scrubSeekUIReleaseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: self?.seekUIReleaseDelayNanoseconds ?? 1_150_000_000)
            guard let self,
                  !Task.isCancelled,
                  !self.isTerminated,
                  self.scrubSeekGeneration == generation,
                  self.hasCurrentSurface(generation: baselineSurfaceGeneration),
                  self.isUserSeeking
            else { return }

            self.isUserSeeking = false
            self.playbackRecoveryWatchdogTask?.cancel()
            self.playbackRecoveryWatchdogTask = nil
            if self.wantsAutoplay,
               self.canActivatePlayback(generation: baselineSurfaceGeneration) {
                self.engine.recoverSurface()
                self.refreshSurfaceLayout()
                self.engine.play()
                self.engine.setPlaybackRate(self.playbackRate.rawValue)
            }
            if self.hasPresentedPlayback {
                self.isBuffering = self.wantsAutoplay
                self.playbackPhase = self.wantsAutoplay ? .buffering : .paused
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
              canActivatePlayback(),
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
            guard canActivatePlayback() else { return }
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
        let taskID = UUID()
        let task = Task { [weak self] in
            guard !Task.isCancelled else { return }
            await onSponsorBlockSegmentSkipped(event)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      !self.isTerminated
                else { return }
                self.sponsorBlockSkipReportTasks[taskID] = nil
            }
        }
        sponsorBlockSkipReportTasks[taskID] = task
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

private extension UIImage {
    var biliLooksLikeBlackFrame: Bool {
        guard let cgImage else { return false }
        let width = 8
        let height = 8
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return false
        }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var brightPixelCount = 0
        var lumaSum = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Int(pixels[index])
            let green = Int(pixels[index + 1])
            let blue = Int(pixels[index + 2])
            let luma = (red * 299 + green * 587 + blue * 114) / 1000
            lumaSum += luma
            if luma > 18 {
                brightPixelCount += 1
            }
        }

        let averageLuma = Double(lumaSum) / Double(width * height)
        return averageLuma < 10 && brightPixelCount <= 1
    }
}

extension PlayerStateViewModel: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in
            guard let self, !self.isTerminated else { return }
            self.isPictureInPictureActive = true
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in
            guard let self, !self.isTerminated else { return }
            self.isPictureInPictureActive = false
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        Task { @MainActor [weak self] in
            guard let self, !self.isTerminated else {
                completionHandler(false)
                return
            }
            self.isPictureInPictureActive = false
            let didRestore = await self.restoreUserInterfaceForPictureInPictureStop?() ?? true
            completionHandler(didRestore)
        }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, !self.isTerminated else { return }
            self.isPictureInPictureActive = false
            self.errorMessage = "画中画启动失败：\(error.localizedDescription)"
        }
    }
}
