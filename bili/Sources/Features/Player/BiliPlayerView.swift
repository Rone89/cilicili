import AVFoundation
import Combine
import OSLog
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

enum PlayerLongPressSpeedBoost {
    struct Profile: Equatable {
        let rate: BiliPlaybackRate
        let sustainedRate: BiliPlaybackRate
        let feedbackTitle: String
        let sustainedFeedbackTitle: String
        let sustainAfterNanoseconds: UInt64
        let maximumDurationNanoseconds: UInt64
        let isGuarded: Bool

        var usesSustainedStepDown: Bool {
            sustainedRate != rate
        }

        var startupRate: BiliPlaybackRate {
            rate.rawValue > BiliPlaybackRate.x15.rawValue ? .x15 : rate
        }

        var startupFeedbackTitle: String {
            startupRate.rawValue == rate.rawValue ? feedbackTitle : startupRate.title
        }

        var usesPeakRampUp: Bool {
            startupRate.rawValue != rate.rawValue
        }

        var peakRampAfterNanoseconds: UInt64 {
            isGuarded ? 0 : 620_000_000
        }
    }

    static let rate: BiliPlaybackRate = .x20
    static let sustainedRate: BiliPlaybackRate = .x15
    static let feedbackTitle = "2.0x"
    static let sustainedFeedbackTitle = "1.5x"

    static var sustainAfterNanoseconds: UInt64 {
        PlaybackEnvironment.current.shouldPreferConservativePlayback
            ? 1_900_000_000
            : 2_700_000_000
    }

    static var maximumDurationNanoseconds: UInt64 {
        PlaybackEnvironment.current.shouldPreferConservativePlayback
            ? 4_200_000_000
            : 5_200_000_000
    }

    static func profile(
        for diagnostics: PlayerEngineDiagnostics,
        environment: PlaybackEnvironment = .current
    ) -> Profile {
        if diagnostics.decodePath == .sampleBuffer {
            return Profile(
                rate: .x15,
                sustainedRate: .x125,
                feedbackTitle: "1.5x",
                sustainedFeedbackTitle: "1.25x",
                sustainAfterNanoseconds: environment.shouldPreferConservativePlayback
                    ? 1_250_000_000
                    : 1_650_000_000,
                maximumDurationNanoseconds: environment.shouldPreferConservativePlayback
                    ? 3_200_000_000
                    : 4_000_000_000,
                isGuarded: true
            )
        }
        if shouldUseGuardedProfile(for: diagnostics, environment: environment) {
            return Profile(
                rate: .x15,
                sustainedRate: .x125,
                feedbackTitle: "1.5x",
                sustainedFeedbackTitle: "1.25x",
                sustainAfterNanoseconds: environment.shouldPreferConservativePlayback
                    ? 1_800_000_000
                    : 2_400_000_000,
                maximumDurationNanoseconds: environment.shouldPreferConservativePlayback
                    ? 4_000_000_000
                    : 5_000_000_000,
                isGuarded: true
            )
        }

        return Profile(
            rate: rate,
            sustainedRate: sustainedRate,
            feedbackTitle: feedbackTitle,
            sustainedFeedbackTitle: sustainedFeedbackTitle,
            sustainAfterNanoseconds: sustainAfterNanoseconds,
            maximumDurationNanoseconds: maximumDurationNanoseconds,
            isGuarded: false
        )
    }

