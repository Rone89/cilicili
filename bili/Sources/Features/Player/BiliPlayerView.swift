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

@MainActor
private final class PlayerPlaybackProgressReporter: ObservableObject {
    private weak var clock: PlayerPlaybackClock?
    private var cancellable: AnyCancellable?
    private var report: ((TimeInterval) -> Void)?

    func start(clock: PlayerPlaybackClock, report: @escaping (TimeInterval) -> Void) {
        self.report = report
        guard self.clock !== clock else { return }

        cancellable?.cancel()
        self.clock = clock
        cancellable = clock.$currentTime
            .throttle(for: .seconds(5), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] time in
                self?.report?(time)
            }
    }

    func stop() {
        cancellable?.cancel()
        cancellable = nil
        clock = nil
        report = nil
    }
}

@MainActor
private final class PlayerViewModelBox: ObservableObject {
    let viewModel: PlayerStateViewModel

    init(viewModel: PlayerStateViewModel) {
        self.viewModel = viewModel
    }
}

private struct PlayerSurfaceSnapshot: Equatable {
    var isPlaying = false
    var canSeek = false
    var playbackRate: BiliPlaybackRate = .x10
    var isPreparing = true
    var isBuffering = false
    var isUserSeeking = false
    var loadingProgress = 0.08
    var errorMessage: String?
    var hasPresentedPlayback = false
    var isPictureInPictureSupported = false
    var isPictureInPictureActive = false
    var usesNativePlaybackControls = false

    @MainActor
    init(viewModel: PlayerStateViewModel? = nil) {
        guard let viewModel else { return }
        isPlaying = viewModel.isPlaying
        canSeek = viewModel.canSeek
        playbackRate = viewModel.playbackRate
        isPreparing = viewModel.isPreparing
        isBuffering = viewModel.isBuffering
        isUserSeeking = viewModel.isUserSeeking
        loadingProgress = viewModel.loadingProgress
        errorMessage = viewModel.errorMessage
        hasPresentedPlayback = viewModel.hasPresentedPlayback
        isPictureInPictureSupported = viewModel.isPictureInPictureSupported
        isPictureInPictureActive = viewModel.isPictureInPictureActive
        usesNativePlaybackControls = viewModel.usesNativePlaybackControls
    }
}

@MainActor
private final class PlayerSurfaceStateModel: ObservableObject {
    @Published private(set) var snapshot: PlayerSurfaceSnapshot

    private weak var viewModel: PlayerStateViewModel?
    private var cancellables = Set<AnyCancellable>()
    private var snapshotRefreshTask: Task<Void, Never>?

    init(viewModel: PlayerStateViewModel? = nil) {
        snapshot = PlayerSurfaceSnapshot(viewModel: viewModel)
    }

    var isPlaying: Bool { snapshot.isPlaying }
    var canSeek: Bool { snapshot.canSeek }
    var playbackRate: BiliPlaybackRate { snapshot.playbackRate }
    var isPreparing: Bool { snapshot.isPreparing }
    var isBuffering: Bool { snapshot.isBuffering }
    var isUserSeeking: Bool { snapshot.isUserSeeking }
    var loadingProgress: Double { snapshot.loadingProgress }
    var errorMessage: String? { snapshot.errorMessage }
    var hasPresentedPlayback: Bool { snapshot.hasPresentedPlayback }
    var isPictureInPictureSupported: Bool { snapshot.isPictureInPictureSupported }
    var isPictureInPictureActive: Bool { snapshot.isPictureInPictureActive }
    var usesNativePlaybackControls: Bool { snapshot.usesNativePlaybackControls }

    func bind(viewModel: PlayerStateViewModel) {
        guard self.viewModel !== viewModel else {
            refreshSnapshot(from: viewModel)
            return
        }
        cancellables.removeAll()
        self.viewModel = viewModel
        refreshSnapshot(from: viewModel)

        let refresh: () -> Void = { [weak self] in
            self?.scheduleSnapshotRefresh()
        }

        viewModel.$isPlaying
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)

