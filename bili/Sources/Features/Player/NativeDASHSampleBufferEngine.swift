import AVFoundation
import AVKit
import OSLog
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class AdaptivePlayerRenderingEngine: PlayerRenderingEngine {
    private var activeEngine: PlayerRenderingEngine
    private let preferredKernel: PlayerKernelType
    private weak var surface: UIView?
    private weak var nativeController: AVPlayerViewController?
    private var videoGravity: AVLayerVideoGravity = .resizeAspect
    private weak var viewModel: PlayerStateViewModel?
    private var contentOverlay: AnyView?
    private var isDanmakuEnabled = true
    private var onToggleDanmaku: (() -> Void)?
    private var onShowDanmakuSettings: (() -> Void)?
    private var qualityControls: PlayerQualityControls?
    private var currentVolume: Float = 1
    private var currentMuted = false
    private var currentRate: Double = 1
    private var preferredPeakBitRate: Double?
    private var isTemporaryAudioSuppressed = false
    private var isPictureInPictureEnabled = false
    private var wantsPlayback = false
    private var currentSource: PlayerStreamSource?
    private var didFallbackFromNativeDASHForCurrentSource = false
    private var runtimeFallbackTask: Task<Void, Never>?
    private var playbackGeneration = 0
    private var isStopped = true

    private enum AVPlayerFallbackDecision: String {
        case failAVPlayerOnly = "avPlayerOnly"
        case skipCancelled = "cancelled"
        case skipRefreshPlayURL = "refreshPlayURL"
        case skipAuthRefresh = "authRefresh"
        case skipSourceRecovery = "sourceRecovery"
    }

    var onPlaybackStateChange: (@MainActor (PlayerEnginePlaybackState) -> Void)?
    var onPlaybackIntentChange: (@MainActor (Bool) -> Void)?
    var onLoadingProgressChange: (@MainActor (Double) -> Void)?
    var onFirstFrame: (@MainActor (TimeInterval) -> Void)?

    init(preferredKernel: PlayerKernelType = .avPlayer) {
        self.preferredKernel = preferredKernel.normalizedForFormalPlayback
        activeEngine = Self.makeEngine(for: self.preferredKernel)
        bind(activeEngine)
    }

    var hasMedia: Bool { !isStopped && activeEngine.hasMedia }
    var needsMediaRecovery: Bool { !isStopped && activeEngine.needsMediaRecovery }
    var playbackErrorMessage: String? { activeEngine.playbackErrorMessage }
    var lastFailureReason: HLSBridgeFailureReason? { activeEngine.lastFailureReason }
    var supportsPictureInPicture: Bool { activeEngine.supportsPictureInPicture }
    var isPictureInPictureActive: Bool { activeEngine.isPictureInPictureActive }
    var usesNativePlaybackControls: Bool { activeEngine.usesNativePlaybackControls }
    var diagnostics: PlayerEngineDiagnostics { activeEngine.diagnostics }
    var volume: Float { activeEngine.volume }
    var isMuted: Bool { activeEngine.isMuted }

    func attachSurface(_ surface: UIView) {
        self.surface = surface
        activeEngine.attachSurface(surface)
    }

    func detachSurface(_ surface: UIView) {
        activeEngine.detachSurface(surface)
        if self.surface === surface {
            self.surface = nil
        }
    }

    func refreshSurfaceLayout() {
        guard !isStopped else { return }
        activeEngine.refreshSurfaceLayout()
    }

    func recoverSurface() {
        guard !isStopped else { return }
        activeEngine.recoverSurface()
    }

    func setViewModel(_ viewModel: PlayerStateViewModel?) {
        self.viewModel = viewModel
        activeEngine.setViewModel(viewModel)
    }

    func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        videoGravity = gravity
        activeEngine.setVideoGravity(gravity)
    }

    func setContentOverlay(_ overlay: AnyView?) {
        contentOverlay = overlay
        activeEngine.setContentOverlay(overlay)
    }

    func setDanmakuControls(
        isEnabled: Bool,
        onToggle: (() -> Void)?,
        onShowSettings: (() -> Void)?
    ) {
        isDanmakuEnabled = isEnabled
        onToggleDanmaku = onToggle
        onShowDanmakuSettings = onShowSettings
        activeEngine.setDanmakuControls(
            isEnabled: isEnabled,
            onToggle: onToggle,
            onShowSettings: onShowSettings
        )
    }

    func attachNativePlaybackController(_ controller: AVPlayerViewController) {
        nativeController = controller
        activeEngine.attachNativePlaybackController(controller)
        activeEngine.setPictureInPictureEnabled(isPictureInPictureEnabled)
    }

    func detachNativePlaybackController(_ controller: AVPlayerViewController) {
        activeEngine.detachNativePlaybackController(controller)
        if nativeController === controller {
            nativeController = nil
        }
    }

    func setPictureInPictureEnabled(_ isEnabled: Bool) {
        isPictureInPictureEnabled = isEnabled
        activeEngine.setPictureInPictureEnabled(isEnabled)
    }

    func prepare(source: PlayerStreamSource) async throws {
        playbackGeneration &+= 1
        let generation = playbackGeneration
        isStopped = false
        currentSource = source
        didFallbackFromNativeDASHForCurrentSource = false
        runtimeFallbackTask?.cancel()
        runtimeFallbackTask = nil

        let effectiveKernel = preferredKernel(for: source)

        if !(activeEngine is AVPlayerHLSBridgeEngine) {
            switchActiveEngine(to: AVPlayerHLSBridgeEngine())
        }
        PlayerMetricsLog.logger.info(
            "adaptiveEngineSelected path=avPlayer reason=\(self.selectionReason(for: source, effectiveKernel: effectiveKernel), privacy: .public) id=\(source.metricsID, privacy: .public)"
        )
        do {
            try await activeEngine.prepare(source: source)
            guard !Task.isCancelled, generation == playbackGeneration else {
                throw CancellationError()
            }
        } catch {
            guard !Task.isCancelled, generation == playbackGeneration else {
                throw CancellationError()
            }
            try await fallbackFromAVPlayerPrepareFailure(
                source: source,
                error: error,
                generation: generation
            )
        }
    }

    private func preferredKernel(for _: PlayerStreamSource) -> PlayerKernelType {
        .avPlayer
    }

    private func selectionReason(
        for source: PlayerStreamSource,
        effectiveKernel: PlayerKernelType
    ) -> String {
        guard let stream = source.videoStream else { return "preferredKernel" }
        if effectiveKernel == .avPlayer,
           stream.isAV1VideoCodec {
            return "av1AVPlayerHardwarePipeline"
        }
        return "avPlayerOnly"
    }

    func play() {
        guard !isStopped else { return }
        wantsPlayback = true
        activeEngine.play()
    }

    func pause() {
        guard !isStopped else { return }
        wantsPlayback = false
        activeEngine.pause()
    }

    func pauseForNavigation() {
        guard !isStopped else { return }
        wantsPlayback = false
        activeEngine.pauseForNavigation()
    }

    func suspendForNavigation() {
        guard !isStopped else { return }
        wantsPlayback = false
        activeEngine.suspendForNavigation()
    }

    func stop() {
        playbackGeneration &+= 1
        wantsPlayback = false
        runtimeFallbackTask?.cancel()
        runtimeFallbackTask = nil
        currentSource = nil
        didFallbackFromNativeDASHForCurrentSource = false
        isStopped = true
        activeEngine.stop()
    }

    func setPlaybackRate(_ rate: Double) {
        currentRate = rate
        activeEngine.setPlaybackRate(rate)
    }

    func setPreferredPeakBitRate(_ bitRate: Double?) {
        preferredPeakBitRate = bitRate
        activeEngine.setPreferredPeakBitRate(bitRate)
    }

    func setVolume(_ volume: Float) {
        currentVolume = min(max(volume, 0), 1)
        activeEngine.setVolume(currentVolume)
        if isTemporaryAudioSuppressed {
            activeEngine.setTemporaryAudioSuppressed(true)
        }
    }

    func setMuted(_ isMuted: Bool) {
        currentMuted = isMuted
        activeEngine.setMuted(isMuted)
        if isTemporaryAudioSuppressed {
            activeEngine.setTemporaryAudioSuppressed(true)
        }
    }

    func setQualityControls(_ controls: PlayerQualityControls?) {
        qualityControls = controls
        activeEngine.setQualityControls(controls)
    }

    func setTemporaryAudioSuppressed(_ isSuppressed: Bool) {
        isTemporaryAudioSuppressed = isSuppressed
        activeEngine.setTemporaryAudioSuppressed(isSuppressed)
    }

    func seek(toTime time: TimeInterval) -> TimeInterval? {
        guard !isStopped else { return nil }
        let appliedTime = activeEngine.seek(toTime: time)
        updateCurrentSourceResumeTime(appliedTime)
        return appliedTime
    }

    func seek(toProgress progress: Double, duration: TimeInterval?) -> TimeInterval? {
        guard !isStopped else { return nil }
        let appliedTime = activeEngine.seek(toProgress: progress, duration: duration)
        updateCurrentSourceResumeTime(appliedTime)
        return appliedTime
    }

    func seek(by interval: TimeInterval, from currentTime: TimeInterval, duration: TimeInterval?) -> TimeInterval? {
        guard !isStopped else { return nil }
        let appliedTime = activeEngine.seek(by: interval, from: currentTime, duration: duration)
        updateCurrentSourceResumeTime(appliedTime)
        return appliedTime
    }

    func seekAfterUserScrub(toProgress progress: Double, duration: TimeInterval?) async -> TimeInterval? {
        guard !isStopped else { return nil }
        wantsPlayback = false
        let engine = activeEngine
        let generation = playbackGeneration
        let appliedTime = await engine.seekAfterUserScrub(toProgress: progress, duration: duration)
        guard !Task.isCancelled,
              !isStopped,
              generation == playbackGeneration
        else { return nil }
        if let appliedTime {
            updateCurrentSourceResumeTime(appliedTime)
            return appliedTime
        }
        return nil
    }

    func snapshot(durationHint: TimeInterval?) -> PlayerPlaybackSnapshot {
        activeEngine.snapshot(durationHint: durationHint)
    }

    func currentVideoFrameImage() -> UIImage? {
        activeEngine.currentVideoFrameImage()
    }

    func currentSurfaceSnapshotImage() -> UIImage? {
        activeEngine.currentSurfaceSnapshotImage()
            ?? surface?.biliRenderedSnapshotImage()
    }

    func pictureInPictureContentSource() -> AVPictureInPictureController.ContentSource? {
        activeEngine.pictureInPictureContentSource()
    }

    func togglePictureInPicture() {
        guard !isStopped else { return }
        activeEngine.togglePictureInPicture()
    }

    func stopPictureInPictureIfNeeded() {
        guard !isStopped else { return }
        activeEngine.stopPictureInPictureIfNeeded()
    }

    func invalidatePictureInPicturePlaybackState() {
        guard !isStopped else { return }
        activeEngine.invalidatePictureInPicturePlaybackState()
    }

    private func switchActiveEngine(to engine: PlayerRenderingEngine) {
        guard activeEngine !== engine else { return }
        let oldEngine = activeEngine
        oldEngine.onPlaybackStateChange = nil
        oldEngine.onPlaybackIntentChange = nil
        oldEngine.onLoadingProgressChange = nil
        oldEngine.onFirstFrame = nil
        if let nativeController {
            oldEngine.detachNativePlaybackController(nativeController)
        }
        if let surface {
            oldEngine.detachSurface(surface)
        }
        oldEngine.setViewModel(nil)
        oldEngine.stop()

        activeEngine = engine
        syncSurfaceNativePlaybackControllerVisibility(for: engine)
        bind(engine)
        engine.setViewModel(viewModel)
        engine.setVideoGravity(videoGravity)
        engine.setVolume(currentVolume)
        engine.setMuted(currentMuted)
        engine.setTemporaryAudioSuppressed(isTemporaryAudioSuppressed)
        engine.setPlaybackRate(currentRate)
        engine.setPreferredPeakBitRate(preferredPeakBitRate)
        engine.setPictureInPictureEnabled(isPictureInPictureEnabled)
        engine.setContentOverlay(contentOverlay)
        engine.setDanmakuControls(
            isEnabled: isDanmakuEnabled,
            onToggle: onToggleDanmaku,
            onShowSettings: onShowDanmakuSettings
        )
        engine.setQualityControls(qualityControls)
        if let surface {
            engine.attachSurface(surface)
        }
        if let nativeController {
            engine.attachNativePlaybackController(nativeController)
        }
    }

    private func syncSurfaceNativePlaybackControllerVisibility(for engine: PlayerRenderingEngine) {
        guard let surfaceContainer = surface?.superview as? VideoSurfaceContainerView else { return }
        surfaceContainer.setNativePlaybackControllerEnabled(engine.usesNativePlaybackControls)
    }

    private func updateCurrentSourceResumeTime(_ resumeTime: TimeInterval?) {
        guard let resumeTime,
              resumeTime.isFinite,
              resumeTime >= 0,
              let currentSource
        else { return }
        self.currentSource = currentSource.withResumeTime(resumeTime)
    }

    private func bind(_ engine: PlayerRenderingEngine) {
        engine.onPlaybackStateChange = { [weak self, weak engine] state in
            guard let self,
                  let engine,
                  !self.isStopped,
                  self.activeEngine === engine
            else { return }
            if case .failed(let message) = state,
               (self.fallbackFromNativeRuntimeFailure(message: message)
                || self.fallbackFromAVPlayerRuntimeFailure(message: message)) {
                return
            }
            self.onPlaybackStateChange?(state)
        }
        engine.onPlaybackIntentChange = { [weak self, weak engine] wantsPlayback in
            guard let self,
                  let engine,
                  !self.isStopped,
                  self.activeEngine === engine
            else { return }
            self.wantsPlayback = wantsPlayback
            self.onPlaybackIntentChange?(wantsPlayback)
        }
        engine.onLoadingProgressChange = { [weak self, weak engine] progress in
            guard let self,
                  let engine,
                  !self.isStopped,
                  self.activeEngine === engine
            else { return }
            self.onLoadingProgressChange?(progress)
        }
        engine.onFirstFrame = { [weak self, weak engine] currentTime in
            guard let self,
                  let engine,
                  !self.isStopped,
                  self.activeEngine === engine
            else { return }
            self.onFirstFrame?(currentTime)
        }
    }

    private static func makeEngine(for kernel: PlayerKernelType) -> PlayerRenderingEngine {
        switch kernel {
        case .ksPlayer, .avPlayer:
            return AVPlayerHLSBridgeEngine()
        }
    }

    private func fallbackFromNativeRuntimeFailure(message: String?) -> Bool {
        guard !isStopped,
              activeEngine is NativeDASHSampleBufferEngine,
              !didFallbackFromNativeDASHForCurrentSource,
              let currentSource
        else { return false }
        didFallbackFromNativeDASHForCurrentSource = true
        let fallbackSnapshot = activeEngine.snapshot(durationHint: currentSource.durationHint)
        let fallbackTime = fallbackSnapshot.currentTime.flatMap { time -> TimeInterval? in
            guard time.isFinite, time > 0.35 else { return nil }
            return time
        } ?? currentSource.resumeTime
        let fallbackSource = currentSource.withResumeTime(fallbackTime)
        self.currentSource = fallbackSource
        let generation = playbackGeneration
        runtimeFallbackTask?.cancel()
        runtimeFallbackTask = Task { @MainActor [weak self] in
            guard let self,
                  !Task.isCancelled,
                  !self.isStopped,
                  generation == self.playbackGeneration
            else { return }
            defer { self.runtimeFallbackTask = nil }
            PlayerMetricsLog.logger.error(
                "nativeSampleBufferRuntimeFailed fallback=avPlayer id=\(fallbackSource.metricsID, privacy: .public) time=\(fallbackTime, format: .fixed(precision: 2), privacy: .public) error=\((message ?? "-"), privacy: .public)"
            )
            self.onPlaybackStateChange?(.buffering)
            self.switchActiveEngine(to: AVPlayerHLSBridgeEngine())
            do {
                try await self.activeEngine.prepare(source: fallbackSource)
                guard !Task.isCancelled,
                      !self.isStopped,
                      generation == self.playbackGeneration
                else { return }
                if self.wantsPlayback {
                    self.activeEngine.play()
                }
            } catch {
                guard !Task.isCancelled,
                      !self.isStopped,
                      generation == self.playbackGeneration
                else { return }
                do {
                    try await self.fallbackFromAVPlayerPrepareFailure(
                        source: fallbackSource,
                        error: error,
                        generation: generation
                    )
                    guard !Task.isCancelled,
                          !self.isStopped,
                          generation == self.playbackGeneration
                    else { return }
                    if self.wantsPlayback {
                        self.activeEngine.play()
                    }
                } catch {
                    guard !Task.isCancelled,
                          !self.isStopped,
                          generation == self.playbackGeneration
                    else { return }
                    self.onPlaybackStateChange?(.failed(error.localizedDescription))
                }
            }
        }
        return true
    }

    private func fallbackFromAVPlayerRuntimeFailure(message: String?) -> Bool {
        guard !isStopped,
              activeEngine is AVPlayerHLSBridgeEngine,
              let currentSource
        else { return false }
        let failureReason = activeEngine.lastFailureReason
        let decision = avPlayerFallbackDecision(for: failureReason)
        recordAVPlayerFallbackDecision(
            decision,
            source: currentSource,
            origin: "runtime",
            reason: failureReason,
            message: message
        )
        return false
    }

    private func fallbackFromAVPlayerPrepareFailure(
        source: PlayerStreamSource,
        error: Error,
        generation: Int
    ) async throws {
        let failureReason = activeEngine.lastFailureReason ?? HLSBridgeRemoteFailure.reason(for: error)
        let decision = avPlayerFallbackDecision(for: failureReason)
        recordAVPlayerFallbackDecision(
            decision,
            source: source,
            origin: "prepare",
            reason: failureReason,
            message: error.localizedDescription
        )
        guard !Task.isCancelled,
              !isStopped,
              generation == playbackGeneration
        else {
            throw CancellationError()
        }
        throw error
    }

    private func avPlayerFallbackDecision(for reason: HLSBridgeFailureReason?) -> AVPlayerFallbackDecision {
        guard let reason else { return .failAVPlayerOnly }
        switch reason.category {
        case .authDenied:
            return .skipAuthRefresh
        case .urlExpired:
            return .skipRefreshPlayURL
        case .rateLimited:
            return .skipSourceRecovery
        case .cancelled:
            return .skipCancelled
        case .serverUnavailable, .timeout, .network, .invalidResponse,
             .codecUnsupported, .hardwareDecodeRejected, .decoderFailed,
             .terminalStall, .rangeUnsupported, .unknown:
            return .failAVPlayerOnly
        }
    }

    private func recordAVPlayerFallbackDecision(
        _ decision: AVPlayerFallbackDecision,
        source: PlayerStreamSource,
        origin: String,
        reason: HLSBridgeFailureReason?,
        message: String?
    ) {
        PlayerMetricsLog.record(
            .network,
            metricsID: source.metricsID,
            title: source.title,
            message: "fallbackDecision=\(decision.rawValue) origin=\(origin) \(failureReasonDescription(reason)) error=\(message ?? "-")"
        )
        PlayerMetricsLog.logger.info(
            "avPlayerFallbackDecision decision=\(decision.rawValue, privacy: .public) origin=\(origin, privacy: .public) id=\(source.metricsID, privacy: .public) category=\(reason?.category.rawValue ?? "-", privacy: .public) status=\(reason?.statusCode ?? 0, privacy: .public)"
        )
    }

    private func failureReasonDescription(_ reason: HLSBridgeFailureReason?) -> String {
        guard let reason else { return "reason=unknown" }
        var parts = [
            "reason=\(reason.category.rawValue)",
            "layer=\(reason.layer.rawValue)"
        ]
        if let statusCode = reason.statusCode {
            parts.append("status=\(statusCode)")
        }
        if let host = reason.urlHost, !host.isEmpty {
            parts.append("host=\(host)")
        }
        if let rangeDescription = reason.rangeDescription, !rangeDescription.isEmpty {
            parts.append("range=\(rangeDescription)")
        }
        return parts.joined(separator: " ")
    }
}