    private static func shouldUseGuardedProfile(
        for diagnostics: PlayerEngineDiagnostics,
        environment: PlaybackEnvironment
    ) -> Bool {
        if diagnostics.decodePath == .unknown || diagnostics.engineName == "未创建" {
            return true
        }
        if environment.shouldPreferConservativePlayback {
            return true
        }
        if diagnostics.dynamicRange.isHDR {
            return true
        }
        if (diagnostics.bandwidth ?? 0) >= 8_000_000 {
            return true
        }
        let frameRate = diagnostics.frameRate.flatMap(DASHStream.numericFrameRate(from:)) ?? 0
        return frameRate >= 50
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
private final class PlayerClockDisplayModel: ObservableObject {
    @Published private(set) var snapshot = PlayerClockDisplaySnapshot()

    private weak var clock: PlayerPlaybackClock?
    private var cancellables = Set<AnyCancellable>()

    var currentText: String { snapshot.currentText }
    var durationText: String? { snapshot.durationText }
    var summaryText: String { snapshot.summaryText }

    func bind(clock: PlayerPlaybackClock) {
        guard self.clock !== clock else { return }
        cancellables.removeAll()
        self.clock = clock
        update(currentSecond: Self.secondBucket(for: clock.currentTime), durationSecond: clock.duration.map(Self.secondBucket(for:)))

        Publishers.CombineLatest(
            clock.$currentTime
                .map(Self.secondBucket(for:))
                .removeDuplicates(),
            clock.$duration
                .map { duration in
                    duration.map(Self.secondBucket(for:))
                }
                .removeDuplicates()
        )
        .sink { [weak self] currentSecond, durationSecond in
            self?.update(currentSecond: currentSecond, durationSecond: durationSecond)
        }
        .store(in: &cancellables)
    }

    private func update(currentSecond: Int, durationSecond: Int?) {
        let next = PlayerClockDisplaySnapshot(
            currentSecond: currentSecond,
            durationSecond: durationSecond
        )
        guard next != snapshot else { return }
        snapshot = next
    }

    private static func secondBucket(for time: TimeInterval) -> Int {
        max(0, Int(time.rounded()))
    }
}

private struct PlayerClockDisplaySnapshot: Equatable {
    let currentSecond: Int
    let durationSecond: Int?
    let currentText: String
    let durationText: String?
    let summaryText: String

    init(currentSecond: Int = 0, durationSecond: Int? = nil) {
        let currentText = BiliFormatters.duration(currentSecond)
        let durationText: String?
        if let durationSecond, durationSecond > 0 {
            durationText = BiliFormatters.duration(durationSecond)
        } else {
            durationText = nil
        }

        self.currentSecond = currentSecond
        self.durationSecond = durationSecond
        self.currentText = currentText
        self.durationText = durationText
        self.summaryText = durationText.map { "\(currentText) / \($0)" } ?? "\(currentText) / --:--"
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
    let progress: Double
    let message: String

    private var normalizedProgress: Double {
        min(max(progress, 0), 0.98)
    }

    var body: some View {
        HStack(spacing: 8) {
            PlayerLoadingSpinner(size: 14, lineWidth: 2, accentColor: PlayerControlPalette.bilibiliPink)

            Text(message)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            PlayerLoadingProgressBar(
                progress: normalizedProgress,
                width: 68,
                height: 3,
                accentColor: PlayerControlPalette.bilibiliPink
            )

            Text("\(Int((normalizedProgress * 100).rounded()))%")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white.opacity(0.74))
                .frame(width: 30, alignment: .trailing)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
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
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModelBox: PlayerViewModelBox
    @StateObject private var surfaceState: PlayerSurfaceStateModel
    @StateObject private var runtimeSettings = PlayerRuntimeSettingsStore()
    @State private var controlsVisible = true
    @State private var autoHideControlsTask: Task<Void, Never>?
    @State private var isScrubbing = false
    @State private var scrubProgress = 0.0
    @State private var lastPreparedScrubProgress = -1.0
    @State private var controlsLocked = false
    @State private var lockAffordanceVisible = false
    @State private var autoHideLockTask: Task<Void, Never>?
    @State private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    @State private var gestureFeedback: PlayerGestureFeedback?
    @State private var gestureFeedbackTask: Task<Void, Never>?
    @State private var gesturePanMode: PlayerGesturePanMode = .none
    @State private var gesturePanStartProgress = 0.0
    @State private var gesturePanStartVolume: Float = 1
    @State private var gesturePanStartBrightness: CGFloat = 0.5
    @State private var longPressRateRestoreValue: BiliPlaybackRate?
    @State private var longPressSpeedBoostTask: Task<Void, Never>?
    @State private var longPressSpeedBoostSignpostState: OSSignpostIntervalState?
    @State private var playPauseIconScale: CGFloat = 1
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
    private let durationHint: TimeInterval?
    private let embeddedAspectRatio: CGFloat
    private let ignoresContainerSafeArea: Bool
    private let keepsPlayerSurfaceStable: Bool
    private let prefersNativePlaybackControls: Bool
    private let manualFullscreenMode: ManualVideoFullscreenMode?
    private let onPrepareForUserSeek: ((Double) -> Void)?
    private let onRequestManualFullscreen: (() -> Void)?
    private let onExitManualFullscreen: (() -> Void)?
    private var isManualFullscreenActive: Bool {
        manualFullscreenMode != nil
    }
    private var forcesDirectPlaybackSurface: Bool {
        !prefersNativePlaybackControls || presentation == .fullScreen || isManualFullscreenActive
    }
    private var usesNativePlaybackControls: Bool {
        showsPlaybackControls && surfaceState.usesNativePlaybackControls && !forcesDirectPlaybackSurface
    }
    private var usesCustomPlaybackControls: Bool {
        showsPlaybackControls && !usesNativePlaybackControls
    }
    private var canRequestManualFullscreen: Bool {
        onRequestManualFullscreen != nil && !isManualFullscreenActive
    }
    private var chromeState: PlayerChromeState {
        PlayerChromeState(
            usesCustomControls: usesCustomPlaybackControls,
            controlsVisible: controlsVisible,
            controlsLocked: controlsLocked,
            lockAffordanceVisible: lockAffordanceVisible,
            isManualFullscreenActive: isManualFullscreenActive
        )
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
        embeddedAspectRatio: CGFloat = 16 / 9,
        ignoresContainerSafeArea: Bool = true,
        keepsPlayerSurfaceStable: Bool = false,
        prefersNativePlaybackControls: Bool = true,
        manualFullscreenMode: ManualVideoFullscreenMode? = nil,
        onPrepareForUserSeek: ((Double) -> Void)? = nil,
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
        self.topLeadingControlsAccessory = topLeadingControlsAccessory
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
        self.onPrepareForUserSeek = onPrepareForUserSeek
        self.onRequestManualFullscreen = onRequestManualFullscreen
        self.onExitManualFullscreen = onExitManualFullscreen
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
        embeddedAspectRatio: CGFloat = 16 / 9,
        ignoresContainerSafeArea: Bool = true,
        keepsPlayerSurfaceStable: Bool = false,
        prefersNativePlaybackControls: Bool = true,
        manualFullscreenMode: ManualVideoFullscreenMode? = nil,
        onPrepareForUserSeek: ((Double) -> Void)? = nil,
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
        self.topLeadingControlsAccessory = topLeadingControlsAccessory
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
        self.onPrepareForUserSeek = onPrepareForUserSeek
        self.onRequestManualFullscreen = onRequestManualFullscreen
        self.onExitManualFullscreen = onExitManualFullscreen
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
        embeddedAspectRatio: CGFloat = 16 / 9,
        ignoresContainerSafeArea: Bool = true,
        keepsPlayerSurfaceStable: Bool = false,
        prefersNativePlaybackControls: Bool = true,
        cdnPreference: PlaybackCDNPreference = .automatic,
        manualFullscreenMode: ManualVideoFullscreenMode? = nil,
        onPrepareForUserSeek: ((Double) -> Void)? = nil,
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
        self.topLeadingControlsAccessory = topLeadingControlsAccessory
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
        self.onPrepareForUserSeek = onPrepareForUserSeek
        self.onRequestManualFullscreen = onRequestManualFullscreen
        self.onExitManualFullscreen = onExitManualFullscreen
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
            runtimeSettings.bind(dependencies.libraryStore)
            surfaceState.bind(viewModel: viewModel)
            viewModel.setHostFullscreenRequestHandler(onRequestManualFullscreen)
            applyVideoGravity()
            applyPlaybackDefaults()
            if viewModel.wantsAutoplay {
                viewModel.play()
            }
            progressReporter.start(clock: viewModel.playbackClock) { time in
                savePlaybackProgress(time)
            }
            controlsVisible = usesCustomPlaybackControls
            scheduleControlsAutoHideIfNeeded()
        }
        .onChange(of: surfaceState.isPlaying) { _, isPlaying in
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
                restoreLongPressPlaybackRateIfNeeded()
                cancelControlsAutoHide()
                controlsVisible = true
            }
        }
        .onChange(of: surfaceState.isBuffering) { _, isBuffering in
            guard isBuffering else { return }
            restoreLongPressPlaybackRateForPressureIfNeeded()
        }
        .onChange(of: scrubProgress) { _, progress in
            guard isScrubbing else { return }
            prepareUserSeekWarmupIfNeeded(progress)
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
        .onChange(of: isManualFullscreenActive) { _, isActive in
            guard isActive, usesCustomPlaybackControls, surfaceState.isPlaying else { return }
            controlsVisible = true
            scheduleControlsAutoHideIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            viewModel.recoverPlaybackAfterAppResume()
            scheduleControlsAutoHideIfNeeded()
        }
        .onDisappear {
            viewModel.setHostFullscreenRequestHandler(nil)
            restoreLongPressPlaybackRateIfNeeded()
            savePlaybackProgress(viewModel.currentTime)
            progressReporter.stop()
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
        guard !runtimeSettings.incognitoModeEnabled else { return }
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
        viewModel.setPlaybackRate(BiliPlaybackRate(rawValue: runtimeSettings.defaultPlaybackRate) ?? .x10)
    }

    private var displayDuration: TimeInterval? {
        viewModel.displayDuration ?? durationHint
    }

    private var currentProgress: Double {
        viewModel.playbackClock.progress
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
                PlayerInlineLoadingIndicator(
                    progress: surfaceState.loadingProgress,
                    message: surfaceState.isBuffering ? "正在缓冲" : "准备播放"
                )
                .padding(presentation == .embedded ? 12 : 16)
                .zIndex(2)
            }

            if showsInlineLoadingProgress {
                PlayerInlineLoadingIndicator(
                    progress: surfaceState.loadingProgress,
                    message: surfaceState.isUserSeeking ? "定位进度" : "补充缓冲"
                )
                .padding(.top, presentation == .embedded ? 10 : 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(6)
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
                .zIndex(3)
            }

            let currentChromeState = chromeState

            if currentChromeState.showsGestureOverlay {
                PlayerGestureOverlay(
                    isEnabled: currentChromeState.showsGestureOverlay,
                    respectsSystemEdgeGestures: !isManualFullscreenActive,
                    onSingleTap: handlePlayerTap,
                    onDoubleTap: handlePlayerDoubleTap,
                    onPanChanged: handlePlayerPanChanged,
                    onPanEnded: handlePlayerPanEnded,
                    onLongPressStart: handlePlayerLongPressStart,
                    onLongPressEnd: handlePlayerLongPressEnd
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .zIndex(5)
            }

            if let gestureFeedback {
                playerGestureFeedbackContainer(gestureFeedback)
                    .transition(.scale(scale: 0.82).combined(with: .opacity))
                    .zIndex(7)
            }

            if currentChromeState.showsLockAffordance {
                lockedControlsAffordance
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    .zIndex(8)
            }

            if currentChromeState.showsPlaybackChrome {
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
                onShowDanmakuSettings: onShowDanmakuSettings,
                onPrepareForUserSeek: onPrepareForUserSeek
            )
        }
    }

    private var videoGravity: AVLayerVideoGravity {
        .resizeAspect
    }

    private var showsPlayerLoadingChrome: Bool {
        guard !usesNativePlaybackControls else { return false }
        guard surfaceState.isPreparing || surfaceState.isBuffering else { return false }
        guard !surfaceState.hasPresentedPlayback else { return false }
        return showsStartupLoadingIndicator
    }

    private var showsInlineLoadingProgress: Bool {
        guard !usesNativePlaybackControls else { return false }
        guard surfaceState.hasPresentedPlayback else { return false }
        return surfaceState.isUserSeeking || surfaceState.isBuffering
    }

    private var playerControls: some View {
        Group {
            if presentation == .embedded {
                embeddedBiliPlayerControls
            } else {
                fullscreenBiliPlayerControls
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
    }

    private var embeddedBiliPlayerControls: some View {
        ZStack {
            VStack(spacing: 0) {
                PlayerControlScrim(edge: .top, height: 64, opacity: 0.36)
                Spacer(minLength: 0)
                PlayerControlScrim(edge: .bottom, height: 110, opacity: 0.70)
            }
            .allowsHitTesting(false)

            if let topLeadingControlsAccessory {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        topLeadingControlsAccessory
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 8)
                .padding(.horizontal, 8)
            }

            nativeBottomPanel(isCompact: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, 10)
                .padding(.bottom, 7 + controlsBottomLift)
        }
    }

    private var fullscreenBiliPlayerControls: some View {
        ZStack {
            VStack(spacing: 0) {
                PlayerControlScrim(edge: .top, height: 112, opacity: 0.56)
                Spacer(minLength: 0)
                PlayerControlScrim(edge: .bottom, height: 154, opacity: 0.72)
            }
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                nativeTopBar
                    .padding(.top, isManualFullscreenActive ? 10 : 16)
                    .padding(.horizontal, 16)

                Spacer(minLength: 0)

                nativeBottomPanel(isCompact: false)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16 + controlsBottomLift)
            }
        }
    }

    private var nativeTopBar: some View {
        HStack(spacing: 10) {
            if isManualFullscreenActive {
                nativeIconButton(systemName: "xmark", accessibilityLabel: "退出全屏") {
                    exitManualFullscreen()
                }
            } else if let topLeadingControlsAccessory {
                topLeadingControlsAccessory
            }

            Text(viewModel.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .shadow(color: .black.opacity(0.55), radius: 2, y: 1)

            Spacer(minLength: 10)

            if isManualFullscreenActive {
                nativeIconButton(
                    systemName: controlsLocked ? "lock.fill" : "lock.open",
                    accessibilityLabel: controlsLocked ? "解锁播放控件" : "锁定播放控件"
                ) {
                    toggleControlsLock()
                }
            }

            if surfaceState.isPictureInPictureSupported {
                nativeIconButton(
                    systemName: surfaceState.isPictureInPictureActive ? "pip.exit" : "pip.enter",
                    accessibilityLabel: surfaceState.isPictureInPictureActive ? "退出画中画" : "进入画中画"
                ) {
                    viewModel.togglePictureInPicture()
                    handlePlayerInteraction()
                }
            }
        }
        .frame(height: 44)
    }

    private func nativeBottomPanel(isCompact: Bool) -> some View {
        VStack(spacing: isCompact ? 5 : 8) {
            PlayerClockProgressSlider(
                clock: viewModel.playbackClock,
                isScrubbing: isScrubbing,
                scrubProgress: $scrubProgress,
                height: isCompact ? 18 : 22,
                tint: PlayerControlPalette.bilibiliPink,
                onEditingChanged: handleScrubbingChanged
            )

            HStack(spacing: isCompact ? 10 : 14) {
                PlayerClockSummaryText(clock: viewModel.playbackClock, isCompact: isCompact)

                Spacer(minLength: 6)

                nativeDanmakuToggle(isCompact: isCompact)

                if let controlsAccessory {
                    controlsAccessory
                }

                if !isCompact {
                    speedMenu
                }

                nativeFullscreenButton(isCompact: isCompact)
            }
            .frame(height: isCompact ? 32 : 36)
        }
    }

    private func nativePlayPauseButton(isCompact: Bool) -> some View {
        nativeIconButton(
            systemName: surfaceState.isPlaying ? "pause.fill" : "play.fill",
            size: isCompact ? 34 : 38,
            iconSize: isCompact ? 15 : 17,
            isProminent: true,
            accessibilityLabel: surfaceState.isPlaying ? "暂停" : "播放"
        ) {
            togglePlaybackFromControls()
        }
        .scaleEffect(playPauseIconScale)
    }

    @ViewBuilder
    private func nativeDanmakuToggle(isCompact: Bool) -> some View {
        if let onToggleDanmaku {
            Button {
                Haptics.light()
                onToggleDanmaku()
                handlePlayerInteraction()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isDanmakuEnabled ? "text.bubble.fill" : "text.bubble")
                        .font(.system(size: isCompact ? 13 : 14, weight: .semibold))
                    if !isCompact {
                        Text(isDanmakuEnabled ? "弹幕" : "弹幕关")
                            .font(.caption2.weight(.semibold))
                    }
                }
                .frame(height: isCompact ? 30 : 32)
                .padding(.horizontal, isCompact ? 8 : 10)
            }
            .foregroundStyle(isDanmakuEnabled ? .white : .white.opacity(0.62))
            .biliPlayerYouTubePillStyle(prominent: isDanmakuEnabled)
            .accessibilityLabel(isDanmakuEnabled ? "关闭弹幕" : "开启弹幕")
        }
    }

    @ViewBuilder
    private func nativeFullscreenButton(isCompact: Bool) -> some View {
        if isManualFullscreenActive {
            nativeIconButton(
                systemName: "arrow.down.right.and.arrow.up.left",
                size: isCompact ? 34 : 38,
                iconSize: isCompact ? 14 : 15,
                accessibilityLabel: "退出全屏"
            ) {
                exitManualFullscreen()
            }
        } else if canRequestManualFullscreen {
            nativeIconButton(
                systemName: "arrow.up.left.and.arrow.down.right",
                size: isCompact ? 34 : 38,
                iconSize: isCompact ? 14 : 15,
                accessibilityLabel: "全屏播放"
            ) {
                PlayerMetricsLog.logger.info(
                    "manualFullscreenButtonTapped presentation=\(String(describing: self.presentation), privacy: .public) controlsVisible=\(self.controlsVisible, privacy: .public)"
                )
                Haptics.light()
                onRequestManualFullscreen?()
                handlePlayerInteraction()
            }
        }
    }

    private func nativeIconButton(
        systemName: String,
        size: CGFloat = 38,
        iconSize: CGFloat = 16,
        isProminent: Bool = false,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonBorderShape(.circle)
        .buttonStyle(.plain)
        .background {
            Circle()
                .fill(.black.opacity(isProminent ? 0.48 : 0.34))
        }
        .overlay {
            Circle()
                .stroke(.white.opacity(isProminent ? 0.13 : 0.08), lineWidth: 0.5)
        }
        .contentShape(Circle())
        .foregroundStyle(.white)
        .accessibilityLabel(accessibilityLabel)
    }

    private func togglePlaybackFromControls() {
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

    private var embeddedPlayerControls: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 8) {
                topToolRow(isCompact: true)
                bottomTimeline(isCompact: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .padding(.bottom, controlsBottomLift)
    }

    private var fullscreenPlayerControls: some View {
        GlassEffectContainer(spacing: 16) {
            VStack(spacing: 0) {
                topToolRow(isCompact: false)
                    .padding(.top, isManualFullscreenActive ? 12 : 18)
                    .padding(.horizontal, 16)

                Spacer(minLength: 0)

                bottomTimeline(isCompact: false)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18 + controlsBottomLift)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .buttonBorderShape(.circle)
            .buttonStyle(.plain)
            .background(Circle().fill(.black.opacity(0.44)))
            .accessibilityLabel("解锁播放控件")

            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.leading, 22)
        .padding(.trailing, 22)
        .padding(.bottom, 18 + controlsBottomLift)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func topToolRow(isCompact: Bool) -> some View {
        HStack(spacing: isCompact ? 7 : 9) {
            if isManualFullscreenActive {
                playerControlButton(systemName: "xmark", isCompact: isCompact, accessibilityLabel: "退出全屏") {
                    exitManualFullscreen()
                }
            }

            Spacer(minLength: 8)

            if isManualFullscreenActive {
                playerControlButton(
                    systemName: controlsLocked ? "lock.fill" : "lock.open",
                    isCompact: isCompact,
                    accessibilityLabel: controlsLocked ? "解锁播放控件" : "锁定播放控件"
                ) {
                    toggleControlsLock()
                }
            }

            if surfaceState.isPictureInPictureSupported {
                playerControlButton(
                    systemName: surfaceState.isPictureInPictureActive ? "pip.exit" : "pip.enter",
                    isCompact: isCompact,
                    accessibilityLabel: surfaceState.isPictureInPictureActive ? "退出画中画" : "进入画中画"
                ) {
                    viewModel.togglePictureInPicture()
                    handlePlayerInteraction()
                }
            }

            if canRequestManualFullscreen {
                playerControlButton(
                    systemName: "arrow.up.left.and.arrow.down.right",
                    isCompact: isCompact,
                    accessibilityLabel: "全屏播放"
                ) {
                    PlayerMetricsLog.logger.info(
                        "manualFullscreenButtonTapped presentation=\(String(describing: self.presentation), privacy: .public) controlsVisible=\(self.controlsVisible, privacy: .public)"
                    )
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
        PlayerLegacyTimeline(
            clock: viewModel.playbackClock,
            isCompact: isCompact,
            isScrubbing: isScrubbing,
            scrubProgress: $scrubProgress,
            onEditingChanged: handleScrubbingChanged
        )
    }

    private var speedMenu: some View {
        Menu {
            ForEach(BiliPlaybackRate.allCases) { rate in
                Button {
                    viewModel.setPlaybackRate(rate)
                    dependencies.libraryStore.setDefaultPlaybackRate(rate.rawValue)
                    handlePlayerInteraction()
                } label: {
                    Label(rate.title, systemImage: surfaceState.playbackRate == rate ? "checkmark" : "speedometer")
                }
            }
        } label: {
            if presentation == .embedded {
                Text(compactPlaybackRateTitle)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .frame(width: 28, height: 26)
            } else {
                Text(surfaceState.playbackRate.title)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .frame(minWidth: 46, minHeight: 34)
                    .padding(.horizontal, 2)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, presentation == .embedded ? 5 : 7)
        .biliPlayerYouTubePillStyle()
    }

    private var compactPlaybackRateTitle: String {
        if surfaceState.playbackRate == .x10 {
            return "1x"
        }
        return surfaceState.playbackRate.title.replacingOccurrences(of: ".0x", with: "x")
    }

    private func playerControlButton(
        systemName: String,
        isEnabled: Bool = true,
        isPrimary: Bool = false,
        isCompact: Bool = false,
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let size: CGFloat = isCompact ? (isPrimary ? 32 : 28) : (isPrimary ? 40 : 34)
        let hitSize: CGFloat = max(size, 44)
        return Button(action: action) {
            ZStack {
                Image(systemName: systemName)
                    .font(.system(size: isCompact ? (isPrimary ? 13.5 : 12) : (isPrimary ? 16 : 13.5), weight: isPrimary ? .bold : .semibold))
                    .frame(width: size, height: size)
            }
            .frame(width: hitSize, height: hitSize)
            .contentShape(Rectangle())
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
        .buttonBorderShape(.circle)
        .biliGlassButtonStyle(prominent: isPrimary)
        .foregroundStyle(.white)
        .accessibilityLabel(accessibilityLabel ?? systemName)
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
            let isNowPlaying = viewModel.togglePlayback()
            controlsVisible = true
            scheduleControlsAutoHideIfNeeded()
            showGestureFeedback(isNowPlaying ? .play : .pause)
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

    private func handlePlayerPanChanged(_ event: PlayerPanGestureEvent) {
        guard usesCustomPlaybackControls else { return }
        guard !controlsLocked else {
            showLockAffordance()
            return
        }

        if gesturePanMode == .none {
            let horizontalTravel = abs(event.translation.width)
            let verticalTravel = abs(event.translation.height)
            guard max(horizontalTravel, verticalTravel) > 8 else { return }
            restoreLongPressPlaybackRateIfNeeded()
            cancelControlsAutoHide()
            controlsVisible = false
            if horizontalTravel > verticalTravel * 1.15, viewModel.canSeek {
                gesturePanMode = .seeking
                gesturePanStartProgress = currentProgress
                lastPreparedScrubProgress = -1
                prepareUserSeekWarmupIfNeeded(gesturePanStartProgress, force: true)
            } else if event.location.x < event.size.width / 2 {
                gesturePanMode = .brightness
                gesturePanStartBrightness = activePlayerScreen?.brightness ?? gesturePanStartBrightness
            } else {
                gesturePanMode = .volume
                gesturePanStartVolume = viewModel.volume
            }
        }

        switch gesturePanMode {
        case .none:
            return
        case .seeking:
            guard let duration = displayDuration, duration > 0 else { return }
            let seekWindow = min(max(duration * 0.28, 36), 180)
            let deltaSeconds = TimeInterval(event.translation.width / max(event.size.width, 1)) * seekWindow
            let targetTime = min(max(gesturePanStartProgress * duration + deltaSeconds, 0), duration)
            scrubProgress = targetTime / duration
            prepareUserSeekWarmupIfNeeded(scrubProgress)
            showGestureFeedback(.scrub(time: targetTime, duration: duration))
        case .brightness:
            let delta = -event.translation.height / max(event.size.height, 1)
            let value = min(max(gesturePanStartBrightness + delta, 0), 1)
            activePlayerScreen?.brightness = value
            showGestureFeedback(.brightness(percent: Int((value * 100).rounded())))
        case .volume:
            let delta = -event.translation.height / max(event.size.height, 1)
            let value = min(max(CGFloat(gesturePanStartVolume) + delta, 0), 1)
            viewModel.setVolume(Float(value))
            showGestureFeedback(.volume(percent: Int((value * 100).rounded())))
        }
    }

    private func handlePlayerPanEnded() {
        defer {
            gesturePanMode = .none
            scheduleControlsAutoHideIfNeeded()
        }
        guard gesturePanMode == .seeking else {
            Haptics.light()
            return
        }
        Haptics.light()
        prepareUserSeekWarmupIfNeeded(scrubProgress, force: true)
        viewModel.seekAfterUserScrub(to: scrubProgress)
        lastPreparedScrubProgress = -1
    }

    private func handlePlayerLongPressStart() {
        guard usesCustomPlaybackControls else { return }
        guard !controlsLocked else {
            showLockAffordance()
            return
        }
        guard !surfaceState.isBuffering, longPressRateRestoreValue == nil else { return }
        let boostProfile = PlayerLongPressSpeedBoost.profile(for: viewModel.engineDiagnostics)
        let startupRate = boostProfile.startupRate
        longPressRateRestoreValue = viewModel.playbackRate
        longPressSpeedBoostSignpostState = PlayerMetricsLog.beginSignpostedInterval(
            "PlayerSpeedBoost",
            message: "start rate=\(boostProfile.startupFeedbackTitle) target=\(boostProfile.feedbackTitle) guarded=\(boostProfile.isGuarded)"
        )
        Haptics.medium()
        viewModel.setPlaybackRate(startupRate)
        viewModel.recordSpeedBoostMetric(
            "start rate=\(boostProfile.startupFeedbackTitle) target=\(boostProfile.feedbackTitle) guarded=\(boostProfile.isGuarded)"
        )
        controlsVisible = false
        cancelControlsAutoHide()
        showGestureFeedback(.speed(boostProfile.startupFeedbackTitle))
        scheduleLongPressSpeedBoostTimeout(boostProfile)
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
            lastPreparedScrubProgress = -1
            prepareUserSeekWarmupIfNeeded(scrubProgress, force: true)
            cancelControlsAutoHide()
            controlsVisible = true
        } else {
            isScrubbing = false
            Haptics.light()
            prepareUserSeekWarmupIfNeeded(scrubProgress, force: true)
            viewModel.seekAfterUserScrub(to: scrubProgress)
            lastPreparedScrubProgress = -1
            scheduleControlsAutoHideIfNeeded()
        }
    }

    private func prepareUserSeekWarmupIfNeeded(_ progress: Double, force: Bool = false) {
        let clampedProgress = min(max(progress, 0), 1)
        guard force || abs(clampedProgress - lastPreparedScrubProgress) >= 0.015 else { return }
        lastPreparedScrubProgress = clampedProgress
        onPrepareForUserSeek?(clampedProgress)
    }

    private func scheduleControlsAutoHideIfNeeded() {
        cancelControlsAutoHide()
        guard usesCustomPlaybackControls else { return }
        autoHideControlsTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, !isScrubbing else { return }
            controlsVisible = false
        }
    }

    private func cancelControlsAutoHide() {
        autoHideControlsTask?.cancel()
        autoHideControlsTask = nil
    }

    private func scheduleLongPressSpeedBoostTimeout(_ boostProfile: PlayerLongPressSpeedBoost.Profile) {
        longPressSpeedBoostTask?.cancel()
        longPressSpeedBoostTask = Task { @MainActor in
            let startedAt = CACurrentMediaTime()
            let sustainAfter = TimeInterval(boostProfile.sustainAfterNanoseconds) / 1_000_000_000
            let peakRampAfter = TimeInterval(boostProfile.peakRampAfterNanoseconds) / 1_000_000_000
            let maximumDuration = TimeInterval(boostProfile.maximumDurationNanoseconds) / 1_000_000_000
            var didApplyPeakRate = !boostProfile.usesPeakRampUp
            var didApplySustainedRate = false
            var lastSampleWallTime = startedAt
            var lastPlaybackTime = currentLongPressPlaybackTime
            var slowProgressSamples = 0

            while !Task.isCancelled, longPressRateRestoreValue != nil {
                let elapsedBeforeSleep = CACurrentMediaTime() - startedAt
                if boostProfile.usesPeakRampUp,
                   !didApplyPeakRate,
                   elapsedBeforeSleep >= peakRampAfter {
                    viewModel.setPlaybackRate(boostProfile.rate)
                    viewModel.recordSpeedBoostMetric(
                        "peak rate=\(boostProfile.feedbackTitle) guarded=\(boostProfile.isGuarded)"
                    )
                    showGestureFeedback(.speed(boostProfile.feedbackTitle))
                    didApplyPeakRate = true
                    lastSampleWallTime = CACurrentMediaTime()
                    lastPlaybackTime = currentLongPressPlaybackTime
                }

                if boostProfile.usesSustainedStepDown,
                   didApplyPeakRate,
                   !didApplySustainedRate,
                   elapsedBeforeSleep >= sustainAfter {
                    viewModel.setPlaybackRate(boostProfile.sustainedRate)
                    viewModel.recordSpeedBoostMetric(
                        "sustain rate=\(boostProfile.sustainedFeedbackTitle) guarded=\(boostProfile.isGuarded)"
                    )
                    showGestureFeedback(.speed(boostProfile.sustainedFeedbackTitle))
                    didApplySustainedRate = true
                    lastSampleWallTime = CACurrentMediaTime()
                    lastPlaybackTime = currentLongPressPlaybackTime
                }

                let sleepNanoseconds: UInt64 = (!didApplyPeakRate && boostProfile.usesPeakRampUp)
                    ? 220_000_000
                    : 700_000_000
                try? await Task.sleep(nanoseconds: sleepNanoseconds)
                guard !Task.isCancelled, longPressRateRestoreValue != nil else { return }

                let now = CACurrentMediaTime()
                if now - startedAt >= maximumDuration {
                    viewModel.recordSpeedBoostMetric("timeout interrupted=false restore=\(longPressRateRestoreValue?.title ?? "-")")
                    restoreLongPressPlaybackRateIfNeeded()
                    if !controlsLocked {
                        scheduleControlsAutoHideIfNeeded()
                    }
                    return
                }

                guard now - startedAt >= 2.4 else { continue }
                let sampleInterval = now - lastSampleWallTime
                guard sampleInterval >= 1.15 else { continue }
                let playbackTime = currentLongPressPlaybackTime
                let playbackDelta = max(playbackTime - lastPlaybackTime, 0)
                let slowProgressThreshold = max(0.30, sampleInterval * 0.14)
                if playbackDelta < slowProgressThreshold {
                    slowProgressSamples += 1
                } else {
                    slowProgressSamples = 0
                }
                lastSampleWallTime = now
                lastPlaybackTime = playbackTime

                guard slowProgressSamples >= 2 else { continue }
                viewModel.recordSpeedBoostMetric("pressureRestore interrupted=true restore=\(longPressRateRestoreValue?.title ?? "-") reason=slowProgress")
                restoreLongPressPlaybackRateForPressureIfNeeded()
                if !controlsLocked {
                    scheduleControlsAutoHideIfNeeded()
                }
                return
            }
        }
    }

    private var currentLongPressPlaybackTime: TimeInterval {
        let snapshotTime = viewModel.playbackSnapshot().currentTime ?? 0
        let time = max(snapshotTime, viewModel.currentTime, viewModel.playbackClock.currentTime)
        guard time.isFinite else { return 0 }
        return max(time, 0)
    }

    private func restoreLongPressPlaybackRateIfNeeded() {
        restoreLongPressPlaybackRate(to: longPressRateRestoreValue)
    }

    private func restoreLongPressPlaybackRateForPressureIfNeeded() {
        guard let restoreRate = longPressRateRestoreValue else { return }
        let boostProfile = PlayerLongPressSpeedBoost.profile(for: viewModel.engineDiagnostics)
        let fallbackRate: BiliPlaybackRate
        if restoreRate.rawValue >= boostProfile.rate.rawValue {
            fallbackRate = .x10
        } else {
            fallbackRate = restoreRate
        }
        viewModel.recordSpeedBoostMetric("pressureRestore interrupted=true restore=\(fallbackRate.title)")
        restoreLongPressPlaybackRate(to: fallbackRate)
    }

    private func restoreLongPressPlaybackRate(to restoreRate: BiliPlaybackRate?) {
        guard let restoreRate else { return }
        longPressSpeedBoostTask?.cancel()
        longPressSpeedBoostTask = nil
        if let signpostState = longPressSpeedBoostSignpostState {
            PlayerMetricsLog.endSignpostedInterval(
                "PlayerSpeedBoost",
                signpostState,
                message: "restore=\(restoreRate.title)"
            )
            longPressSpeedBoostSignpostState = nil
        }
        longPressRateRestoreValue = nil
        viewModel.setPlaybackRate(restoreRate)
        viewModel.stabilizePlaybackAfterSpeedBoost(restoredRate: restoreRate, reason: "embeddedRestore")
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

    @ViewBuilder
    private func playerGestureFeedbackContainer(_ feedback: PlayerGestureFeedback) -> some View {
        if case .speed(let title) = feedback {
            playerSpeedFeedbackView(title)
        } else {
            playerGestureFeedbackView(feedback)
        }
    }

    private func playerSpeedFeedbackView(_ title: String) -> some View {
        let topPadding: CGFloat = isManualFullscreenActive ? 12 : (presentation == .embedded ? 6 : 10)

        return HStack(spacing: 5) {
            Image(systemName: "forward.fill")
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background {
            Capsule()
                .fill(.black.opacity(0.34))
        }
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.07), lineWidth: 0.5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, topPadding)
        .allowsHitTesting(false)
    }

    private func playerGestureFeedbackView(_ feedback: PlayerGestureFeedback) -> some View {
        let horizontalPadding: CGFloat = presentation == .embedded ? 26 : 62

        return VStack(spacing: 4) {
            Image(systemName: feedback.systemName)
                .font(.system(size: feedback.title == nil ? 30 : 22, weight: .bold))

            if let title = feedback.title {
                Text(title)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
            }
        }
            .foregroundStyle(.white)
            .frame(width: feedback.width, height: 68)
            .background {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .fill(.black.opacity(feedback.title == nil ? 0.48 : 0.42))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 0.5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: feedback.alignment)
            .padding(.horizontal, horizontalPadding)
            .allowsHitTesting(false)
    }

    private var activePlayerScreen: UIScreen? {
        UIApplication.shared.biliPlayerForegroundKeyWindow?.windowScene?.screen
    }
}

private extension URL {
    var isLikelyHLSManifest: Bool {
        pathExtension.localizedCaseInsensitiveCompare("m3u8") == .orderedSame
            || absoluteString.range(of: ".m3u8", options: .caseInsensitive) != nil
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
    case scrub(time: TimeInterval, duration: TimeInterval)
    case brightness(percent: Int)
    case volume(percent: Int)
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
        case .scrub:
            return "arrow.left.and.right"
        case .brightness:
            return "sun.max.fill"
        case .volume(let percent):
            return percent == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill"
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
        case .scrub(let time, let duration):
            return "\(BiliFormatters.duration(Int(time.rounded()))) / \(BiliFormatters.duration(Int(duration.rounded())))"
        case .brightness(let percent), .volume(let percent):
            return "\(percent)%"
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
        case .play, .pause, .scrub, .brightness, .volume, .speed:
            return .center
        }
    }

    var width: CGFloat {
        switch self {
        case .scrub:
            return 142
        default:
            return title == nil ? 86 : 96
        }
    }

    var isSpeedFeedback: Bool {
        if case .speed = self {
            return true
        }
        return false
    }
}

private struct PlayerControlScrim: View {
    enum Edge {
        case top
        case bottom
    }

    let edge: Edge
    let height: CGFloat
    let opacity: Double

    var body: some View {
        LinearGradient(
            colors: gradientColors,
            startPoint: edge == .top ? .top : .bottom,
            endPoint: edge == .top ? .bottom : .top
        )
        .frame(height: height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge == .top ? .top : .bottom)
    }

    private var gradientColors: [Color] {
        [
            .black.opacity(opacity),
            .black.opacity(opacity * 0.58),
            .black.opacity(0)
        ]
    }
}

private enum PlayerControlPalette {
    static let bilibiliPink = Color(red: 1.0, green: 0.36, blue: 0.58)
}

private struct PlayerChromeState: Equatable {
    let usesCustomControls: Bool
    let controlsVisible: Bool
    let controlsLocked: Bool
    let lockAffordanceVisible: Bool
    let isManualFullscreenActive: Bool

    var showsGestureOverlay: Bool {
        guard usesCustomControls else { return false }
        return true
    }

    var showsPlaybackChrome: Bool {
        usesCustomControls && controlsVisible
    }

    var showsLockAffordance: Bool {
        usesCustomControls
            && isManualFullscreenActive
            && controlsLocked
            && lockAffordanceVisible
    }
}

private enum PlayerGesturePanMode {
    case none
    case seeking
    case brightness
    case volume
}

private struct PlayerPanGestureEvent {
    let location: CGPoint
    let translation: CGSize
    let size: CGSize
}

private extension UIApplication {
    var biliPlayerForegroundKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}

private struct PlayerClockSummaryText: View {
    let clock: PlayerPlaybackClock
    let isCompact: Bool
    @StateObject private var display = PlayerClockDisplayModel()

    var body: some View {
        Text(display.summaryText)
            .font(.caption2.monospacedDigit().weight(.medium))
            .foregroundStyle(.white.opacity(0.92))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .frame(width: isCompact ? 96 : 118, alignment: .leading)
            .onAppear {
                display.bind(clock: clock)
            }
            .onChange(of: ObjectIdentifier(clock)) { _, _ in
                display.bind(clock: clock)
            }
    }
}

private struct PlayerClockProgressSlider: View {
    let clock: PlayerPlaybackClock
    let isScrubbing: Bool
    @Binding var scrubProgress: Double
    let height: CGFloat
    let tint: Color
    let onEditingChanged: (Bool) -> Void

    private var displayProgress: Double {
        isScrubbing ? scrubProgress : clock.progress
    }

    var body: some View {
        LiquidPlayerProgressSlider(
            value: $scrubProgress,
            in: 0...1,
            tint: tint,
            displayProgress: displayProgress,
            clock: clock,
            isScrubbing: isScrubbing,
            onEditingChanged: onEditingChanged
        )
        .frame(height: height)
    }
}

private struct PlayerLegacyTimeline: View {
    let clock: PlayerPlaybackClock
    let isCompact: Bool
    let isScrubbing: Bool
    @Binding var scrubProgress: Double
    let onEditingChanged: (Bool) -> Void
    @StateObject private var display = PlayerClockDisplayModel()

    var body: some View {
        HStack(spacing: isCompact ? 7 : 10) {
            Text(display.currentText)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: isCompact ? 38 : 46, alignment: .leading)

            PlayerClockProgressSlider(
                clock: clock,
                isScrubbing: isScrubbing,
                scrubProgress: $scrubProgress,
                height: isCompact ? 18 : 24,
                tint: PlayerControlPalette.bilibiliPink,
                onEditingChanged: onEditingChanged
            )
            .layoutPriority(1)

            if let durationText = display.durationText {
                Text(durationText)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(width: isCompact ? 38 : 46, alignment: .trailing)
            }
        }
        .padding(.horizontal, isCompact ? 10 : 12)
        .padding(.vertical, isCompact ? 6 : 8)
        .background {
            Capsule()
                .fill(.black.opacity(0.34))
        }
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.08), lineWidth: 0.5)
        }
        .onAppear {
            display.bind(clock: clock)
        }
        .onChange(of: ObjectIdentifier(clock)) { _, _ in
            display.bind(clock: clock)
        }
    }
}

private struct LiquidPlayerProgressSlider: UIViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let tint: Color
    let displayProgress: Double
    let clock: PlayerPlaybackClock?
    let isScrubbing: Bool
    let onEditingChanged: (Bool) -> Void

    init(
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        tint: Color,
        displayProgress: Double,
        clock: PlayerPlaybackClock? = nil,
        isScrubbing: Bool = false,
        onEditingChanged: @escaping (Bool) -> Void
    ) {
        _value = value
        self.range = range
        self.tint = tint
        self.displayProgress = displayProgress
        self.clock = clock
        self.isScrubbing = isScrubbing
        self.onEditingChanged = onEditingChanged
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            value: $value,
            onEditingChanged: onEditingChanged,
            displayProgress: displayProgress,
            isScrubbing: isScrubbing
        )
    }

    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider()
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.value = Float(value)
        slider.minimumTrackTintColor = UIColor(tint)
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.28)
        slider.setMinimumTrackImage(Self.trackImage(height: 3, color: UIColor(tint)), for: .normal)
        slider.setMaximumTrackImage(Self.trackImage(height: 3, color: UIColor.white.withAlphaComponent(0.28)), for: .normal)
        slider.setThumbImage(Self.thumbImage(visualDiameter: 7, canvasDiameter: 28, color: .white), for: .normal)
        slider.setThumbImage(Self.thumbImage(visualDiameter: 11, canvasDiameter: 32, color: .white), for: .highlighted)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.touchDown(_:)), for: .touchDown)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.touchUp(_:)),
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )
        context.coordinator.attach(slider: slider, clock: clock, displayProgress: displayProgress)
        context.coordinator.refreshSliderValue(animated: false)
        return slider
    }

    func updateUIView(_ slider: UISlider, context: Context) {
        context.coordinator.value = $value
        context.coordinator.onEditingChanged = onEditingChanged
        context.coordinator.isScrubbing = isScrubbing
        let lower = Float(range.lowerBound)
        let upper = Float(range.upperBound)
        if slider.minimumValue != lower {
            slider.minimumValue = lower
        }
        if slider.maximumValue != upper {
            slider.maximumValue = upper
        }
        context.coordinator.displayProgress = displayProgress
        context.coordinator.attach(slider: slider, clock: clock, displayProgress: displayProgress)
        context.coordinator.refreshSliderValue(animated: false)
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
        var displayProgress: Double
        var isScrubbing = false
        var isEditing = false
        private weak var slider: UISlider?
        private weak var clock: PlayerPlaybackClock?
        private var clockCancellable: AnyCancellable?
        private var latestClockProgress: Double?

        init(
            value: Binding<Double>,
            onEditingChanged: @escaping (Bool) -> Void,
            displayProgress: Double,
            isScrubbing: Bool
        ) {
            self.value = value
            self.onEditingChanged = onEditingChanged
            self.displayProgress = displayProgress
            self.isScrubbing = isScrubbing
        }

        func attach(slider: UISlider, clock: PlayerPlaybackClock?, displayProgress: Double) {
            self.slider = slider
            self.displayProgress = displayProgress
            guard self.clock !== clock else { return }
            clockCancellable?.cancel()
            clockCancellable = nil
            self.clock = clock
            guard let clock else {
                latestClockProgress = displayProgress
                return
            }
            latestClockProgress = displayProgress

            Task { @MainActor [weak self] in
                guard let self, self.clock === clock else { return }
                self.clockCancellable = clock.$currentTime
                    .combineLatest(clock.$duration)
                    .sink { [weak self] currentTime, duration in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            self.latestClockProgress = Self.progress(
                                currentTime: currentTime,
                                duration: duration
                            )
                            self.refreshSliderValue(animated: false)
                        }
                    }
            }
        }

        func refreshSliderValue(animated: Bool) {
            guard let slider else { return }
            let nextValue = isEditing || isScrubbing
                ? value.wrappedValue
                : latestClockProgress ?? displayProgress
            let clampedValue = min(max(Float(nextValue), slider.minimumValue), slider.maximumValue)
            guard abs(slider.value - clampedValue) > 0.001 else { return }
            slider.setValue(clampedValue, animated: animated)
        }

        @objc func touchDown(_ slider: UISlider) {
            isEditing = true
            onEditingChanged(true)
            value.wrappedValue = Double(slider.value)
            refreshSliderValue(animated: false)
        }

        @objc func valueChanged(_ slider: UISlider) {
            value.wrappedValue = Double(slider.value)
            refreshSliderValue(animated: false)
        }

        @objc func touchUp(_ slider: UISlider) {
            value.wrappedValue = Double(slider.value)
            isEditing = false
            onEditingChanged(false)
            refreshSliderValue(animated: false)
        }

        private static func progress(currentTime: TimeInterval, duration: TimeInterval?) -> Double {
            guard let duration, duration > 0 else { return 0 }
            return min(max(currentTime / duration, 0), 1)
        }
    }
}

