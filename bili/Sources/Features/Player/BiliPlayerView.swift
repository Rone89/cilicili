import AVFoundation
import Combine
import SwiftUI
import UIKit

enum BiliPlayerPresentation: Equatable {
    case fullScreen
    case embedded
}

enum BiliPlaybackRate: Double, CaseIterable, Identifiable {
    case x075 = 0.75
    case x10 = 1.0
    case x125 = 1.25
    case x15 = 1.5
    case x20 = 2.0

    var id: Double { rawValue }

    var title: String {
        rawValue == 1.0 ? "1.0x" : "\(rawValue.formatted(.number.precision(.fractionLength(0...2))))x"
    }
}

struct BiliPlayerView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var observedViewModel: PlayerStateViewModel
    @StateObject private var ownedViewModel: PlayerStateViewModel
    @State private var controlsVisible = true
    @State private var autoHideControlsTask: Task<Void, Never>?
    @State private var isScrubbing = false
    @State private var scrubProgress = 0.0
    @State private var controlsLocked = false
    @State private var lockAffordanceVisible = false
    @State private var autoHideLockTask: Task<Void, Never>?
    @State private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    @State private var gestureFeedback: PlayerGestureFeedback?
    @State private var gestureFeedbackTask: Task<Void, Never>?
    @State private var longPressRateRestoreValue: BiliPlaybackRate?
    @State private var playPauseIconScale: CGFloat = 1
    private let usesOwnedViewModel: Bool
    private let historyVideo: VideoItem?
    private let historyCID: Int?
    private let historyDuration: TimeInterval?
    private let presentation: BiliPlayerPresentation
    private let showsNavigationChrome: Bool
    private let showsPlaybackControls: Bool
    private let showsStartupLoadingIndicator: Bool
    private let pausesOnDisappear: Bool
    private let surfaceOverlay: AnyView?
    private let controlsAccessory: AnyView?
    private let controlsBottomLift: CGFloat
    private let isDanmakuEnabled: Bool
    private let onToggleDanmaku: (() -> Void)?
    private let onShowDanmakuSettings: (() -> Void)?
    private let durationHint: TimeInterval?
    private let embeddedAspectRatio: CGFloat
    private let ignoresContainerSafeArea: Bool
    private let keepsPlayerSurfaceStable: Bool
    private let prefersNativePlaybackControls: Bool
    private let manualFullscreenMode: ManualVideoFullscreenMode?
    private let onRequestManualFullscreen: (() -> Void)?
    private let onExitManualFullscreen: (() -> Void)?
    private var isManualFullscreenActive: Bool {
        manualFullscreenMode != nil
    }
    private var forcesDirectPlaybackSurface: Bool {
        !prefersNativePlaybackControls || presentation == .fullScreen || isManualFullscreenActive
    }
    private var usesNativePlaybackControls: Bool {
        showsPlaybackControls && viewModel.usesNativePlaybackControls && !forcesDirectPlaybackSurface
    }
    private var usesCustomPlaybackControls: Bool {
        showsPlaybackControls && !usesNativePlaybackControls
    }
    private var canRequestManualFullscreen: Bool {
        onRequestManualFullscreen != nil && !isManualFullscreenActive
    }
    private var viewModel: PlayerStateViewModel {
        usesOwnedViewModel ? ownedViewModel : observedViewModel
    }

    init(
        viewModel: PlayerStateViewModel,
        historyVideo: VideoItem? = nil,
        historyCID: Int? = nil,
        duration: TimeInterval? = nil,
        presentation: BiliPlayerPresentation = .fullScreen,
        showsNavigationChrome: Bool = true,
        showsPlaybackControls: Bool = true,
        showsStartupLoadingIndicator: Bool = true,
        pausesOnDisappear: Bool = true,
        surfaceOverlay: AnyView? = nil,
        controlsAccessory: AnyView? = nil,
        controlsBottomLift: CGFloat = 0,
        isDanmakuEnabled: Bool = true,
        onToggleDanmaku: (() -> Void)? = nil,
        onShowDanmakuSettings: (() -> Void)? = nil,
        embeddedAspectRatio: CGFloat = 16 / 9,
        ignoresContainerSafeArea: Bool = true,
        keepsPlayerSurfaceStable: Bool = false,
        prefersNativePlaybackControls: Bool = true,
        manualFullscreenMode: ManualVideoFullscreenMode? = nil,
        onRequestManualFullscreen: (() -> Void)? = nil,
        onExitManualFullscreen: (() -> Void)? = nil
    ) {
        self.historyVideo = historyVideo
        self.historyCID = historyCID
        self.historyDuration = historyVideo?.duration.map(TimeInterval.init)
        self.presentation = presentation
        self.showsNavigationChrome = showsNavigationChrome
        self.showsPlaybackControls = showsPlaybackControls
        self.showsStartupLoadingIndicator = showsStartupLoadingIndicator
        self.pausesOnDisappear = pausesOnDisappear
        self.surfaceOverlay = surfaceOverlay
        self.controlsAccessory = controlsAccessory
        self.controlsBottomLift = controlsBottomLift
        self.isDanmakuEnabled = isDanmakuEnabled
        self.onToggleDanmaku = onToggleDanmaku
        self.onShowDanmakuSettings = onShowDanmakuSettings
        self.durationHint = duration
        self.embeddedAspectRatio = embeddedAspectRatio
        self.ignoresContainerSafeArea = ignoresContainerSafeArea
        self.keepsPlayerSurfaceStable = keepsPlayerSurfaceStable
        self.prefersNativePlaybackControls = prefersNativePlaybackControls
        self.manualFullscreenMode = manualFullscreenMode
        self.onRequestManualFullscreen = onRequestManualFullscreen
        self.onExitManualFullscreen = onExitManualFullscreen
        self.usesOwnedViewModel = false
        _observedViewModel = ObservedObject(wrappedValue: viewModel)
        _ownedViewModel = StateObject(wrappedValue: viewModel)
    }

    init(
        videoURL: URL,
        title: String,
        referer: String = "https://www.bilibili.com",
        duration: TimeInterval? = nil,
        presentation: BiliPlayerPresentation = .fullScreen,
        showsNavigationChrome: Bool = true,
        showsPlaybackControls: Bool = true,
        showsStartupLoadingIndicator: Bool = true,
        pausesOnDisappear: Bool = true,
        surfaceOverlay: AnyView? = nil,
        controlsAccessory: AnyView? = nil,
        controlsBottomLift: CGFloat = 0,
        isDanmakuEnabled: Bool = true,
        onToggleDanmaku: (() -> Void)? = nil,
        onShowDanmakuSettings: (() -> Void)? = nil,
        embeddedAspectRatio: CGFloat = 16 / 9,
        ignoresContainerSafeArea: Bool = true,
        keepsPlayerSurfaceStable: Bool = false,
        prefersNativePlaybackControls: Bool = true,
        manualFullscreenMode: ManualVideoFullscreenMode? = nil,
        onRequestManualFullscreen: (() -> Void)? = nil,
        onExitManualFullscreen: (() -> Void)? = nil
    ) {
        self.historyVideo = nil
        self.historyCID = nil
        self.historyDuration = nil
        self.presentation = presentation
        self.showsNavigationChrome = showsNavigationChrome
        self.showsPlaybackControls = showsPlaybackControls
        self.showsStartupLoadingIndicator = showsStartupLoadingIndicator
        self.pausesOnDisappear = pausesOnDisappear
        self.surfaceOverlay = surfaceOverlay
        self.controlsAccessory = controlsAccessory
        self.controlsBottomLift = controlsBottomLift
        self.isDanmakuEnabled = isDanmakuEnabled
        self.onToggleDanmaku = onToggleDanmaku
        self.onShowDanmakuSettings = onShowDanmakuSettings
        self.durationHint = duration
        self.embeddedAspectRatio = embeddedAspectRatio
        self.ignoresContainerSafeArea = ignoresContainerSafeArea
        self.keepsPlayerSurfaceStable = keepsPlayerSurfaceStable
        self.prefersNativePlaybackControls = prefersNativePlaybackControls
        self.manualFullscreenMode = manualFullscreenMode
        self.onRequestManualFullscreen = onRequestManualFullscreen
        self.onExitManualFullscreen = onExitManualFullscreen
        self.usesOwnedViewModel = true
        let playerViewModel = PlayerStateViewModel(
            videoURL: videoURL,
            audioURL: nil,
            videoStream: nil,
            audioStream: nil,
            title: title,
            referer: referer,
            durationHint: duration,
            metricsID: historyVideo?.bvid
        )
        _observedViewModel = ObservedObject(wrappedValue: playerViewModel)
        _ownedViewModel = StateObject(wrappedValue: playerViewModel)
    }

    init(
        playVariant: PlayVariant,
        title: String,
        referer: String = "https://www.bilibili.com",
        duration: TimeInterval? = nil,
        resumeTime: TimeInterval? = nil,
        historyVideo: VideoItem? = nil,
        historyCID: Int? = nil,
        presentation: BiliPlayerPresentation = .fullScreen,
        showsNavigationChrome: Bool = true,
        showsPlaybackControls: Bool = true,
        showsStartupLoadingIndicator: Bool = true,
        pausesOnDisappear: Bool = true,
        surfaceOverlay: AnyView? = nil,
        controlsAccessory: AnyView? = nil,
        controlsBottomLift: CGFloat = 0,
        isDanmakuEnabled: Bool = true,
        onToggleDanmaku: (() -> Void)? = nil,
        onShowDanmakuSettings: (() -> Void)? = nil,
        embeddedAspectRatio: CGFloat = 16 / 9,
        ignoresContainerSafeArea: Bool = true,
        keepsPlayerSurfaceStable: Bool = false,
        prefersNativePlaybackControls: Bool = true,
        cdnPreference: PlaybackCDNPreference = .automatic,
        manualFullscreenMode: ManualVideoFullscreenMode? = nil,
        onRequestManualFullscreen: (() -> Void)? = nil,
        onExitManualFullscreen: (() -> Void)? = nil
    ) {
        self.historyVideo = historyVideo
        self.historyCID = historyCID
        self.historyDuration = historyVideo?.duration.map(TimeInterval.init)
        self.presentation = presentation
        self.showsNavigationChrome = showsNavigationChrome
        self.showsPlaybackControls = showsPlaybackControls
        self.showsStartupLoadingIndicator = showsStartupLoadingIndicator
        self.pausesOnDisappear = pausesOnDisappear
        self.surfaceOverlay = surfaceOverlay
        self.controlsAccessory = controlsAccessory
        self.controlsBottomLift = controlsBottomLift
        self.isDanmakuEnabled = isDanmakuEnabled
        self.onToggleDanmaku = onToggleDanmaku
        self.onShowDanmakuSettings = onShowDanmakuSettings
        self.durationHint = duration
        self.embeddedAspectRatio = embeddedAspectRatio
        self.ignoresContainerSafeArea = ignoresContainerSafeArea
        self.keepsPlayerSurfaceStable = keepsPlayerSurfaceStable
        self.prefersNativePlaybackControls = prefersNativePlaybackControls
        self.manualFullscreenMode = manualFullscreenMode
        self.onRequestManualFullscreen = onRequestManualFullscreen
        self.onExitManualFullscreen = onExitManualFullscreen
        self.usesOwnedViewModel = true
        let playerViewModel = PlayerStateViewModel(
            videoURL: playVariant.videoURL,
            audioURL: playVariant.audioURL,
            videoStream: playVariant.videoStream,
            audioStream: playVariant.audioStream,
            title: title,
            referer: referer,
            durationHint: duration,
            resumeTime: resumeTime ?? 0,
            dynamicRange: playVariant.dynamicRange,
            cdnPreference: cdnPreference,
            metricsID: historyVideo?.bvid
        )
        _observedViewModel = ObservedObject(wrappedValue: playerViewModel)
        _ownedViewModel = StateObject(wrappedValue: playerViewModel)
    }

    var body: some View {
        Group {
            if keepsPlayerSurfaceStable {
                playerSurface
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .clipped()
            } else if presentation == .embedded {
                Color.black
                    .aspectRatio(max(embeddedAspectRatio, 0.3), contentMode: .fit)
                    .overlay {
                        playerSurface
                    }
                    .clipped()
            } else if showsNavigationChrome {
                playerSurface
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .ignoresContainerSafeArea(ignoresContainerSafeArea)
                    .navigationTitle(viewModel.title)
                    .navigationBarTitleDisplayMode(.inline)
            } else {
                playerSurface
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .ignoresContainerSafeArea(ignoresContainerSafeArea)
            }
        }
        .onAppear {
            viewModel.setHostFullscreenRequestHandler(onRequestManualFullscreen)
            applyVideoGravity()
            applyPlaybackDefaults()
            reportPlaybackProgress(0)
            if viewModel.wantsAutoplay {
                viewModel.play()
            }
            controlsVisible = usesCustomPlaybackControls
            scheduleControlsAutoHideIfNeeded()
        }
        .onReceive(viewModel.$currentTime.throttle(for: .seconds(5), scheduler: RunLoop.main, latest: true)) { time in
            savePlaybackProgress(time)
        }
        .onChange(of: viewModel.isPlaying) { _, isPlaying in
            guard usesCustomPlaybackControls else {
                controlsVisible = false
                cancelControlsAutoHide()
                return
            }
            guard !controlsLocked else {
                controlsVisible = false
                cancelControlsAutoHide()
                return
            }
            if isPlaying {
                controlsVisible = true
                scheduleControlsAutoHideIfNeeded()
            } else {
                cancelControlsAutoHide()
                controlsVisible = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.recoverPlaybackAfterAppResume()
                scheduleControlsAutoHideIfNeeded()
            } else if phase == .background {
                Task {
                    await VideoPreloadCenter.shared.cancelAll()
                }
                restoreLongPressPlaybackRateIfNeeded()
                savePlaybackProgressInBackground()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            viewModel.recoverPlaybackAfterAppResume()
            scheduleControlsAutoHideIfNeeded()
        }
        .onDisappear {
            viewModel.setHostFullscreenRequestHandler(nil)
            restoreLongPressPlaybackRateIfNeeded()
            savePlaybackProgress(viewModel.currentTime)
            cancelControlsAutoHide()
            endBackgroundTaskIfNeeded()
            guard pausesOnDisappear else { return }
            guard !isManualFullscreenActive, !ManualVideoFullscreenSession.isActive else { return }
            viewModel.suspendForNavigation()
        }
        .onChange(of: isManualFullscreenActive) { _, isActive in
            if !isActive {
                controlsLocked = false
                lockAffordanceVisible = false
                cancelLockAutoHide()
            }
            applyVideoGravity()
        }
        .onChange(of: presentation) { _, _ in
            applyVideoGravity()
        }
    }

    private func applyVideoGravity() {
        viewModel.setVideoGravity(videoGravity)
    }

    private func savePlaybackProgress(_ time: TimeInterval) {
        reportPlaybackProgress(time)
    }

    private func savePlaybackProgressInBackground() {
        endBackgroundTaskIfNeeded()
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "cc.bili.player.progress") {
            endBackgroundTaskIfNeeded()
        }
        savePlaybackProgress(viewModel.currentTime)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            endBackgroundTaskIfNeeded()
        }
    }

    private func endBackgroundTaskIfNeeded() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    private func reportPlaybackProgress(_ time: TimeInterval) {
        guard !libraryStore.incognitoModeEnabled else { return }
        guard let aid = historyVideo?.aid else { return }
        Task {
            try? await dependencies.api.reportVideoHistory(
                aid: aid,
                cid: historyCID ?? historyVideo?.cid,
                progress: time,
                duration: historyDuration ?? durationHint ?? viewModel.duration
            )
        }
    }

    private func applyPlaybackDefaults() {
        viewModel.setPlaybackRate(BiliPlaybackRate(rawValue: libraryStore.defaultPlaybackRate) ?? .x10)
    }

    private var displayDuration: TimeInterval? {
        viewModel.displayDuration ?? durationHint
    }

    private var currentProgress: Double {
        viewModel.currentProgress
    }

    private var progressBinding: Binding<Double> {
        Binding(
            get: {
                isScrubbing ? scrubProgress : currentProgress
            },
            set: { newValue in
                scrubProgress = newValue
            }
        )
    }

    private var playerSurface: some View {
        ZStack(alignment: .bottom) {
            playbackSurface
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .background(.black)
                .zIndex(0)

            if let surfaceOverlay {
                surfaceOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(1)
            }

            if showsPlayerLoadingChrome {
                VStack(spacing: 7) {
                    ProgressView()
                    if viewModel.isBuffering {
                        Text("缓冲中")
                            .font(.caption2.weight(.medium))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.black.opacity(0.5))
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .padding(presentation == .embedded ? 12 : 16)
                .zIndex(2)
            }

            if let message = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(message)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(.black.opacity(0.72))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(presentation == .embedded ? 10 : 16)
                .zIndex(3)
            }

            if usesCustomPlaybackControls {
                PlayerGestureOverlay(
                    isEnabled: gestureOverlayAllowsHitTesting,
                    onSingleTap: handlePlayerTap,
                    onDoubleTap: handlePlayerDoubleTap,
                    onLongPressStart: handlePlayerLongPressStart,
                    onLongPressEnd: handlePlayerLongPressEnd
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .zIndex(5)
            }

            if usesCustomPlaybackControls, controlsVisible, !controlsLocked {
                telegramCenterTransportControls
                    .transition(.opacity.combined(with: .scale(scale: 0.88)))
                    .zIndex(6)
            }

            if let gestureFeedback {
                playerGestureFeedbackView(gestureFeedback)
                    .transition(.scale(scale: 0.82).combined(with: .opacity))
                    .zIndex(7)
            }

            if usesCustomPlaybackControls, isManualFullscreenActive, controlsLocked, lockAffordanceVisible {
                lockedControlsAffordance
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    .zIndex(8)
            }

            if usesCustomPlaybackControls, controlsVisible {
                playerControls
                    .transition(.opacity)
                    .zIndex(9)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(.black)
        .animation(.easeInOut(duration: 0.18), value: controlsVisible)
        .animation(.easeInOut(duration: 0.18), value: lockAffordanceVisible)
        .animation(.snappy(duration: 0.2), value: gestureFeedback)
    }

    @ViewBuilder
    private var playbackSurface: some View {
        if usesNativePlaybackControls {
            NativePlayerControllerView(
                viewModel: viewModel,
                videoGravity: videoGravity
            )
        } else {
            VideoSurfaceView(
                viewModel: viewModel,
                prefersNativePlaybackControls: usesNativePlaybackControls,
                manualFullscreenMode: manualFullscreenMode,
                onExitManualFullscreen: onExitManualFullscreen,
                manualFullscreenOverlay: surfaceOverlay,
                isDanmakuEnabled: isDanmakuEnabled,
                onToggleDanmaku: onToggleDanmaku,
                onShowDanmakuSettings: onShowDanmakuSettings
            )
        }
    }

    private var videoGravity: AVLayerVideoGravity {
        .resizeAspect
    }

    private var showsPlayerLoadingChrome: Bool {
        guard !usesNativePlaybackControls else { return false }
        guard viewModel.isPreparing || viewModel.isBuffering else { return false }
        return viewModel.hasPresentedPlayback || showsStartupLoadingIndicator
    }

    private var gestureOverlayAllowsHitTesting: Bool {
        guard usesCustomPlaybackControls else { return false }
        if controlsLocked {
            return true
        }
        return !controlsVisible
    }

    private var playerControls: some View {
        GlassEffectContainer(spacing: presentation == .embedded ? 6 : 10) {
            VStack(spacing: 0) {
                if let controlsAccessory {
                    controlsAccessory
                        .padding(.horizontal, presentation == .embedded ? 10 : 16)
                        .padding(.bottom, presentation == .embedded ? 0 : 2)
                }

                if presentation == .embedded {
                    embeddedPlayerControls
                } else {
                    fullscreenPlayerControls
                }
            }
        }
        .foregroundStyle(.white)
    }

    private var embeddedPlayerControls: some View {
        VStack(spacing: 8) {
            topToolRow(isCompact: true)
            bottomTimeline(isCompact: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .padding(.bottom, controlsBottomLift)
    }

    private var fullscreenPlayerControls: some View {
        VStack(spacing: 0) {
            topToolRow(isCompact: false)
                .padding(.top, isManualFullscreenActive ? 12 : 18)
                .padding(.horizontal, 16)

            Spacer(minLength: 0)

            bottomTimeline(isCompact: false)
                .padding(.horizontal, 18)
                .padding(.bottom, 18 + controlsBottomLift)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var compactProgressSlider: some View {
        LiquidPlayerProgressSlider(
            value: progressBinding,
            in: 0...1,
            tint: Color(red: 1.0, green: 0.25, blue: 0.50),
            onEditingChanged: handleScrubbingChanged
        )
    }

    private var lockedControlsAffordance: some View {
        HStack {
            Button {
                unlockControls()
            } label: {
                Image(systemName: "lock.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .liquidPlayerGlass(in: Circle(), tint: .black.opacity(0.035), stroke: .white.opacity(0.30))
            .shadow(color: .black.opacity(0.28), radius: 12, y: 5)
            .accessibilityLabel("解锁播放控件")

            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.leading, 22)
        .padding(.trailing, 22)
        .padding(.bottom, 18 + controlsBottomLift)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var telegramCenterTransportControls: some View {
        HStack(spacing: presentation == .embedded ? 18 : 26) {
            telegramTransportButton(systemName: "gobackward.10", size: presentation == .embedded ? 46 : 54, isEnabled: viewModel.canSeek) {
                seekByGesture(-10)
            }

            telegramTransportButton(
                systemName: viewModel.isPlaying ? "pause.fill" : "play.fill",
                size: presentation == .embedded ? 64 : 78,
                isPrimary: true,
                iconOffsetX: viewModel.isPlaying ? 0 : 3,
                isEnabled: true
            ) {
                Haptics.medium()
                withAnimation(.bouncy(duration: 0.22, extraBounce: 0.16)) {
                    playPauseIconScale = 0.9
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    withAnimation(.bouncy(duration: 0.26, extraBounce: 0.18)) {
                        playPauseIconScale = 1
                    }
                }
                viewModel.togglePlayback()
                handlePlayerInteraction()
            }
            .scaleEffect(playPauseIconScale)

            telegramTransportButton(systemName: "goforward.10", size: presentation == .embedded ? 46 : 54, isEnabled: viewModel.canSeek) {
                seekByGesture(10)
            }
        }
        .padding(.horizontal, presentation == .embedded ? 18 : 26)
        .padding(.vertical, presentation == .embedded ? 10 : 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func topToolRow(isCompact: Bool) -> some View {
        HStack(spacing: isCompact ? 7 : 9) {
            if isManualFullscreenActive {
                playerControlButton(systemName: "xmark", isCompact: isCompact) {
                    exitManualFullscreen()
                }
            }

            Spacer(minLength: 8)

            if isManualFullscreenActive {
                playerControlButton(systemName: controlsLocked ? "lock.fill" : "lock.open", isCompact: isCompact) {
                    toggleControlsLock()
                }
            }

            if viewModel.isPictureInPictureSupported {
                playerControlButton(systemName: viewModel.isPictureInPictureActive ? "pip.exit" : "pip.enter", isCompact: isCompact) {
                    viewModel.togglePictureInPicture()
                    handlePlayerInteraction()
                }
            }

            if canRequestManualFullscreen {
                playerControlButton(systemName: "arrow.up.left.and.arrow.down.right", isCompact: isCompact) {
                    Haptics.light()
                    onRequestManualFullscreen?()
                    handlePlayerInteraction()
                }
            }

            speedMenu
        }
        .frame(maxWidth: .infinity)
    }

    private func bottomTimeline(isCompact: Bool) -> some View {
        HStack(spacing: isCompact ? 7 : 10) {
            Text(BiliFormatters.duration(Int(viewModel.currentTime.rounded())))
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: isCompact ? 38 : 46, alignment: .leading)

            compactProgressSlider
                .frame(height: isCompact ? 18 : 24)
                .layoutPriority(1)

            if let duration = displayDuration, duration > 0 {
                Text(BiliFormatters.duration(Int(duration.rounded())))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(width: isCompact ? 38 : 46, alignment: .trailing)
            }
        }
        .padding(.horizontal, isCompact ? 10 : 12)
        .padding(.vertical, isCompact ? 6 : 8)
        .liquidPlayerGlassCapsule(tint: .black.opacity(0.035), stroke: .white.opacity(0.34))
        .shadow(color: .black.opacity(0.20), radius: 12, y: 5)
    }

    private var speedMenu: some View {
        Menu {
            ForEach(BiliPlaybackRate.allCases) { rate in
                Button {
                    viewModel.setPlaybackRate(rate)
                    libraryStore.setDefaultPlaybackRate(rate.rawValue)
                    handlePlayerInteraction()
                } label: {
                    Label(rate.title, systemImage: viewModel.playbackRate == rate ? "checkmark" : "speedometer")
                }
            }
        } label: {
            if presentation == .embedded {
                Text(compactPlaybackRateTitle)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .frame(width: 30, height: 28)
            } else {
                Text(viewModel.playbackRate.title)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .frame(minWidth: 50, minHeight: 36)
                    .padding(.horizontal, 2)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .liquidPlayerGlassCapsule(tint: .black.opacity(0.03), stroke: .white.opacity(0.32), interactive: true)
        .shadow(color: .black.opacity(0.20), radius: 10, y: 4)
    }

    private var compactPlaybackRateTitle: String {
        if viewModel.playbackRate == .x10 {
            return "1x"
        }
        return viewModel.playbackRate.title.replacingOccurrences(of: ".0x", with: "x")
    }

    private func playerControlButton(
        systemName: String,
        isEnabled: Bool = true,
        isPrimary: Bool = false,
        isCompact: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let size: CGFloat = isCompact ? (isPrimary ? 32 : 28) : (isPrimary ? 40 : 34)
        return Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: isCompact ? (isPrimary ? 13.5 : 12) : (isPrimary ? 16 : 13.5), weight: isPrimary ? .bold : .semibold))
                .frame(width: size, height: size)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .liquidPlayerGlass(
            in: Circle(),
            tint: .black.opacity(isPrimary ? 0.045 : 0.03),
            stroke: .white.opacity(isPrimary ? 0.34 : 0.30)
        )
        .shadow(color: .black.opacity(isPrimary ? 0.26 : 0.18), radius: isPrimary ? 12 : 9, y: isPrimary ? 5 : 4)
    }

    private func telegramTransportButton(
        systemName: String,
        size: CGFloat,
        isPrimary: Bool = false,
        iconOffsetX: CGFloat = 0,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: isPrimary ? size * 0.36 : size * 0.29, weight: .bold))
                .offset(x: iconOffsetX)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.38)
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .glassEffect(
            .regular
                .tint(.black.opacity(isPrimary ? 0.055 : 0.035))
                .interactive(true),
            in: Circle()
        )
        .overlay(
            Circle()
                .stroke(.white.opacity(isPrimary ? 0.34 : 0.30), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(isPrimary ? 0.28 : 0.20), radius: isPrimary ? 18 : 12, y: isPrimary ? 8 : 5)
    }

    private func handlePlayerTap() {
        guard usesCustomPlaybackControls else { return }
        if controlsLocked {
            showLockAffordance()
            return
        }
        withAnimation(.easeInOut(duration: 0.18)) {
            controlsVisible.toggle()
        }
        if controlsVisible {
            scheduleControlsAutoHideIfNeeded()
        } else {
            cancelControlsAutoHide()
        }
    }

    private func handlePlayerDoubleTap(_ region: PlayerGestureRegion) {
        guard usesCustomPlaybackControls else { return }
        if controlsLocked {
            showLockAffordance()
            return
        }
        Haptics.medium()
        switch region {
        case .leading:
            guard viewModel.canSeek else { return }
            seekByGesture(-10)
        case .trailing:
            guard viewModel.canSeek else { return }
            seekByGesture(10)
        case .center:
            viewModel.togglePlayback()
            controlsVisible = true
            scheduleControlsAutoHideIfNeeded()
            showGestureFeedback(viewModel.isPlaying ? .pause : .play)
        }
    }

    private func seekByGesture(_ seconds: TimeInterval) {
        guard viewModel.canSeek else { return }
        Haptics.light()
        viewModel.seek(by: seconds)
        if controlsVisible {
            scheduleControlsAutoHideIfNeeded()
        }
        showGestureFeedback(seconds < 0 ? .seekBackward(seconds: Int(abs(seconds))) : .seekForward(seconds: Int(seconds)))
    }

    private func handlePlayerLongPressStart() {
        guard usesCustomPlaybackControls else { return }
        guard !controlsLocked else {
            showLockAffordance()
            return
        }
        guard viewModel.isPlaying, longPressRateRestoreValue == nil else { return }
        longPressRateRestoreValue = viewModel.playbackRate
        Haptics.medium()
        viewModel.setPlaybackRate(.x20)
        controlsVisible = false
        cancelControlsAutoHide()
        showGestureFeedback(.speed("2.0x"))
    }

    private func handlePlayerLongPressEnd() {
        restoreLongPressPlaybackRateIfNeeded()
        if !controlsLocked {
            scheduleControlsAutoHideIfNeeded()
        }
    }

    private func handlePlayerInteraction() {
        guard usesCustomPlaybackControls else { return }
        guard !controlsLocked else {
            showLockAffordance()
            return
        }
        controlsVisible = true
        scheduleControlsAutoHideIfNeeded()
    }

    private func handleScrubbingChanged(_ editing: Bool) {
        guard usesCustomPlaybackControls else { return }
        if editing {
            isScrubbing = true
            scrubProgress = currentProgress
            cancelControlsAutoHide()
            controlsVisible = true
        } else {
            isScrubbing = false
            Haptics.light()
            viewModel.seekAfterUserScrub(to: scrubProgress)
            scheduleControlsAutoHideIfNeeded()
        }
    }

    private func scheduleControlsAutoHideIfNeeded() {
        cancelControlsAutoHide()
        guard usesCustomPlaybackControls else { return }
        guard !controlsLocked else { return }
        guard viewModel.isPlaying else { return }
        autoHideControlsTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard !Task.isCancelled, viewModel.isPlaying, !isScrubbing else { return }
            controlsVisible = false
        }
    }

    private func cancelControlsAutoHide() {
        autoHideControlsTask?.cancel()
        autoHideControlsTask = nil
    }

    private func restoreLongPressPlaybackRateIfNeeded() {
        guard let restoreRate = longPressRateRestoreValue else { return }
        longPressRateRestoreValue = nil
        viewModel.setPlaybackRate(restoreRate)
        gestureFeedbackTask?.cancel()
        if gestureFeedback?.isSpeedFeedback == true {
            gestureFeedback = nil
        }
    }

    private func toggleControlsLock() {
        if controlsLocked {
            unlockControls()
        } else {
            lockControls()
        }
    }

    private func exitManualFullscreen() {
        guard isManualFullscreenActive else { return }
        Haptics.light()
        controlsLocked = false
        lockAffordanceVisible = false
        cancelLockAutoHide()
        onExitManualFullscreen?()
    }

    private func lockControls() {
        guard isManualFullscreenActive else { return }
        Haptics.light()
        controlsLocked = true
        controlsVisible = false
        lockAffordanceVisible = true
        cancelControlsAutoHide()
        scheduleLockAutoHide()
    }

    private func unlockControls() {
        Haptics.light()
        controlsLocked = false
        lockAffordanceVisible = false
        cancelLockAutoHide()
        controlsVisible = true
        scheduleControlsAutoHideIfNeeded()
    }

    private func showLockAffordance() {
        guard controlsLocked else { return }
        lockAffordanceVisible = true
        scheduleLockAutoHide()
    }

    private func scheduleLockAutoHide() {
        cancelLockAutoHide()
        guard controlsLocked else { return }
        autoHideLockTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled, controlsLocked else { return }
            lockAffordanceVisible = false
        }
    }

    private func cancelLockAutoHide() {
        autoHideLockTask?.cancel()
        autoHideLockTask = nil
    }

    private func showGestureFeedback(_ feedback: PlayerGestureFeedback) {
        gestureFeedbackTask?.cancel()
        gestureFeedback = feedback
        guard !feedback.isSpeedFeedback else { return }
        gestureFeedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 620_000_000)
            guard !Task.isCancelled else { return }
            gestureFeedback = nil
        }
    }

    private func playerGestureFeedbackView(_ feedback: PlayerGestureFeedback) -> some View {
        let horizontalPadding: CGFloat = presentation == .embedded ? 26 : 62

        return VStack(spacing: 5) {
            Image(systemName: feedback.systemName)
                .font(.system(size: feedback.title == nil ? 34 : 24, weight: .bold))

            if let title = feedback.title {
                Text(title)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
            }
        }
            .foregroundStyle(.white)
            .frame(width: feedback.width, height: 78)
            .background(.black.opacity(0.44))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.42), radius: 18, y: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: feedback.alignment)
            .padding(.horizontal, horizontalPadding)
            .allowsHitTesting(false)
    }
}

private enum PlayerGestureRegion: Equatable {
    case leading
    case center
    case trailing

    init(locationX: CGFloat, width: CGFloat) {
        guard width > 0 else {
            self = .center
            return
        }
        let ratio = locationX / width
        if ratio < 0.38 {
            self = .leading
        } else if ratio > 0.62 {
            self = .trailing
        } else {
            self = .center
        }
    }
}

private enum PlayerGestureFeedback: Equatable {
    case play
    case pause
    case seekBackward(seconds: Int)
    case seekForward(seconds: Int)
    case speed(String)

    var systemName: String {
        switch self {
        case .play:
            return "play.fill"
        case .pause:
            return "pause.fill"
        case .seekBackward(let seconds):
            return "gobackward.\(seconds)"
        case .seekForward(let seconds):
            return "goforward.\(seconds)"
        case .speed:
            return "forward.fill"
        }
    }

    var title: String? {
        switch self {
        case .speed(let title):
            return title
        case .seekBackward(let seconds):
            return "-\(seconds)s"
        case .seekForward(let seconds):
            return "+\(seconds)s"
        case .play, .pause:
            return nil
        }
    }

    var alignment: Alignment {
        switch self {
        case .seekBackward:
            return .leading
        case .seekForward:
            return .trailing
        case .play, .pause, .speed:
            return .center
        }
    }

    var width: CGFloat {
        title == nil ? 86 : 96
    }

    var isSpeedFeedback: Bool {
        if case .speed = self {
            return true
        }
        return false
    }
}

private struct LiquidPlayerProgressSlider: UIViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let tint: Color
    let onEditingChanged: (Bool) -> Void

    init(
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        tint: Color,
        onEditingChanged: @escaping (Bool) -> Void
    ) {
        _value = value
        self.range = range
        self.tint = tint
        self.onEditingChanged = onEditingChanged
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, onEditingChanged: onEditingChanged)
    }

    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider()
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.value = Float(value)
        slider.minimumTrackTintColor = UIColor(tint)
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.20)
        slider.setMinimumTrackImage(Self.trackImage(height: 4, color: UIColor(tint)), for: .normal)
        slider.setMaximumTrackImage(Self.trackImage(height: 4, color: UIColor.white.withAlphaComponent(0.20)), for: .normal)
        slider.setThumbImage(Self.thumbImage(visualDiameter: 9, canvasDiameter: 30, color: .white), for: .normal)
        slider.setThumbImage(Self.thumbImage(visualDiameter: 13, canvasDiameter: 34, color: .white), for: .highlighted)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.touchDown(_:)), for: .touchDown)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.touchUp(_:)),
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )
        return slider
    }

    func updateUIView(_ slider: UISlider, context: Context) {
        context.coordinator.value = $value
        context.coordinator.onEditingChanged = onEditingChanged
        let lower = Float(range.lowerBound)
        let upper = Float(range.upperBound)
        if slider.minimumValue != lower {
            slider.minimumValue = lower
        }
        if slider.maximumValue != upper {
            slider.maximumValue = upper
        }
        let newValue = Float(value)
        if !context.coordinator.isEditing, abs(slider.value - newValue) > 0.001 {
            slider.setValue(newValue, animated: false)
        }
    }

    private static func trackImage(height: CGFloat, color: UIColor) -> UIImage {
        let size = CGSize(width: 12, height: height)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            color.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: height / 2).fill()
        }
        let cap = max(1, height / 2)
        return image.resizableImage(
            withCapInsets: UIEdgeInsets(top: 0, left: cap, bottom: 0, right: cap),
            resizingMode: .stretch
        )
    }

    private static func thumbImage(visualDiameter: CGFloat, canvasDiameter: CGFloat, color: UIColor) -> UIImage {
        let size = CGSize(width: canvasDiameter, height: canvasDiameter)
        return UIGraphicsImageRenderer(size: size).image { context in
            let rect = CGRect(
                x: (canvasDiameter - visualDiameter) / 2,
                y: (canvasDiameter - visualDiameter) / 2,
                width: visualDiameter,
                height: visualDiameter
            )
            context.cgContext.setShadow(
                offset: CGSize(width: 0, height: 1.5),
                blur: 5,
                color: UIColor.black.withAlphaComponent(0.22).cgColor
            )
            color.setFill()
            context.cgContext.fillEllipse(in: rect)
        }
    }

    final class Coordinator: NSObject {
        var value: Binding<Double>
        var onEditingChanged: (Bool) -> Void
        var isEditing = false

        init(value: Binding<Double>, onEditingChanged: @escaping (Bool) -> Void) {
            self.value = value
            self.onEditingChanged = onEditingChanged
        }

        @objc func touchDown(_ slider: UISlider) {
            isEditing = true
            onEditingChanged(true)
            value.wrappedValue = Double(slider.value)
        }

        @objc func valueChanged(_ slider: UISlider) {
            value.wrappedValue = Double(slider.value)
        }

        @objc func touchUp(_ slider: UISlider) {
            value.wrappedValue = Double(slider.value)
            isEditing = false
            onEditingChanged(false)
        }
    }
}

