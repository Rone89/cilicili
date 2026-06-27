import AVFoundation
import AVKit
import CoreImage
import Network
import OSLog
import SwiftUI
import UIKit

@MainActor
final class AVPlayerHLSBridgeEngine: PlayerRenderingEngine {
    private static let interactiveSeekTolerance = CMTime(seconds: 0.35, preferredTimescale: 600)
    private static let terminalStallDelayNanoseconds: UInt64 = 14_000_000_000
    private static let itemReadinessTimeoutNanoseconds: UInt64 = 14_000_000_000
    private static let itemReadinessPollNanoseconds: UInt64 = 50_000_000
    private static let loadedRangeContinuityTolerance: TimeInterval = 0.12

    private enum PrepareReadinessError: LocalizedError {
        case itemFailed(String?)
        case timedOut

        var errorDescription: String? {
            switch self {
            case .itemFailed(let message):
                message ?? PlayerEngineError.unsupportedMedia.localizedDescription
            case .timedOut:
                "AVPlayer 等待媒体就绪超时"
            }
        }
    }

    private let player = AVPlayer()
    private var backgroundObserver: Any?
    private var foregroundObserver: Any?
    private var itemEndObserver: Any?
    private var itemFailedObserver: Any?
    private var itemStalledObserver: Any?
    private var itemAccessLogObserver: Any?
    private var playerObservers: [NSKeyValueObservation] = []
    private var itemObservers: [NSKeyValueObservation] = []
    private var layerReadyForDisplayObserver: NSKeyValueObservation?
    private var controllerReadyForDisplayObserver: NSKeyValueObservation?
    private var periodicTimeObserver: Any?
    private let videoFrameContext = CIContext()
    private weak var surfaceView: UIView?
    private var playerLayer: AVPlayerLayer?
    private weak var playerViewController: AVPlayerViewController?
    private var playerItem: AVPlayerItem?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var lastVideoFrameImage: UIImage?
    private var source: PlayerStreamSource?
    private var hlsBridge: LocalHLSBridge?
    private var liveHLSProxy: LocalLiveHLSProxy?
    private var mediaTimeOffset: TimeInterval = 0
    private var retainedAssets: [AVAsset] = []
    private var currentRate: Float = 1
    private var wantsPlayback = false
    private var didReportFirstFrame = false
    private var lastPlaybackState: PlayerEnginePlaybackState = .idle
    private var videoGravity: AVLayerVideoGravity = .resizeAspect
    private var isDirectLiveHLS = false
    private var didSeekDirectLiveHLS = false
    private var isPerformingSeek = false
    private var seekGeneration = 0
    private var isSeekProtectionActive = false
    private var seekProtectionReleaseTask: Task<Void, Never>?
    private var seekProtectionTargetTime: TimeInterval?
    private var seekProtectionAppliedAt: CFTimeInterval?
    private var startupBitRateLiftTask: Task<Void, Never>?
    private var terminalStallTask: Task<Void, Never>?
    private var terminalStallGeneration = 0
    private var didLiftStartupBitRate = false
    private var isStartupFastStartActive = false
    private var manualPreferredPeakBitRate: Double?
    private var lastRecordedAccessLogStallCount = 0
    private var lastPlaybackFailureReason: HLSBridgeFailureReason?
    private var playbackGeneration = 0
    private var playbackFailureRecoveryAttempts: [String: Int] = [:]
    private var isPlaybackFailureRecoveryInProgress = false
    private var isStopped = true
    private var targetVolume: Float = 1
    private var targetMuted = false
    private var isPictureInPictureEnabled = false
    private var contentOverlay: AnyView?
    private var contentOverlayHostingController: UIHostingController<AnyView>?
    private weak var contentOverlayContainerView: UIView?
    private weak var viewModel: PlayerStateViewModel?
    private var pendingSurfaceDetachTask: Task<Void, Never>?

    var hasMedia: Bool {
        !isStopped && player.currentItem != nil
    }

    var needsMediaRecovery: Bool {
        guard let item = player.currentItem else { return false }
        return item.status == .failed
    }

    var playbackErrorMessage: String? {
        player.currentItem?.error?.localizedDescription
    }

    var lastFailureReason: HLSBridgeFailureReason? {
        lastPlaybackFailureReason
    }

    var supportsPictureInPicture: Bool {
        false
    }

    var isPictureInPictureActive: Bool {
        false
    }

    var usesNativePlaybackControls: Bool {
        true
    }

    var diagnostics: PlayerEngineDiagnostics {
        PlayerEngineDiagnostics(
            engineName: "AVPlayer",
            decodePath: .avPlayer,
            codec: source?.videoStream?.codecLabel,
            resolution: source?.videoStream?.resolutionLabel,
            frameRate: source?.videoStream?.displayFrameRate,
            bandwidth: source?.videoStream?.bandwidth,
            dynamicRange: source?.dynamicRange ?? .sdr,
            isDASH: source?.audioURL != nil,
            usesLocalHLSBridge: hlsBridge != nil || liveHLSProxy != nil,
            hlsVideoVariantCount: hlsBridge?.videoVariantCount ?? 0,
            hlsVideoVariantQualities: hlsBridge?.videoVariantQualities ?? [],
            preferredForwardBufferDuration: player.currentItem?.preferredForwardBufferDuration,
            maxBufferDuration: nil,
            asynchronousDecompressionEnabled: false,
            hardwareDecodeRequested: true,
            environmentSummary: PlaybackEnvironment.current.diagnosticSummary
        )
    }

    var volume: Float {
        targetVolume
    }

    var isMuted: Bool {
        targetMuted
    }

    var onPlaybackStateChange: (@MainActor (PlayerEnginePlaybackState) -> Void)?
    var onPlaybackIntentChange: (@MainActor (Bool) -> Void)?
    var onLoadingProgressChange: (@MainActor (Double) -> Void)?
    var onFirstFrame: (@MainActor (TimeInterval) -> Void)?

    init() {
        configureAudioSession()
        observePlayerState()
        observeAppLifecycle()
    }

    deinit {
        pendingSurfaceDetachTask?.cancel()
        itemObservers.removeAll()
        layerReadyForDisplayObserver = nil
        controllerReadyForDisplayObserver = nil
        if let itemEndObserver {
            NotificationCenter.default.removeObserver(itemEndObserver)
        }
        if let itemFailedObserver {
            NotificationCenter.default.removeObserver(itemFailedObserver)
        }
        if let itemStalledObserver {
            NotificationCenter.default.removeObserver(itemStalledObserver)
        }
        if let itemAccessLogObserver {
            NotificationCenter.default.removeObserver(itemAccessLogObserver)
        }
        if let periodicTimeObserver {
            player.removeTimeObserver(periodicTimeObserver)
        }
        seekProtectionReleaseTask?.cancel()
        startupBitRateLiftTask?.cancel()
        terminalStallTask?.cancel()
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
    }

    func attachSurface(_ surface: UIView) {
        pendingSurfaceDetachTask?.cancel()
        pendingSurfaceDetachTask = nil
        surfaceView = surface
        if let playerViewController {
            configureNativePlaybackController(playerViewController)
            removePlayerLayer()
        } else {
            let layer = ensurePlayerLayer(in: surface)
            layer.player = player
        }
        refreshSurfaceLayout()
    }

    func detachSurface(_ surface: UIView) {
        guard surfaceView === surface else { return }
        pendingSurfaceDetachTask?.cancel()
        let detachedSurface = surface
        pendingSurfaceDetachTask = Task { @MainActor [weak self, weak detachedSurface] in
            await Task.yield()
            guard let self,
                  !Task.isCancelled,
                  self.surfaceView == nil || self.surfaceView === detachedSurface
            else { return }
            self.removePlayerLayer()
            self.pendingSurfaceDetachTask = nil
        }
        surfaceView = nil
    }

    func refreshSurfaceLayout() {
        guard !isStopped else { return }
        AVPlayerLayoutCoordinator.shared.apply(
            playerLayer: playerLayer,
            in: surfaceView,
            gravity: videoGravity
        )
    }

    func recoverSurface() {
        guard !isStopped else { return }
        configureAudioSession()
        if let playerViewController {
            configureNativePlaybackController(playerViewController)
            return
        }
        guard let surfaceView else { return }
        let layer = ensurePlayerLayer(in: surfaceView)
        layer.player = nil
        layer.player = player
        layer.isHidden = false
        layer.opacity = 1
        refreshSurfaceLayout()
        layer.setNeedsLayout()
        layer.setNeedsDisplay()
    }

    func setViewModel(_ viewModel: PlayerStateViewModel?) {
        self.viewModel = viewModel
    }

