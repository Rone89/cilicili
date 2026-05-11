import Combine
import SwiftUI
import UIKit

enum BiliPlayerPresentation {
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

enum BiliDanmakuOpacity: Double, CaseIterable, Identifiable {
    case light = 0.55
    case normal = 0.82
    case strong = 1.0

    var id: Double { rawValue }

    var title: String {
        switch self {
        case .light:
            return "较淡"
        case .normal:
            return "正常"
        case .strong:
            return "高亮"
        }
    }
}

enum BiliDanmakuFontScale: Double, CaseIterable, Identifiable {
    case small = 0.86
    case normal = 1.0
    case large = 1.16

    var id: Double { rawValue }

    var title: String {
        switch self {
        case .small:
            return "小"
        case .normal:
            return "中"
        case .large:
            return "大"
        }
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
    @State private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private let usesOwnedViewModel: Bool
    private let historyVideo: VideoItem?
    private let historyCID: Int?
    private let historyDuration: TimeInterval?
    private let presentation: BiliPlayerPresentation
    private let showsNavigationChrome: Bool
    private let showsPlaybackControls: Bool
    private let pausesOnDisappear: Bool
    private let controlsAccessory: AnyView?
    private let controlsBottomLift: CGFloat
    private let durationHint: TimeInterval?
    private let embeddedAspectRatio: CGFloat
    private let manualFullscreenOrientation: UIDeviceOrientation?
    private let onExitManualFullscreen: (() -> Void)?
    private var isManualFullscreenActive: Bool {
        manualFullscreenOrientation?.isLandscape == true
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
        pausesOnDisappear: Bool = true,
        controlsAccessory: AnyView? = nil,
        controlsBottomLift: CGFloat = 0,
        embeddedAspectRatio: CGFloat = 16 / 9,
        manualFullscreenOrientation: UIDeviceOrientation? = nil,
        onExitManualFullscreen: (() -> Void)? = nil
    ) {
        self.historyVideo = historyVideo
        self.historyCID = historyCID
        self.historyDuration = historyVideo?.duration.map(TimeInterval.init)
        self.presentation = presentation
        self.showsNavigationChrome = showsNavigationChrome
        self.showsPlaybackControls = showsPlaybackControls
        self.pausesOnDisappear = pausesOnDisappear
        self.controlsAccessory = controlsAccessory
        self.controlsBottomLift = controlsBottomLift
        self.durationHint = duration
        self.embeddedAspectRatio = embeddedAspectRatio
        self.manualFullscreenOrientation = manualFullscreenOrientation
        self.onExitManualFullscreen = onExitManualFullscreen
        self.usesOwnedViewModel = false
        _observedViewModel = ObservedObject(wrappedValue: viewModel)
        _ownedViewModel = StateObject(wrappedValue: viewModel)
    }

    init(
        videoURL: URL,
        title: String,
        danmakus: [DanmakuItem],
        referer: String = "https://www.bilibili.com",
        duration: TimeInterval? = nil,
        presentation: BiliPlayerPresentation = .fullScreen,
        showsNavigationChrome: Bool = true,
        showsPlaybackControls: Bool = true,
        pausesOnDisappear: Bool = true,
        controlsAccessory: AnyView? = nil,
        controlsBottomLift: CGFloat = 0,
        embeddedAspectRatio: CGFloat = 16 / 9,
        manualFullscreenOrientation: UIDeviceOrientation? = nil,
        onExitManualFullscreen: (() -> Void)? = nil
    ) {
        self.historyVideo = nil
        self.historyCID = nil
        self.historyDuration = nil
        self.presentation = presentation
        self.showsNavigationChrome = showsNavigationChrome
        self.showsPlaybackControls = showsPlaybackControls
        self.pausesOnDisappear = pausesOnDisappear
        self.controlsAccessory = controlsAccessory
        self.controlsBottomLift = controlsBottomLift
        self.durationHint = duration
        self.embeddedAspectRatio = embeddedAspectRatio
        self.manualFullscreenOrientation = manualFullscreenOrientation
        self.onExitManualFullscreen = onExitManualFullscreen
        self.usesOwnedViewModel = true
        let playerViewModel = PlayerStateViewModel(
            videoURL: videoURL,
            audioURL: nil,
            videoStream: nil,
            audioStream: nil,
            title: title,
            danmakus: danmakus,
            referer: referer,
            durationHint: duration
        )
        _observedViewModel = ObservedObject(wrappedValue: playerViewModel)
        _ownedViewModel = StateObject(wrappedValue: playerViewModel)
    }

    init(
        playVariant: PlayVariant,
        title: String,
        danmakus: [DanmakuItem],
        referer: String = "https://www.bilibili.com",
        duration: TimeInterval? = nil,
        resumeTime: TimeInterval? = nil,
        historyVideo: VideoItem? = nil,
        historyCID: Int? = nil,
        presentation: BiliPlayerPresentation = .fullScreen,
        showsNavigationChrome: Bool = true,
        showsPlaybackControls: Bool = true,
        pausesOnDisappear: Bool = true,
        controlsAccessory: AnyView? = nil,
        controlsBottomLift: CGFloat = 0,
        embeddedAspectRatio: CGFloat = 16 / 9,
        manualFullscreenOrientation: UIDeviceOrientation? = nil,
        onExitManualFullscreen: (() -> Void)? = nil
    ) {
        self.historyVideo = historyVideo
        self.historyCID = historyCID
        self.historyDuration = historyVideo?.duration.map(TimeInterval.init)
        self.presentation = presentation
        self.showsNavigationChrome = showsNavigationChrome
        self.showsPlaybackControls = showsPlaybackControls
        self.pausesOnDisappear = pausesOnDisappear
        self.controlsAccessory = controlsAccessory
        self.controlsBottomLift = controlsBottomLift
        self.durationHint = duration
        self.embeddedAspectRatio = embeddedAspectRatio
        self.manualFullscreenOrientation = manualFullscreenOrientation
        self.onExitManualFullscreen = onExitManualFullscreen
        self.usesOwnedViewModel = true
        let playerViewModel = PlayerStateViewModel(
            videoURL: playVariant.videoURL,
            audioURL: playVariant.audioURL,
            videoStream: playVariant.videoStream,
            audioStream: playVariant.audioStream,
            title: title,
            danmakus: danmakus,
            referer: referer,
            durationHint: duration,
            resumeTime: resumeTime ?? 0
        )
        _observedViewModel = ObservedObject(wrappedValue: playerViewModel)
        _ownedViewModel = StateObject(wrappedValue: playerViewModel)
    }

    var body: some View {
        Group {
            if presentation == .embedded {
                playerSurface
                    .aspectRatio(max(embeddedAspectRatio, 0.3), contentMode: .fit)
            } else if showsNavigationChrome {
                playerSurface
                    .ignoresSafeArea()
                    .navigationTitle(viewModel.title)
                    .navigationBarTitleDisplayMode(.inline)
            } else {
                playerSurface
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            applyPlaybackDefaults()
            reportPlaybackProgress(0)
            viewModel.play()
            controlsVisible = showsPlaybackControls
            scheduleControlsAutoHideIfNeeded()
        }
        .onReceive(viewModel.$currentTime.throttle(for: .seconds(5), scheduler: RunLoop.main, latest: true)) { time in
            savePlaybackProgress(time)
        }
        .onChange(of: viewModel.isPlaying) { _, isPlaying in
            guard showsPlaybackControls else {
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
                savePlaybackProgressInBackground()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            viewModel.recoverPlaybackAfterAppResume()
            scheduleControlsAutoHideIfNeeded()
        }
        .onDisappear {
            savePlaybackProgress(viewModel.currentTime)
            cancelControlsAutoHide()
            endBackgroundTaskIfNeeded()
            guard pausesOnDisappear else { return }
            guard !isManualFullscreenActive, !ManualVideoFullscreenSession.isActive else { return }
            viewModel.suspendForNavigation()
        }
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
        viewModel.setDanmakuEnabled(libraryStore.defaultDanmakuEnabled)
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
            VideoSurfaceView(
                viewModel: viewModel,
                manualFullscreenOrientation: manualFullscreenOrientation,
                onExitManualFullscreen: onExitManualFullscreen
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .background(.black)
                .zIndex(0)
                .overlay(alignment: .topTrailing) {
                    if viewModel.danmakuEnabled {
                        DanmakuOverlayView(
                            danmakus: viewModel.visibleDanmakus,
                            opacity: viewModel.danmakuOpacity,
                            fontScale: viewModel.danmakuFontScale
                        )
                            .allowsHitTesting(false)
                            .padding(.top, presentation == .embedded ? 14 : 24)
                    }
                }
                .overlay {
                    NavigationContentBackGestureOverlay {
                        handlePlayerTap()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .zIndex(1)

            if viewModel.isPreparing {
                ProgressView()
                    .padding()
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

            if showsPlaybackControls, controlsVisible {
                playerControls
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(4)
            }
        }
        .background(.black)
        .animation(.easeInOut(duration: 0.18), value: controlsVisible)
    }

    private var playerControls: some View {
        VStack(spacing: 10) {
            if let controlsAccessory {
                controlsAccessory
                    .padding(.horizontal, presentation == .embedded ? 12 : 16)
                    .padding(.bottom, 2)
            }

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    playerControlButton(systemName: "gobackward.10", isEnabled: viewModel.canSeek) {
                        Haptics.light()
                        viewModel.seek(by: -10)
                        handlePlayerInteraction()
                    }

                    playerControlButton(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill") {
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

                    if viewModel.isPictureInPictureSupported {
                        playerControlButton(systemName: viewModel.isPictureInPictureActive ? "pip.exit" : "pip.enter") {
                            viewModel.togglePictureInPicture()
                            handlePlayerInteraction()
                        }
                    }

                    speedMenu
                    danmakuMenu
                }

                HStack(spacing: 10) {
                    if let duration = displayDuration, duration > 0 {
                        Text(BiliFormatters.duration(Int(viewModel.currentTime.rounded())))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.92))
                            .frame(width: 44, alignment: .leading)

                        Slider(
                            value: progressBinding,
                            in: 0...1,
                            onEditingChanged: handleScrubbingChanged
                        )
                        .tint(.pink)

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
            .padding(.horizontal, presentation == .embedded ? 12 : 16)
            .padding(.top, 12)
            .padding(.bottom, presentation == .embedded ? 12 : 18 + controlsBottomLift)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.78)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .foregroundStyle(.white)
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
            Text(viewModel.playbackRate.title)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .frame(width: 48, height: 38)
                .background(.white.opacity(0.12))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var danmakuMenu: some View {
        Menu {
            Button {
                let nextValue = !viewModel.danmakuEnabled
                viewModel.setDanmakuEnabled(nextValue)
                libraryStore.setDefaultDanmakuEnabled(nextValue)
                handlePlayerInteraction()
            } label: {
                Label(viewModel.danmakuEnabled ? "关闭弹幕" : "开启弹幕", systemImage: viewModel.danmakuEnabled ? "text.bubble.fill" : "text.bubble")
            }

            Section("显示强度") {
                ForEach(BiliDanmakuOpacity.allCases) { opacity in
                    Button {
                        viewModel.setDanmakuOpacity(opacity)
                        handlePlayerInteraction()
                    } label: {
                        Label(opacity.title, systemImage: viewModel.danmakuOpacityPreset == opacity ? "checkmark" : "circle")
                    }
                }
            }

            Section("字号") {
                ForEach(BiliDanmakuFontScale.allCases) { scale in
                    Button {
                        viewModel.setDanmakuFontScale(scale)
                        handlePlayerInteraction()
                    } label: {
                        Label(scale.title, systemImage: viewModel.danmakuFontScalePreset == scale ? "checkmark" : "textformat.size")
                    }
                }
            }
        } label: {
            Image(systemName: viewModel.danmakuEnabled ? "text.bubble.fill" : "text.bubble")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.12))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func playerControlButton(systemName: String, isEnabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.12))
                .clipShape(Circle())
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
        .buttonStyle(.plain)
    }

    private func handlePlayerTap() {
        guard showsPlaybackControls else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            controlsVisible.toggle()
        }
        if controlsVisible {
            scheduleControlsAutoHideIfNeeded()
        } else {
            cancelControlsAutoHide()
        }
    }

    private func handlePlayerInteraction() {
        guard showsPlaybackControls else { return }
        controlsVisible = true
        scheduleControlsAutoHideIfNeeded()
    }

    private func handleScrubbingChanged(_ editing: Bool) {
        guard showsPlaybackControls else { return }
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
        guard showsPlaybackControls else { return }
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
}

private struct NavigationContentBackGestureOverlay: UIViewRepresentable {
    let onTap: () -> Void

    func makeUIView(context: Context) -> GestureOverlayView {
        let view = GestureOverlayView()
        view.onTap = onTap
        return view
    }

    func updateUIView(_ uiView: GestureOverlayView, context: Context) {
        uiView.onTap = onTap
        uiView.refreshGestureDependenciesIfNeeded()
    }

    final class GestureOverlayView: UIView, UIGestureRecognizerDelegate {
        var onTap: (() -> Void)?

        private weak var attachedNavigationController: UINavigationController?
        private weak var attachedPopGesture: UIGestureRecognizer?
        private weak var attachedContentPopGesture: UIGestureRecognizer?
        private lazy var tapGesture: UITapGestureRecognizer = {
            let gesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            gesture.cancelsTouchesInView = false
            gesture.delegate = self
            return gesture
        }()

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = true
            addGestureRecognizer(tapGesture)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            refreshGestureDependenciesIfNeeded()
        }

        @objc private func handleTap() {
            onTap?()
        }

        func refreshGestureDependenciesIfNeeded() {
            guard let navigationController = enclosingNavigationController() else { return }
            attachedNavigationController = navigationController

            if let popGesture = navigationController.interactivePopGestureRecognizer,
               attachedPopGesture !== popGesture {
                tapGesture.require(toFail: popGesture)
                attachedPopGesture = popGesture
            }
            if let contentPopGesture = navigationController.interactiveContentPopGestureRecognizer,
               attachedContentPopGesture !== contentPopGesture {
                tapGesture.require(toFail: contentPopGesture)
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

private struct DanmakuOverlayView: View {
    let danmakus: [DanmakuItem]
    let opacity: Double
    let fontScale: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(danmakus) { item in
                Text(item.text)
                    .font(.system(size: fontSize(for: item), weight: .semibold))
                    .foregroundStyle(Color(hexRGB: item.color))
                    .shadow(color: .black, radius: 2)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .opacity(opacity)
        .animation(.easeOut(duration: 0.25), value: danmakus)
        .padding(.horizontal)
    }

    private func fontSize(for item: DanmakuItem) -> CGFloat {
        CGFloat(min(max(Double(item.fontSize) * fontScale, 14), 32))
    }
}

private extension Color {
    init(hexRGB: Int) {
        let red = Double((hexRGB >> 16) & 0xff) / 255
        let green = Double((hexRGB >> 8) & 0xff) / 255
        let blue = Double(hexRGB & 0xff) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