private struct PlayerGestureOverlay: UIViewRepresentable {
    let isEnabled: Bool
    let onSingleTap: () -> Void
    let onDoubleTap: (PlayerGestureRegion) -> Void
    let onLongPressStart: () -> Void
    let onLongPressEnd: () -> Void

    func makeUIView(context: Context) -> GestureOverlayView {
        let view = GestureOverlayView()
        view.isGestureOverlayEnabled = isEnabled
        view.onSingleTap = onSingleTap
        view.onDoubleTap = onDoubleTap
        view.onLongPressStart = onLongPressStart
        view.onLongPressEnd = onLongPressEnd
        return view
    }

    func updateUIView(_ uiView: GestureOverlayView, context: Context) {
        uiView.isGestureOverlayEnabled = isEnabled
        uiView.onSingleTap = onSingleTap
        uiView.onDoubleTap = onDoubleTap
        uiView.onLongPressStart = onLongPressStart
        uiView.onLongPressEnd = onLongPressEnd
        uiView.refreshGestureDependenciesIfNeeded()
    }

    final class GestureOverlayView: UIView, UIGestureRecognizerDelegate {
        var isGestureOverlayEnabled = true {
            didSet {
                guard isGestureOverlayEnabled != oldValue else { return }
                isUserInteractionEnabled = isGestureOverlayEnabled
                singleTapGesture.isEnabled = isGestureOverlayEnabled
                doubleTapGesture.isEnabled = isGestureOverlayEnabled
                longPressGesture.isEnabled = isGestureOverlayEnabled
            }
        }
        var onSingleTap: (() -> Void)?
        var onDoubleTap: ((PlayerGestureRegion) -> Void)?
        var onLongPressStart: (() -> Void)?
        var onLongPressEnd: (() -> Void)?