    func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        guard videoGravity != gravity else { return }
        videoGravity = gravity
        playerViewController?.videoGravity = gravity
        playerLayer?.videoGravity = gravity
    }

    func setContentOverlay(_ overlay: AnyView?) {
        contentOverlay = overlay
        installContentOverlayIfPossible()
    }

    func attachNativePlaybackController(_ controller: AVPlayerViewController) {
        if let playerViewController, playerViewController !== controller {
            playerViewController.player = nil
            controllerReadyForDisplayObserver = nil
        }
        playerViewController = controller
        configureNativePlaybackController(controller)
        installContentOverlayIfPossible()
        removePlayerLayer()
    }

    func setPictureInPictureEnabled(_ isEnabled: Bool) {
        isPictureInPictureEnabled = isEnabled
        if let playerViewController {
            configureNativePlaybackController(playerViewController)
        }
    }

    func detachNativePlaybackController(_ controller: AVPlayerViewController) {
        guard playerViewController === controller else { return }
        removeContentOverlayHostingController()
        controller.player = nil
        controllerReadyForDisplayObserver = nil
        playerViewController = nil
    }

    func prepare(source: PlayerStreamSource) async throws {
        let prepareStart = CACurrentMediaTime()
        let signpostState = PlayerMetricsLog.beginSignpostedInterval(
            "AVPlayerBridgePrepare",
            message: "id=\(source.metricsID) dash=\(source.audioURL != nil)"
        )
        var signpostMessage = "id=\(source.metricsID) preparing"
        defer {
            PlayerMetricsLog.endSignpostedInterval(
                "AVPlayerBridgePrepare",
                signpostState,
                message: signpostMessage
            )
        }
        playbackGeneration &+= 1
        let generation = playbackGeneration
        isStopped = false
        tearDownCurrentItemForReplacement()
        self.source = source
        let recoveryKey = playbackFailureRecoveryKey(for: source)
        if !isPlaybackFailureRecoveryInProgress {
            playbackFailureRecoveryAttempts[recoveryKey] = 0
        }
        wantsPlayback = false
        didReportFirstFrame = false
        didSeekDirectLiveHLS = false
        didLiftStartupBitRate = false
        isStartupFastStartActive = false
        manualPreferredPeakBitRate = nil
        lastRecordedAccessLogStallCount = 0
        lastPlaybackFailureReason = nil
        isSeekProtectionActive = false
        seekProtectionReleaseTask?.cancel()
        seekProtectionReleaseTask = nil
        seekProtectionTargetTime = nil
        seekProtectionAppliedAt = nil
        startupBitRateLiftTask?.cancel()
        startupBitRateLiftTask = nil
        configureAudioSession()
        applyTargetAudioState()
        onLoadingProgressChange?(0.18)
        recordPrepareStage(source: source, stage: "start", startedAt: prepareStart)
        publishPlaybackState(.preparing)
        let prepared: PreparedPlayerItem
        do {
            prepared = try await Self.makePlayerItem(source: source)
        } catch {
            lastPlaybackFailureReason = prepareFailureReason(for: error, source: source)
            throw error
        }
        guard !Task.isCancelled, isCurrentPlaybackGeneration(generation) else {
            discardPreparedPlayerItem(prepared)
            signpostMessage = "id=\(source.metricsID) cancelled"
            return
        }
        onLoadingProgressChange?(0.58)
        recordPrepareStage(
            source: source,
            stage: "item",
            startedAt: prepareStart,
            extra: "directLive=\(prepared.isDirectLiveHLS) bridge=\(prepared.bridge != nil) assets=\(prepared.assets.count)"
        )
        removeCurrentItemObservers()
        playerItem = prepared.item
        hlsBridge = prepared.bridge
        liveHLSProxy = prepared.liveProxy
        mediaTimeOffset = prepared.bridge?.mediaTimeOffset ?? 0
        retainedAssets = prepared.assets
        isDirectLiveHLS = prepared.isDirectLiveHLS
        isStartupFastStartActive = !prepared.isDirectLiveHLS
        let item = prepared.item
        configureStartupBuffering(for: item, source: source)
        attachVideoOutput(to: item)
        player.replaceCurrentItem(with: item)
        recordPrepareStage(
            source: source,
            stage: "installed",
            startedAt: prepareStart,
            extra: "buffer=\(String(format: "%.2f", item.preferredForwardBufferDuration))s peak=\(Int(item.preferredPeakBitRate.rounded())) fastStart=\(isStartupFastStartActive)"
        )
        player.automaticallyWaitsToMinimizeStalling = false
        ensurePeriodicTimeObserver()
        if let playerViewController {
            configureNativePlaybackController(playerViewController)
        } else if let surfaceView {
            ensurePlayerLayer(in: surfaceView).player = player
            refreshSurfaceLayout()
        }
        onLoadingProgressChange?(0.68)
        do {
            try await waitForCurrentItemReadyToPlay(item, generation: generation)
        } catch {
            if isCurrentPlayerItem(item), isCurrentPlaybackGeneration(generation) {
                tearDownCurrentItemForReplacement()
            }
            signpostMessage = "id=\(source.metricsID) failed \(error.localizedDescription)"
            throw error
        }
        guard !Task.isCancelled, isCurrentPlaybackGeneration(generation), isCurrentPlayerItem(item) else {
            signpostMessage = "id=\(source.metricsID) cancelled"
            return
        }
        observeCurrentItem(item)
        onLoadingProgressChange?(0.86)
        handleCurrentItemReadyToPlay(item)
        signpostMessage = "id=\(source.metricsID) ready elapsed=\(String(format: "%.1f", PlayerMetricsLog.elapsedMilliseconds(since: prepareStart)))ms"
        recordPrepareStage(source: source, stage: "ready", startedAt: prepareStart)
    }

    func play() {
        guard !isStopped, let item = player.currentItem else { return }
        configureAudioSession()
        applyTargetAudioState()
        wantsPlayback = true
        guard item.status == .readyToPlay else {
            onLoadingProgressChange?(0.72)
            publishPlaybackState(.buffering)
            return
        }
        beginPlayback()
        scheduleTerminalStallWatchdog(reason: "play")
        let currentTime = displayTime(fromPlayerTime: player.currentTime().seconds)
        if player.rate > 0 || player.timeControlStatus == .playing {
            onLoadingProgressChange?(0.98)
            publishPlaybackState(.playing)
        } else {
            onLoadingProgressChange?(0.86)
            publishPlaybackState(.buffering)
        }
        reportFirstFrameIfPossible(currentTime: currentTime)
    }

    func pause() {
        guard !isStopped else { return }
        wantsPlayback = false
        cancelTerminalStallWatchdog()
        player.pause()
        publishPlaybackState(.paused)
    }

    func pauseForNavigation() {
        guard !isStopped else { return }
        wantsPlayback = false
        cancelTerminalStallWatchdog()
        player.rate = 0
        player.pause()
        player.currentItem?.cancelPendingSeeks()
        player.cancelPendingPrerolls()
        publishPlaybackState(.paused)
    }

    func suspendForNavigation() {
        guard !isStopped else { return }
        wantsPlayback = false
        cancelTerminalStallWatchdog()
        silencePlayerImmediately()
        player.currentItem?.cancelPendingSeeks()
        publishPlaybackState(.paused)
    }

    func stop() {
        playbackGeneration &+= 1
        isStopped = true
        wantsPlayback = false
        cancelTerminalStallWatchdog()
        pendingSurfaceDetachTask?.cancel()
        pendingSurfaceDetachTask = nil
        isPlaybackFailureRecoveryInProgress = false
        tearDownCurrentItemForReplacement()
        source = nil
        removePlayerLayer()
        playerViewController?.player = nil
        setContentOverlay(nil)
        layerReadyForDisplayObserver = nil
        deactivateAudioSessionIfPossible()
        publishPlaybackState(.idle)
    }

    func setPlaybackRate(_ rate: Double) {
        let normalizedRate = max(Float(rate), 0.1)
        guard abs(currentRate - normalizedRate) > 0.001 else { return }
        currentRate = normalizedRate
        player.defaultRate = normalizedRate
        applyRateAwareBuffering()
        applyRateAwareAudioPitchAlgorithm()
        if player.rate > 0 {
            player.rate = currentRate
        }
    }

    func setPreferredPeakBitRate(_ bitRate: Double?) {
        guard !isDirectLiveHLS else { return }
        startupBitRateLiftTask?.cancel()
        startupBitRateLiftTask = nil
        manualPreferredPeakBitRate = bitRate
        if let bitRate, let item = player.currentItem {
            item.preferredPeakBitRate = bitRate
        } else if let item = player.currentItem, let source {
            configureStartupBuffering(for: item, source: source)
            applyRateAwareBuffering()
        }
    }

    func setVolume(_ volume: Float) {
        targetVolume = min(max(volume, 0), 1)
        player.volume = targetVolume
    }

    func setMuted(_ isMuted: Bool) {
        targetMuted = isMuted
        player.isMuted = targetMuted
    }

    func setTemporaryAudioSuppressed(_ isSuppressed: Bool) {
        if isSuppressed {
            player.isMuted = true
            player.volume = 0
        } else {
            applyTargetAudioState()
        }
    }

    func seek(toTime time: TimeInterval) -> TimeInterval? {
        guard !isStopped, player.currentItem != nil else { return nil }
        let target = playerTime(fromDisplayTime: max(time, 0))
        let displayTarget = displayTime(fromPlayerTime: target)
        let seekPlaybackGeneration = playbackGeneration
        let generation = beginSeekTransaction(targetDisplayTime: displayTarget)
        if wantsPlayback || isPerformingSeek {
            publishPlaybackState(.buffering)
        }
        warmSeekTargetIfNeeded(displayTarget)
        player.currentItem?.cancelPendingSeeks()
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self,
                      self.isCurrentPlaybackGeneration(seekPlaybackGeneration)
                else { return }
                self.finishSeekTransaction(generation: generation, finished: finished, shouldResume: self.wantsPlayback)
            }
        }
        return displayTarget
    }

    func seek(toProgress progress: Double, duration: TimeInterval?) -> TimeInterval? {
        guard !isStopped, player.currentItem != nil else { return nil }
        let resolvedDuration = resolvedDuration(durationHint: duration)
        guard resolvedDuration > 0 else { return nil }
        let displayTarget = alignedInteractiveSeekTime(
            min(max(progress, 0), 1) * resolvedDuration
        )
        let target = playerTime(fromDisplayTime: displayTarget)
        let seekPlaybackGeneration = playbackGeneration
        let generation = beginSeekTransaction(targetDisplayTime: displayTarget)
        if wantsPlayback || isPerformingSeek {
            publishPlaybackState(.buffering)
        }
        warmSeekTargetIfNeeded(displayTarget)
        let targetTime = CMTime(seconds: target, preferredTimescale: 600)
        player.currentItem?.cancelPendingSeeks()
        player.seek(
            to: targetTime,
            toleranceBefore: Self.interactiveSeekTolerance,
            toleranceAfter: Self.interactiveSeekTolerance
        ) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self,
                      self.isCurrentPlaybackGeneration(seekPlaybackGeneration)
                else { return }
                self.finishSeekTransaction(generation: generation, finished: finished, shouldResume: self.wantsPlayback)
            }
        }
        return displayTarget
    }

    func seek(by interval: TimeInterval, from currentTime: TimeInterval, duration: TimeInterval?) -> TimeInterval? {
        guard !isStopped, player.currentItem != nil else { return nil }
        let resolvedDuration = resolvedDuration(durationHint: duration)
        let target = resolvedDuration > 0
            ? min(max(currentTime + interval, 0), resolvedDuration)
            : max(currentTime + interval, 0)
        let playerTarget = playerTime(fromDisplayTime: target)
        let displayTarget = alignedInteractiveSeekTime(displayTime(fromPlayerTime: playerTarget))
        let alignedPlayerTarget = playerTime(fromDisplayTime: displayTarget)
        let seekPlaybackGeneration = playbackGeneration
        let generation = beginSeekTransaction(targetDisplayTime: displayTarget)
        if wantsPlayback || isPerformingSeek {
            publishPlaybackState(.buffering)
        }
        warmSeekTargetIfNeeded(displayTarget)
        let targetTime = CMTime(seconds: alignedPlayerTarget, preferredTimescale: 600)
        player.currentItem?.cancelPendingSeeks()
        player.seek(
            to: targetTime,
            toleranceBefore: CMTime(seconds: 0.35, preferredTimescale: 600),
            toleranceAfter: CMTime(seconds: 0.35, preferredTimescale: 600)
        ) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self,
                      self.isCurrentPlaybackGeneration(seekPlaybackGeneration)
                else { return }
                self.finishSeekTransaction(generation: generation, finished: finished, shouldResume: self.wantsPlayback)
            }
        }
        return displayTarget
    }

    func seekAfterUserScrub(toProgress progress: Double, duration: TimeInterval?) async -> TimeInterval? {
        guard !isStopped, player.currentItem != nil else { return nil }
        let resolvedDuration = resolvedDuration(durationHint: duration)
        guard resolvedDuration > 0 else { return nil }
        let displayTarget = alignedInteractiveSeekTime(
            min(max(progress, 0), 1) * resolvedDuration
        )
        let target = playerTime(fromDisplayTime: displayTarget)
        let targetTime = CMTime(seconds: target, preferredTimescale: 600)
        wantsPlayback = true
        let seekPlaybackGeneration = playbackGeneration
        let generation = beginSeekTransaction(targetDisplayTime: displayTarget)
        publishPlaybackState(.buffering)
        warmSeekTargetIfNeeded(displayTarget)
        player.currentItem?.cancelPendingSeeks()
        let finished = await withCheckedContinuation { continuation in
            player.seek(to: targetTime, toleranceBefore: Self.interactiveSeekTolerance, toleranceAfter: Self.interactiveSeekTolerance) { finished in
                continuation.resume(returning: finished)
            }
        }
        guard isCurrentPlaybackGeneration(seekPlaybackGeneration) else { return nil }
        finishSeekTransaction(generation: generation, finished: finished, shouldResume: wantsPlayback)
        return finished ? displayTarget : nil
    }

    func snapshot(durationHint: TimeInterval?) -> PlayerPlaybackSnapshot {
        let currentSeconds = displayTime(fromPlayerTime: player.currentTime().seconds)
        let durationSeconds = resolvedDuration(durationHint: durationHint)
        let item = player.currentItem
        let status = item?.status
        return PlayerPlaybackSnapshot(
            currentTime: currentSeconds.isFinite && currentSeconds >= 0 ? currentSeconds : nil,
            renderedVideoTime: (isPerformingSeek || isSeekProtectionActive) ? currentRenderedVideoTime() : nil,
            duration: durationSeconds > 0 ? durationSeconds : durationHint,
            isPlaying: player.rate > 0,
            isSeekable: status == .readyToPlay || (durationHint ?? 0) > 0,
            bufferedRanges: item.map(bufferedRanges(for:)) ?? []
        )
    }

    func currentVideoFrameImage() -> UIImage? {
        guard let videoOutput,
              player.currentItem === playerItem
        else { return lastVideoFrameImage }

        let hostTime = CACurrentMediaTime()
        let hostItemTime = videoOutput.itemTime(forHostTime: hostTime)
        var displayTime = CMTime.invalid
        if let pixelBuffer = videoOutput.copyPixelBuffer(
            forItemTime: hostItemTime,
            itemTimeForDisplay: &displayTime
        ) {
            return cacheVideoFrameImage(from: pixelBuffer)
        }

        let currentItemTime = player.currentTime()
        guard let pixelBuffer = videoOutput.copyPixelBuffer(
            forItemTime: currentItemTime,
            itemTimeForDisplay: nil
        ) else {
            return lastVideoFrameImage
        }
        return cacheVideoFrameImage(from: pixelBuffer)
    }

    private func currentRenderedVideoTime() -> TimeInterval? {
        guard let videoOutput,
              player.currentItem === playerItem
        else { return nil }

        let hostItemTime = videoOutput.itemTime(forHostTime: CACurrentMediaTime())
        var itemDisplayTime = CMTime.invalid
        guard let pixelBuffer = videoOutput.copyPixelBuffer(
            forItemTime: hostItemTime,
            itemTimeForDisplay: &itemDisplayTime
        ) else {
            return nil
        }

        _ = cacheVideoFrameImage(from: pixelBuffer)
        let playerTime = itemDisplayTime.isValid && itemDisplayTime.seconds.isFinite
            ? itemDisplayTime.seconds
            : hostItemTime.seconds
        let renderedTime = displayTime(fromPlayerTime: playerTime)
        guard renderedTime.isFinite, renderedTime >= 0 else { return nil }
        return renderedTime
    }

    func currentSurfaceSnapshotImage() -> UIImage? {
        surfaceView?.biliRenderedSnapshotImage()
    }

    func pictureInPictureContentSource() -> AVPictureInPictureController.ContentSource? {
        guard let playerLayer else { return nil }
        return AVPictureInPictureController.ContentSource(playerLayer: playerLayer)
    }

    func togglePictureInPicture() {}

    func invalidatePictureInPicturePlaybackState() {}

    private func beginPlayback() {
        guard !isStopped, player.currentItem != nil else { return }
        applyTargetAudioState()
        if isDirectLiveHLS {
            player.play()
        } else {
            player.playImmediately(atRate: currentRate)
        }
    }

    private func applyTargetAudioState() {
        player.volume = targetVolume
        player.isMuted = targetMuted
    }

    private func silencePlayerImmediately() {
        player.isMuted = true
        player.volume = 0
        player.rate = 0
        player.pause()
        player.cancelPendingPrerolls()
    }

    private func tearDownCurrentItemForReplacement() {
        let oldItem = player.currentItem
        let oldBridge = hlsBridge
        let oldLiveProxy = liveHLSProxy
        silencePlayerImmediately()
        oldItem?.cancelPendingSeeks()
        oldItem?.asset.cancelLoading()
        if let videoOutput {
            oldItem?.remove(videoOutput)
        }
        videoOutput = nil
        lastVideoFrameImage = nil
        removeCurrentItemObservers()
        removePeriodicTimeObserver()
        if oldItem != nil {
            player.replaceCurrentItem(with: nil)
        }
        oldBridge?.stop()
        oldLiveProxy?.stop()
        playerItem = nil
        hlsBridge = nil
        liveHLSProxy = nil
        mediaTimeOffset = 0
        retainedAssets = []
        isDirectLiveHLS = false
        didSeekDirectLiveHLS = false
        didReportFirstFrame = false
        isPerformingSeek = false
        seekGeneration &+= 1
        isSeekProtectionActive = false
        seekProtectionReleaseTask?.cancel()
        seekProtectionReleaseTask = nil
        seekProtectionTargetTime = nil
        seekProtectionAppliedAt = nil
        startupBitRateLiftTask?.cancel()
        startupBitRateLiftTask = nil
        cancelTerminalStallWatchdog()
        didLiftStartupBitRate = false
        isStartupFastStartActive = false
        manualPreferredPeakBitRate = nil
        lastRecordedAccessLogStallCount = 0
    }

    private func attachVideoOutput(to item: AVPlayerItem) {
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        output.suppressesPlayerRendering = false
        item.add(output)
        videoOutput = output
    }

    private func makeImage(from pixelBuffer: CVPixelBuffer) -> UIImage? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        guard let cgImage = videoFrameContext.createCGImage(ciImage, from: rect) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func cacheVideoFrameImage(from pixelBuffer: CVPixelBuffer) -> UIImage? {
        guard let image = makeImage(from: pixelBuffer) else { return lastVideoFrameImage }
        lastVideoFrameImage = image
        return image
    }

    private func isCurrentPlaybackGeneration(_ generation: Int) -> Bool {
        !isStopped && generation == playbackGeneration
    }

    private func isCurrentPlayerItem(_ item: AVPlayerItem) -> Bool {
        !isStopped && player.currentItem === item && playerItem === item
    }

    private func waitForCurrentItemReadyToPlay(_ item: AVPlayerItem, generation: Int) async throws {
        let startedAt = CACurrentMediaTime()
        let timeoutSeconds = TimeInterval(Self.itemReadinessTimeoutNanoseconds) / 1_000_000_000
        while true {
            try Task.checkCancellation()
            guard isCurrentPlaybackGeneration(generation), isCurrentPlayerItem(item) else {
                throw CancellationError()
            }
            switch item.status {
            case .readyToPlay:
                return
            case .failed:
                logPlayerItemFailure(item)
                lastPlaybackFailureReason = playbackFailureReason(
                    for: item,
                    fallback: item.error?.localizedDescription
                )
                throw PrepareReadinessError.itemFailed(
                    normalizedPlaybackFailureMessage(for: item, fallback: item.error?.localizedDescription)
                )
            case .unknown:
                if CACurrentMediaTime() - startedAt >= timeoutSeconds {
                    throw PrepareReadinessError.timedOut
                }
                try await Task.sleep(nanoseconds: Self.itemReadinessPollNanoseconds)
            @unknown default:
                if CACurrentMediaTime() - startedAt >= timeoutSeconds {
                    throw PrepareReadinessError.timedOut
                }
                try await Task.sleep(nanoseconds: Self.itemReadinessPollNanoseconds)
            }
        }
    }

    private func handleCurrentItemReadyToPlay(_ item: AVPlayerItem) {
        guard isCurrentPlayerItem(item) else { return }
        seekDirectLiveHLSToLiveEdgeIfNeeded(item)
        if wantsPlayback || player.rate > 0 || player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
            if player.rate > 0 || player.timeControlStatus == .playing {
                publishPlaybackState(.playing)
                reportFirstFrameIfPossible()
                maybeReleaseSeekProtectionIfReady(for: item, reason: "item-ready")
            } else {
                publishPlaybackState(.buffering)
                scheduleTerminalStallWatchdog(reason: "item-ready-waiting")
            }
        } else {
            publishPlaybackState(.ready)
        }
    }

    private func isCurrentPlayerLayer(_ identity: ObjectIdentifier) -> Bool {
        guard let playerLayer else { return false }
        return ObjectIdentifier(playerLayer) == identity
    }

    private func isCurrentPlayerViewController(_ identity: ObjectIdentifier) -> Bool {
        guard let playerViewController else { return false }
        return ObjectIdentifier(playerViewController) == identity
    }

    private func discardPreparedPlayerItem(_ prepared: PreparedPlayerItem) {
        prepared.bridge?.stop()
        prepared.liveProxy?.stop()
        prepared.item.cancelPendingSeeks()
        prepared.item.asset.cancelLoading()
        prepared.assets.forEach { $0.cancelLoading() }
    }

    private func seekDirectLiveHLSToLiveEdgeIfNeeded(_ item: AVPlayerItem) {
        guard isCurrentPlayerItem(item) else { return }
        guard isDirectLiveHLS, !didSeekDirectLiveHLS else { return }
        guard let range = item.seekableTimeRanges.last?.timeRangeValue else { return }
        let start = range.start.seconds
        let duration = range.duration.seconds
        guard start.isFinite, duration.isFinite, duration > 0 else { return }
        didSeekDirectLiveHLS = true
        let liveEdge = max(start + duration - 1.0, start)
        PlayerMetricsLog.logger.info(
            "directLiveHLSSeekToEdge start=\(start, format: .fixed(precision: 2), privacy: .public) duration=\(duration, format: .fixed(precision: 2), privacy: .public) target=\(liveEdge, format: .fixed(precision: 2), privacy: .public)"
        )
        player.seek(
            to: CMTime(seconds: liveEdge, preferredTimescale: 600),
            toleranceBefore: CMTime(seconds: 0.5, preferredTimescale: 600),
            toleranceAfter: .zero
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.wantsPlayback, self.isCurrentPlayerItem(item) else { return }
                self.beginPlayback()
            }
        }
    }

    private func configureNativePlaybackController(_ controller: AVPlayerViewController) {
        if controller.player !== player {
            controller.player = player
        }
        controller.showsPlaybackControls = false
        if controller.videoGravity != videoGravity {
            controller.videoGravity = videoGravity
        }
        let isPictureInPictureAllowed = isPictureInPictureEnabled
            && AVPictureInPictureController.isPictureInPictureSupported()
        controller.allowsPictureInPicturePlayback = isPictureInPictureAllowed
        controller.canStartPictureInPictureAutomaticallyFromInline = isPictureInPictureAllowed
        controller.requiresLinearPlayback = false
        controller.updatesNowPlayingInfoCenter = false
        controller.view.backgroundColor = .black
        if #available(iOS 16.0, *) {
            controller.speeds = AVPlaybackSpeed.systemDefaultSpeeds
        }
        observeControllerReadyForDisplay(controller)
    }

    private func installContentOverlayIfPossible() {
        guard let overlay = contentOverlay,
              let playerViewController,
              let containerView = playerViewController.contentOverlayView
        else {
            if contentOverlay == nil {
                removeContentOverlayHostingController()
            }
            return
        }

        if contentOverlayContainerView !== containerView {
            removeContentOverlayHostingController()
        }
        containerView.backgroundColor = .clear
        containerView.isOpaque = false
        containerView.isUserInteractionEnabled = false

        if let contentOverlayHostingController {
            contentOverlayHostingController.rootView = overlay
            contentOverlayHostingController.view.isUserInteractionEnabled = false
        } else {
            let hostingController = UIHostingController(rootView: overlay)
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            hostingController.view.backgroundColor = .clear
            hostingController.view.isOpaque = false
            hostingController.view.isUserInteractionEnabled = false
            playerViewController.addChild(hostingController)
            containerView.addSubview(hostingController.view)
            NSLayoutConstraint.activate([
                hostingController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                hostingController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])
            hostingController.didMove(toParent: playerViewController)
            contentOverlayHostingController = hostingController
            contentOverlayContainerView = containerView
        }
    }

    private func removeContentOverlayHostingController() {
        guard let contentOverlayHostingController else {
            contentOverlayContainerView = nil
            return
        }
        contentOverlayHostingController.willMove(toParent: nil)
        contentOverlayHostingController.view.removeFromSuperview()
        contentOverlayHostingController.removeFromParent()
        self.contentOverlayHostingController = nil
        contentOverlayContainerView = nil
    }

    private func removePlayerLayer() {
        playerLayer?.player = nil
        playerLayer?.removeFromSuperlayer()
        layerReadyForDisplayObserver = nil
        playerLayer = nil
    }

    private func ensurePlayerLayer(in surface: UIView) -> AVPlayerLayer {
        if let playerLayer {
            if playerLayer.superlayer !== surface.layer {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                playerLayer.removeFromSuperlayer()
                surface.layer.insertSublayer(playerLayer, at: 0)
                CATransaction.commit()
            }
            if playerLayer.player == nil {
                playerLayer.player = player
            }
            if layerReadyForDisplayObserver == nil {
                observeLayerReadyForDisplay(playerLayer)
            }
            AVPlayerLayoutCoordinator.shared.apply(playerLayer: playerLayer, in: surface, gravity: videoGravity)
            return playerLayer
        }

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = videoGravity
        layer.backgroundColor = UIColor.black.cgColor
        AVPlayerLayoutCoordinator.shared.apply(playerLayer: layer, in: surface, gravity: videoGravity)
        layer.needsDisplayOnBoundsChange = false
        layer.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "frame": NSNull()
        ]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surface.layer.insertSublayer(layer, at: 0)
        CATransaction.commit()
        playerLayer = layer
        observeLayerReadyForDisplay(layer)
        return layer
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            // Playback can still proceed if the simulator or system declines the session update.
        }
    }

    private func deactivateAudioSessionIfPossible() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            // The session may already be inactive or owned by a system transition.
        }
    }

    private func configureStartupBuffering(for item: AVPlayerItem, source: PlayerStreamSource) {
        let environment = PlaybackEnvironment.current
        item.preferredForwardBufferDuration = preferredForwardBufferDuration(for: source, environment: environment)
        applyRateAwareAudioPitchAlgorithm(to: item)
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = isDirectLiveHLS
        if let manualPreferredPeakBitRate {
            item.preferredPeakBitRate = manualPreferredPeakBitRate
        } else if let bandwidth = preferredPeakBandwidth(for: source), bandwidth > 0 {
            let peakBitRateMultiplier = environment.shouldPreferConservativePlayback ? 0.92 : 1.05
            item.preferredPeakBitRate = Double(bandwidth) * peakBitRateMultiplier
        } else if source.audioURL == nil {
            item.preferredPeakBitRate = 0
        }
    }

    private func recordPrepareStage(
        source: PlayerStreamSource,
        stage: String,
        startedAt: CFTimeInterval,
        extra: String? = nil
    ) {
        let elapsedMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: startedAt)
        PlayerMetricsLog.logger.info(
            "avPlayerBridgePrepareStage id=\(source.metricsID, privacy: .public) stage=\(stage, privacy: .public) elapsedMs=\(elapsedMilliseconds, format: .fixed(precision: 1), privacy: .public)"
        )
        var message = "bridge=\(stage) elapsed=\(String(format: "%.0fms", elapsedMilliseconds))"
        if let videoCodec = source.videoStream?.codecLabel, !videoCodec.isEmpty {
            message += " codec=\(videoCodec)"
        }
        if let resolution = source.videoStream?.resolutionLabel, !resolution.isEmpty {
            message += " res=\(resolution)"
        }
        if let extra, !extra.isEmpty {
            message += " \(extra)"
        }
        PlayerMetricsLog.record(
            .startupBreakdown,
            metricsID: source.metricsID,
            title: source.title,
            message: message
        )
    }

    private func preferredPeakBandwidth(for source: PlayerStreamSource) -> Int? {
        if didLiftStartupBitRate, let maximumBandwidth = source.maximumVideoBandwidth {
            return maximumBandwidth
        }
        return source.videoStream?.bandwidth
    }

    private func preferredForwardBufferDuration(
        for source: PlayerStreamSource,
        environment: PlaybackEnvironment = .current
    ) -> TimeInterval {
        if isStartupFastStartActive, currentRate < 1.75, !isDirectLiveHLS {
            return environment.startupForwardBufferDuration
        }
        let baseDuration = source.audioURL == nil
            ? environment.preferredForwardBufferDuration
            : environment.separatedTrackForwardBufferDuration
        guard currentRate >= 1.75, !isDirectLiveHLS else { return baseDuration }
        return max(baseDuration, environment.highRateForwardBufferDuration)
    }

    private func applyRateAwareBuffering() {
        guard let item = player.currentItem, let source else { return }
        if isSeekProtectionActive {
            applySeekProtection(to: item, source: source, shouldRecordMetric: false)
            return
        }
        item.preferredForwardBufferDuration = preferredForwardBufferDuration(for: source)
    }

    private func applyRateAwareAudioPitchAlgorithm() {
        guard let item = player.currentItem else { return }
        applyRateAwareAudioPitchAlgorithm(to: item)
    }

    private func applyRateAwareAudioPitchAlgorithm(to item: AVPlayerItem) {
        item.audioTimePitchAlgorithm = currentRate >= 1.45 ? .timeDomain : .spectral
    }

    private func observeAppLifecycle() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isStopped else { return }
                self.configureAudioSession()
                guard self.isPictureInPictureEnabled else {
                    if self.wantsPlayback {
                        self.pause()
                    }
                    return
                }
                if self.wantsPlayback {
                    self.beginPlayback()
                }
            }
        }

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isStopped else { return }
                guard self.canRecoverSurfaceFromAppLifecycle else { return }
                guard self.surfaceView != nil || self.playerViewController != nil else { return }
                self.recoverSurface()
            }
        }
    }

    private var canRecoverSurfaceFromAppLifecycle: Bool {
        guard let viewModel else { return true }
        return !viewModel.isTerminated && ActivePlaybackCoordinator.shared.isActive(viewModel)
    }

    private func observePlayerState() {
        playerObservers = [
            player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
                let status = player.timeControlStatus
                Task { @MainActor [weak self] in
                    guard let self,
                          !self.isStopped,
                          player.currentItem === self.playerItem
                    else { return }
                    self.handleTimeControlStatus(status)
                }
            },
            player.observe(\.rate, options: [.new]) { [weak self] player, _ in
                let rate = player.rate
                let itemStatus = player.currentItem?.status
                let timeControlStatus = player.timeControlStatus
                let currentSeconds = player.currentTime().seconds
                Task { @MainActor [weak self] in
                    guard let self, !self.isStopped, player.currentItem === self.playerItem else { return }
                    if rate > 0 {
                        self.cancelTerminalStallWatchdog()
                        self.updatePlaybackIntent(true)
                        self.publishPlaybackState(.playing)
                        self.reportFirstFrameIfPossible(
                            currentTime: self.displayTime(fromPlayerTime: currentSeconds)
                        )
                        self.maybeReleaseSeekProtectionIfReady(reason: "rate")
                    } else if timeControlStatus == .paused,
                              itemStatus == .readyToPlay {
                        if self.isPerformingSeek || self.wantsPlayback {
                            self.publishPlaybackState(.buffering)
                        } else {
                            self.updatePlaybackIntent(false)
                            self.publishPlaybackState(.paused)
                        }
                    } else if self.wantsPlayback,
                              itemStatus == .readyToPlay,
                              timeControlStatus == .waitingToPlayAtSpecifiedRate {
                        self.publishPlaybackState(.buffering)
                        self.scheduleTerminalStallWatchdog(reason: "rate-waiting")
                    }
                }
            }
        ]
    }

    private func observeCurrentItem(_ item: AVPlayerItem) {
        itemObservers = [
            item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                let status = item.status
                let rawErrorMessage = item.error?.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self, self.isCurrentPlayerItem(item) else { return }
                    switch status {
                    case .readyToPlay:
                        self.handleCurrentItemReadyToPlay(item)
                    case .failed:
                        self.cancelTerminalStallWatchdog()
                        self.logPlayerItemFailure(item)
                        self.lastPlaybackFailureReason = self.playbackFailureReason(
                            for: item,
                            fallback: rawErrorMessage
                        )
                        let errorMessage = self.normalizedPlaybackFailureMessage(for: item, fallback: rawErrorMessage)
                        if await self.recoverFromPlaybackFailureIfPossible(
                            item: item,
                            errorMessage: errorMessage,
                            reason: "status"
                        ) {
                            return
                        }
                        self.publishPlaybackState(.failed(errorMessage))
                    case .unknown:
                        break
                    @unknown default:
                        break
                    }
                }
            },
            item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
                let isPlaybackLikelyToKeepUp = item.isPlaybackLikelyToKeepUp
                Task { @MainActor [weak self] in
                    guard let self, self.wantsPlayback, self.isCurrentPlayerItem(item) else { return }
                    if isPlaybackLikelyToKeepUp {
                        self.cancelTerminalStallWatchdog()
                        self.beginPlayback()
                        self.publishPlaybackState(.playing)
                        self.maybeReleaseSeekProtectionIfReady(for: item, reason: "keepup")
                    } else {
                        self.publishPlaybackState(.buffering)
                        self.scheduleTerminalStallWatchdog(reason: "keepup-false")
                    }
                }
            },
            item.observe(\.loadedTimeRanges, options: [.initial, .new]) { [weak self] item, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isCurrentPlayerItem(item) else { return }
                    self.handleLoadedTimeRangesChanged(for: item)
                }
            },
            item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
                let isPlaybackBufferEmpty = item.isPlaybackBufferEmpty
                Task { @MainActor [weak self] in
                    guard let self,
                          self.wantsPlayback,
                          isPlaybackBufferEmpty,
                          self.isCurrentPlayerItem(item)
                    else { return }
                    self.publishPlaybackState(.buffering)
                    self.scheduleTerminalStallWatchdog(reason: "buffer-empty")
                }
            },
            item.observe(\.seekableTimeRanges, options: [.new]) { [weak self] item, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isCurrentPlayerItem(item) else { return }
                    self.seekDirectLiveHLSToLiveEdgeIfNeeded(item)
                }
            }
        ]

        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isCurrentPlayerItem(item) else { return }
                self.cancelTerminalStallWatchdog()
                self.wantsPlayback = false
                self.publishPlaybackState(.ended)
            }
        }

        itemFailedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let rawErrorMessage = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                .localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.isCurrentPlayerItem(item) else { return }
                self.cancelTerminalStallWatchdog()
                self.logPlayerItemFailure(item)
                self.lastPlaybackFailureReason = self.playbackFailureReason(
                    for: item,
                    fallback: rawErrorMessage
                )
                let errorMessage = self.normalizedPlaybackFailureMessage(for: item, fallback: rawErrorMessage)
                if await self.recoverFromPlaybackFailureIfPossible(
                    item: item,
                    errorMessage: errorMessage,
                    reason: "failedToEnd"
                ) {
                    return
                }
                self.publishPlaybackState(.failed(errorMessage))
            }
        }

        itemStalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      self.wantsPlayback,
                      self.isCurrentPlayerItem(item)
                else { return }
                self.publishPlaybackState(.buffering)
                self.scheduleTerminalStallWatchdog(reason: "playback-stalled")
            }
        }

        itemAccessLogObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewAccessLogEntry,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isCurrentPlayerItem(item) else { return }
                self.recordAccessLogEntry(for: item)
            }
        }
    }

    private func logPlayerItemFailure(_ item: AVPlayerItem) {
        let event = item.errorLog()?.events.last
        PlayerMetricsLog.logger.error(
            "playerItemFailed error=\(item.error?.localizedDescription ?? "-", privacy: .public) status=\(event?.errorStatusCode ?? 0, privacy: .public) domain=\(event?.errorDomain ?? "-", privacy: .public) comment=\(event?.errorComment ?? "-", privacy: .public) uri=\(event?.uri ?? "-", privacy: .private)"
        )
    }

    private func normalizedPlaybackFailureMessage(for item: AVPlayerItem, fallback: String?) -> String? {
        if let statusCode = item.errorLog()?.events.last?.errorStatusCode,
           let message = HLSBridgeRemoteFailure.playbackMessage(forHTTPStatus: statusCode) {
            return message
        }
        guard let fallback, !fallback.isEmpty else { return nil }
        return fallback
    }

    private func playbackFailureReason(for item: AVPlayerItem, fallback: String?) -> HLSBridgeFailureReason? {
        if let statusCode = item.errorLog()?.events.last?.errorStatusCode {
            return HLSBridgeRemoteFailure.reason(forHTTPStatus: statusCode)
        }
        if let error = item.error {
            return HLSBridgeRemoteFailure.reason(for: error)
        }
        guard let fallback, !fallback.isEmpty else { return nil }
        return HLSBridgeFailureReason(
            layer: .avPlayerItem,
            category: .unknown,
            statusCode: nil,
            urlHost: nil,
            rangeDescription: nil,
            underlyingDescription: fallback
        )
    }

    private func prepareFailureReason(for error: Error, source: PlayerStreamSource) -> HLSBridgeFailureReason {
        if error is CancellationError {
            return HLSBridgeFailureReason(
                layer: .local,
                category: .cancelled,
                statusCode: nil,
                urlHost: source.videoURL?.host?.lowercased(),
                rangeDescription: nil,
                underlyingDescription: error.localizedDescription
            )
        }
        if let failure = error as? HLSBridgeRemoteFailure {
            return failure.reason
        }
        if let streamError = error as? HLSRangeStreamError {
            return HLSBridgeRemoteFailure.reason(for: streamError)
        }
        if let urlError = error as? URLError {
            return HLSBridgeFailureReason(
                layer: .remoteRange,
                category: HLSBridgeRemoteFailure.reason(for: urlError).category,
                statusCode: nil,
                urlHost: source.videoURL?.host?.lowercased(),
                rangeDescription: nil,
                underlyingDescription: urlError.localizedDescription
            )
        }
        let category: HLSBridgeRemoteFailureCategory
        if let engineError = error as? PlayerEngineError {
            switch engineError {
            case .missingVideoURL:
                category = .invalidResponse
            case .unsupportedMedia:
                category = .hardwareDecodeRejected
            }
        } else {
            category = HLSBridgeRemoteFailure.reason(for: error).category
        }
        return HLSBridgeFailureReason(
            layer: .local,
            category: category,
            statusCode: nil,
            urlHost: source.videoURL?.host?.lowercased(),
            rangeDescription: nil,
            underlyingDescription: error.localizedDescription
        )
    }

    private func shouldAttemptSameSourceRecovery(item: AVPlayerItem, errorMessage: String?) -> Bool {
        if let statusCode = item.errorLog()?.events.last?.errorStatusCode,
           !HLSBridgeRemoteFailure.allowsSameSourceRecovery(forHTTPStatus: statusCode) {
            return false
        }
        if let errorMessage,
           !HLSBridgeRemoteFailure.allowsSameSourceRecovery(forPlaybackMessage: errorMessage) {
            return false
        }
        return true
    }

    private func recoverFromPlaybackFailureIfPossible(
        item: AVPlayerItem,
        errorMessage: String?,
        reason: String
    ) async -> Bool {
        guard !isPlaybackFailureRecoveryInProgress else {
            PlayerMetricsLog.record(
                .network,
                metricsID: source?.metricsID ?? "-",
                title: source?.title,
                message: "hlsRecover=alreadyInProgress reason=\(reason)"
            )
            return true
        }
        guard isCurrentPlayerItem(item),
              let source
        else { return false }
        let recoveryGeneration = playbackGeneration
        guard source.audioURL != nil || hlsBridge != nil else { return false }
        guard shouldAttemptSameSourceRecovery(item: item, errorMessage: errorMessage) else {
            await recordPlaybackFailureAvoidance(
                source: source,
                reason: reason,
                errorMessage: errorMessage
            )
            guard isCurrentPlayerItem(item),
                  recoveryGeneration == playbackGeneration
            else { return true }
            PlayerMetricsLog.record(
                .network,
                metricsID: source.metricsID,
                title: source.title,
                message: "hlsRecover=skip reason=\(reason) error=\(errorMessage ?? "-")"
            )
            return false
        }

        let recoveryKey = playbackFailureRecoveryKey(for: source)
        let attempt = playbackFailureRecoveryAttempts[recoveryKey] ?? 0
        guard attempt < 2 else { return false }
        playbackFailureRecoveryAttempts[recoveryKey] = attempt + 1
        isPlaybackFailureRecoveryInProgress = true
        defer { isPlaybackFailureRecoveryInProgress = false }

        let restoreTime = snapshot(durationHint: source.durationHint).currentTime
            ?? displayTime(fromPlayerTime: player.currentTime().seconds)
        let shouldResume = wantsPlayback || player.rate > 0
        let restoreRate = currentRate
        publishPlaybackState(.buffering)
        onLoadingProgressChange?(0.16)
        await recordPlaybackFailureAvoidance(
            source: source,
            reason: reason,
            errorMessage: errorMessage
        )
        guard isCurrentPlayerItem(item),
              recoveryGeneration == playbackGeneration
        else { return true }
        PlayerMetricsLog.record(
            .network,
            metricsID: source.metricsID,
            title: source.title,
            message: "hlsRecover reason=\(reason) attempt=\(attempt + 1) time=\(String(format: "%.2fs", max(restoreTime, 0)))"
        )

        let preparedRecoveryGeneration = recoveryGeneration &+ 1
        do {
            try await prepare(source: source.withResumeTime(max(restoreTime, 0)))
            guard !Task.isCancelled,
                  !isStopped,
                  playbackGeneration == preparedRecoveryGeneration
            else { return true }
            setPlaybackRate(Double(restoreRate))
            if restoreTime > 0.35 {
                _ = seek(toTime: restoreTime)
            }
            if shouldResume {
                play()
            } else {
                pause()
            }
            PlayerMetricsLog.record(
                .network,
                metricsID: source.metricsID,
                title: source.title,
                message: "hlsRecover=ok attempt=\(attempt + 1)"
            )
            return true
        } catch {
            guard !Task.isCancelled,
                  !isStopped,
                  playbackGeneration == preparedRecoveryGeneration
            else { return true }
            PlayerMetricsLog.logger.error(
                "hlsRecoverFailed attempt=\(attempt + 1, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            PlayerMetricsLog.record(
                .network,
                metricsID: source.metricsID,
                title: source.title,
                message: "hlsRecover=failed attempt=\(attempt + 1) \(error.localizedDescription)"
            )
            return false
        }
    }

    private func recordPlaybackFailureAvoidance(
        source: PlayerStreamSource,
        reason: String,
        errorMessage: String?
    ) async {
        var seenHosts = Set<String>()
        var hosts = [String]()
        for url in [source.videoURL, source.audioURL] {
            guard let url,
                  let rawHost = URLComponents(url: url, resolvingAgainstBaseURL: false)?.host
            else { continue }
            let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !host.isEmpty, seenHosts.insert(host).inserted else { continue }
            hosts.append(host)
        }
        let messageReason = [
            "player-\(reason)",
            errorMessage?.isEmpty == false ? "error" : nil
        ]
        .compactMap { $0 }
        .joined(separator: "-")

        for host in hosts {
            await HLSSourcePreferenceCache.shared.recordSessionAvoidance(
                host: host,
                reason: messageReason,
                metricsID: source.metricsID,
                title: source.title
            )
        }
    }

    private func playbackFailureRecoveryKey(for source: PlayerStreamSource) -> String {
        [
            source.metricsID,
            source.videoURL?.absoluteString ?? "-",
            source.audioURL?.absoluteString ?? "-"
        ].joined(separator: "|")
    }

    private func recordAccessLogEntry(for item: AVPlayerItem) {
        guard let source, let event = item.accessLog()?.events.last else { return }
        let observedKbps = Int((event.observedBitrate / 1_000).rounded())
        let indicatedKbps = Int((event.indicatedBitrate / 1_000).rounded())
        let transferMilliseconds = Int((event.transferDuration * 1_000).rounded())
        let startupMilliseconds = Int((event.startupTime * 1_000).rounded())
        let server = event.serverAddress ?? "-"
        let stallDelta = max(event.numberOfStalls - lastRecordedAccessLogStallCount, 0)
        lastRecordedAccessLogStallCount = max(lastRecordedAccessLogStallCount, event.numberOfStalls)
        let feedbackHost = recordPlaybackURLFeedback(
            source: source,
            observedKilobitsPerSecond: observedKbps,
            transferMilliseconds: transferMilliseconds,
            bytes: event.numberOfBytesTransferred,
            stallDelta: stallDelta
        )
        let message = [
            "observedKbps=\(max(observedKbps, 0))",
            "indicatedKbps=\(max(indicatedKbps, 0))",
            "stalls=\(event.numberOfStalls)",
            "stallDelta=\(stallDelta)",
            "transfer=\(max(transferMilliseconds, 0))ms",
            "startup=\(max(startupMilliseconds, 0))ms",
            "bytes=\(event.numberOfBytesTransferred)",
            "requests=\(event.numberOfMediaRequests)",
            "host=\(feedbackHost ?? "-")",
            "server=\(server)"
        ].joined(separator: " ")
        PlayerMetricsLog.record(
            .accessLog,
            metricsID: source.metricsID,
            title: source.title,
            message: message
        )
    }

    private func recordPlaybackURLFeedback(
        source: PlayerStreamSource,
        observedKilobitsPerSecond: Int,
        transferMilliseconds: Int,
        bytes: Int64,
        stallDelta: Int
    ) -> String? {
        guard observedKilobitsPerSecond > 0 || bytes > 0 || stallDelta > 0 else { return nil }
        guard let videoURL = source.videoURL ?? source.audioURL else { return nil }
        PlaybackURLPreferenceStore.shared.recordPlaybackFeedback(
            url: videoURL,
            observedKilobitsPerSecond: max(observedKilobitsPerSecond, 0),
            transferMilliseconds: max(transferMilliseconds, 0),
            bytes: max(bytes, 0),
            stallCount: stallDelta
        )
        if stallDelta > 0,
           let audioURL = source.audioURL,
           audioURL.host?.lowercased() != videoURL.host?.lowercased() {
            PlaybackURLPreferenceStore.shared.recordPlaybackFeedback(
                url: audioURL,
                observedKilobitsPerSecond: 0,
                transferMilliseconds: max(transferMilliseconds, 0),
                bytes: 0,
                stallCount: stallDelta
            )
        }
        if stallDelta > 0 {
            let videoHost = videoURL.host
            let audioHost = source.audioURL?.host
            Task {
                await HLSSourcePreferenceCache.shared.recordSessionAvoidance(
                    host: videoHost,
                    reason: "accesslog-stall-\(stallDelta)",
                    metricsID: source.metricsID,
                    title: source.title
                )
                if audioHost?.lowercased() != videoHost?.lowercased() {
                    await HLSSourcePreferenceCache.shared.recordSessionAvoidance(
                        host: audioHost,
                        reason: "accesslog-stall-\(stallDelta)",
                        metricsID: source.metricsID,
                        title: source.title
                    )
                }
            }
        }
        return videoURL.host
    }

    private func observeLayerReadyForDisplay(_ layer: AVPlayerLayer) {
        layerReadyForDisplayObserver = layer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            let layerIdentity = ObjectIdentifier(layer)
            Task { @MainActor [weak self] in
                guard let self,
                      !self.isStopped,
                      self.isCurrentPlayerLayer(layerIdentity),
                      self.player.currentItem === self.playerItem
                else { return }
                self.reportFirstFrameIfPossible()
            }
        }
    }

    private func observeControllerReadyForDisplay(_ controller: AVPlayerViewController) {
        guard controllerReadyForDisplayObserver == nil else { return }
        controllerReadyForDisplayObserver = controller.observe(\.isReadyForDisplay, options: [.new]) { [weak self] controller, _ in
            guard controller.isReadyForDisplay else { return }
            let controllerIdentity = ObjectIdentifier(controller)
            Task { @MainActor [weak self] in
                guard let self,
                      !self.isStopped,
                      self.isCurrentPlayerViewController(controllerIdentity),
                      self.player.currentItem === self.playerItem
                else { return }
                self.reportFirstFrameIfPossible()
            }
        }
    }

    private func ensurePeriodicTimeObserver() {
        guard periodicTimeObserver == nil else { return }
        periodicTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor [weak self] in
                guard let self,
                      !self.isStopped,
                      self.player.currentItem === self.playerItem
                else { return }
                self.reportFirstFrameIfPossible(currentTime: self.displayTime(fromPlayerTime: seconds))
            }
        }
    }

    private func removePeriodicTimeObserver() {
        guard let periodicTimeObserver else { return }
        player.removeTimeObserver(periodicTimeObserver)
        self.periodicTimeObserver = nil
    }

    private func removeCurrentItemObservers() {
        itemObservers.removeAll()
        if let itemEndObserver {
            NotificationCenter.default.removeObserver(itemEndObserver)
            self.itemEndObserver = nil
        }
        if let itemFailedObserver {
            NotificationCenter.default.removeObserver(itemFailedObserver)
            self.itemFailedObserver = nil
        }
        if let itemStalledObserver {
            NotificationCenter.default.removeObserver(itemStalledObserver)
            self.itemStalledObserver = nil
        }
        if let itemAccessLogObserver {
            NotificationCenter.default.removeObserver(itemAccessLogObserver)
            self.itemAccessLogObserver = nil
        }
    }

    private func beginSeekTransaction(targetDisplayTime: TimeInterval?) -> Int {
        seekGeneration &+= 1
        isPerformingSeek = true
        if let targetDisplayTime, targetDisplayTime.isFinite, targetDisplayTime >= 0 {
            seekProtectionTargetTime = targetDisplayTime
        } else {
            seekProtectionTargetTime = nil
        }
        if let item = player.currentItem, let source {
            applySeekProtection(to: item, source: source, shouldRecordMetric: true)
        }
        onLoadingProgressChange?(0.12)
        return seekGeneration
    }

    private func finishSeekTransaction(generation: Int, finished: Bool, shouldResume: Bool) {
        guard !isStopped else { return }
        guard generation == seekGeneration else { return }
        isPerformingSeek = false
        if let item = player.currentItem {
            updateLoadingProgress(for: item)
        }
        guard finished else {
            releaseSeekProtection(reason: "cancelled")
            return
        }
        guard shouldResume else {
            releaseSeekProtection(reason: "paused")
            return
        }
        scheduleSeekProtectionRelease(generation: generation)
        beginPlayback()
        if let item = player.currentItem {
            maybeReleaseSeekProtectionIfReady(for: item, reason: "finish")
        }
    }

    private func applySeekProtection(
        to item: AVPlayerItem,
        source: PlayerStreamSource,
        shouldRecordMetric: Bool
    ) {
        guard !isDirectLiveHLS else { return }
        let wasActive = isSeekProtectionActive
        isSeekProtectionActive = true
        seekProtectionAppliedAt = CACurrentMediaTime()
        seekProtectionReleaseTask?.cancel()
        seekProtectionReleaseTask = nil
        let environment = PlaybackEnvironment.current
        let currentBuffer = preferredForwardBufferDuration(for: source, environment: environment)
        let protectedBuffer = min(max(currentBuffer + 1.6, 3.2), 7.0)
        item.preferredForwardBufferDuration = protectedBuffer
        if let bandwidth = source.videoStream?.bandwidth, bandwidth > 0 {
            let multiplier: Double = currentRate >= 1.75 ? 0.78 : 0.88
            item.preferredPeakBitRate = Double(bandwidth) * multiplier
        }
        guard shouldRecordMetric, !wasActive else { return }
        PlayerMetricsLog.record(
            .network,
            metricsID: source.metricsID,
            title: source.title,
            message: "seekProtect=on buffer=\(String(format: "%.1f", protectedBuffer))s peak=\(Int(item.preferredPeakBitRate.rounded()))"
        )
    }

    private func scheduleSeekProtectionRelease(generation: Int) {
        seekProtectionReleaseTask?.cancel()
        seekProtectionReleaseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard let self,
                  !Task.isCancelled,
                  !self.isStopped,
                  generation == self.seekGeneration
            else { return }
            self.releaseSeekProtection(reason: "timeout")
        }
    }

    private func releaseSeekProtection(reason: String) {
        guard isSeekProtectionActive else { return }
        isSeekProtectionActive = false
        seekProtectionReleaseTask?.cancel()
        seekProtectionReleaseTask = nil
        let elapsedMilliseconds = seekProtectionAppliedAt
            .map { Int(PlayerMetricsLog.elapsedMilliseconds(since: $0).rounded()) }
        seekProtectionTargetTime = nil
        seekProtectionAppliedAt = nil
        guard let item = player.currentItem, let source else { return }
        configureStartupBuffering(for: item, source: source)
        applyRateAwareBuffering()
        PlayerMetricsLog.record(
            .network,
            metricsID: source.metricsID,
            title: source.title,
            message: "seekProtect=off reason=\(reason) elapsed=\(elapsedMilliseconds.map { "\($0)ms" } ?? "-") buffer=\(String(format: "%.1f", item.preferredForwardBufferDuration))s peak=\(Int(item.preferredPeakBitRate.rounded()))"
        )
    }

    private func scheduleTerminalStallWatchdog(reason: String) {
        guard terminalStallTask == nil,
              wantsPlayback,
              !isPerformingSeek,
              !isSeekProtectionActive,
              player.rate == 0,
              player.timeControlStatus == .waitingToPlayAtSpecifiedRate,
              let item = player.currentItem,
              isCurrentPlayerItem(item),
              item.status == .readyToPlay,
              !item.isPlaybackLikelyToKeepUp
        else { return }
        terminalStallGeneration &+= 1
        let stallGeneration = terminalStallGeneration
        let generation = playbackGeneration
        let startedAt = CACurrentMediaTime()
        terminalStallTask = Task { @MainActor [weak self, weak item] in
            try? await Task.sleep(nanoseconds: Self.terminalStallDelayNanoseconds)
            guard let self else { return }
            defer {
                if self.terminalStallGeneration == stallGeneration {
                    self.terminalStallTask = nil
                }
            }
            guard let item,
                  !Task.isCancelled,
                  self.terminalStallGeneration == stallGeneration,
                  self.shouldTreatPlaybackAsTerminallyStalled(item: item, generation: generation)
            else { return }
            await self.handleTerminalPlaybackStall(item: item, reason: reason, startedAt: startedAt)
        }
    }

    private func cancelTerminalStallWatchdog() {
        terminalStallGeneration &+= 1
        terminalStallTask?.cancel()
        terminalStallTask = nil
    }

    private func shouldTreatPlaybackAsTerminallyStalled(item: AVPlayerItem, generation: Int) -> Bool {
        guard isCurrentPlaybackGeneration(generation),
              isCurrentPlayerItem(item),
              wantsPlayback,
              !isPerformingSeek,
              !isSeekProtectionActive,
              player.rate == 0,
              player.timeControlStatus == .waitingToPlayAtSpecifiedRate,
              item.status == .readyToPlay,
              !item.isPlaybackLikelyToKeepUp
        else { return false }
        return bufferAhead(for: item) < 0.45
    }

    private func handleTerminalPlaybackStall(
        item: AVPlayerItem,
        reason: String,
        startedAt: CFTimeInterval
    ) async {
        guard isCurrentPlayerItem(item), let source else { return }
        let elapsedMilliseconds = Int(PlayerMetricsLog.elapsedMilliseconds(since: startedAt).rounded())
        let message = "播放长时间无进展"
        lastPlaybackFailureReason = HLSBridgeFailureReason(
            layer: .avPlayerItem,
            category: .terminalStall,
            statusCode: nil,
            urlHost: nil,
            rangeDescription: nil,
            underlyingDescription: message
        )
        PlayerMetricsLog.logger.error(
            "avPlayerTerminalStall reason=\(reason, privacy: .public) elapsedMs=\(elapsedMilliseconds, privacy: .public) id=\(source.metricsID, privacy: .public)"
        )
        PlayerMetricsLog.record(
            .network,
            metricsID: source.metricsID,
            title: source.title,
            message: "terminalStall reason=\(reason) elapsed=\(elapsedMilliseconds)ms buffer=\(String(format: "%.2fs", bufferAhead(for: item)))"
        )
        if await recoverFromPlaybackFailureIfPossible(
            item: item,
            errorMessage: message,
            reason: "terminalStall-\(reason)"
        ) {
            return
        }
        guard isCurrentPlayerItem(item) else { return }
        publishPlaybackState(.failed(message))
    }

    private func handleLoadedTimeRangesChanged(for item: AVPlayerItem) {
        updateLoadingProgress(for: item)
        if wantsPlayback,
           player.timeControlStatus == .waitingToPlayAtSpecifiedRate,
           !item.isPlaybackLikelyToKeepUp {
            scheduleTerminalStallWatchdog(reason: "buffer-waiting")
        } else if player.rate > 0 || item.isPlaybackLikelyToKeepUp {
            cancelTerminalStallWatchdog()
        }
        maybeReleaseSeekProtectionIfReady(for: item, reason: "buffer")
    }

    private func maybeReleaseSeekProtectionIfReady(for item: AVPlayerItem? = nil, reason: String) {
        guard isSeekProtectionActive, !isPerformingSeek else { return }
        let resolvedItem = item ?? player.currentItem
        guard let resolvedItem, player.currentItem === resolvedItem else { return }
        if player.timeControlStatus == .playing {
            releaseSeekProtection(reason: reason)
            return
        }
        if resolvedItem.isPlaybackLikelyToKeepUp {
            releaseSeekProtection(reason: reason)
            return
        }
        guard let targetTime = seekProtectionTargetTime else { return }
        let coverage = seekProtectionBufferCoverage(for: resolvedItem, around: targetTime)
        guard coverage >= 0.86 else { return }
        releaseSeekProtection(reason: "\(reason)-coverage\(Int((coverage * 100).rounded()))")
    }

    private func seekProtectionBufferCoverage(for item: AVPlayerItem, around targetTime: TimeInterval) -> Double {
        PlayerPlaybackSnapshot(
            currentTime: nil,
            duration: nil,
            isPlaying: player.rate > 0,
            isSeekable: true,
            bufferedRanges: bufferedRanges(for: item)
        )
        .bufferedCoverageProgress(around: targetTime, preroll: 0.25, forward: 1.45)
    }

    private func updateLoadingProgress(for item: AVPlayerItem) {
        guard player.currentItem === item else { return }
        let bufferAhead = bufferAhead(for: item)
        let targetBuffer = max(item.preferredForwardBufferDuration, 1)
        let progress = min(max(bufferAhead / targetBuffer, item.isPlaybackBufferEmpty ? 0 : 0.12), 1)
        onLoadingProgressChange?(progress)
    }

    private func bufferAhead(for item: AVPlayerItem) -> TimeInterval {
        guard player.currentItem === item else { return 0 }
        let currentSeconds = player.currentTime().seconds
        guard currentSeconds.isFinite, currentSeconds >= 0 else { return 0 }
        let ranges = item.loadedTimeRanges
            .map(\.timeRangeValue)
            .compactMap { range -> (start: TimeInterval, end: TimeInterval)? in
                let start = range.start.seconds
                let end = range.end.seconds
                guard start.isFinite, end.isFinite, end > start else { return nil }
                return (start, end)
            }
            .sorted { lhs, rhs in
                if lhs.start == rhs.start {
                    return lhs.end < rhs.end
                }
                return lhs.start < rhs.start
            }
        guard !ranges.isEmpty else { return 0 }
        let tolerance = Self.loadedRangeContinuityTolerance
        guard let containingIndex = ranges.firstIndex(where: { range in
            range.start - tolerance <= currentSeconds && currentSeconds <= range.end + tolerance
        }) else { return 0 }

        var bufferedEnd = max(ranges[containingIndex].end, currentSeconds)
        for range in ranges[(containingIndex + 1)...] {
            guard range.start <= bufferedEnd + tolerance else { break }
            bufferedEnd = max(bufferedEnd, range.end)
        }
        return max(bufferedEnd - currentSeconds, 0)
    }

    private func bufferedRanges(for item: AVPlayerItem) -> [PlayerBufferedRange] {
        item.loadedTimeRanges
            .map(\.timeRangeValue)
            .compactMap { range -> PlayerBufferedRange? in
                let start = displayTime(fromPlayerTime: range.start.seconds)
                let end = displayTime(fromPlayerTime: range.end.seconds)
                guard start.isFinite, end.isFinite, end > start else { return nil }
                return PlayerBufferedRange(start: max(start, 0), end: max(end, 0))
            }
    }

    private func handleTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
        guard !isStopped, player.currentItem != nil else { return }
        switch status {
        case .paused:
            publishPlaybackState((wantsPlayback || isPerformingSeek) ? .buffering : .paused)
            if !(wantsPlayback || isPerformingSeek) {
                cancelTerminalStallWatchdog()
            }
        case .waitingToPlayAtSpecifiedRate:
            if wantsPlayback || isPerformingSeek {
                publishPlaybackState(.buffering)
                scheduleTerminalStallWatchdog(reason: "timeControl-waiting")
            }
        case .playing:
            cancelTerminalStallWatchdog()
            updatePlaybackIntent(true)
            publishPlaybackState(.playing)
            reportFirstFrameIfPossible()
            maybeReleaseSeekProtectionIfReady(reason: "playing")
        @unknown default:
            break
        }
    }

    private func updatePlaybackIntent(_ wantsPlayback: Bool) {
        guard self.wantsPlayback != wantsPlayback else { return }
        self.wantsPlayback = wantsPlayback
        onPlaybackIntentChange?(wantsPlayback)
    }

    private func reportFirstFrameIfPossible(currentTime: TimeInterval? = nil) {
        guard !isStopped, player.currentItem != nil else { return }
        guard !didReportFirstFrame else { return }
        guard playerViewController?.isReadyForDisplay == true
            || playerLayer?.isReadyForDisplay == true
        else { return }
        didReportFirstFrame = true
        cancelTerminalStallWatchdog()
        removePeriodicTimeObserver()
        let resolvedTime = currentTime ?? displayTime(fromPlayerTime: player.currentTime().seconds)
        onFirstFrame?(resolvedTime.isFinite ? max(resolvedTime, 0) : 0)
        restoreSteadyStateBufferingAfterFirstFrame()
        scheduleStartupBitRateLiftIfNeeded()
    }

    private func restoreSteadyStateBufferingAfterFirstFrame() {
        guard isStartupFastStartActive else { return }
        isStartupFastStartActive = false
        player.automaticallyWaitsToMinimizeStalling = !isDirectLiveHLS
        guard !isSeekProtectionActive,
              let item = player.currentItem,
              let source = self.source
        else { return }
        configureStartupBuffering(for: item, source: source)
        applyRateAwareBuffering()
        PlayerMetricsLog.record(
            .startupBreakdown,
            metricsID: source.metricsID,
            title: source.title,
            message: "bridge=steadyBuffer buffer=\(String(format: "%.2fs", item.preferredForwardBufferDuration)) waits=\(!isDirectLiveHLS)"
        )
    }

    private func scheduleStartupBitRateLiftIfNeeded() {
        guard startupBitRateLiftTask == nil,
              !didLiftStartupBitRate,
              !isDirectLiveHLS,
              let source,
              (hlsBridge?.videoVariantCount ?? 1) > 1,
              !source.alternateVideoRenditions.isEmpty,
              let startupBandwidth = source.videoStream?.bandwidth,
              let maximumBandwidth = source.maximumVideoBandwidth,
              maximumBandwidth > startupBandwidth
        else { return }

        let generation = playbackGeneration
        startupBitRateLiftTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_350_000_000)
            guard let self, !Task.isCancelled else { return }
            defer { self.startupBitRateLiftTask = nil }
            guard !self.isStopped,
                  self.isCurrentPlaybackGeneration(generation),
                  !self.isSeekProtectionActive,
                  let item = self.player.currentItem,
                  let source = self.source
            else { return }
            self.didLiftStartupBitRate = true
            self.configureStartupBuffering(for: item, source: source)
            self.applyRateAwareBuffering()
            PlayerMetricsLog.record(
                .qualitySupplement,
                metricsID: source.metricsID,
                title: source.title,
                message: "hlsVariantLift peak=\(Int(item.preferredPeakBitRate.rounded())) variants=\(source.alternateVideoRenditions.count + 1)"
            )
        }
    }

    private func publishPlaybackState(_ state: PlayerEnginePlaybackState) {
        guard state != lastPlaybackState else { return }
        lastPlaybackState = state
        onPlaybackStateChange?(state)
    }

    private func resolvedDuration(durationHint: TimeInterval?) -> TimeInterval {
        let itemDuration = player.currentItem?.duration.seconds ?? 0
        if mediaTimeOffset > 0 {
            if let durationHint, durationHint > 0 {
                return durationHint
            }
            if let sourceDurationHint = source?.durationHint, sourceDurationHint > 0 {
                return sourceDurationHint
            }
            if itemDuration.isFinite, itemDuration > mediaTimeOffset {
                return itemDuration - mediaTimeOffset
            }
        }
        if itemDuration.isFinite, itemDuration > 0 {
            return itemDuration
        }
        return durationHint ?? source?.durationHint ?? 0
    }

    private func alignedInteractiveSeekTime(_ displayTime: TimeInterval) -> TimeInterval {
        guard displayTime.isFinite, displayTime > 0 else { return 0 }
        guard let alignedTime = hlsBridge?.alignedSeekTime(near: displayTime),
              alignedTime.isFinite,
              alignedTime >= 0
        else {
            return displayTime
        }
        return alignedTime
    }

    private func warmSeekTargetIfNeeded(_ displayTime: TimeInterval) {
        guard displayTime.isFinite, displayTime >= 0 else { return }
        hlsBridge?.warmSeekTarget(around: displayTime, metricsID: source?.metricsID)
    }

    private func playerTime(fromDisplayTime time: TimeInterval) -> TimeInterval {
        guard mediaTimeOffset > 0 else { return time }
        return max(time, 0) + mediaTimeOffset
    }

    private func displayTime(fromPlayerTime time: TimeInterval) -> TimeInterval {
        guard time.isFinite, time >= 0 else { return time }
        guard mediaTimeOffset > 0 else { return time }
        return max(time - mediaTimeOffset, 0)
    }

    private static func makePlayerItem(source: PlayerStreamSource) async throws -> PreparedPlayerItem {
        guard let videoURL = source.videoURL else {
            throw PlayerEngineError.missingVideoURL
        }
        try enforceHardwareDecodingCompatibility(for: source)

        let headers = source.httpHeaders

        if source.audioURL != nil {
            if let videoStream = source.videoStream,
               let audioStream = source.audioStream,
               videoStream.segmentBase?.indexByteRange != nil,
               audioStream.segmentBase?.indexByteRange != nil {
                do {
                    // Keep AVPlayer on a standard HTTP HLS surface for device playback.
                    // The bridge only accepts HEVC video + AAC audio inputs so the
                    // decode path stays fully inside Apple's hardware pipeline.
                    let manifest = try await BiliHLSManifestBuilder.make(
                        source: source,
                        shouldValidateHardwareDecoding: true
                    )
                    guard let bridge = manifest.bridge else {
                        throw PlayerEngineError.unsupportedMedia
                    }
                    let asset = AVURLAsset(url: manifest.masterPlaylistURL)
                    let item = AVPlayerItem(asset: asset)
                    item.preferredForwardBufferDuration = PlaybackEnvironment.current.startupForwardBufferDuration
                    return PreparedPlayerItem(item: item, bridge: bridge, liveProxy: nil, assets: [asset], isDirectLiveHLS: false)
                } catch {
                    PlayerMetricsLog.logger.error(
                        "avPlayerLocalHLSBridgeRejected reason=\(error.localizedDescription, privacy: .public)"
                    )
                    throw error
                }
            }

            throw PlayerEngineError.unsupportedMedia
        }

        let isDirectLiveHLS = videoURL.isLikelyHLSManifest && source.durationHint == nil
        let asset = AVURLAsset(url: videoURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = isDirectLiveHLS ? 0.5 : PlaybackEnvironment.current.startupForwardBufferDuration
        return PreparedPlayerItem(item: item, bridge: nil, liveProxy: nil, assets: [asset], isDirectLiveHLS: isDirectLiveHLS)
    }

    private nonisolated static func enforceHardwareDecodingCompatibility(for source: PlayerStreamSource) throws {
        if let videoStream = source.videoStream {
            guard videoStream.isHardwareDecodingCompatibleVideo else {
                PlayerMetricsLog.logger.error(
                    "hardwareDecodeRejected media=video codec=\(videoStream.codecs ?? "-", privacy: .public) codecid=\(videoStream.codecid ?? -1, privacy: .public)"
                )
                throw PlayerEngineError.unsupportedMedia
            }
        } else if source.audioURL != nil {
            PlayerMetricsLog.logger.error("hardwareDecodeRejected media=video codec=missing")
            throw PlayerEngineError.unsupportedMedia
        }

        if let audioStream = source.audioStream,
           !audioStream.isHardwareDecodingCompatibleAudio {
            PlayerMetricsLog.logger.error(
                "hardwareDecodeRejected media=audio codec=\(audioStream.codecs ?? "-", privacy: .public) codecid=\(audioStream.codecid ?? -1, privacy: .public)"
            )
            throw PlayerEngineError.unsupportedMedia
        }
    }

    private nonisolated static func makeComposition(
        videoURL: URL,
        audioURL: URL,
        headers: [String: String]
    ) async throws -> AVMutableComposition {
        let options = ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let videoAsset = AVURLAsset(url: videoURL, options: options)
        let audioAsset = AVURLAsset(url: audioURL, options: options)

        async let videoTracks = videoAsset.loadTracks(withMediaType: .video)
        async let audioTracks = audioAsset.loadTracks(withMediaType: .audio)
        async let videoDuration = videoAsset.load(.duration)
        async let audioDuration = audioAsset.load(.duration)

        guard let sourceVideoTrack = try await videoTracks.first else {
            throw PlayerEngineError.unsupportedMedia
        }
        let sourceAudioTrack = try await audioTracks.first
        let duration = try await minFinite(videoDuration, audioDuration)
        let composition = AVMutableComposition()
        let range = CMTimeRange(start: .zero, duration: duration)

        if let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try videoTrack.insertTimeRange(range, of: sourceVideoTrack, at: .zero)
            videoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        }

        if let sourceAudioTrack,
           let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try audioTrack.insertTimeRange(range, of: sourceAudioTrack, at: .zero)
        }

        return composition
    }

    private nonisolated static func minFinite(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
        let left = lhs.seconds
        let right = rhs.seconds
        if left.isFinite, right.isFinite, left > 0, right > 0 {
            return left <= right ? lhs : rhs
        }
        if left.isFinite, left > 0 {
            return lhs
        }
        if right.isFinite, right > 0 {
            return rhs
        }
        return .positiveInfinity
    }

    private nonisolated static func hlsBridgeTrack(
        url: URL,
        stream: DASHStream?,
        mediaType: HLSBridgeTrack.MediaType,
        dynamicRange: BiliVideoDynamicRange = .sdr,
        cdnPreference: PlaybackCDNPreference = .automatic
    ) -> HLSBridgeTrack {
        HLSBridgeTrack(
            url: url,
            fallbackURLs: stream?.backupPlayURLs(cdnPreference: cdnPreference) ?? [],
            stream: stream,
            mediaType: mediaType,
            dynamicRange: dynamicRange
        )
    }
}