        viewModel.$isSeekable
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)

        viewModel.$duration
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)

        viewModel.$playbackRate
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)

        viewModel.$isPreparing
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)

        viewModel.$isBuffering
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)

        viewModel.$isUserSeeking
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)

        viewModel.$loadingProgress
            .removeDuplicates { abs($0 - $1) < 0.01 }
            .sink { _ in refresh() }
            .store(in: &cancellables)

        viewModel.$errorMessage
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)

        viewModel.$hasPresentedPlayback
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)

        viewModel.$isPictureInPictureActive
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)

        viewModel.$engineDiagnostics
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)
    }

    private func scheduleSnapshotRefresh() {
        guard snapshotRefreshTask == nil else { return }
        snapshotRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard let self, !Task.isCancelled else { return }
            self.snapshotRefreshTask = nil
            guard let viewModel = self.viewModel else { return }
            self.refreshSnapshot(from: viewModel)
        }
    }

    private func refreshSnapshot(from viewModel: PlayerStateViewModel) {
        let nextSnapshot = PlayerSurfaceSnapshot(viewModel: viewModel)
        guard snapshot != nextSnapshot else { return }
        snapshot = nextSnapshot
    }

    deinit {
        snapshotRefreshTask?.cancel()
    }
}

private struct PlayerInlineLoadingIndicator: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(.white)
                .accessibilityHidden(true)

            Text(message)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.58), in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.10), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