nonisolated private enum NativeDASHStartupExperiment {
    private static let userDefaultsKey = "cc.bili.nativeDASHStartupEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: userDefaultsKey)
    }
}

@MainActor
final class NativeDASHSampleBufferEngine: PlayerRenderingEngine {
    private static let candidateLimit = 3
    private static let candidatePairLimit = 2
    private static let prepareTimeout: TimeInterval = 2.4
    private static let seekPrepareTimeout: TimeInterval = 2.2
    private static let firstFrameTimeoutNanoseconds: UInt64 = 2_800_000_000

    private let displayLayer: AVSampleBufferDisplayLayer
    private let videoRenderer: AVSampleBufferVideoRenderer
    private let audioRenderer = AVSampleBufferAudioRenderer()
    private let synchronizer = AVSampleBufferRenderSynchronizer()
    private weak var surfaceView: UIView?
    private var source: PlayerStreamSource?
    private var session: NativeDASHSampleBufferSession?
    private var seekTask: Task<Void, Never>?
    private var warmupTask: Task<Void, Never>?
    private var firstFrameWatchdogTask: Task<Void, Never>?
    private var pendingSurfaceDetachTask: Task<Void, Never>?
    private var decodeFailureObserver: NSObjectProtocol?
    private var requiresFlushObserver: NSObjectProtocol?
    private var duration: TimeInterval?
    private var currentRate: Float = 1
    private var wantsPlayback = false
    private var isStopped = true
    private var didReportFirstFrame = false
    private var currentTime: TimeInterval = 0
    private var lastErrorMessage: String?
    private var videoGravity: AVLayerVideoGravity = .resizeAspect
    private var sessionGeneration = 0
    private var targetVolume: Float = 1
    private var targetMuted = false
    private var isTemporaryAudioSuppressed = false
    private var pendingRestartTime: TimeInterval?

    var onPlaybackStateChange: (@MainActor (PlayerEnginePlaybackState) -> Void)?
    var onPlaybackIntentChange: (@MainActor (Bool) -> Void)?
    var onLoadingProgressChange: (@MainActor (Double) -> Void)?
    var onFirstFrame: (@MainActor (TimeInterval) -> Void)?