private struct PreparedPlayerItem {
    let item: AVPlayerItem
    let bridge: LocalHLSBridge?
    let liveProxy: LocalLiveHLSProxy?
    let assets: [AVAsset]
    let isDirectLiveHLS: Bool
}

private extension URL {
    var isLikelyHLSManifest: Bool {
        pathExtension.localizedCaseInsensitiveCompare("m3u8") == .orderedSame
            || absoluteString.range(of: ".m3u8", options: .caseInsensitive) != nil
    }
}

struct LocalHLSBridge: Sendable {
    let masterPlaylistURL: URL
    let mediaTimeOffset: TimeInterval
    let videoClockDelay: TimeInterval
    let videoVariantCount: Int
    let videoVariantQualities: [Int]
    let routePlanCacheState: String
    let serverCacheState: String
    private let seekPlanner: HLSBridgeSeekPlanner?
    private let server: LocalHLSProxyServer

    nonisolated func updateMetricsID(_ metricsID: String?) {
        server.updateMetricsID(metricsID)
    }

    nonisolated func withCacheDiagnostics(routePlanState: String, serverState: String) -> LocalHLSBridge {
        LocalHLSBridge(
            masterPlaylistURL: masterPlaylistURL,
            mediaTimeOffset: mediaTimeOffset,
            videoClockDelay: videoClockDelay,
            videoVariantCount: videoVariantCount,
            videoVariantQualities: videoVariantQualities,
            routePlanCacheState: routePlanState,
            serverCacheState: serverState,
            seekPlanner: seekPlanner,
            server: server
        )
    }

