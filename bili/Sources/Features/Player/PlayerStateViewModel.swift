import AVFoundation
import AVKit
import Combine
import UIKit

@MainActor
final class PlayerStateViewModel: NSObject, ObservableObject {
    let title: String

    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval?
    @Published var isPlaying = false
    @Published var isSeekable = false
    @Published var danmakuEnabled = true
    @Published var danmakuOpacityPreset: BiliDanmakuOpacity = .normal
    @Published var danmakuFontScalePreset: BiliDanmakuFontScale = .normal
    @Published private(set) var visibleDanmakus: [DanmakuItem] = []
    @Published var playbackRate: BiliPlaybackRate = .x10
    @Published var isPreparing = true
    @Published var errorMessage: String?
    @Published var isPictureInPictureActive = false
    @Published private(set) var activeSponsorBlockSegment: SponsorBlockSegment?

    private(set) var wantsAutoplay = true
    private let danmakus: [DanmakuItem]
    private let streamSource: PlayerStreamSource
    private let durationHint: TimeInterval?
    private let resumeTime: TimeInterval
    private let engine: PlayerRenderingEngine
    private weak var surfaceView: VideoSurfaceContainerView?
    private var timeObserver: Timer?
    private var didApplyResumeTime = false
    private var mediaPreparationTask: Task<Void, Never>?
    private var scrubSeekTask: Task<Void, Never>?
    private var pictureInPictureController: AVPictureInPictureController?
    private var didConfigurePictureInPicture = false
    private var sponsorBlockSegments: [SponsorBlockSegment] = []
    private var skippedSponsorBlockIDs = Set<String>()
    private var sponsorBlockReportedIDs = Set<String>()
    private var sponsorBlockEnabled = false
    private var onSponsorBlockSegmentSkipped: (@Sendable (SponsorBlockSkipEvent) async -> Void)?
    private let playbackStateRefreshInterval: TimeInterval = 0.75
    private let sponsorBlockPrerollTolerance: TimeInterval = 0.35
    private let sponsorBlockTailTolerance: TimeInterval = 0.12
    private let maxVisibleDanmakuCount = 8

    init(
        videoURL: URL?,
        audioURL: URL?,
        videoStream: DASHStream? = nil,
        audioStream: DASHStream? = nil,
        title: String,
        danmakus: [DanmakuItem],
        referer: String,
        durationHint: TimeInterval? = nil,
        resumeTime: TimeInterval = 0,
        engine: PlayerRenderingEngine? = nil
    ) {
        self.title = title
        self.danmakus = danmakus.sorted { $0.time < $1.time }
        self.streamSource = PlayerStreamSource(
            videoURL: videoURL,
            audioURL: audioURL,
            videoStream: videoStream,
            audioStream: audioStream,
            referer: referer,
            durationHint: durationHint,
            resumeTime: resumeTime
        )
        self.durationHint = durationHint
        self.duration = durationHint
        self.resumeTime = resumeTime
        self.engine = engine ?? AVPlayerHLSBridgeEngine()
        super.init()
        startTimeObserver()
    }

    deinit {
        mediaPreparationTask?.cancel()
        scrubSeekTask?.cancel()
        timeObserver?.invalidate()
        let engine = engine
        Task { @MainActor in
            engine.stop()
        }
    }

    var canSeek: Bool {
        isSeekable || (duration ?? durationHint ?? 0) > 0
    }

    var danmakuOpacity: Double {
        danmakuOpacityPreset.rawValue
    }

    var danmakuFontScale: Double {
        danmakuFontScalePreset.rawValue
    }

    var isPictureInPictureSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    var displayDuration: TimeInterval? {
        duration ?? durationHint
    }