    init() {
        let layer = AVSampleBufferDisplayLayer()
        displayLayer = layer
        videoRenderer = layer.sampleBufferRenderer
        displayLayer.videoGravity = videoGravity
        displayLayer.backgroundColor = UIColor.black.cgColor
        displayLayer.preventsDisplaySleepDuringVideoPlayback = true
        displayLayer.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "frame": NSNull()
        ]
        synchronizer.addRenderer(videoRenderer)
        synchronizer.addRenderer(audioRenderer)
        observeVideoRendererFailures()
    }

    deinit {
        if let decodeFailureObserver {
            NotificationCenter.default.removeObserver(decodeFailureObserver)
        }
        if let requiresFlushObserver {
            NotificationCenter.default.removeObserver(requiresFlushObserver)
        }
        seekTask?.cancel()
        warmupTask?.cancel()
        firstFrameWatchdogTask?.cancel()
        pendingSurfaceDetachTask?.cancel()
        session?.stop()
        videoRenderer.stopRequestingMediaData()
        audioRenderer.stopRequestingMediaData()
    }

    static func canPrepare(_ source: PlayerStreamSource) -> Bool {
        guard source.videoURL != nil,
              source.audioURL != nil,
              let videoStream = source.videoStream,
              let audioStream = source.audioStream,
              videoStream.isHEVCVideoCodec,
              audioStream.isAACAudioCodec
        else { return false }
        return true
    }

    var hasMedia: Bool {
        !isStopped && session != nil
    }

    var needsMediaRecovery: Bool {
        lastErrorMessage != nil
    }

    var playbackErrorMessage: String? {
        lastErrorMessage
    }

    var lastFailureReason: HLSBridgeFailureReason? {
        nil
    }

    var supportsPictureInPicture: Bool {
        false
    }

    var isPictureInPictureActive: Bool {
        false
    }

    var usesNativePlaybackControls: Bool {
        false
    }

    var diagnostics: PlayerEngineDiagnostics {
        PlayerEngineDiagnostics(
            engineName: "Native DASH",
            decodePath: .sampleBuffer,
            codec: source?.videoStream?.codecLabel,
            resolution: source?.videoStream?.resolutionLabel,
            frameRate: source?.videoStream?.displayFrameRate,
            bandwidth: source?.videoStream?.bandwidth,
            dynamicRange: source?.dynamicRange ?? .sdr,
            isDASH: true,
            usesLocalHLSBridge: false,
            hlsVideoVariantCount: 0,
            hlsVideoVariantQualities: [],
            preferredForwardBufferDuration: nil,
            maxBufferDuration: nil,
            asynchronousDecompressionEnabled: false,
            hardwareDecodeRequested: true,
            isHardwareDecodeCompatible: source?.videoStream?.isHardwareDecodingCompatibleVideo,
            environmentSummary: nativeDiagnosticSummary
        )
    }

    private var nativeDiagnosticSummary: String {
        var parts: [String] = [
            PlaybackEnvironment.current.diagnosticSummary,
            "独立Asset会话",
            "Range缓存",
            "Content-Length缓存"
        ]
        if let session {
            parts.append("video=\(session.videoHost)")
            parts.append("audio=\(session.audioHost)")
        }
        if PlaybackEnvironment.current.shouldPreferConservativePlayback {
            parts.append("保守网络策略")
        } else {
            parts.append("小Range快速兜底")
        }
        return parts
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var volume: Float {
        targetVolume
    }

    var isMuted: Bool {
        targetMuted
    }

    func attachSurface(_ surface: UIView) {
        pendingSurfaceDetachTask?.cancel()
        pendingSurfaceDetachTask = nil
        surfaceView = surface
        if displayLayer.superlayer !== surface.layer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            displayLayer.removeFromSuperlayer()
            surface.layer.insertSublayer(displayLayer, at: 0)
            CATransaction.commit()
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
            self.displayLayer.removeFromSuperlayer()
            self.pendingSurfaceDetachTask = nil
        }
        surfaceView = nil
    }

    func refreshSurfaceLayout() {
        guard !isStopped, let surfaceView else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = surfaceView.bounds
        displayLayer.videoGravity = videoGravity
        displayLayer.setNeedsLayout()
        displayLayer.layoutIfNeeded()
        displayLayer.setNeedsDisplay()
        CATransaction.commit()
    }

    func recoverSurface() {
        guard !isStopped else { return }
        if let surfaceView {
            attachSurface(surfaceView)
        }
    }

    func setViewModel(_: PlayerStateViewModel?) {}

    func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        videoGravity = gravity
        displayLayer.videoGravity = gravity
        refreshSurfaceLayout()
    }

    func attachNativePlaybackController(_: AVPlayerViewController) {}

    func detachNativePlaybackController(_: AVPlayerViewController) {}

    func prepare(source: PlayerStreamSource) async throws {
        guard Self.canPrepare(source) else {
            throw PlayerEngineError.unsupportedMedia
        }
        guard !Self.candidatePairs(for: source).isEmpty else {
            throw PlayerEngineError.missingVideoURL
        }

        seekTask?.cancel()
        warmupTask?.cancel()
        firstFrameWatchdogTask?.cancel()
        firstFrameWatchdogTask = nil
        warmupTask = nil
        sessionGeneration &+= 1
        let prepareGeneration = sessionGeneration
        stopSessionOnly()
        configureAudioSession()
        applyTargetAudioState()
        self.source = source
        isStopped = false
        wantsPlayback = false
        didReportFirstFrame = false
        lastErrorMessage = nil
        currentTime = max(source.resumeTime, 0)
        onLoadingProgressChange?(0.16)
        publish(.preparing)
        recordCandidateSummary(source: source, reason: "prepare")
        scheduleWarmup(source: source, around: currentTime, reason: "prepare")

        let preparedSession = try await makeSession(
            source: source,
            startTime: CMTime(seconds: currentTime, preferredTimescale: 600),
            timeout: Self.prepareTimeout
        )
        guard !Task.isCancelled,
              !isStopped,
              prepareGeneration == sessionGeneration
        else {
            preparedSession.stop()
            throw CancellationError()
        }

        duration = preparedSession.duration.seconds.isFinite ? preparedSession.duration.seconds : source.durationHint
        session = preparedSession
        synchronizer.setRate(0, time: CMTime(seconds: currentTime, preferredTimescale: 600))
        onLoadingProgressChange?(0.78)
        publish(.ready)
    }

    func play() {
        guard !isStopped else { return }
        if session == nil, let source {
            let restartTime = pendingRestartTime ?? currentTime
            restartSessionAndPlay(source: source, time: restartTime)
            return
        }
        guard let session else { return }
        configureAudioSession()
        applyTargetAudioState()
        pendingRestartTime = nil
        wantsPlayback = true
        onPlaybackIntentChange?(true)
        session.start()
        scheduleFirstFrameWatchdog(generation: sessionGeneration)
        let time = safeSynchronizerTime()
        synchronizer.setRate(currentRate, time: time)
        publish(.playing)
    }

    func pause() {
        guard !isStopped else { return }
        wantsPlayback = false
        onPlaybackIntentChange?(false)
        cancelFirstFrameWatchdog()
        currentTime = safeSynchronizerTime().seconds
        synchronizer.setRate(0, time: safeSynchronizerTime())
        publish(.paused)
    }

    func pauseForNavigation() {
        guard !isStopped else { return }
        wantsPlayback = false
        onPlaybackIntentChange?(false)
        cancelFirstFrameWatchdog()
        currentTime = safeSynchronizerTime().seconds
        synchronizer.setRate(0, time: safeSynchronizerTime())
        publish(.paused)
    }

    func suspendForNavigation() {
        guard !isStopped else { return }
        wantsPlayback = false
        onPlaybackIntentChange?(false)
        cancelFirstFrameWatchdog()
        let snapshotTime = safeSynchronizerTime().seconds
        if snapshotTime.isFinite, snapshotTime >= 0 {
            currentTime = snapshotTime
        }
        pendingRestartTime = currentTime
        silenceAudioRendererImmediately()
        sessionGeneration &+= 1
        stopSessionOnly(removingDisplayedImage: false)
        publish(.paused)
    }

    func stop() {
        silenceAudioRendererImmediately()
        seekTask?.cancel()
        seekTask = nil
        warmupTask?.cancel()
        warmupTask = nil
        pendingSurfaceDetachTask?.cancel()
        pendingSurfaceDetachTask = nil
        cancelFirstFrameWatchdog()
        sessionGeneration &+= 1
        isStopped = true
        wantsPlayback = false
        onPlaybackIntentChange?(false)
        stopSessionOnly()
        source = nil
        duration = nil
        lastErrorMessage = nil
        currentTime = 0
        pendingRestartTime = nil
        didReportFirstFrame = false
        displayLayer.removeFromSuperlayer()
        deactivateAudioSessionIfPossible()
        publish(.idle)
    }

    func setPlaybackRate(_ rate: Double) {
        currentRate = max(Float(rate), 0.1)
        guard wantsPlayback else { return }
        synchronizer.setRate(currentRate, time: safeSynchronizerTime())
    }

    func setPreferredPeakBitRate(_: Double?) {}

    func setVolume(_ volume: Float) {
        targetVolume = min(max(volume, 0), 1)
        applyTargetAudioState()
    }

    func setMuted(_ isMuted: Bool) {
        targetMuted = isMuted
        applyTargetAudioState()
    }

    func setTemporaryAudioSuppressed(_ isSuppressed: Bool) {
        isTemporaryAudioSuppressed = isSuppressed
        if isSuppressed {
            audioRenderer.isMuted = true
            audioRenderer.volume = 0
        } else {
            applyTargetAudioState()
        }
    }

    func seek(toTime time: TimeInterval) -> TimeInterval? {
        seek(to: max(time, 0))
    }

    func seek(toProgress progress: Double, duration: TimeInterval?) -> TimeInterval? {
        let resolvedDuration = duration ?? self.duration ?? 0
        guard resolvedDuration > 0 else { return nil }
        return seek(to: min(max(progress, 0), 1) * resolvedDuration)
    }

    func seek(by interval: TimeInterval, from currentTime: TimeInterval, duration: TimeInterval?) -> TimeInterval? {
        let resolvedDuration = duration ?? self.duration ?? 0
        let target = resolvedDuration > 0
            ? min(max(currentTime + interval, 0), resolvedDuration)
            : max(currentTime + interval, 0)
        return seek(to: target)
    }

    func seekAfterUserScrub(toProgress progress: Double, duration: TimeInterval?) async -> TimeInterval? {
        let resolvedDuration = duration ?? self.duration ?? 0
        guard resolvedDuration > 0 else { return nil }
        return await seekAndWait(to: min(max(progress, 0), 1) * resolvedDuration)
    }

    func snapshot(durationHint: TimeInterval?) -> PlayerPlaybackSnapshot {
        let resolvedTime = safeSynchronizerTime().seconds
        if resolvedTime.isFinite, resolvedTime >= 0 {
            currentTime = resolvedTime
        }
        let resolvedDuration = duration ?? durationHint
        return PlayerPlaybackSnapshot(
            currentTime: currentTime.isFinite ? currentTime : nil,
            duration: resolvedDuration,
            isPlaying: wantsPlayback && synchronizer.rate > 0,
            isSeekable: (resolvedDuration ?? 0) > 0,
            bufferedRanges: bufferedRanges(around: currentTime, duration: resolvedDuration)
        )
    }

    func currentSurfaceSnapshotImage() -> UIImage? {
        surfaceView?.biliRenderedSnapshotImage()
    }

    func pictureInPictureContentSource() -> AVPictureInPictureController.ContentSource? {
        nil
    }

    func togglePictureInPicture() {}

    func invalidatePictureInPicturePlaybackState() {}

    private func seek(to time: TimeInterval) -> TimeInterval? {
        guard !isStopped, let source else { return nil }
        guard !Self.candidatePairs(for: source).isEmpty else { return nil }
        let clampedTime = min(max(time, 0), duration ?? time)
        let shouldResume = wantsPlayback
        wantsPlayback = shouldResume
        seekTask?.cancel()
        cancelFirstFrameWatchdog()
        sessionGeneration &+= 1
        let generation = sessionGeneration
        publish(.buffering)
        stopSessionOnly()
        currentTime = clampedTime
        pendingRestartTime = nil
        didReportFirstFrame = false
        synchronizer.setRate(0, time: CMTime(seconds: clampedTime, preferredTimescale: 600))
        scheduleWarmup(source: source, around: clampedTime, reason: "seek")

        seekTask = Task { @MainActor [weak self] in
            guard let self, !self.isStopped else { return }
            do {
                let preparedSession = try await self.makeSession(
                    source: source,
                    startTime: CMTime(seconds: clampedTime, preferredTimescale: 600),
                    timeout: Self.seekPrepareTimeout
                )
                guard !Task.isCancelled,
                      !self.isStopped,
                      generation == self.sessionGeneration
                else {
                    preparedSession.stop()
                    return
                }
                self.session = preparedSession
                self.synchronizer.setRate(0, time: CMTime(seconds: clampedTime, preferredTimescale: 600))
                if shouldResume {
                    self.play()
                } else {
                    self.publish(.paused)
                }
            } catch {
                guard !Task.isCancelled,
                      !self.isStopped,
                      generation == self.sessionGeneration
                else { return }
                self.lastErrorMessage = error.localizedDescription
                self.publish(.failed(error.localizedDescription))
            }
        }
        return clampedTime
    }

    private func seekAndWait(to time: TimeInterval) async -> TimeInterval? {
        guard !isStopped, let source else { return nil }
        guard !Self.candidatePairs(for: source).isEmpty else { return nil }
        let clampedTime = min(max(time, 0), duration ?? time)
        seekTask?.cancel()
        seekTask = nil
        cancelFirstFrameWatchdog()
        sessionGeneration &+= 1
        let generation = sessionGeneration
        publish(.buffering)
        stopSessionOnly()
        currentTime = clampedTime
        pendingRestartTime = nil
        didReportFirstFrame = false
        synchronizer.setRate(0, time: CMTime(seconds: clampedTime, preferredTimescale: 600))
        scheduleWarmup(source: source, around: clampedTime, reason: "scrub")

        do {
            let preparedSession = try await makeSession(
                source: source,
                startTime: CMTime(seconds: clampedTime, preferredTimescale: 600),
                timeout: Self.seekPrepareTimeout
            )
            guard !Task.isCancelled,
                  !isStopped,
                  generation == sessionGeneration
            else {
                preparedSession.stop()
                return nil
            }
            session = preparedSession
            synchronizer.setRate(0, time: CMTime(seconds: clampedTime, preferredTimescale: 600))
            publish(.paused)
            return clampedTime
        } catch {
            guard !Task.isCancelled,
                  !isStopped,
                  generation == sessionGeneration
            else { return nil }
            lastErrorMessage = error.localizedDescription
            publish(.failed(error.localizedDescription))
            return nil
        }
    }

    private func stopSessionOnly(removingDisplayedImage: Bool? = nil) {
        session?.stop()
        session = nil
        synchronizer.setRate(0, time: safeSynchronizerTime())
        videoRenderer.stopRequestingMediaData()
        audioRenderer.stopRequestingMediaData()
        videoRenderer.flush(removingDisplayedImage: removingDisplayedImage ?? isStopped)
        audioRenderer.flush()
    }

    private func restartSessionAndPlay(source: PlayerStreamSource, time: TimeInterval) {
        seekTask?.cancel()
        cancelFirstFrameWatchdog()
        sessionGeneration &+= 1
        let generation = sessionGeneration
        let clampedTime = min(max(time, 0), duration ?? time)
        currentTime = clampedTime
        pendingRestartTime = nil
        didReportFirstFrame = false
        publish(.buffering)

        seekTask = Task { @MainActor [weak self] in
            guard let self, !self.isStopped else { return }
            do {
                let preparedSession = try await self.makeSession(
                    source: source,
                    startTime: CMTime(seconds: clampedTime, preferredTimescale: 600),
                    timeout: Self.seekPrepareTimeout
                )
                guard !Task.isCancelled,
                      !self.isStopped,
                      generation == self.sessionGeneration
                else {
                    preparedSession.stop()
                    return
                }
                self.session = preparedSession
                self.synchronizer.setRate(0, time: CMTime(seconds: clampedTime, preferredTimescale: 600))
                self.play()
            } catch {
                guard !Task.isCancelled,
                      !self.isStopped,
                      generation == self.sessionGeneration
                else { return }
                self.lastErrorMessage = error.localizedDescription
                self.publish(.failed(error.localizedDescription))
            }
        }
    }

    private func safeSynchronizerTime() -> CMTime {
        let time = synchronizer.currentTime()
        guard time.isValid, time.seconds.isFinite, time.seconds >= 0 else {
            return CMTime(seconds: max(currentTime, 0), preferredTimescale: 600)
        }
        return time
    }

    private func bufferedRanges(around time: TimeInterval, duration: TimeInterval?) -> [PlayerBufferedRange] {
        guard let duration, duration > 0 else { return [] }
        return [
            PlayerBufferedRange(
                start: max(time - 0.25, 0),
                end: min(time + 2.5, duration)
            )
        ]
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
        }
    }

    private func deactivateAudioSessionIfPossible() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
        }
    }

    private func publish(_ state: PlayerEnginePlaybackState) {
        onPlaybackStateChange?(state)
    }

    private func scheduleFirstFrameWatchdog(generation: Int) {
        guard wantsPlayback, !didReportFirstFrame else { return }
        firstFrameWatchdogTask?.cancel()
        firstFrameWatchdogTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.firstFrameTimeoutNanoseconds)
            } catch {
                return
            }
            guard let self,
                  !Task.isCancelled,
                  !self.isStopped,
                  self.wantsPlayback,
                  !self.didReportFirstFrame,
                  generation == self.sessionGeneration
            else { return }
            let message = "Native DASH 首帧加载超时，正在切换播放器"
            self.firstFrameWatchdogTask = nil
            self.lastErrorMessage = message
            PlayerMetricsLog.logger.error(
                "nativeDASHFirstFrameTimedOut fallback=avPlayer id=\(self.source?.metricsID ?? "-", privacy: .public)"
            )
            self.stopSessionOnly(removingDisplayedImage: false)
            self.publish(.failed(message))
        }
    }

    private func cancelFirstFrameWatchdog() {
        firstFrameWatchdogTask?.cancel()
        firstFrameWatchdogTask = nil
    }

    private func applyTargetAudioState() {
        guard !isTemporaryAudioSuppressed else {
            audioRenderer.volume = 0
            audioRenderer.isMuted = true
            return
        }
        audioRenderer.volume = targetVolume
        audioRenderer.isMuted = targetMuted
    }

    private func silenceAudioRendererImmediately() {
        let time = safeSynchronizerTime()
        synchronizer.setRate(0, time: time)
        audioRenderer.volume = 0
        audioRenderer.isMuted = true
        audioRenderer.stopRequestingMediaData()
        audioRenderer.flush()
    }

    private func makeSession(
        source: PlayerStreamSource,
        startTime: CMTime,
        timeout: TimeInterval
    ) async throws -> NativeDASHSampleBufferSession {
        let allPairs = Self.candidatePairs(for: source)
        let availablePairs = allPairs.filter { !NativeDASHFailureCooldown.shared.isCoolingDown($0) }
        let pairs = availablePairs.isEmpty ? allPairs : availablePairs
        var lastError: Error = PlayerEngineError.missingVideoURL

        for (index, pair) in pairs.enumerated() {
            try Task.checkCancellation()
            let attemptStart = CACurrentMediaTime()
            recordCandidateAttempt(source: source, pair: pair, index: index, total: pairs.count, startTime: startTime)

            let preflight = await preflightCandidateIfPossible(
                source: source,
                pair: pair,
                startTime: startTime,
                timeout: min(max(timeout * 0.22, 0.45), 0.75)
            )
            switch preflight {
            case .passed, .skipped:
                break
            case .failed(let error):
                lastError = error
                recordCandidateFailure(
                    source: source,
                    pair: pair,
                    index: index,
                    total: pairs.count,
                    elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: attemptStart),
                    error: error
                )
                NativeDASHFailureCooldown.shared.recordFailure(pair)
                continue
            }

            do {
                let callbacks = makeSessionCallbacks(generation: sessionGeneration)
                let videoURLs = Self.resourceSourceURLs(
                    primary: pair.videoURL,
                    selected: source.videoURL,
                    stream: source.videoStream,
                    cdnPreference: source.cdnPreference
                )
                let audioURLs = Self.resourceSourceURLs(
                    primary: pair.audioURL,
                    selected: source.audioURL,
                    stream: source.audioStream,
                    cdnPreference: source.cdnPreference
                )
                let task = Task { @MainActor [videoRenderer, audioRenderer, synchronizer] in
                    try await NativeDASHSampleBufferSession.make(
                        videoURLs: videoURLs,
                        audioURLs: audioURLs,
                        videoStream: source.videoStream,
                        audioStream: source.audioStream,
                        headers: source.httpHeaders,
                        startTime: startTime,
                        videoRenderer: videoRenderer,
                        audioRenderer: audioRenderer,
                        synchronizer: synchronizer,
                        callbacks: callbacks,
                        metricsID: source.metricsID,
                        title: source.title
                    )
                }
                defer {
                    if task.isCancelled {
                        stopRenderersBeforeNextCandidate()
                    }
                }

                let session = try await NativeDASHTaskWaiter.value(
                    of: task,
                    timeoutNanoseconds: UInt64(max(timeout, 0.1) * 1_000_000_000)
                )
                PlayerMetricsLog.logger.info(
                    "nativeDASHSessionReady candidate=\(index + 1, privacy: .public)/\(pairs.count, privacy: .public) videoHost=\(pair.videoURL.host ?? "-", privacy: .public) audioHost=\(pair.audioURL.host ?? "-", privacy: .public)"
                )
                NativeDASHFailureCooldown.shared.recordSuccess(pair)
                recordCandidateSuccess(
                    source: source,
                    pair: pair,
                    index: index,
                    total: pairs.count,
                    elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: attemptStart),
                    duration: session.duration.seconds
                )
                return session
            } catch let error as NativeDASHTaskWaiter.Timeout {
                lastError = error
                PlayerMetricsLog.logger.error(
                    "nativeDASHSessionTimedOut candidate=\(index + 1, privacy: .public)/\(pairs.count, privacy: .public) videoHost=\(pair.videoURL.host ?? "-", privacy: .public) audioHost=\(pair.audioURL.host ?? "-", privacy: .public)"
                )
                recordCandidateFailure(
                    source: source,
                    pair: pair,
                    index: index,
                    total: pairs.count,
                    elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: attemptStart),
                    error: error
                )
                NativeDASHFailureCooldown.shared.recordFailure(pair)
                stopRenderersBeforeNextCandidate()
            } catch let error as CancellationError {
                throw error
            } catch {
                lastError = error
                PlayerMetricsLog.logger.error(
                    "nativeDASHSessionFailed candidate=\(index + 1, privacy: .public)/\(pairs.count, privacy: .public) videoHost=\(pair.videoURL.host ?? "-", privacy: .public) audioHost=\(pair.audioURL.host ?? "-", privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                recordCandidateFailure(
                    source: source,
                    pair: pair,
                    index: index,
                    total: pairs.count,
                    elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: attemptStart),
                    error: error
                )
                NativeDASHFailureCooldown.shared.recordFailure(pair)
                stopRenderersBeforeNextCandidate()
            }
        }

        throw lastError
    }

    private func preflightCandidateIfPossible(
        source: PlayerStreamSource,
        pair: NativeDASHURLPair,
        startTime: CMTime,
        timeout: TimeInterval
    ) async -> NativeDASHPreflightResult {
        let targetSeconds = startTime.seconds
        guard targetSeconds.isFinite, targetSeconds >= 0.35 else {
            recordCandidatePreflight(
                source: source,
                pair: pair,
                state: "skip-startup",
                elapsedMilliseconds: 0,
                startTime: startTime
            )
            return .skipped
        }
        guard let tracks = Self.warmupTracks(for: source, pair: pair) else {
            recordCandidatePreflight(
                source: source,
                pair: pair,
                state: "skip",
                elapsedMilliseconds: 0,
                startTime: startTime
            )
            return .skipped
        }

        let preflightStart = CACurrentMediaTime()
        let task = Task<Bool, Error>.detached(priority: .userInitiated) {
            await LocalHLSBridge.warmup(
                videoTrack: tracks.video,
                audioTrack: tracks.audio,
                headers: source.httpHeaders,
                around: max(targetSeconds, 0)
            )
        }

        do {
            let didWarm = try await NativeDASHTaskWaiter.value(
                of: task,
                timeoutNanoseconds: UInt64(max(timeout, 0.1) * 1_000_000_000)
            )
            recordCandidatePreflight(
                source: source,
                pair: pair,
                state: didWarm ? "pass" : "fail",
                elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: preflightStart),
                startTime: startTime
            )
            return didWarm ? .passed : .failed(NativeDASHPreflightError.failed)
        } catch let error as NativeDASHTaskWaiter.Timeout {
            recordCandidatePreflight(
                source: source,
                pair: pair,
                state: "timeout",
                elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: preflightStart),
                startTime: startTime
            )
            return .failed(error)
        } catch {
            recordCandidatePreflight(
                source: source,
                pair: pair,
                state: "fail",
                elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: preflightStart),
                startTime: startTime
            )
            return .failed(error)
        }
    }

    private func makeSessionCallbacks(generation: Int) -> NativeDASHSampleBufferSession.Callbacks {
        NativeDASHSampleBufferSession.Callbacks(
            onVideoSample: { [weak self] time in
                guard let self,
                      !self.isStopped,
                      generation == self.sessionGeneration
                else { return }
                if !self.didReportFirstFrame {
                    self.didReportFirstFrame = true
                    self.cancelFirstFrameWatchdog()
                    self.recordFirstVideoSample(time)
                    self.onFirstFrame?(time)
                }
                self.currentTime = time
            },
            onCompleted: { [weak self] in
                guard let self,
                      !self.isStopped,
                      generation == self.sessionGeneration
                else { return }
                self.cancelFirstFrameWatchdog()
                self.wantsPlayback = false
                self.publish(.ended)
            },
            onFailed: { [weak self] message in
                guard let self,
                      !self.isStopped,
                      generation == self.sessionGeneration
                else { return }
                self.cancelFirstFrameWatchdog()
                self.lastErrorMessage = message
                PlayerMetricsLog.record(
                    .manifestStage,
                    metricsID: self.source?.metricsID ?? "-",
                    title: self.source?.title,
                    message: "nativeDASHFailed \(message)"
                )
                self.publish(.failed(message))
            }
        )
    }

    private func stopRenderersBeforeNextCandidate() {
        videoRenderer.stopRequestingMediaData()
        audioRenderer.stopRequestingMediaData()
        videoRenderer.flush(removingDisplayedImage: false)
        audioRenderer.flush()
    }

    private func recordCandidateSummary(source: PlayerStreamSource, reason: String) {
        let pairs = Self.candidatePairs(for: source)
        PlayerMetricsLog.record(
            .manifestStage,
            metricsID: source.metricsID,
            title: source.title,
            message: "nativeDASHCandidates reason=\(reason) count=\(pairs.count) video=\(Self.hostSummary(pairs.map(\.videoURL))) audio=\(Self.hostSummary(pairs.map(\.audioURL))) q=\(source.videoStream?.id ?? -1)"
        )
    }

    private func recordCandidateAttempt(
        source: PlayerStreamSource,
        pair: NativeDASHURLPair,
        index: Int,
        total: Int,
        startTime: CMTime
    ) {
        let seconds = startTime.seconds
        let target = seconds.isFinite ? max(seconds, 0) : 0
        PlayerMetricsLog.record(
            .manifestStage,
            metricsID: source.metricsID,
            title: source.title,
            message: "nativeDASHTry \(index + 1)/\(total) target=\(String(format: "%.2fs", target)) video=\(pair.videoHost) audio=\(pair.audioHost)"
        )
    }

    private func recordCandidateSuccess(
        source: PlayerStreamSource,
        pair: NativeDASHURLPair,
        index: Int,
        total: Int,
        elapsedMilliseconds: Double,
        duration: TimeInterval
    ) {
        recordURLPreferenceResult(
            pair: pair,
            elapsedMilliseconds: elapsedMilliseconds,
            succeeded: true
        )
        let durationText = duration.isFinite ? String(format: "%.1fs", duration) : "-"
        PlayerMetricsLog.record(
            .manifestStage,
            metricsID: source.metricsID,
            title: source.title,
            message: "nativeDASHReady \(index + 1)/\(total) elapsed=\(String(format: "%.0fms", elapsedMilliseconds)) duration=\(durationText) video=\(pair.videoHost) audio=\(pair.audioHost)"
        )
    }

    private func recordCandidateFailure(
        source: PlayerStreamSource,
        pair: NativeDASHURLPair,
        index: Int,
        total: Int,
        elapsedMilliseconds: Double,
        error: Error
    ) {
        recordURLPreferenceResult(
            pair: pair,
            elapsedMilliseconds: elapsedMilliseconds,
            succeeded: false
        )
        PlayerMetricsLog.record(
            .manifestStage,
            metricsID: source.metricsID,
            title: source.title,
            message: "nativeDASHFail \(index + 1)/\(total) elapsed=\(String(format: "%.0fms", elapsedMilliseconds)) video=\(pair.videoHost) audio=\(pair.audioHost) error=\(error.localizedDescription)"
        )
    }

    private func recordCandidatePreflight(
        source: PlayerStreamSource,
        pair: NativeDASHURLPair,
        state: String,
        elapsedMilliseconds: Double,
        startTime: CMTime
    ) {
        let seconds = startTime.seconds
        let target = seconds.isFinite ? max(seconds, 0) : 0
        PlayerMetricsLog.record(
            .mediaCache,
            metricsID: source.metricsID,
            title: source.title,
            message: "nativeDASHPreflight state=\(state) elapsed=\(String(format: "%.0fms", elapsedMilliseconds)) target=\(String(format: "%.2fs", target)) video=\(pair.videoHost) audio=\(pair.audioHost)"
        )
    }

    private func recordURLPreferenceResult(
        pair: NativeDASHURLPair,
        elapsedMilliseconds: Double,
        succeeded: Bool
    ) {
        let boundedElapsed = min(max(elapsedMilliseconds, 10), 8_000)
        PlaybackURLPreferenceStore.shared.record(
            url: pair.videoURL,
            elapsedMilliseconds: boundedElapsed,
            bytes: 0,
            succeeded: succeeded
        )
        guard pair.audioHost.lowercased() != pair.videoHost.lowercased() else { return }
        PlaybackURLPreferenceStore.shared.record(
            url: pair.audioURL,
            elapsedMilliseconds: boundedElapsed,
            bytes: 0,
            succeeded: succeeded
        )
    }

    private func recordFirstVideoSample(_ time: TimeInterval) {
        guard let source else { return }
        PlayerMetricsLog.record(
            .manifestStage,
            metricsID: source.metricsID,
            title: source.title,
            message: "nativeDASHFirstSample t=\(String(format: "%.2fs", time)) video=\(session?.videoHost ?? "-") audio=\(session?.audioHost ?? "-")"
        )
    }

    private func scheduleWarmup(source: PlayerStreamSource, around playbackTime: TimeInterval, reason: String) {
        guard let tracks = Self.warmupTracks(for: source) else { return }
        warmupTask?.cancel()
        let metricsID = source.metricsID
        let title = source.title
        let headers = source.httpHeaders
        let videoHost = tracks.video.url.host ?? "-"
        let audioHost = tracks.audio?.url.host ?? "-"
        let quality = source.videoStream?.id ?? -1
        warmupTask = Task.detached(priority: .utility) {
            let start = CACurrentMediaTime()
            let didWarm = await LocalHLSBridge.warmup(
                videoTrack: tracks.video,
                audioTrack: tracks.audio,
                headers: headers,
                around: playbackTime
            )
            guard !Task.isCancelled else { return }
            await PlayerMetricsLog.record(
                .mediaCache,
                metricsID: metricsID,
                title: title,
                message: "nativeDASHWarmup reason=\(reason) warmed=\(didWarm) target=\(String(format: "%.2fs", playbackTime)) elapsed=\(String(format: "%.0fms", PlayerMetricsLog.elapsedMilliseconds(since: start))) video=\(videoHost) audio=\(audioHost) q=\(quality)"
            )
        }
    }

    private static func warmupTracks(for source: PlayerStreamSource) -> (video: HLSBridgeTrack, audio: HLSBridgeTrack?)? {
        guard let videoURL = candidateURLs(
            selected: source.videoURL,
            stream: source.videoStream,
            cdnPreference: source.cdnPreference
        ).first else { return nil }

        let audioURL = candidateURLs(
            selected: source.audioURL,
            stream: source.audioStream,
            cdnPreference: source.cdnPreference
        ).first

        let videoTrack = HLSBridgeTrack(
            url: videoURL,
            fallbackURLs: source.videoStream?.backupPlayURLs(cdnPreference: source.cdnPreference) ?? [],
            stream: source.videoStream,
            mediaType: .video,
            dynamicRange: source.dynamicRange
        )
        let audioTrack = audioURL.map {
            HLSBridgeTrack(
                url: $0,
                fallbackURLs: source.audioStream?.backupPlayURLs(cdnPreference: source.cdnPreference) ?? [],
                stream: source.audioStream,
                mediaType: .audio
            )
        }
        return (videoTrack, audioTrack)
    }

    private static func warmupTracks(
        for source: PlayerStreamSource,
        pair: NativeDASHURLPair
    ) -> (video: HLSBridgeTrack, audio: HLSBridgeTrack?)? {
        guard source.videoStream?.segmentBase?.initializationByteRange != nil,
              source.videoStream?.segmentBase?.indexByteRange != nil
        else { return nil }

        let videoTrack = HLSBridgeTrack(
            url: pair.videoURL,
            fallbackURLs: [],
            stream: source.videoStream,
            mediaType: .video,
            dynamicRange: source.dynamicRange
        )
        let audioTrack = HLSBridgeTrack(
            url: pair.audioURL,
            fallbackURLs: [],
            stream: source.audioStream,
            mediaType: .audio
        )
        return (videoTrack, audioTrack)
    }

    private static func hostSummary(_ urls: [URL]) -> String {
        let hosts = urls.map { $0.host ?? "-" }
        var seen = Set<String>()
        let uniqueHosts = hosts.filter { seen.insert($0).inserted }
        return uniqueHosts.prefix(3).joined(separator: ",")
    }

    private static func candidatePairs(for source: PlayerStreamSource) -> [NativeDASHURLPair] {
        let videoURLs = candidateURLs(
            selected: source.videoURL,
            stream: source.videoStream,
            cdnPreference: source.cdnPreference
        )
        let audioURLs = candidateURLs(
            selected: source.audioURL,
            stream: source.audioStream,
            cdnPreference: source.cdnPreference
        )
        guard !videoURLs.isEmpty, !audioURLs.isEmpty else { return [] }

        var pairs: [NativeDASHURLPair] = []
        var seen = Set<String>()

        func append(_ videoURL: URL, _ audioURL: URL) {
            let key = "\(videoURL.absoluteString)\n\(audioURL.absoluteString)"
            guard seen.insert(key).inserted else { return }
            pairs.append(NativeDASHURLPair(videoURL: videoURL, audioURL: audioURL))
        }

        for index in 0..<max(videoURLs.count, audioURLs.count) {
            append(
                videoURLs[min(index, videoURLs.count - 1)],
                audioURLs[min(index, audioURLs.count - 1)]
            )
        }

        for videoURL in videoURLs {
            for audioURL in audioURLs {
                append(videoURL, audioURL)
                if pairs.count >= candidatePairLimit {
                    return pairs
                }
            }
        }

        return Array(pairs.prefix(candidatePairLimit))
    }

    private static func resourceSourceURLs(
        primary: URL,
        selected: URL?,
        stream: DASHStream?,
        cdnPreference: PlaybackCDNPreference
    ) -> [URL] {
        var urls = [primary]
        urls += candidateURLs(selected: selected, stream: stream, cdnPreference: cdnPreference)
        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    private static func candidateURLs(
        selected: URL?,
        stream: DASHStream?,
        cdnPreference: PlaybackCDNPreference
    ) -> [URL] {
        var urls: [URL] = []
        if let selected {
            urls.append(selected)
        }
        if let stream {
            let preferred = cdnPreference.preferredURLs(
                primary: URL(string: stream.baseURL),
                backups: stream.backupPlayURLs
            )
            if let primary = preferred.primary {
                urls.append(primary)
            }
            urls.append(contentsOf: preferred.backups)
        }

        var seen = Set<String>()
        return urls
            .filter { seen.insert($0.absoluteString).inserted }
            .prefix(candidateLimit)
            .map { $0 }
    }

    private func observeVideoRendererFailures() {
        decodeFailureObserver = NotificationCenter.default.addObserver(
            forName: AVSampleBufferVideoRenderer.didFailToDecodeNotification,
            object: videoRenderer,
            queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVSampleBufferVideoRenderer.didFailToDecodeNotificationErrorKey] as? NSError
            let message = error?.localizedDescription ?? "视频解码失败"
            let generation = self.map { engine in
                MainActor.assumeIsolated { engine.sessionGeneration }
            }
            Task { @MainActor [weak self] in
                guard let self,
                      !self.isStopped,
                      generation == self.sessionGeneration
                else { return }
                self.lastErrorMessage = message
                PlayerMetricsLog.record(
                    .manifestStage,
                    metricsID: self.source?.metricsID ?? "-",
                    title: self.source?.title,
                    message: "nativeDASHDecodeFailed \(message)"
                )
                self.publish(.failed(message))
            }
        }
        requiresFlushObserver = NotificationCenter.default.addObserver(
            forName: AVSampleBufferVideoRenderer.requiresFlushToResumeDecodingDidChangeNotification,
            object: videoRenderer,
            queue: .main
        ) { [weak self] _ in
            let generation = self.map { engine in
                MainActor.assumeIsolated { engine.sessionGeneration }
            }
            Task { @MainActor [weak self] in
                guard let self,
                      !self.isStopped,
                      generation == self.sessionGeneration,
                      self.videoRenderer.requiresFlushToResumeDecoding
                else { return }
                self.lastErrorMessage = "视频解码器需要重置"
                PlayerMetricsLog.record(
                    .manifestStage,
                    metricsID: self.source?.metricsID ?? "-",
                    title: self.source?.title,
                    message: "nativeDASHRendererFlushRequired"
                )
                self.publish(.failed(self.lastErrorMessage))
            }
        }
    }
}