    nonisolated func stop() {
        server.stop()
    }

    nonisolated func alignedSeekTime(near playbackTime: TimeInterval) -> TimeInterval? {
        seekPlanner?.alignedSeekTime(near: playbackTime)
    }

    nonisolated func warmSeekTarget(around playbackTime: TimeInterval, metricsID: String?) {
        guard let seekPlanner else { return }
        Task.detached(priority: .utility) {
            await seekPlanner.warm(around: playbackTime, metricsID: metricsID)
        }
    }

    nonisolated static func make(
        videoTrack: HLSBridgeTrack,
        audioTrack: HLSBridgeTrack,
        durationHint: TimeInterval?,
        headers: [String: String],
        metricsID: String? = nil
    ) async throws -> LocalHLSBridge {
        try await make(
            videoTracks: [videoTrack],
            audioTrack: audioTrack,
            durationHint: durationHint,
            headers: headers,
            metricsID: metricsID
        )
    }

    nonisolated static func make(
        videoTracks: [HLSBridgeTrack],
        audioTrack: HLSBridgeTrack,
        durationHint: TimeInterval?,
        headers: [String: String],
        metricsID: String? = nil
    ) async throws -> LocalHLSBridge {
        guard let primaryVideoTrack = videoTracks.first else {
            throw PlayerEngineError.missingVideoURL
        }
        let start = CACurrentMediaTime()
        PlayerMetricsLog.logger.info(
            "hlsBridgeMakeStart videoQ=\(primaryVideoTrack.stream?.id ?? -1, privacy: .public) videoVariants=\(videoTracks.count, privacy: .public) audioBandwidth=\(audioTrack.stream?.bandwidth ?? 0, privacy: .public)"
        )
        await recordManifestStage(
            metricsID: metricsID,
            "plannedVideo=\(qualitySummary(for: videoTracks))"
        )
        let (plan, planState) = try await routePlan(
            videoTracks: videoTracks,
            audioTrack: audioTrack,
            durationHint: durationHint,
            headers: headers,
            metricsID: metricsID
        )
        let cacheKey = bridgeCacheKey(
            videoTracks: videoTracks,
            audioTrack: audioTrack,
            durationHint: durationHint,
            headers: headers
        )
        let bridgeResult: (bridge: LocalHLSBridge, state: LocalHLSBridgeInstanceCache.State)
        if let cacheKey {
            bridgeResult = try await LocalHLSBridgeInstanceCache.shared.cachedOrBuild(for: cacheKey) {
                try await build(
                    from: plan,
                    headers: headers,
                    metricsID: metricsID
                )
            }
        } else {
            bridgeResult = (
                try await build(
                    from: plan,
                    headers: headers,
                    metricsID: metricsID
                ),
                .miss
            )
        }
        let bridge = bridgeResult.bridge.withCacheDiagnostics(
            routePlanState: planState,
            serverState: bridgeResult.state.rawValue
        )
        bridge.updateMetricsID(metricsID)
        let elapsedMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: start)
        PlayerMetricsLog.logger.info(
            "hlsBridgeMakeReady routePlan=\(planState, privacy: .public) server=\(bridgeResult.state.rawValue, privacy: .public) elapsedMs=\(elapsedMilliseconds, format: .fixed(precision: 1), privacy: .public)"
        )
        await recordManifestStage(
            metricsID: metricsID,
            "bridge=\(planState) server=\(bridgeResult.state.rawValue) total=\(formatMilliseconds(elapsedMilliseconds))"
        )
        return bridge
    }

    @discardableResult
    nonisolated static func prebuildBridge(
        videoTracks: [HLSBridgeTrack],
        audioTrack: HLSBridgeTrack,
        durationHint: TimeInterval?,
        headers: [String: String],
        metricsID: String? = nil,
        waitsForDemuxWarmup: Bool = true
    ) async -> Bool {
        do {
            let bridge = try await make(
                videoTracks: videoTracks,
                audioTrack: audioTrack,
                durationHint: durationHint,
                headers: headers,
                metricsID: metricsID
            )
            if waitsForDemuxWarmup {
                return await FFmpegDemuxWarmupCenter.shared.warmLocalHLSMaster(
                    bridge.masterPlaylistURL,
                    metricsID: metricsID
                )
            }
            Task.detached(priority: .utility) {
                await FFmpegDemuxWarmupCenter.shared.warmLocalHLSMaster(
                    bridge.masterPlaylistURL,
                    metricsID: metricsID
                )
            }
            return true
        } catch {
            PlayerMetricsLog.logger.info(
                "hlsBridgePrebuildFailed error=\(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    @discardableResult
    nonisolated static func prebuildRoutePlan(
        videoTrack: HLSBridgeTrack,
        audioTrack: HLSBridgeTrack,
        durationHint: TimeInterval?,
        headers: [String: String],
        metricsID: String? = nil
    ) async -> Bool {
        await prebuildRoutePlan(
            videoTracks: [videoTrack],
            audioTrack: audioTrack,
            durationHint: durationHint,
            headers: headers,
            metricsID: metricsID
        )
    }

    @discardableResult
    nonisolated static func prebuildRoutePlan(
        videoTracks: [HLSBridgeTrack],
        audioTrack: HLSBridgeTrack,
        durationHint: TimeInterval?,
        headers: [String: String],
        metricsID: String? = nil
    ) async -> Bool {
        guard let primaryVideoTrack = videoTracks.first else { return false }
        guard let cacheKey = bridgeCacheKey(
            videoTracks: videoTracks,
            audioTrack: audioTrack,
            durationHint: durationHint,
            headers: headers
        ) else { return false }

        let start = CACurrentMediaTime()
        do {
            let state = try await HLSBridgeRoutePlanCache.shared.prebuild(for: cacheKey) {
                try await makeRoutePlan(
                    videoTracks: videoTracks,
                    audioTrack: audioTrack,
                    durationHint: durationHint,
                    headers: headers,
                    metricsID: metricsID
                )
            }
            let elapsedMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: start)
            PlayerMetricsLog.logger.info(
                "hlsBridgeRoutePlanPrebuild state=\(state.rawValue, privacy: .public) videoQ=\(primaryVideoTrack.stream?.id ?? -1, privacy: .public) elapsedMs=\(elapsedMilliseconds, format: .fixed(precision: 1), privacy: .public)"
            )
            await recordManifestStage(
                metricsID: metricsID,
                "routePrebuild=\(state.rawValue) \(formatMilliseconds(elapsedMilliseconds))"
            )
            return state != .skippedPending
        } catch {
            PlayerMetricsLog.logger.info(
                "hlsBridgeRoutePlanPrebuildFailed videoQ=\(primaryVideoTrack.stream?.id ?? -1, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    private nonisolated static func routePlan(
        videoTracks: [HLSBridgeTrack],
        audioTrack: HLSBridgeTrack,
        durationHint: TimeInterval?,
        headers: [String: String],
        metricsID: String?
    ) async throws -> (HLSBridgeRoutePlan, String) {
        guard let cacheKey = bridgeCacheKey(
            videoTracks: videoTracks,
            audioTrack: audioTrack,
            durationHint: durationHint,
            headers: headers
        ) else {
            let plan = try await makeRoutePlan(
                videoTracks: videoTracks,
                audioTrack: audioTrack,
                durationHint: durationHint,
                headers: headers,
                metricsID: metricsID
            )
            return (plan, "uncached")
        }

        let result = try await HLSBridgeRoutePlanCache.shared.cachedOrBuild(for: cacheKey) {
            try await makeRoutePlan(
                videoTracks: videoTracks,
                audioTrack: audioTrack,
                durationHint: durationHint,
                headers: headers,
                metricsID: metricsID
            )
        }
        return (result.plan, result.state.rawValue)
    }

    private nonisolated static func makeRoutePlan(
        videoTracks: [HLSBridgeTrack],
        audioTrack: HLSBridgeTrack,
        durationHint: TimeInterval?,
        headers: [String: String],
        metricsID: String?
    ) async throws -> HLSBridgeRoutePlan {
        guard !videoTracks.isEmpty else {
            throw PlayerEngineError.missingVideoURL
        }
        let start = CACurrentMediaTime()
        PlayerMetricsLog.logger.info(
            "hlsBridgeRoutePlanBuildStart videoVariants=\(videoTracks.count, privacy: .public)"
        )
        async let audioRenditionTask = makeRendition(for: audioTrack, durationHint: durationHint, headers: headers, metricsID: metricsID)
        let videoRenditions = try await makeVideoRenditions(
            for: videoTracks,
            durationHint: durationHint,
            headers: headers,
            metricsID: metricsID
        )
        let audioRendition = try await audioRenditionTask
        let renditionMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: start)
        PlayerMetricsLog.logger.info(
            "hlsBridgeRenditionsReady elapsedMs=\(renditionMilliseconds, format: .fixed(precision: 1), privacy: .public) videoVariants=\(videoRenditions.count, privacy: .public) videoRefs=\(videoRenditions.first?.references.count ?? 0, privacy: .public) audioRefs=\(audioRendition.references.count, privacy: .public)"
        )
        await recordManifestStage(
            metricsID: metricsID,
            "renditions=\(formatMilliseconds(renditionMilliseconds)) video=\(qualitySummary(for: videoRenditions)) videoRefs=\(videoRenditions.first?.references.count ?? 0) audioRefs=\(audioRendition.references.count)"
        )

        return HLSBridgeRoutePlan(
            videoRenditions: videoRenditions,
            audioRendition: audioRendition,
            masterPlaylistVersion: masterPlaylistVersion(for: videoRenditions)
        )
    }

    private nonisolated static func makeVideoRenditions(
        for tracks: [HLSBridgeTrack],
        durationHint: TimeInterval?,
        headers: [String: String],
        metricsID: String?
    ) async throws -> [HLSRendition] {
        guard let primaryTrack = tracks.first else { return [] }
        let primaryRendition = try await makeRendition(
            for: primaryTrack,
            durationHint: durationHint,
            headers: headers,
            metricsID: metricsID
        )
        let alternateTracks = Array(tracks.dropFirst())
        guard !alternateTracks.isEmpty else { return [primaryRendition] }
        let waitBudget = optionalVideoRenditionPostPrimaryWaitNanoseconds
        guard waitBudget > 0 else {
            await recordManifestStage(
                metricsID: metricsID,
                "alternateVideo=deferred"
            )
            return [primaryRendition]
        }
        let alternateTask = Task(priority: .utility) {
            await makeOptionalVideoRenditions(
                for: alternateTracks,
                durationHint: durationHint,
                headers: headers,
                metricsID: metricsID
            )
        }
        defer { alternateTask.cancel() }
        let alternateRenditions = await optionalVideoRenditions(
            from: alternateTask,
            waitBudget: waitBudget
        )
        return [primaryRendition] + alternateRenditions
    }

    private nonisolated static func optionalVideoRenditions(
        from task: Task<[HLSRendition], Never>,
        waitBudget: UInt64
    ) async -> [HLSRendition] {
        guard waitBudget > 0 else { return [] }
        let timeoutTask = Task(priority: .utility) { () -> [HLSRendition] in
            try? await Task.sleep(nanoseconds: waitBudget)
            return []
        }
        defer {
            timeoutTask.cancel()
        }
        return await withTaskGroup(of: [HLSRendition].self, returning: [HLSRendition].self) { group in
            group.addTask { await task.value }
            group.addTask { await timeoutTask.value }
            let renditions = await group.next() ?? []
            group.cancelAll()
            return renditions
        }
    }

    private nonisolated static func build(
        from plan: HLSBridgeRoutePlan,
        headers: [String: String],
        metricsID: String?
    ) async throws -> LocalHLSBridge {
        guard let videoRendition = plan.videoRenditions.first else {
            throw PlayerEngineError.missingVideoURL
        }
        let start = CACurrentMediaTime()
        let videoRenditions = plan.videoRenditions
        let audioRendition = plan.audioRendition
        let server = try LocalHLSProxyServer.make(headers: headers, metricsID: metricsID)
        let baseURL = server.baseURL
        let audioPlaylistURL = baseURL.appendingPathComponent("audio.m3u8")
        let masterPlaylistURL = baseURL.appendingPathComponent("master.m3u8")
        let audioPlaylist = audioRendition.playlist(baseURL: baseURL, routePrefix: "audio")
        let videoPlaylistEntries = videoRenditions.enumerated().map { index, rendition in
            let routePrefix = videoRoutePrefix(for: index)
            let playlistURL = baseURL.appendingPathComponent("\(routePrefix).m3u8")
            return """
            #EXT-X-STREAM-INF:BANDWIDTH=\(rendition.bandwidth),CODECS="\(rendition.codec),\(audioRendition.codec)",AUDIO="audio"\(rendition.hlsResolutionAttribute)\(rendition.hlsVideoRangeAttribute)\(rendition.hlsAdvertisedSupplementalCodecAttribute)
            \(playlistURL.absoluteString)
            """
        }.joined(separator: "\n")
        let masterPlaylist = """
        #EXTM3U
        #EXT-X-VERSION:\(plan.masterPlaylistVersion)
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="audio",DEFAULT=YES,AUTOSELECT=YES,URI="\(audioPlaylistURL.absoluteString)"
        \(videoPlaylistEntries)
        """

        var routes: [String: HLSProxyRoute] = [
            "/master.m3u8": .data(Data(masterPlaylist.utf8), contentType: "application/vnd.apple.mpegurl"),
            "/audio.m3u8": .data(Data(audioPlaylist.utf8), contentType: "application/vnd.apple.mpegurl")
        ]
        for (index, rendition) in videoRenditions.enumerated() {
            let routePrefix = videoRoutePrefix(for: index)
            let playlist = rendition.playlist(baseURL: baseURL, routePrefix: routePrefix)
            routes["/\(routePrefix).m3u8"] = .data(Data(playlist.utf8), contentType: "application/vnd.apple.mpegurl")
            rendition.registerRoutes(routePrefix: routePrefix, into: &routes)
        }
        audioRendition.registerRoutes(routePrefix: "audio", into: &routes)
        server.updateRoutes(routes)
        try await server.start()
        let serverMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: start)
        PlayerMetricsLog.logger.info(
            "hlsBridgeServerReady elapsedMs=\(serverMilliseconds, format: .fixed(precision: 1), privacy: .public) dynamicRange=\(videoRendition.dynamicRange.rawValue, privacy: .public) codec=\(videoRendition.codec, privacy: .public) version=\(plan.masterPlaylistVersion, privacy: .public) variants=\(videoRenditions.count, privacy: .public) routes=\(routes.count, privacy: .public)"
        )
        await recordManifestStage(
            metricsID: metricsID,
            "server=\(formatMilliseconds(serverMilliseconds)) routes=\(routes.count) variants=\(videoRenditions.count) codec=\(videoRendition.codec)"
        )

        let originalMediaTimeOffset = [videoRendition.mediaTimeOffset, audioRendition.mediaTimeOffset]
            .filter { $0.isFinite && $0 > 0 }
            .min() ?? 0
        let originalVideoClockDelay = normalizedVideoClockDelay(
            audioStart: audioRendition.mediaTimeOffset,
            videoStart: videoRendition.mediaTimeOffset
        )
        if abs(originalVideoClockDelay) > 0.001 || originalMediaTimeOffset > 0.001 {
            PlayerMetricsLog.logger.info(
                "hlsBridgeTimelineNormalize audioStart=\(audioRendition.mediaTimeOffset, format: .fixed(precision: 3), privacy: .public) videoStart=\(videoRendition.mediaTimeOffset, format: .fixed(precision: 3), privacy: .public) originalVideoDelay=\(originalVideoClockDelay, format: .fixed(precision: 3), privacy: .public)"
            )
        }

        return LocalHLSBridge(
            masterPlaylistURL: masterPlaylistURL,
            mediaTimeOffset: 0,
            videoClockDelay: 0,
            videoVariantCount: videoRenditions.count,
            videoVariantQualities: videoRenditions.compactMap(\.quality),
            routePlanCacheState: "-",
            serverCacheState: "-",
            seekPlanner: HLSBridgeSeekPlanner(
                video: videoRendition.seekMap(includeExtraSegment: true),
                audio: audioRendition.seekMap(includeExtraSegment: false),
                headers: headers
            ),
            server: server
        )
    }

    private nonisolated static func normalizedVideoClockDelay(audioStart: TimeInterval, videoStart: TimeInterval) -> TimeInterval {
        guard audioStart.isFinite, videoStart.isFinite else { return 0 }
        let delay = audioStart - videoStart
        guard delay.isFinite, abs(delay) <= 60 else { return 0 }
        return abs(delay) < 0.001 ? 0 : delay
    }

    private nonisolated static func videoRoutePrefix(for index: Int) -> String {
        index == 0 ? "video" : "video-\(index)"
    }

    private nonisolated static func qualitySummary(for tracks: [HLSBridgeTrack]) -> String {
        let qualities = tracks.compactMap { $0.stream?.id }
        guard !qualities.isEmpty else { return "-" }
        return qualities
            .map { "q\($0)" }
            .joined(separator: "/")
    }

    private nonisolated static func qualitySummary(for renditions: [HLSRendition]) -> String {
        let qualities = renditions.compactMap(\.quality)
        guard !qualities.isEmpty else { return "-" }
        return qualities
            .map { "q\($0)" }
            .joined(separator: "/")
    }

    private nonisolated static func masterPlaylistVersion(for videoRenditions: [HLSRendition]) -> Int {
        if videoRenditions.contains(where: { !$0.hlsAdvertisedSupplementalCodecAttribute.isEmpty }) {
            return 10
        }
        if videoRenditions.contains(where: { !$0.hlsVideoRangeAttribute.isEmpty }) {
            return 8
        }
        return 7
    }

    private nonisolated static func recordManifestStage(metricsID: String?, _ message: String) async {
        guard let metricsID, !metricsID.isEmpty else { return }
        await PlayerMetricsLog.record(.manifestStage, metricsID: metricsID, message: message)
    }

    private nonisolated static func makeOptionalVideoRenditions(
        for tracks: [HLSBridgeTrack],
        durationHint: TimeInterval?,
        headers: [String: String],
        metricsID: String?
    ) async -> [HLSRendition] {
        guard !tracks.isEmpty else { return [] }
        let budget = optionalVideoRenditionBudgetNanoseconds
        let results = await withTaskGroup(of: (Int, HLSRendition)?.self, returning: [(Int, HLSRendition)].self) { group in
            for (index, track) in tracks.enumerated() {
                group.addTask {
                    await makeOptionalVideoRendition(
                        for: track,
                        index: index,
                        durationHint: durationHint,
                        headers: headers,
                        metricsID: metricsID,
                        budget: budget
                    )
                }
            }
            var renditions = [(Int, HLSRendition)]()
            for await result in group {
                if let result {
                    renditions.append(result)
                }
            }
            return renditions
        }
        let renditions = results
            .sorted { $0.0 < $1.0 }
            .map(\.1)
        if renditions.count < tracks.count {
            await recordManifestStage(
                metricsID: metricsID,
                "alternateVideo=\(renditions.count)/\(tracks.count)"
            )
        }
        return renditions
    }

    private nonisolated static func makeOptionalVideoRendition(
        for track: HLSBridgeTrack,
        index: Int,
        durationHint: TimeInterval?,
        headers: [String: String],
        metricsID: String?,
        budget: UInt64
    ) async -> (Int, HLSRendition)? {
        let buildTask = Task(priority: .utility) { () -> HLSRendition? in
            guard !Task.isCancelled else { return nil }
            do {
                return try await makeRendition(
                    for: track,
                    durationHint: durationHint,
                    headers: headers,
                    metricsID: metricsID
                )
            } catch {
                PlayerMetricsLog.logger.info(
                    "hlsBridgeAlternateVideoSkipped q=\(track.stream?.id ?? -1, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                return nil
            }
        }
        let timeoutTask = Task(priority: .utility) { () -> HLSRendition? in
            try? await Task.sleep(nanoseconds: budget)
            return nil
        }
        let rendition = await withTaskGroup(of: HLSRendition?.self, returning: HLSRendition?.self) { group in
            group.addTask { await buildTask.value }
            group.addTask { await timeoutTask.value }
            let firstResult = await group.next() ?? nil
            group.cancelAll()
            buildTask.cancel()
            timeoutTask.cancel()
            return firstResult
        }
        guard let rendition else {
            PlayerMetricsLog.logger.info(
                "hlsBridgeAlternateVideoTimedOut q=\(track.stream?.id ?? -1, privacy: .public)"
            )
            return nil
        }
        return (index, rendition)
    }

    private nonisolated static var optionalVideoRenditionBudgetNanoseconds: UInt64 {
        switch PlaybackEnvironment.current.networkClass {
        case .wifi:
            return 260_000_000
        case .unknown:
            return 180_000_000
        case .cellular, .constrained:
            return 120_000_000
        }
    }

    private nonisolated static var optionalVideoRenditionPostPrimaryWaitNanoseconds: UInt64 {
        0
    }

    private nonisolated static func formatMilliseconds(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        if rounded >= 1000 {
            return String(format: "%.2fs", Double(rounded) / 1000)
        }
        return "\(rounded)ms"
    }

    private nonisolated static func startupWarmRanges(
        initialization: HTTPByteRange,
        references: [SIDXParser.Reference],
        includeExtraVideoSegment: Bool
    ) -> [HTTPByteRange] {
        var ranges = [initialization]
        ranges += references.prefix(includeExtraVideoSegment ? 2 : 1).map(\.range)
        return ranges
    }

    private nonisolated static func warmRanges(
        _ ranges: [HTTPByteRange],
        from urls: [URL],
        headers: [String: String],
        strategy: HLSByteRangeFetchStrategy,
        delayStepNanoseconds: UInt64 = 180_000_000
    ) async {
        await withTaskGroup(of: Void.self) { group in
            for (index, range) in ranges.enumerated() {
                group.addTask {
                    if index > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(index) * delayStepNanoseconds)
                    }
                    await warmRange(range, from: urls, headers: headers, strategy: strategy)
                }
            }
        }
    }

    private nonisolated static func warmRange(
        _ range: HTTPByteRange?,
        from urls: [URL],
        headers: [String: String],
        strategy: HLSByteRangeFetchStrategy
    ) async {
        guard let range else { return }
        _ = try? await fetchByteRange(range, from: urls, headers: headers, strategy: strategy)
    }

    private nonisolated static func makeRendition(
        for track: HLSBridgeTrack,
        durationHint: TimeInterval?,
        headers: [String: String],
        metricsID: String?
    ) async throws -> HLSRendition {
        guard let segmentBase = track.stream?.segmentBase,
              let initialization = segmentBase.initializationByteRange,
              let indexRange = segmentBase.indexByteRange
        else {
            throw PlayerEngineError.unsupportedMedia
        }

        let start = CACurrentMediaTime()
        let mediaType = track.mediaType.logLabel
        PlayerMetricsLog.logger.info(
            "hlsBridgeRenditionStart media=\(mediaType, privacy: .public) quality=\(track.stream?.id ?? -1, privacy: .public) index=\(indexRange.start, privacy: .public)-\(indexRange.endInclusive, privacy: .public)"
        )
        let renditionResult = try await HLSRenditionCache.shared.cachedOrBuild(
            for: renditionCacheKey(for: track, initialization: initialization, indexRange: indexRange)
        ) {
            let fetchStart = CACurrentMediaTime()
            let sourceURLs = [track.url] + track.fallbackURLs
            let bootstrapPayload = try await fetchRenditionBootstrapPayload(
                initialization: initialization,
                indexRange: indexRange,
                from: sourceURLs,
                headers: headers
            )
            await recordManifestStage(
                metricsID: metricsID,
                "\(mediaType)Boot=\(bootstrapPayload.mode) \(formatMilliseconds(PlayerMetricsLog.elapsedMilliseconds(since: fetchStart)))"
            )
            PlayerMetricsLog.logger.info(
                "hlsBridgeIndexFetched media=\(mediaType, privacy: .public) mode=\(bootstrapPayload.mode, privacy: .public) bytes=\(bootstrapPayload.indexData.count, privacy: .public) initBytes=\(bootstrapPayload.initializationData?.count ?? 0, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: fetchStart), format: .fixed(precision: 1), privacy: .public)"
            )
            let parseStart = CACurrentMediaTime()
            let references = try SIDXParser.parseReferences(from: bootstrapPayload.indexData, sidxStartOffset: indexRange.start)
            guard !references.isEmpty else {
                throw PlayerEngineError.unsupportedMedia
            }
            let resolvedTimelineOffset = await startupTimelineOffset(
                for: track,
                references: references,
                headers: headers,
                metricsID: metricsID
            )
            PlayerMetricsLog.logger.info(
                "hlsBridgeIndexParsed media=\(mediaType, privacy: .public) refs=\(references.count, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: parseStart), format: .fixed(precision: 1), privacy: .public)"
            )
            return makeRendition(
                for: track,
                initialization: initialization,
                initializationData: bootstrapPayload.initializationData,
                references: references,
                durationHint: durationHint,
                timelineOffsetOverride: resolvedTimelineOffset
            )
        }
        let rendition = renditionResult.rendition
        let elapsedMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: start)
        PlayerMetricsLog.logger.info(
            "hlsBridgeRenditionReady media=\(mediaType, privacy: .public) state=\(renditionResult.state.rawValue, privacy: .public) elapsedMs=\(elapsedMilliseconds, format: .fixed(precision: 1), privacy: .public)"
        )
        await recordManifestStage(
            metricsID: metricsID,
            "\(mediaType)=\(renditionResult.state.rawValue) \(formatMilliseconds(elapsedMilliseconds)) refs=\(rendition.references.count)"
        )
        return rendition
    }

    private struct HLSRenditionBootstrapPayload: Sendable {
        let initializationData: Data?
        let indexData: Data
        let mode: String
    }

    private nonisolated static func fetchRenditionBootstrapPayload(
        initialization: HTTPByteRange,
        indexRange: HTTPByteRange,
        from urls: [URL],
        headers: [String: String]
    ) async throws -> HLSRenditionBootstrapPayload {
        let strategy = bootstrapFetchStrategy(urlCount: urls.count)
        if let combinedRange = combinedBootstrapRange(initialization: initialization, indexRange: indexRange) {
            do {
                let combinedData = try await fetchByteRange(
                    combinedRange,
                    from: urls,
                    headers: headers,
                    policy: strategy
                )
                if let initializationData = dataSlice(for: initialization, in: combinedData, baseRange: combinedRange),
                   let indexData = dataSlice(for: indexRange, in: combinedData, baseRange: combinedRange) {
                    return HLSRenditionBootstrapPayload(
                        initializationData: initializationData,
                        indexData: indexData,
                        mode: "\(strategy.fetchStrategy.logLabel)+init"
                    )
                }
            } catch {
                PlayerMetricsLog.logger.info(
                    "hlsBridgeBootstrapCombinedFallback range=\(combinedRange.start, privacy: .public)-\(combinedRange.endInclusive, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
            }
        }

        let indexData = try await fetchByteRange(
            indexRange,
            from: urls,
            headers: headers,
            policy: strategy
        )
        return HLSRenditionBootstrapPayload(
            initializationData: nil,
            indexData: indexData,
            mode: strategy.fetchStrategy.logLabel
        )
    }

    private nonisolated static func combinedBootstrapRange(
        initialization: HTTPByteRange,
        indexRange: HTTPByteRange
    ) -> HTTPByteRange? {
        guard initialization.length > 0, indexRange.length > 0 else { return nil }
        let lowerBound = min(initialization.start, indexRange.start)
        let upperBound = max(initialization.endInclusive, indexRange.endInclusive)
        guard upperBound >= lowerBound else { return nil }

        let gap: Int64
        if initialization.endInclusive < indexRange.start {
            gap = indexRange.start - initialization.endInclusive - 1
        } else if indexRange.endInclusive < initialization.start {
            gap = initialization.start - indexRange.endInclusive - 1
        } else {
            gap = 0
        }

        let combinedLength = upperBound - lowerBound + 1
        guard gap <= maxBootstrapCombinedGapBytes,
              combinedLength <= maxBootstrapCombinedRangeBytes
        else { return nil }
        return HTTPByteRange(start: lowerBound, endInclusive: upperBound)
    }

    private nonisolated static func dataSlice(
        for range: HTTPByteRange,
        in data: Data,
        baseRange: HTTPByteRange
    ) -> Data? {
        guard range.start >= baseRange.start,
              range.endInclusive <= baseRange.endInclusive,
              let lowerBound = Int(exactly: range.start - baseRange.start),
              let length = Int(exactly: range.length),
              length > 0,
              lowerBound >= 0,
              lowerBound + length <= data.count
        else { return nil }
        return data.subdata(in: lowerBound..<(lowerBound + length))
    }

    private nonisolated static func fetchIndexRange(
        indexRange: HTTPByteRange,
        from urls: [URL],
        headers: [String: String]
    ) async throws -> (indexData: Data, mode: String) {
        let strategy = bootstrapFetchStrategy(urlCount: urls.count)
        let indexData = try await fetchByteRange(
            indexRange,
            from: urls,
            headers: headers,
            policy: strategy
        )
        return (indexData, strategy.fetchStrategy.logLabel)
    }

    private nonisolated static func bootstrapFetchStrategy(urlCount: Int) -> HLSBootstrapFetchPolicy {
        let strategy: HLSByteRangeFetchStrategy = PlaybackEnvironment.current.shouldPreferConservativePlayback
            ? .sequential
            : .fastFallback
        return HLSBootstrapFetchPolicy(
            fetchStrategy: strategy,
            remoteRequestPolicy: .startupIndex(urlCount: urlCount)
        )
    }

    private nonisolated static let maxBootstrapCombinedRangeBytes: Int64 = 256 * 1024
    private nonisolated static let maxBootstrapCombinedGapBytes: Int64 = 32 * 1024

    fileprivate nonisolated static func fetchByteRange(
        _ range: HTTPByteRange,
        from url: URL,
        headers: [String: String]
    ) async throws -> Data {
        try await VideoRangeCache.shared.cachedOrFetch(url: url, range: range) {
            try await fetchRemoteByteRangeWithRetry(
                range,
                from: url,
                headers: headers,
                policy: .default(for: range)
            )
        }
    }

    fileprivate nonisolated static func fetchByteRange(
        _ range: HTTPByteRange,
        from urls: [URL],
        headers: [String: String],
        strategy: HLSByteRangeFetchStrategy = .sequential
    ) async throws -> Data {
        try await fetchByteRange(
            range,
            from: urls,
            headers: headers,
            policy: HLSBootstrapFetchPolicy(
                fetchStrategy: strategy,
                remoteRequestPolicy: .default(for: range)
            )
        )
    }

    fileprivate nonisolated static func fetchByteRange(
        _ range: HTTPByteRange,
        from urls: [URL],
        headers: [String: String],
        policy: HLSBootstrapFetchPolicy
    ) async throws -> Data {
        let canonicalSourceURLs = urls.removingDuplicates()
        guard let primaryURL = canonicalSourceURLs.first else {
            throw PlayerEngineError.unsupportedMedia
        }
        let sourceURLs = await HLSSourcePreferenceCache.shared.preferredURLs(for: canonicalSourceURLs)
        guard policy.fetchStrategy.isFastFallback, sourceURLs.count > 1 else {
            return try await fetchByteRangeSequential(
                range,
                from: sourceURLs,
                primaryURL: primaryURL,
                headers: headers,
                remoteRequestPolicy: policy.remoteRequestPolicy
            )
        }

        return try await fetchByteRangeFastFallback(
            range,
            from: sourceURLs,
            primaryURL: primaryURL,
            headers: headers,
            remoteRequestPolicy: policy.remoteRequestPolicy
        )
    }

    private nonisolated static func fetchByteRangeSequential(
        _ range: HTTPByteRange,
        from sourceURLs: [URL],
        primaryURL: URL,
        headers: [String: String],
        remoteRequestPolicy: HLSRemoteByteRangeRequestPolicy
    ) async throws -> Data {
        guard !sourceURLs.isEmpty else {
            throw PlayerEngineError.unsupportedMedia
        }
        var lastError: Error?
        for (index, url) in sourceURLs.enumerated() {
            let fetchStart = CACurrentMediaTime()
            do {
                let cacheResult = try await VideoRangeCache.shared.cachedOrFetchWithSource(url: url, range: range) {
                    try await fetchRemoteByteRangeWithRetry(
                        range,
                        from: url,
                        headers: headers,
                        policy: remoteRequestPolicy
                    )
                }
                let data = cacheResult.data
                if cacheResult.source == .remote {
                    await HLSSourcePreferenceCache.shared.recordResult(
                        url: url,
                        for: sourceURLs,
                        elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: fetchStart),
                        bytes: Int64(data.count),
                        succeeded: true
                    )
                }
                if index > 0 {
                    if cacheResult.source == .remote {
                        await HLSSourcePreferenceCache.shared.recordPreferredURL(url, for: sourceURLs)
                    }
                    await VideoRangeCache.shared.store(data, url: primaryURL, range: range)
                    PlayerMetricsLog.logger.info(
                        "hlsBridgeByteRangeFallbackSuccess fallbackIndex=\(index, privacy: .public) range=\(range.start, privacy: .public)-\(range.endInclusive, privacy: .public)"
                    )
                }
                return data
            } catch {
                await HLSSourcePreferenceCache.shared.recordFailure(
                    url: url,
                    for: sourceURLs,
                    elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: fetchStart),
                    error: error
                )
                lastError = error
                guard index < sourceURLs.count - 1, !Task.isCancelled else { break }
                PlayerMetricsLog.logger.info(
                    "hlsBridgeByteRangeFallbackSwitch fallbackIndex=\(index + 1, privacy: .public) range=\(range.start, privacy: .public)-\(range.endInclusive, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
            }
        }
        throw lastError ?? PlayerEngineError.unsupportedMedia
    }

    private nonisolated static func fetchByteRangeFastFallback(
        _ range: HTTPByteRange,
        from sourceURLs: [URL],
        primaryURL: URL,
        headers: [String: String],
        remoteRequestPolicy: HLSRemoteByteRangeRequestPolicy
    ) async throws -> Data {
        let result: Result<(index: Int, data: Data, source: VideoRangeCacheFetchSource), Error> = await withTaskGroup(of: Result<(index: Int, data: Data, source: VideoRangeCacheFetchSource), Error>.self) { group in
            for (index, url) in sourceURLs.enumerated() {
                group.addTask(priority: .userInitiated) {
                    let fetchStart = CACurrentMediaTime()
                    do {
                        if index > 0 {
                            let delay = remoteRequestPolicy.fastFallbackDelayNanoseconds(forSourceIndex: index)
                            try await Task.sleep(nanoseconds: delay)
                        }
                        let cacheResult = try await VideoRangeCache.shared.cachedOrFetchWithSource(url: url, range: range) {
                            try await fetchRemoteByteRangeWithRetry(
                                range,
                                from: url,
                                headers: headers,
                                policy: remoteRequestPolicy
                            )
                        }
                        let data = cacheResult.data
                        if cacheResult.source == .remote {
                            await HLSSourcePreferenceCache.shared.recordResult(
                                url: url,
                                for: sourceURLs,
                                elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: fetchStart),
                                bytes: Int64(data.count),
                                succeeded: true
                            )
                        }
                        return .success((index, data, cacheResult.source))
                    } catch {
                        await HLSSourcePreferenceCache.shared.recordFailure(
                            url: url,
                            for: sourceURLs,
                            elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: fetchStart),
                            error: error
                        )
                        return .failure(error)
                    }
                }
            }

            var lastError: Error?
            for await result in group {
                switch result {
                case let .success(payload):
                    group.cancelAll()
                    return Result<(index: Int, data: Data, source: VideoRangeCacheFetchSource), Error>.success(payload)
                case let .failure(error):
                    lastError = error
                }
            }
            return .failure(lastError ?? PlayerEngineError.unsupportedMedia)
        }

        switch result {
        case let .success(payload):
            if payload.source == .remote, let preferredURL = sourceURLs[safe: payload.index] {
                await HLSSourcePreferenceCache.shared.recordPreferredURL(preferredURL, for: sourceURLs)
            }
            if payload.index > 0 {
                await VideoRangeCache.shared.store(payload.data, url: primaryURL, range: range)
                PlayerMetricsLog.logger.info(
                    "hlsBridgeByteRangeFastFallbackSuccess fallbackIndex=\(payload.index, privacy: .public) range=\(range.start, privacy: .public)-\(range.endInclusive, privacy: .public)"
                )
            }
            return payload.data
        case let .failure(error):
            throw error
        }
    }

    private nonisolated static func fetchRemoteByteRangeWithRetry(
        _ range: HTTPByteRange,
        from url: URL,
        headers: [String: String],
        policy: HLSRemoteByteRangeRequestPolicy
    ) async throws -> Data {
        var lastError: Error?
        for attempt in 0..<policy.attempts {
            do {
                return try await fetchRemoteByteRange(
                    range,
                    from: url,
                    headers: headers,
                    timeoutInterval: policy.timeoutInterval(for: range)
                )
            } catch {
                lastError = error
                guard attempt < policy.attempts - 1, !Task.isCancelled else { break }
                PlayerMetricsLog.logger.info(
                    "hlsBridgeByteRangeRetry attempt=\(attempt + 1, privacy: .public) range=\(range.start, privacy: .public)-\(range.endInclusive, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                try? await Task.sleep(nanoseconds: policy.retryDelayNanoseconds)
            }
        }
        throw lastError ?? PlayerEngineError.unsupportedMedia
    }

    fileprivate nonisolated static func fetchRemoteByteRange(
        _ range: HTTPByteRange,
        from url: URL,
        headers: [String: String]
    ) async throws -> Data {
        try await fetchRemoteByteRange(
            range,
            from: url,
            headers: headers,
            timeoutInterval: HLSRemoteByteRangeRequestPolicy.default(for: range).timeoutInterval(for: range)
        )
    }

    fileprivate nonisolated static func fetchRemoteByteRange(
        _ range: HTTPByteRange,
        from url: URL,
        headers: [String: String],
        timeoutInterval: TimeInterval
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = timeoutInterval
        request.networkServiceType = .video
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.setValue("bytes=\(range.start)-\(range.endInclusive)", forHTTPHeaderField: "Range")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await BiliPlaybackNetworkSessionPool.shared.playbackDataSession().data(for: request)
        } catch let error as URLError {
            throw HLSBridgeRemoteFailure.urlSession(error, url: url, range: range)
        } catch {
            throw error
        }
        do {
            try HLSRemoteRangeResponseValidator.validate(response, requestedRange: range, url: url)
        } catch {
            if let httpResponse = response as? HTTPURLResponse {
                PlayerMetricsLog.logger.error(
                    "hlsBridgeByteRangeHTTPError status=\(httpResponse.statusCode, privacy: .public) range=\(range.start, privacy: .public)-\(range.endInclusive, privacy: .public) url=\(url.absoluteString, privacy: .private)"
                )
            }
            throw error
        }
        guard !data.isEmpty else {
            PlayerMetricsLog.logger.error(
                "hlsBridgeByteRangeEmptyResponse range=\(range.start, privacy: .public)-\(range.endInclusive, privacy: .public) url=\(url.absoluteString, privacy: .private)"
            )
            throw HLSBridgeRemoteFailure.emptyResponse(url: url, range: range)
        }
        return data
    }

    @discardableResult
    nonisolated static func warmup(
        videoTrack: HLSBridgeTrack,
        audioTrack: HLSBridgeTrack?,
        headers: [String: String],
        around playbackTime: TimeInterval? = nil
    ) async -> Bool {
        await warmup(
            videoTracks: [videoTrack],
            audioTrack: audioTrack,
            headers: headers,
            around: playbackTime
        )
    }

    @discardableResult
    nonisolated static func warmup(
        videoTracks: [HLSBridgeTrack],
        audioTrack: HLSBridgeTrack?,
        headers: [String: String],
        around playbackTime: TimeInterval? = nil
    ) async -> Bool {
        let tracks = videoTracks + [audioTrack].compactMap { $0 }
        guard !tracks.isEmpty else { return false }
        return await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            for track in tracks {
                group.addTask(priority: .utility) {
                    await warmup(track: track, headers: headers, around: playbackTime)
                }
            }

            var didWarm = false
            for await result in group where result {
                didWarm = true
            }
            return didWarm
        }
    }

    nonisolated static func clearWarmupCache() async {
        await HLSBridgeRoutePlanCache.shared.removeAll()
        await LocalHLSBridgeInstanceCache.shared.removeAll()
        await HLSRenditionCache.shared.removeAll()
    }

    nonisolated static func sourceDiagnostics(for urls: [URL]) async -> [HLSBridgeSourceDiagnosticsSnapshot] {
        await HLSSourcePreferenceCache.shared.diagnostics(for: urls)
    }

    private nonisolated static func warmup(
        track: HLSBridgeTrack,
        headers: [String: String],
        around playbackTime: TimeInterval? = nil
    ) async -> Bool {
        guard let segmentBase = track.stream?.segmentBase,
              let initialization = segmentBase.initializationByteRange,
              let indexRange = segmentBase.indexByteRange
        else { return false }

        do {
            let sourceURLs = [track.url] + track.fallbackURLs
            let renditionResult = try await HLSRenditionCache.shared.cachedOrBuild(
                for: renditionCacheKey(for: track, initialization: initialization, indexRange: indexRange)
            ) {
                let bootstrapPayload = try await fetchRenditionBootstrapPayload(
                    initialization: initialization,
                    indexRange: indexRange,
                    from: sourceURLs,
                    headers: headers
                )
                let references = try SIDXParser.parseReferences(from: bootstrapPayload.indexData, sidxStartOffset: indexRange.start)
                guard !references.isEmpty else {
                    throw PlayerEngineError.unsupportedMedia
                }
                let resolvedTimelineOffset = await startupTimelineOffset(
                    for: track,
                    references: references,
                    headers: headers,
                    metricsID: nil
                )
                return makeRendition(
                    for: track,
                    initialization: initialization,
                    initializationData: bootstrapPayload.initializationData,
                    references: references,
                    durationHint: nil,
                    timelineOffsetOverride: resolvedTimelineOffset
                )
            }
            let strategy = bootstrapFetchStrategy(urlCount: sourceURLs.count)
            await warmRanges(
                warmRanges(
                    initialization: initialization,
                    references: renditionResult.rendition.references,
                    mediaTimeOffset: renditionResult.rendition.mediaTimeOffset,
                    includeExtraVideoSegment: track.mediaType.isVideo,
                    around: playbackTime
                ),
                from: sourceURLs,
                headers: headers,
                strategy: strategy.fetchStrategy,
                delayStepNanoseconds: 0
            )
            return true
        } catch {
            return false
        }
    }

    private nonisolated static func warmRanges(
        initialization: HTTPByteRange,
        references: [SIDXParser.Reference],
        mediaTimeOffset: TimeInterval,
        includeExtraVideoSegment: Bool,
        around playbackTime: TimeInterval?
    ) -> [HTTPByteRange] {
        guard let playbackTime, playbackTime.isFinite, playbackTime > 0 else {
            return startupWarmRanges(
                initialization: initialization,
                references: references,
                includeExtraVideoSegment: includeExtraVideoSegment
            )
        }
        guard !references.isEmpty else { return [initialization] }
        let targetTime = max(0, playbackTime + mediaTimeOffset)
        let startIndex = references.lastIndex { reference in
            reference.startTime <= targetTime
        } ?? 0
        let segmentCount = includeExtraVideoSegment ? 3 : 2
        let endIndex = min(references.count, startIndex + segmentCount)
        return [initialization] + references[startIndex..<endIndex].map(\.range)
    }

    private nonisolated static func makeRendition(
        for track: HLSBridgeTrack,
        initialization: HTTPByteRange,
        initializationData: Data?,
        references: [SIDXParser.Reference],
        durationHint: TimeInterval?,
        timelineOffsetOverride: HLSRenditionTimelineOffset?
    ) -> HLSRendition {
        let timelineOffset = timelineOffsetOverride ?? HLSRenditionTimelineOffset(
            baseMediaDecodeTimeTicks: references.first?.startTimeTicks ?? 0
        )
        let mediaTimeOffsetTicks = timelineOffset.baseMediaDecodeTimeTicks
        let timescale = references.first?.timescale ?? 0
        let mediaTimeOffset = timescale > 0
            ? TimeInterval(mediaTimeOffsetTicks) / TimeInterval(timescale)
            : references.first?.startTime ?? 0
        return HLSRendition(
            sourceURL: track.url,
            fallbackSourceURLs: track.fallbackURLs,
            mediaType: track.mediaType,
            quality: track.stream?.id,
            initialization: initialization,
            initializationData: initializationData,
            references: references,
            targetDuration: max(references.map(\.duration).max() ?? durationHint ?? 1, 1),
            bandwidth: max(track.stream?.bandwidth ?? 0, 128_000),
            codec: normalizedCodec(track.stream?.codecs, mediaType: track.mediaType),
            mediaTimeOffset: mediaTimeOffset,
            baseMediaDecodeTimeOffsetTicks: timelineOffset.baseMediaDecodeTimeTicks,
            dynamicRange: track.dynamicRange,
            dimensions: track.stream?.hlsDimensions
        )
    }

    private nonisolated static func startupTimelineOffset(
        for track: HLSBridgeTrack,
        references: [SIDXParser.Reference],
        headers _: [String: String],
        metricsID: String?
    ) async -> HLSRenditionTimelineOffset? {
        guard let firstReference = references.first else { return nil }
        await recordManifestStage(
            metricsID: metricsID,
            "\(track.mediaType.logLabel)Probe=sidx"
        )
        return HLSRenditionTimelineOffset(
            baseMediaDecodeTimeTicks: firstReference.startTimeTicks
        )
    }

    private nonisolated static func renditionCacheKey(
        for track: HLSBridgeTrack,
        initialization: HTTPByteRange,
        indexRange: HTTPByteRange
    ) -> String {
        let mediaType = switch track.mediaType {
        case .audio:
            "audio"
        case .video:
            "video"
        }
        return [
            "timeline-v9-bootstrap-init",
            mediaType,
            track.cacheIdentity,
            "\(initialization.start)-\(initialization.endInclusive)",
            "\(indexRange.start)-\(indexRange.endInclusive)",
            "\(track.stream?.bandwidth ?? 0)",
            track.stream?.codecs ?? "",
            track.dynamicRange.rawValue
        ].joined(separator: "|")
    }

    private nonisolated static func bridgeCacheKey(
        videoTracks: [HLSBridgeTrack],
        audioTrack: HLSBridgeTrack,
        durationHint: TimeInterval?,
        headers: [String: String]
    ) -> String? {
        let videoKeys = videoTracks.compactMap(bridgeTrackCacheKey(for:))
        guard videoKeys.count == videoTracks.count,
              let audioKey = bridgeTrackCacheKey(for: audioTrack)
        else { return nil }
        let durationKey: String
        if let durationHint, durationHint.isFinite, durationHint > 0 {
            durationKey = String(format: "%.3f", durationHint)
        } else {
            durationKey = "-"
        }
        let headerKey = headers
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        return [
            "route-plan-v1",
            videoKeys.joined(separator: "@@"),
            audioKey,
            durationKey,
            headerKey
        ].joined(separator: "||")
    }

    private nonisolated static func bridgeTrackCacheKey(for track: HLSBridgeTrack) -> String? {
        guard let segmentBase = track.stream?.segmentBase,
              let initialization = segmentBase.initializationByteRange,
              let indexRange = segmentBase.indexByteRange
        else { return nil }
        return renditionCacheKey(for: track, initialization: initialization, indexRange: indexRange)
    }

    private nonisolated static func normalizedCodec(_ codec: String?, mediaType: HLSBridgeTrack.MediaType) -> String {
        guard let codec, !codec.isEmpty else {
            switch mediaType {
            case .audio:
                return "mp4a.40.2"
            case .video:
                return "hvc1.1.6.L120.B0"
            }
        }
        return codec
    }

    fileprivate nonisolated static func formatDuration(_ duration: TimeInterval) -> String {
        String(format: "%.6f", max(duration, 0.001))
    }
}