    var currentProgress: Double {
        guard let duration = displayDuration, duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    func attachSurface(_ view: VideoSurfaceContainerView) {
        let isNewSurface = surfaceView !== view
        surfaceView = view
        if isNewSurface {
            engine.attachSurface(view.drawableView)
        }
        configurePictureInPictureIfNeeded()
        if isNewSurface, engine.hasMedia {
            engine.refreshSurfaceLayout()
        }
    }

    func detachSurface(_ view: VideoSurfaceContainerView) {
        guard surfaceView === view else { return }
        engine.detachSurface(view.drawableView)
        surfaceView = nil
    }

    func refreshSurfaceLayout() {
        guard surfaceView != nil else { return }
        engine.refreshSurfaceLayout()
    }

    func recoverPlaybackAfterAppResume() {
        if timeObserver == nil {
            startTimeObserver()
        }
        engine.recoverSurface()
        refreshSurfaceLayout()
        configurePictureInPictureIfNeeded()
        pictureInPictureController?.invalidatePlaybackState()

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
        guard mediaPreparationTask == nil else { return }
        let restoreTime = currentTime
        isPreparing = false
        mediaPreparationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.engine.prepare(source: self.streamSource)
                guard !Task.isCancelled else { return }
                self.mediaPreparationTask = nil
                if restoreTime > 0, let time = self.engine.seek(toTime: restoreTime) {
                    self.updatePlaybackTime(time, force: true)
                }
                if self.wantsAutoplay {
                    self.startPreparedPlayback()
                } else {
                    self.refreshPlaybackState()
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.mediaPreparationTask = nil
                self.errorMessage = error.localizedDescription
                self.isPreparing = false
            }
        }
    }

    func play() {
        wantsAutoplay = true
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
        wantsAutoplay = true
        play()
    }

    func pause() {
        wantsAutoplay = false
        engine.pause()
        isPlaying = false
        pictureInPictureController?.invalidatePlaybackState()
    }

    func suspendForNavigation() {
        mediaPreparationTask?.cancel()
        mediaPreparationTask = nil
        pause()
    }

    func stop() {
        mediaPreparationTask?.cancel()
        mediaPreparationTask = nil
        scrubSeekTask?.cancel()
        scrubSeekTask = nil
        timeObserver?.invalidate()
        timeObserver = nil
        wantsAutoplay = false
        engine.stop()
        isPlaying = false
        isPreparing = false
        pictureInPictureController?.invalidatePlaybackState()
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to progress: Double) {
        guard engine.hasMedia else { return }
        if let time = engine.seek(toProgress: progress, duration: duration) {
            updatePlaybackTime(time, force: true)
        }
        pictureInPictureController?.invalidatePlaybackState()
    }