        private weak var attachedNavigationController: UINavigationController?
        private weak var attachedPopGesture: UIGestureRecognizer?
        private weak var attachedContentPopGesture: UIGestureRecognizer?
        private lazy var singleTapGesture: UITapGestureRecognizer = {
            let gesture = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
            gesture.numberOfTapsRequired = 1
            gesture.cancelsTouchesInView = false
            gesture.delegate = self
            return gesture
        }()
        private lazy var doubleTapGesture: UITapGestureRecognizer = {
            let gesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            gesture.numberOfTapsRequired = 2
            gesture.cancelsTouchesInView = false
            gesture.delegate = self
            return gesture
        }()
        private lazy var longPressGesture: UILongPressGestureRecognizer = {
            let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
            gesture.minimumPressDuration = 0.38
            gesture.allowableMovement = 18
            gesture.cancelsTouchesInView = false
            gesture.delegate = self
            return gesture
        }()

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = isGestureOverlayEnabled
            singleTapGesture.require(toFail: doubleTapGesture)
            addGestureRecognizer(singleTapGesture)
            addGestureRecognizer(doubleTapGesture)
            addGestureRecognizer(longPressGesture)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            refreshGestureDependenciesIfNeeded()
        }

        @objc private func handleSingleTap() {
            onSingleTap?()
        }