private struct HLSRendition: Sendable {
    let sourceURL: URL
    let fallbackSourceURLs: [URL]
    let mediaType: HLSBridgeTrack.MediaType
    let quality: Int?
    let initialization: HTTPByteRange
    let initializationData: Data?
    let references: [SIDXParser.Reference]
    let targetDuration: TimeInterval
    let bandwidth: Int
    let codec: String
    let mediaTimeOffset: TimeInterval
    let baseMediaDecodeTimeOffsetTicks: UInt64
    let dynamicRange: BiliVideoDynamicRange
    let dimensions: CGSize?

    nonisolated var hlsAdvertisedSupplementalCodecAttribute: String {
        guard dynamicRange != .dolbyVision else { return "" }
        return hlsSupplementalCodecAttribute
    }

    nonisolated var hlsSupplementalCodecAttribute: String {
        guard dynamicRange == .dolbyVision,
              !codec.localizedCaseInsensitiveContains("dvh"),
              !codec.localizedCaseInsensitiveContains("dvhe")
        else { return "" }

        return ",SUPPLEMENTAL-CODECS=\"dvh1.08.06/db1p\""
    }

    nonisolated var hlsVideoRangeAttribute: String {
        guard dynamicRange != .dolbyVision,
              let videoRange = dynamicRange.hlsVideoRangeAttribute
        else { return "" }
        return ",VIDEO-RANGE=\(videoRange)"
    }