private struct NativeDASHURLPair: Sendable {
    let videoURL: URL
    let audioURL: URL

    var videoHost: String {
        videoURL.host ?? "-"
    }

    var audioHost: String {
        audioURL.host ?? "-"
    }
}

private enum NativeDASHPreflightResult {
    case passed
    case skipped
    case failed(Error)
}

private enum NativeDASHPreflightError: LocalizedError {
    case failed

    var errorDescription: String? {
        "Native DASH 线路预检失败"
    }
}

nonisolated private final class NativeDASHFailureCooldown: @unchecked Sendable {
    static let shared = NativeDASHFailureCooldown()

    private let lock = NSLock()
    private let cooldown: TimeInterval = 10
    private var failures: [String: Date] = [:]

    func isCoolingDown(_ pair: NativeDASHURLPair, now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        trimExpiredLocked(now: now)
        guard let date = failures[key(for: pair)] else { return false }
        return now.timeIntervalSince(date) < cooldown
    }

    func recordFailure(_ pair: NativeDASHURLPair, now: Date = Date()) {
        lock.lock()
        failures[key(for: pair)] = now
        trimExpiredLocked(now: now)
        lock.unlock()
    }

    func recordSuccess(_ pair: NativeDASHURLPair) {
        lock.lock()
        failures.removeValue(forKey: key(for: pair))
        lock.unlock()
    }

    private func trimExpiredLocked(now: Date) {
        failures = failures.filter { now.timeIntervalSince($0.value) < cooldown }
    }

    private func key(for pair: NativeDASHURLPair) -> String {
        "\(pair.videoURL.absoluteString)\n\(pair.audioURL.absoluteString)"
    }
}

