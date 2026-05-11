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
    private let usesOwnedViewModel: Bool
    private let historyVideo: VideoItem?
    private let historyCID: Int?
    private let historyDuration: TimeInterval?
    private let presentation: BiliPlayerPresentation
    private let showsNavigationChrome: Bool
    private let showsPlaybackControls: Bool
    private let showsStartupLoadingIndicator: Bool
    private let pausesOnDisappear: Bool
    private let controlsAccessory: AnyView?
    private let controlsBottomLift: CGFloat
    private let durationHint: TimeInterval?
    private let embeddedAspectRatio: CGFloat
    private let ignoresContainerSafeArea: Bool
    private let manualFullscreenMode: ManualVideoFullscreenMode?
    private let onRequestManualFullscreen: (() -> Void)?
    private let onExitManualFullscreen: (() -> Void)?
    private var isManualFullscreenActive: Bool {
        manualFullscreenMode != nil
    }
    private var usesNativePlaybackControls: Bool {
        showsPlaybackControls && viewModel.usesNativePlaybackControls
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
        controlsAccessory: AnyView? = nil,
        controlsBottomLift: CGFloat = 0,
        embeddedAspectRatio: CGFloat = 16 / 9,
        ignoresContainerSafeArea: Bool = true,
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
        self.controlsAccessory = controlsAccessory
        self.controlsBottomLift = controlsBottomLift
        self.durationHint = duration
        self.embeddedAspectRatio = embeddedAspectRatio
        self.ignoresContainerSafeArea = ignoresContainerSafeArea
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
        controlsAccessory: AnyView? = nil,
        controlsBottomLift: CGFloat = 0,
        embeddedAspectRatio: CGFloat = 16 / 9,
        ignoresContainerSafeArea: Bool = true,
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
        self.controlsAccessory = controlsAccessory
        self.controlsBottomLift = controlsBottomLift
        self.durationHint = duration
        self.embeddedAspectRatio = embeddedAspectRatio
        self.ignoresContainerSafeArea = ignoresContainerSafeArea
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
        controlsAccessory: AnyView? = nil,
        controlsBottomLift: CGFloat = 0,
        embeddedAspectRatio: CGFloat = 16 / 9,
        ignoresContainerSafeArea: Bool = true,
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
        self.controlsAccessory = controlsAccessory
        self.controlsBottomLift = controlsBottomLift
        self.durationHint = duration
        self.embeddedAspectRatio = embeddedAspectRatio
        self.ignoresContainerSafeArea = ignoresContainerSafeArea
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
            metricsID: historyVideo?.bvid
        )
        _observedViewModel = ObservedObject(wrappedValue: playerViewModel)
        _ownedViewModel = StateObject(wrappedValue: playerViewModel)
    }

    var body: some View {
        Group {
            if presentation == .embedded {
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
        viewModel.setVideoGravity(.resizeAspect)
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

            if showsPlayerLoadingChrome {
                VStack(spacing: 7) {
                    ProgressView()
                    if viewModel.isBuffering {
                        Text("缂撳啿涓?)
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
                    onSingleTap: handlePlayerTap,
                    onDoubleTap: handlePlayerDoubleTap,
                    onLongPressStart: handlePlayerLongPressStart,
                    onLongPressEnd: handlePlayerLongPressEnd
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .zIndex(5)
            }

            if let gestureFeedback {
                playerGestureFeedbackView(gestureFeedback)
                    .transition(.scale(scale: 0.82).combined(with: .opacity))
                    .zIndex(6)
            }

            if usesCustomPlaybackControls, isManualFullscreenActive, controlsLocked, lockAffordanceVisible {
                lockedControlsAffordance
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    .zIndex(7)
            }

            if usesCustomPlaybackControls, controlsVisible {
                playerControls
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(8)
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
                videoGravity: .resizeAspect
            )
        } else {
            VideoSurfaceView(
                viewModel: viewModel,
                manualFullscreenMode: manualFullscreenMode,
                onExitManualFullscreen: onExitManualFullscreen
            )
        }
    }

    private var showsPlayerLoadingChrome: Bool {
        guard !usesNativePlaybackControls else { return false }
        guard viewModel.isPreparing || viewModel.isBuffering else { return false }
        return viewModel.hasPresentedPlayback || showsStartupLoadingIndicator
    }

    private var playerControls: some View {
        VStack(spacing: 6) {
            if let controlsAccessory {
                controlsAccessory
                    .padding(.horizontal, presentation == .embedded ? 10 : 16)
                    .padding(.bottom, presentation == .embedded ? 0 : 4)
            }

            if presentation == .embedded {
                embeddedPlayerControls
            } else {
                fullscreenPlayerControls
            }
        }
        .foregroundStyle(.white)
    }

    private var embeddedPlayerControls: some View {
        HStack(spacing: 6) {
            playerControlButton(
                systemName: viewModel.isPlaying ? "pause.fill" : "play.fill",
                isPrimary: true,
                isCompact: true
            ) {
                Haptics.light()
                viewModel.togglePlayback()
                handlePlayerInteraction()
            }

            inlineProgressBar
                .layoutPriority(1)

            if viewModel.isPictureInPictureSupported {
                playerControlButton(
                    systemName: viewModel.isPictureInPictureActive ? "pip.exit" : "pip.enter",
                    isCompact: true
                ) {
                    viewModel.togglePictureInPicture()
                    handlePlayerInteraction()
                }
            }

            if canRequestManualFullscreen {
                playerControlButton(systemName: "arrow.up.left.and.arrow.down.right", isCompact: true) {
                    Haptics.light()
                    _ = viewModel.requestHostFullscreen()
                    handlePlayerInteraction()
                }
            }

            speedMenu
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.clear)
                .biliGlassEffect(
                    tint: .black.opacity(0.22),
                    interactive: false,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 6 + controlsBottomLift)
    }

    private var fullscreenPlayerControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 9) {
                playerControlButton(systemName: "gobackward.10", isEnabled: viewModel.canSeek) {
                    Haptics.light()
                    viewModel.seek(by: -10)
                    handlePlayerInteraction()
                }

                playerControlButton(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill", isPrimary: true) {
                    Haptics.light()
                    viewModel.togglePlayback()
                    handlePlayerInteraction()
                }

                playerControlButton(systemName: "goforward.10", isEnabled: viewModel.canSeek) {
                    Haptics.light()
                    viewModel.seek(by: 10)
                    handlePlayerInteraction()
                }

                Spacer(minLength: 8)

                if isManualFullscreenActive {
                    playerControlButton(systemName: "arrow.down.right.and.arrow.up.left") {
                        exitManualFullscreen()
                    }

                    playerControlButton(systemName: controlsLocked ? "lock.fill" : "lock.open") {
                        toggleControlsLock()
                    }
                }

                if viewModel.isPictureInPictureSupported {
                    playerControlButton(systemName: viewModel.isPictureInPictureActive ? "pip.exit" : "pip.enter") {
                        viewModel.togglePictureInPicture()
                        handlePlayerInteraction()
                    }
                }

                if canRequestManualFullscreen {
                    playerControlButton(systemName: "arrow.up.left.and.arrow.down.right") {
                        Haptics.light()
                        _ = viewModel.requestHostFullscreen()
                        handlePlayerInteraction()
                    }
                }

                speedMenu
            }

            progressRow
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 20 + controlsBottomLift)
        .background(
            Rectangle()
                .fill(.clear)
                .biliGlassEffect(
                    tint: .black.opacity(0.26),
                    interactive: false,
                    in: Rectangle()
                )
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(.white.opacity(0.08))
                        .frame(height: 0.6)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var inlineProgressBar: some View {
        HStack(spacing: 5) {
            Text(BiliFormatters.duration(Int(viewModel.currentTime.rounded())))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.86))
                .frame(width: 36, alignment: .leading)

            compactProgressSlider
                .frame(height: 18)
                .layoutPriority(1)
        }
        .frame(minWidth: 0)
    }

    private var progressRow: some View {
        HStack(spacing: 10) {
            if let duration = displayDuration, duration > 0 {
                Text(BiliFormatters.duration(Int(viewModel.currentTime.rounded())))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 44, alignment: .leading)

                compactProgressSlider
                    .frame(height: 22)

                Text(BiliFormatters.duration(Int(duration.rounded())))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 44, alignment: .trailing)
            } else {
                Spacer(minLength: 8)
                Text(BiliFormatters.duration(Int(viewModel.currentTime.rounded())))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.92))
                Spacer(minLength: 8)
            }
        }
    }

    private var compactProgressSlider: some View {
        Slider(
            value: progressBinding,
            in: 0...1,
            onEditingChanged: handleScrubbingChanged
        )
        .tint(Color(red: 1.0, green: 0.25, blue: 0.50))
        .controlSize(.mini)
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
            .biliGlassButtonStyle()
            .tint(.white.opacity(0.18))
            .accessibilityLabel("瑙ｉ攣鎾斁鎺т欢")

            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.leading, 22)
        .padding(.trailing, 22)
        .padding(.bottom, 18 + controlsBottomLift)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
        .biliGlassButtonStyle()
        .tint(.white.opacity(0.18))
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
        .biliGlassButtonStyle(prominent: isPrimary)
        .tint(isPrimary ? Color(red: 1.0, green: 0.25, blue: 0.50) : .white.opacity(0.16))
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

    private func handlePlayerDoubleTap() {
        guard usesCustomPlaybackControls else { return }
        if controlsLocked {
            showLockAffordance()
            return
        }
        Haptics.medium()
        viewModel.togglePlayback()
        controlsVisible = true
        scheduleControlsAutoHideIfNeeded()
        showGestureFeedback(viewModel.isPlaying ? .pause : .play)
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
        VStack(spacing: 5) {
            Image(systemName: feedback.systemName)
                .font(.system(size: feedback.title == nil ? 34 : 24, weight: .bold))

            if let title = feedback.title {
                Text(title)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
            }
        }
            .foregroundStyle(.white)
            .frame(width: 86, height: 78)
            .background(.black.opacity(0.44))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.42), radius: 18, y: 8)
            .allowsHitTesting(false)
    }
}