    nonisolated var hlsResolutionAttribute: String {
        guard mediaType.isVideo,
              let dimensions,
              dimensions.width > 0,
              dimensions.height > 0
        else { return "" }
        return ",RESOLUTION=\(Int(dimensions.width))x\(Int(dimensions.height))"
    }

    nonisolated func playlist(baseURL: URL, routePrefix: String) -> String {
        let initURL = mediaURL(baseURL: baseURL, routePrefix: routePrefix, component: "init.mp4")
        let playlistSegments = references.enumerated().map { index, reference in
            let segmentURL = mediaURL(baseURL: baseURL, routePrefix: routePrefix, component: "segment-\(index).m4s")
            return """
            #EXTINF:\(LocalHLSBridge.formatDuration(reference.duration)),
            \(segmentURL.absoluteString)
            """
        }

        return """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-PLAYLIST-TYPE:VOD
        #EXT-X-TARGETDURATION:\(Int(ceil(targetDuration)))
        #EXT-X-MAP:URI="\(initURL.absoluteString)"
        \(playlistSegments.joined(separator: "\n"))
        #EXT-X-ENDLIST
        """
    }

    nonisolated func registerRoutes(routePrefix: String, into routes: inout [String: HLSProxyRoute]) {
        let contentType = switch mediaType {
        case .audio:
            "audio/mp4"
        case .video:
            "video/mp4"
        }
        if let initializationData {
            routes["/media/\(routePrefix)/init.mp4"] = .data(initializationData, contentType: contentType)
        } else {
            routes["/media/\(routePrefix)/init.mp4"] = .remoteByteRange(
                url: sourceURL,
                fallbackURLs: fallbackSourceURLs,
                range: initialization,
                contentType: contentType,
                transform: nil
            )
        }

        let segmentTransform = baseMediaDecodeTimeOffsetTicks > 0
            ? HLSMediaSegmentTransform(baseMediaDecodeTimeOffset: baseMediaDecodeTimeOffsetTicks)
            : nil
        for (index, reference) in references.enumerated() {
            routes["/media/\(routePrefix)/segment-\(index).m4s"] = .remoteByteRange(
                url: sourceURL,
                fallbackURLs: fallbackSourceURLs,
                range: reference.range,
                contentType: contentType,
                transform: segmentTransform
            )
        }
    }

    nonisolated func seekMap(includeExtraSegment: Bool) -> HLSBridgeSeekMap {
        HLSBridgeSeekMap(
            sourceURLs: ([sourceURL] + fallbackSourceURLs).removingDuplicates(),
            initialization: initialization,
            segments: references.map {
                HLSBridgeSeekSegment(
                    startTime: max($0.startTime - mediaTimeOffset, 0),
                    duration: $0.duration,
                    range: $0.range
                )
            },
            includeExtraSegment: includeExtraSegment
        )
    }

    nonisolated private func mediaURL(baseURL: URL, routePrefix: String, component: String) -> URL {
        baseURL
            .appendingPathComponent("media")
            .appendingPathComponent(routePrefix)
            .appendingPathComponent(component)
    }
}

private struct HLSBridgeRoutePlan: Sendable {
    let videoRenditions: [HLSRendition]
    let audioRendition: HLSRendition
    let masterPlaylistVersion: Int
}

private struct HLSBridgeSeekPlanner: Sendable {
    let video: HLSBridgeSeekMap
    let audio: HLSBridgeSeekMap
    let headers: [String: String]

    nonisolated func alignedSeekTime(near playbackTime: TimeInterval) -> TimeInterval? {
        video.alignedSeekTime(near: playbackTime)
    }

    nonisolated func warm(around playbackTime: TimeInterval, metricsID: String?) async {
        let start = CACurrentMediaTime()
        let videoRanges = video.warmRanges(around: playbackTime)
        let audioRanges = audio.warmRanges(around: playbackTime)
        guard !videoRanges.isEmpty || !audioRanges.isEmpty else { return }

        await withTaskGroup(of: Bool.self) { group in
            if !videoRanges.isEmpty {
                group.addTask(priority: .utility) {
                    await Self.warm(ranges: videoRanges, map: video, headers: headers)
                }
            }
            if !audioRanges.isEmpty {
                group.addTask(priority: .utility) {
                    await Self.warm(ranges: audioRanges, map: audio, headers: headers)
                }
            }
            var didWarm = false
            for await result in group where result {
                didWarm = true
            }
            guard didWarm else { return }
            let elapsed = PlayerMetricsLog.elapsedMilliseconds(since: start)
            await MainActor.run {
                PlayerMetricsLog.record(
                    .mediaCache,
                    metricsID: metricsID ?? "hls-seek-warm",
                    message: "seekWarm target=\(String(format: "%.2fs", playbackTime)) elapsed=\(String(format: "%.0fms", elapsed))"
                )
            }
        }
    }

    private nonisolated static func warm(
        ranges: [HTTPByteRange],
        map: HLSBridgeSeekMap,
        headers: [String: String]
    ) async -> Bool {
        guard !map.sourceURLs.isEmpty else { return false }
        var didWarm = false
        for range in ranges {
            do {
                _ = try await LocalHLSBridge.fetchByteRange(
                    range,
                    from: map.sourceURLs,
                    headers: headers,
                    strategy: .fastFallback
                )
                didWarm = true
            } catch {}
        }
        return didWarm
    }
}

private final class LocalLiveHLSProxy: @unchecked Sendable {
    let playlistURL: URL

    private let sourcePlaylistURL: URL
    private let headers: [String: String]
    private let metricsID: String?
    private let listener: NWListener
    private let queue: DispatchQueue
    nonisolated(unsafe) private var segmentRoutes: [String: URL] = [:]
    nonisolated(unsafe) private var activeConnections: [ObjectIdentifier: NWConnection] = [:]
    nonisolated(unsafe) private var isStarted = false
    nonisolated(unsafe) private var isClosed = false

    private init(port: UInt16, sourcePlaylistURL: URL, headers: [String: String], metricsID: String?) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port),
              let baseURL = URL(string: "http://127.0.0.1:\(port)")
        else {
            throw PlayerEngineError.unsupportedMedia
        }
        self.playlistURL = baseURL.appendingPathComponent("live.m3u8")
        self.sourcePlaylistURL = sourcePlaylistURL
        self.headers = headers
        self.metricsID = metricsID
        self.listener = try NWListener(using: .tcp, on: endpointPort)
        self.queue = DispatchQueue(label: "cc.bili.live-hls.\(port)", qos: .userInitiated)
    }

    deinit {
        listener.cancel()
        activeConnections.values.forEach { $0.cancel() }
    }

    nonisolated func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isClosed = true
            self.isStarted = false
            self.segmentRoutes.removeAll(keepingCapacity: false)
            self.listener.cancel()
            self.activeConnections.values.forEach { $0.cancel() }
            self.activeConnections.removeAll(keepingCapacity: false)
        }
    }

    static func make(playlistURL: URL, headers: [String: String], metricsID: String?) async throws -> LocalLiveHLSProxy {
        var lastError: Error?
        for _ in 0..<24 {
            let port = UInt16.random(in: 49152...61000)
            do {
                let proxy = try LocalLiveHLSProxy(
                    port: port,
                    sourcePlaylistURL: playlistURL,
                    headers: headers,
                    metricsID: metricsID
                )
                try await proxy.start()
                PlayerMetricsLog.logger.info(
                    "directLiveHLSProxyReady url=\(proxy.playlistURL.absoluteString, privacy: .public)"
                )
                return proxy
            } catch {
                lastError = error
            }
        }
        throw lastError ?? PlayerEngineError.unsupportedMedia
    }

    private func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: PlayerEngineError.unsupportedMedia)
                    return
                }
                guard !self.isStarted else {
                    continuation.resume()
                    return
                }
                self.isStarted = true

                var didResume = false
                self.listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        guard !didResume else { return }
                        didResume = true
                        continuation.resume()
                    case let .failed(error):
                        guard !didResume else { return }
                        didResume = true
                        continuation.resume(throwing: error)
                    case .cancelled:
                        break
                    default:
                        break
                    }
                }
                self.listener.newConnectionHandler = { [weak self] connection in
                    self?.handleConnection(connection)
                }
                self.listener.start(queue: self.queue)
            }
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        guard !isClosed else {
            connection.cancel()
            return
        }
        let identifier = ObjectIdentifier(connection)
        activeConnections[identifier] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                self?.queue.async { [weak self] in
                    self?.activeConnections[identifier] = nil
                }
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveRequest(from: connection, accumulatedData: Data())
    }

    private func receiveRequest(from connection: NWConnection, accumulatedData: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if error != nil {
                connection.cancel()
                return
            }

            var requestData = accumulatedData
            if let data {
                requestData.append(data)
            }

            if requestData.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.respond(to: connection, requestData: requestData)
            } else if isComplete || requestData.count > 64 * 1024 {
                self.sendError(400, reason: "Bad Request", to: connection)
            } else {
                self.receiveRequest(from: connection, accumulatedData: requestData)
            }
        }
    }

    private func respond(to connection: NWConnection, requestData: Data) {
        let connectionID = ObjectIdentifier(connection)
        guard let request = HLSProxyRequest(data: requestData) else {
            sendError(400, reason: "Bad Request", to: connection)
            return
        }

        guard request.method == "GET" || request.method == "HEAD" else {
            sendError(405, reason: "Method Not Allowed", to: connection)
            return
        }

        if request.path == "/live.m3u8" {
            Task.detached(priority: .userInitiated) { [headers, sourcePlaylistURL, playlistURL, metricsID] in
                do {
                    let start = CACurrentMediaTime()
                    let (playlistData, routes) = try await Self.fetchRewrittenPlaylist(
                        sourcePlaylistURL,
                        headers: headers,
                        localPlaylistURL: playlistURL
                    )
                    self.queue.async {
                        guard self.isConnectionActive(connectionID) else { return }
                        self.segmentRoutes.merge(routes) { _, new in new }
                        self.sendData(
                            playlistData,
                            contentType: "application/vnd.apple.mpegurl",
                            request: request,
                            to: connection
                        )
                    }
                    PlayerMetricsLog.logger.info(
                        "directLiveHLSPlaylistProxy segments=\(routes.count, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: start), format: .fixed(precision: 1), privacy: .public)"
                    )
                    if let metricsID {
                        await PlayerMetricsLog.record(
                            .network,
                            metricsID: metricsID,
                            message: "live playlist \(routes.count) segments"
                        )
                    }
                } catch {
                    PlayerMetricsLog.logger.error(
                        "directLiveHLSPlaylistProxyFailed error=\(error.localizedDescription, privacy: .public)"
                    )
                    self.queue.async {
                        guard self.isConnectionActive(connectionID) else { return }
                        self.sendError(502, reason: "Bad Gateway", to: connection)
                    }
                }
            }
            return
        }

        guard let remoteURL = segmentRoutes[request.path] else {
            PlayerMetricsLog.logger.error(
                "directLiveHLSSegmentMiss path=\(request.path, privacy: .public)"
            )
            sendError(404, reason: "Not Found", to: connection)
            return
        }

        Task.detached(priority: .userInitiated) { [headers, metricsID] in
            do {
                let start = CACurrentMediaTime()
                let (data, contentType) = try await Self.fetchSegment(remoteURL, headers: headers)
                let responseData: Data
                let servedRange: HTTPByteRange?
                if let range = request.range?.clamped(toLength: Int64(data.count)),
                   let lowerBound = Int(exactly: range.start),
                   let upperBoundInclusive = Int(exactly: range.endInclusive),
                   lowerBound >= 0,
                   upperBoundInclusive < data.count {
                    responseData = data.subdata(in: lowerBound..<(upperBoundInclusive + 1))
                    servedRange = range
                } else {
                    responseData = data
                    servedRange = nil
                }
                self.queue.async {
                    guard self.isConnectionActive(connectionID) else { return }
                    self.sendData(
                        responseData,
                        contentType: contentType,
                        request: request,
                        totalLength: Int64(data.count),
                        servedRange: servedRange,
                        to: connection
                    )
                }
                PlayerMetricsLog.logger.info(
                    "directLiveHLSSegmentProxy bytes=\(data.count, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: start), format: .fixed(precision: 1), privacy: .public)"
                )
                if let metricsID {
                    await PlayerMetricsLog.record(
                        .network,
                        metricsID: metricsID,
                        message: "live segment \(data.count / 1024)KB"
                    )
                }
            } catch {
                PlayerMetricsLog.logger.error(
                    "directLiveHLSSegmentProxyFailed url=\(remoteURL.absoluteString, privacy: .private) error=\(error.localizedDescription, privacy: .public)"
                )
                self.queue.async {
                    guard self.isConnectionActive(connectionID) else { return }
                    self.sendError(502, reason: "Bad Gateway", to: connection)
                }
            }
        }
    }

    private static func fetchRewrittenPlaylist(
        _ url: URL,
        headers: [String: String],
        localPlaylistURL: URL
    ) async throws -> (Data, [String: URL]) {
        let data = try await fetchRemoteData(url, headers: headers, timeoutInterval: 8)
        guard let playlist = String(data: data, encoding: .utf8) else {
            throw PlayerEngineError.unsupportedMedia
        }

        var routes: [String: URL] = [:]
        var hasIndependentSegments = false
        var hasPlaylistType = false
        var hasEndList = false
        let lines = playlist.components(separatedBy: .newlines)
        var rewrittenLines = lines.compactMap { line -> String? in
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.hasPrefix("#EXT-X-INDEPENDENT-SEGMENTS") {
                hasIndependentSegments = true
            } else if trimmedLine.hasPrefix("#EXT-X-PLAYLIST-TYPE") {
                hasPlaylistType = true
            } else if trimmedLine.hasPrefix("#EXT-X-ENDLIST") {
                hasEndList = true
            }
            guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("#") else {
                return line
            }
            guard let remoteURL = URL(string: trimmedLine, relativeTo: url)?.absoluteURL else {
                return line
            }
            let routePath = liveSegmentPath(for: remoteURL)
            routes[routePath] = remoteURL
            return URL(string: routePath, relativeTo: localPlaylistURL)?.absoluteString ?? line
        }

        if !hasIndependentSegments,
           let insertionIndex = rewrittenLines.firstIndex(where: { !$0.hasPrefix("#EXTM3U") && !$0.hasPrefix("#EXT-X-VERSION") }) {
            rewrittenLines.insert("#EXT-X-INDEPENDENT-SEGMENTS", at: insertionIndex)
        }
        if !hasPlaylistType, !hasEndList,
           let insertionIndex = rewrittenLines.firstIndex(where: { $0.hasPrefix("#EXT-X-MEDIA-SEQUENCE") }) {
            rewrittenLines.insert("#EXT-X-PLAYLIST-TYPE:EVENT", at: insertionIndex)
        }
        if rewrittenLines.last?.isEmpty != true {
            rewrittenLines.append("")
        }
        return (Data(rewrittenLines.joined(separator: "\n").utf8), routes)
    }

    private static func fetchSegment(_ url: URL, headers: [String: String]) async throws -> (Data, String) {
        let data = try await fetchRemoteData(url, headers: headers, timeoutInterval: 12)
        let contentType = url.pathExtension.localizedCaseInsensitiveCompare("m4s") == .orderedSame
            ? "video/iso.segment"
            : "video/mp2t"
        return (data, contentType)
    }

    private static func fetchRemoteData(_ url: URL, headers: [String: String], timeoutInterval: TimeInterval) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = timeoutInterval
        request.networkServiceType = .video
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await BiliNetworkRetry.data(
            sessionProvider: { BiliPlaybackNetworkSessionPool.shared.playbackDataSession() },
            request: request,
            policy: .playbackShortResource
        )
        if let response = response as? HTTPURLResponse,
           !(200...299).contains(response.statusCode) {
            throw PlayerEngineError.unsupportedMedia
        }
        return data
    }

    private static func liveSegmentPath(for url: URL) -> String {
        let filename = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !filename.isEmpty,
           let encodedFilename = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
            return "/live-segment/\(encodedFilename)"
        }
        return "/live-segment/\(abs(url.absoluteString.hashValue)).ts"
    }

    private func sendData(
        _ data: Data,
        contentType: String,
        request: HLSProxyRequest,
        totalLength: Int64? = nil,
        servedRange: HTTPByteRange? = nil,
        to connection: NWConnection,
        closesConnection: Bool = true
    ) {
        let body = request.method == "HEAD" ? Data() : data
        var headers = [
            "Content-Type": contentType,
            "Content-Length": "\(data.count)",
            "Accept-Ranges": "bytes",
            "Cache-Control": request.path.hasSuffix(".m3u8") ? "no-cache" : "public, max-age=15",
            "Connection": closesConnection ? "close" : "keep-alive"
        ]
        let statusLine: String
        if let servedRange, let totalLength {
            statusLine = "HTTP/1.1 206 Partial Content"
            headers["Content-Range"] = "bytes \(servedRange.start)-\(servedRange.endInclusive)/\(totalLength)"
        } else {
            statusLine = "HTTP/1.1 200 OK"
        }
        sendResponse(statusLine: statusLine, headers: headers, body: body, to: connection, closesConnection: closesConnection)
    }

    private func sendError(_ statusCode: Int, reason: String, to connection: NWConnection) {
        let body = Data(reason.utf8)
        sendResponse(
            statusLine: "HTTP/1.1 \(statusCode) \(reason)",
            headers: [
                "Content-Type": "text/plain; charset=utf-8",
                "Content-Length": "\(body.count)",
                "Connection": "close"
            ],
            body: body,
            to: connection
        )
    }

    private func sendResponse(
        statusLine: String,
        headers: [String: String],
        body: Data,
        to connection: NWConnection,
        closesConnection: Bool = true
    ) {
        let headerText = ([statusLine] + headers.map { "\($0.key): \($0.value)" })
            .joined(separator: "\r\n") + "\r\n\r\n"
        var response = Data(headerText.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            guard !closesConnection, let self else {
                connection.cancel()
                return
            }
            self.receiveRequest(from: connection, accumulatedData: Data())
        })
    }

    private func isConnectionActive(_ identifier: ObjectIdentifier) -> Bool {
        !isClosed && activeConnections[identifier] != nil
    }
}

private actor HLSRenditionCache {
    static let shared = HLSRenditionCache()

    enum State: String, Sendable {
        case hit
        case disk
        case pending
        case miss
    }

    private let ttl: TimeInterval = 8 * 60
    private let maxCount = 48
    private let maxDiskCount = 96
    private let fileManager = FileManager.default
    private let rootURL: URL
    private var cache: [String: Entry] = [:]
    private let pendingJoinTimeoutNanoseconds: UInt64 = 220_000_000
    private var pendingBuilds: [String: PendingBuild] = [:]
    private var storeCountSinceDiskTrim = 0
    private var diskTrimTask: Task<Void, Never>?

    init() {
        rootURL = fileManager
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HLSRenditionCache", isDirectory: true)
    }

    func cachedOrBuild(
        for key: String,
        builder: @escaping @Sendable () async throws -> HLSRendition
    ) async throws -> (rendition: HLSRendition, state: State) {
        trimExpired()
        if let entry = cache[key] {
            cache[key] = Entry(rendition: entry.rendition, date: Date())
            return (entry.rendition, .hit)
        }
        if let entry = loadPersistedEntry(for: key) {
            cache[key] = entry
            trimIfNeeded()
            return (entry.rendition, .disk)
        }
        if let pendingBuild = pendingBuilds[key] {
            do {
                let rendition = try await HLSCachePendingWaiter.value(
                    of: pendingBuild.task,
                    timeout: pendingJoinTimeoutNanoseconds
                )
                return (rendition, .pending)
            } catch HLSCachePendingWaiter.Timeout.timedOut {
                let rendition = try await pendingBuild.task.value
                return (rendition, .pending)
            } catch {
                if pendingBuilds[key]?.id == pendingBuild.id {
                    pendingBuilds[key] = nil
                }
                throw error
            }
        }

        let pendingBuild = PendingBuild(task: Task.detached(priority: .userInitiated) {
            try await builder()
        })
        pendingBuilds[key] = pendingBuild
        do {
            let rendition = try await pendingBuild.task.value
            pendingBuilds[key] = nil
            cache[key] = Entry(rendition: rendition, date: Date())
            storePersistedEntry(Entry(rendition: rendition, date: Date()), for: key)
            trimIfNeeded()
            return (rendition, .miss)
        } catch {
            pendingBuilds[key] = nil
            throw error
        }
    }

    func removeAll() {
        pendingBuilds.values.forEach { $0.task.cancel() }
        pendingBuilds.removeAll()
        cache.removeAll()
        try? fileManager.removeItem(at: rootURL)
    }

    private func trimExpired() {
        let expiry = Date().addingTimeInterval(-ttl)
        cache = cache.filter { $0.value.date >= expiry }
    }

    private func trimIfNeeded() {
        trimExpired()
        guard cache.count > maxCount else { return }
        let keptKeys = Set(
            cache
                .sorted { $0.value.date > $1.value.date }
                .prefix(maxCount)
                .map(\.key)
        )
        cache = cache.filter { keptKeys.contains($0.key) }
    }

    private struct Entry {
        let rendition: HLSRendition
        let date: Date
    }

    private func loadPersistedEntry(for key: String) -> Entry? {
        let fileURL = cacheFileURL(for: key)
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let persisted = try? JSONDecoder().decode(PersistedEntry.self, from: data)
        else { return nil }
        guard persisted.date >= Date().addingTimeInterval(-ttl),
              let rendition = persisted.rendition.makeRendition()
        else {
            try? fileManager.removeItem(at: fileURL)
            return nil
        }
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
        return Entry(rendition: rendition, date: persisted.date)
    }

    private func storePersistedEntry(_ entry: Entry, for key: String) {
        guard let persisted = PersistedEntry(entry: entry) else { return }
        let fileURL = cacheFileURL(for: key)
        Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let data = try JSONEncoder().encode(persisted)
                try data.write(to: fileURL, options: .atomic)
            } catch {}
        }
        scheduleDiskTrimIfNeeded()
    }

    private func scheduleDiskTrimIfNeeded() {
        storeCountSinceDiskTrim += 1
        guard diskTrimTask == nil, storeCountSinceDiskTrim >= 16 else { return }
        let actor = self
        diskTrimTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await actor.trimDiskIfNeeded()
            await actor.completeDiskTrim()
        }
    }

    private func completeDiskTrim() {
        diskTrimTask = nil
        storeCountSinceDiskTrim = 0
    }

    private func trimDiskIfNeeded() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return }
        let expiry = Date().addingTimeInterval(-ttl)
        let entries = files.compactMap { url -> (url: URL, date: Date, size: Int64)? in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else { return nil }
            return (url, values.contentModificationDate ?? .distantPast, Int64(values.fileSize ?? 0))
        }
        for entry in entries where entry.date < expiry {
            try? fileManager.removeItem(at: entry.url)
        }
        let retained = entries.filter { $0.date >= expiry }
        guard retained.count > maxDiskCount else { return }
        for entry in retained.sorted(by: { $0.date < $1.date }).prefix(retained.count - maxDiskCount) {
            try? fileManager.removeItem(at: entry.url)
        }
    }

    private func cacheFileURL(for key: String) -> URL {
        rootURL.appendingPathComponent("\(Self.stableCacheHash(key)).json")
    }

    private nonisolated static func stableCacheHash(_ string: String) -> String {
        let basis: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211
        let value = string.utf8.reduce(basis) { partial, byte in
            (partial ^ UInt64(byte)) &* prime
        }
        return String(value, radix: 16)
    }

    private struct PersistedEntry: Codable {
        let date: Date
        let rendition: PersistedRendition

        init?(entry: Entry) {
            guard let rendition = PersistedRendition(rendition: entry.rendition) else { return nil }
            self.date = entry.date
            self.rendition = rendition
        }
    }

    private struct PersistedRendition: Codable {
        let sourceURL: String
        let fallbackSourceURLs: [String]
        let mediaType: String
        let quality: Int?
        let initialization: PersistedRange
        let references: [PersistedReference]
        let targetDuration: TimeInterval
        let bandwidth: Int
        let codec: String
        let mediaTimeOffset: TimeInterval
        let baseMediaDecodeTimeOffsetTicks: UInt64
        let dynamicRange: String
        let dimensionsWidth: Double?
        let dimensionsHeight: Double?

        init?(rendition: HLSRendition) {
            self.sourceURL = rendition.sourceURL.absoluteString
            self.fallbackSourceURLs = rendition.fallbackSourceURLs.map(\.absoluteString)
            self.mediaType = rendition.mediaType.logLabel
            self.quality = rendition.quality
            self.initialization = PersistedRange(range: rendition.initialization)
            self.references = rendition.references.map(PersistedReference.init(reference:))
            self.targetDuration = rendition.targetDuration
            self.bandwidth = rendition.bandwidth
            self.codec = rendition.codec
            self.mediaTimeOffset = rendition.mediaTimeOffset
            self.baseMediaDecodeTimeOffsetTicks = rendition.baseMediaDecodeTimeOffsetTicks
            self.dynamicRange = rendition.dynamicRange.rawValue
            self.dimensionsWidth = rendition.dimensions.map { Double($0.width) }
            self.dimensionsHeight = rendition.dimensions.map { Double($0.height) }
        }

        func makeRendition() -> HLSRendition? {
            guard let sourceURL = URL(string: sourceURL) else { return nil }
            let resolvedMediaType: HLSBridgeTrack.MediaType = mediaType == "audio" ? .audio : .video
            let dimensions: CGSize?
            if let dimensionsWidth, let dimensionsHeight, dimensionsWidth > 0, dimensionsHeight > 0 {
                dimensions = CGSize(width: dimensionsWidth, height: dimensionsHeight)
            } else {
                dimensions = nil
            }
            return HLSRendition(
                sourceURL: sourceURL,
                fallbackSourceURLs: fallbackSourceURLs.compactMap(URL.init(string:)),
                mediaType: resolvedMediaType,
                quality: quality,
                initialization: initialization.makeRange(),
                initializationData: nil,
                references: references.map(\.makeReference),
                targetDuration: targetDuration,
                bandwidth: bandwidth,
                codec: codec,
                mediaTimeOffset: mediaTimeOffset,
                baseMediaDecodeTimeOffsetTicks: baseMediaDecodeTimeOffsetTicks,
                dynamicRange: BiliVideoDynamicRange(rawValue: dynamicRange) ?? .sdr,
                dimensions: dimensions
            )
        }
    }

    private struct PersistedRange: Codable {
        let start: Int64
        let endInclusive: Int64

        init(range: HTTPByteRange) {
            self.start = range.start
            self.endInclusive = range.endInclusive
        }

        func makeRange() -> HTTPByteRange {
            HTTPByteRange(start: start, endInclusive: endInclusive)
        }
    }

    private struct PersistedReference: Codable {
        let range: PersistedRange
        let duration: TimeInterval
        let startTime: TimeInterval
        let startTimeTicks: UInt64
        let timescale: UInt32

        init(reference: SIDXParser.Reference) {
            self.range = PersistedRange(range: reference.range)
            self.duration = reference.duration
            self.startTime = reference.startTime
            self.startTimeTicks = reference.startTimeTicks
            self.timescale = reference.timescale
        }

        var makeReference: SIDXParser.Reference {
            SIDXParser.Reference(
                range: range.makeRange(),
                duration: duration,
                startTime: startTime,
                startTimeTicks: startTimeTicks,
                timescale: timescale
            )
        }
    }

    private struct PendingBuild {
        let id = UUID()
        let task: Task<HLSRendition, Error>
    }
}