private actor NativeDASHAssetProbeCache {
    static let shared = NativeDASHAssetProbeCache()

    func probe(
        urls: [URL],
        headers: [String: String],
        mediaType: AVMediaType,
        bootstrapRanges: [HTTPByteRange],
        metricsID: String,
        title: String
    ) async throws -> NativeDASHAssetProbe {
        guard let url = urls.first else {
            throw PlayerEngineError.unsupportedMedia
        }
        let start = CACurrentMediaTime()
        do {
            let probe = try await Self.loadProbe(
                urls: urls,
                headers: headers,
                mediaType: mediaType,
                bootstrapRanges: bootstrapRanges
            )
            await recordProbe(
                metricsID: metricsID,
                title: title,
                mediaType: mediaType,
                url: url,
                state: "fresh",
                elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: start)
            )
            return probe
        } catch {
            await recordProbe(metricsID: metricsID, title: title, mediaType: mediaType, url: url, state: "fail", elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: start))
            throw error
        }
    }

    private static func loadProbe(
        urls: [URL],
        headers: [String: String],
        mediaType: AVMediaType,
        bootstrapRanges: [HTTPByteRange]
    ) async throws -> NativeDASHAssetProbe {
        let cancellationBox = NativeDASHAssetLoadingCancellationBox()
        return try await withTaskCancellationHandler {
            let loader = NativeDASHResourceLoader(sourceURLs: urls, headers: headers, mediaType: mediaType)
            loader.startBootstrapWarmup(bootstrapRanges)
            let asset = AVURLAsset(url: loader.assetURL)
            cancellationBox.set(asset: asset, loader: loader)
            asset.resourceLoader.setDelegate(loader, queue: loader.queue)
            do {
                async let tracks = asset.loadTracks(withMediaType: mediaType)
                async let duration = asset.load(.duration)
                guard let track = try await tracks.first else {
                    throw PlayerEngineError.unsupportedMedia
                }
                return try await NativeDASHAssetProbe(
                    asset: asset,
                    loader: loader,
                    track: track,
                    duration: duration
                )
            } catch {
                asset.cancelLoading()
                loader.cancelActiveRequests()
                throw error
            }
        } onCancel: {
            cancellationBox.cancel()
        }
    }

    private func recordProbe(
        metricsID: String,
        title: String,
        mediaType: AVMediaType,
        url: URL,
        state: String,
        elapsedMilliseconds: Double
    ) async {
        await PlayerMetricsLog.record(
            .mediaCache,
            metricsID: metricsID,
            title: title,
            message: "nativeDASHAssetProbe media=\(mediaType.rawValue) state=\(state) elapsed=\(String(format: "%.0fms", elapsedMilliseconds)) host=\(url.host ?? "-")"
        )
    }
}

