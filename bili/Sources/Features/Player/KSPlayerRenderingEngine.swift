import AVFoundation
import AVKit
import CoreImage
import KSPlayer
import OSLog
import UIKit

@MainActor
final class KSPlayerRenderingEngine: NSObject, PlayerRenderingEngine {
    private struct PlaybackEndpoint {
        let url: URL
        let bridge: LocalHLSBridge?
        let mediaTimeOffset: TimeInterval
    }

    private struct StartupProbeProfile {
        let name: String
        let probeSize: Int64
        let maxAnalyzeDuration: Int64
        let formatProbeSize: Int
        let fpsProbeSize: Int

        var diagnosticDescription: String {
            let probeKilobytes = probeSize / 1024
            let analyzeMilliseconds = maxAnalyzeDuration / 1_000
            return "\(name) probe=\(probeKilobytes)KB analyze=\(analyzeMilliseconds)ms fps=\(fpsProbeSize)"
        }
    }

    private struct StartupTiming {
        let startedAt: CFTimeInterval
        var endpointMilliseconds: Double?
        var layerMilliseconds: Double?
        var layerCreateMilliseconds: Double?
        var viewInstallMilliseconds: Double?
        var prepareReturnMilliseconds: Double?
        var readyMilliseconds: Double?
        var decodedFrameMilliseconds: Double?
        var renderCallbackMilliseconds: Double?
        var firstFramePrimeMilliseconds: Double?
        var firstFramePrimeTime: CFTimeInterval?
        var firstFramePrimeReason = "-"
        var renderCallbackThread = "-"
        var ffmpegOpenMilliseconds: Double?
        var ffmpegFindMilliseconds: Double?
        var ffmpegReadyMilliseconds: Double?
        var ffmpegTotalMilliseconds: Double?
        var endpointKind = "-"
        var probeName = "-"
        var variantCount: Int?
    }

    private enum StartupProbeMode {
        case optimized
        case systemDefault

        var diagnosticName: String {
            switch self {
            case .optimized:
                return "optimized"
            case .systemDefault:
                return "default"
            }
        }
    }

    private static var didConfigureDefaults = false

    private var playerLayer: KSPlayerLayer?
    private weak var surfaceView: UIView?
    private weak var playerView: UIView?
    private let videoFrameContext = CIContext()
    private var lastVideoFrameImage: UIImage?
    private var pendingSurfaceDetachTask: Task<Void, Never>?
    private var source: PlayerStreamSource?
    private var hlsBridge: LocalHLSBridge?
    private var mediaTimeOffset: TimeInterval = 0
    private var currentRate: Float = 1
    private var currentVolume: Float = 1
    private var currentMuted = false
    private var wantsPlayback = false
    private var didReportFirstFrame = false
    private var firstDecodedFrameSeenAt: CFTimeInterval?
    private var firstNonBlackDecodedFrameSeenAt: CFTimeInterval?
    private var firstFrameProbeTask: Task<Void, Never>?
    private var seekResumeTask: Task<Void, Never>?
    private var startupWarmupTask: Task<Void, Never>?
    private var currentEndpoint: PlaybackEndpoint?
    private var currentStartupProbeMode: StartupProbeMode = .optimized
    private var activeStartupProbeProfile: StartupProbeProfile?
    private var startupTiming: StartupTiming?
    private var didRetryWithoutStartupProbe = false
    private var didRecordCurrentLayerTiming = false
    private var didRecordSteadyBuffering = false
    private var didRecordStartupFirstFramePrime = false
    private var lastPlaybackState: PlayerEnginePlaybackState = .idle
    private var lastError: Error?
    private var prepareContinuation: CheckedContinuation<Void, Error>?
    private var playerPrepareStartTime: CFTimeInterval?
    private var videoGravity: AVLayerVideoGravity = .resizeAspect
    private var lastDiagnostics: PlayerEngineDiagnostics = .empty
    private var playbackGeneration = 0
    private var isStopped = true

    var hasMedia: Bool {
        !isStopped && playerLayer != nil
    }

    var needsMediaRecovery: Bool {
        !isStopped && playerLayer?.state == .error
    }

    var playbackErrorMessage: String? {
        lastError?.localizedDescription
    }

    var lastFailureReason: HLSBridgeFailureReason? {
        nil
    }

