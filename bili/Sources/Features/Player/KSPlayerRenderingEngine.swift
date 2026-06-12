import AVFoundation
import AVKit
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

    private static var didConfigureDefaults = false

    private var playerLayer: KSPlayerLayer?
    private weak var surfaceView: UIView?
    private weak var playerView: UIView?
    private var source: PlayerStreamSource?
    private var hlsBridge: LocalHLSBridge?
    private var mediaTimeOffset: TimeInterval = 0
    private var currentRate: Float = 1
    private var currentVolume: Float = 1
    private var currentMuted = false
    private var wantsPlayback = false
    private var didReportFirstFrame = false
    private var firstFrameProbeTask: Task<Void, Never>?
    private var lastPlaybackState: PlayerEnginePlaybackState = .idle
    private var lastError: Error?
    private var prepareContinuation: CheckedContinuation<Void, Error>?
    private var playerPrepareStartTime: CFTimeInterval?
    private var videoGravity: AVLayerVideoGravity = .resizeAspect
    private var lastDiagnostics: PlayerEngineDiagnostics = .empty

    var hasMedia: Bool {
        playerLayer != nil
    }

    var needsMediaRecovery: Bool {
        playerLayer?.state == .error
    }

    var playbackErrorMessage: String? {
        lastError?.localizedDescription
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
        firstFrameProbeTask?.cancel()
        prepareContinuation?.resume(throwing: CancellationError())
        prepareContinuation = nil
        playerLayer?.delegate = nil
        playerLayer?.stop()
    }

    func attachSurface(_ surface: UIView) {
        surfaceView = surface
        installPlayerViewIfNeeded()
    }

    func detachSurface(_ surface: UIView) {
        guard surfaceView === surface else { return }
        playerView?.removeFromSuperview()
        playerView = nil
        surfaceView = nil
    }

    func refreshSurfaceLayout() {
        applyVideoGravity()
    }

    func recoverSurface() {
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
        self.source = source
        wantsPlayback = false
        didReportFirstFrame = false
        firstFrameProbeTask?.cancel()
        firstFrameProbeTask = nil
        lastError = nil
        lastDiagnostics = Self.makeDiagnostics(
            source: source,
            endpoint: nil,
            options: nil
        )
        onLoadingProgressChange?(0.18)
        publishPlaybackState(.preparing)

        let endpoint = try await makePlaybackEndpoint(for: source)
        guard !Task.isCancelled else { throw CancellationError() }

        releaseCurrentPlayer(notifyIdle: false)
        hlsBridge = endpoint.bridge
        mediaTimeOffset = endpoint.mediaTimeOffset

        let options = makeOptions(for: source)
        lastDiagnostics = Self.makeDiagnostics(
            source: source,
            endpoint: endpoint,
            options: options
        )
        PlayerMetricsLog.record(
            .mediaPrepared,
            metricsID: source.metricsID,
            title: source.title,
            message: lastDiagnostics.compactDescription
        )
        let layer = KSPlayerLayer(url: endpoint.url, isAutoPlay: false, options: options, delegate: self)
        layer.player.playbackRate = currentRate
        layer.player.playbackVolume = currentVolume
        layer.player.isMuted = currentMuted
        playerLayer = layer
        configureFirstFrameRenderCallback(for: layer)
        installPlayerViewIfNeeded()
        onLoadingProgressChange?(0.42)
        let prepareStart = CACurrentMediaTime()
        playerPrepareStartTime = prepareStart
        layer.prepareToPlay()
        let elapsedMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: prepareStart)
        PlayerMetricsLog.record(
            .manifestStage,
            metricsID: source.metricsID,
            title: source.title,
            message: "ksPrepareReturn=async \(Int(elapsedMilliseconds.rounded()))ms"
        )
        onLoadingProgressChange?(0.72)
    }

    func play() {
        guard let playerLayer else { return }
        wantsPlayback = true
        lastError = nil
        onPlaybackIntentChange?(true)
        playerLayer.play()
        playerLayer.player.playbackRate = currentRate
        onLoadingProgressChange?(0.98)
        if playerLayer.player.isPlaying || playerLayer.state.isPlaying {
            publishPlaybackState(.playing)
            reportFirstRenderedFrameIfPossible(currentTime: displayTime(fromPlayerTime: playerLayer.player.currentPlaybackTime))
        } else {
            publishPlaybackState(.buffering)
        }
    }

    func pause() {
        wantsPlayback = false
        onPlaybackIntentChange?(false)
        playerLayer?.pause()
        publishPlaybackState(.paused)
    }

    func pauseForNavigation() {
        wantsPlayback = false
        onPlaybackIntentChange?(false)
        playerLayer?.pause()
        publishPlaybackState(.paused)
    }

    func stop() {
        wantsPlayback = false
        completePrepare(.failure(CancellationError()))
        firstFrameProbeTask?.cancel()
        firstFrameProbeTask = nil
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

    func seek(toTime time: TimeInterval) -> TimeInterval? {
        guard let playerLayer else { return nil }
        let target = playerTime(fromDisplayTime: max(time, 0))
        if wantsPlayback {
            publishPlaybackState(.buffering)
        }
        playerLayer.seek(time: target, autoPlay: wantsPlayback) { [weak self] finished in
            guard let self, finished else { return }
            Task { @MainActor in
                if self.wantsPlayback {
                    self.publishPlaybackState(.playing)
                }
            }
        }
        return displayTime(fromPlayerTime: target)
    }

    func seek(toProgress progress: Double, duration: TimeInterval?) -> TimeInterval? {
        guard playerLayer != nil else { return nil }
        let resolvedDuration = resolvedDuration(durationHint: duration)
        guard resolvedDuration > 0 else { return nil }
        return seek(toTime: min(max(progress, 0), 1) * resolvedDuration)
    }

    func seek(by interval: TimeInterval, from currentTime: TimeInterval, duration: TimeInterval?) -> TimeInterval? {
        guard playerLayer != nil else { return nil }
        let resolvedDuration = resolvedDuration(durationHint: duration)
        let target = resolvedDuration > 0
            ? min(max(currentTime + interval, 0), resolvedDuration)
            : max(currentTime + interval, 0)
        return seek(toTime: target)
    }

    func seekAfterUserScrub(toProgress progress: Double, duration: TimeInterval?) async -> TimeInterval? {
        guard let playerLayer else { return nil }
        let resolvedDuration = resolvedDuration(durationHint: duration)
        guard resolvedDuration > 0 else { return nil }
        let target = playerTime(fromDisplayTime: min(max(progress, 0), 1) * resolvedDuration)
        wantsPlayback = true
        if wantsPlayback {
            publishPlaybackState(.buffering)
        }
        let finished = await withCheckedContinuation { continuation in
            playerLayer.seek(time: target, autoPlay: wantsPlayback) { finished in
                continuation.resume(returning: finished)
            }
        }
        return finished ? displayTime(fromPlayerTime: target) : nil
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
        return PlayerPlaybackSnapshot(
            currentTime: currentTime.isFinite ? currentTime : nil,
            duration: duration > 0 ? duration : nil,
            isPlaying: player.isPlaying || playerLayer.state.isPlaying,
            isSeekable: player.seekable || duration > 0,
            bufferedRanges: []
        )
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
        KSOptions.logLevel = .warning
        didConfigureDefaults = true
    }

    private func makePlaybackEndpoint(for source: PlayerStreamSource) async throws -> PlaybackEndpoint {
        guard let videoURL = source.videoURL else {
            throw PlayerEngineError.missingVideoURL
        }

        if source.audioURL != nil {
            let manifest = try await BiliHLSManifestBuilder.make(source: source, shouldValidateHardwareDecoding: false)
            return PlaybackEndpoint(
                url: manifest.masterPlaylistURL,
                bridge: manifest.bridge,
                mediaTimeOffset: manifest.mediaTimeOffset
            )
        }

        return PlaybackEndpoint(url: videoURL, bridge: nil, mediaTimeOffset: 0)
    }

    private func makeOptions(for source: PlayerStreamSource) -> KSOptions {
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
            options.preferredForwardBufferDuration = preferredForwardBufferDuration(for: source, environment: environment)
            options.maxBufferDuration = environment.shouldPreferConservativePlayback ? 3.2 : 4.5
        }
        options.isSecondOpen = true
        options.isAccurateSeek = false
        options.hardwareDecode = true
        options.asynchronousDecompression = Self.shouldUseAsynchronousDecompression(for: source)
        options.registerRemoteControll = true
        return options
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

    private func applyRateAwareBuffering() {
        guard let source, let options = playerLayer?.options else { return }
        options.preferredForwardBufferDuration = preferredForwardBufferDuration(for: source)
        lastDiagnostics.preferredForwardBufferDuration = options.preferredForwardBufferDuration
    }

    private static func shouldUseAsynchronousDecompression(for source: PlayerStreamSource) -> Bool {
        guard let stream = source.videoStream else { return false }
        guard stream.isHardwareDecodingCompatibleVideo else { return false }
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
            hlsVideoVariantCount: source.alternateVideoRenditions.count + (source.videoURL == nil ? 0 : 1),
            hlsVideoVariantQualities: ([source.videoStream?.id] + source.alternateVideoRenditions.map(\.quality))
                .compactMap { $0 },
            preferredForwardBufferDuration: options?.preferredForwardBufferDuration,
            maxBufferDuration: options?.maxBufferDuration,
            asynchronousDecompressionEnabled: options?.asynchronousDecompression == true,
            hardwareDecodeRequested: options?.hardwareDecode == true,
            environmentSummary: PlaybackEnvironment.current.diagnosticSummary
        )
    }

    private func installPlayerViewIfNeeded() {
        guard let surfaceView, let playerView = playerLayer?.player.view else { return }
        if self.playerView !== playerView {
            self.playerView?.removeFromSuperview()
            self.playerView = playerView
        }
        if playerView.superview !== surfaceView {
            playerView.removeFromSuperview()
            playerView.translatesAutoresizingMaskIntoConstraints = false
            playerView.backgroundColor = .black
            playerView.isUserInteractionEnabled = false
            surfaceView.insertSubview(playerView, at: 0)
            NSLayoutConstraint.activate([
                playerView.topAnchor.constraint(equalTo: surfaceView.topAnchor),
                playerView.leadingAnchor.constraint(equalTo: surfaceView.leadingAnchor),
                playerView.bottomAnchor.constraint(equalTo: surfaceView.bottomAnchor),
                playerView.trailingAnchor.constraint(equalTo: surfaceView.trailingAnchor)
            ])
        }
        applyVideoGravity()
    }

    private func applyVideoGravity() {
        let mode: UIView.ContentMode
        switch videoGravity {
        case .resize:
            mode = .scaleToFill
        case .resizeAspectFill:
            mode = .scaleAspectFill
        default:
            mode = .scaleAspectFit
        }
        playerView?.contentMode = mode
        playerLayer?.player.contentMode = mode
    }

    private func releaseCurrentPlayer(notifyIdle: Bool) {
        firstFrameProbeTask?.cancel()
        firstFrameProbeTask = nil
        clearFirstFrameRenderCallback()
        playerLayer?.delegate = nil
        playerLayer?.stop()
        playerLayer = nil
        playerView?.removeFromSuperview()
        playerView = nil
        hlsBridge = nil
        mediaTimeOffset = 0
        playerPrepareStartTime = nil
        didReportFirstFrame = false
        if notifyIdle {
            lastDiagnostics = .empty
        }
        if notifyIdle {
            lastError = nil
            publishPlaybackState(.idle)
        }
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
        onLoadingProgressChange?(1)
        onFirstFrame?(currentTime)
    }

    private func configureFirstFrameRenderCallback(for layer: KSPlayerLayer) {
        _ = layer
    }

    private func clearFirstFrameRenderCallback() {}

    private func recordRenderedFrameStage(currentTime: TimeInterval) {
        guard let source else { return }
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
        if hasRenderedVideoFrame {
            reportFirstFrameIfPossible(currentTime: currentTime)
        } else {
            scheduleFirstFrameProbe(currentTime: currentTime)
        }
    }

    private var requiresRenderedFrameConfirmation: Bool {
        guard let player = playerLayer?.player else { return true }
        return player is KSMEPlayer
    }

    private var hasRenderedVideoFrame: Bool {
        guard let player = playerLayer?.player as? KSMEPlayer else {
            return playerLayer?.player.view != nil
        }
        return player.videoOutput?.pixelBuffer != nil
    }

    private func scheduleFirstFrameProbe(currentTime: TimeInterval) {
        guard firstFrameProbeTask == nil else { return }
        guard let probeLayer = playerLayer else { return }
        firstFrameProbeTask = Task { @MainActor [weak self, weak probeLayer] in
            try? await Task.sleep(nanoseconds: 70_000_000)
            let deadline = CACurrentMediaTime() + 1.15
            var lastKnownTime = currentTime
            var nextReadKick = CACurrentMediaTime()

            while !Task.isCancelled {
                guard let self else { return }
                guard let probeLayer, probeLayer === self.playerLayer, !self.didReportFirstFrame else {
                    self.firstFrameProbeTask = nil
                    return
                }

                let playerTime = self.displayTime(fromPlayerTime: probeLayer.player.currentPlaybackTime)
                if playerTime.isFinite, playerTime >= 0 {
                    lastKnownTime = playerTime
                }

                if self.hasRenderedVideoFrame {
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
                        nextReadKick = now + 0.12
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
        guard layer === playerLayer else { return }
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
            publishPlaybackState(.ready)
            if wantsPlayback {
                layer.play()
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
            lastError = error
            completePrepare(.failure(error))
            publishPlaybackState(.failed(error.localizedDescription))
        }
    }

    func player(layer: KSPlayerLayer, currentTime: TimeInterval, totalTime _: TimeInterval) {
        guard layer === playerLayer else { return }
        if wantsPlayback || layer.player.isPlaying || layer.state.isPlaying {
            publishPlaybackState(.playing)
            reportFirstRenderedFrameIfPossible(currentTime: displayTime(fromPlayerTime: currentTime))
        }
    }

    func player(layer: KSPlayerLayer, finish error: Error?) {
        guard layer === playerLayer else { return }
        if let error {
            lastError = error
            completePrepare(.failure(error))
            publishPlaybackState(.failed(error.localizedDescription))
        } else {
            publishPlaybackState(.ended)
        }
    }

    func player(layer: KSPlayerLayer, bufferedCount _: Int, consumeTime _: TimeInterval) {
        guard layer === playerLayer else { return }
        let bufferedProgress = Double(layer.bufferingProgress) / 100
        let fallbackProgress: Double = layer.state == .buffering ? 0.22 : 0.12
        onLoadingProgressChange?(min(max(bufferedProgress, fallbackProgress), 0.98))
    }
}