struct BiliPlayerView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @StateObject private var viewModelBox: PlayerViewModelBox
    @StateObject private var surfaceState: PlayerSurfaceStateModel
    @State private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    @State private var lastPreparedScrubProgress = -1.0
    @State private var arePlaybackControlsVisible = true
    @State private var isPlaybackControlsAutoHideSuspended = false
    @State private var playbackControlsAutoHideTask: Task<Void, Never>?
    @StateObject private var progressReporter = PlayerPlaybackProgressReporter()
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
    private let topLeadingControlsAccessory: AnyView?
    private let controlsBottomLift: CGFloat
    private let isDanmakuEnabled: Bool
    private let onToggleDanmaku: (() -> Void)?
    private let onShowDanmakuSettings: (() -> Void)?
    private let isSecondaryControlsPresented: Bool
    private let durationHint: TimeInterval?
    private let embeddedAspectRatio: CGFloat
    private let ignoresContainerSafeArea: Bool
    private let keepsPlayerSurfaceStable: Bool
    private let fullscreenMode: PlayerFullscreenMode?
    private let onPrepareForUserSeek: ((Double) -> Void)?
    private let onRequestFullscreen: (() -> Void)?
    private let onExitFullscreen: (() -> Void)?
    private var isFullscreenActive: Bool {
        fullscreenMode != nil
    }
    private var canToggleFullscreen: Bool {
        if isFullscreenActive {
            return onExitFullscreen != nil
        }
        return onRequestFullscreen != nil
    }
    private var controlMetrics: PlayerNativeControlMetrics {
        if fullscreenMode?.isLandscape == true || verticalSizeClass == .compact {
            return .landscape
        }
        return .portrait
    }
    private var viewModel: PlayerStateViewModel {
        viewModelBox.viewModel
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
        topLeadingControlsAccessory: AnyView? = nil,
        controlsBottomLift: CGFloat = 0,
        isDanmakuEnabled: Bool = true,
        onToggleDanmaku: (() -> Void)? = nil,
        onShowDanmakuSettings: (() -> Void)? = nil,
        isSecondaryControlsPresented: Bool = false,
        embeddedAspectRatio: CGFloat = 16 / 9,
        ignoresContainerSafeArea: Bool = true,
        keepsPlayerSurfaceStable: Bool = false,
        prefersNativePlaybackControls: Bool = true,
        fullscreenMode: PlayerFullscreenMode? = nil,
        onPrepareForUserSeek: ((Double) -> Void)? = nil,
        onRequestFullscreen: (() -> Void)? = nil,
        onExitFullscreen: (() -> Void)? = nil
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
        self.topLeadingControlsAccessory = topLeadingControlsAccessory
        self.controlsBottomLift = controlsBottomLift
        self.isDanmakuEnabled = isDanmakuEnabled
        self.onToggleDanmaku = onToggleDanmaku
        self.onShowDanmakuSettings = onShowDanmakuSettings
        self.isSecondaryControlsPresented = isSecondaryControlsPresented
        self.durationHint = duration
        self.embeddedAspectRatio = embeddedAspectRatio
        self.ignoresContainerSafeArea = ignoresContainerSafeArea
        self.keepsPlayerSurfaceStable = keepsPlayerSurfaceStable
        self.fullscreenMode = fullscreenMode
        self.onPrepareForUserSeek = onPrepareForUserSeek
        self.onRequestFullscreen = onRequestFullscreen
        self.onExitFullscreen = onExitFullscreen
        _viewModelBox = StateObject(wrappedValue: PlayerViewModelBox(viewModel: viewModel))
        _surfaceState = StateObject(wrappedValue: PlayerSurfaceStateModel(viewModel: viewModel))
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
        topLeadingControlsAccessory: AnyView? = nil,
        controlsBottomLift: CGFloat = 0,
        isDanmakuEnabled: Bool = true,
        onToggleDanmaku: (() -> Void)? = nil,
        onShowDanmakuSettings: (() -> Void)? = nil,
        isSecondaryControlsPresented: Bool = false,
        embeddedAspectRatio: CGFloat = 16 / 9,
        ignoresContainerSafeArea: Bool = true,
        keepsPlayerSurfaceStable: Bool = false,
        prefersNativePlaybackControls: Bool = true,
        fullscreenMode: PlayerFullscreenMode? = nil,
        onPrepareForUserSeek: ((Double) -> Void)? = nil,
        onRequestFullscreen: (() -> Void)? = nil,
        onExitFullscreen: (() -> Void)? = nil
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
        self.topLeadingControlsAccessory = topLeadingControlsAccessory
        self.controlsBottomLift = controlsBottomLift
        self.isDanmakuEnabled = isDanmakuEnabled
        self.onToggleDanmaku = onToggleDanmaku
        self.onShowDanmakuSettings = onShowDanmakuSettings
        self.isSecondaryControlsPresented = isSecondaryControlsPresented
        self.durationHint = duration
        self.embeddedAspectRatio = embeddedAspectRatio
        self.ignoresContainerSafeArea = ignoresContainerSafeArea
        self.keepsPlayerSurfaceStable = keepsPlayerSurfaceStable
        self.fullscreenMode = fullscreenMode
        self.onPrepareForUserSeek = onPrepareForUserSeek
        self.onRequestFullscreen = onRequestFullscreen
        self.onExitFullscreen = onExitFullscreen
        let playerViewModel = PlayerStateViewModel(
            videoURL: videoURL,
            audioURL: nil,
            videoStream: nil,
            audioStream: nil,
            title: title,
            referer: referer,
            durationHint: duration,
            metricsID: historyVideo?.bvid,
            engine: DefaultPlayerRenderingEngine.make()
        )
        _viewModelBox = StateObject(wrappedValue: PlayerViewModelBox(viewModel: playerViewModel))
        _surfaceState = StateObject(wrappedValue: PlayerSurfaceStateModel(viewModel: playerViewModel))
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
        topLeadingControlsAccessory: AnyView? = nil,
        controlsBottomLift: CGFloat = 0,
        isDanmakuEnabled: Bool = true,
        onToggleDanmaku: (() -> Void)? = nil,
        onShowDanmakuSettings: (() -> Void)? = nil,
        isSecondaryControlsPresented: Bool = false,
        embeddedAspectRatio: CGFloat = 16 / 9,
        ignoresContainerSafeArea: Bool = true,
        keepsPlayerSurfaceStable: Bool = false,
        prefersNativePlaybackControls: Bool = true,
        cdnPreference: PlaybackCDNPreference = .automatic,
        fullscreenMode: PlayerFullscreenMode? = nil,
        onPrepareForUserSeek: ((Double) -> Void)? = nil,
        onRequestFullscreen: (() -> Void)? = nil,
        onExitFullscreen: (() -> Void)? = nil
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
        self.topLeadingControlsAccessory = topLeadingControlsAccessory
        self.controlsBottomLift = controlsBottomLift
        self.isDanmakuEnabled = isDanmakuEnabled
        self.onToggleDanmaku = onToggleDanmaku
        self.onShowDanmakuSettings = onShowDanmakuSettings
        self.isSecondaryControlsPresented = isSecondaryControlsPresented
        self.durationHint = duration
        self.embeddedAspectRatio = embeddedAspectRatio
        self.ignoresContainerSafeArea = ignoresContainerSafeArea
        self.keepsPlayerSurfaceStable = keepsPlayerSurfaceStable
        self.fullscreenMode = fullscreenMode
        self.onPrepareForUserSeek = onPrepareForUserSeek
        self.onRequestFullscreen = onRequestFullscreen
        self.onExitFullscreen = onExitFullscreen
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
        _viewModelBox = StateObject(wrappedValue: PlayerViewModelBox(viewModel: playerViewModel))
        _surfaceState = StateObject(wrappedValue: PlayerSurfaceStateModel(viewModel: playerViewModel))
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
            surfaceState.bind(viewModel: viewModel)
            isPlaybackControlsAutoHideSuspended = isSecondaryControlsPresented
            applyVideoGravity()
            applyPlaybackDefaults()
            if viewModel.wantsAutoplay {
                viewModel.play()
            }
            progressReporter.start(clock: viewModel.playbackClock) { time in
                savePlaybackProgress(time)
            }
            schedulePlaybackControlsAutoHide()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.recoverPlaybackAfterAppResume()
            } else if phase == .background {
                Task {
                    await VideoPreloadCenter.shared.cancelAll()
                }
                savePlaybackProgressInBackground()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            viewModel.recoverPlaybackAfterAppResume()
        }
        .onDisappear {
            savePlaybackProgress(viewModel.currentTime)
            progressReporter.stop()
            cancelPlaybackControlsAutoHide()
            endBackgroundTaskIfNeeded()
            guard pausesOnDisappear else { return }
            guard !isFullscreenActive else { return }
            viewModel.suspendForNavigation()
        }
        .onChange(of: isFullscreenActive) { _, _ in
            applyVideoGravity()
            showPlaybackControlsAndScheduleAutoHide()
        }
        .onChange(of: presentation) { _, _ in
            applyVideoGravity()
            showPlaybackControlsAndScheduleAutoHide()
        }
        .onChange(of: isSecondaryControlsPresented) { _, isPresented in
            isPlaybackControlsAutoHideSuspended = isPresented
            if isPresented {
                cancelPlaybackControlsAutoHide()
                showPlaybackControls(scheduleAutoHide: false)
            } else {
                schedulePlaybackControlsAutoHide()
            }
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
        guard time.isFinite, time >= 5 else { return }
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

    private var playerSurface: some View {
        ZStack(alignment: .bottom) {
            playbackSurface
                .contentShape(Rectangle())
                .gesture(playbackSurfaceTapGesture)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .background(.black)
                .zIndex(0)

            if let surfaceOverlay {
                surfaceOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .zIndex(1)
            }

            if showsPlayerLoadingChrome {
                VStack(spacing: 7) {
                    ProgressView()
                    if surfaceState.isBuffering {
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
                .allowsHitTesting(false)
                .zIndex(2)
            }

            if showsInlineLoadingProgress {
                PlayerInlineLoadingIndicator(
                    message: surfaceState.isUserSeeking ? "正在定位" : "正在缓冲"
                )
                .padding(.top, presentation == .embedded ? 10 : 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .allowsHitTesting(false)
                .zIndex(6)
            }

            if showsActivePlaybackControls, let topLeadingControlsAccessory {
                topLeadingControlsAccessory
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, presentation == .embedded ? 10 : 14)
                    .padding(.leading, presentation == .embedded ? 10 : 14)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
                    .zIndex(8)
            }

            if showsActivePlaybackControls {
                nativePlaybackControls
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, presentation == .embedded ? 10 : 14)
                    .padding(.bottom, (presentation == .embedded ? 8 : 14) + controlsBottomLift)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(7)
            }

            if let message = surfaceState.errorMessage {
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
                .allowsHitTesting(false)
                .zIndex(3)
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(.black)
        .environment(\.playerNativeControlMetrics, controlMetrics)
    }

    private var showsActivePlaybackControls: Bool {
        showsPlaybackControls && arePlaybackControlsVisible
    }

    private var nativePlaybackControls: some View {
        GlassEffectContainer(spacing: controlMetrics.groupSpacing) {
            VStack(spacing: controlMetrics.stackSpacing) {
                PlayerNativeProgressSlider(
                    clock: viewModel.playbackClock,
                    canSeek: surfaceState.canSeek,
                    sliderVisualScale: controlMetrics.sliderVisualScale,
                    onScrubStart: { progress in
                        markPlaybackControlsInteraction(keepsVisible: true)
                        prepareUserSeekWarmupIfNeeded(progress, force: true)
                    },
                    onScrubChanged: { progress in
                        prepareUserSeekWarmupIfNeeded(progress)
                    },
                    onScrubEnded: { progress in
                        prepareUserSeekWarmupIfNeeded(progress, force: true)
                        viewModel.seekAfterUserScrub(to: progress)
                        lastPreparedScrubProgress = -1
                        markPlaybackControlsInteraction()
                    }
                )
                .padding(.horizontal, controlMetrics.sliderHorizontalPadding)
                .frame(height: controlMetrics.progressControlHeight)

                HStack(spacing: controlMetrics.controlSpacing) {
                    Button {
                        markPlaybackControlsInteraction()
                        viewModel.togglePlayback()
                    } label: {
                        Image(systemName: surfaceState.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: controlMetrics.iconSize, weight: .semibold))
                            .frame(
                                width: controlMetrics.controlHeight,
                                height: controlMetrics.controlHeight
                            )
                    }
                    .biliPlayerCompactGlassCircle(metrics: controlMetrics)
                    .accessibilityLabel(surfaceState.isPlaying ? "暂停" : "播放")

                    PlayerNativeTimeLabel(clock: viewModel.playbackClock, metrics: controlMetrics)
                        .frame(
                            width: controlMetrics.timeLabelWidth,
                            height: controlMetrics.controlHeight
                        )
                        .biliPlayerClearGlass(interactive: false, in: Capsule())

                    Spacer(minLength: 0)

                    if let controlsAccessory {
                        controlsAccessory
                            .frame(height: controlMetrics.controlHeight)
                    }

                    if onShowDanmakuSettings != nil || onToggleDanmaku != nil {
                        Button {
                            if let onShowDanmakuSettings {
                                markPlaybackControlsInteraction(keepsVisible: true)
                                onShowDanmakuSettings()
                            } else {
                                markPlaybackControlsInteraction()
                                onToggleDanmaku?()
                            }
                        } label: {
                            Image(systemName: isDanmakuEnabled ? "text.bubble.fill" : "text.bubble")
                                .font(.system(size: controlMetrics.iconSize, weight: .semibold))
                                .frame(
                                    width: controlMetrics.controlHeight,
                                    height: controlMetrics.controlHeight
                                )
                        }
                        .biliPlayerCompactGlassCircle(metrics: controlMetrics)
                        .accessibilityLabel("弹幕设置")
                    }

                    if canToggleFullscreen {
                        Button {
                            markPlaybackControlsInteraction()
                            if isFullscreenActive {
                                onExitFullscreen?()
                            } else {
                                onRequestFullscreen?()
                            }
                        } label: {
                            Image(systemName: isFullscreenActive ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: controlMetrics.iconSize, weight: .semibold))
                                .frame(
                                    width: controlMetrics.controlHeight,
                                    height: controlMetrics.controlHeight
                                )
                        }
                        .biliPlayerCompactGlassCircle(metrics: controlMetrics)
                        .accessibilityLabel(isFullscreenActive ? "退出全屏" : "全屏")
                    }
                }
                .frame(height: controlMetrics.controlHeight)
            }
        }
        .foregroundStyle(.white)
        .controlSize(.mini)
    }

    private var playbackSurfaceTapGesture: some Gesture {
        TapGesture(count: 2)
            .exclusively(before: TapGesture(count: 1))
            .onEnded { value in
                switch value {
                case .first:
                    viewModel.togglePlayback()
                    showPlaybackControlsAndScheduleAutoHide()
                case .second:
                    togglePlaybackControlsVisibility()
                }
            }
    }

    private func togglePlaybackControlsVisibility() {
        guard showsPlaybackControls else { return }
        if arePlaybackControlsVisible {
            cancelPlaybackControlsAutoHide()
            withAnimation(.easeInOut(duration: 0.18)) {
                arePlaybackControlsVisible = false
            }
        } else {
            showPlaybackControlsAndScheduleAutoHide()
        }
    }

    private func showPlaybackControlsAndScheduleAutoHide() {
        showPlaybackControls(scheduleAutoHide: true)
    }

    private func markPlaybackControlsInteraction(keepsVisible: Bool = false) {
        showPlaybackControls(scheduleAutoHide: !keepsVisible)
        if keepsVisible {
            cancelPlaybackControlsAutoHide()
        }
    }

    private func showPlaybackControls(scheduleAutoHide: Bool) {
        guard showsPlaybackControls else { return }
        if !arePlaybackControlsVisible {
            withAnimation(.easeInOut(duration: 0.18)) {
                arePlaybackControlsVisible = true
            }
        }
        if scheduleAutoHide {
            schedulePlaybackControlsAutoHide()
        }
    }

    private func schedulePlaybackControlsAutoHide() {
        guard showsPlaybackControls, arePlaybackControlsVisible else { return }
        guard !isPlaybackControlsAutoHideSuspended else { return }
        cancelPlaybackControlsAutoHide()
        playbackControlsAutoHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            guard !isPlaybackControlsAutoHideSuspended else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                arePlaybackControlsVisible = false
            }
            playbackControlsAutoHideTask = nil
        }
    }

    private func cancelPlaybackControlsAutoHide() {
        playbackControlsAutoHideTask?.cancel()
        playbackControlsAutoHideTask = nil
    }

    @ViewBuilder
    private var playbackSurface: some View {
        VideoSurfaceView(
            viewModel: viewModel,
            prefersNativePlaybackControls: false
        )
    }

    private var videoGravity: AVLayerVideoGravity {
        .resizeAspect
    }

    private var showsPlayerLoadingChrome: Bool {
        guard surfaceState.isPreparing || surfaceState.isBuffering else { return false }
        guard !surfaceState.hasPresentedPlayback else { return false }
        return showsStartupLoadingIndicator
    }

    private var showsInlineLoadingProgress: Bool {
        guard surfaceState.hasPresentedPlayback else { return false }
        return surfaceState.isUserSeeking || surfaceState.isBuffering
    }

    private func prepareUserSeekWarmupIfNeeded(_ progress: Double, force: Bool = false) {
        let clampedProgress = min(max(progress, 0), 1)
        guard force || abs(clampedProgress - lastPreparedScrubProgress) >= 0.015 else { return }
        lastPreparedScrubProgress = clampedProgress
        onPrepareForUserSeek?(clampedProgress)
    }

}