private enum PlayerGestureFeedback: Equatable {
    case play
    case pause
    case speed(String)

    var systemName: String {
        switch self {
        case .play:
            return "play.fill"
        case .pause:
            return "pause.fill"
        case .speed:
            return "forward.fill"
        }
    }

    var title: String? {
        switch self {
        case .speed(let title):
            return title
        case .play, .pause:
            return nil
        }
    }

    var isSpeedFeedback: Bool {
        if case .speed = self {
            return true
        }
        return false
    }
}

private struct PlayerGestureOverlay: UIViewRepresentable {
    let onSingleTap: () -> Void
    let onDoubleTap: () -> Void
    let onLongPressStart: () -> Void
    let onLongPressEnd: () -> Void

    func makeUIView(context: Context) -> GestureOverlayView {
        let view = GestureOverlayView()
        view.onSingleTap = onSingleTap
        view.onDoubleTap = onDoubleTap
        view.onLongPressStart = onLongPressStart
        view.onLongPressEnd = onLongPressEnd
        return view
    }

    func updateUIView(_ uiView: GestureOverlayView, context: Context) {
        uiView.onSingleTap = onSingleTap
        uiView.onDoubleTap = onDoubleTap
        uiView.onLongPressStart = onLongPressStart
        uiView.onLongPressEnd = onLongPressEnd
        uiView.refreshGestureDependenciesIfNeeded()
    }

    final class GestureOverlayView: UIView, UIGestureRecognizerDelegate {
        var onSingleTap: (() -> Void)?
        var onDoubleTap: (() -> Void)?
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
            let gesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
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
            isUserInteractionEnabled = true
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

        @objc private func handleDoubleTap() {
            onDoubleTap?()
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
}