    func seekAfterUserScrub(to progress: Double) {
        guard engine.hasMedia else { return }
        wantsAutoplay = true
        scrubSeekTask?.cancel()
        scrubSeekTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let time = await self.engine.seekAfterUserScrub(toProgress: progress, duration: self.duration)
            guard !Task.isCancelled else { return }
            if let time {
                self.updatePlaybackTime(time, force: true)
            }
            self.startPreparedPlayback()
        }
    }

    func seek(by interval: TimeInterval) {
        guard engine.hasMedia else { return }
        if let time = engine.seek(by: interval, from: currentTime, duration: duration ?? durationHint) {
            updatePlaybackTime(time, force: true)
        }
        pictureInPictureController?.invalidatePlaybackState()
    }

    func setPlaybackRate(_ rate: BiliPlaybackRate) {
        playbackRate = rate
        engine.setPlaybackRate(rate.rawValue)
        pictureInPictureController?.invalidatePlaybackState()
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

    func setDanmakuEnabled(_ isEnabled: Bool) {
        danmakuEnabled = isEnabled
        if isEnabled {
            updateVisibleDanmakus(for: currentTime, force: true)
        } else {
            visibleDanmakus = []
        }
    }

    func setDanmakuOpacity(_ opacity: BiliDanmakuOpacity) {
        danmakuOpacityPreset = opacity
    }

    func setDanmakuFontScale(_ scale: BiliDanmakuFontScale) {
        danmakuFontScalePreset = scale
    }

    func togglePictureInPicture() {
        configurePictureInPictureIfNeeded()
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
        guard mediaPreparationTask == nil else { return }
        isPreparing = true
        mediaPreparationTask = Task { [weak self] in
            guard let self else { return }
        do {
            try await self.engine.prepare(source: self.streamSource)
            guard !Task.isCancelled else { return }
            self.mediaPreparationTask = nil
            if self.wantsAutoplay {
                self.startPreparedPlayback()
            } else {
                self.isPreparing = false
            }
        } catch {
                guard !Task.isCancelled else { return }
                self.mediaPreparationTask = nil
                self.errorMessage = error.localizedDescription
                self.isPreparing = false
            }
        }
    }

    private func startPreparedPlayback() {
        guard engine.hasMedia else { return }
        wantsAutoplay = true
        isPreparing = false
        isPlaying = true
        engine.play()
        engine.setPlaybackRate(playbackRate.rawValue)
        applyResumeTimeIfNeeded()
        pictureInPictureController?.invalidatePlaybackState()
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
        let snapshot = engine.snapshot(durationHint: durationHint)
        if let snapshotTime = snapshot.currentTime {
            updatePlaybackTime(snapshotTime)
            if isPreparing {
                isPreparing = false
            }
        }
        if let snapshotDuration = snapshot.duration {
            updateDuration(snapshotDuration)
        }
        if wantsAutoplay, engine.hasMedia, !snapshot.isPlaying, errorMessage == nil {
            engine.play()
            engine.setPlaybackRate(playbackRate.rawValue)
        }
        let shouldDisplayPlaying = snapshot.isPlaying || (wantsAutoplay && engine.hasMedia && errorMessage == nil)
        if isPlaying != shouldDisplayPlaying {
            isPlaying = shouldDisplayPlaying
        }
        if isSeekable != snapshot.isSeekable {
            isSeekable = snapshot.isSeekable
        }
        if let snapshotTime = snapshot.currentTime {
            skipSponsorBlockSegmentIfNeeded(at: snapshotTime)
        }
    }

    private func applyResumeTimeIfNeeded() {
        guard !didApplyResumeTime, resumeTime >= 10 else { return }
        didApplyResumeTime = true
        let milliseconds = Int32(min(resumeTime * 1000, Double(Int32.max)))
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let self else { return }
            if let time = self.engine.seek(toTime: TimeInterval(milliseconds) / 1000) {
                self.updatePlaybackTime(time, force: true)
            }
            if self.wantsAutoplay {
                self.engine.play()
                self.engine.setPlaybackRate(self.playbackRate.rawValue)
            }
        }
    }

    private func updatePlaybackTime(_ time: TimeInterval, force: Bool = false) {
        let normalizedTime = max(time, 0)
        if force || abs(currentTime - normalizedTime) >= 0.2 {
            currentTime = normalizedTime
        }
        updateVisibleDanmakus(for: normalizedTime, force: force)
    }

    private func updateDuration(_ newDuration: TimeInterval) {
        guard newDuration > 0 else { return }
        if let duration, abs(duration - newDuration) < 0.5 {
            return
        }
        duration = newDuration
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
        updatePlaybackTime(skippedTo, force: true)

        if wantsAutoplay {
            engine.play()
            engine.setPlaybackRate(playbackRate.rawValue)
        }
        pictureInPictureController?.invalidatePlaybackState()
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

    private func updateVisibleDanmakus(for time: TimeInterval, force: Bool = false) {
        guard danmakuEnabled, !danmakus.isEmpty else {
            if !visibleDanmakus.isEmpty {
                visibleDanmakus = []
            }
            return
        }

        let startTime = max(time - 4, 0)
        var lowerBound = 0
        var upperBound = danmakus.count
        while lowerBound < upperBound {
            let midpoint = (lowerBound + upperBound) / 2
            if danmakus[midpoint].time <= startTime {
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint
            }
        }

        var visible = [DanmakuItem]()
        visible.reserveCapacity(maxVisibleDanmakuCount)
        var index = lowerBound
        while index < danmakus.count,
              danmakus[index].time <= time,
              visible.count < maxVisibleDanmakuCount {
            visible.append(danmakus[index])
            index += 1
        }

        if force || visibleDanmakus != visible {
            visibleDanmakus = visible
        }
    }

    private func configurePictureInPictureIfNeeded() {
        guard !didConfigurePictureInPicture,
              isPictureInPictureSupported,
              let contentSource = engine.pictureInPictureContentSource()
        else { return }

        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        pictureInPictureController = controller
        didConfigurePictureInPicture = true
    }
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