private struct PlayerGestureOverlay: UIViewRepresentable {
    let isEnabled: Bool
    let respectsSystemEdgeGestures: Bool
    let onSingleTap: () -> Void
    let onDoubleTap: (PlayerGestureRegion) -> Void
    let onPanChanged: (PlayerPanGestureEvent) -> Void
    let onPanEnded: () -> Void
    let onLongPressStart: () -> Void
    let onLongPressEnd: () -> Void

    func makeUIView(context: Context) -> GestureOverlayView {
        let view = GestureOverlayView()
        view.isGestureOverlayEnabled = isEnabled
        view.respectsSystemEdgeGestures = respectsSystemEdgeGestures
        view.onSingleTap = onSingleTap
        view.onDoubleTap = onDoubleTap
        view.onPanChanged = onPanChanged
        view.onPanEnded = onPanEnded
        view.onLongPressStart = onLongPressStart
        view.onLongPressEnd = onLongPressEnd
        return view
    }

    func updateUIView(_ uiView: GestureOverlayView, context: Context) {
        uiView.isGestureOverlayEnabled = isEnabled
        uiView.respectsSystemEdgeGestures = respectsSystemEdgeGestures
        uiView.onSingleTap = onSingleTap
        uiView.onDoubleTap = onDoubleTap
        uiView.onPanChanged = onPanChanged
        uiView.onPanEnded = onPanEnded
        uiView.onLongPressStart = onLongPressStart
        uiView.onLongPressEnd = onLongPressEnd
        uiView.refreshGestureDependenciesIfNeeded()
    }

