import AVFoundation
import AVKit
import Combine
import OSLog
import PillarboxPlayer
import SwiftUI
import UIKit

@MainActor
final class PillarboxPlayerRenderingEngine: NSObject, PlayerRenderingEngine {
    private var player: Player
    private var cancellables = Set<AnyCancellable>()
    private var currentItem: PlayerItem?
    private var source: PlayerStreamSource?
    private var hlsBridge: LocalHLSBridge?
    private var progressiveLoader: BiliHeaderResourceLoaderDelegate?
    private var mediaTimeOffset: TimeInterval = 0
    private weak var surfaceView: UIView?
    private weak var playerViewController: AVPlayerViewController?
    private weak var hostFullscreenExitTarget: PlayerHostFullscreenExitTarget?
    private var hostingController: UIHostingController<PillarboxVideoSurface>?
    private var playerLayer: AVPlayerLayer?
    private var layerReadyForDisplayObserver: NSKeyValueObservation?
    private var itemEndObserver: Any?
    private var itemFailedObserver: Any?
    private var systemItemObservers: [NSKeyValueObservation] = []
    private var systemItemObservationTask: Task<Void, Never>?
    private var foregroundObserver: Any?
    private var backgroundObserver: Any?
    private var visualOutputProbeTask: Task<Void, Never>?
    private var currentRate: Float = 1
    private var wantsPlayback = false
    private var didReportFirstFrame = false
    private var lastPlaybackState: PlayerEnginePlaybackState = .idle
    private var playbackError: String?
    private var videoGravity: AVLayerVideoGravity = .resizeAspect
    private var isHostFullscreenActive = false

    var hasMedia: Bool {
        player.currentItem != nil || player.systemPlayer.currentItem != nil
    }

    var needsMediaRecovery: Bool {
        player.systemPlayer.currentItem?.status == .failed
    }

    var playbackErrorMessage: String? {
        playbackError ?? player.error?.localizedDescription ?? player.systemPlayer.currentItem?.error?.localizedDescription
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
        player.systemPlayer.volume
    }

    var isMuted: Bool {
        player.isMuted
    }

    var onPlaybackStateChange: (@MainActor (PlayerEnginePlaybackState) -> Void)?
    var onPlaybackIntentChange: (@MainActor (Bool) -> Void)?
    var onLoadingProgressChange: (@MainActor (Double) -> Void)?
    var onFirstFrame: (@MainActor (TimeInterval) -> Void)?

    override init() {
        player = Self.makePlayer()
        super.init()
        configureAudioSession()
        observePlayer()
        observeAppLifecycle()
    }

    deinit {
        if let itemEndObserver = itemEndObserver {
            NotificationCenter.default.removeObserver(itemEndObserver)
        }
        if let itemFailedObserver = itemFailedObserver {
            NotificationCenter.default.removeObserver(itemFailedObserver)
        }
        systemItemObservationTask?.cancel()
        visualOutputProbeTask?.cancel()
        systemItemObservers.removeAll()
        if let foregroundObserver = foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
        if let backgroundObserver = backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
    }

    func attachSurface(_ surface: UIView) {
        surfaceView = surface
        guard playerViewController == nil else {
            refreshSurfaceLayout()
            return
        }
        installPlayerLayerIfNeeded(in: surface)
        refreshSurfaceLayout()
    }

    func detachSurface(_ surface: UIView) {
        guard surfaceView === surface else { return }
        removePlayerLayer()
        uninstallPillarboxSurface()
        surfaceView = nil
    }

    func refreshSurfaceLayout() {
        if let playerViewController {
            AVPlayerLayoutCoordinator.shared.apply(
                playerController: playerViewController,
                bounds: playerViewController.view.superview?.bounds ?? playerViewController.view.bounds,
                gravity: videoGravity
            )
        }
        guard let surfaceView = surfaceView else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if playerViewController == nil {
            let layer = installPlayerLayerIfNeeded(in: surfaceView)
            AVPlayerLayoutCoordinator.shared.apply(
                playerLayer: layer,
                in: surfaceView,
                gravity: videoGravity
            )
        }
        CATransaction.commit()
    }