struct PlayerNativeControlMetrics: Equatable {
    let controlHeight: CGFloat
    let progressControlHeight: CGFloat
    let sliderVisualScale: CGFloat
    let iconSize: CGFloat
    let timeFont: Font
    let stackSpacing: CGFloat
    let groupSpacing: CGFloat
    let controlSpacing: CGFloat
    let sliderHorizontalPadding: CGFloat
    let timeLabelWidth: CGFloat
    let qualityButtonMaxWidth: CGFloat
    let qualityHorizontalPadding: CGFloat

    static let portrait = PlayerNativeControlMetrics(
        controlHeight: 28,
        progressControlHeight: 22,
        sliderVisualScale: 0.82,
        iconSize: 12,
        timeFont: .caption2.monospacedDigit(),
        stackSpacing: 5,
        groupSpacing: 5,
        controlSpacing: 4,
        sliderHorizontalPadding: 8,
        timeLabelWidth: 62,
        qualityButtonMaxWidth: 68,
        qualityHorizontalPadding: 6
    )

    static let landscape = PlayerNativeControlMetrics(
        controlHeight: 34,
        progressControlHeight: 26,
        sliderVisualScale: 0.92,
        iconSize: 14,
        timeFont: .caption.monospacedDigit(),
        stackSpacing: 7,
        groupSpacing: 7,
        controlSpacing: 6,
        sliderHorizontalPadding: 11,
        timeLabelWidth: 86,
        qualityButtonMaxWidth: 92,
        qualityHorizontalPadding: 9
    )
}