nonisolated private final class NativeDASHAssetLoadingCancellationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var asset: AVURLAsset?
    private var loader: NativeDASHResourceLoader?

    func set(asset: AVURLAsset, loader: NativeDASHResourceLoader) {
        lock.lock()
        self.asset = asset
        self.loader = loader
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        let asset = asset
        let loader = loader
        self.asset = nil
        self.loader = nil
        lock.unlock()
        asset?.cancelLoading()
        loader?.cancelActiveRequests()
    }
}

nonisolated private struct NativeDASHAssetProbe: @unchecked Sendable {
    let asset: AVURLAsset
    let loader: NativeDASHResourceLoader
    let track: AVAssetTrack
    let duration: CMTime
}

nonisolated private final class NativeDASHContentLengthCache: @unchecked Sendable {
    static let shared = NativeDASHContentLengthCache()

    private let lock = NSLock()
    private let ttl: TimeInterval = 10 * 60
    private let maxEntryCount = 64
    private var entries: [String: Entry] = [:]

    private struct Entry {
        let length: Int64
        let date: Date
    }

    func contentLength(for url: URL, now: Date = Date()) -> Int64? {
        lock.lock()
        defer { lock.unlock() }
        trimExpiredLocked(now: now)
        guard let entry = entries[url.absoluteString] else { return nil }
        return entry.length
    }

    func set(_ length: Int64, for url: URL, now: Date = Date()) {
        guard length > 0 else { return }
        lock.lock()
        entries[url.absoluteString] = Entry(length: length, date: now)
        trimExpiredLocked(now: now)
        trimIfNeededLocked()
        lock.unlock()
    }

    private func trimExpiredLocked(now: Date) {
        entries = entries.filter { now.timeIntervalSince($0.value.date) < ttl }
    }

    private func trimIfNeededLocked() {
        guard entries.count > maxEntryCount else { return }
        let keysToRemove = entries
            .sorted { $0.value.date < $1.value.date }
            .prefix(entries.count - maxEntryCount)
            .map(\.key)
        for key in keysToRemove {
            entries[key] = nil
        }
    }
}

