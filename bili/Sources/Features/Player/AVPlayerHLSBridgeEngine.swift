import AVFoundation
import AVKit
import Network
import OSLog
import UIKit

@MainActor
final class AVPlayerHLSBridgeEngine: PlayerRenderingEngine {
    private let player = AVPlayer()
    private var backgroundObserver: Any?
    private var foregroundObserver: Any?
    private var itemEndObserver: Any?
    private var itemFailedObserver: Any?
    private var playerObservers: [NSKeyValueObservation] = []
    private var itemObservers: [NSKeyValueObservation] = []
    private var layerReadyForDisplayObserver: NSKeyValueObservation?
    private var controllerReadyForDisplayObserver: NSKeyValueObservation?
    private var periodicTimeObserver: Any?
    private weak var surfaceView: UIView?
    private weak var playerLayer: AVPlayerLayer?
    private weak var playerViewController: AVPlayerViewController?
    private var playerItem: AVPlayerItem?
    private var source: PlayerStreamSource?
    private var hlsBridge: LocalHLSBridge?
    private var mediaTimeOffset: TimeInterval = 0
    private var retainedAssets: [AVAsset] = []
    private var currentRate: Float = 1
    private var wantsPlayback = false
    private var didReportFirstFrame = false
    private var lastPlaybackState: PlayerEnginePlaybackState = .idle
    private var videoGravity: AVLayerVideoGravity = .resizeAspect

    var hasMedia: Bool {
        player.currentItem != nil
    }

    var needsMediaRecovery: Bool {
        guard let item = player.currentItem else { return false }
        return item.status == .failed
    }

    var playbackErrorMessage: String? {
        player.currentItem?.error?.localizedDescription
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

    var volume: Float {
        player.volume
    }

    var isMuted: Bool {
        player.isMuted
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
        itemObservers.removeAll()
        layerReadyForDisplayObserver = nil
        controllerReadyForDisplayObserver = nil
        if let itemEndObserver {
            NotificationCenter.default.removeObserver(itemEndObserver)
        }
        if let itemFailedObserver {
            NotificationCenter.default.removeObserver(itemFailedObserver)
        }
        if let periodicTimeObserver {
            player.removeTimeObserver(periodicTimeObserver)
        }
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
    }

    func attachSurface(_ surface: UIView) {
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
        removePlayerLayer()
        surfaceView = nil
    }

    func refreshSurfaceLayout() {
        AVPlayerLayoutCoordinator.shared.apply(
            playerLayer: playerLayer,
            in: surfaceView,
            gravity: videoGravity
        )
    }

    func recoverSurface() {
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

    func setViewModel(_: PlayerStateViewModel?) {}

    func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        guard videoGravity != gravity else { return }
        videoGravity = gravity
        playerViewController?.videoGravity = gravity
        playerLayer?.videoGravity = gravity
    }

    func attachNativePlaybackController(_ controller: AVPlayerViewController) {
        if let playerViewController, playerViewController !== controller {
            playerViewController.player = nil
            controllerReadyForDisplayObserver = nil
        }
        playerViewController = controller
        configureNativePlaybackController(controller)
        removePlayerLayer()
    }

    func detachNativePlaybackController(_ controller: AVPlayerViewController) {
        guard playerViewController === controller else { return }
        controller.player = nil
        controllerReadyForDisplayObserver = nil
        playerViewController = nil
    }

    func setHostFullscreenActive(_: Bool, exitTarget _: PlayerHostFullscreenExitTarget?) {}

    func prepare(source: PlayerStreamSource) async throws {
        configureAudioSession()
        self.source = source
        wantsPlayback = false
        didReportFirstFrame = false
        onLoadingProgressChange?(0.18)
        publishPlaybackState(.preparing)
        let prepared = try await Self.makePlayerItem(source: source)
        guard !Task.isCancelled else { return }
        onLoadingProgressChange?(0.58)
        removeCurrentItemObservers()
        playerItem = prepared.item
        hlsBridge = prepared.bridge
        mediaTimeOffset = prepared.bridge?.mediaTimeOffset ?? 0
        retainedAssets = prepared.assets
        let item = prepared.item
        configureStartupBuffering(for: item, source: source)
        player.replaceCurrentItem(with: item)
        player.automaticallyWaitsToMinimizeStalling = false
        observeCurrentItem(item)
        ensurePeriodicTimeObserver()
        if let playerViewController {
            configureNativePlaybackController(playerViewController)
        } else if let surfaceView {
            ensurePlayerLayer(in: surfaceView).player = player
            refreshSurfaceLayout()
        }
        onLoadingProgressChange?(0.86)
        publishPlaybackState(.ready)
    }

    func play() {
        guard player.currentItem != nil else { return }
        configureAudioSession()
        wantsPlayback = true
        player.playImmediately(atRate: currentRate)
        let currentTime = displayTime(fromPlayerTime: player.currentTime().seconds)
        onLoadingProgressChange?(0.98)
        publishPlaybackState(.playing)
        reportFirstFrameIfPossible(currentTime: currentTime)
    }

    func pause() {
        wantsPlayback = false
        player.pause()
        publishPlaybackState(.paused)
    }

    func stop() {
        wantsPlayback = false
        player.pause()
        removeCurrentItemObservers()
        removePeriodicTimeObserver()
        player.replaceCurrentItem(with: nil)
        playerItem = nil
        source = nil
        hlsBridge = nil
        mediaTimeOffset = 0
        retainedAssets = []
        didReportFirstFrame = false
        playerLayer?.player = nil
        layerReadyForDisplayObserver = nil
        publishPlaybackState(.idle)
    }

    func setPlaybackRate(_ rate: Double) {
        currentRate = max(Float(rate), 0.1)
        if player.rate > 0 {
            player.rate = currentRate
        }
    }

    func setVolume(_ volume: Float) {
        player.volume = min(max(volume, 0), 1)
    }

    func setMuted(_ isMuted: Bool) {
        player.isMuted = isMuted
    }

    func seek(toTime time: TimeInterval) -> TimeInterval? {
        guard player.currentItem != nil else { return nil }
        let target = playerTime(fromDisplayTime: max(time, 0))
        if wantsPlayback {
            publishPlaybackState(.buffering)
        }
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        return displayTime(fromPlayerTime: target)
    }

    func seek(toProgress progress: Double, duration: TimeInterval?) -> TimeInterval? {
        guard player.currentItem != nil else { return nil }
        let resolvedDuration = resolvedDuration(durationHint: duration)
        guard resolvedDuration > 0 else { return nil }
        let target = playerTime(fromDisplayTime: min(max(progress, 0), 1) * resolvedDuration)
        if wantsPlayback {
            publishPlaybackState(.buffering)
        }
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        return displayTime(fromPlayerTime: target)
    }

    func seek(by interval: TimeInterval, from currentTime: TimeInterval, duration: TimeInterval?) -> TimeInterval? {
        guard player.currentItem != nil else { return nil }
        let resolvedDuration = resolvedDuration(durationHint: duration)
        let target = resolvedDuration > 0
            ? min(max(currentTime + interval, 0), resolvedDuration)
            : max(currentTime + interval, 0)
        let playerTarget = playerTime(fromDisplayTime: target)
        if wantsPlayback {
            publishPlaybackState(.buffering)
        }
        let targetTime = CMTime(seconds: playerTarget, preferredTimescale: 600)
        player.seek(
            to: targetTime,
            toleranceBefore: CMTime(seconds: 0.35, preferredTimescale: 600),
            toleranceAfter: CMTime(seconds: 0.35, preferredTimescale: 600)
        )
        return displayTime(fromPlayerTime: playerTarget)
    }

    func seekAfterUserScrub(toProgress progress: Double, duration: TimeInterval?) async -> TimeInterval? {
        guard player.currentItem != nil else { return nil }
        let resolvedDuration = resolvedDuration(durationHint: duration)
        guard resolvedDuration > 0 else { return nil }
        let target = playerTime(fromDisplayTime: min(max(progress, 0), 1) * resolvedDuration)
        let targetTime = CMTime(seconds: target, preferredTimescale: 600)
        if wantsPlayback {
            publishPlaybackState(.buffering)
        }
        let finished = await withCheckedContinuation { continuation in
            player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                continuation.resume(returning: finished)
            }
        }
        return finished ? displayTime(fromPlayerTime: target) : nil
    }

    func snapshot(durationHint: TimeInterval?) -> PlayerPlaybackSnapshot {
        let currentSeconds = displayTime(fromPlayerTime: player.currentTime().seconds)
        let durationSeconds = resolvedDuration(durationHint: durationHint)
        let status = player.currentItem?.status
        return PlayerPlaybackSnapshot(
            currentTime: currentSeconds.isFinite && currentSeconds >= 0 ? currentSeconds : nil,
            duration: durationSeconds > 0 ? durationSeconds : durationHint,
            isPlaying: player.rate > 0,
            isSeekable: status == .readyToPlay || (durationHint ?? 0) > 0
        )
    }

    func pictureInPictureContentSource() -> AVPictureInPictureController.ContentSource? {
        guard let playerLayer else { return nil }
        return AVPictureInPictureController.ContentSource(playerLayer: playerLayer)
    }

    func togglePictureInPicture() {}

    func invalidatePictureInPicturePlaybackState() {}