private struct PlayerNativeControlMetricsKey: EnvironmentKey {
    static let defaultValue = PlayerNativeControlMetrics.portrait
}

extension EnvironmentValues {
    var playerNativeControlMetrics: PlayerNativeControlMetrics {
        get { self[PlayerNativeControlMetricsKey.self] }
        set { self[PlayerNativeControlMetricsKey.self] = newValue }
    }
}

private struct PlayerNativeProgressSlider: View {
    @ObservedObject var clock: PlayerPlaybackClock
    let canSeek: Bool
    let sliderVisualScale: CGFloat
    let onScrubStart: (Double) -> Void
    let onScrubChanged: (Double) -> Void
    let onScrubEnded: (Double) -> Void

    @State private var editingProgress = 0.0
    @State private var isEditing = false
    @State private var hasReportedScrubStart = false

    private var progressBinding: Binding<Double> {
        Binding(
            get: {
                isEditing ? editingProgress : clock.progress
            },
            set: { newValue in
                let clampedValue = min(max(newValue, 0), 1)
                if !isEditing {
                    beginScrub(at: clampedValue)
                }
                editingProgress = clampedValue
                onScrubChanged(clampedValue)
            }
        )
    }

    var body: some View {
        ZStack {
            ProgressView(value: displayProgress, total: 1)
                .progressViewStyle(.linear)
                .tint(.white)
                .opacity(isEditing ? 0 : 1)
                .allowsHitTesting(false)

            Slider(value: progressBinding, in: 0...1) { editing in
                if editing {
                    beginScrub(at: progressBinding.wrappedValue)
                } else {
                    finishScrub(at: progressBinding.wrappedValue)
                }
            }
            .labelsHidden()
            .tint(.white)
            .opacity(isEditing ? 1 : 0.001)
            .allowsHitTesting(effectiveCanSeek)

            GeometryReader { proxy in
                Color.clear
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard effectiveCanSeek else { return }
                                let progress = scrubProgress(
                                    locationX: value.location.x,
                                    width: proxy.size.width
                                )
                                beginScrub(at: progress)
                                editingProgress = progress
                                onScrubChanged(progress)
                            }
                            .onEnded { value in
                                guard effectiveCanSeek else { return }
                                let progress = scrubProgress(
                                    locationX: value.location.x,
                                    width: proxy.size.width
                                )
                                finishScrub(at: progress)
                            }
                    )
                    .allowsHitTesting(effectiveCanSeek)
            }
        }
        .disabled(!effectiveCanSeek)
        .controlSize(.mini)
        .scaleEffect(y: sliderVisualScale, anchor: .center)
        .accessibilityLabel("播放进度")
    }

    private var displayProgress: Double {
        min(max(isEditing ? editingProgress : clock.progress, 0), 1)
    }

    private var effectiveCanSeek: Bool {
        canSeek || (clock.duration ?? 0) > 0
    }

    private func beginScrub(at progress: Double) {
        guard effectiveCanSeek else { return }
        let clampedProgress = min(max(progress, 0), 1)
        if !hasReportedScrubStart {
            hasReportedScrubStart = true
            isEditing = true
            editingProgress = clampedProgress
            onScrubStart(clampedProgress)
        } else {
            isEditing = true
        }
    }

    private func finishScrub(at progress: Double) {
        guard effectiveCanSeek else { return }
        let clampedProgress = min(max(progress, 0), 1)
        editingProgress = clampedProgress
        hasReportedScrubStart = false
        isEditing = false
        onScrubEnded(clampedProgress)
    }

    private func scrubProgress(locationX: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(max(Double(locationX / width), 0), 1)
    }
}