    func recoverSurface() {
        configureAudioSession()
        player.becomeActive()
        if let playerViewController {
            configureNativePlaybackController(playerViewController)
            return
        }
        if let surfaceView = surfaceView {
            installPlayerLayerIfNeeded(in: surfaceView)
            refreshSurfaceLayout()
        }
        if wantsPlayback {
            player.play()
            player.playbackSpeed = currentRate
        }
    }

    func setViewModel(_: PlayerStateViewModel?) {}

    func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        guard videoGravity != gravity else { return }
        videoGravity = gravity
        playerViewController?.videoGravity = gravity
        playerLayer?.videoGravity = gravity
        refreshSurfaceLayout()
    }

    func attachNativePlaybackController(_ controller: AVPlayerViewController) {
        if let playerViewController, playerViewController !== controller {
            playerViewController.player = nil
        }
        playerViewController = controller
        configureNativePlaybackController(controller)
        removePlayerLayer()
        uninstallPillarboxSurface()
    }

    func detachNativePlaybackController(_ controller: AVPlayerViewController) {
        guard playerViewController === controller else { return }
        controller.player = nil
        playerViewController = nil
    }

    func setHostFullscreenActive(_ isActive: Bool, exitTarget: PlayerHostFullscreenExitTarget?) {
        isHostFullscreenActive = isActive
        hostFullscreenExitTarget = exitTarget
        guard playerViewController == nil else {
            refreshSurfaceLayout()
            return
        }
        rebuildPillarboxSurface()
    }

    func prepare(source: PlayerStreamSource) async throws {
        configureAudioSession()
        player.becomeActive()
        self.source = source
        wantsPlayback = false
        didReportFirstFrame = false
        playbackError = nil
        onLoadingProgressChange?(0.18)
        publishPlaybackState(.preparing)

        let manifest = try await BiliHLSManifestBuilder.make(source: source)
        guard !Task.isCancelled else { return }
        onLoadingProgressChange?(0.58)

        currentItem = nil
        hlsBridge = manifest.bridge
        progressiveLoader = manifest.progressiveLoader
        mediaTimeOffset = manifest.mediaTimeOffset

        let playbackConfiguration = PlaybackConfiguration(
            position: at(.zero),
            preferredForwardBufferDuration: preferredForwardBufferDuration(for: source)
        )
        let item = makePlayerItem(from: manifest, configuration: playbackConfiguration)
        let previousVolume = player.systemPlayer.volume
        let previousMuted = player.isMuted
        player.pause()
        player.resignActive()
        player = Self.makePlayer(item: item)
        player.systemPlayer.volume = previousVolume
        player.isMuted = previousMuted
        player.playbackSpeed = currentRate
        player.becomeActive()
        cancellables.removeAll()
        observePlayer()
        if let playerViewController {
            configureNativePlaybackController(playerViewController)
        }
        rebuildPillarboxSurface()
        currentItem = item
        removeCurrentItemObservers()
        player.systemPlayer.automaticallyWaitsToMinimizeStalling = false
        scheduleSystemItemObservation()
        onLoadingProgressChange?(0.86)
        publishPlaybackState(.ready)
        refreshSurfaceLayout()
    }

    func play() {
        guard hasMedia else { return }
        configureAudioSession()
        player.becomeActive()
        wantsPlayback = true
        player.playbackSpeed = currentRate
        player.play()
        onLoadingProgressChange?(0.98)
        publishPlaybackState(.playing)
        reportFirstFrameIfPossible()
        schedulePlaybackSurfaceReadyFallback()
        scheduleVisualOutputProbe()
    }

    func pause() {
        wantsPlayback = false
        player.pause()
        publishPlaybackState(.paused)
    }

    func stop() {
        wantsPlayback = false
        player.pause()
        player.currentItem = nil
        playerViewController?.player = nil
        playerLayer?.player = nil
        player.resignActive()
        removeCurrentItemObservers()
        systemItemObservationTask?.cancel()
        visualOutputProbeTask?.cancel()
        systemItemObservers.removeAll()
        currentItem = nil
        source = nil
        hlsBridge = nil
        progressiveLoader = nil
        mediaTimeOffset = 0
        playbackError = nil
        didReportFirstFrame = false
        publishPlaybackState(.idle)
    }

    func setPlaybackRate(_ rate: Double) {
        currentRate = max(Float(rate), 0.1)
        player.playbackSpeed = currentRate
        if wantsPlayback {
            player.play()
        }
    }

    func setVolume(_ volume: Float) {
        player.systemPlayer.volume = min(max(volume, 0), 1)
    }

    func setMuted(_ isMuted: Bool) {
        player.isMuted = isMuted
    }

    func seek(toTime time: TimeInterval) -> TimeInterval? {
        guard hasMedia else { return nil }
        let target = playerTime(fromDisplayTime: max(time, 0))
        if wantsPlayback {
            publishPlaybackState(.buffering)
        }
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        return displayTime(fromPlayerTime: target)
    }

    func seek(toProgress progress: Double, duration: TimeInterval?) -> TimeInterval? {
        guard hasMedia else { return nil }
        let resolvedDuration = resolvedDuration(durationHint: duration)
        guard resolvedDuration > 0 else { return nil }
        let target = playerTime(fromDisplayTime: min(max(progress, 0), 1) * resolvedDuration)
        if wantsPlayback {
            publishPlaybackState(.buffering)
        }
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        return displayTime(fromPlayerTime: target)
    }

    func seek(by interval: TimeInterval, from currentTime: TimeInterval, duration: TimeInterval?) -> TimeInterval? {
        guard hasMedia else { return nil }
        let resolvedDuration = resolvedDuration(durationHint: duration)
        let target = resolvedDuration > 0
            ? min(max(currentTime + interval, 0), resolvedDuration)
            : max(currentTime + interval, 0)
        let playerTarget = playerTime(fromDisplayTime: target)
        if wantsPlayback {
            publishPlaybackState(.buffering)
        }
        player.seek(to: CMTime(seconds: playerTarget, preferredTimescale: 600))
        return displayTime(fromPlayerTime: playerTarget)
    }

    func seekAfterUserScrub(toProgress progress: Double, duration: TimeInterval?) async -> TimeInterval? {
        guard hasMedia else { return nil }
        let resolvedDuration = resolvedDuration(durationHint: duration)
        guard resolvedDuration > 0 else { return nil }
        let target = playerTime(fromDisplayTime: min(max(progress, 0), 1) * resolvedDuration)
        let targetTime = CMTime(seconds: target, preferredTimescale: 600)
        if wantsPlayback {
            publishPlaybackState(.buffering)
        }
        let finished = await withCheckedContinuation { continuation in
            player.seek(to: targetTime) { finished in
                continuation.resume(returning: finished)
            }
        }
        return finished ? displayTime(fromPlayerTime: target) : nil
    }

    func snapshot(durationHint: TimeInterval?) -> PlayerPlaybackSnapshot {
        let playerTime = player.systemPlayer.currentTime().seconds
        let currentSeconds = displayTime(fromPlayerTime: playerTime)
        let durationSeconds = resolvedDuration(durationHint: durationHint)
        let itemStatus = player.systemPlayer.currentItem?.status
        return PlayerPlaybackSnapshot(
            currentTime: currentSeconds.isFinite && currentSeconds >= 0 ? currentSeconds : nil,
            duration: durationSeconds > 0 ? durationSeconds : durationHint,
            isPlaying: player.systemPlayer.rate > 0 || player.playbackState == .playing,
            isSeekable: itemStatus == .readyToPlay || player.systemPlayer.currentItem?.hasSeekableTimeRangesForBili == true || (durationHint ?? 0) > 0
        )
    }

    func pictureInPictureContentSource() -> AVPictureInPictureController.ContentSource? {
        guard let playerLayer else { return nil }
        return AVPictureInPictureController.ContentSource(playerLayer: playerLayer)
    }

    func togglePictureInPicture() {
        // PlayerStateViewModel owns AVPictureInPictureController for direct AVPlayerLayer surfaces.
    }

    func invalidatePictureInPicturePlaybackState() {}

    private func installPillarboxSurfaceIfNeeded(in surface: UIView) {
        let controller: UIHostingController<PillarboxVideoSurface>
        if let hostingController {
            controller = hostingController
            controller.rootView = makePillarboxSurface()
        } else {
            controller = UIHostingController(rootView: makePillarboxSurface())
            hostingController = controller
        }

        var addedParent: UIViewController?
        if let parent = surface.enclosingViewControllerForBili {
            if controller.parent !== parent {
                controller.willMove(toParent: nil)
                controller.removeFromParent()
                parent.addChild(controller)
                addedParent = parent
            }
        } else if controller.parent != nil {
            controller.willMove(toParent: nil)
            controller.removeFromParent()
        }

        configureHostingView(controller.view, in: surface)
        if controller.view.superview !== surface {
            controller.view.removeFromSuperview()
            surface.addSubview(controller.view)
        }
        surface.sendSubviewToBack(controller.view)
        if let addedParent {
            controller.didMove(toParent: addedParent)
        }
        refreshSurfaceLayout()
    }

    @discardableResult
    private func installPlayerLayerIfNeeded(in surface: UIView) -> AVPlayerLayer {
        if let playerLayer {
            if playerLayer.superlayer !== surface.layer {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                playerLayer.removeFromSuperlayer()
                surface.layer.insertSublayer(playerLayer, at: 0)
                CATransaction.commit()
            }
            if playerLayer.player !== player.systemPlayer {
                playerLayer.player = player.systemPlayer
            }
            if layerReadyForDisplayObserver == nil {
                observeLayerReadyForDisplay(playerLayer)
            }
            AVPlayerLayoutCoordinator.shared.apply(
                playerLayer: playerLayer,
                in: surface,
                gravity: videoGravity
            )
            return playerLayer
        }

        let layer = AVPlayerLayer(player: player.systemPlayer)
        layer.videoGravity = videoGravity
        layer.backgroundColor = UIColor.black.cgColor
        layer.needsDisplayOnBoundsChange = false
        layer.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "frame": NSNull()
        ]
        AVPlayerLayoutCoordinator.shared.apply(
            playerLayer: layer,
            in: surface,
            gravity: videoGravity
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surface.layer.insertSublayer(layer, at: 0)
        CATransaction.commit()
        playerLayer = layer
        observeLayerReadyForDisplay(layer)
        return layer
    }

    private func removePlayerLayer() {
        playerLayer?.player = nil
        playerLayer?.removeFromSuperlayer()
        layerReadyForDisplayObserver = nil
        playerLayer = nil
    }

    private func uninstallPillarboxSurface() {
        guard let hostingController = hostingController else { return }
        hostingController.willMove(toParent: nil)
        hostingController.view.removeFromSuperview()
        hostingController.removeFromParent()
        self.hostingController = nil
    }

    private func rebuildPillarboxSurface() {
        if let surfaceView, playerViewController == nil {
            installPlayerLayerIfNeeded(in: surfaceView)
        }
        hostingController?.rootView = makePillarboxSurface()
        refreshSurfaceLayout()
    }

    private func makePillarboxSurface() -> PillarboxVideoSurface {
        PillarboxVideoSurface(
            player: player,
            gravity: videoGravity
        )
    }

    private func configureHostingView(_ view: UIView, in surface: UIView) {
        view.backgroundColor = .black
        view.isOpaque = true
        view.clipsToBounds = true
        view.isHidden = false
        view.insetsLayoutMarginsFromSafeArea = false
        view.preservesSuperviewLayoutMargins = false
        view.layoutMargins = .zero
        view.frame = surface.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            PlayerMetricsLog.logger.error("pillarboxAudioSessionFailed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private static func makePlayer(item: PlayerItem? = nil) -> Player {
        let configuration = PlayerConfiguration(
            allowsExternalPlayback: true,
            preventsDisplaySleepDuringVideoPlayback: true,
            backwardSkipInterval: 10,
            forwardSkipInterval: 10,
            allowsConstrainedNetworkAccess: true
        )
        let player: Player
        if let item = item {
            player = Player(item: item, configuration: configuration)
        } else {
            player = Player(configuration: configuration)
        }
        player.actionAtItemEnd = .pause
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        return player
    }

    private func makePlayerItem(
        from manifest: BiliHLSPlaybackManifest,
        configuration: PlaybackConfiguration
    ) -> PlayerItem {
        if let progressiveLoader = manifest.progressiveLoader {
            return PlayerItem.custom(
                url: manifest.masterPlaylistURL,
                delegate: progressiveLoader,
                configuration: configuration
            )
        }
        return PlayerItem.simple(
            url: manifest.masterPlaylistURL,
            configuration: configuration
        )
    }

    private func configureNativePlaybackController(_ controller: AVPlayerViewController) {
        if controller.player !== player.systemPlayer {
            controller.player = player.systemPlayer
        }
        controller.showsPlaybackControls = true
        controller.videoGravity = videoGravity
        controller.allowsPictureInPicturePlayback = AVPictureInPictureController.isPictureInPictureSupported()
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.requiresLinearPlayback = false
        controller.updatesNowPlayingInfoCenter = false
        controller.view.backgroundColor = .black
        controller.view.isOpaque = true
    }

    private func preferredForwardBufferDuration(for source: PlayerStreamSource) -> TimeInterval {
        let environment = PlaybackEnvironment.current
        return source.audioURL == nil
            ? environment.preferredForwardBufferDuration
            : min(environment.preferredForwardBufferDuration, 0.02)
    }

    private func observePlayer() {
        player.propertiesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] properties in
                Task { @MainActor [weak self] in
                    self?.handleProperties(properties)
                }
            }
            .store(in: &cancellables)

        player.periodicTimePublisher(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                Task { @MainActor [weak self] in
                    self?.reportFirstFrameIfPossible(currentTime: self?.displayTime(fromPlayerTime: time.seconds))
                }
            }
            .store(in: &cancellables)

        player.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self, let error = self.player.error else { return }
                    self.handlePlaybackFailure(error.localizedDescription)
                }
            }
            .store(in: &cancellables)

    }

    private func observeAppLifecycle() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.configureAudioSession()
                if self.wantsPlayback {
                    self.player.play()
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

    private func observeCurrentSystemItemIfReady() {
        guard let item = player.systemPlayer.currentItem else {
            return
        }
        guard systemItemObservers.isEmpty else { return }

        configureStartupBuffering(for: item)
        let statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status = item.status
            let errorMessage = item.error?.localizedDescription
            Task { @MainActor [weak self] in
                switch status {
                case .readyToPlay:
                    self?.publishPlaybackState(.ready)
                case .failed:
                    self?.handlePlaybackFailure(errorMessage)
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }
        let keepUpObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            let isPlaybackLikelyToKeepUp = item.isPlaybackLikelyToKeepUp
            Task { @MainActor [weak self] in
                guard let self = self, self.wantsPlayback else { return }
                if isPlaybackLikelyToKeepUp {
                    self.player.play()
                    self.publishPlaybackState(.playing)
                } else {
                    self.publishPlaybackState(.buffering)
                }
            }
        }
        let bufferEmptyObserver = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
            let isPlaybackBufferEmpty = item.isPlaybackBufferEmpty
            Task { @MainActor [weak self] in
                guard let self = self, self.wantsPlayback, isPlaybackBufferEmpty else { return }
                self.publishPlaybackState(.buffering)
            }
        }
        systemItemObservers = [statusObserver, keepUpObserver, bufferEmptyObserver]
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
                self?.handlePlaybackFailure(errorMessage)
            }
        }
    }

    private func scheduleSystemItemObservation() {
        systemItemObservationTask?.cancel()
        observeCurrentSystemItemIfReady()
        guard systemItemObservers.isEmpty else { return }
        systemItemObservationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            self?.observeCurrentSystemItemIfReady()
            self?.systemItemObservationTask = nil
        }
    }

    private func configureStartupBuffering(for item: AVPlayerItem) {
        guard let source = source else { return }
        item.preferredForwardBufferDuration = preferredForwardBufferDuration(for: source)
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        if let bandwidth = source.videoStream?.bandwidth, bandwidth > 0 {
            item.preferredPeakBitRate = Double(bandwidth) * 1.18
        } else if source.audioURL == nil {
            item.preferredPeakBitRate = 0
        }
    }

    private func removeCurrentItemObservers() {
        if let itemEndObserver = itemEndObserver {
            NotificationCenter.default.removeObserver(itemEndObserver)
            self.itemEndObserver = nil
        }
        if let itemFailedObserver = itemFailedObserver {
            NotificationCenter.default.removeObserver(itemFailedObserver)
            self.itemFailedObserver = nil
        }
        systemItemObservationTask?.cancel()
        systemItemObservationTask = nil
        systemItemObservers.removeAll()
    }

    private func handleProperties(_ properties: PlayerProperties) {
        observeCurrentSystemItemIfMissing()
        onLoadingProgressChange?(Double(max(properties.buffer, 0)))
        guard playbackError == nil else { return }
        if let itemError = player.systemPlayer.currentItem?.error {
            handlePlaybackFailure(itemError.localizedDescription)
            return
        }

        switch properties.playbackState {
        case .idle:
            publishPlaybackState(hasMedia ? .preparing : .idle)
        case .playing:
            updatePlaybackIntent(true)
            if properties.isBuffering {
                publishPlaybackState(.buffering)
            } else {
                publishPlaybackState(.playing)
                reportFirstFrameIfPossible(
                    currentTime: displayTime(fromPlayerTime: player.systemPlayer.currentTime().seconds)
                )
            }
        case .paused:
            publishPlaybackState(wantsPlayback && properties.isBuffering ? .buffering : .paused)
        case .ended:
            wantsPlayback = false
            publishPlaybackState(.ended)
        @unknown default:
            break
        }
    }

    private func observeCurrentSystemItemIfMissing() {
        guard systemItemObservers.isEmpty else { return }
        guard player.systemPlayer.currentItem != nil else { return }
        observeCurrentSystemItemIfReady()
    }

    private func observeLayerReadyForDisplay(_ layer: AVPlayerLayer) {
        layerReadyForDisplayObserver = layer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            Task { @MainActor [weak self] in
                self?.reportFirstFrameIfPossible()
            }
        }
    }

    private func handlePlaybackFailure(_ message: String?) {
        let resolvedMessage = message ?? PlayerEngineError.unsupportedMedia.localizedDescription
        playbackError = resolvedMessage
        PlayerMetricsLog.logger.error("pillarboxPlaybackFailed error=\(resolvedMessage, privacy: .public)")
        publishPlaybackState(.failed(resolvedMessage))
    }

    private func updatePlaybackIntent(_ wantsPlayback: Bool) {
        guard self.wantsPlayback != wantsPlayback else { return }
        self.wantsPlayback = wantsPlayback
        onPlaybackIntentChange?(wantsPlayback)
    }

    private func reportFirstFrameIfPossible(currentTime: TimeInterval? = nil) {
        guard !didReportFirstFrame else { return }
        guard player.systemPlayer.currentItem?.status == .readyToPlay || player.systemPlayer.rate > 0 else { return }
        if let currentTime = currentTime {
            guard currentTime > 0 || player.systemPlayer.rate > 0 else { return }
        } else {
            let current = displayTime(fromPlayerTime: player.systemPlayer.currentTime().seconds)
            guard current > 0 || player.systemPlayer.rate > 0 else { return }
        }
        didReportFirstFrame = true
        let resolvedTime = currentTime ?? displayTime(fromPlayerTime: player.systemPlayer.currentTime().seconds)
        onFirstFrame?(resolvedTime.isFinite ? max(resolvedTime, 0) : 0)
    }

    private func schedulePlaybackSurfaceReadyFallback() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard let self, self.wantsPlayback, self.player.systemPlayer.rate > 0 else { return }
            self.reportFirstFrameIfPossible(
                currentTime: self.displayTime(fromPlayerTime: self.player.systemPlayer.currentTime().seconds)
            )
        }
    }

    private func scheduleVisualOutputProbe() {
        visualOutputProbeTask?.cancel()
        guard source?.audioURL != nil else { return }
        visualOutputProbeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard let self,
                  !Task.isCancelled,
                  self.wantsPlayback,
                  self.player.systemPlayer.rate > 0,
                  let item = self.player.systemPlayer.currentItem,
                  item.status == .readyToPlay
            else { return }

            let presentationSize = item.presentationSize
            let hasVideoTrack = item.tracks.contains { track in
                track.isEnabled && track.assetTrack?.mediaType == .video
            }
            let hasPresentationSize = presentationSize.width > 2 && presentationSize.height > 2
            let playbackTime = self.displayTime(fromPlayerTime: self.player.systemPlayer.currentTime().seconds)
            guard playbackTime > 0.8, !hasVideoTrack, !hasPresentationSize else { return }

            self.handlePlaybackFailure("No video output was detected. Trying a more compatible stream.")
        }
    }

    private func publishPlaybackState(_ state: PlayerEnginePlaybackState) {
        guard state != lastPlaybackState else { return }
        lastPlaybackState = state
        onPlaybackStateChange?(state)
    }

    private func resolvedDuration(durationHint: TimeInterval?) -> TimeInterval {
        let itemDuration = player.systemPlayer.currentItem?.duration.seconds ?? 0
        let rawDuration = itemDuration.isFinite && itemDuration > 0 ? itemDuration : 0
        if mediaTimeOffset > 0 {
            if let durationHint, durationHint > 0 {
                return durationHint
            }
            if let sourceDurationHint = source?.durationHint, sourceDurationHint > 0 {
                return sourceDurationHint
            }
            if rawDuration > mediaTimeOffset {
                return rawDuration - mediaTimeOffset
            }
        }
        if rawDuration > 0 {
            return rawDuration
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

private struct PillarboxVideoSurface: View {
    let player: Player
    let gravity: AVLayerVideoGravity

    var body: some View {
        VideoView(player: player)
            .gravity(gravity)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(Color.black)
            .clipped()
            .ignoresSafeArea()
    }
}

private extension UIView {
    var enclosingViewControllerForBili: UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController
            }
            responder = current.next
        }
        return nil
    }
}

private extension CMTimeRange {
    var isValidAndNotEmptyForBili: Bool {
        isValid && !isEmpty && start.isValid && duration.isValid && duration.seconds > 0
    }
}

private extension AVPlayerItem {
    var hasSeekableTimeRangesForBili: Bool {
        seekableTimeRanges
            .map(\.timeRangeValue)
            .contains { $0.isValidAndNotEmptyForBili }
    }
}