    private func configureNativePlaybackController(_ controller: AVPlayerViewController) {
        if controller.player !== player {
            controller.player = player
        }
        controller.showsPlaybackControls = true
        if controller.videoGravity != videoGravity {
            controller.videoGravity = videoGravity
        }
        controller.allowsPictureInPicturePlayback = AVPictureInPictureController.isPictureInPictureSupported()
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.requiresLinearPlayback = false
        controller.updatesNowPlayingInfoCenter = false
        controller.view.backgroundColor = .black
        observeControllerReadyForDisplay(controller)
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

    private func configureStartupBuffering(for item: AVPlayerItem, source: PlayerStreamSource) {
        let environment = PlaybackEnvironment.current
        let bufferDuration = source.audioURL == nil
            ? environment.preferredForwardBufferDuration
            : min(environment.preferredForwardBufferDuration, 0.02)
        item.preferredForwardBufferDuration = bufferDuration
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        if let bandwidth = source.videoStream?.bandwidth, bandwidth > 0 {
            item.preferredPeakBitRate = Double(bandwidth) * 1.18
        }
        if source.audioURL == nil {
            item.preferredPeakBitRate = 0
        }
    }

    private func observeAppLifecycle() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.configureAudioSession()
                if self.wantsPlayback {
                    self.player.playImmediately(atRate: self.currentRate)
                }
            }
        }

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recoverSurface()
            }
        }
    }

    private func observePlayerState() {
        playerObservers = [
            player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
                let status = player.timeControlStatus
                Task { @MainActor [weak self] in
                    self?.handleTimeControlStatus(status)
                }
            },
            player.observe(\.rate, options: [.new]) { [weak self] player, _ in
                let rate = player.rate
                let itemStatus = player.currentItem?.status
                let timeControlStatus = player.timeControlStatus
                let currentSeconds = player.currentTime().seconds
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if rate > 0 {
                        self.updatePlaybackIntent(true)
                        self.publishPlaybackState(.playing)
                        self.reportFirstFrameIfPossible(
                            currentTime: self.displayTime(fromPlayerTime: currentSeconds)
                        )
                    } else if timeControlStatus == .paused,
                              itemStatus == .readyToPlay {
                        self.updatePlaybackIntent(false)
                        self.publishPlaybackState(.paused)
                    } else if self.wantsPlayback,
                              itemStatus == .readyToPlay,
                              timeControlStatus == .waitingToPlayAtSpecifiedRate {
                        self.publishPlaybackState(.buffering)
                    }
                }
            }
        ]
    }

    private func observeCurrentItem(_ item: AVPlayerItem) {
        itemObservers = [
            item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                let status = item.status
                let errorMessage = item.error?.localizedDescription
                Task { @MainActor [weak self] in
                    switch status {
                    case .readyToPlay:
                        self?.publishPlaybackState(.ready)
                    case .failed:
                        self?.publishPlaybackState(.failed(errorMessage))
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
                    guard let self, self.wantsPlayback else { return }
                    if isPlaybackLikelyToKeepUp {
                        self.player.playImmediately(atRate: self.currentRate)
                        self.publishPlaybackState(.playing)
                    } else {
                        self.publishPlaybackState(.buffering)
                    }
                }
            },
            item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
                let isPlaybackBufferEmpty = item.isPlaybackBufferEmpty
                Task { @MainActor [weak self] in
                    guard let self, self.wantsPlayback, isPlaybackBufferEmpty else { return }
                    self.publishPlaybackState(.buffering)
                }
            }
        ]

        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.wantsPlayback = false
                self?.publishPlaybackState(.ended)
            }
        }

        itemFailedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let errorMessage = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                .localizedDescription
            Task { @MainActor [weak self] in
                self?.publishPlaybackState(.failed(errorMessage))
            }
        }
    }

    private func observeLayerReadyForDisplay(_ layer: AVPlayerLayer) {
        layerReadyForDisplayObserver = layer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            Task { @MainActor [weak self] in
                self?.reportFirstFrameIfPossible()
            }
        }
    }

    private func observeControllerReadyForDisplay(_ controller: AVPlayerViewController) {
        guard controllerReadyForDisplayObserver == nil else { return }
        controllerReadyForDisplayObserver = controller.observe(\.isReadyForDisplay, options: [.new]) { [weak self] controller, _ in
            guard controller.isReadyForDisplay else { return }
            Task { @MainActor [weak self] in
                self?.reportFirstFrameIfPossible()
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
                guard let self else { return }
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
    }

    private func handleTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
        guard player.currentItem != nil else { return }
        switch status {
        case .paused:
            publishPlaybackState(wantsPlayback ? .buffering : .paused)
        case .waitingToPlayAtSpecifiedRate:
            if wantsPlayback {
                publishPlaybackState(.buffering)
            }
        case .playing:
            updatePlaybackIntent(true)
            publishPlaybackState(.playing)
            reportFirstFrameIfPossible()
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
        guard !didReportFirstFrame else { return }
        guard playerViewController?.isReadyForDisplay == true
            || playerLayer?.isReadyForDisplay == true
            || player.rate > 0
        else { return }
        didReportFirstFrame = true
        let resolvedTime = currentTime ?? displayTime(fromPlayerTime: player.currentTime().seconds)
        onFirstFrame?(resolvedTime.isFinite ? max(resolvedTime, 0) : 0)
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

        if let audioURL = source.audioURL {
            let hlsBridge = try? await LocalHLSBridge.make(
                videoTrack: Self.hlsBridgeTrack(
                    url: videoURL,
                    stream: source.videoStream,
                    mediaType: .video,
                    dynamicRange: source.dynamicRange
                ),
                audioTrack: Self.hlsBridgeTrack(
                    url: audioURL,
                    stream: source.audioStream,
                    mediaType: .audio
                ),
                durationHint: source.durationHint,
                headers: headers,
                metricsID: source.metricsID
            )
            if let hlsBridge {
                let asset = AVURLAsset(
                    url: hlsBridge.masterPlaylistURL,
                    options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
                )
                let item = AVPlayerItem(asset: asset)
                item.preferredForwardBufferDuration = 2
                return PreparedPlayerItem(item: item, bridge: hlsBridge, assets: [asset])
            }

            let composition = try await makeComposition(videoURL: videoURL, audioURL: audioURL, headers: headers)
            let item = AVPlayerItem(asset: composition)
            item.preferredForwardBufferDuration = 2
            return PreparedPlayerItem(item: item, bridge: nil, assets: [composition])
        }

        let asset = AVURLAsset(url: videoURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 2
        return PreparedPlayerItem(item: item, bridge: nil, assets: [asset])
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
        dynamicRange: BiliVideoDynamicRange = .sdr
    ) -> HLSBridgeTrack {
        HLSBridgeTrack(
            url: url,
            fallbackURLs: stream?.backupPlayURLs ?? [],
            stream: stream,
            mediaType: mediaType,
            dynamicRange: dynamicRange
        )
    }
}

private struct PreparedPlayerItem {
    let item: AVPlayerItem
    let bridge: LocalHLSBridge?
    let assets: [AVAsset]
}

struct LocalHLSBridge: Sendable {
    private nonisolated static let timelineProbeLength: Int64 = 128 * 1024
    private nonisolated static let maxCombinedBootstrapRangeLength: Int64 = 512 * 1024

    let masterPlaylistURL: URL
    let mediaTimeOffset: TimeInterval
    let videoClockDelay: TimeInterval
    private let server: LocalHLSProxyServer

    nonisolated func updateMetricsID(_ metricsID: String?) {
        server.updateMetricsID(metricsID)
    }

    nonisolated static func make(
        videoTrack: HLSBridgeTrack,
        audioTrack: HLSBridgeTrack,
        durationHint: TimeInterval?,
        headers: [String: String],
        metricsID: String? = nil
    ) async throws -> LocalHLSBridge {
        let start = CACurrentMediaTime()
        PlayerMetricsLog.logger.info(
            "hlsBridgeMakeStart videoQ=\(videoTrack.stream?.id ?? -1, privacy: .public) audioBandwidth=\(audioTrack.stream?.bandwidth ?? 0, privacy: .public)"
        )
        let cacheKey = bridgeCacheKey(videoTrack: videoTrack, audioTrack: audioTrack, headers: headers)
        guard let cacheKey else {
            let bridge = try await build(
                videoTrack: videoTrack,
                audioTrack: audioTrack,
                durationHint: durationHint,
                headers: headers,
                metricsID: metricsID
            )
            PlayerMetricsLog.logger.info(
                "hlsBridgeMakeReady cacheable=false elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: start), format: .fixed(precision: 1), privacy: .public)"
            )
            return bridge
        }

        let bridge = try await LocalHLSBridgeInstanceCache.shared.cachedOrBuild(for: cacheKey) {
            try await build(
                videoTrack: videoTrack,
                audioTrack: audioTrack,
                durationHint: durationHint,
                headers: headers,
                metricsID: metricsID
            )
        }
        bridge.updateMetricsID(metricsID)
        PlayerMetricsLog.logger.info(
            "hlsBridgeMakeReady cacheable=true elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: start), format: .fixed(precision: 1), privacy: .public)"
        )
        return bridge
    }

    private nonisolated static func build(
        videoTrack: HLSBridgeTrack,
        audioTrack: HLSBridgeTrack,
        durationHint: TimeInterval?,
        headers: [String: String],
        metricsID: String?
    ) async throws -> LocalHLSBridge {
        let start = CACurrentMediaTime()
        PlayerMetricsLog.logger.info("hlsBridgeBuildStart")
        async let videoRenditionTask = makeRendition(for: videoTrack, durationHint: durationHint, headers: headers)
        async let audioRenditionTask = makeRendition(for: audioTrack, durationHint: durationHint, headers: headers)
        let (videoRendition, audioRendition) = try await (videoRenditionTask, audioRenditionTask)
        PlayerMetricsLog.logger.info(
            "hlsBridgeRenditionsReady elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: start), format: .fixed(precision: 1), privacy: .public) videoRefs=\(videoRendition.references.count, privacy: .public) audioRefs=\(audioRendition.references.count, privacy: .public)"
        )

        let server = try LocalHLSProxyServer.make(headers: headers, metricsID: metricsID)
        let baseURL = server.baseURL
        let videoPlaylistURL = baseURL.appendingPathComponent("video.m3u8")
        let audioPlaylistURL = baseURL.appendingPathComponent("audio.m3u8")
        let masterPlaylistURL = baseURL.appendingPathComponent("master.m3u8")
        let videoPlaylist = videoRendition.playlist(baseURL: baseURL, routePrefix: "video")
        let audioPlaylist = audioRendition.playlist(baseURL: baseURL, routePrefix: "audio")
        let shouldAdvertiseDynamicRange = videoRendition.dynamicRange != .dolbyVision
        let videoRangeAttribute: String
        if shouldAdvertiseDynamicRange, let videoRange = videoRendition.dynamicRange.hlsVideoRangeAttribute {
            videoRangeAttribute = ",VIDEO-RANGE=\(videoRange)"
        } else {
            videoRangeAttribute = ""
        }
        let supplementalCodecAttribute = shouldAdvertiseDynamicRange ? videoRendition.hlsSupplementalCodecAttribute : ""
        let masterPlaylistVersion = supplementalCodecAttribute.isEmpty
            ? (videoRangeAttribute.isEmpty ? 7 : 8)
            : 10
        let resolutionAttribute = videoRendition.hlsResolutionAttribute
        let masterPlaylist = """
        #EXTM3U
        #EXT-X-VERSION:\(masterPlaylistVersion)
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="audio",DEFAULT=YES,AUTOSELECT=YES,URI="\(audioPlaylistURL.absoluteString)"
        #EXT-X-STREAM-INF:BANDWIDTH=\(videoRendition.bandwidth),CODECS="\(videoRendition.codec),\(audioRendition.codec)",AUDIO="audio"\(resolutionAttribute)\(videoRangeAttribute)\(supplementalCodecAttribute)
        \(videoPlaylistURL.absoluteString)
        """

        var routes: [String: HLSProxyRoute] = [
            "/master.m3u8": .data(Data(masterPlaylist.utf8), contentType: "application/vnd.apple.mpegurl"),
            "/video.m3u8": .data(Data(videoPlaylist.utf8), contentType: "application/vnd.apple.mpegurl"),
            "/audio.m3u8": .data(Data(audioPlaylist.utf8), contentType: "application/vnd.apple.mpegurl")
        ]
        videoRendition.registerRoutes(routePrefix: "video", into: &routes)
        audioRendition.registerRoutes(routePrefix: "audio", into: &routes)
        server.updateRoutes(routes)
        try await server.start()
        warmStartupRanges(
            videoRendition: videoRendition,
            audioRendition: audioRendition,
            headers: headers
        )
        PlayerMetricsLog.logger.info(
            "hlsBridgeServerReady elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: start), format: .fixed(precision: 1), privacy: .public) dynamicRange=\(videoRendition.dynamicRange.rawValue, privacy: .public) codec=\(videoRendition.codec, privacy: .public) version=\(masterPlaylistVersion, privacy: .public) routes=\(routes.count, privacy: .public) supplemental=\((!supplementalCodecAttribute.isEmpty), privacy: .public)"
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
            server: server
        )
    }

    private nonisolated static func normalizedVideoClockDelay(audioStart: TimeInterval, videoStart: TimeInterval) -> TimeInterval {
        guard audioStart.isFinite, videoStart.isFinite else { return 0 }
        let delay = audioStart - videoStart
        guard delay.isFinite, abs(delay) <= 60 else { return 0 }
        return abs(delay) < 0.001 ? 0 : delay
    }

    private nonisolated static func warmStartupRanges(
        videoRendition: HLSRendition,
        audioRendition: HLSRendition,
        headers: [String: String]
    ) {
        Task.detached(priority: .userInitiated) {
            async let videoStartup: Void = warmRanges(
                videoRendition.references.prefix(2).map(\.range),
                from: [videoRendition.sourceURL] + videoRendition.fallbackSourceURLs,
                headers: headers,
                strategy: .fastFallback
            )
            async let audioStartup: Void = warmRanges(
                audioRendition.references.prefix(1).map(\.range),
                from: [audioRendition.sourceURL] + audioRendition.fallbackSourceURLs,
                headers: headers,
                strategy: .fastFallback
            )
            _ = await (videoStartup, audioStartup)
            PlayerMetricsLog.logger.info(
                "hlsBridgeWarmupStartup videoRefs=\(videoRendition.references.count, privacy: .public) audioRefs=\(audioRendition.references.count, privacy: .public)"
            )
        }
    }

    private nonisolated static func warmRanges(
        _ ranges: [HTTPByteRange],
        from urls: [URL],
        headers: [String: String],
        strategy: HLSByteRangeFetchStrategy
    ) async {
        await withTaskGroup(of: Void.self) { group in
            for (index, range) in ranges.enumerated() {
                group.addTask {
                    if index > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(index) * 180_000_000)
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
        headers: [String: String]
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
        let rendition = try await HLSRenditionCache.shared.cachedOrBuild(
            for: renditionCacheKey(for: track, initialization: initialization, indexRange: indexRange)
        ) {
            let fetchStart = CACurrentMediaTime()
            let sourceURLs = [track.url] + track.fallbackURLs
            let (indexData, initializationData, fetchMode) = try await fetchBootstrapRanges(
                initialization: initialization,
                indexRange: indexRange,
                from: sourceURLs,
                headers: headers
            )
            PlayerMetricsLog.logger.info(
                "hlsBridgeIndexFetched media=\(mediaType, privacy: .public) mode=\(fetchMode, privacy: .public) bytes=\(indexData.count, privacy: .public) initBytes=\(initializationData.count, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: fetchStart), format: .fixed(precision: 1), privacy: .public)"
            )
            let parseStart = CACurrentMediaTime()
            let references = try SIDXParser.parseReferences(from: indexData, sidxStartOffset: indexRange.start)
            guard !references.isEmpty else {
                throw PlayerEngineError.unsupportedMedia
            }
            let resolvedTimelineOffset = await resolvedTimelineOffset(
                for: track,
                references: references,
                headers: headers
            )
            PlayerMetricsLog.logger.info(
                "hlsBridgeIndexParsed media=\(mediaType, privacy: .public) refs=\(references.count, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: parseStart), format: .fixed(precision: 1), privacy: .public)"
            )
            return makeRendition(
                for: track,
                initialization: initialization,
                initializationData: initializationData,
                references: references,
                durationHint: durationHint,
                timelineOffsetOverride: resolvedTimelineOffset
            )
        }
        PlayerMetricsLog.logger.info(
            "hlsBridgeRenditionReady media=\(mediaType, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: start), format: .fixed(precision: 1), privacy: .public)"
        )
        return rendition
    }

    private nonisolated static func fetchBootstrapRanges(
        initialization: HTTPByteRange,
        indexRange: HTTPByteRange,
        from urls: [URL],
        headers: [String: String]
    ) async throws -> (indexData: Data, initializationData: Data, mode: String) {
        if let combinedRange = combinedBootstrapRange(initialization: initialization, indexRange: indexRange) {
            do {
                let combinedData = try await fetchByteRange(
                    combinedRange,
                    from: urls,
                    headers: headers,
                    strategy: .fastFallback
                )
                let initializationData = try sliceData(combinedData, sourceRange: combinedRange, subrange: initialization)
                let indexData = try sliceData(combinedData, sourceRange: combinedRange, subrange: indexRange)
                return (indexData, initializationData, "combined")
            } catch {
                PlayerMetricsLog.logger.info(
                    "hlsBridgeBootstrapCombinedFallback range=\(combinedRange.start, privacy: .public)-\(combinedRange.endInclusive, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
            }
        }

        async let indexDataTask: Data = fetchByteRange(indexRange, from: urls, headers: headers, strategy: .fastFallback)
        async let initializationDataTask: Data = fetchByteRange(initialization, from: urls, headers: headers, strategy: .fastFallback)
        let (indexData, initializationData) = try await (indexDataTask, initializationDataTask)
        return (indexData, initializationData, "split")
    }

    private nonisolated static func combinedBootstrapRange(
        initialization: HTTPByteRange,
        indexRange: HTTPByteRange
    ) -> HTTPByteRange? {
        let lowerBound = min(initialization.start, indexRange.start)
        let upperBound = max(initialization.endInclusive, indexRange.endInclusive)
        let combined = HTTPByteRange(start: lowerBound, endInclusive: upperBound)
        guard combined.length <= maxCombinedBootstrapRangeLength else { return nil }
        let rangesTouchOrOverlap = initialization.endInclusive + 1 >= indexRange.start
            && indexRange.endInclusive + 1 >= initialization.start
        return rangesTouchOrOverlap ? combined : nil
    }

    private nonisolated static func sliceData(
        _ data: Data,
        sourceRange: HTTPByteRange,
        subrange: HTTPByteRange
    ) throws -> Data {
        let lowerOffset = subrange.start - sourceRange.start
        let upperOffset = subrange.endInclusive - sourceRange.start
        guard lowerOffset >= 0,
              upperOffset >= lowerOffset,
              let lowerBound = Int(exactly: lowerOffset),
              let upperBoundInclusive = Int(exactly: upperOffset),
              upperBoundInclusive < data.count
        else {
            throw PlayerEngineError.unsupportedMedia
        }
        return data.subdata(in: lowerBound..<(upperBoundInclusive + 1))
    }

    fileprivate nonisolated static func fetchByteRange(
        _ range: HTTPByteRange,
        from url: URL,
        headers: [String: String]
    ) async throws -> Data {
        try await VideoRangeCache.shared.cachedOrFetch(url: url, range: range) {
            try await fetchRemoteByteRangeWithRetry(range, from: url, headers: headers)
        }
    }

    fileprivate nonisolated static func fetchByteRange(
        _ range: HTTPByteRange,
        from urls: [URL],
        headers: [String: String],
        strategy: HLSByteRangeFetchStrategy = .sequential
    ) async throws -> Data {
        let canonicalSourceURLs = urls.removingDuplicates()
        guard let primaryURL = canonicalSourceURLs.first else {
            throw PlayerEngineError.unsupportedMedia
        }
        let sourceURLs = await HLSSourcePreferenceCache.shared.preferredURLs(for: canonicalSourceURLs)
        guard strategy.isFastFallback, sourceURLs.count > 1 else {
            return try await fetchByteRangeSequential(
                range,
                from: sourceURLs,
                primaryURL: primaryURL,
                headers: headers
            )
        }

        return try await fetchByteRangeFastFallback(
            range,
            from: sourceURLs,
            primaryURL: primaryURL,
            headers: headers
        )
    }

    private nonisolated static func fetchByteRangeSequential(
        _ range: HTTPByteRange,
        from sourceURLs: [URL],
        primaryURL: URL,
        headers: [String: String]
    ) async throws -> Data {
        guard !sourceURLs.isEmpty else {
            throw PlayerEngineError.unsupportedMedia
        }
        var lastError: Error?
        for (index, url) in sourceURLs.enumerated() {
            let fetchStart = CACurrentMediaTime()
            do {
                let data = try await fetchByteRange(range, from: url, headers: headers)
                await HLSSourcePreferenceCache.shared.recordResult(
                    url: url,
                    for: sourceURLs,
                    elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: fetchStart),
                    bytes: Int64(data.count),
                    succeeded: true
                )
                if index > 0 {
                    await HLSSourcePreferenceCache.shared.recordPreferredURL(url, for: sourceURLs)
                    await VideoRangeCache.shared.store(data, url: primaryURL, range: range)
                    PlayerMetricsLog.logger.info(
                        "hlsBridgeByteRangeFallbackSuccess fallbackIndex=\(index, privacy: .public) range=\(range.start, privacy: .public)-\(range.endInclusive, privacy: .public)"
                    )
                }
                return data
            } catch {
                await HLSSourcePreferenceCache.shared.recordResult(
                    url: url,
                    for: sourceURLs,
                    elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: fetchStart),
                    bytes: 0,
                    succeeded: false
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
        headers: [String: String]
    ) async throws -> Data {
        let result: Result<(index: Int, data: Data), Error> = await withTaskGroup(of: Result<(index: Int, data: Data), Error>.self) { group in
            for (index, url) in sourceURLs.enumerated() {
                group.addTask(priority: .userInitiated) {
                    let fetchStart = CACurrentMediaTime()
                    do {
                        if index > 0 {
                            let delay = UInt64(55_000_000 + max(index - 1, 0) * 45_000_000)
                            try await Task.sleep(nanoseconds: delay)
                        }
                        let data = try await fetchByteRange(range, from: url, headers: headers)
                        await HLSSourcePreferenceCache.shared.recordResult(
                            url: url,
                            for: sourceURLs,
                            elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: fetchStart),
                            bytes: Int64(data.count),
                            succeeded: true
                        )
                        return .success((index, data))
                    } catch {
                        await HLSSourcePreferenceCache.shared.recordResult(
                            url: url,
                            for: sourceURLs,
                            elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: fetchStart),
                            bytes: 0,
                            succeeded: false
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
                    return Result<(index: Int, data: Data), Error>.success(payload)
                case let .failure(error):
                    lastError = error
                }
            }
            return .failure(lastError ?? PlayerEngineError.unsupportedMedia)
        }

        switch result {
        case let .success(payload):
            if let preferredURL = sourceURLs[safe: payload.index] {
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
        headers: [String: String]
    ) async throws -> Data {
        var lastError: Error?
        for attempt in 0..<2 {
            do {
                return try await fetchRemoteByteRange(range, from: url, headers: headers)
            } catch {
                lastError = error
                guard attempt < 1, !Task.isCancelled else { break }
                PlayerMetricsLog.logger.info(
                    "hlsBridgeByteRangeRetry attempt=\(attempt + 1, privacy: .public) range=\(range.start, privacy: .public)-\(range.endInclusive, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                try? await Task.sleep(nanoseconds: 90_000_000)
            }
        }
        throw lastError ?? PlayerEngineError.unsupportedMedia
    }

    fileprivate nonisolated static func fetchRemoteByteRange(
        _ range: HTTPByteRange,
        from url: URL,
        headers: [String: String]
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = range.length > 1_500_000 ? 2.4 : 1.6
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.setValue("bytes=\(range.start)-\(range.endInclusive)", forHTTPHeaderField: "Range")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            PlayerMetricsLog.logger.error(
                "hlsBridgeByteRangeHTTPError status=\(httpResponse.statusCode, privacy: .public) range=\(range.start, privacy: .public)-\(range.endInclusive, privacy: .public) url=\(url.absoluteString, privacy: .private)"
            )
            throw PlayerEngineError.unsupportedMedia
        }
        return data
    }

    @discardableResult
    nonisolated static func warmup(
        videoTrack: HLSBridgeTrack,
        audioTrack: HLSBridgeTrack?,
        headers: [String: String]
    ) async -> Bool {
        async let videoWarmup: Bool = warmup(track: videoTrack, headers: headers)
        if let audioTrack {
            async let audioWarmup: Bool = warmup(track: audioTrack, headers: headers)
            let results = await (videoWarmup, audioWarmup)
            let didWarm = results.0 || results.1
            if didWarm {
                _ = try? await make(
                    videoTrack: videoTrack,
                    audioTrack: audioTrack,
                    durationHint: nil,
                    headers: headers
                )
            }
            return didWarm
        } else {
            return await videoWarmup
        }
    }

    nonisolated static func clearWarmupCache() async {
        await LocalHLSBridgeInstanceCache.shared.removeAll()
    }

    private nonisolated static func warmup(track: HLSBridgeTrack, headers: [String: String]) async -> Bool {
        guard let segmentBase = track.stream?.segmentBase,
              let initialization = segmentBase.initializationByteRange,
              let indexRange = segmentBase.indexByteRange
        else { return false }

        do {
            let sourceURLs = [track.url] + track.fallbackURLs
            async let initializationData: Data = fetchByteRange(initialization, from: sourceURLs, headers: headers, strategy: .fastFallback)
            let rendition = try await HLSRenditionCache.shared.cachedOrBuild(
                for: renditionCacheKey(for: track, initialization: initialization, indexRange: indexRange)
            ) {
                async let indexDataTask: Data = fetchByteRange(indexRange, from: sourceURLs, headers: headers, strategy: .fastFallback)
                async let initializationDataTask: Data = fetchByteRange(initialization, from: sourceURLs, headers: headers, strategy: .fastFallback)
                let (indexData, initializationData) = try await (indexDataTask, initializationDataTask)
                let references = try SIDXParser.parseReferences(from: indexData, sidxStartOffset: indexRange.start)
                guard !references.isEmpty else {
                    throw PlayerEngineError.unsupportedMedia
                }
                let resolvedTimelineOffset = await resolvedTimelineOffset(
                    for: track,
                    references: references,
                    headers: headers
                )
                return makeRendition(
                    for: track,
                    initialization: initialization,
                    initializationData: initializationData,
                    references: references,
                    durationHint: nil,
                    timelineOffsetOverride: resolvedTimelineOffset
                )
            }
            _ = try await initializationData
            if let firstReference = rendition.references.first {
                _ = try? await fetchByteRange(
                    startupProbeRange(for: firstReference.range),
                    from: [track.url] + track.fallbackURLs,
                    headers: headers,
                    strategy: .fastFallback
                )
            }
            return true
        } catch {
            return false
        }
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

    private nonisolated static func resolvedTimelineOffset(
        for track: HLSBridgeTrack,
        references: [SIDXParser.Reference],
        headers: [String: String]
    ) async -> HLSRenditionTimelineOffset? {
        guard let firstReference = references.first else { return nil }
        let sourceURLs = [track.url] + track.fallbackURLs
        do {
            let probeRange = startupProbeRange(for: firstReference.range)
            let firstSegmentData = try await fetchByteRange(
                probeRange,
                from: sourceURLs,
                headers: headers,
                strategy: .fastFallback
            )
            guard let timing = FMP4TimelineNormalizer.initialTiming(in: firstSegmentData) else {
                return nil
            }
            if timing.baseMediaDecodeTimeTicks != firstReference.startTimeTicks {
                PlayerMetricsLog.logger.info(
                    "hlsBridgeTimelineOffset media=\(track.mediaType.logLabel, privacy: .public) sidxPts=\(firstReference.startTimeTicks, privacy: .public) tfdt=\(timing.baseMediaDecodeTimeTicks, privacy: .public)"
                )
            }
            return HLSRenditionTimelineOffset(
                baseMediaDecodeTimeTicks: timing.baseMediaDecodeTimeTicks
            )
        } catch {
            PlayerMetricsLog.logger.info(
                "hlsBridgeTFDTOffsetFallback media=\(track.mediaType.logLabel, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private nonisolated static func startupProbeRange(for range: HTTPByteRange) -> HTTPByteRange {
        let endInclusive = min(
            range.endInclusive,
            range.start + max(Self.timelineProbeLength, 1) - 1
        )
        return HTTPByteRange(start: range.start, endInclusive: endInclusive)
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
            "timeline-v6-tfdt-only",
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
        videoTrack: HLSBridgeTrack,
        audioTrack: HLSBridgeTrack,
        headers: [String: String]
    ) -> String? {
        guard let videoKey = bridgeTrackCacheKey(for: videoTrack),
              let audioKey = bridgeTrackCacheKey(for: audioTrack)
        else { return nil }
        let headerKey = headers
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        return [videoKey, audioKey, headerKey].joined(separator: "||")
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
                return "avc1.640028"
            }
        }
        return codec
    }

    fileprivate nonisolated static func formatDuration(_ duration: TimeInterval) -> String {
        String(format: "%.6f", max(duration, 0.001))
    }
}

struct HLSBridgeTrack: Sendable {
    enum MediaType: Sendable {
        case video
        case audio

        nonisolated var logLabel: String {
            switch self {
            case .video:
                "video"
            case .audio:
                "audio"
            }
        }
    }

    let url: URL
    let fallbackURLs: [URL]
    let stream: DASHStream?
    let mediaType: MediaType
    let dynamicRange: BiliVideoDynamicRange

    nonisolated init(
        url: URL,
        fallbackURLs: [URL] = [],
        stream: DASHStream?,
        mediaType: MediaType,
        dynamicRange: BiliVideoDynamicRange = .sdr
    ) {
        self.url = url
        self.fallbackURLs = fallbackURLs.filter { $0 != url }
        self.stream = stream
        self.mediaType = mediaType
        self.dynamicRange = switch mediaType {
        case .video:
            dynamicRange
        case .audio:
            .sdr
        }
    }

    nonisolated init(
        stream: DASHStream,
        mediaType: MediaType,
        dynamicRange: BiliVideoDynamicRange = .sdr
    ) throws {
        guard let url = stream.playURL else {
            throw PlayerEngineError.missingVideoURL
        }
        self.init(
            url: url,
            fallbackURLs: stream.backupPlayURLs,
            stream: stream,
            mediaType: mediaType,
            dynamicRange: dynamicRange
        )
    }

    nonisolated var cacheIdentity: String {
        ([url] + fallbackURLs)
            .map(\.absoluteString)
            .joined(separator: ",")
    }
}

private struct HLSRendition: Sendable {
    let sourceURL: URL
    let fallbackSourceURLs: [URL]
    let mediaType: HLSBridgeTrack.MediaType
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

    nonisolated var hlsSupplementalCodecAttribute: String {
        guard dynamicRange == .dolbyVision,
              !codec.localizedCaseInsensitiveContains("dvh"),
              !codec.localizedCaseInsensitiveContains("dvhe")
        else { return "" }

        return ",SUPPLEMENTAL-CODECS=\"dvh1.08.06/db1p\""
    }

    nonisolated var hlsResolutionAttribute: String {
        guard mediaType == .video,
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

        let segmentTransform = HLSMediaSegmentTransform(
            baseMediaDecodeTimeOffset: baseMediaDecodeTimeOffsetTicks
        )
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

    nonisolated private func mediaURL(baseURL: URL, routePrefix: String, component: String) -> URL {
        baseURL
            .appendingPathComponent("media")
            .appendingPathComponent(routePrefix)
            .appendingPathComponent(component)
    }
}

private actor HLSRenditionCache {
    static let shared = HLSRenditionCache()

    private let ttl: TimeInterval = 180
    private let maxCount = 24
    private var cache: [String: Entry] = [:]
    private var pendingBuilds: [String: Task<HLSRendition, Error>] = [:]

    func cachedOrBuild(
        for key: String,
        builder: @escaping @Sendable () async throws -> HLSRendition
    ) async throws -> HLSRendition {
        trimExpired()
        if let entry = cache[key] {
            return entry.rendition
        }
        if let pendingBuild = pendingBuilds[key] {
            return try await pendingBuild.value
        }

        let pendingBuild = Task.detached(priority: .userInitiated) {
            try await builder()
        }
        pendingBuilds[key] = pendingBuild
        do {
            let rendition = try await pendingBuild.value
            pendingBuilds[key] = nil
            cache[key] = Entry(rendition: rendition, date: Date())
            trimIfNeeded()
            return rendition
        } catch {
            pendingBuilds[key] = nil
            throw error
        }
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
}

private actor LocalHLSBridgeInstanceCache {
    static let shared = LocalHLSBridgeInstanceCache()

    private let logger = Logger(subsystem: "cc.bili", category: "PlayerMetrics")
    private let ttl: TimeInterval = 90
    private let maxCount = 8
    private var cache: [String: Entry] = [:]
    private var pendingBuilds: [String: Task<LocalHLSBridge, Error>] = [:]

    func cachedOrBuild(
        for key: String,
        builder: @escaping @Sendable () async throws -> LocalHLSBridge
    ) async throws -> LocalHLSBridge {
        trimExpired()
        if let entry = cache[key] {
            cache[key] = Entry(bridge: entry.bridge, date: Date())
            logger.info("hlsBridgeCache hit")
            return entry.bridge
        }
        if let pendingBuild = pendingBuilds[key] {
            logger.info("hlsBridgeCache pending")
            return try await pendingBuild.value
        }

        logger.info("hlsBridgeCache miss")
        let pendingBuild = Task.detached(priority: .userInitiated) {
            try await builder()
        }
        pendingBuilds[key] = pendingBuild
        do {
            let bridge = try await pendingBuild.value
            pendingBuilds[key] = nil
            cache[key] = Entry(bridge: bridge, date: Date())
            trimIfNeeded()
            return bridge
        } catch {
            pendingBuilds[key] = nil
            throw error
        }
    }

    func removeAll() {
        pendingBuilds.values.forEach { $0.cancel() }
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
}

private actor HLSSourcePreferenceCache {
    static let shared = HLSSourcePreferenceCache()

    private let ttl: TimeInterval = 24 * 60 * 60
    private let maxCount = 256
    private let maxHostScoreCount = 192
    private let fileManager = FileManager.default
    private let storeURL: URL
    private let hostScoreStoreURL: URL
    private var entries: [String: Entry] = [:]
    private var hostScores: [String: HostScore] = [:]
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
            return scoredURLs
                .sorted { lhs, rhs in
                    switch (lhs.score, rhs.score) {
                    case let (left?, right?):
                        if abs(left - right) > 0.01 {
                            return left < right
                        }
                        return lhs.index < rhs.index
                    case (.some, .none):
                        return true
                    case (.none, .some):
                        return false
                    case (.none, .none):
                        return lhs.index < rhs.index
                    }
                }
                .map(\.url)
        }
        guard let preferredURL = preferredURL(for: urls),
              let preferredIndex = urls.firstIndex(of: preferredURL),
              preferredIndex > 0
        else {
            return urls
        }
        var reordered = urls
        let preferred = reordered.remove(at: preferredIndex)
        reordered.insert(preferred, at: 0)
        return reordered
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
        succeeded: Bool
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
        hostScores[host] = score
        if succeeded {
            entries[exactCacheKey(for: urls)] = Entry(preferredURLString: url.absoluteString, date: now)
            if let hostKey = hostCacheKey(for: urls) {
                entries[hostKey] = Entry(preferredURLString: url.absoluteString, date: now)
            }
        }
        trimExpired()
        trimIfNeeded()
        trimHostScoresIfNeeded()
        persistDirty = true
        schedulePersist()
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

    private func trimExpired() {
        let expiry = Date().addingTimeInterval(-ttl)
        entries = entries.filter { $0.value.date >= expiry }
        hostScores = hostScores.filter { $0.value.date >= expiry }
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

private enum HLSRemoteRangeStreamer {
    nonisolated static func stream(
        range: HTTPByteRange,
        from url: URL,
        headers: [String: String],
        responseHeader: Data,
        connection: NWConnection,
        cacheLimit: Int64,
        startupChunkSize: Int = 32 * 1024,
        transform: HLSMediaSegmentTransform? = nil,
        onFirstChunkSent: (@Sendable (Int) async -> Void)? = nil
    ) async throws -> VideoRangeStreamCachePayload? {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = range.length > 1_500_000 ? 3.2 : 2.0
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.setValue("bytes=\(range.start)-\(range.endInclusive)", forHTTPHeaderField: "Range")

        let delegate = HLSRemoteRangeStreamDelegate()
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.qualityOfService = .userInitiated
        let session = URLSession(
            configuration: .ephemeral,
            delegate: delegate,
            delegateQueue: delegateQueue
        )
        let task = session.dataTask(with: request)
        var didInvalidateSession = false
        defer {
            if !didInvalidateSession {
                session.invalidateAndCancel()
            }
        }
        task.resume()

        let response = try await delegate.response()
        try LocalHLSProxyServer.validateRemoteRangeResponse(response, requestedRange: range)
        try await send(responseHeader, to: connection)

        let cacheCollector = VideoRangeStreamCacheCollector(range: range, cacheLimit: cacheLimit)
        do {
            let chunkSize = min(max(startupChunkSize, 24 * 1024), 96 * 1024)
            var chunk = Data()
            var didNotifyFirstChunk = false
            var didApplyTransform = false
            chunk.reserveCapacity(chunkSize)
            for try await data in delegate.chunks {
                try Task.checkCancellation()
                chunk.append(data)
                if chunk.count >= chunkSize {
                    try cacheCollector?.append(chunk)
                    let outboundChunk: Data
                    if let transform, !didApplyTransform {
                        outboundChunk = transform.apply(to: chunk)
                        didApplyTransform = true
                    } else {
                        outboundChunk = chunk
                    }
                    try await send(outboundChunk, to: connection)
                    if !didNotifyFirstChunk {
                        didNotifyFirstChunk = true
                        await onFirstChunkSent?(outboundChunk.count)
                    }
                    chunk.removeAll(keepingCapacity: true)
                }
            }
            if !chunk.isEmpty {
                try cacheCollector?.append(chunk)
                let outboundChunk: Data
                if let transform, !didApplyTransform {
                    outboundChunk = transform.apply(to: chunk)
                    didApplyTransform = true
                } else {
                    outboundChunk = chunk
                }
                try await send(outboundChunk, to: connection)
                if !didNotifyFirstChunk {
                    await onFirstChunkSent?(outboundChunk.count)
                }
            }
        } catch {
            task.cancel()
            session.invalidateAndCancel()
            didInvalidateSession = true
            connection.cancel()
            cacheCollector?.cancel()
            throw HLSRangeStreamError.responseAlreadyStarted(error)
        }
        session.finishTasksAndInvalidate()
        didInvalidateSession = true
        connection.cancel()
        return try cacheCollector?.finish()
    }

    private nonisolated static func send(_ data: Data, to connection: NWConnection) async throws {
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
}

private final class HLSRemoteRangeStreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let chunks: AsyncThrowingStream<Data, Error>

    private let lock = NSLock()
    private let chunkContinuation: AsyncThrowingStream<Data, Error>.Continuation
    private var responseContinuation: CheckedContinuation<URLResponse, Error>?
    private var responseResult: Result<URLResponse, Error>?

    override init() {
        var continuation: AsyncThrowingStream<Data, Error>.Continuation?
        self.chunks = AsyncThrowingStream(Data.self, bufferingPolicy: .unbounded) { streamContinuation in
            continuation = streamContinuation
        }
        self.chunkContinuation = continuation!
        super.init()
    }

    func response() async throws -> URLResponse {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let responseResult {
                lock.unlock()
                continuation.resume(with: responseResult)
                return
            }
            responseContinuation = continuation
            lock.unlock()
        }
    }

    func urlSession(
        _: URLSession,
        dataTask _: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        completeResponse(.success(response))
        completionHandler(.allow)
    }

    func urlSession(
        _: URLSession,
        dataTask _: URLSessionDataTask,
        didReceive data: Data
    ) {
        chunkContinuation.yield(data)
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            completeResponse(.failure(error))
            chunkContinuation.finish(throwing: error)
        } else {
            completeResponse(.failure(PlayerEngineError.unsupportedMedia))
            chunkContinuation.finish()
        }
    }

    private func completeResponse(_ result: Result<URLResponse, Error>) {
        lock.lock()
        guard responseResult == nil else {
            lock.unlock()
            return
        }
        responseResult = result
        let continuation = responseContinuation
        responseContinuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

private enum VideoRangeStreamCachePayload: Sendable {
    case data(Data)
    case file(URL)

    nonisolated var byteCount: Int {
        switch self {
        case let .data(data):
            return data.count
        case let .file(url):
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return size
        }
    }

    nonisolated func loadData() throws -> Data {
        switch self {
        case let .data(data):
            return data
        case let .file(url):
            return try Data(contentsOf: url, options: .mappedIfSafe)
        }
    }

    nonisolated func cleanup() {
        if case let .file(url) = self {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

nonisolated private final class VideoRangeStreamCacheCollector: @unchecked Sendable {
    private let fileURL: URL?
    private var data: Data?
    private var handle: FileHandle?
    private var isFinished = false

    init?(range: HTTPByteRange, cacheLimit: Int64) {
        guard range.length <= cacheLimit else { return nil }
        if range.length > 1_500_000 {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("cc.bili.hls-stream-cache", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let candidateURL = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("tmp")
            FileManager.default.createFile(atPath: candidateURL.path, contents: nil)
            if let handle = try? FileHandle(forWritingTo: candidateURL) {
                self.fileURL = candidateURL
                self.handle = handle
                self.data = nil
            } else {
                self.fileURL = nil
                self.handle = nil
                self.data = Data()
            }
        } else {
            self.fileURL = nil
            self.handle = nil
            self.data = Data()
            self.data?.reserveCapacity(Int(range.length))
        }
    }

    func append(_ chunk: Data) throws {
        if let handle {
            try handle.write(contentsOf: chunk)
        } else {
            data?.append(chunk)
        }
    }

    func finish() throws -> VideoRangeStreamCachePayload? {
        guard !isFinished else { return nil }
        isFinished = true
        if let handle {
            try handle.close()
            self.handle = nil
        }
        if let fileURL {
            return .file(fileURL)
        }
        if let data {
            return .data(data)
        }
        return nil
    }

    func cancel() {
        guard !isFinished else { return }
        isFinished = true
        try? handle?.close()
        handle = nil
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        data = nil
    }

    deinit {
        cancel()
    }
}

private enum HLSRangeStreamError: LocalizedError {
    case responseAlreadyStarted(Error)
    case notCacheable

    nonisolated var isRetryable: Bool {
        switch self {
        case .responseAlreadyStarted:
            false
        case .notCacheable:
            true
        }
    }

    nonisolated var errorDescription: String? {
        switch self {
        case let .responseAlreadyStarted(error):
            error.localizedDescription
        case .notCacheable:
            "range is too large to cache"
        }
    }
}

private actor HLSProxyStartupMetrics {
    static let shared = HLSProxyStartupMetrics()

    private let maxSessionCount = 36
    private var sessions: [String: Session] = [:]
    private var order: [String] = []

    func record(
        metricsID: String?,
        path: String,
        bytes: Int,
        elapsedMilliseconds: Double,
        source: String
    ) async {
        guard let metricsID, !metricsID.isEmpty,
              let bucket = StartupBucket(path: path)
        else { return }

        var session = sessions[metricsID] ?? Session()
        let didUpdate = session.record(
            bucket,
            bytes: bytes,
            elapsedMilliseconds: elapsedMilliseconds,
            source: source
        )
        guard didUpdate else { return }

        if sessions[metricsID] == nil {
            order.append(metricsID)
        }
        sessions[metricsID] = session
        trimIfNeeded()

        let message = session.summary
        PlayerMetricsLog.logger.info(
            "hlsProxyStartup id=\(metricsID, privacy: .public) path=\(path, privacy: .public) source=\(source, privacy: .public) elapsedMs=\(elapsedMilliseconds, format: .fixed(precision: 1), privacy: .public) bytes=\(bytes, privacy: .public) summary=\(message, privacy: .public)"
        )
        await PlayerMetricsLog.record(.network, metricsID: metricsID, message: message)
    }

    private func trimIfNeeded() {
        guard order.count > maxSessionCount else { return }
        let overflow = order.count - maxSessionCount
        for key in order.prefix(overflow) {
            sessions[key] = nil
        }
        order.removeFirst(overflow)
    }

    private struct Session: Sendable {
        private var entries: [StartupBucket: Entry] = [:]

        var summary: String {
            [
                "HLS",
                "m:\(value(.masterPlaylist))",
                "v/a:\(value(.videoPlaylist))/\(value(.audioPlaylist))",
                "init:\(value(.videoInit))/\(value(.audioInit))",
                "seg0:\(value(.videoSegment0))/\(value(.audioSegment0))"
            ].joined(separator: " ")
        }

        mutating func record(
            _ bucket: StartupBucket,
            bytes: Int,
            elapsedMilliseconds: Double,
            source: String
        ) -> Bool {
            let rounded = max(0, Int(elapsedMilliseconds.rounded()))
            if let existing = entries[bucket], existing.elapsedMilliseconds <= rounded {
                return false
            }
            entries[bucket] = Entry(
                bytes: bytes,
                elapsedMilliseconds: rounded,
                source: source
            )
            return true
        }

        private func value(_ bucket: StartupBucket) -> String {
            guard let entry = entries[bucket] else { return "-" }
            return "\(entry.elapsedMilliseconds)"
        }
    }

    private struct Entry: Sendable {
        let bytes: Int
        let elapsedMilliseconds: Int
        let source: String
    }

    private enum StartupBucket: Hashable, Sendable {
        case masterPlaylist
        case videoPlaylist
        case audioPlaylist
        case videoInit
        case audioInit
        case videoSegment0
        case audioSegment0

        init?(path: String) {
            switch path {
            case "/master.m3u8":
                self = .masterPlaylist
            case "/video.m3u8":
                self = .videoPlaylist
            case "/audio.m3u8":
                self = .audioPlaylist
            case "/media/video/init.mp4":
                self = .videoInit
            case "/media/audio/init.mp4":
                self = .audioInit
            case "/media/video/segment-0.m4s":
                self = .videoSegment0
            case "/media/audio/segment-0.m4s":
                self = .audioSegment0
            default:
                return nil
            }
        }
    }
}

private actor HLSProxyCacheMetrics {
    static let shared = HLSProxyCacheMetrics()

    private let maxSessionCount = 36
    private var sessions: [String: Session] = [:]
    private var order: [String] = []
    private var updateCounts: [String: Int] = [:]

    func record(
        metricsID: String?,
        path: String,
        source: String,
        bytes: Int,
        elapsedMilliseconds: Double
    ) async {
        guard let metricsID, !metricsID.isEmpty else { return }
        var session = sessions[metricsID] ?? Session()
        if sessions[metricsID] == nil {
            order.append(metricsID)
        }
        session.record(source: source, bytes: bytes, elapsedMilliseconds: elapsedMilliseconds)
        sessions[metricsID] = session
        trimIfNeeded()

        let message = session.summary
        PlayerMetricsLog.logger.info(
            "hlsProxyCache id=\(metricsID, privacy: .public) path=\(path, privacy: .public) source=\(source, privacy: .public) elapsedMs=\(elapsedMilliseconds, format: .fixed(precision: 1), privacy: .public) bytes=\(bytes, privacy: .public) summary=\(message, privacy: .public)"
        )
        guard shouldPublish(metricsID: metricsID, source: source) else { return }
        await PlayerMetricsLog.record(.mediaCache, metricsID: metricsID, message: message)
    }

    private func shouldPublish(metricsID: String, source: String) -> Bool {
        var count = updateCounts[metricsID] ?? 0
        count += 1
        updateCounts[metricsID] = count
        return count <= 2 || count.isMultiple(of: 12)
    }

    private func trimIfNeeded() {
        guard order.count > maxSessionCount else { return }
        let overflow = order.count - maxSessionCount
        for key in order.prefix(overflow) {
            sessions[key] = nil
            updateCounts[key] = nil
        }
        order.removeFirst(overflow)
    }

    private struct Session: Sendable {
        private var cacheHits = 0
        private var remoteFetches = 0
        private var streamedRanges = 0
        private var joinedRanges = 0
        private var totalBytes = 0
        private var bestElapsedMilliseconds: Int?

        var summary: String {
            let best = bestElapsedMilliseconds.map { "\($0)ms" } ?? "-"
            return [
                "Cache",
                "hit:\(cacheHits)",
                "fetch:\(remoteFetches)",
                "stream:\(streamedRanges)",
                "join:\(joinedRanges)",
                "bytes:\(totalBytes / 1024)KB",
                "best:\(best)"
            ].joined(separator: " ")
        }

        mutating func record(source: String, bytes: Int, elapsedMilliseconds: Double) {
            if source.contains("Cache") || source == "cache" {
                cacheHits += 1
            } else if source == "streamJoin" {
                joinedRanges += 1
            } else if source == "stream" {
                streamedRanges += 1
            } else {
                remoteFetches += 1
            }
            totalBytes += max(bytes, 0)
            let roundedElapsed = max(0, Int(elapsedMilliseconds.rounded()))
            if roundedElapsed > 0, bestElapsedMilliseconds.map({ roundedElapsed < $0 }) ?? true {
                bestElapsedMilliseconds = roundedElapsed
            }
        }
    }
}

fileprivate enum HLSByteRangeFetchStrategy: Sendable {
    case sequential
    case fastFallback

    nonisolated var isFastFallback: Bool {
        switch self {
        case .fastFallback:
            return true
        case .sequential:
            return false
        }
    }
}

private extension VideoRangeExternalFetchReservation {
    nonisolated var isReserved: Bool {
        if case .reserved = self {
            return true
        }
        return false
    }
}

private struct HLSRenditionTimelineOffset: Sendable {
    let baseMediaDecodeTimeTicks: UInt64
}

private struct HLSMediaSegmentTransform: Sendable {
    let baseMediaDecodeTimeOffset: UInt64

    nonisolated func apply(to data: Data) -> Data {
        guard baseMediaDecodeTimeOffset > 0 else { return data }
        return FMP4TimelineNormalizer.normalized(
            data,
            subtractingBaseMediaDecodeTime: baseMediaDecodeTimeOffset
        )
    }
}

private enum FMP4TimelineNormalizer {
    struct InitialTiming: Sendable {
        let baseMediaDecodeTimeTicks: UInt64
    }

    nonisolated static func initialTiming(in data: Data) -> InitialTiming? {
        guard data.count >= 16 else { return nil }
        let bytes = [UInt8](data)
        return firstTiming(in: bytes, range: 0..<bytes.count)
    }

    nonisolated static func normalized(
        _ data: Data,
        subtractingBaseMediaDecodeTime baseMediaDecodeTimeOffset: UInt64
    ) -> Data {
        guard baseMediaDecodeTimeOffset > 0, data.count >= 16 else { return data }
        var bytes = [UInt8](data)
        normalizeBoxes(
            in: &bytes,
            range: 0..<bytes.count,
            subtractingBaseMediaDecodeTime: baseMediaDecodeTimeOffset
        )
        return Data(bytes)
    }

    private nonisolated static func normalizeBoxes(
        in bytes: inout [UInt8],
        range: Range<Int>,
        subtractingBaseMediaDecodeTime baseMediaDecodeTimeOffset: UInt64
    ) {
        var cursor = range.lowerBound
        while cursor + 8 <= range.upperBound {
            let boxStart = cursor
            let declaredSize = Int64(readUInt32(bytes, offset: cursor))
            guard cursor + 8 <= range.upperBound else { return }
            let typeStart = cursor + 4
            let typeEnd = cursor + 8
            let type = String(bytes: bytes[typeStart..<typeEnd], encoding: .ascii)
            cursor += 8

            let boxEnd: Int
            if declaredSize == 1 {
                guard cursor + 8 <= range.upperBound else { return }
                let largeSize = readUInt64(bytes, offset: cursor)
                cursor += 8
                guard largeSize >= 16 else { return }
                boxEnd = boxStart + Int(min(UInt64(Int.max), largeSize))
            } else if declaredSize == 0 {
                boxEnd = range.upperBound
            } else {
                guard declaredSize >= 8 else { return }
                boxEnd = boxStart + Int(declaredSize)
            }

            guard boxEnd <= range.upperBound, boxEnd > cursor else { return }

            if type == "tfdt" {
                normalizeTFDT(
                    in: &bytes,
                    payloadStart: cursor,
                    boxEnd: boxEnd,
                    subtractingBaseMediaDecodeTime: baseMediaDecodeTimeOffset
                )
            } else if isContainerBox(type) {
                normalizeBoxes(
                    in: &bytes,
                    range: cursor..<boxEnd,
                    subtractingBaseMediaDecodeTime: baseMediaDecodeTimeOffset
                )
            }

            cursor = boxEnd
        }
    }

    private nonisolated static func firstTiming(in bytes: [UInt8], range: Range<Int>) -> InitialTiming? {
        var baseDecodeTime: UInt64?
        var cursor = range.lowerBound
        while cursor + 8 <= range.upperBound {
            let boxStart = cursor
            let declaredSize = Int64(readUInt32(bytes, offset: cursor))
            guard cursor + 8 <= range.upperBound else { return nil }
            let typeStart = cursor + 4
            let typeEnd = cursor + 8
            let type = String(bytes: bytes[typeStart..<typeEnd], encoding: .ascii)
            cursor += 8

            let boxEnd: Int
            if declaredSize == 1 {
                guard cursor + 8 <= range.upperBound else { return nil }
                let largeSize = readUInt64(bytes, offset: cursor)
                cursor += 8
                guard largeSize >= 16 else { return nil }
                boxEnd = boxStart + Int(min(UInt64(Int.max), largeSize))
            } else if declaredSize == 0 {
                boxEnd = range.upperBound
            } else {
                guard declaredSize >= 8 else { return nil }
                boxEnd = boxStart + Int(declaredSize)
            }

            guard boxEnd <= range.upperBound, boxEnd > cursor else { return nil }

            if type == "tfdt" {
                baseDecodeTime = readTFDT(in: bytes, payloadStart: cursor, boxEnd: boxEnd)
            } else if isContainerBox(type), let nested = firstTiming(in: bytes, range: cursor..<boxEnd) {
                if baseDecodeTime == nil {
                    baseDecodeTime = nested.baseMediaDecodeTimeTicks
                }
            }

            if let baseDecodeTime {
                return InitialTiming(
                    baseMediaDecodeTimeTicks: baseDecodeTime
                )
            }

            cursor = boxEnd
        }
        if let baseDecodeTime {
            return InitialTiming(
                baseMediaDecodeTimeTicks: baseDecodeTime
            )
        }
        return nil
    }

    private nonisolated static func readTFDT(in bytes: [UInt8], payloadStart: Int, boxEnd: Int) -> UInt64? {
        guard payloadStart + 8 <= boxEnd else { return nil }
        let version = bytes[payloadStart]
        let timeOffset = payloadStart + 4
        if version == 1 {
            guard timeOffset + 8 <= boxEnd else { return nil }
            return readUInt64(bytes, offset: timeOffset)
        } else {
            guard timeOffset + 4 <= boxEnd else { return nil }
            return UInt64(readUInt32(bytes, offset: timeOffset))
        }
    }

    private nonisolated static func normalizeTFDT(
        in bytes: inout [UInt8],
        payloadStart: Int,
        boxEnd: Int,
        subtractingBaseMediaDecodeTime offset: UInt64
    ) {
        guard offset > 0 else { return }
        guard payloadStart + 8 <= boxEnd else { return }
        let version = bytes[payloadStart]
        let timeOffset = payloadStart + 4
        if version == 1 {
            guard timeOffset + 8 <= boxEnd else { return }
            let original = readUInt64(bytes, offset: timeOffset)
            writeUInt64(original > offset ? original - offset : 0, to: &bytes, offset: timeOffset)
        } else {
            guard timeOffset + 4 <= boxEnd else { return }
            let original = UInt64(readUInt32(bytes, offset: timeOffset))
            let normalized = original > offset ? original - offset : 0
            writeUInt32(UInt32(min(normalized, UInt64(UInt32.max))), to: &bytes, offset: timeOffset)
        }
    }

    private nonisolated static func isContainerBox(_ type: String?) -> Bool {
        switch type {
        case "moof", "traf", "moov", "trak", "mdia", "minf", "stbl", "edts", "dinf", "mvex":
            return true
        default:
            return false
        }
    }

    private nonisolated static func readUInt32(_ bytes: [UInt8], offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }

    private nonisolated static func readUInt64(_ bytes: [UInt8], offset: Int) -> UInt64 {
        (UInt64(readUInt32(bytes, offset: offset)) << 32) | UInt64(readUInt32(bytes, offset: offset + 4))
    }

    private nonisolated static func writeUInt32(_ value: UInt32, to bytes: inout [UInt8], offset: Int) {
        bytes[offset] = UInt8((value >> 24) & 0xff)
        bytes[offset + 1] = UInt8((value >> 16) & 0xff)
        bytes[offset + 2] = UInt8((value >> 8) & 0xff)
        bytes[offset + 3] = UInt8(value & 0xff)
    }

    private nonisolated static func writeUInt64(_ value: UInt64, to bytes: inout [UInt8], offset: Int) {
        writeUInt32(UInt32((value >> 32) & 0xffff_ffff), to: &bytes, offset: offset)
        writeUInt32(UInt32(value & 0xffff_ffff), to: &bytes, offset: offset + 4)
    }
}

private enum HLSProxyRoute: Sendable {
    case data(Data, contentType: String)
    case remoteByteRange(
        url: URL,
        fallbackURLs: [URL],
        range: HTTPByteRange,
        contentType: String,
        transform: HLSMediaSegmentTransform?
    )
}

private final class LocalHLSProxyServer: @unchecked Sendable {
    nonisolated private static let maxStreamingCacheBytes: Int64 = 24 * 1024 * 1024

    let baseURL: URL

    private let headers: [String: String]
    nonisolated(unsafe) private var metricsID: String?
    private let listener: NWListener
    private let queue: DispatchQueue
    nonisolated(unsafe) private var routes: [String: HLSProxyRoute] = [:]
    nonisolated(unsafe) private var isStarted = false

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
            PlayerMetricsLog.logger.error(
                "hlsProxyRemoteFetchFailed path=\(request.path, privacy: .public) range=\(fetchRange.start, privacy: .public)-\(fetchRange.endInclusive, privacy: .public) url=\(url.absoluteString, privacy: .private) error=\(error.localizedDescription, privacy: .public)"
            )
            queue.async {
                self.sendError(502, reason: "Bad Gateway", to: connection)
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
        if path.hasSuffix("/init.mp4") {
            return .fastFallback
        }
        guard path.contains("/segment-0.m4s")
                || path.contains("/segment-1.m4s")
        else {
            return .sequential
        }
        return .fastFallback
    }

    nonisolated private func shouldStreamRemoteRange(
        request: HLSProxyRequest,
        range: HTTPByteRange,
        transform: HLSMediaSegmentTransform?
    ) -> Bool {
        guard case nil = request.range else { return false }
        return request.method == "GET"
            && request.path.contains("/media/video/")
            && range.length >= 512 * 1024
    }

    nonisolated private func startupChunkSize(for path: String, transform: HLSMediaSegmentTransform?) -> Int {
        if transform != nil {
            return 128 * 1024
        }
        if path.contains("/segment-0.m4s") || path.contains("/segment-1.m4s") {
            return 8 * 1024
        }
        return 32 * 1024
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
                await HLSSourcePreferenceCache.shared.recordResult(
                    url: url,
                    for: canonicalURLs,
                    elapsedMilliseconds: 0,
                    bytes: Int64(data.count),
                    succeeded: true
                )
                queue.async {
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
                await HLSSourcePreferenceCache.shared.recordPreferredURL(url, for: canonicalURLs)
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
                    await HLSSourcePreferenceCache.shared.recordPreferredURL(url, for: canonicalURLs)
                    await HLSSourcePreferenceCache.shared.recordResult(
                        url: url,
                        for: canonicalURLs,
                        elapsedMilliseconds: 0,
                        bytes: Int64(data.count),
                        succeeded: true
                    )
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
                await HLSSourcePreferenceCache.shared.recordResult(
                    url: url,
                    for: canonicalURLs,
                    elapsedMilliseconds: streamElapsed,
                    bytes: Int64(streamedBytes),
                    succeeded: true
                )
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
                await HLSSourcePreferenceCache.shared.recordPreferredURL(url, for: canonicalURLs)
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
                await HLSSourcePreferenceCache.shared.recordResult(
                    url: url,
                    for: canonicalURLs,
                    elapsedMilliseconds: 0,
                    bytes: 0,
                    succeeded: false
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
            self.receiveRequest(from: connection, accumulatedData: Data())
        })
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

    nonisolated fileprivate static func validateRemoteRangeResponse(
        _ response: URLResponse,
        requestedRange: HTTPByteRange
    ) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw PlayerEngineError.unsupportedMedia
        }
        if httpResponse.statusCode == 200, requestedRange.start > 0 {
            throw PlayerEngineError.unsupportedMedia
        }
    }
}

private extension Array where Element == URL {
    nonisolated func removingDuplicates() -> [URL] {
        var seen = Set<String>()
        var result = [URL]()
        for url in self {
            let key = url.absoluteString
            guard seen.insert(key).inserted else { continue }
            result.append(url)
        }
        return result
    }
}

private extension Array {
    nonisolated subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct HLSProxyRequest: Sendable {
    let method: String
    let path: String
    let range: HTTPByteRange?
    let shouldCloseConnection: Bool

    nonisolated init?(data: Data) {
        guard let rawRequest = String(data: data, encoding: .utf8) else { return nil }
        let lines = rawRequest.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count >= 2 else { return nil }

        method = requestParts[0]
        let rawPath = requestParts[1]
        let httpVersion = requestParts.indices.contains(2) ? requestParts[2].lowercased() : "http/1.0"
        path = URLComponents(string: "http://127.0.0.1\(rawPath)")?.path ?? rawPath

        var parsedRange: HTTPByteRange?
        var connectionValue: String?
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            switch key {
            case "range":
                parsedRange = HTTPByteRange(httpHeaderValue: value)
            case "connection":
                connectionValue = value.lowercased()
            default:
                break
            }
        }
        range = parsedRange
        if connectionValue?.contains("close") == true {
            shouldCloseConnection = true
        } else if httpVersion == "http/1.1" {
            shouldCloseConnection = false
        } else {
            shouldCloseConnection = connectionValue?.contains("keep-alive") != true
        }
    }
}

private struct SIDXParser {
    struct Reference {
        let range: HTTPByteRange
        let duration: TimeInterval
        let startTime: TimeInterval
        let startTimeTicks: UInt64
        let timescale: UInt32
    }

    nonisolated static func parseReferences(from data: Data, sidxStartOffset: Int64) throws -> [Reference] {
        let bytes = [UInt8](data)
        guard bytes.count >= 12 else { throw PlayerEngineError.unsupportedMedia }

        var offset = 0
        if String(bytes: bytes[4..<min(8, bytes.count)], encoding: .ascii) != "sidx" {
            while offset + 8 <= bytes.count {
                let size = Int(readUInt32(bytes, offset: offset))
                guard size >= 8, offset + size <= bytes.count else { break }
                let type = String(bytes: bytes[(offset + 4)..<(offset + 8)], encoding: .ascii)
                if type == "sidx" {
                    break
                }
                offset += size
            }
        }

        guard offset + 12 <= bytes.count,
              String(bytes: bytes[(offset + 4)..<(offset + 8)], encoding: .ascii) == "sidx"
        else {
            throw PlayerEngineError.unsupportedMedia
        }

        let boxSize = Int64(readUInt32(bytes, offset: offset))
        let version = bytes[offset + 8]
        var cursor = offset + 12
        guard cursor + 8 <= bytes.count else { throw PlayerEngineError.unsupportedMedia }
        cursor += 4
        let timescaleValue = readUInt32(bytes, offset: cursor)
        let timescale = Double(timescaleValue)
        cursor += 4
        guard timescale > 0 else { throw PlayerEngineError.unsupportedMedia }

        let firstOffset: Int64
        let earliestPresentationTime: UInt64
        if version == 0 {
            guard cursor + 8 <= bytes.count else { throw PlayerEngineError.unsupportedMedia }
            earliestPresentationTime = UInt64(readUInt32(bytes, offset: cursor))
            cursor += 4
            firstOffset = Int64(readUInt32(bytes, offset: cursor))
            cursor += 4
        } else {
            guard cursor + 16 <= bytes.count else { throw PlayerEngineError.unsupportedMedia }
            earliestPresentationTime = readUInt64(bytes, offset: cursor)
            cursor += 8
            firstOffset = Int64(readUInt64(bytes, offset: cursor))
            cursor += 8
        }

        cursor += 2
        guard cursor + 2 <= bytes.count else { throw PlayerEngineError.unsupportedMedia }
        let referenceCount = Int(readUInt16(bytes, offset: cursor))
        cursor += 2

        var mediaOffset = sidxStartOffset + boxSize + firstOffset
        var presentationTime = TimeInterval(earliestPresentationTime) / timescale
        var elapsedTicks: UInt64 = 0
        var references = [Reference]()
        references.reserveCapacity(referenceCount)

        for _ in 0..<referenceCount {
            guard cursor + 12 <= bytes.count else { break }
            let typeAndSize = readUInt32(bytes, offset: cursor)
            cursor += 4
            let isSubsegment = (typeAndSize & 0x8000_0000) != 0
            let size = Int64(typeAndSize & 0x7fff_ffff)
            let durationOffset = cursor
            let durationTicks = readUInt32(bytes, offset: durationOffset)
            let duration = TimeInterval(durationTicks) / timescale
            cursor += 4
            cursor += 4
            guard !isSubsegment, size > 0 else { continue }
            references.append(Reference(
                range: HTTPByteRange(start: mediaOffset, endInclusive: mediaOffset + size - 1),
                duration: duration,
                startTime: presentationTime,
                startTimeTicks: earliestPresentationTime + elapsedTicks,
                timescale: timescaleValue
            ))
            mediaOffset += size
            elapsedTicks += UInt64(durationTicks)
            presentationTime += duration
        }

        return references
    }

    private nonisolated static func readUInt16(_ bytes: [UInt8], offset: Int) -> UInt16 {
        (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    private nonisolated static func readUInt32(_ bytes: [UInt8], offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }

    private nonisolated static func readUInt64(_ bytes: [UInt8], offset: Int) -> UInt64 {
        (UInt64(readUInt32(bytes, offset: offset)) << 32)
            | UInt64(readUInt32(bytes, offset: offset + 4))
    }
}