private struct PlayerNativeTimeLabel: View {
    @ObservedObject var clock: PlayerPlaybackClock
    let metrics: PlayerNativeControlMetrics

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(fullTimeText)
            Text(currentText)
        }
            .font(metrics.timeFont)
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .accessibilityLabel("播放时间 \(fullTimeText)")
    }

    private var currentText: String {
        BiliFormatters.duration(Int(clock.currentTime.rounded()))
    }

    private var fullTimeText: String {
        guard let duration = clock.duration, duration > 0 else {
            return "\(currentText) / --:--"
        }
        return "\(currentText) / \(BiliFormatters.duration(Int(duration.rounded())))"
    }
}

private extension URL {
    var isLikelyHLSManifest: Bool {
        pathExtension.localizedCaseInsensitiveCompare("m3u8") == .orderedSame
            || absoluteString.range(of: ".m3u8", options: .caseInsensitive) != nil
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

extension View {
    @ViewBuilder
    func biliPlayerCompactGlassCircle(metrics: PlayerNativeControlMetrics) -> some View {
        buttonStyle(.plain)
            .contentShape(Circle())
            .biliPlayerClearGlass(interactive: true, in: Circle())
    }

    @ViewBuilder
    func biliPlayerCompactGlassCapsule(metrics: PlayerNativeControlMetrics) -> some View {
        buttonStyle(.plain)
            .contentShape(Capsule())
            .biliPlayerClearGlass(interactive: true, in: Capsule())
    }

    @ViewBuilder
    func biliPlayerClearGlass<S: Shape>(
        interactive: Bool,
        in shape: S
    ) -> some View {
        glassEffect(
            .clear
                .interactive(interactive),
            in: shape
        )
    }
}