        @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            let location = recognizer.location(in: self)
            onDoubleTap?(PlayerGestureRegion(locationX: location.x, width: bounds.width))
        }

        @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began:
                onLongPressStart?()
            case .ended, .cancelled, .failed:
                onLongPressEnd?()
            default:
                break
            }
        }

        func refreshGestureDependenciesIfNeeded() {
            guard let navigationController = enclosingNavigationController() else { return }
            attachedNavigationController = navigationController

            if let popGesture = navigationController.interactivePopGestureRecognizer,
               attachedPopGesture !== popGesture {
                singleTapGesture.require(toFail: popGesture)
                doubleTapGesture.require(toFail: popGesture)
                attachedPopGesture = popGesture
            }
            if let contentPopGesture = navigationController.interactiveContentPopGestureRecognizer,
               attachedContentPopGesture !== contentPopGesture {
                singleTapGesture.require(toFail: contentPopGesture)
                doubleTapGesture.require(toFail: contentPopGesture)
                attachedContentPopGesture = contentPopGesture
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            otherGestureRecognizer == attachedNavigationController?.interactiveContentPopGestureRecognizer
                || otherGestureRecognizer == attachedNavigationController?.interactivePopGestureRecognizer
        }

        private func enclosingNavigationController() -> UINavigationController? {
            var responder: UIResponder? = self
            while let current = responder {
                if let viewController = current as? UIViewController, let navigationController = viewController.navigationController {
                    return navigationController
                }
                responder = current.next
            }
            return nil
        }
    }
}

private extension View {
    @ViewBuilder
    func ignoresContainerSafeArea(_ isEnabled: Bool) -> some View {
        if isEnabled {
            ignoresSafeArea()
        } else {
            self
        }
    }

    func liquidPlayerGlass<S: Shape>(
        in shape: S,
        tint: Color,
        stroke: Color = .white.opacity(0.2),
        interactive: Bool = true
    ) -> some View {
        glassEffect(
            .regular
                .tint(tint)
                .interactive(interactive),
            in: shape
        )
        .overlay(
            shape
                .stroke(stroke, lineWidth: 0.8)
        )
        .overlay(
            shape
                .stroke(.white.opacity(0.12), lineWidth: 0.35)
                .blur(radius: 0.6)
                .offset(y: -0.5)
        )
    }

    func liquidPlayerGlassCapsule(
        tint: Color,
        stroke: Color = .white.opacity(0.2),
        interactive: Bool = false
    ) -> some View {
        liquidPlayerGlass(
            in: Capsule(),
            tint: tint,
            stroke: stroke,
            interactive: interactive
        )
    }
}