nonisolated private enum HLSCachePendingWaiter {
    enum Timeout: Error {
        case timedOut
    }

    static func value<T: Sendable>(
        of task: Task<T, Error>,
        timeout: UInt64
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await task.value
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeout)
                throw Timeout.timedOut
            }
            guard let value = try await group.next() else {
                throw Timeout.timedOut
            }
            group.cancelAll()
            return value
        }
    }
}

private actor HLSBridgeRoutePlanCache {
    static let shared = HLSBridgeRoutePlanCache()

    enum State: String, Sendable {
        case hit
        case pending
        case miss
        case skippedPending
    }

    private let ttl: TimeInterval = 3 * 60
    private let maxCount = 12
    private let pendingJoinTimeoutNanoseconds: UInt64 = 220_000_000
    private var cache: [String: Entry] = [:]
    private var pendingBuilds: [String: PendingBuild] = [:]

    func cachedOrBuild(
        for key: String,
        builder: @escaping @Sendable () async throws -> HLSBridgeRoutePlan
    ) async throws -> (plan: HLSBridgeRoutePlan, state: State) {
        trimExpired()
        if let entry = cache[key] {
            cache[key] = Entry(plan: entry.plan, date: Date())
            return (entry.plan, .hit)
        }
        if let pendingBuild = pendingBuilds[key] {
            do {
                let plan = try await HLSCachePendingWaiter.value(
                    of: pendingBuild.task,
                    timeout: pendingJoinTimeoutNanoseconds
                )
                return (plan, .pending)
            } catch HLSCachePendingWaiter.Timeout.timedOut {
                let plan = try await pendingBuild.task.value
                return (plan, .pending)
            } catch {
                if pendingBuilds[key]?.id == pendingBuild.id {
                    pendingBuilds[key] = nil
                }
                throw error
            }
        }

        let pendingBuild = PendingBuild(task: Task.detached(priority: .userInitiated) {
            try await builder()
        })
        pendingBuilds[key] = pendingBuild
        do {
            let plan = try await pendingBuild.task.value
            pendingBuilds[key] = nil
            cache[key] = Entry(plan: plan, date: Date())
            trimIfNeeded()
            return (plan, .miss)
        } catch {
            pendingBuilds[key] = nil
            throw error
        }
    }

    func prebuild(
        for key: String,
        builder: @escaping @Sendable () async throws -> HLSBridgeRoutePlan
    ) async throws -> State {
        trimExpired()
        if let entry = cache[key] {
            cache[key] = Entry(plan: entry.plan, date: Date())
            return .hit
        }
        guard pendingBuilds[key] == nil else {
            return .skippedPending
        }

        let pendingBuild = PendingBuild(task: Task.detached(priority: .utility) {
            try await builder()
        })
        pendingBuilds[key] = pendingBuild
        do {
            let plan = try await pendingBuild.task.value
            if pendingBuilds[key]?.id == pendingBuild.id {
                pendingBuilds[key] = nil
            }
            cache[key] = Entry(plan: plan, date: Date())
            trimIfNeeded()
            return .miss
        } catch {
            if pendingBuilds[key]?.id == pendingBuild.id {
                pendingBuilds[key] = nil
            }
            throw error
        }
    }

    func removeAll() {
        pendingBuilds.values.forEach { $0.task.cancel() }
        pendingBuilds.removeAll()
        cache.removeAll()
    }

    private func trimExpired() {
        let expiry = Date().addingTimeInterval(-ttl)
        cache = cache.filter { $0.value.date >= expiry }
    }

    private func trimIfNeeded() {
        trimExpired()
        guard cache.count > maxCount else { return }
        let keptKeys = Set(
            cache
                .sorted { $0.value.date > $1.value.date }
                .prefix(maxCount)
                .map(\.key)
        )
        cache = cache.filter { keptKeys.contains($0.key) }
    }

    private struct Entry {
        let plan: HLSBridgeRoutePlan
        let date: Date
    }

    private struct PendingBuild {
        let id = UUID()
        let task: Task<HLSBridgeRoutePlan, Error>
    }
}

private actor LocalHLSBridgeInstanceCache {
    static let shared = LocalHLSBridgeInstanceCache()

    enum State: String, Sendable {
        case hit
        case pending
        case miss
    }

    private let logger = Logger(subsystem: "cc.bili", category: "PlayerMetrics")
    private let ttl: TimeInterval = 90
    private let maxCount = 8
    private var cache: [String: Entry] = [:]
    private let pendingJoinTimeoutNanoseconds: UInt64 = 160_000_000
    private var pendingBuilds: [String: PendingBuild] = [:]

    func cachedOrBuild(
        for key: String,
        builder: @escaping @Sendable () async throws -> LocalHLSBridge
    ) async throws -> (bridge: LocalHLSBridge, state: State) {
        trimExpired()
        if let entry = cache[key] {
            cache[key] = Entry(bridge: entry.bridge, date: Date())
            logger.info("hlsBridgeCache hit")
            return (entry.bridge, .hit)
        }
        if let pendingBuild = pendingBuilds[key] {
            logger.info("hlsBridgeCache pending")
            do {
                let bridge = try await HLSCachePendingWaiter.value(
                    of: pendingBuild.task,
                    timeout: pendingJoinTimeoutNanoseconds
                )
                return (bridge, .pending)
            } catch HLSCachePendingWaiter.Timeout.timedOut {
                logger.info("hlsBridgeCache pending continue")
                let bridge = try await pendingBuild.task.value
                return (bridge, .pending)
            } catch {
                if pendingBuilds[key]?.id == pendingBuild.id {
                    pendingBuilds[key] = nil
                }
                throw error
            }
        }

        logger.info("hlsBridgeCache miss")
        let pendingBuild = PendingBuild(task: Task.detached(priority: .userInitiated) {
            try await builder()
        })
        pendingBuilds[key] = pendingBuild
        do {
            let bridge = try await pendingBuild.task.value
            pendingBuilds[key] = nil
            cache[key] = Entry(bridge: bridge, date: Date())
            trimIfNeeded()
            return (bridge, .miss)
        } catch {
            pendingBuilds[key] = nil
            throw error
        }
    }

    func removeAll() {
        pendingBuilds.values.forEach { $0.task.cancel() }
        pendingBuilds.removeAll()
        cache.removeAll()
    }

    private func trimExpired() {
        let expiry = Date().addingTimeInterval(-ttl)
        cache = cache.filter { $0.value.date >= expiry }
    }

    private func trimIfNeeded() {
        trimExpired()
        guard cache.count > maxCount else { return }
        let keptKeys = Set(
            cache
                .sorted { $0.value.date > $1.value.date }
                .prefix(maxCount)
                .map(\.key)
        )
        cache = cache.filter { keptKeys.contains($0.key) }
    }

    private struct Entry {
        let bridge: LocalHLSBridge
        let date: Date
    }

    private struct PendingBuild {
        let id = UUID()
        let task: Task<LocalHLSBridge, Error>
    }
}

private actor HLSSourcePreferenceCache {
    static let shared = HLSSourcePreferenceCache()

    private let ttl: TimeInterval = 24 * 60 * 60
    private let sessionAvoidanceTTL: TimeInterval = 10 * 60
    private let maxCount = 256
    private let maxHostScoreCount = 192
    private let fileManager = FileManager.default
    private let storeURL: URL
    private let hostScoreStoreURL: URL
    private var entries: [String: Entry] = [:]
    private var hostScores: [String: HostScore] = [:]
    private var sessionAvoidance: [String: SessionAvoidance] = [:]
    private var hasLoadedStore = false
    private var persistTask: Task<Void, Never>?
    private var persistDirty = false

    init() {
        storeURL = fileManager
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HLSSourcePreferenceCache.json")
        hostScoreStoreURL = fileManager
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HLSSourceScores.json")
    }

    func preferredURLs(for urls: [URL]) -> [URL] {
        loadStoreIfNeeded()
        trimExpired()
        guard urls.count > 1 else { return urls }
        let scoredURLs = urls.enumerated().map { index, url -> (index: Int, url: URL, score: Double?) in
            guard let host = url.host, let hostScore = hostScores[host] else {
                return (index, url, nil)
            }
            return (index, url, hostScore.rankScore)
        }
        let urlsWithScores = scoredURLs.filter { $0.score != nil }
        if !urlsWithScores.isEmpty {
            let ordered = scoredURLs
                .sorted { lhs, rhs in
                    let leftScore = lhs.score ?? HostScore.unmeasuredRankScore
                    let rightScore = rhs.score ?? HostScore.unmeasuredRankScore
                    if abs(leftScore - rightScore) > 0.01 {
                        return leftScore < rightScore
                    }
                    if (lhs.score == nil) != (rhs.score == nil) {
                        return lhs.index < rhs.index
                    }
                    return lhs.index < rhs.index
                }
                .map(\.url)
            return demoteSessionAvoidedHosts(ordered)
        }
        guard let preferredURL = preferredURL(for: urls),
              let preferredIndex = urls.firstIndex(of: preferredURL),
              preferredIndex > 0
        else {
            return demoteSessionAvoidedHosts(urls)
        }
        var reordered = urls
        let preferred = reordered.remove(at: preferredIndex)
        reordered.insert(preferred, at: 0)
        return demoteSessionAvoidedHosts(reordered)
    }

    func recordPreferredURL(_ url: URL, for urls: [URL]) {
        loadStoreIfNeeded()
        guard urls.contains(url) else { return }
        let now = Date()
        entries[exactCacheKey(for: urls)] = Entry(preferredURLString: url.absoluteString, date: now)
        if let hostKey = hostCacheKey(for: urls) {
            entries[hostKey] = Entry(preferredURLString: url.absoluteString, date: now)
        }
        trimExpired()
        trimIfNeeded()
        persistDirty = true
        schedulePersist()
    }

    func recordResult(
        url: URL,
        for urls: [URL],
        elapsedMilliseconds: Double,
        bytes: Int64,
        succeeded: Bool,
        failureReason: String? = nil,
        failurePenaltyMultiplier: Int = 1,
        metricsID: String? = nil,
        title: String? = nil
    ) {
        loadStoreIfNeeded()
        guard urls.contains(url), let host = url.host else { return }
        let now = Date()
        var score = hostScores[host] ?? HostScore()
        score.record(
            elapsedMilliseconds: elapsedMilliseconds,
            bytes: bytes,
            succeeded: succeeded,
            date: now
        )
        PlaybackURLPreferenceStore.shared.record(
            url: url,
            elapsedMilliseconds: elapsedMilliseconds,
            bytes: bytes,
            succeeded: succeeded
        )
        hostScores[host] = score
        if succeeded {
            clearSessionAvoidance(for: host)
            entries[exactCacheKey(for: urls)] = Entry(preferredURLString: url.absoluteString, date: now)
            if let hostKey = hostCacheKey(for: urls) {
                entries[hostKey] = Entry(preferredURLString: url.absoluteString, date: now)
            }
        } else {
            markSessionAvoidedHost(
                host,
                reason: failureReason ?? "range-failed",
                penaltyMultiplier: max(failurePenaltyMultiplier, 1),
                metricsID: metricsID,
                title: title
            )
        }
        trimExpired()
        trimIfNeeded()
        trimHostScoresIfNeeded()
        persistDirty = true
        schedulePersist()
    }

    func recordFailure(
        url: URL,
        for urls: [URL],
        elapsedMilliseconds: Double,
        error: Error,
        metricsID: String? = nil,
        title: String? = nil
    ) {
        guard HLSBridgeRemoteFailure.shouldRecordSourceFailure(error) else { return }
        recordResult(
            url: url,
            for: urls,
            elapsedMilliseconds: elapsedMilliseconds,
            bytes: 0,
            succeeded: false,
            failureReason: HLSBridgeRemoteFailure.sourceAvoidanceReason(for: error),
            failurePenaltyMultiplier: HLSBridgeRemoteFailure.sourceAvoidancePenaltyMultiplier(for: error),
            metricsID: metricsID,
            title: title
        )
    }

    func recordSessionAvoidance(
        host: String?,
        reason: String,
        metricsID: String?,
        title: String? = nil
    ) {
        loadStoreIfNeeded()
        guard let host else { return }
        markSessionAvoidedHost(
            host,
            reason: reason,
            penaltyMultiplier: 2,
            metricsID: metricsID,
            title: title
        )
    }

    func diagnostics(for urls: [URL]) -> [HLSBridgeSourceDiagnosticsSnapshot] {
        loadStoreIfNeeded()
        trimExpired()
        let orderedURLs = preferredURLs(for: urls.removingDuplicates())
        let now = Date()
        var seenHosts = Set<String>()
        return orderedURLs.enumerated().compactMap { index, url -> HLSBridgeSourceDiagnosticsSnapshot? in
            guard let host = normalizedHost(url.host),
                  seenHosts.insert(host).inserted
            else { return nil }
            let score = hostScores[host] ?? url.host.flatMap { hostScores[$0] }
            let avoidance = sessionAvoidance[host]
            let isAvoided = avoidance.map { $0.expiresAt > now } ?? false
            return HLSBridgeSourceDiagnosticsSnapshot(
                host: host,
                order: index + 1,
                averageMilliseconds: score.map { Int($0.averageMilliseconds.rounded()) },
                averageKilobytesPerSecond: Int((score?.averageKilobytesPerSecond ?? 0).rounded()),
                successCount: score?.successCount ?? 0,
                failureCount: score?.failureCount ?? 0,
                isSessionAvoided: isAvoided,
                avoidanceReason: isAvoided ? avoidance?.reason : nil,
                avoidanceExpiresAt: isAvoided ? avoidance?.expiresAt : nil
            )
        }
    }

    private func preferredURL(for urls: [URL]) -> URL? {
        let keys = [exactCacheKey(for: urls), hostCacheKey(for: urls)]
            .compactMap { $0 }
        for key in keys {
            guard let entry = entries[key],
                  let url = URL(string: entry.preferredURLString)
            else { continue }
            if urls.contains(url) {
                return url
            }
            if let host = url.host,
               let matchingURL = urls.first(where: { $0.host == host }) {
                return matchingURL
            }
        }
        return nil
    }

    private func exactCacheKey(for urls: [URL]) -> String {
        "exact|" + urls
            .map(\.absoluteString)
            .joined(separator: "|")
    }

    private func hostCacheKey(for urls: [URL]) -> String? {
        let hosts = urls.compactMap(\.host)
        guard hosts.count > 1 else { return nil }
        return "host|" + hosts.joined(separator: "|")
    }

    private func demoteSessionAvoidedHosts(_ urls: [URL]) -> [URL] {
        trimSessionAvoidance()
        guard !sessionAvoidance.isEmpty else { return urls }
        var preferred: [URL] = []
        var avoided: [URL] = []
        for url in urls {
            if isSessionAvoided(url.host) {
                avoided.append(url)
            } else {
                preferred.append(url)
            }
        }
        guard !preferred.isEmpty else { return urls }
        return preferred + avoided
    }

    private func markSessionAvoidedHost(
        _ host: String,
        reason: String,
        penaltyMultiplier: Int,
        metricsID: String?,
        title: String?
    ) {
        guard let key = normalizedHost(host) else { return }
        trimSessionAvoidance()
        let existing = sessionAvoidance[key]
        let failureCount = min((existing?.failureCount ?? 0) + max(penaltyMultiplier, 1), 8)
        let penaltySeconds = min(sessionAvoidanceTTL, 90 + TimeInterval(failureCount) * 75)
        let expiresAt = Date().addingTimeInterval(penaltySeconds)
        sessionAvoidance[key] = SessionAvoidance(
            reason: reason,
            failureCount: failureCount,
            expiresAt: expiresAt
        )
        PlayerMetricsLog.logger.info(
            "hlsSourceSessionAvoid host=\(key, privacy: .public) reason=\(reason, privacy: .public) failures=\(failureCount, privacy: .public) ttl=\(Int(penaltySeconds), privacy: .public)s"
        )
        if let metricsID {
            Task { @MainActor in
                PlayerMetricsLog.record(
                    .network,
                    metricsID: metricsID,
                    title: title,
                    message: "sessionAvoid host=\(key) reason=\(reason) failures=\(failureCount) ttl=\(Int(penaltySeconds))s"
                )
            }
        }
    }

    private func clearSessionAvoidance(for host: String) {
        guard let key = normalizedHost(host) else { return }
        sessionAvoidance[key] = nil
    }

    private func isSessionAvoided(_ host: String?) -> Bool {
        guard let key = normalizedHost(host) else { return false }
        guard let avoidance = sessionAvoidance[key] else { return false }
        return avoidance.expiresAt > Date()
    }

    private func normalizedHost(_ host: String?) -> String? {
        let trimmed = host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func trimSessionAvoidance() {
        let now = Date()
        sessionAvoidance = sessionAvoidance.filter { $0.value.expiresAt > now }
    }

    private func trimExpired() {
        let expiry = Date().addingTimeInterval(-ttl)
        entries = entries.filter { $0.value.date >= expiry }
        hostScores = hostScores.filter { $0.value.date >= expiry }
        trimSessionAvoidance()
    }

    private func trimIfNeeded() {
        guard entries.count > maxCount else { return }
        let keptKeys = Set(
            entries
                .sorted { $0.value.date > $1.value.date }
                .prefix(maxCount)
                .map(\.key)
        )
        entries = entries.filter { keptKeys.contains($0.key) }
    }

    private func trimHostScoresIfNeeded() {
        guard hostScores.count > maxHostScoreCount else { return }
        let keptKeys = Set(
            hostScores
                .sorted { $0.value.date > $1.value.date }
                .prefix(maxHostScoreCount)
                .map(\.key)
        )
        hostScores = hostScores.filter { keptKeys.contains($0.key) }
    }

    private func loadStoreIfNeeded() {
        guard !hasLoadedStore else { return }
        hasLoadedStore = true
        if let data = try? Data(contentsOf: storeURL),
           let persisted = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = persisted
        }
        if let data = try? Data(contentsOf: hostScoreStoreURL),
           let persistedScores = try? JSONDecoder().decode([String: HostScore].self, from: data) {
            hostScores = persistedScores
        }
        trimExpired()
        trimIfNeeded()
        trimHostScoresIfNeeded()
    }

    private func schedulePersist() {
        guard persistTask == nil else { return }
        let actor = self
        let storeURL = storeURL
        let hostScoreStoreURL = hostScoreStoreURL
        persistTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 700_000_000)
            let entries = await actor.persistenceSnapshotForWrite()
            Self.writePersistedEntries(entries.entries, hostScores: entries.hostScores, to: storeURL, hostScoreStoreURL: hostScoreStoreURL)
            await actor.completePersist()
        }
    }

    private func persistenceSnapshotForWrite() async -> PersistenceSnapshot {
        persistDirty = false
        return PersistenceSnapshot(entries: entries, hostScores: hostScores)
    }

    private func completePersist() async {
        persistTask = nil
        if persistDirty {
            schedulePersist()
        }
    }

    nonisolated private static func writePersistedEntries(
        _ entries: [String: Entry],
        hostScores: [String: HostScore],
        to storeURL: URL,
        hostScoreStoreURL: URL
    ) {
        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(entries)
            try data.write(to: storeURL, options: .atomic)
            let scoreData = try JSONEncoder().encode(hostScores)
            try scoreData.write(to: hostScoreStoreURL, options: .atomic)
        } catch {}
    }

    private struct PersistenceSnapshot: Sendable {
        let entries: [String: Entry]
        let hostScores: [String: HostScore]
    }

    private struct Entry: Codable, Sendable {
        let preferredURLString: String
        let date: Date
    }

    private struct SessionAvoidance: Sendable {
        var reason: String
        var failureCount: Int
        var expiresAt: Date
    }

    private struct HostScore: Codable, Sendable {
        var averageMilliseconds: Double
        var averageKilobytesPerSecond: Double
        var successCount: Int
        var failureCount: Int
        var date: Date

        init(
            averageMilliseconds: Double = 900,
            averageKilobytesPerSecond: Double = 0,
            successCount: Int = 0,
            failureCount: Int = 0,
            date: Date = .distantPast
        ) {
            self.averageMilliseconds = averageMilliseconds
            self.averageKilobytesPerSecond = averageKilobytesPerSecond
            self.successCount = successCount
            self.failureCount = failureCount
            self.date = date
        }

        var rankScore: Double {
            let attempts = max(successCount + failureCount, 1)
            let failureRate = Double(failureCount) / Double(attempts)
            let throughputBonus = min(averageKilobytesPerSecond / 256.0, 300)
            return averageMilliseconds + failureRate * 900 - throughputBonus
        }

        static var unmeasuredRankScore: Double { 900 }

        mutating func record(
            elapsedMilliseconds: Double,
            bytes: Int64,
            succeeded: Bool,
            date: Date
        ) {
            let boundedElapsed = min(max(elapsedMilliseconds, 10), 8_000)
            let alpha = successCount + failureCount == 0 ? 1.0 : 0.28
            averageMilliseconds = averageMilliseconds * (1 - alpha) + boundedElapsed * alpha
            if succeeded {
                successCount += 1
                if bytes > 0, boundedElapsed > 0 {
                    let kbps = (Double(bytes) / 1024.0) / max(boundedElapsed / 1000.0, 0.001)
                    let throughputAlpha = averageKilobytesPerSecond <= 0 ? 1.0 : 0.24
                    averageKilobytesPerSecond = averageKilobytesPerSecond * (1 - throughputAlpha) + kbps * throughputAlpha
                }
            } else {
                failureCount += 1
            }
            if successCount + failureCount > 80 {
                successCount = max(successCount / 2, succeeded ? 1 : 0)
                failureCount = failureCount / 2
            }
            self.date = date
        }
    }
}

private final class LocalHLSProxyServer: @unchecked Sendable {
    nonisolated private static let maxStreamingCacheBytes: Int64 = 24 * 1024 * 1024

    let baseURL: URL

    private let headers: [String: String]
    nonisolated(unsafe) private var metricsID: String?
    private let listener: NWListener
    private let queue: DispatchQueue
    nonisolated(unsafe) private var routes: [String: HLSProxyRoute] = [:]
    nonisolated(unsafe) private var activeConnections: [ObjectIdentifier: NWConnection] = [:]
    nonisolated(unsafe) private var isStarted = false
    nonisolated(unsafe) private var isClosed = false