nonisolated private final class NativeDASHResourceLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    let assetURL: URL
    let queue: DispatchQueue

    private let sourceURLs: [URL]
    private let headers: [String: String]
    private let mediaType: AVMediaType
    private let lock = NSLock()
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var activeRequests: Set<ObjectIdentifier> = []
    private var bootstrapWarmupTask: Task<Void, Never>?
    private var knownContentLength: Int64?

    private struct RemoteRangePayload: Sendable {
        let data: Data
        let servedRange: HTTPByteRange
        let contentLength: Int64?
    }

    init(sourceURLs: [URL], headers: [String: String], mediaType: AVMediaType) {
        self.sourceURLs = sourceURLs
        self.headers = headers
        self.mediaType = mediaType
        queue = DispatchQueue(label: "cc.bili.native-dash.resource-loader.\(mediaType.rawValue)")
        let identifier = UUID().uuidString
        let extensionName = mediaType == .audio ? "m4a" : "mp4"
        assetURL = URL(string: "bili-native-dash://asset/\(identifier)/media.\(extensionName)")!
        super.init()
    }

    deinit {
        cancelAll()
        cancelBootstrapWarmup()
    }

    func startBootstrapWarmup(_ ranges: [HTTPByteRange]) {
        let warmRanges = ranges
            .filter { $0.length > 0 }
            .prefix(mediaType == .audio ? 3 : 4)
        guard !warmRanges.isEmpty else { return }
        let task = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.warmBootstrapRanges(Array(warmRanges))
        }
        lock.lock()
        let previousTask = bootstrapWarmupTask
        bootstrapWarmupTask = task
        lock.unlock()
        previousTask?.cancel()
    }

    func cancelActiveRequests() {
        cancelAll()
        lock.lock()
        let task = bootstrapWarmupTask
        bootstrapWarmupTask = nil
        lock.unlock()
        task?.cancel()
    }

    func cancelBootstrapWarmup() {
        lock.lock()
        let task = bootstrapWarmupTask
        bootstrapWarmupTask = nil
        lock.unlock()
        task?.cancel()
    }

    private func warmBootstrapRanges(_ ranges: [HTTPByteRange]) async {
        guard !ranges.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for range in ranges {
                group.addTask(priority: .utility) { [weak self] in
                    guard let self else { return }
                    _ = try? await self.fetch(range)
                }
            }
        }
    }

    nonisolated static func bootstrapRanges(
        for stream: DASHStream?,
        mediaType: AVMediaType
    ) -> [HTTPByteRange] {
        var ranges: [HTTPByteRange] = []
        if let initialization = stream?.segmentBase?.initializationByteRange {
            ranges.append(initialization)
        }
        if let indexRange = stream?.segmentBase?.indexByteRange {
            ranges.append(indexRange)
        }
        let fallbackLength: Int64 = mediaType == .audio ? 512 * 1024 : 2 * 1024 * 1024
        ranges.append(HTTPByteRange(start: 0, endInclusive: fallbackLength - 1))
        var seen = Set<HTTPByteRange>()
        return ranges.filter { seen.insert($0).inserted }
    }

    func resourceLoader(
        _: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        let identifier = ObjectIdentifier(loadingRequest)
        storeActiveRequest(identifier)
        let task = Task.detached(priority: .userInitiated) { [weak self, weak loadingRequest] in
            guard let self, let loadingRequest else { return }
            guard self.isRequestActive(identifier) else { return }
            await self.respond(to: loadingRequest)
            self.removeTask(for: identifier)
            self.removeActiveRequest(identifier)
        }
        if store(task, for: identifier) == false {
            task.cancel()
        }
        return true
    }

    func resourceLoader(
        _: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        let identifier = ObjectIdentifier(loadingRequest)
        lock.lock()
        let task = tasks.removeValue(forKey: identifier)
        activeRequests.remove(identifier)
        lock.unlock()
        task?.cancel()
    }

    private func respond(to loadingRequest: AVAssetResourceLoadingRequest) async {
        let identifier = ObjectIdentifier(loadingRequest)
        do {
            let requestedRange = requestedRange(for: loadingRequest)
            if requestedRange.length > directFetchThreshold {
                try await stream(requestedRange, to: loadingRequest)
                guard isRequestActive(identifier) else { return }
                loadingRequest.finishLoading()
                return
            }
            let (data, sourceURL, contentLength) = try await fetch(requestedRange)
            guard isRequestActive(identifier) else { return }
            if let contentLength {
                setKnownContentLength(contentLength)
            }
            await fillContentInformation(
                loadingRequest.contentInformationRequest,
                contentLength: contentLength ?? currentKnownContentLength(),
                sourceURL: sourceURL
            )
            loadingRequest.dataRequest?.respond(with: data)
            loadingRequest.finishLoading()
        } catch is CancellationError {
            guard isRequestActive(identifier) else { return }
            loadingRequest.finishLoading(with: NSError(
                domain: "cc.bili.native-dash.resource-loader",
                code: NSURLErrorCancelled,
                userInfo: [NSLocalizedDescriptionKey: "Native DASH request cancelled"]
            ))
        } catch {
            guard isRequestActive(identifier) else { return }
            loadingRequest.finishLoading(with: error)
        }
    }

    private func stream(
        _ range: HTTPByteRange,
        to loadingRequest: AVAssetResourceLoadingRequest
    ) async throws {
        var offset = range.start
        var didFillContentInformation = false
        var lastSourceURL = sourceURLs.first ?? assetURL

        while offset <= range.endInclusive {
            try Task.checkCancellation()
            let chunkRange = HTTPByteRange(
                start: offset,
                endInclusive: min(offset + streamingChunkLength - 1, range.endInclusive)
            )
            let (data, sourceURL, contentLength) = try await fetch(chunkRange)
            lastSourceURL = sourceURL
            if let contentLength {
                setKnownContentLength(contentLength)
            }
            if !didFillContentInformation {
                await fillContentInformation(
                    loadingRequest.contentInformationRequest,
                    contentLength: contentLength ?? currentKnownContentLength(),
                    sourceURL: sourceURL
                )
                didFillContentInformation = true
            }
            loadingRequest.dataRequest?.respond(with: data)
            offset = chunkRange.endInclusive + 1
        }

        if !didFillContentInformation {
            await fillContentInformation(
                loadingRequest.contentInformationRequest,
                contentLength: currentKnownContentLength(),
                sourceURL: lastSourceURL
            )
        }
    }

    private func fetch(_ range: HTTPByteRange) async throws -> (Data, URL, Int64?) {
        let urls = PlaybackURLPreferenceStore.shared
            .orderedURLs(sourceURLs.removingNativeDASHDuplicates())
        guard !urls.isEmpty else { throw PlayerEngineError.unsupportedMedia }
        if shouldUseFastFallback(for: range, urlCount: urls.count) {
            return try await fetchFastFallback(range, from: urls)
        }
        return try await fetchSequential(range, from: urls)
    }

    private func fetchSequential(_ range: HTTPByteRange, from urls: [URL]) async throws -> (Data, URL, Int64?) {
        var lastError: Error?
        for (index, url) in urls.enumerated() {
            try Task.checkCancellation()
            let start = CACurrentMediaTime()
            do {
                let (data, contentLength) = try await fetch(range, from: url)
                recordURLResult(
                    url: url,
                    elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: start),
                    bytes: Int64(data.count),
                    succeeded: true
                )
                if index > 0, let primaryURL = urls.first {
                    await VideoRangeCache.shared.store(data, url: primaryURL, range: range)
                }
                return (data, url, contentLength)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled {
                    throw CancellationError()
                }
                lastError = error
                recordURLResult(
                    url: url,
                    elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: start),
                    bytes: 0,
                    succeeded: false
                )
                PlayerMetricsLog.logger.info(
                    "nativeDASHResourceFallback media=\(self.mediaType.rawValue, privacy: .public) index=\(index, privacy: .public) range=\(range.start, privacy: .public)-\(range.endInclusive, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
            }
        }
        throw lastError ?? PlayerEngineError.unsupportedMedia
    }

    private func fetchFastFallback(_ range: HTTPByteRange, from urls: [URL]) async throws -> (Data, URL, Int64?) {
        enum FetchResult {
            case success(index: Int, url: URL, data: Data, contentLength: Int64?, elapsedMilliseconds: Double)
            case failure(index: Int, url: URL, error: Error, elapsedMilliseconds: Double)
        }

        let result: FetchResult = await withTaskGroup(of: FetchResult.self, returning: FetchResult.self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask(priority: .userInitiated) { [self] in
                    let start = CACurrentMediaTime()
                    do {
                        if index > 0 {
                            let delay = UInt64(55_000_000 + max(index - 1, 0) * 45_000_000)
                            try await Task.sleep(nanoseconds: delay)
                        }
                        let (data, contentLength) = try await fetch(range, from: url)
                        return FetchResult.success(
                            index: index,
                            url: url,
                            data: data,
                            contentLength: contentLength,
                            elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: start)
                        )
                    } catch {
                        return FetchResult.failure(
                            index: index,
                            url: url,
                            error: error,
                            elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: start)
                        )
                    }
                }
            }

            var lastError: Error?
            for await result in group {
                switch result {
                case let .success(index, url, data, contentLength, elapsedMilliseconds):
                    recordURLResult(
                        url: url,
                        elapsedMilliseconds: elapsedMilliseconds,
                        bytes: Int64(data.count),
                        succeeded: true
                    )
                    if index > 0, let primaryURL = urls.first {
                        await VideoRangeCache.shared.store(data, url: primaryURL, range: range)
                        PlayerMetricsLog.logger.info(
                            "nativeDASHFastFallbackSuccess media=\(self.mediaType.rawValue, privacy: .public) index=\(index, privacy: .public) range=\(range.start, privacy: .public)-\(range.endInclusive, privacy: .public)"
                        )
                    }
                    group.cancelAll()
                    return FetchResult.success(index: index, url: url, data: data, contentLength: contentLength, elapsedMilliseconds: elapsedMilliseconds)
                case let .failure(index, url, error, elapsedMilliseconds):
                    if Task.isCancelled {
                        lastError = CancellationError()
                    } else {
                        lastError = error
                        recordURLResult(
                            url: url,
                            elapsedMilliseconds: elapsedMilliseconds,
                            bytes: 0,
                            succeeded: false
                        )
                        PlayerMetricsLog.logger.info(
                            "nativeDASHFastFallbackFailed media=\(self.mediaType.rawValue, privacy: .public) index=\(index, privacy: .public) range=\(range.start, privacy: .public)-\(range.endInclusive, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                        )
                    }
                }
            }
            return FetchResult.failure(index: 0, url: urls.first ?? assetURL, error: lastError ?? PlayerEngineError.unsupportedMedia, elapsedMilliseconds: 0)
        }

        switch result {
        case let .success(_, url, data, contentLength, _):
            return (data, url, contentLength)
        case let .failure(_, _, error, _):
            if error is CancellationError || Task.isCancelled {
                throw CancellationError()
            }
            throw error
        }
    }

    private func fetch(_ range: HTTPByteRange, from url: URL) async throws -> (Data, Int64?) {
        if let cachedData = await VideoRangeCache.shared.data(url: url, range: range) {
            if let cachedContentLength = NativeDASHContentLengthCache.shared.contentLength(for: url) {
                setKnownContentLength(cachedContentLength)
            }
            return (cachedData, currentKnownContentLength())
        }
        try Task.checkCancellation()
        let data = try await fetchExactData(range, from: url)
        try Task.checkCancellation()
        await VideoRangeCache.shared.store(data, url: url, range: range)
        if let cachedContentLength = NativeDASHContentLengthCache.shared.contentLength(for: url) {
            setKnownContentLength(cachedContentLength)
        }
        return (data, currentKnownContentLength())
    }

    private func fetchExactData(_ range: HTTPByteRange, from url: URL) async throws -> Data {
        let payload = try await fetchRemote(range, from: url)
        if let contentLength = payload.contentLength {
            setKnownContentLength(contentLength)
        }
        let data = try Self.data(payload.data, servedRange: payload.servedRange, requestedRange: range)
        if let contentLength = payload.contentLength {
            NativeDASHContentLengthCache.shared.set(contentLength, for: url)
        }
        if payload.servedRange != range,
           payload.servedRange.length <= maxCacheableServedPayloadLength,
           Int64(payload.data.count) == payload.servedRange.length {
            await VideoRangeCache.shared.store(payload.data, url: url, range: payload.servedRange)
        }
        return data
    }

    private func fetchRemote(_ range: HTTPByteRange, from url: URL) async throws -> RemoteRangePayload {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = timeoutInterval(for: range)
        request.networkServiceType = .video
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.setValue("bytes=\(range.start)-\(range.endInclusive)", forHTTPHeaderField: "Range")
        let (data, response) = try await BiliNetworkRetry.data(
            sessionProvider: { BiliPlaybackNetworkSessionPool.shared.playbackDataSession() },
            request: request,
            policy: .playbackShortResource
        )
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode)
        else {
            throw PlayerEngineError.unsupportedMedia
        }
        if httpResponse.statusCode == 200, range.start > 0 {
            throw PlayerEngineError.unsupportedMedia
        }
        let parsedContentRange = Self.contentRange(from: httpResponse)
        let contentLength = Self.contentLength(
            from: httpResponse,
            contentRange: parsedContentRange,
            servedRangeFallback: range,
            fallbackDataLength: data.count
        )
        let servedRange: HTTPByteRange
        if let parsedRange = parsedContentRange?.range {
            servedRange = parsedRange
        } else if httpResponse.statusCode == 200 {
            servedRange = HTTPByteRange(start: 0, endInclusive: max(Int64(data.count) - 1, 0))
        } else {
            servedRange = range
        }
        return RemoteRangePayload(
            data: data,
            servedRange: servedRange,
            contentLength: contentLength
        )
    }

    private func requestedRange(for loadingRequest: AVAssetResourceLoadingRequest) -> HTTPByteRange {
        guard let dataRequest = loadingRequest.dataRequest else {
            return HTTPByteRange(start: 0, endInclusive: 1)
        }
        let start = dataRequest.currentOffset > 0 ? dataRequest.currentOffset : dataRequest.requestedOffset
        let requestedLength = Int64(dataRequest.requestedLength)
        let fallbackLength: Int64 = mediaType == .audio ? 192 * 1024 : 768 * 1024
        let length = requestedLength > 0 ? requestedLength : fallbackLength
        return HTTPByteRange(start: max(start, 0), endInclusive: max(start, 0) + max(length, 1) - 1)
    }

    private func fillContentInformation(
        _ contentInformationRequest: AVAssetResourceLoadingContentInformationRequest?,
        contentLength: Int64?,
        sourceURL: URL
    ) async {
        guard let contentInformationRequest else { return }
        contentInformationRequest.isByteRangeAccessSupported = true
        if let contentLength, contentLength > 0 {
            contentInformationRequest.contentLength = contentLength
        }
        if mediaType == .audio {
            contentInformationRequest.contentType = UTType.mpeg4Audio.identifier
            return
        }
        if let type = UTType(filenameExtension: sourceURL.pathExtension), type.conforms(to: .movie) {
            contentInformationRequest.contentType = type.identifier
        } else if let type = UTType(filenameExtension: "mp4") {
            contentInformationRequest.contentType = type.identifier
        }
    }

    private func timeoutInterval(for range: HTTPByteRange) -> TimeInterval {
        if range.length <= 384 * 1024 {
            return 4
        }
        if range.length <= 2 * 1024 * 1024 {
            return 7
        }
        return 12
    }

    private var directFetchThreshold: Int64 {
        mediaType == .audio ? 1024 * 1024 : 4 * 1024 * 1024
    }

    private var streamingChunkLength: Int64 {
        mediaType == .audio ? 512 * 1024 : 2 * 1024 * 1024
    }

    private var maxCacheableServedPayloadLength: Int64 {
        mediaType == .audio ? 2 * 1024 * 1024 : 8 * 1024 * 1024
    }

    private func shouldUseFastFallback(for range: HTTPByteRange, urlCount: Int) -> Bool {
        guard urlCount > 1 else { return false }
        guard !PlaybackEnvironment.current.shouldPreferConservativePlayback else { return false }
        let limit: Int64 = mediaType == .audio ? 768 * 1024 : 2 * 1024 * 1024
        return range.length <= limit || range.start <= 2 * 1024 * 1024
    }

    private func recordURLResult(
        url: URL,
        elapsedMilliseconds: Double,
        bytes: Int64,
        succeeded: Bool
    ) {
        PlaybackURLPreferenceStore.shared.record(
            url: url,
            elapsedMilliseconds: min(max(elapsedMilliseconds, 10), 8_000),
            bytes: bytes,
            succeeded: succeeded
        )
    }

    private func setKnownContentLength(_ value: Int64) {
        guard value > 0 else { return }
        lock.lock()
        knownContentLength = value
        lock.unlock()
    }

    private func currentKnownContentLength() -> Int64? {
        lock.lock()
        let value = knownContentLength
        lock.unlock()
        return value
    }

    private func store(_ task: Task<Void, Never>, for identifier: ObjectIdentifier) -> Bool {
        lock.lock()
        guard activeRequests.contains(identifier) else {
            lock.unlock()
            return false
        }
        tasks[identifier] = task
        lock.unlock()
        return true
    }

    private func removeTask(for identifier: ObjectIdentifier) {
        lock.lock()
        tasks.removeValue(forKey: identifier)
        lock.unlock()
    }

    private func storeActiveRequest(_ identifier: ObjectIdentifier) {
        lock.lock()
        activeRequests.insert(identifier)
        lock.unlock()
    }

    private func removeActiveRequest(_ identifier: ObjectIdentifier) {
        lock.lock()
        activeRequests.remove(identifier)
        lock.unlock()
    }

    private func isRequestActive(_ identifier: ObjectIdentifier) -> Bool {
        lock.lock()
        let isActive = activeRequests.contains(identifier)
        lock.unlock()
        return isActive
    }

    private func cancelAll() {
        lock.lock()
        let currentTasks = Array(tasks.values)
        tasks.removeAll()
        activeRequests.removeAll()
        lock.unlock()
        currentTasks.forEach { $0.cancel() }
    }

    private static func contentLength(
        from response: HTTPURLResponse,
        contentRange: (range: HTTPByteRange, totalLength: Int64?)?,
        servedRangeFallback: HTTPByteRange,
        fallbackDataLength: Int
    ) -> Int64? {
        if let total = contentRange?.totalLength, total > 0 {
            return total
        }
        if response.statusCode == 200, response.expectedContentLength > 0 {
            return response.expectedContentLength
        }
        if response.statusCode == 200 {
            return max(Int64(fallbackDataLength), servedRangeFallback.endInclusive + 1)
        }
        return nil
    }

    private static func data(
        _ data: Data,
        servedRange: HTTPByteRange,
        requestedRange: HTTPByteRange
    ) throws -> Data {
        guard servedRange.start <= requestedRange.start,
              servedRange.endInclusive >= requestedRange.endInclusive,
              let lowerBound = Int(exactly: requestedRange.start - servedRange.start),
              let length = Int(exactly: requestedRange.length),
              lowerBound >= 0,
              length > 0,
              lowerBound + length <= data.count
        else {
            if servedRange == requestedRange, Int64(data.count) == requestedRange.length {
                return data
            }
            throw PlayerEngineError.unsupportedMedia
        }
        if lowerBound == 0, length == data.count {
            return data
        }
        return data.subdata(in: lowerBound..<(lowerBound + length))
    }

    private static func contentRange(from response: HTTPURLResponse) -> (range: HTTPByteRange, totalLength: Int64?)? {
        guard let value = response.value(forHTTPHeaderField: "Content-Range")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              value.hasPrefix("bytes ")
        else { return nil }
        let payload = value.dropFirst("bytes ".count)
        let parts = payload.split(separator: "/", maxSplits: 1).map(String.init)
        guard let range = HTTPByteRange(rawValue: parts.first) else { return nil }
        let totalLength = parts.indices.contains(1) ? Int64(parts[1]) : nil
        return (range, totalLength)
    }
}

private extension Array where Element == URL {
    nonisolated func removingNativeDASHDuplicates() -> [URL] {
        var seen = Set<String>()
        return filter { seen.insert($0.absoluteString).inserted }
    }
}

nonisolated private enum NativeDASHTaskWaiter {
    enum Timeout: LocalizedError {
        case timedOut

        var errorDescription: String? {
            "Native DASH 准备超时"
        }
    }

    static func value<T: Sendable>(
        of task: Task<T, Error>,
        timeoutNanoseconds: UInt64
    ) async throws -> T {
        let state = NativeDASHTaskWaiterState<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.install(continuation)

                let timeoutTask = Task.detached(priority: .userInitiated) {
                    do {
                        try await Task.sleep(nanoseconds: timeoutNanoseconds)
                    } catch {
                        return
                    }
                    if state.resume(.failure(Timeout.timedOut)) {
                        task.cancel()
                    }
                }

                let waiterTask = Task.detached(priority: .userInitiated) {
                    let result: Result<T, Error>
                    do {
                        result = .success(try await task.value)
                    } catch {
                        result = .failure(error)
                    }
                    if state.resume(result) {
                        timeoutTask.cancel()
                    }
                }

                state.storeTasks(waiter: waiterTask, timeout: timeoutTask)
            }
        } onCancel: {
            state.cancel()
            task.cancel()
        }
    }
}