    final class GestureOverlayView: UIView, UIGestureRecognizerDelegate {
        private enum Constants {
            static let systemBackEdgeWidth: CGFloat = 28
            static let minimumPanVelocity: CGFloat = 70
            static let horizontalDominance: CGFloat = 1.15
            static let verticalDominance: CGFloat = 1.08
        }

        var isGestureOverlayEnabled = true {
            didSet {
                guard isGestureOverlayEnabled != oldValue else { return }
                isUserInteractionEnabled = isGestureOverlayEnabled
                singleTapGesture.isEnabled = isGestureOverlayEnabled
                doubleTapGesture.isEnabled = isGestureOverlayEnabled
                longPressGesture.isEnabled = isGestureOverlayEnabled
                panGesture.isEnabled = isGestureOverlayEnabled
            }
        }
        var respectsSystemEdgeGestures = true
        var onSingleTap: (() -> Void)?
        var onDoubleTap: ((PlayerGestureRegion) -> Void)?
        var onPanChanged: ((PlayerPanGestureEvent) -> Void)?
        var onPanEnded: (() -> Void)?
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
        private lazy var panGesture: UIPanGestureRecognizer = {
            let gesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            gesture.minimumNumberOfTouches = 1
            gesture.maximumNumberOfTouches = 1
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
            addGestureRecognizer(panGesture)
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

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began, .changed:
                let translation = recognizer.translation(in: self)
                let location = recognizer.location(in: self)
                onPanChanged?(
                    PlayerPanGestureEvent(
                        location: location,
                        translation: CGSize(width: translation.x, height: translation.y),
                        size: bounds.size
                    )
                )
            case .ended, .cancelled, .failed:
                onPanEnded?()
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

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard isGestureOverlayEnabled else { return false }
            guard gestureRecognizer === panGesture else { return true }

            let velocity = panGesture.velocity(in: self)
            let horizontalSpeed = abs(velocity.x)
            let verticalSpeed = abs(velocity.y)
            guard max(horizontalSpeed, verticalSpeed) >= Constants.minimumPanVelocity else {
                return false
            }

            let startLocation = panGesture.location(in: self)
            if respectsSystemEdgeGestures,
               startLocation.x <= Constants.systemBackEdgeWidth,
               velocity.x > horizontalSpeed * 0.62,
               horizontalSpeed > verticalSpeed {
                return false
            }

            if horizontalSpeed > verticalSpeed * Constants.horizontalDominance {
                return true
            }
            if verticalSpeed > horizontalSpeed * Constants.verticalDominance {
                return true
            }
            return false
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

private enum PlayerControlGlassTint {
    static let timeline = Color.black.opacity(0.24)
}