    nonisolated private init(port: UInt16, headers: [String: String], metricsID: String?) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port),
              let baseURL = URL(string: "http://127.0.0.1:\(port)")
        else {
            throw PlayerEngineError.unsupportedMedia
        }
        self.baseURL = baseURL
        self.headers = headers
        self.metricsID = metricsID
        self.listener = try NWListener(using: .tcp, on: endpointPort)
        self.queue = DispatchQueue(label: "cc.bili.local-hls.\(port)", qos: .userInitiated)
    }

    deinit {
        listener.cancel()
        activeConnections.values.forEach { $0.cancel() }
    }

    nonisolated func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isClosed = true
            self.isStarted = false
            self.routes.removeAll(keepingCapacity: false)
            self.listener.cancel()
            self.activeConnections.values.forEach { $0.cancel() }
            self.activeConnections.removeAll(keepingCapacity: false)
        }
    }

    nonisolated static func make(headers: [String: String], metricsID: String? = nil) throws -> LocalHLSProxyServer {
        var lastError: Error?
        for _ in 0..<24 {
            let port = UInt16.random(in: 49152...61000)
            do {
                return try LocalHLSProxyServer(port: port, headers: headers, metricsID: metricsID)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? PlayerEngineError.unsupportedMedia
    }

    nonisolated func updateRoutes(_ routes: [String: HLSProxyRoute]) {
        queue.async { [weak self] in
            self?.routes = routes
        }
    }

    nonisolated func updateMetricsID(_ metricsID: String?) {
        queue.async { [weak self] in
            self?.metricsID = metricsID
        }
    }

    nonisolated func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: PlayerEngineError.unsupportedMedia)
                    return
                }
                guard !self.isStarted else {
                    continuation.resume()
                    return
                }
                self.isStarted = true

                var didResume = false
                self.listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        guard !didResume else { return }
                        didResume = true
                        continuation.resume()
                    case let .failed(error):
                        guard !didResume else { return }
                        didResume = true
                        continuation.resume(throwing: error)
                    case .cancelled:
                        break
                    default:
                        break
                    }
                }
                self.listener.newConnectionHandler = { [weak self] connection in
                    self?.handleConnection(connection)
                }
                self.listener.start(queue: self.queue)
            }
        }
    }

    nonisolated private func handleConnection(_ connection: NWConnection) {
        guard !isClosed else {
            connection.cancel()
            return
        }
        let identifier = ObjectIdentifier(connection)
        activeConnections[identifier] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                self?.queue.async { [weak self] in
                    self?.activeConnections[identifier] = nil
                }
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveRequest(from: connection, accumulatedData: Data())
    }

    nonisolated private func receiveRequest(from connection: NWConnection, accumulatedData: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if error != nil {
                connection.cancel()
                return
            }

            var requestData = accumulatedData
            if let data {
                requestData.append(data)
            }

            if requestData.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.respond(to: connection, requestData: requestData)
            } else if isComplete || requestData.count > 64 * 1024 {
                self.sendError(400, reason: "Bad Request", to: connection)
            } else {
                self.receiveRequest(from: connection, accumulatedData: requestData)
            }
        }
    }

    nonisolated private func respond(to connection: NWConnection, requestData: Data) {
        let connectionID = ObjectIdentifier(connection)
        let requestStart = CACurrentMediaTime()
        guard let request = HLSProxyRequest(data: requestData) else {
            PlayerMetricsLog.logger.error("hlsProxyBadRequest")
            sendError(400, reason: "Bad Request", to: connection)
            return
        }

        guard request.method == "GET" || request.method == "HEAD" else {
            PlayerMetricsLog.logger.error(
                "hlsProxyMethodRejected method=\(request.method, privacy: .public) path=\(request.path, privacy: .public)"
            )
            sendError(405, reason: "Method Not Allowed", to: connection)
            return
        }

        guard let route = routes[request.path] else {
            PlayerMetricsLog.logger.error(
                "hlsProxyRouteMiss method=\(request.method, privacy: .public) path=\(request.path, privacy: .public)"
            )
            sendError(404, reason: "Not Found", to: connection)
            return
        }

        switch route {
        case let .data(data, contentType):
            PlayerMetricsLog.logger.debug(
                "hlsProxyServeData method=\(request.method, privacy: .public) path=\(request.path, privacy: .public) type=\(contentType, privacy: .public) bytes=\(data.count, privacy: .public)"
            )
            sendData(
                data,
                contentType: contentType,
                request: request,
                to: connection,
                closesConnection: request.shouldCloseConnection
            )
            Task.detached(priority: .utility) { [metricsID] in
                await HLSProxyStartupMetrics.shared.record(
                    metricsID: metricsID,
                    path: request.path,
                    bytes: data.count,
                    elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: requestStart),
                    source: "data"
                )
            }
        case let .remoteByteRange(url, fallbackURLs, sourceRange, contentType, transform):
            Task.detached(priority: .userInitiated) { [headers] in
                await self.serveRemoteByteRange(
                    url: url,
                    fallbackURLs: fallbackURLs,
                    sourceRange: sourceRange,
                    contentType: contentType,
                    transform: transform,
                    request: request,
                    headers: headers,
                    connectionID: connectionID,
                    to: connection
                )
            }
        }
    }

    nonisolated private func serveRemoteByteRange(
        url: URL,
        fallbackURLs: [URL],
        sourceRange: HTTPByteRange,
        contentType: String,
        transform: HLSMediaSegmentTransform?,
        request: HLSProxyRequest,
        headers: [String: String],
        connectionID: ObjectIdentifier,
        to connection: NWConnection
    ) async {
        let start = CACurrentMediaTime()
        let resolvedRange = request.range?.clamped(toLength: sourceRange.length)
        let fetchRange: HTTPByteRange
        if transform != nil {
            fetchRange = sourceRange
        } else if let resolvedRange {
            fetchRange = HTTPByteRange(
                start: sourceRange.start + resolvedRange.start,
                endInclusive: sourceRange.start + resolvedRange.endInclusive
            )
        } else {
            fetchRange = sourceRange
        }

        let sourceURLs = ([url] + fallbackURLs).removingDuplicates()
        if let cached = await cachedRange(fetchRange, sourceURLs: sourceURLs, transform: transform) {
            let responseData = responseData(from: cached, servedRange: resolvedRange, transform: transform)
            let elapsedMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: start)
            PlayerMetricsLog.logger.info(
                "hlsProxyRangeCacheHit path=\(request.path, privacy: .public) bytes=\(responseData.count, privacy: .public) elapsedMs=\(elapsedMilliseconds, format: .fixed(precision: 1), privacy: .public)"
            )
            await HLSProxyCacheMetrics.shared.record(
                metricsID: metricsID,
                path: request.path,
                source: "cache",
                bytes: responseData.count,
                elapsedMilliseconds: elapsedMilliseconds
            )
            await HLSProxyStartupMetrics.shared.record(
                metricsID: metricsID,
                path: request.path,
                bytes: responseData.count,
                elapsedMilliseconds: elapsedMilliseconds,
                source: "cache"
            )
            queue.async {
                guard self.isConnectionActive(connectionID) else { return }
                self.sendData(
                    responseData,
                    contentType: contentType,
                    request: request,
                    totalLength: sourceRange.length,
                    servedRange: resolvedRange,
                    to: connection,
                    closesConnection: true
                )
            }
            return
        }

        do {
            let fetchStart = CACurrentMediaTime()
            if shouldStreamRemoteRange(request: request, range: fetchRange, transform: transform) {
                try await streamRemoteByteRange(
                    fetchRange,
                    from: sourceURLs,
                    primaryURL: url,
                    contentType: contentType,
                    transform: transform,
                    request: request,
                    headers: headers,
                    totalLength: sourceRange.length,
                    servedRange: resolvedRange,
                    connectionID: connectionID,
                    to: connection
                )
                PlayerMetricsLog.logger.info(
                    "hlsProxyRangeStreamed path=\(request.path, privacy: .public) bytes=\(fetchRange.length, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: fetchStart), format: .fixed(precision: 1), privacy: .public)"
                )
                return
            }

            let fetchedData = try await LocalHLSBridge.fetchByteRange(
                fetchRange,
                from: sourceURLs,
                headers: headers,
                strategy: startupFetchStrategy(for: request.path)
            )
            let transformedData = transform?.apply(to: fetchedData) ?? fetchedData
            let data = responseData(from: transformedData, servedRange: resolvedRange, transform: transform)
            let elapsedMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: start)
            PlayerMetricsLog.logger.info(
                "hlsProxyRangeFetched path=\(request.path, privacy: .public) bytes=\(data.count, privacy: .public) fetchMs=\(PlayerMetricsLog.elapsedMilliseconds(since: fetchStart), format: .fixed(precision: 1), privacy: .public) elapsedMs=\(elapsedMilliseconds, format: .fixed(precision: 1), privacy: .public)"
            )
            await HLSProxyCacheMetrics.shared.record(
                metricsID: metricsID,
                path: request.path,
                source: "fetch",
                bytes: data.count,
                elapsedMilliseconds: elapsedMilliseconds
            )
            await HLSProxyStartupMetrics.shared.record(
                metricsID: metricsID,
                path: request.path,
                bytes: data.count,
                elapsedMilliseconds: elapsedMilliseconds,
                source: "fetch"
            )
            queue.async {
                guard self.isConnectionActive(connectionID) else { return }
                self.sendData(
                    data,
                    contentType: contentType,
                    request: request,
                    totalLength: sourceRange.length,
                    servedRange: resolvedRange,
                    to: connection,
                    closesConnection: true
                )
            }
        } catch {
            let proxyFailure = HLSBridgeRemoteFailure.proxyHTTPStatus(for: error)
            PlayerMetricsLog.logger.error(
                "hlsProxyRemoteFetchFailed path=\(request.path, privacy: .public) range=\(fetchRange.start, privacy: .public)-\(fetchRange.endInclusive, privacy: .public) status=\(proxyFailure.statusCode, privacy: .public) url=\(url.absoluteString, privacy: .private) error=\(error.localizedDescription, privacy: .public)"
            )
            queue.async {
                guard self.isConnectionActive(connectionID) else { return }
                self.sendError(proxyFailure.statusCode, reason: proxyFailure.reason, to: connection)
            }
        }
    }

    nonisolated private func responseData(
        from data: Data,
        servedRange: HTTPByteRange?,
        transform: HLSMediaSegmentTransform?
    ) -> Data {
        guard transform != nil, let servedRange else { return data }
        guard let lowerBound = Int(exactly: servedRange.start),
              let upperBoundInclusive = Int(exactly: servedRange.endInclusive),
              lowerBound >= 0,
              upperBoundInclusive >= lowerBound,
              upperBoundInclusive < data.count
        else {
            return Data()
        }
        return data.subdata(in: lowerBound..<(upperBoundInclusive + 1))
    }

    nonisolated private func cachedRange(_ range: HTTPByteRange, sourceURLs: [URL], transform: HLSMediaSegmentTransform?) async -> Data? {
        for url in sourceURLs {
            if let cached = await VideoRangeCache.shared.data(url: url, range: range) {
                return transform?.apply(to: cached) ?? cached
            }
        }
        return nil
    }

    nonisolated private func startupFetchStrategy(for path: String) -> HLSByteRangeFetchStrategy {
        if PlaybackEnvironment.current.shouldPreferConservativePlayback {
            return .sequential
        }
        if path.hasSuffix("/init.mp4") {
            return .fastFallback
        }
        return .sequential
    }

    nonisolated private func shouldStreamRemoteRange(
        request: HLSProxyRequest,
        range: HTTPByteRange,
        transform: HLSMediaSegmentTransform?
    ) -> Bool {
        guard case nil = request.range else { return false }
        guard request.method == "GET" else { return false }
        if request.path.contains("/media/video/") {
            return range.length >= 512 * 1024
        }
        return request.path.contains("/media/audio/")
            && (request.path.contains("/segment-0.m4s") || request.path.contains("/segment-1.m4s"))
            && range.length >= 128 * 1024
    }

    nonisolated private func startupChunkSize(for path: String, transform: HLSMediaSegmentTransform?) -> Int {
        if transform != nil {
            return 16 * 1024
        }
        if path.contains("/media/audio/") {
            return 12 * 1024
        }
        if path.contains("/segment-0.m4s") || path.contains("/segment-1.m4s") {
            return 8 * 1024
        }
        return 32 * 1024
    }

    nonisolated private static func isStartupCriticalMediaPath(_ path: String) -> Bool {
        path.hasSuffix("/init.mp4")
            || path.contains("/segment-0.m4s")
            || path.contains("/segment-1.m4s")
    }

    nonisolated private static func shouldSessionAvoidSlowStartupHost(
        path: String,
        elapsedMilliseconds: Double,
        bytes: Int,
        sourceURLCount: Int
    ) -> Bool {
        guard sourceURLCount > 1,
              isStartupCriticalMediaPath(path),
              !PlaybackEnvironment.current.shouldPreferConservativePlayback
        else { return false }

        if path.hasSuffix("/init.mp4") {
            return elapsedMilliseconds >= 850
        }

        let kilobytesPerSecond = bytes > 0 && elapsedMilliseconds > 0
            ? (Double(bytes) / 1024.0) / max(elapsedMilliseconds / 1000.0, 0.001)
            : 0
        let threshold: Double = path.contains("/segment-0.m4s") ? 2_200 : 2_800
        return elapsedMilliseconds >= threshold && kilobytesPerSecond < 768
    }

    nonisolated private static func slowStartupAvoidanceReason(path: String, elapsedMilliseconds: Double) -> String {
        let bucket: String
        if path.hasSuffix("/init.mp4") {
            bucket = "init"
        } else if path.contains("/segment-0.m4s") {
            bucket = "seg0"
        } else if path.contains("/segment-1.m4s") {
            bucket = "seg1"
        } else {
            bucket = "startup"
        }
        return "\(bucket)-slow-\(Int(elapsedMilliseconds.rounded()))ms"
    }

    nonisolated private func streamRemoteByteRange(
        _ range: HTTPByteRange,
        from urls: [URL],
        primaryURL: URL,
        contentType: String,
        transform: HLSMediaSegmentTransform?,
        request: HLSProxyRequest,
        headers: [String: String],
        totalLength: Int64,
        servedRange: HTTPByteRange?,
        connectionID: ObjectIdentifier,
        to connection: NWConnection
    ) async throws {
        let canonicalURLs = urls.removingDuplicates()
        let sourceURLs = await HLSSourcePreferenceCache.shared.preferredURLs(for: canonicalURLs)
        var lastError: Error?

        for (index, url) in sourceURLs.enumerated() {
            let reservation = await VideoRangeCache.shared.reserveExternalFetch(
                url: url,
                range: range,
                maxCacheBytes: Self.maxStreamingCacheBytes
            )
            switch reservation {
            case let .cached(data):
                let cachedStart = CACurrentMediaTime()
                let responseData = transform?.apply(to: data) ?? data
                queue.async {
                    guard self.isConnectionActive(connectionID) else { return }
                    self.sendData(
                        responseData,
                        contentType: contentType,
                        request: request,
                        totalLength: totalLength,
                        servedRange: servedRange,
                        to: connection,
                        closesConnection: true
                    )
                }
                PlayerMetricsLog.logger.info(
                    "hlsProxyRangeStreamCacheHit path=\(request.path, privacy: .public) bytes=\(responseData.count, privacy: .public)"
                )
                await HLSProxyCacheMetrics.shared.record(
                    metricsID: metricsID,
                    path: request.path,
                    source: "streamCache",
                    bytes: responseData.count,
                    elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: cachedStart)
                )
                await HLSProxyStartupMetrics.shared.record(
                    metricsID: metricsID,
                    path: request.path,
                    bytes: responseData.count,
                    elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: cachedStart),
                    source: "streamCache"
                )
                return
            case let .pending(task):
                do {
                    let joinedStart = CACurrentMediaTime()
                    let data = try await task.value
                    let responseData = transform?.apply(to: data) ?? data
                    queue.async {
                        guard self.isConnectionActive(connectionID) else { return }
                        self.sendData(
                            responseData,
                            contentType: contentType,
                            request: request,
                            totalLength: totalLength,
                            servedRange: servedRange,
                            to: connection,
                            closesConnection: true
                        )
                    }
                    PlayerMetricsLog.logger.info(
                        "hlsProxyRangeStreamJoined path=\(request.path, privacy: .public) bytes=\(responseData.count, privacy: .public)"
                    )
                    await HLSProxyCacheMetrics.shared.record(
                        metricsID: metricsID,
                        path: request.path,
                        source: "streamJoin",
                        bytes: responseData.count,
                        elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: joinedStart)
                    )
                    await HLSProxyStartupMetrics.shared.record(
                        metricsID: metricsID,
                        path: request.path,
                        bytes: responseData.count,
                        elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: joinedStart),
                        source: "streamJoin"
                    )
                    return
                } catch {
                    lastError = error
                    guard index < sourceURLs.count - 1, !Task.isCancelled else { break }
                    continue
                }
            case .unreserved, .reserved:
                break
            }

            do {
                let streamStart = CACurrentMediaTime()
                let responseHeader = streamingHeaderData(
                    contentType: contentType,
                    request: request,
                    responseLength: range.length,
                    totalLength: totalLength,
                    servedRange: servedRange
                )
                let startupMetricsID = metricsID
                let cacheData = try await HLSRemoteRangeStreamer.stream(
                    range: range,
                    from: url,
                    headers: headers,
                    responseHeader: responseHeader,
                    connection: connection,
                    cacheLimit: Self.maxStreamingCacheBytes,
                    startupChunkSize: startupChunkSize(for: request.path, transform: transform),
                    transform: transform
                ) { bytes in
                    await HLSProxyStartupMetrics.shared.record(
                        metricsID: startupMetricsID,
                        path: request.path,
                        bytes: bytes,
                        elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: streamStart),
                        source: "stream"
                    )
                }
                let streamElapsed = PlayerMetricsLog.elapsedMilliseconds(since: streamStart)
                let streamedBytes = cacheData?.byteCount ?? Int(range.length)
                let shouldAvoidSlowStartupHost = Self.shouldSessionAvoidSlowStartupHost(
                    path: request.path,
                    elapsedMilliseconds: streamElapsed,
                    bytes: streamedBytes,
                    sourceURLCount: canonicalURLs.count
                )
                await HLSSourcePreferenceCache.shared.recordResult(
                    url: url,
                    for: canonicalURLs,
                    elapsedMilliseconds: streamElapsed,
                    bytes: Int64(streamedBytes),
                    succeeded: true,
                    metricsID: metricsID
                )
                if shouldAvoidSlowStartupHost {
                    let reason = Self.slowStartupAvoidanceReason(path: request.path, elapsedMilliseconds: streamElapsed)
                    await HLSSourcePreferenceCache.shared.recordSessionAvoidance(
                        host: url.host,
                        reason: reason,
                        metricsID: metricsID
                    )
                    await PlayerMetricsLog.record(
                        .network,
                        metricsID: metricsID ?? request.path,
                        message: "startupAvoid host=\(url.host ?? "-") reason=\(reason) bytes=\(streamedBytes / 1024)KB"
                    )
                }
                if request.path.contains("/segment-0.m4s") || request.path.contains("/init.mp4") {
                    await PlayerMetricsLog.record(
                        .network,
                        metricsID: metricsID ?? request.path,
                        message: "host=\(url.host ?? "-") \(Int(streamElapsed.rounded()))ms \(streamedBytes / 1024)KB"
                    )
                }
                await HLSProxyCacheMetrics.shared.record(
                    metricsID: metricsID,
                    path: request.path,
                    source: "stream",
                    bytes: streamedBytes,
                    elapsedMilliseconds: streamElapsed
                )
                if !shouldAvoidSlowStartupHost {
                    await HLSSourcePreferenceCache.shared.recordPreferredURL(url, for: canonicalURLs)
                }
                if case let .reserved(token) = reservation {
                    if let cacheData {
                        do {
                            let data = try cacheData.loadData()
                            await VideoRangeCache.shared.finishExternalFetch(token, data: data)
                        } catch {
                            await VideoRangeCache.shared.failExternalFetch(token, error: error)
                        }
                    } else {
                        await VideoRangeCache.shared.failExternalFetch(token, error: HLSRangeStreamError.notCacheable)
                    }
                }
                if let cacheData, !reservation.isReserved {
                    do {
                        let data = try cacheData.loadData()
                        await VideoRangeCache.shared.store(data, url: url, range: range)
                        if url != primaryURL {
                            await VideoRangeCache.shared.store(data, url: primaryURL, range: range)
                        }
                    } catch {
                        PlayerMetricsLog.logger.error(
                            "hlsProxyRangeStreamCacheWriteFailed path=\(request.path, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                        )
                    }
                }
                cacheData?.cleanup()
                if index > 0 {
                    PlayerMetricsLog.logger.info(
                        "hlsProxyRangeStreamFallbackSuccess fallbackIndex=\(index, privacy: .public) path=\(request.path, privacy: .public)"
                    )
                }
                return
            } catch {
                if case let .reserved(token) = reservation {
                    await VideoRangeCache.shared.failExternalFetch(token, error: error)
                }
                await HLSSourcePreferenceCache.shared.recordFailure(
                    url: url,
                    for: canonicalURLs,
                    elapsedMilliseconds: 0,
                    error: error,
                    metricsID: metricsID
                )
                lastError = error
                if let streamError = error as? HLSRangeStreamError,
                   !streamError.isRetryable {
                    break
                }
                guard index < sourceURLs.count - 1, !Task.isCancelled else { break }
                PlayerMetricsLog.logger.info(
                    "hlsProxyRangeStreamFallbackSwitch fallbackIndex=\(index + 1, privacy: .public) path=\(request.path, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
            }
        }

        throw lastError ?? PlayerEngineError.unsupportedMedia
    }

    nonisolated private func streamingHeaderData(
        contentType: String,
        request: HLSProxyRequest,
        responseLength: Int64,
        totalLength: Int64,
        servedRange: HTTPByteRange?
    ) -> Data {
        var headers = [
            "Content-Type": contentType,
            "Content-Length": "\(responseLength)",
            "Accept-Ranges": "bytes",
            "Cache-Control": "public, max-age=3600",
            "Connection": "close"
        ]
        let statusLine: String
        if let servedRange {
            statusLine = "HTTP/1.1 206 Partial Content"
            headers["Content-Range"] = "bytes \(servedRange.start)-\(servedRange.endInclusive)/\(totalLength)"
        } else {
            statusLine = "HTTP/1.1 200 OK"
        }
        return Self.responseHeaderData(statusLine: statusLine, headers: headers)
    }

    nonisolated private func sendData(
        _ data: Data,
        contentType: String,
        request: HLSProxyRequest,
        totalLength: Int64? = nil,
        servedRange: HTTPByteRange? = nil,
        to connection: NWConnection,
        closesConnection: Bool = true
    ) {
        let body = request.method == "HEAD" ? Data() : data
        var headers = [
            "Content-Type": contentType,
            "Content-Length": "\(data.count)",
            "Accept-Ranges": "bytes",
            "Cache-Control": request.path.hasSuffix(".m3u8") ? "no-cache" : "public, max-age=3600",
            "Connection": closesConnection ? "close" : "keep-alive"
        ]
        let statusLine: String
        if let servedRange, let totalLength {
            statusLine = "HTTP/1.1 206 Partial Content"
            headers["Content-Range"] = "bytes \(servedRange.start)-\(servedRange.endInclusive)/\(totalLength)"
        } else {
            statusLine = "HTTP/1.1 200 OK"
        }
        sendResponse(
            statusLine: statusLine,
            headers: headers,
            body: body,
            to: connection,
            closesConnection: closesConnection
        )
    }

    nonisolated private func sendError(_ statusCode: Int, reason: String, to connection: NWConnection) {
        let body = Data(reason.utf8)
        sendResponse(
            statusLine: "HTTP/1.1 \(statusCode) \(reason)",
            headers: [
                "Content-Type": "text/plain; charset=utf-8",
                "Content-Length": "\(body.count)",
                "Connection": "close"
            ],
            body: body,
            to: connection
        )
    }

    nonisolated private func sendStreamingHeader(
        contentType: String,
        request: HLSProxyRequest,
        responseLength: Int64,
        totalLength: Int64,
        servedRange: HTTPByteRange?,
        to connection: NWConnection
    ) async throws {
        var headers = [
            "Content-Type": contentType,
            "Content-Length": "\(responseLength)",
            "Accept-Ranges": "bytes",
            "Cache-Control": request.path.hasSuffix(".m3u8") ? "no-cache" : "public, max-age=3600",
            "Connection": "close"
        ]
        let statusLine: String
        if let servedRange {
            statusLine = "HTTP/1.1 206 Partial Content"
            headers["Content-Range"] = "bytes \(servedRange.start)-\(servedRange.endInclusive)/\(totalLength)"
        } else {
            statusLine = "HTTP/1.1 200 OK"
        }
        try await sendContent(Self.responseHeaderData(statusLine: statusLine, headers: headers), to: connection)
    }

    nonisolated private func sendResponse(
        statusLine: String,
        headers: [String: String],
        body: Data,
        to connection: NWConnection,
        closesConnection: Bool = true
    ) {
        var response = Self.responseHeaderData(statusLine: statusLine, headers: headers)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            guard !closesConnection, let self else {
                connection.cancel()
                return
            }
            guard self.isConnectionActive(ObjectIdentifier(connection)) else {
                connection.cancel()
                return
            }
            self.receiveRequest(from: connection, accumulatedData: Data())
        })
    }

    nonisolated private func isConnectionActive(_ identifier: ObjectIdentifier) -> Bool {
        !isClosed && activeConnections[identifier] != nil
    }

    nonisolated private func sendContent(_ data: Data, to connection: NWConnection) async throws {
        guard !data.isEmpty else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    nonisolated private static func responseHeaderData(
        statusLine: String,
        headers: [String: String]
    ) -> Data {
        let headerText = ([statusLine] + headers.map { "\($0.key): \($0.value)" })
            .joined(separator: "\r\n") + "\r\n\r\n"
        return Data(headerText.utf8)
    }

}