nonisolated private final class NativeDASHTaskWaiterState<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var waiterTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var didResume = false

    func install(_ continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        if didResume {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func storeTasks(waiter: Task<Void, Never>, timeout: Task<Void, Never>) {
        lock.lock()
        if didResume {
            lock.unlock()
            waiter.cancel()
            timeout.cancel()
            return
        }
        waiterTask = waiter
        timeoutTask = timeout
        lock.unlock()
    }

    @discardableResult
    func resume(_ result: Result<T, Error>) -> Bool {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return false
        }
        didResume = true
        let continuation = continuation
        let waiterTask = waiterTask
        let timeoutTask = timeoutTask
        self.continuation = nil
        self.waiterTask = nil
        self.timeoutTask = nil
        lock.unlock()

        waiterTask?.cancel()
        timeoutTask?.cancel()
        switch result {
        case .success(let value):
            continuation?.resume(returning: value)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
        return true
    }

    func cancel() {
        _ = resume(.failure(CancellationError()))
    }
}

nonisolated private final class NativeDASHSampleBufferSession: @unchecked Sendable {
    struct Callbacks {
        let onVideoSample: @MainActor (TimeInterval) -> Void
        let onCompleted: @MainActor () -> Void
        let onFailed: @MainActor (String) -> Void
    }

    let duration: CMTime
    let videoHost: String
    let audioHost: String

    private let videoReader: AVAssetReader
    private let audioReader: AVAssetReader
    private let videoOutput: AVAssetReaderTrackOutput
    private let audioOutput: AVAssetReaderTrackOutput
    private let videoLoader: NativeDASHResourceLoader
    private let audioLoader: NativeDASHResourceLoader
    private let videoRenderer: AVSampleBufferVideoRenderer
    private let audioRenderer: AVSampleBufferAudioRenderer
    private let callbacks: Callbacks
    private let videoQueue: DispatchQueue
    private let audioQueue: DispatchQueue
    private let visibleStartSeconds: TimeInterval
    private let lock = NSLock()
    private var didStart = false
    private var didStop = false
    private var didCompleteVideo = false
    private var didCompleteAudio = false
    private var videoStarvationRetryCount = 0
    private var audioStarvationRetryCount = 0

    private init(
        videoReader: AVAssetReader,
        audioReader: AVAssetReader,
        videoOutput: AVAssetReaderTrackOutput,
        audioOutput: AVAssetReaderTrackOutput,
        videoLoader: NativeDASHResourceLoader,
        audioLoader: NativeDASHResourceLoader,
        videoRenderer: AVSampleBufferVideoRenderer,
        audioRenderer: AVSampleBufferAudioRenderer,
        duration: CMTime,
        videoHost: String,
        audioHost: String,
        visibleStartSeconds: TimeInterval,
        callbacks: Callbacks
    ) {
        self.videoReader = videoReader
        self.audioReader = audioReader
        self.videoOutput = videoOutput
        self.audioOutput = audioOutput
        self.videoLoader = videoLoader
        self.audioLoader = audioLoader
        self.videoRenderer = videoRenderer
        self.audioRenderer = audioRenderer
        self.duration = duration
        self.videoHost = videoHost
        self.audioHost = audioHost
        self.visibleStartSeconds = visibleStartSeconds
        self.callbacks = callbacks
        videoQueue = DispatchQueue(label: "cc.bili.native-dash.video", qos: .userInitiated)
        audioQueue = DispatchQueue(label: "cc.bili.native-dash.audio", qos: .userInitiated)
    }

    static func make(
        videoURLs: [URL],
        audioURLs: [URL],
        videoStream: DASHStream?,
        audioStream: DASHStream?,
        headers: [String: String],
        startTime: CMTime,
        videoRenderer: AVSampleBufferVideoRenderer,
        audioRenderer: AVSampleBufferAudioRenderer,
        synchronizer _: AVSampleBufferRenderSynchronizer,
        callbacks: Callbacks,
        metricsID: String,
        title: String
    ) async throws -> NativeDASHSampleBufferSession {
        guard let videoURL = videoURLs.first,
              let audioURL = audioURLs.first
        else {
            throw PlayerEngineError.unsupportedMedia
        }
        async let videoProbe = NativeDASHAssetProbeCache.shared.probe(
            urls: videoURLs,
            headers: headers,
            mediaType: .video,
            bootstrapRanges: NativeDASHResourceLoader.bootstrapRanges(
                for: videoStream,
                mediaType: .video
            ),
            metricsID: metricsID,
            title: title
        )
        async let audioProbe = NativeDASHAssetProbeCache.shared.probe(
            urls: audioURLs,
            headers: headers,
            mediaType: .audio,
            bootstrapRanges: NativeDASHResourceLoader.bootstrapRanges(
                for: audioStream,
                mediaType: .audio
            ),
            metricsID: metricsID,
            title: title
        )
        let (videoAssetProbe, audioAssetProbe) = try await (videoProbe, audioProbe)
        let videoAsset = videoAssetProbe.asset
        let audioAsset = audioAssetProbe.asset
        let videoTrack = videoAssetProbe.track
        let audioTrack = audioAssetProbe.track
        let duration = minFinite(videoAssetProbe.duration, audioAssetProbe.duration)
        let videoReader = try AVAssetReader(asset: videoAsset)
        let audioReader = try AVAssetReader(asset: audioAsset)
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
        videoOutput.alwaysCopiesSampleData = false
        audioOutput.alwaysCopiesSampleData = false
        guard videoReader.canAdd(videoOutput),
              audioReader.canAdd(audioOutput)
        else {
            throw PlayerEngineError.unsupportedMedia
        }
        videoReader.add(videoOutput)
        audioReader.add(audioOutput)

        let safeStart = startTime.isValid ? startTime : .zero
        let videoReaderStart = Self.videoReaderStartTime(for: safeStart)
        Self.applyTimeRange(to: videoReader, start: videoReaderStart, duration: duration)
        Self.applyTimeRange(to: audioReader, start: safeStart, duration: duration)

        if videoReaderStart.seconds < safeStart.seconds {
            PlayerMetricsLog.logger.info(
                "nativeDASHVideoPreroll target=\(safeStart.seconds, format: .fixed(precision: 2), privacy: .public) readerStart=\(videoReaderStart.seconds, format: .fixed(precision: 2), privacy: .public)"
            )
        }

        guard videoReader.startReading(),
              audioReader.startReading()
        else {
            throw videoReader.error ?? audioReader.error ?? PlayerEngineError.unsupportedMedia
        }

        return NativeDASHSampleBufferSession(
            videoReader: videoReader,
            audioReader: audioReader,
            videoOutput: videoOutput,
            audioOutput: audioOutput,
            videoLoader: videoAssetProbe.loader,
            audioLoader: audioAssetProbe.loader,
            videoRenderer: videoRenderer,
            audioRenderer: audioRenderer,
            duration: duration,
            videoHost: videoURL.host ?? "-",
            audioHost: audioURL.host ?? "-",
            visibleStartSeconds: max(safeStart.seconds, 0),
            callbacks: callbacks
        )
    }

    deinit {
        stop()
    }

    func start() {
        lock.lock()
        guard !didStart, !didStop else {
            lock.unlock()
            return
        }
        didStart = true
        lock.unlock()

        videoRenderer.requestMediaDataWhenReady(on: videoQueue) { [weak self] in
            self?.pumpVideo()
        }
        audioRenderer.requestMediaDataWhenReady(on: audioQueue) { [weak self] in
            self?.pumpAudio()
        }
    }

    func stop() {
        lock.lock()
        let wasStopped = didStop
        didStop = true
        lock.unlock()
        guard !wasStopped else { return }
        videoRenderer.stopRequestingMediaData()
        audioRenderer.stopRequestingMediaData()
        videoReader.cancelReading()
        audioReader.cancelReading()
        videoLoader.cancelActiveRequests()
        audioLoader.cancelActiveRequests()
    }

    private func pumpVideo() {
        while videoRenderer.isReadyForMoreMediaData && !isStopped {
            guard let sampleBuffer = videoOutput.copyNextSampleBuffer() else {
                handleVideoOutputGapOrCompletion()
                return
            }
            videoStarvationRetryCount = 0
            videoRenderer.enqueue(sampleBuffer)
            let time = sampleBuffer.presentationTimeStamp.seconds
            if time.isFinite, time >= max(visibleStartSeconds - 0.05, 0) {
                Task { @MainActor [callbacks] in
                    callbacks.onVideoSample(time)
                }
            }
        }
    }

    private func pumpAudio() {
        while audioRenderer.isReadyForMoreMediaData && !isStopped {
            guard let sampleBuffer = audioOutput.copyNextSampleBuffer() else {
                handleAudioOutputGapOrCompletion()
                return
            }
            audioStarvationRetryCount = 0
            audioRenderer.enqueue(sampleBuffer)
        }
    }

    private var isStopped: Bool {
        lock.lock()
        let value = didStop
        lock.unlock()
        return value
    }

    private func handleVideoOutputGapOrCompletion() {
        switch videoReader.status {
        case .completed:
            markVideoCompleted()
        case .failed:
            fail(videoReader.error ?? PlayerEngineError.unsupportedMedia)
        case .cancelled:
            break
        case .reading, .unknown:
            retryVideoPumpAfterTransientGap()
        @unknown default:
            retryVideoPumpAfterTransientGap()
        }
    }

    private func handleAudioOutputGapOrCompletion() {
        switch audioReader.status {
        case .completed:
            markAudioCompleted()
        case .failed:
            fail(audioReader.error ?? PlayerEngineError.unsupportedMedia)
        case .cancelled:
            break
        case .reading, .unknown:
            retryAudioPumpAfterTransientGap()
        @unknown default:
            retryAudioPumpAfterTransientGap()
        }
    }

    private func retryVideoPumpAfterTransientGap() {
        guard !isStopped else { return }
        videoStarvationRetryCount += 1
        if videoStarvationRetryCount > 240 {
            fail(videoReader.error ?? NativeDASHReaderStarvationError.video)
            return
        }
        videoQueue.asyncAfter(deadline: .now() + retryDelay(for: videoStarvationRetryCount)) { [weak self] in
            self?.pumpVideo()
        }
    }

    private func retryAudioPumpAfterTransientGap() {
        guard !isStopped else { return }
        audioStarvationRetryCount += 1
        if audioStarvationRetryCount > 240 {
            fail(audioReader.error ?? NativeDASHReaderStarvationError.audio)
            return
        }
        audioQueue.asyncAfter(deadline: .now() + retryDelay(for: audioStarvationRetryCount)) { [weak self] in
            self?.pumpAudio()
        }
    }

    private func retryDelay(for retryCount: Int) -> DispatchTimeInterval {
        let milliseconds = min(12 + retryCount / 8, 45)
        return .milliseconds(milliseconds)
    }

    private func markVideoCompleted() {
        lock.lock()
        didCompleteVideo = true
        let shouldComplete = didCompleteAudio && !didStop
        lock.unlock()
        if shouldComplete {
            complete()
        }
    }

    private func markAudioCompleted() {
        lock.lock()
        didCompleteAudio = true
        let shouldComplete = didCompleteVideo && !didStop
        lock.unlock()
        if shouldComplete {
            complete()
        }
    }

    private func complete() {
        stop()
        Task { @MainActor [callbacks] in
            callbacks.onCompleted()
        }
    }

    private func fail(_ error: Error) {
        stop()
        Task { @MainActor [callbacks] in
            callbacks.onFailed(error.localizedDescription)
        }
    }

    private static func minFinite(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
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

    private static func applyTimeRange(to reader: AVAssetReader, start: CMTime, duration: CMTime) {
        let safeStart = start.isValid ? start : .zero
        if duration.isValid, duration.seconds.isFinite, duration.seconds > safeStart.seconds {
            let remaining = CMTimeSubtract(duration, safeStart)
            reader.timeRange = CMTimeRange(start: safeStart, duration: remaining)
        } else if safeStart.seconds > 0 {
            reader.timeRange = CMTimeRange(start: safeStart, duration: .positiveInfinity)
        }
    }

    private static func videoReaderStartTime(for targetTime: CMTime) -> CMTime {
        let seconds = targetTime.seconds
        guard seconds.isFinite, seconds > 0.4 else { return .zero }
        let preroll: TimeInterval
        if seconds < 2.0 {
            preroll = 0.45
        } else if seconds < 15.0 {
            preroll = 0.9
        } else {
            preroll = 1.25
        }
        return CMTime(seconds: max(seconds - preroll, 0), preferredTimescale: 600)
    }
}

private enum NativeDASHReaderStarvationError: LocalizedError {
    case video
    case audio

    var errorDescription: String? {
        switch self {
        case .video:
            return "Native DASH 视频读取超时"
        case .audio:
            return "Native DASH 音频读取超时"
        }
    }
}