    var supportsPictureInPicture: Bool {
        if #available(iOS 15.0, tvOS 15.0, *) {
            return playerLayer?.player.pipController != nil
        }
        return false
    }

    var isPictureInPictureActive: Bool {
        playerLayer?.isPipActive == true
    }

    var usesNativePlaybackControls: Bool {
        false
    }

    var diagnostics: PlayerEngineDiagnostics {
        lastDiagnostics
    }

    var volume: Float {
        currentVolume
    }

    var isMuted: Bool {
        currentMuted
    }

    var onPlaybackStateChange: (@MainActor (PlayerEnginePlaybackState) -> Void)?
    var onPlaybackIntentChange: (@MainActor (Bool) -> Void)?
    var onLoadingProgressChange: (@MainActor (Double) -> Void)?
    var onFirstFrame: (@MainActor (TimeInterval) -> Void)?

    override init() {
        Self.configureDefaultsIfNeeded()
        super.init()
    }

    deinit {
        KSPlayerDecodeLogForwarder.shared.clearActivePlayback(metricsID: source?.metricsID)
        pendingSurfaceDetachTask?.cancel()
        firstFrameProbeTask?.cancel()
        seekResumeTask?.cancel()
        startupWarmupTask?.cancel()
        prepareContinuation?.resume(throwing: CancellationError())
        prepareContinuation = nil
        playerLayer?.delegate = nil
        playerLayer?.stop()
    }

    func attachSurface(_ surface: UIView) {
        pendingSurfaceDetachTask?.cancel()
        pendingSurfaceDetachTask = nil
        surfaceView = surface
        installPlayerViewIfNeeded()
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
            self.playerView?.removeFromSuperview()
            self.playerView = nil
            self.pendingSurfaceDetachTask = nil
        }
        surfaceView = nil
    }

    func refreshSurfaceLayout() {
        applyVideoGravity()
    }

    func recoverSurface() {
        guard !isStopped else { return }
        installPlayerViewIfNeeded()
        if wantsPlayback {
            playerLayer?.play()
        }
    }

    func setViewModel(_: PlayerStateViewModel?) {}

    func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        videoGravity = gravity
        applyVideoGravity()
    }

    func attachNativePlaybackController(_ controller: AVPlayerViewController) {
        controller.player = nil
    }

    func detachNativePlaybackController(_ controller: AVPlayerViewController) {
        controller.player = nil
    }

    func prepare(source: PlayerStreamSource) async throws {
        Self.configureDefaultsIfNeeded()
        playbackGeneration &+= 1
        let generation = playbackGeneration
        isStopped = false
        self.source = source
        wantsPlayback = false
        didReportFirstFrame = false
        await HLSProxyStartupMetrics.shared.reset(metricsID: source.metricsID)
        firstDecodedFrameSeenAt = nil
        firstNonBlackDecodedFrameSeenAt = nil
        currentEndpoint = nil
        currentStartupProbeMode = .optimized
        activeStartupProbeProfile = nil
        startupTiming = StartupTiming(startedAt: CACurrentMediaTime())
        didRetryWithoutStartupProbe = false
        didRecordCurrentLayerTiming = false
        didRecordSteadyBuffering = false
        didRecordStartupFirstFramePrime = false
        firstFrameProbeTask?.cancel()
        firstFrameProbeTask = nil
        startupWarmupTask?.cancel()
        startupWarmupTask = nil
        lastError = nil
        prepareContinuation?.resume(throwing: CancellationError())
        prepareContinuation = nil
        lastDiagnostics = Self.makeDiagnostics(
            source: source,
            endpoint: nil,
            options: nil
        )
        onLoadingProgressChange?(0.18)
        publishPlaybackState(.preparing)

        try validateSourceForDirectKSPlayback(source)
        let endpointStart = CACurrentMediaTime()
        let endpoint = try await makePlaybackEndpoint(for: source)
        startupTiming?.endpointMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: endpointStart)
        startupTiming?.endpointKind = endpoint.bridge == nil ? "direct" : "localHLS"
        startupTiming?.variantCount = endpoint.bridge?.videoVariantCount
        guard !Task.isCancelled, isCurrentPlaybackGeneration(generation) else {
            throw CancellationError()
        }

        releaseCurrentPlayer(notifyIdle: false)
        guard isCurrentPlaybackGeneration(generation) else {
            throw CancellationError()
        }
        KSPlayerDecodeLogForwarder.shared.setActivePlayback(
            metricsID: source.metricsID,
            title: source.title
        )
        hlsBridge = endpoint.bridge
        mediaTimeOffset = endpoint.mediaTimeOffset
        currentEndpoint = endpoint

        try installPlayerLayer(
            source: source,
            endpoint: endpoint,
            probeMode: .optimized,
            generation: generation
        )
    }

    func play() {
        guard !isStopped, let playerLayer else { return }
        wantsPlayback = true
        lastError = nil
        onPlaybackIntentChange?(true)
        playerLayer.play()
        playerLayer.player.playbackRate = currentRate
        if playerLayer.player.isReadyToPlay {
            primeStartupFirstFrameRender(on: playerLayer, reason: "play")
        }
        onLoadingProgressChange?(0.98)
        if playerLayer.player.isPlaying || playerLayer.state.isPlaying {
            publishPlaybackState(.playing)
            reportFirstRenderedFrameIfPossible(currentTime: displayTime(fromPlayerTime: playerLayer.player.currentPlaybackTime))
        } else {
            publishPlaybackState(.buffering)
        }
    }

    func pause() {
        guard !isStopped else { return }
        wantsPlayback = false
        onPlaybackIntentChange?(false)
        playerLayer?.pause()
        publishPlaybackState(.paused)
    }

    func pauseForNavigation() {
        guard !isStopped else { return }
        wantsPlayback = false
        onPlaybackIntentChange?(false)
        playerLayer?.pause()
        publishPlaybackState(.paused)
    }

    func stop() {
        playbackGeneration &+= 1
        isStopped = true
        wantsPlayback = false
        completePrepare(.failure(CancellationError()))
        firstFrameProbeTask?.cancel()
        firstFrameProbeTask = nil
        startupWarmupTask?.cancel()
        startupWarmupTask = nil
        releaseCurrentPlayer(notifyIdle: true)
    }

    func setPlaybackRate(_ rate: Double) {
        let normalizedRate = max(Float(rate), 0.1)
        guard abs(currentRate - normalizedRate) > 0.001 else { return }
        currentRate = normalizedRate
        applyRateAwareBuffering()
        playerLayer?.player.playbackRate = currentRate
    }

    func setPreferredPeakBitRate(_: Double?) {}

    func setVolume(_ volume: Float) {
        currentVolume = min(max(volume, 0), 1)
        playerLayer?.player.playbackVolume = currentVolume
    }

    func setMuted(_ isMuted: Bool) {
        currentMuted = isMuted
        playerLayer?.player.isMuted = isMuted
    }

    func setTemporaryAudioSuppressed(_ isSuppressed: Bool) {
        if isSuppressed {
            playerLayer?.player.isMuted = true
            playerLayer?.player.playbackVolume = 0
        } else {
            playerLayer?.player.playbackVolume = currentVolume
            playerLayer?.player.isMuted = currentMuted
        }
    }

    func seek(toTime time: TimeInterval) -> TimeInterval? {
        guard let playerLayer else { return nil }
        let displayTarget = alignedInteractiveSeekTime(max(time, 0))
        let target = playerTime(fromDisplayTime: displayTarget)
        let generation = playbackGeneration
        if wantsPlayback {
            publishPlaybackState(.buffering)
        }
        warmSeekTargetIfNeeded(displayTarget)
        playerLayer.seek(time: target, autoPlay: wantsPlayback) { [weak self, weak playerLayer] finished in
            guard let self, finished else { return }
            Task { @MainActor [weak self, weak playerLayer] in
                guard let self,
                      let playerLayer,
                      playerLayer === self.playerLayer,
                      self.isCurrentPlaybackGeneration(generation)
                else { return }
                if self.wantsPlayback {
                    self.resumePlaybackAfterInteractiveSeek(
                        layer: playerLayer,
                        generation: generation,
                        targetTime: target,
                        displayTarget: displayTarget,
                        allowsFollowUpSeek: false
                    )
                }
            }
        }
        if wantsPlayback {
            primeVideoOutputAfterInteractiveSeek(on: playerLayer, shouldFlush: false, readCount: 2)
            resumePlaybackAfterInteractiveSeek(
                layer: playerLayer,
                generation: generation,
                targetTime: target,
                displayTarget: displayTarget,
                allowsFollowUpSeek: true
            )
        }
        return displayTarget
    }

    func seek(toProgress progress: Double, duration: TimeInterval?) -> TimeInterval? {
        guard playerLayer != nil else { return nil }
        let resolvedDuration = resolvedDuration(durationHint: duration)
        guard resolvedDuration > 0 else { return nil }
        return seek(toTime: alignedInteractiveSeekTime(min(max(progress, 0), 1) * resolvedDuration))
    }

    func seek(by interval: TimeInterval, from currentTime: TimeInterval, duration: TimeInterval?) -> TimeInterval? {
        guard playerLayer != nil else { return nil }
        let resolvedDuration = resolvedDuration(durationHint: duration)
        let target = resolvedDuration > 0
            ? min(max(currentTime + interval, 0), resolvedDuration)
            : max(currentTime + interval, 0)
        return seek(toTime: alignedInteractiveSeekTime(target))
    }

    func seekAfterUserScrub(toProgress progress: Double, duration: TimeInterval?) async -> TimeInterval? {
        guard let playerLayer else { return nil }
        let resolvedDuration = resolvedDuration(durationHint: duration)
        guard resolvedDuration > 0 else { return nil }
        let displayTarget = alignedInteractiveSeekTime(min(max(progress, 0), 1) * resolvedDuration)
        let seekTarget = playerTime(fromDisplayTime: adjustedInteractiveSeekDisplayTime(displayTarget))
        let generation = playbackGeneration
        wantsPlayback = true
        seekResumeTask?.cancel()
        publishPlaybackState(.buffering)
        warmSeekTargetIfNeeded(displayTarget)
        let finished = await attemptInteractiveSeek(
            on: playerLayer,
            targetTime: seekTarget,
            generation: generation
        )
        guard !Task.isCancelled,
              playerLayer === self.playerLayer,
              isCurrentPlaybackGeneration(generation)
        else { return nil }
        if wantsPlayback {
            primeVideoOutputAfterInteractiveSeek(on: playerLayer, shouldFlush: false, readCount: 2)
            resumePlaybackAfterInteractiveSeek(
                layer: playerLayer,
                generation: generation,
                targetTime: seekTarget,
                displayTarget: displayTarget,
                allowsFollowUpSeek: !finished
            )
        }
        if !finished {
            PlayerMetricsLog.record(
                .seekRecovery,
                metricsID: source?.metricsID ?? "-",
                title: source?.title,
                message: "ksSeek=queued target=\(String(format: "%.2fs", displayTarget)) completion=timeout"
            )
        }
        return displayTarget
    }

    func snapshot(durationHint: TimeInterval?) -> PlayerPlaybackSnapshot {
        guard let playerLayer else {
            return PlayerPlaybackSnapshot(
                currentTime: nil,
                duration: durationHint,
                isPlaying: false,
                isSeekable: false,
                bufferedRanges: []
            )
        }

        let player = playerLayer.player
        let duration = resolvedDuration(durationHint: durationHint)
        let currentTime = displayTime(fromPlayerTime: player.currentPlaybackTime)
        let requiresRenderedTime = player is KSMEPlayer
        return PlayerPlaybackSnapshot(
            currentTime: currentTime.isFinite ? currentTime : nil,
            renderedVideoTime: requiresRenderedTime ? currentRenderedVideoTime(for: player) : nil,
            requiresRenderedVideoTimeForRecovery: requiresRenderedTime,
            duration: duration > 0 ? duration : nil,
            isPlaying: player.isPlaying || playerLayer.state.isPlaying,
            isSeekable: player.seekable || duration > 0,
            bufferedRanges: []
        )
    }

    func currentSurfaceSnapshotImage() -> UIImage? {
        playerView?.biliRenderedSnapshotImage()
            ?? surfaceView?.biliRenderedSnapshotImage()
    }

    func currentVideoFrameImage() -> UIImage? {
        guard let pixelBuffer = (playerLayer?.player as? KSMEPlayer)?.videoOutput?.pixelBuffer else {
            return lastVideoFrameImage
        }
        return cacheVideoFrameImage(from: pixelBuffer)
    }

    func pictureInPictureContentSource() -> AVPictureInPictureController.ContentSource? {
        nil
    }

    func togglePictureInPicture() {
        playerLayer?.isPipActive.toggle()
    }

    func invalidatePictureInPicturePlaybackState() {
        if #available(iOS 15.0, tvOS 15.0, *) {
            playerLayer?.player.pipController?.invalidatePlaybackState()
        }
    }

    private static func configureDefaultsIfNeeded() {
        guard !didConfigureDefaults else { return }
        KSOptions.firstPlayerType = KSMEPlayer.self
        KSOptions.secondPlayerType = nil
        KSOptions.logLevel = .info
        KSOptions.logger = KSPlayerDecodeLogForwarder.shared
        didConfigureDefaults = true
    }

    private func makePlaybackEndpoint(for source: PlayerStreamSource) async throws -> PlaybackEndpoint {
        guard let videoURL = source.videoURL else {
            throw PlayerEngineError.missingVideoURL
        }

        if source.audioURL != nil {
            let manifest = try await BiliHLSManifestBuilder.make(
                source: source,
                shouldValidateHardwareDecoding: false,
                includesAlternateVideoRenditions: false
            )
            return PlaybackEndpoint(
                url: manifest.masterPlaylistURL,
                bridge: manifest.bridge,
                mediaTimeOffset: manifest.mediaTimeOffset
            )
        }

        return PlaybackEndpoint(url: videoURL, bridge: nil, mediaTimeOffset: 0)
    }

    private func installPlayerLayer(
        source: PlayerStreamSource,
        endpoint: PlaybackEndpoint,
        probeMode: StartupProbeMode,
        generation: Int
    ) throws {
        currentStartupProbeMode = probeMode
        let options = makeOptions(for: source, startupProbeMode: probeMode)
        startupTiming?.probeName = activeStartupProbeProfile?.name ?? probeMode.diagnosticName
        lastDiagnostics = Self.makeDiagnostics(
            source: source,
            endpoint: endpoint,
            options: options
        )
        PlayerMetricsLog.record(
            .mediaPrepared,
            metricsID: source.metricsID,
            title: source.title,
            message: "\(lastDiagnostics.compactDescription) · probe=\(probeMode.diagnosticName)"
        )
        let layerStart = CACurrentMediaTime()
        let layerCreateStart = CACurrentMediaTime()
        let layer = KSPlayerLayer(url: endpoint.url, isAutoPlay: false, options: options, delegate: self)
        startupTiming?.layerCreateMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: layerCreateStart)
        layer.player.playbackRate = currentRate
        layer.player.playbackVolume = currentVolume
        layer.player.isMuted = currentMuted
        playerLayer = layer
        didRecordCurrentLayerTiming = false
        configureFirstFrameRenderCallback(for: layer)
        let viewInstallStart = CACurrentMediaTime()
        installPlayerViewIfNeeded(forceLayout: false)
        startupTiming?.viewInstallMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: viewInstallStart)
        startupTiming?.layerMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: layerStart)
        guard !Task.isCancelled,
              layer === playerLayer,
              isCurrentPlaybackGeneration(generation)
        else {
            layer.delegate = nil
            layer.stop()
            throw CancellationError()
        }
        onLoadingProgressChange?(0.42)
        let prepareStart = CACurrentMediaTime()
        playerPrepareStartTime = prepareStart
        layer.prepareToPlay()
        let elapsedMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: prepareStart)
        startupTiming?.prepareReturnMilliseconds = elapsedMilliseconds
        PlayerMetricsLog.record(
            .manifestStage,
            metricsID: source.metricsID,
            title: source.title,
            message: "ksPrepareReturn=async \(Int(elapsedMilliseconds.rounded()))ms probe=\(probeMode.diagnosticName)"
        )
        guard !Task.isCancelled,
              layer === playerLayer,
              isCurrentPlaybackGeneration(generation)
        else { throw CancellationError() }
        onLoadingProgressChange?(0.72)
    }

    private func makeOptions(
        for source: PlayerStreamSource,
        startupProbeMode: StartupProbeMode = .optimized
    ) -> KSOptions {
        let options = KSOptions()
        options.userAgent = source.httpHeaders["User-Agent"] ?? options.userAgent
        options.referer = source.referer
        options.appendHeader(source.httpHeaders)
        let environment = PlaybackEnvironment.current
        if source.durationHint == nil {
            options.preferredForwardBufferDuration = environment.shouldPreferConservativePlayback ? 0.5 : 0.8
            options.maxBufferDuration = environment.shouldPreferConservativePlayback ? 4 : 8
        } else if source.audioURL == nil {
            options.preferredForwardBufferDuration = preferredForwardBufferDuration(for: source, environment: environment)
            options.maxBufferDuration = environment.maxBufferDuration
        } else {
            options.preferredForwardBufferDuration = startupPreferredForwardBufferDuration(
                for: source,
                environment: environment
            )
            options.maxBufferDuration = startupMaxBufferDuration(for: source, environment: environment)
        }
        recordBufferConfiguration(stage: "startup", source: source, options: options, environment: environment)
        options.isSecondOpen = true
        options.isAccurateSeek = false
        options.hardwareDecode = true
        if let stream = source.videoStream {
            options.requiresHardwareDecode = PlayerKernelPlaybackSupport.shouldRequireHardwareDecode(
                for: stream,
                on: .ksPlayer
            )
        }
        options.asynchronousDecompression = Self.shouldUseAsynchronousDecompression(for: source)
        if source.videoStream?.isAV1VideoCodec == true {
            options.codecLowDelay = true
        }
        switch startupProbeMode {
        case .optimized:
            activeStartupProbeProfile = applyStartupProbeProfileIfNeeded(
                to: options,
                for: source,
                environment: environment
            )
        case .systemDefault:
            activeStartupProbeProfile = nil
            if source.audioURL != nil {
                PlayerMetricsLog.record(
                    .manifestStage,
                    metricsID: source.metricsID,
                    title: source.title,
                    message: "ksFastProbe=default"
                )
            }
        }
        options.registerRemoteControll = false
        return options
    }

    @discardableResult
    private func applyStartupProbeProfileIfNeeded(
        to options: KSOptions,
        for source: PlayerStreamSource,
        environment: PlaybackEnvironment
    ) -> StartupProbeProfile? {
        guard let profile = startupProbeProfile(for: source, environment: environment) else { return nil }
        options.probesize = profile.probeSize
        options.maxAnalyzeDuration = profile.maxAnalyzeDuration
        options.formatContextOptions["probesize"] = profile.probeSize
        options.formatContextOptions["analyzeduration"] = profile.maxAnalyzeDuration
        options.formatContextOptions["formatprobesize"] = profile.formatProbeSize
        options.formatContextOptions["fpsprobesize"] = profile.fpsProbeSize
        PlayerMetricsLog.record(
            .manifestStage,
            metricsID: source.metricsID,
            title: source.title,
            message: "ksFastProbe=\(profile.diagnosticDescription)"
        )
        return profile
    }

    private func startupProbeProfile(
        for source: PlayerStreamSource,
        environment: PlaybackEnvironment
    ) -> StartupProbeProfile? {
        guard source.audioURL != nil else { return nil }
        guard source.videoURL != nil else { return nil }

        let stream = source.videoStream
        let frameRate = DASHStream.numericFrameRate(from: stream?.frameRate) ?? 0
        let width = stream?.width ?? 0
        let height = stream?.height ?? 0
        let longEdge = max(width, height)
        let pixelCount = width * height
        let isLargeOrComplexVideo = source.dynamicRange.isHDR
            || frameRate >= 50
            || longEdge >= 2560
            || pixelCount >= 2560 * 1440

        if isLargeOrComplexVideo {
            return StartupProbeProfile(
                name: "balanced",
                probeSize: 512 * 1024,
                maxAnalyzeDuration: 650_000,
                formatProbeSize: 64 * 1024,
                fpsProbeSize: 3
            )
        }

        if stream?.isAV1VideoCodec == true {
            return StartupProbeProfile(
                name: "av1",
                probeSize: 384 * 1024,
                maxAnalyzeDuration: 480_000,
                formatProbeSize: 64 * 1024,
                fpsProbeSize: 2
            )
        }

        if environment.shouldPreferConservativePlayback {
            return StartupProbeProfile(
                name: "safe",
                probeSize: 384 * 1024,
                maxAnalyzeDuration: 520_000,
                formatProbeSize: 64 * 1024,
                fpsProbeSize: 3
            )
        }

        return StartupProbeProfile(
            name: "fast",
            probeSize: 256 * 1024,
            maxAnalyzeDuration: 360_000,
            formatProbeSize: 48 * 1024,
            fpsProbeSize: 2
        )
    }

    private func validateSourceForDirectKSPlayback(_ source: PlayerStreamSource) throws {
        guard let stream = source.videoStream else { return }
        guard PlayerKernelPlaybackSupport.shouldRejectDirectPlayback(of: stream, on: .ksPlayer) else {
            return
        }
        PlayerMetricsLog.logger.notice(
            "ksPlayerDirectPlaybackRejected codec=\(stream.codecs ?? "-", privacy: .public) codecid=\(stream.codecid ?? -1, privacy: .public) reason=ksPlayerAV1VideoToolboxUnavailable id=\(source.metricsID, privacy: .public)"
        )
        throw PlayerEngineError.unsupportedMedia
    }

    private func preferredForwardBufferDuration(
        for source: PlayerStreamSource,
        environment: PlaybackEnvironment = .current
    ) -> TimeInterval {
        let baseDuration = source.audioURL == nil
            ? environment.preferredForwardBufferDuration
            : environment.separatedTrackForwardBufferDuration
        guard currentRate >= 1.5 else { return baseDuration }
        return max(baseDuration, environment.highRateForwardBufferDuration)
    }

    private func startupPreferredForwardBufferDuration(
        for source: PlayerStreamSource,
        environment: PlaybackEnvironment = .current
    ) -> TimeInterval {
        let steadyStateDuration = preferredForwardBufferDuration(for: source, environment: environment)
        let startupFloor = source.audioURL == nil
            ? max(environment.startupForwardBufferDuration * 2, 0.10)
            : max(
                environment.startupForwardBufferDuration * 2,
                environment.shouldPreferConservativePlayback ? 0.18 : 0.12
            )
        return min(steadyStateDuration, startupFloor)
    }

    private func startupMaxBufferDuration(
        for source: PlayerStreamSource,
        environment: PlaybackEnvironment = .current
    ) -> TimeInterval {
        guard source.audioURL != nil else { return environment.maxBufferDuration }
        let preferredDuration = startupPreferredForwardBufferDuration(for: source, environment: environment)
        let minimumDuration = environment.shouldPreferConservativePlayback ? 1.4 : 1.8
        return min(environment.maxBufferDuration, max(minimumDuration, preferredDuration * 8))
    }

    private func steadyStateMaxBufferDuration(
        for source: PlayerStreamSource,
        environment: PlaybackEnvironment = .current
    ) -> TimeInterval {
        guard source.durationHint != nil else {
            return environment.shouldPreferConservativePlayback ? 4 : 8
        }
        return environment.maxBufferDuration
    }

    private func applyRateAwareBuffering() {
        guard let source, let options = playerLayer?.options else { return }
        let preferredDuration = didReportFirstFrame
            ? preferredForwardBufferDuration(for: source)
            : startupPreferredForwardBufferDuration(for: source)
        options.preferredForwardBufferDuration = preferredDuration
        options.maxBufferDuration = didReportFirstFrame
            ? steadyStateMaxBufferDuration(for: source)
            : startupMaxBufferDuration(for: source)
        lastDiagnostics.preferredForwardBufferDuration = options.preferredForwardBufferDuration
        lastDiagnostics.maxBufferDuration = options.maxBufferDuration
        if didReportFirstFrame, !didRecordSteadyBuffering {
            didRecordSteadyBuffering = true
            recordBufferConfiguration(stage: "steady", source: source, options: options)
        }
    }

    private func recordBufferConfiguration(
        stage: String,
        source: PlayerStreamSource,
        options: KSOptions,
        environment: PlaybackEnvironment = .current
    ) {
        guard source.audioURL != nil else { return }
        PlayerMetricsLog.record(
            .manifestStage,
            metricsID: source.metricsID,
            title: source.title,
            message: [
                "ksStartupBuffer=\(stage)",
                "preferred=\(String(format: "%.2fs", options.preferredForwardBufferDuration))",
                "max=\(String(format: "%.2fs", options.maxBufferDuration))",
                "steady=\(String(format: "%.2fs", preferredForwardBufferDuration(for: source, environment: environment)))",
                "steadyMax=\(String(format: "%.2fs", steadyStateMaxBufferDuration(for: source, environment: environment)))"
            ].joined(separator: " ")
        )
    }

    private static func shouldUseAsynchronousDecompression(for source: PlayerStreamSource) -> Bool {
        guard let stream = source.videoStream else { return false }
        guard stream.isHardwareDecodingCompatibleVideo else { return false }
        if stream.isAV1VideoCodec {
            return PlayerKernelPlaybackSupport.shouldRejectDirectPlayback(of: stream, on: .ksPlayer) == false
        }
        if PlaybackEnvironment.current.isThermallyConstrained {
            return false
        }
        let frameRate = DASHStream.numericFrameRate(from: stream.frameRate) ?? 0
        let width = stream.width ?? 0
        let height = stream.height ?? 0
        return frameRate >= 50
            || width >= 2560
            || height >= 1440
            || source.dynamicRange.isHDR
    }

    private static func makeDiagnostics(
        source: PlayerStreamSource,
        endpoint: PlaybackEndpoint?,
        options: KSOptions?
    ) -> PlayerEngineDiagnostics {
        let stream = source.videoStream
        let resolution = stream?.resolutionLabel
        let frameRate = stream?.displayFrameRate
        return PlayerEngineDiagnostics(
            engineName: "KSPlayer",
            decodePath: .ksPlayer,
            codec: stream?.codecLabel ?? DASHStream.codecLabel(for: stream?.codecs, codecid: stream?.codecid),
            resolution: resolution,
            frameRate: frameRate,
            bandwidth: stream?.bandwidth,
            dynamicRange: source.dynamicRange,
            isDASH: source.audioURL != nil,
            usesLocalHLSBridge: endpoint?.bridge != nil,
            hlsVideoVariantCount: endpoint?.bridge?.videoVariantCount ?? 0,
            hlsVideoVariantQualities: endpoint?.bridge?.videoVariantQualities ?? [],
            preferredForwardBufferDuration: options?.preferredForwardBufferDuration,
            maxBufferDuration: options?.maxBufferDuration,
            asynchronousDecompressionEnabled: options?.asynchronousDecompression == true,
            hardwareDecodeRequested: options?.hardwareDecode == true,
            environmentSummary: PlaybackEnvironment.current.diagnosticSummary
        )
    }

    private func installPlayerViewIfNeeded(forceLayout: Bool = true) {
        guard let surfaceView, let playerView = playerLayer?.player.view else { return }
        if self.playerView !== playerView {
            self.playerView?.removeFromSuperview()
            self.playerView = playerView
        }
        if playerView.superview !== surfaceView {
            playerView.removeFromSuperview()
            playerView.translatesAutoresizingMaskIntoConstraints = true
            playerView.backgroundColor = .black
            playerView.isUserInteractionEnabled = false
            surfaceView.insertSubview(playerView, at: 0)
        }
        applyVideoGravity(forceLayout: forceLayout)
    }

    private func applyVideoGravity(forceLayout: Bool = true) {
        let mode: UIView.ContentMode
        switch videoGravity {
        case .resize:
            mode = .scaleToFill
        case .resizeAspectFill:
            mode = .scaleAspectFill
        default:
            mode = .scaleAspectFit
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation {
            playerView?.frame = surfaceView?.bounds ?? .zero
            playerView?.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            playerView?.contentMode = mode
            if forceLayout {
                playerView?.setNeedsLayout()
                playerView?.layoutIfNeeded()
            }
        }
        CATransaction.commit()
        playerLayer?.player.contentMode = mode
    }

    private func releaseCurrentPlayer(notifyIdle: Bool) {
        if notifyIdle {
            KSPlayerDecodeLogForwarder.shared.clearActivePlayback(metricsID: source?.metricsID)
        }
        tearDownCurrentLayerForReplacement()
        startupWarmupTask?.cancel()
        startupWarmupTask = nil
        completePrepare(.failure(CancellationError()))
        hlsBridge = nil
        currentEndpoint = nil
        activeStartupProbeProfile = nil
        if notifyIdle {
            startupTiming = nil
        }
        currentStartupProbeMode = .optimized
        didRetryWithoutStartupProbe = false
        mediaTimeOffset = 0
        if notifyIdle {
            lastDiagnostics = .empty
        }
        if notifyIdle {
            lastError = nil
            publishPlaybackState(.idle)
        }
    }

    private func tearDownCurrentLayerForReplacement() {
        pendingSurfaceDetachTask?.cancel()
        pendingSurfaceDetachTask = nil
        firstFrameProbeTask?.cancel()
        firstFrameProbeTask = nil
        seekResumeTask?.cancel()
        seekResumeTask = nil
        clearFirstFrameRenderCallback()
        playerLayer?.delegate = nil
        playerLayer?.stop()
        playerLayer = nil
        lastVideoFrameImage = nil
        playerView?.removeFromSuperview()
        playerView = nil
        playerPrepareStartTime = nil
        didReportFirstFrame = false
        firstDecodedFrameSeenAt = nil
        firstNonBlackDecodedFrameSeenAt = nil
        didRecordCurrentLayerTiming = false
        didRecordSteadyBuffering = false
        didRecordStartupFirstFramePrime = false
    }

    private func retryPlaybackWithDefaultProbeIfPossible(error: Error?) -> Bool {
        guard !isStopped,
              !didReportFirstFrame,
              !didRetryWithoutStartupProbe,
              currentStartupProbeMode == .optimized,
              let failedProfile = activeStartupProbeProfile,
              let source,
              let endpoint = currentEndpoint
        else { return false }

        didRetryWithoutStartupProbe = true
        let errorDescription = error?.localizedDescription ?? "ksPlayerError"
        PlayerMetricsLog.record(
            .manifestStage,
            metricsID: source.metricsID,
            title: source.title,
            message: "ksFastProbeFallback=default failed=\(failedProfile.name) error=\(errorDescription)"
        )
        let generation = playbackGeneration
        lastError = nil
        publishPlaybackState(.preparing)
        tearDownCurrentLayerForReplacement()
        hlsBridge = endpoint.bridge
        mediaTimeOffset = endpoint.mediaTimeOffset
        do {
            try installPlayerLayer(
                source: source,
                endpoint: endpoint,
                probeMode: .systemDefault,
                generation: generation
            )
            if wantsPlayback {
                publishPlaybackState(.buffering)
            }
            return true
        } catch {
            lastError = error
            completePrepare(.failure(error))
            publishPlaybackState(.failed(error.localizedDescription))
            return true
        }
    }

    private func recordKSPlayerStartupTimingIfNeeded(layer: KSPlayerLayer, stage: String) {
        guard !didRecordCurrentLayerTiming,
              let source,
              layer === playerLayer
        else { return }
        let options = layer.options
        guard options.prepareTime > 0,
              options.openTime > 0,
              options.findTime > 0,
              options.readyTime > 0
        else { return }

        didRecordCurrentLayerTiming = true
        let openMilliseconds = max(options.openTime - options.prepareTime, 0) * 1_000
        let findMilliseconds = max(options.findTime - options.openTime, 0) * 1_000
        let readyMilliseconds = max(options.readyTime - options.findTime, 0) * 1_000
        let totalMilliseconds = max(options.readyTime - options.prepareTime, 0) * 1_000
        let formatName = options.formatName.isEmpty ? "-" : options.formatName
        let profileName = activeStartupProbeProfile?.name ?? currentStartupProbeMode.diagnosticName
        if let timing = startupTiming {
            startupTiming?.readyMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: timing.startedAt)
            startupTiming?.ffmpegOpenMilliseconds = openMilliseconds
            startupTiming?.ffmpegFindMilliseconds = findMilliseconds
            startupTiming?.ffmpegReadyMilliseconds = readyMilliseconds
            startupTiming?.ffmpegTotalMilliseconds = totalMilliseconds
        }
        PlayerMetricsLog.record(
            .manifestStage,
            metricsID: source.metricsID,
            title: source.title,
            message: "ksFFmpeg=\(stage) probe=\(profileName) open=\(String(format: "%.0fms", openMilliseconds)) find=\(String(format: "%.0fms", findMilliseconds)) ready=\(String(format: "%.0fms", readyMilliseconds)) total=\(String(format: "%.0fms", totalMilliseconds)) format=\(formatName)"
        )
        recordKSStartupBreakdown(stage: stage, ffmpegTotalMilliseconds: totalMilliseconds)
    }

    private func recordKSStartupBreakdown(
        stage: String,
        currentTime: TimeInterval? = nil,
        ffmpegTotalMilliseconds: Double? = nil
    ) {
        guard let source, let timing = startupTiming else { return }
        let firstFrameMilliseconds = stage == "firstFrame"
            ? PlayerMetricsLog.elapsedMilliseconds(since: timing.startedAt)
            : nil
        let renderAfterReadyMilliseconds: Double? = {
            guard let firstFrameMilliseconds,
                  let readyMilliseconds = timing.readyMilliseconds
            else { return nil }
            return max(firstFrameMilliseconds - readyMilliseconds, 0)
        }()
        var fields = [
            "ksStartup=\(stage)",
            "endpoint=\(formattedMilliseconds(timing.endpointMilliseconds))",
            "layer=\(formattedMilliseconds(timing.layerMilliseconds))",
            "layerCreate=\(formattedMilliseconds(timing.layerCreateMilliseconds))",
            "viewInstall=\(formattedMilliseconds(timing.viewInstallMilliseconds))",
            "prepareCall=\(formattedMilliseconds(timing.prepareReturnMilliseconds))",
            "ready=\(formattedMilliseconds(timing.readyMilliseconds))",
            "firstFrame=\(formattedMilliseconds(firstFrameMilliseconds))",
            "renderAfterReady=\(formattedMilliseconds(renderAfterReadyMilliseconds))",
            "prime=\(formattedMilliseconds(timing.firstFramePrimeMilliseconds))",
            "readyToPrime=\(formattedMillisecondsDelta(from: timing.readyMilliseconds, to: timing.firstFramePrimeMilliseconds))",
            "primeToFrame=\(formattedMillisecondsDelta(from: timing.firstFramePrimeMilliseconds, to: firstFrameMilliseconds))",
            "primeToRender=\(formattedMillisecondsDelta(from: timing.firstFramePrimeMilliseconds, to: timing.renderCallbackMilliseconds))",
            "primeReason=\(timing.firstFramePrimeReason)",
            "renderThread=\(timing.renderCallbackThread)",
            "decodedFrame=\(formattedMilliseconds(timing.decodedFrameMilliseconds))",
            "ksRender=\(formattedMilliseconds(timing.renderCallbackMilliseconds))",
            "ffmpeg=\(formattedMilliseconds(ffmpegTotalMilliseconds ?? timing.ffmpegTotalMilliseconds))",
            "ffOpen=\(formattedMilliseconds(timing.ffmpegOpenMilliseconds))",
            "ffFind=\(formattedMilliseconds(timing.ffmpegFindMilliseconds))",
            "ffReady=\(formattedMilliseconds(timing.ffmpegReadyMilliseconds))",
            "probe=\(timing.probeName)",
            "endpointKind=\(timing.endpointKind)",
            "variants=\(timing.variantCount.map(String.init) ?? "-")"
        ]
        if let bridge = hlsBridge {
            fields.append("bridge=\(bridge.routePlanCacheState)")
            fields.append("server=\(bridge.serverCacheState)")
        }
        if let options = playerLayer?.options {
            fields.append(contentsOf: [
                "ksLayer=\(formattedSecondsDuration(options.playerLayerInitDuration))",
                "playerNew=\(formattedSecondsDuration(options.mediaPlayerCreateDuration))",
                "playerInit=\(formattedSecondsDuration(options.mediaPlayerInitDuration))",
                "audioSession=\(formattedSecondsDuration(options.audioSessionSetupDuration))",
                "audioOut=\(formattedSecondsDuration(options.audioOutputInitDuration))",
                "itemInit=\(formattedSecondsDuration(options.playerItemInitDuration))",
                "ffGlobal=\(formattedSecondsDuration(options.ffmpegGlobalInitDuration))",
                "videoOut=\(formattedSecondsDuration(options.videoOutputInitDuration))",
                "bindOut=\(formattedSecondsDuration(options.outputBindDuration))",
                "codecCreate=\(formattedTimeDelta(from: options.codecCreateStartTime, to: options.codecCreateEndTime))",
                "readVideo=\(formattedTimeDelta(from: options.readyTime, to: options.readVideoTime))",
                "readAudio=\(formattedTimeDelta(from: options.readyTime, to: options.readAudioTime))",
                "decodeVideo=\(formattedTimeDelta(from: options.readVideoTime, to: options.decodeVideoTime))",
                "decodeAudio=\(formattedTimeDelta(from: options.readAudioTime, to: options.decodeAudioTime))",
                "playable=\(formattedTimeDelta(from: options.readyTime, to: options.firstPlayableTime))",
                "frameDecoded=\(formattedTimeDelta(from: options.readyTime, to: options.firstVideoFrameDecodedTime))",
                "frameFetched=\(formattedTimeDelta(from: options.readyTime, to: options.firstVideoFrameFetchedTime))",
                "displayEnq=\(formattedTimeDelta(from: options.readyTime, to: options.firstDisplayLayerEnqueueTime))",
                "primeToFetch=\(formattedTimeDelta(from: timing.firstFramePrimeTime ?? 0, to: options.firstVideoFrameFetchedTime))",
                "primeToEnq=\(formattedTimeDelta(from: timing.firstFramePrimeTime ?? 0, to: options.firstDisplayLayerEnqueueTime))",
                "metalDrawable=\(formattedTimeDelta(from: options.readyTime, to: options.firstMetalDrawableTime))",
                "metalDraw=\(formattedTimeDelta(from: options.readyTime, to: options.firstMetalDrawEndTime))",
                "decodeReady=\(formattedTimeDelta(from: options.readVideoTime, to: options.firstVideoFrameDecodedTime))",
                "fetchGap=\(formattedTimeDelta(from: options.firstVideoFrameDecodedTime, to: options.firstVideoFrameFetchedTime))",
                "enqueueGap=\(formattedTimeDelta(from: options.firstVideoFrameFetchedTime, to: options.firstDisplayLayerEnqueueTime))",
                "metalWait=\(formattedTimeDelta(from: options.firstMetalDrawStartTime, to: options.firstMetalDrawableTime))"
            ])
        }
        if let codec = source.videoStream?.codecLabel, !codec.isEmpty {
            fields.append("codec=\(codec)")
        }
        if let frameRate = source.videoStream?.displayFrameRate, !frameRate.isEmpty {
            fields.append("fps=\(frameRate)")
        }
        if let resolution = source.videoStream?.resolutionLabel, !resolution.isEmpty {
            fields.append("res=\(resolution)")
        }
        if let currentTime, currentTime.isFinite {
            fields.append("time=\(String(format: "%.2fs", max(currentTime, 0)))")
        }
        PlayerMetricsLog.record(
            .startupBreakdown,
            metricsID: source.metricsID,
            title: source.title,
            message: fields.joined(separator: " ")
        )
        publishHLSStartupSummaryIfNeeded(stage: stage, source: source)
    }

    private func publishHLSStartupSummaryIfNeeded(stage: String, source: PlayerStreamSource) {
        guard stage == "firstFrame",
              startupTiming?.endpointKind == "localHLS"
        else { return }
        let metricsID = source.metricsID
        let title = source.title
        Task { @MainActor in
            for delay in [0, 35_000_000, 120_000_000, 260_000_000] as [UInt64] {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
                guard let summary = await HLSProxyStartupMetrics.shared.summary(metricsID: metricsID) else {
                    continue
                }
                PlayerMetricsLog.record(
                    .network,
                    metricsID: metricsID,
                    title: title,
                    message: summary
                )
                return
            }
        }
    }

    private func formattedMilliseconds(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "-" }
        return "\(Int(value.rounded()))ms"
    }

    private func formattedMillisecondsDelta(from start: Double?, to end: Double?) -> String {
        guard let start,
              let end,
              start.isFinite,
              end.isFinite
        else { return "-" }
        return formattedMilliseconds(max(end - start, 0))
    }

    private func formattedSecondsDuration(_ value: TimeInterval) -> String {
        guard value.isFinite, value > 0 else { return "-" }
        return formattedMilliseconds(value * 1_000)
    }

    private func formattedTimeDelta(from start: CFTimeInterval, to end: CFTimeInterval) -> String {
        guard start.isFinite,
              end.isFinite,
              start > 0,
              end > 0
        else { return "-" }
        return formattedMilliseconds(max(end - start, 0) * 1_000)
    }

    private func completePrepare(_ result: Result<Void, Error>) {
        guard let continuation = prepareContinuation else { return }
        prepareContinuation = nil
        switch result {
        case .success:
            continuation.resume()
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private func reportFirstFrameIfPossible(currentTime: TimeInterval) {
        guard !didReportFirstFrame else { return }
        firstFrameProbeTask?.cancel()
        firstFrameProbeTask = nil
        didReportFirstFrame = true
        applyRateAwareBuffering()
        onLoadingProgressChange?(1)
        onFirstFrame?(currentTime)
        recordKSStartupBreakdown(stage: "firstFrame", currentTime: currentTime)
        startupTiming = nil
    }

    private func isCurrentPlaybackGeneration(_ generation: Int) -> Bool {
        generation == playbackGeneration
    }

    private func adjustedInteractiveSeekDisplayTime(_ displayTime: TimeInterval) -> TimeInterval {
        max(displayTime, 0)
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

    private func scheduleStartupWarmupIfNeeded(for source: PlayerStreamSource) {
        startupWarmupTask?.cancel()
        startupWarmupTask = nil
        guard let videoURL = source.videoURL,
              let audioURL = source.audioURL,
              let videoStream = source.videoStream,
              let audioStream = source.audioStream,
              videoStream.segmentBase?.indexByteRange != nil,
              audioStream.segmentBase?.indexByteRange != nil
        else { return }

        let playbackTime = source.resumeTime > 0.25 ? source.resumeTime : nil
        let targetDescription = playbackTime.map { String(format: "%.2fs", $0) } ?? "startup"
        PlayerMetricsLog.record(
            .manifestStage,
            metricsID: source.metricsID,
            title: source.title,
            message: "ksStartupWarm=queued target=\(targetDescription)"
        )

        let videoTrack = HLSBridgeTrack(
            url: videoURL,
            fallbackURLs: videoStream.backupPlayURLs(cdnPreference: source.cdnPreference),
            stream: videoStream,
            mediaType: .video,
            dynamicRange: source.dynamicRange
        )
        let audioTrack = HLSBridgeTrack(
            url: audioURL,
            fallbackURLs: audioStream.backupPlayURLs(cdnPreference: source.cdnPreference),
            stream: audioStream,
            mediaType: .audio
        )
        let headers = source.httpHeaders
        let metricsID = source.metricsID
        let title = source.title

        startupWarmupTask = Task.detached(priority: .userInitiated) {
            let start = CACurrentMediaTime()
            let didWarm = await LocalHLSBridge.warmup(
                videoTrack: videoTrack,
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
                message: "ksStartupWarm=\(didWarm ? "ok" : "skip") target=\(targetDescription) elapsed=\(String(format: "%.0fms", elapsed))"
            )
        }
    }

    private func attemptInteractiveSeek(
        on layer: KSPlayerLayer,
        targetTime: TimeInterval,
        generation: Int
    ) async -> Bool {
        let attempts: [(delay: UInt64, timeout: UInt64)] = [
            (0, 420_000_000),
            (70_000_000, 620_000_000)
        ]

        for attempt in attempts {
            if attempt.delay > 0 {
                try? await Task.sleep(nanoseconds: attempt.delay)
            }
            guard !Task.isCancelled,
                  layer === playerLayer,
                  isCurrentPlaybackGeneration(generation)
            else { return false }

            primeVideoOutputAfterInteractiveSeek(on: layer, shouldFlush: false)
            let finished = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                var didResume = false

                func resume(_ value: Bool) {
                    guard !didResume else { return }
                    didResume = true
                    continuation.resume(returning: value)
                }

                layer.seek(time: targetTime, autoPlay: true) { finished in
                    Task { @MainActor in
                        resume(finished)
                    }
                }

                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: attempt.timeout)
                    resume(false)
                }
            }
            if finished {
                return true
            }
        }
        return false
    }

    private func resumePlaybackAfterInteractiveSeek(
        layer: KSPlayerLayer,
        generation: Int,
        targetTime: TimeInterval,
        displayTarget: TimeInterval,
        allowsFollowUpSeek: Bool
    ) {
        seekResumeTask?.cancel()
        let recoveryStartedAt = CACurrentMediaTime()
        seekResumeTask = Task { @MainActor [weak self, weak layer] in
            let delays: [UInt64] = [
                0,
                16_000_000,
                34_000_000,
                70_000_000,
                120_000_000,
                210_000_000,
                360_000_000,
                620_000_000,
                950_000_000,
                1_200_000_000
            ]
            var previousDelay: UInt64 = 0
            var didFollowUpSeek = false
            var didRecordRenderReady = false
            for (index, targetDelay) in delays.enumerated() {
                let delay = targetDelay > previousDelay ? targetDelay - previousDelay : 0
                previousDelay = targetDelay
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                } else {
                    await Task.yield()
                }
                guard let self,
                      let layer,
                      !Task.isCancelled,
                      layer === self.playerLayer,
                      self.isCurrentPlaybackGeneration(generation),
                      self.wantsPlayback
                else { return }

                self.installPlayerViewIfNeeded()
                self.applyVideoGravity()
                let readCount = targetDelay <= 120_000_000 ? 2 : 1
                self.primeVideoOutputAfterInteractiveSeek(
                    on: layer,
                    shouldFlush: false,
                    readCount: readCount
                )
                layer.play()
                layer.player.playbackRate = self.currentRate
                if layer.player.isPlaying || layer.state.isPlaying {
                    self.publishPlaybackState(.playing)
                } else {
                    self.publishPlaybackState(.buffering)
                }

                let currentTime = self.displayTime(fromPlayerTime: layer.player.currentPlaybackTime)
                let renderedTime = self.currentRenderedVideoTime(for: layer.player)
                let hasTargetFrame = renderedTime.map {
                    self.isRenderedTime($0, closeTo: displayTarget)
                } ?? false
                let hasVisibleTargetFrame = hasTargetFrame && self.hasVisibleRenderedVideoFrame
                if hasVisibleTargetFrame, !didRecordRenderReady {
                    didRecordRenderReady = true
                    self.recordSeekRenderProbe(
                        stage: "renderReady",
                        target: displayTarget,
                        currentTime: currentTime,
                        renderedTime: renderedTime,
                        elapsed: CACurrentMediaTime() - recoveryStartedAt,
                        attempt: index,
                        targetDelay: targetDelay
                    )
                }

                if allowsFollowUpSeek,
                   !didFollowUpSeek,
                   targetDelay >= 360_000_000,
                   !hasVisibleTargetFrame {
                    didFollowUpSeek = true
                    PlayerMetricsLog.record(
                        .seekRecovery,
                        metricsID: self.source?.metricsID ?? "-",
                        title: self.source?.title,
                        message: "ksSeek=followUp target=\(String(format: "%.2fs", displayTarget))"
                    )
                    layer.seek(time: targetTime, autoPlay: true) { [weak self, weak layer] finished in
                        Task { @MainActor [weak self, weak layer] in
                            guard let self,
                                  let layer,
                                  layer === self.playerLayer,
                                  self.isCurrentPlaybackGeneration(generation),
                                  self.wantsPlayback
                            else { return }
                            self.primeVideoOutputAfterInteractiveSeek(
                                on: layer,
                                shouldFlush: false,
                                readCount: 2
                            )
                            layer.play()
                            layer.player.playbackRate = self.currentRate
                            PlayerMetricsLog.record(
                                .seekRecovery,
                                metricsID: self.source?.metricsID ?? "-",
                                title: self.source?.title,
                                message: "ksSeek=followUpResult target=\(String(format: "%.2fs", displayTarget)) finished=\(finished)"
                            )
                        }
                    }
                }

                if self.didReportFirstFrame {
                    self.onLoadingProgressChange?(0.98)
                } else {
                    self.reportFirstRenderedFrameIfPossible(currentTime: currentTime)
                }

                if index == delays.count - 1, !didRecordRenderReady {
                    self.recordSeekRenderProbe(
                        stage: "renderPending",
                        target: displayTarget,
                        currentTime: currentTime,
                        renderedTime: renderedTime,
                        elapsed: CACurrentMediaTime() - recoveryStartedAt,
                        attempt: index,
                        targetDelay: targetDelay
                    )
                }
            }
            self?.seekResumeTask = nil
        }
    }

    private func configureFirstFrameRenderCallback(for layer: KSPlayerLayer) {
        guard let player = layer.player as? KSMEPlayer else { return }
        player.videoOutput?.onRenderedFrame = { [weak self, weak layer] playerTime in
            if Thread.isMainThread {
                MainActor.assumeIsolated { [weak self, weak layer] in
                    self?.handleRenderedFirstFrame(
                        playerTime: playerTime,
                        layer: layer,
                        callbackThread: "main"
                    )
                }
            } else {
                Task { @MainActor [weak self, weak layer] in
                    self?.handleRenderedFirstFrame(
                        playerTime: playerTime,
                        layer: layer,
                        callbackThread: "background"
                    )
                }
            }
        }
    }

    private func clearFirstFrameRenderCallback() {
        (playerLayer?.player as? KSMEPlayer)?.videoOutput?.onRenderedFrame = nil
    }

    private func handleRenderedFirstFrame(
        playerTime: TimeInterval,
        layer: KSPlayerLayer?,
        callbackThread: String
    ) {
        guard let layer,
              !didReportFirstFrame,
              !isStopped,
              layer === playerLayer
        else { return }
        startupTiming?.renderCallbackThread = callbackThread
        let currentTime = displayTime(fromPlayerTime: playerTime)
        recordRenderedFrameStage(currentTime: currentTime)
        _ = hasDecodedVideoFrame
        reportFirstFrameIfPossible(currentTime: currentTime)
    }

    private func recordRenderedFrameStage(currentTime: TimeInterval) {
        guard let source else { return }
        if let timing = startupTiming,
           startupTiming?.renderCallbackMilliseconds == nil {
            startupTiming?.renderCallbackMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: timing.startedAt)
        }
        let normalizedTime = currentTime.isFinite ? max(currentTime, 0) : 0
        PlayerMetricsLog.record(
            .manifestStage,
            metricsID: source.metricsID,
            title: source.title,
            message: "ksRender=callback time=\(String(format: "%.2f", normalizedTime))s"
        )
    }

    private func reportFirstRenderedFrameIfPossible(currentTime: TimeInterval) {
        guard !didReportFirstFrame else { return }
        guard requiresRenderedFrameConfirmation else {
            reportFirstFrameIfPossible(currentTime: currentTime)
            return
        }
        if hasDecodedVideoFrame, canFallbackToDecodedFirstFrame {
            reportFirstFrameIfPossible(currentTime: currentTime)
        } else if shouldProbeVisibleSurface, hasVisibleRenderedVideoFrame {
            reportFirstFrameIfPossible(currentTime: currentTime)
        } else {
            scheduleFirstFrameProbe(currentTime: currentTime)
        }
    }

    private func primeStartupFirstFrameRender(on layer: KSPlayerLayer, reason: String) {
        guard !didReportFirstFrame,
              wantsPlayback,
              layer.player.isReadyToPlay,
              layer === playerLayer
        else { return }

        playerView?.setNeedsLayout()
        playerView?.layoutIfNeeded()
        if let timing = startupTiming,
           startupTiming?.firstFramePrimeTime == nil {
            let now = CACurrentMediaTime()
            startupTiming?.firstFramePrimeTime = now
            startupTiming?.firstFramePrimeMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: timing.startedAt)
            startupTiming?.firstFramePrimeReason = reason
        }
        primeVideoOutputAfterInteractiveSeek(on: layer, shouldFlush: false, readCount: 2)
        let currentTime = displayTime(fromPlayerTime: layer.player.currentPlaybackTime)
        if !didRecordStartupFirstFramePrime {
            didRecordStartupFirstFramePrime = true
            PlayerMetricsLog.record(
                .manifestStage,
                metricsID: source?.metricsID ?? "-",
                title: source?.title,
                message: "ksFirstFramePrime=\(reason) time=\(String(format: "%.2fs", max(currentTime, 0)))"
            )
        }
        reportFirstRenderedFrameIfPossible(currentTime: currentTime)
        scheduleFirstFrameProbe(
            currentTime: currentTime,
            initialDelayNanoseconds: 8_000_000,
            readKickInterval: 0.045
        )
    }

    private var requiresRenderedFrameConfirmation: Bool {
        guard let player = playerLayer?.player else { return true }
        return player is KSMEPlayer
    }

    private var hasVisibleRenderedVideoFrame: Bool {
        guard hasDecodedVideoFrame else { return false }
        guard let image = playerView?.biliRenderedSnapshotImage()
            ?? surfaceView?.biliRenderedSnapshotImage()
        else { return false }
        return !image.ksPlayerLooksLikeBlackFrame
    }

    private func currentRenderedVideoTime(for player: MediaPlayerProtocol) -> TimeInterval? {
        guard hasCurrentDecodedVideoFrame else { return nil }
        let renderedTime = displayTime(fromPlayerTime: player.currentPlaybackTime)
        guard renderedTime.isFinite, renderedTime >= 0 else { return nil }
        return renderedTime
    }

    private func isRenderedTime(_ renderedTime: TimeInterval, closeTo targetTime: TimeInterval) -> Bool {
        guard renderedTime.isFinite, targetTime.isFinite else { return false }
        let toleranceBefore = max(0.75, min(targetTime * 0.025, 1.8))
        let toleranceAfter = max(3.5, min(targetTime * 0.08, 8.0))
        return renderedTime >= max(targetTime - toleranceBefore, 0)
            && renderedTime <= targetTime + toleranceAfter
    }

    private func recordSeekRenderProbe(
        stage: String,
        target: TimeInterval,
        currentTime: TimeInterval,
        renderedTime: TimeInterval?,
        elapsed: CFTimeInterval,
        attempt: Int,
        targetDelay: UInt64
    ) {
        PlayerMetricsLog.record(
            .seekRecovery,
            metricsID: source?.metricsID ?? "-",
            title: source?.title,
            message: [
                "ksSeek=\(stage)",
                "target=\(String(format: "%.2fs", target))",
                "current=\(String(format: "%.2fs", currentTime))",
                "rendered=\(renderedTime.map { String(format: "%.2fs", $0) } ?? "-")",
                "elapsed=\(String(format: "%.0fms", elapsed * 1_000))",
                "attempt=\(attempt)",
                "delay=\(String(format: "%.0fms", Double(targetDelay) / 1_000_000))"
            ].joined(separator: " ")
        )
    }

    private var hasCurrentDecodedVideoFrame: Bool {
        guard let player = playerLayer?.player as? KSMEPlayer else {
            guard let image = playerView?.biliRenderedSnapshotImage()
                ?? surfaceView?.biliRenderedSnapshotImage()
            else { return false }
            return !image.ksPlayerLooksLikeBlackFrame
        }
        guard player.videoOutput?.pixelBuffer != nil else { return false }
        if firstDecodedFrameSeenAt == nil {
            firstDecodedFrameSeenAt = CACurrentMediaTime()
            if let timing = startupTiming,
               startupTiming?.decodedFrameMilliseconds == nil {
                startupTiming?.decodedFrameMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: timing.startedAt)
            }
        }
        return true
    }

    private var hasDecodedVideoFrame: Bool {
        guard let player = playerLayer?.player as? KSMEPlayer else {
            guard let image = playerView?.biliRenderedSnapshotImage()
                ?? surfaceView?.biliRenderedSnapshotImage()
            else { return false }
            return !image.ksPlayerLooksLikeBlackFrame
        }
        guard player.videoOutput?.pixelBuffer != nil else { return false }
        if firstDecodedFrameSeenAt == nil {
            firstDecodedFrameSeenAt = CACurrentMediaTime()
            if let timing = startupTiming,
               startupTiming?.decodedFrameMilliseconds == nil {
                startupTiming?.decodedFrameMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: timing.startedAt)
            }
        }
        return true
    }

    private var shouldProbeVisibleSurface: Bool {
        guard let timing = startupTiming else { return false }
        return CACurrentMediaTime() - timing.startedAt >= 0.18
    }

    private var canFallbackToDecodedFirstFrame: Bool {
        guard let firstDecodedFrameSeenAt else { return false }
        return CACurrentMediaTime() - firstDecodedFrameSeenAt >= 0.035
    }

    private func primeVideoOutputAfterInteractiveSeek(
        on layer: KSPlayerLayer,
        shouldFlush: Bool,
        readCount: Int = 1
    ) {
        guard let player = layer.player as? KSMEPlayer else { return }
        if shouldFlush {
            player.videoOutput?.flush()
        }
        player.videoOutput?.play()
        for _ in 0..<max(readCount, 1) {
            player.videoOutput?.readNextFrame()
        }
    }

    private func makeImage(from pixelBuffer: PixelBufferProtocol) -> UIImage? {
        if let cvPixelBuffer = pixelBuffer.cvPixelBuffer {
            return makeImage(from: cvPixelBuffer)
        }
        guard let cgImage = pixelBuffer.cgImage() else { return nil }
        return UIImage(cgImage: cgImage)
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

    private func cacheVideoFrameImage(from pixelBuffer: PixelBufferProtocol) -> UIImage? {
        guard let image = makeImage(from: pixelBuffer) else { return lastVideoFrameImage }
        lastVideoFrameImage = image
        return image
    }

    private func scheduleFirstFrameProbe(
        currentTime: TimeInterval,
        initialDelayNanoseconds: UInt64 = 70_000_000,
        readKickInterval: CFTimeInterval = 0.12
    ) {
        guard firstFrameProbeTask == nil else { return }
        guard let probeLayer = playerLayer else { return }
        let generation = playbackGeneration
        firstFrameProbeTask = Task { @MainActor [weak self, weak probeLayer] in
            try? await Task.sleep(nanoseconds: initialDelayNanoseconds)
            let deadline = CACurrentMediaTime() + 0.72
            var lastKnownTime = currentTime
            var nextReadKick = CACurrentMediaTime()

            while !Task.isCancelled {
                guard let self else { return }
                guard let probeLayer,
                      probeLayer === self.playerLayer,
                      self.isCurrentPlaybackGeneration(generation),
                      !self.didReportFirstFrame
                else {
                    self.firstFrameProbeTask = nil
                    return
                }

                let playerTime = self.displayTime(fromPlayerTime: probeLayer.player.currentPlaybackTime)
                if playerTime.isFinite, playerTime >= 0 {
                    lastKnownTime = playerTime
                }

                if self.hasVisibleRenderedVideoFrame
                    || (self.hasDecodedVideoFrame && self.canFallbackToDecodedFirstFrame) {
                    self.reportFirstFrameIfPossible(currentTime: lastKnownTime)
                    return
                }

                if self.wantsPlayback {
                    self.playerView?.setNeedsLayout()
                    self.playerView?.layoutIfNeeded()
                    if !(probeLayer.player.isPlaying || probeLayer.state.isPlaying) {
                        probeLayer.play()
                    }
                    let now = CACurrentMediaTime()
                    if now >= nextReadKick {
                        (probeLayer.player as? KSMEPlayer)?.videoOutput?.readNextFrame()
                        nextReadKick = now + readKickInterval
                    }
                }

                guard CACurrentMediaTime() < deadline else {
                    self.firstFrameProbeTask = nil
                    return
                }
                try? await Task.sleep(nanoseconds: 35_000_000)
            }
        }
    }

    private func publishPlaybackState(_ state: PlayerEnginePlaybackState) {
        guard state != lastPlaybackState else { return }
        lastPlaybackState = state
        onPlaybackStateChange?(state)
    }

    private func resolvedDuration(durationHint: TimeInterval?) -> TimeInterval {
        let playerDuration = playerLayer?.player.duration ?? 0
        if mediaTimeOffset > 0 {
            if let durationHint, durationHint > 0 {
                return durationHint
            }
            if let sourceDurationHint = source?.durationHint, sourceDurationHint > 0 {
                return sourceDurationHint
            }
            if playerDuration.isFinite, playerDuration > mediaTimeOffset {
                return playerDuration - mediaTimeOffset
            }
        }
        if playerDuration.isFinite, playerDuration > 0 {
            return playerDuration
        }
        return durationHint ?? source?.durationHint ?? 0
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
}

extension KSPlayerRenderingEngine: KSPlayerLayerDelegate {
    func player(layer: KSPlayerLayer, state: KSPlayerState) {
        guard !isStopped, layer === playerLayer else { return }
        switch state {
        case .initialized:
            publishPlaybackState(.idle)
        case .preparing:
            publishPlaybackState(.preparing)
        case .readyToPlay:
            completePrepare(.success(()))
            if let source,
               let playerPrepareStartTime {
                let elapsedMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: playerPrepareStartTime)
                PlayerMetricsLog.record(
                    .manifestStage,
                    metricsID: source.metricsID,
                    title: source.title,
                    message: "ksReady=\(Int(elapsedMilliseconds.rounded()))ms"
                )
            }
            recordKSPlayerStartupTimingIfNeeded(layer: layer, stage: "ready")
            publishPlaybackState(.ready)
            if wantsPlayback {
                layer.play()
                layer.player.playbackRate = currentRate
                primeStartupFirstFrameRender(on: layer, reason: "ready")
            }
        case .buffering:
            publishPlaybackState(.buffering)
        case .bufferFinished:
            publishPlaybackState(wantsPlayback ? .playing : .ready)
            if wantsPlayback {
                reportFirstRenderedFrameIfPossible(currentTime: displayTime(fromPlayerTime: layer.player.currentPlaybackTime))
            }
        case .paused:
            publishPlaybackState(.paused)
        case .playedToTheEnd:
            publishPlaybackState(.ended)
        case .error:
            let error = lastError ?? PlayerEngineError.unsupportedMedia
            if retryPlaybackWithDefaultProbeIfPossible(error: lastError) {
                return
            }
            lastError = error
            completePrepare(.failure(error))
            publishPlaybackState(.failed(error.localizedDescription))
        }
    }

    func player(layer: KSPlayerLayer, currentTime: TimeInterval, totalTime _: TimeInterval) {
        guard !isStopped, layer === playerLayer else { return }
        if wantsPlayback || layer.player.isPlaying || layer.state.isPlaying {
            publishPlaybackState(.playing)
            reportFirstRenderedFrameIfPossible(currentTime: displayTime(fromPlayerTime: currentTime))
        }
    }

    func player(layer: KSPlayerLayer, finish error: Error?) {
        guard !isStopped, layer === playerLayer else { return }
        if let error {
            if retryPlaybackWithDefaultProbeIfPossible(error: error) {
                return
            }
            lastError = error
            completePrepare(.failure(error))
            publishPlaybackState(.failed(error.localizedDescription))
        } else {
            publishPlaybackState(.ended)
        }
    }

    func player(layer: KSPlayerLayer, bufferedCount _: Int, consumeTime _: TimeInterval) {
        guard !isStopped, layer === playerLayer else { return }
        let bufferedProgress = Double(layer.bufferingProgress) / 100
        let fallbackProgress: Double = layer.state == .buffering ? 0.22 : 0.12
        onLoadingProgressChange?(min(max(bufferedProgress, fallbackProgress), 0.98))
    }
}

private extension UIImage {
    var ksPlayerLooksLikeBlackFrame: Bool {
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
