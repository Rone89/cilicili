import Combine
import CoreGraphics
import SwiftUI
import UIKit

@MainActor
final class VideoDetailSwiftUIContainerModel: ObservableObject {
    let viewModel: VideoDetailViewModel
    let runtimeSettings: VideoDetailRuntimeSettingsStore
    let rotationCoordinator: PlaybackRotationCoordinator
    let contentUpdateGate: VideoDetailContentUpdateGate
    let contentState = VideoDetailShellContentView.State()

    @Published private(set) var activePlayerViewModel: PlayerStateViewModel?
    @Published private(set) var surfacePlayerViewModel: PlayerStateViewModel?
    @Published private(set) var videoAspectRatio: CGFloat
    @Published private(set) var currentPlayerHeight: CGFloat?
    @Published private(set) var lastScrollOffset: CGFloat = 0
    @Published private(set) var isCollapsedChromeActive = false
    @Published private(set) var isBareSurfaceTransitionActive = false
    @Published private(set) var retainsChromeDuringBareSurfaceTransition = false
    @Published private(set) var playerFrame = CGRect.zero
    @Published var rootSafeAreaInsets = UIEdgeInsets.zero

    private var cancellables = Set<AnyCancellable>()
    private var scrollOffsets: [VideoDetailContentTab: CGFloat] = [:]
    private var visitedContentTabs: Set<VideoDetailContentTab>
    private var isBackgroundRenderFreezeActive = false

    init(
        viewModel: VideoDetailViewModel,
        runtimeSettings: VideoDetailRuntimeSettingsStore,
        rotationCoordinator: PlaybackRotationCoordinator,
        initialContentTab: VideoDetailContentTab
    ) {
        self.viewModel = viewModel
        self.runtimeSettings = runtimeSettings
        self.rotationCoordinator = rotationCoordinator
        contentUpdateGate = VideoDetailContentUpdateGate()
        videoAspectRatio = CGFloat(viewModel.detail.dimension?.aspectRatio ?? (16.0 / 9.0))
        let initialPlayerViewModel = viewModel.playbackSession.activePlayer
        activePlayerViewModel = initialPlayerViewModel
        surfacePlayerViewModel = initialPlayerViewModel
        visitedContentTabs = [initialContentTab]
        bind()
    }

    func setSecondaryContentMounted(_ mounted: Bool) {
        contentState.mountsSecondaryContent = mounted
    }

    func setBackgroundRenderFreezeActive(_ active: Bool) {
        isBackgroundRenderFreezeActive = active
        setContentUpdatesDeferred(false)
    }

    func beginSystemRotation(toLandscape: Bool) {
        isBareSurfaceTransitionActive = true
        retainsChromeDuringBareSurfaceTransition = true
        contentState.suppressesInteractiveContentActions = true
        if !toLandscape {
            currentPlayerHeight = nil
        }
    }

    func finishSystemRotation() {
        isBareSurfaceTransitionActive = false
        retainsChromeDuringBareSurfaceTransition = false
        contentState.suppressesInteractiveContentActions = false
    }

    func recoverStableLayout() {
        isBareSurfaceTransitionActive = false
        retainsChromeDuringBareSurfaceTransition = false
        contentState.suppressesInteractiveContentActions = false
    }

    func setContentUpdatesDeferred(_ deferred: Bool) {
        let shouldDefer = deferred || isBackgroundRenderFreezeActive
        viewModel.setContentRenderUpdatesDeferred(shouldDefer)
        viewModel.setPlaybackRenderUpdatesDeferred(shouldDefer)
        contentUpdateGate.setUpdatesDeferred(shouldDefer)
    }

    func layout(
        in size: CGSize,
        safeAreaTop: CGFloat,
        rotationCoordinator: PlaybackRotationCoordinator
    ) -> VideoDetailShellLayout {
        VideoDetailShellLayout.resolve(
            bounds: CGRect(origin: .zero, size: size),
            safeAreaTop: safeAreaTop,
            videoAspectRatio: videoAspectRatio,
            currentPlayerHeight: currentPlayerHeight,
            isPlaybackActive: isPlaybackActive,
            isLandscape: rotationCoordinator.layoutLandscape,
            isPortraitFullscreen: rotationCoordinator.isPortraitFullscreen
        )
    }

    func synchronize(layout: VideoDetailShellLayout) {
#if DEBUG
        if playerFrame != layout.playerFrame {
            print("[VideoDetailGeometry] coordinates=SwiftUI-root playerFrame=\(layout.playerFrame) contentFrame=\(layout.contentFrame) safeArea=\(rootSafeAreaInsets)")
        }
#endif
        if playerFrame != layout.playerFrame { playerFrame = layout.playerFrame }
        if contentState.hidesBottomToolbar != layout.usesFullscreenLayout {
            contentState.hidesBottomToolbar = layout.usesFullscreenLayout
        }
        guard let contentTopInset = layout.contentTopInset else { return }
        guard abs(contentState.topInset - contentTopInset) > 0.5 else { return }
        contentState.topInset = contentTopInset
    }

    func handleSelectedTabChange(
        _ tab: VideoDetailContentTab,
        bounds: CGSize,
        rotationCoordinator: PlaybackRotationCoordinator
    ) {
        guard !rotationCoordinator.isTransitioning,
              !rotationCoordinator.layoutLandscape,
              !rotationCoordinator.isPortraitFullscreen
        else { return }

        if visitedContentTabs.contains(tab) {
            if let preservedOffset = scrollOffsets[tab] {
                lastScrollOffset = preservedOffset
                if preservedOffset <= 0.5 {
                    currentPlayerHeight = nil
                } else {
                    applyPlayerHeight(forOffset: preservedOffset, bounds: bounds)
                }
                contentState.requestScrollAdjustment(tab: tab, offset: preservedOffset)
                updateCollapsedChrome(bounds: bounds)
            }
            return
        }

        visitedContentTabs.insert(tab)
        let expanded = expandedPlayerHeight(bounds: bounds)
        let current = resolvedPlayerHeight(bounds: bounds)
        let targetOffset = max(0, expanded - current)
        lastScrollOffset = targetOffset
        Task { @MainActor [weak self, weak rotationCoordinator] in
            guard let self,
                  rotationCoordinator?.isTransitioning == false
            else { return }
            self.contentState.requestScrollAdjustment(tab: tab, offset: targetOffset)
        }
    }

    func handleScrollOffset(
        tab: VideoDetailContentTab,
        offset: CGFloat,
        selectedTab: VideoDetailContentTab,
        bounds: CGSize,
        rotationCoordinator: PlaybackRotationCoordinator
    ) {
        scrollOffsets[tab] = offset
        guard tab == selectedTab,
              !rotationCoordinator.isTransitioning,
              !rotationCoordinator.layoutLandscape,
              !rotationCoordinator.isPortraitFullscreen
        else { return }

        let previousOffset = lastScrollOffset
        lastScrollOffset = offset
        if offset <= 0.5 {
            lastScrollOffset = 0
            if previousOffset > 0.5 {
                currentPlayerHeight = nil
            }
        } else {
            applyPlayerHeight(forOffset: offset, bounds: bounds)
        }
        updateCollapsedChrome(bounds: bounds)
    }

    func updateCollapsedChrome(bounds: CGSize) {
        let playerHeight = resolvedPlayerHeight(bounds: bounds)
        let minimum = minimumPlayerHeight(forWidth: bounds.width)
        let standard = VideoDetailShellLayout.standardPlayerHeight(forWidth: bounds.width)
        isCollapsedChromeActive = !rotationCoordinator.layoutLandscape
            && !isPlaybackActive
            && playerHeight <= standard - 4
            && playerHeight > 0
        let collapseDistance = max(standard - minimum, 1)
        _ = max(0, min(1, (standard - playerHeight) / collapseDistance))
    }

    private var isPlaybackActive: Bool {
        guard let player = activePlayerViewModel ?? surfacePlayerViewModel else { return false }
        return player.isPlaying || player.isUserSeeking
    }

    private func bind() {
        viewModel.objectWillChange
            .sink { [weak contentUpdateGate] _ in
                contentUpdateGate?.receiveUpdate()
            }
            .store(in: &cancellables)

        viewModel.$detail
            .receive(on: RunLoop.main)
            .sink { [weak self] detail in
                guard let self,
                      let ratio = detail.dimension?.aspectRatio,
                      ratio > 0.1
                else { return }
                self.videoAspectRatio = CGFloat(ratio)
                self.currentPlayerHeight = nil
            }
            .store(in: &cancellables)

        viewModel.playbackSession.$activePlayer
            .receive(on: RunLoop.main)
            .sink { [weak self] player in
                guard let self else { return }
                self.activePlayerViewModel = player
                if let player {
                    self.surfacePlayerViewModel = player
                }
            }
            .store(in: &cancellables)
    }

    private func expandedPlayerHeight(bounds: CGSize) -> CGFloat {
        VideoDetailShellLayout.expandedPlayerHeight(
            bounds: bounds,
            videoAspectRatio: videoAspectRatio
        )
    }

    private func minimumPlayerHeight(forWidth width: CGFloat) -> CGFloat {
        VideoDetailShellLayout.minimumPlayerHeight(
            forWidth: width,
            isPlaybackActive: isPlaybackActive
        )
    }

    private func resolvedPlayerHeight(bounds: CGSize) -> CGFloat {
        VideoDetailShellLayout.resolvedPlayerHeight(
            bounds: bounds,
            videoAspectRatio: videoAspectRatio,
            currentPlayerHeight: currentPlayerHeight,
            isPlaybackActive: isPlaybackActive
        )
    }

    private func applyPlayerHeight(forOffset offset: CGFloat, bounds: CGSize) {
        let expanded = expandedPlayerHeight(bounds: bounds)
        let minimum = minimumPlayerHeight(forWidth: bounds.width)
        let target = max(minimum, min(expanded, expanded - offset))
        guard currentPlayerHeight.map({ abs($0 - target) > 0.5 }) ?? true else { return }
        currentPlayerHeight = target
    }

}

@MainActor
struct VideoDetailSwiftUIContainer: View {
    let viewModel: VideoDetailViewModel
    @ObservedObject var model: VideoDetailSwiftUIContainerModel
    @ObservedObject var runtimeSettings: VideoDetailRuntimeSettingsStore
    @ObservedObject var rotationCoordinator: PlaybackRotationCoordinator
    @Binding var selectedContentTab: VideoDetailContentTab
    let dependencies: AppDependencies
    let onShowNetworkDiagnostics: () -> Void
    let onShowFavoriteFolders: () -> Void
    let onShowCoinPicker: () -> Void
    let onOpenCommentComposer: (Comment?) -> Void
    let onReply: (Comment) -> Void
    let openVideoOwnerRoute: ((VideoOwner) -> Void)?
    let onShowMoreControls: (@escaping () -> Void) -> Void
    let onDismissMoreControls: () -> Void
    let onRequestFullscreen: () -> Void
    let onExitFullscreen: () -> Void
    let onToggleDanmaku: () -> Void
    let onShowDanmakuSettings: () -> Void
    let onNavigateBack: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let layout = model.layout(
                in: proxy.size,
                safeAreaTop: model.rootSafeAreaInsets.top,
                rotationCoordinator: rotationCoordinator
            )

            ZStack(alignment: .topLeading) {
                VideoDetailShellContentView(
                    viewModel: viewModel,
                    libraryStore: dependencies.libraryStore,
                    updateGate: model.contentUpdateGate,
                    runtimeSettings: runtimeSettings,
                    state: model.contentState,
                    layoutWidth: proxy.size.width,
                    selectedContentTab: $selectedContentTab,
                    onShowNetworkDiagnostics: onShowNetworkDiagnostics,
                    onShowFavoriteFolders: onShowFavoriteFolders,
                    onShowCoinPicker: onShowCoinPicker,
                    onOpenCommentComposer: onOpenCommentComposer,
                    onReply: onReply,
                    openVideoOwnerRoute: openVideoOwnerRoute,
                    onSelectedTabChange: { tab in
                        DispatchQueue.main.async {
                            model.handleSelectedTabChange(
                                tab,
                                bounds: proxy.size,
                                rotationCoordinator: rotationCoordinator
                            )
                        }
                    },
                    onScrollOffsetChange: { tab, offset in
                        DispatchQueue.main.async {
                            model.handleScrollOffset(
                                tab: tab,
                                offset: offset,
                                selectedTab: selectedContentTab,
                                bounds: proxy.size,
                                rotationCoordinator: rotationCoordinator
                            )
                        }
                    }
                )
                .frame(
                    width: layout.contentFrame.width,
                    height: layout.contentFrame.height
                )
                .position(x: layout.contentFrame.midX, y: layout.contentFrame.midY)
                .opacity(layout.usesFullscreenLayout ? 0 : 1)
                .allowsHitTesting(
                    !layout.usesFullscreenLayout
                        && !model.contentState.suppressesInteractiveContentActions
                )

                if let playerViewModel = model.surfacePlayerViewModel {
                    VideoDetailShellSurfaceRepresentable(
                        playerViewModel: playerViewModel,
                        detailViewModel: viewModel,
                        dependencies: dependencies,
                        runtimeSettings: runtimeSettings,
                        rotationCoordinator: rotationCoordinator,
                        videoAspectRatio: model.videoAspectRatio,
                        isBareSurfaceTransitionActive: model.isBareSurfaceTransitionActive,
                        retainsChromeDuringBareSurfaceTransition: model.retainsChromeDuringBareSurfaceTransition,
                        isCollapsedChromeActive: model.isCollapsedChromeActive,
                        onShowMoreControls: onShowMoreControls,
                        onDismissMoreControls: onDismissMoreControls,
                        onRequestFullscreen: onRequestFullscreen,
                        onExitFullscreen: onExitFullscreen,
                        onToggleDanmaku: onToggleDanmaku,
                        onShowDanmakuSettings: onShowDanmakuSettings,
                        onNavigateBack: onNavigateBack
                    )
                    .frame(width: layout.playerFrame.width, height: layout.playerFrame.height)
                    .position(x: layout.playerFrame.midX, y: layout.playerFrame.midY)
                    .zIndex(2)

                    if model.isCollapsedChromeActive && !layout.usesFullscreenLayout {
                        VideoDetailShellCollapsedBar(
                            playerViewModel: playerViewModel,
                            onNavigateBack: onNavigateBack,
                            onRequestFullscreen: onRequestFullscreen
                        )
                        .frame(width: layout.playerFrame.width, height: layout.playerFrame.height)
                        .position(x: layout.playerFrame.midX, y: layout.playerFrame.midY)
                        .zIndex(3)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .onAppear {
                DispatchQueue.main.async {
                    model.synchronize(layout: layout)
                    model.updateCollapsedChrome(bounds: proxy.size)
                }
            }
            .onChange(of: layout) { _, newLayout in
                DispatchQueue.main.async {
                    model.synchronize(layout: newLayout)
                }
            }
        }
        .background(.black)
    }
}

@MainActor
protocol VideoDetailRotationBridgeDelegate: AnyObject {
    func requestVideoDetailFullscreen()
    func requestVideoDetailExitFullscreen()
    func navigateBackFromVideoDetail()
}

/// SwiftUI 内容树的 UIKit 宿主。
///
/// 该控制器只负责承载 SwiftUI 和转发内容层回调；方向请求仍由外层
/// `VideoDetailRotationBridgeViewController` 统一处理。
@MainActor
final class VideoDetailSwiftUIContainerViewController: UIViewController {
    let viewModel: VideoDetailViewModel
    let contentModel: VideoDetailSwiftUIContainerModel
    let rotationCoordinator: PlaybackRotationCoordinator

    weak var rotationDelegate: (any VideoDetailRotationBridgeDelegate)?

    private let runtimeSettings: VideoDetailRuntimeSettingsStore
    private let dependencies: AppDependencies
    private let selectedContentTab: Binding<VideoDetailContentTab>
    private let openVideoOwnerRoute: ((VideoOwner) -> Void)?
    private let onShowNetworkDiagnostics: () -> Void
    private let onShowFavoriteFolders: () -> Void
    private let onShowCoinPicker: () -> Void
    private let onOpenCommentComposer: (Comment?) -> Void
    private let onShowDanmakuSettings: () -> Void
    private let onReply: (Comment) -> Void
    private let onPresentPlayerMoreControls: (PlayerStateViewModel, @escaping () -> Void) -> Void
    private let onDismissPlayerMoreControls: () -> Void
    private let onToggleDanmaku: () -> Void
    private let onNavigateBack: () -> Void
    private let playbackDiagnostics = VideoDetailPlaybackDiagnostics()
    private var cancellables = Set<AnyCancellable>()

#if DEBUG
    private let rotationDiagnosticsAccessibilityView = UILabel()
#endif

    private lazy var hostingController: UIHostingController<VideoDetailSwiftUIContainer> = {
        UIHostingController(rootView: makeRootView())
    }()

    init(
        viewModel: VideoDetailViewModel,
        runtimeSettings: VideoDetailRuntimeSettingsStore,
        dependencies: AppDependencies,
        rotationCoordinator: PlaybackRotationCoordinator,
        openVideoOwnerRoute: ((VideoOwner) -> Void)?,
        selectedContentTab: Binding<VideoDetailContentTab>,
        onShowNetworkDiagnostics: @escaping () -> Void,
        onShowFavoriteFolders: @escaping () -> Void,
        onShowCoinPicker: @escaping () -> Void,
        onOpenCommentComposer: @escaping (Comment?) -> Void,
        onShowDanmakuSettings: @escaping () -> Void,
        onPresentPlayerMoreControls: @escaping (PlayerStateViewModel, @escaping () -> Void) -> Void,
        onDismissPlayerMoreControls: @escaping () -> Void,
        onReply: @escaping (Comment) -> Void,
        onToggleDanmaku: @escaping () -> Void,
        onNavigateBack: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.runtimeSettings = runtimeSettings
        self.dependencies = dependencies
        self.selectedContentTab = selectedContentTab
        self.openVideoOwnerRoute = openVideoOwnerRoute
        self.onShowNetworkDiagnostics = onShowNetworkDiagnostics
        self.onShowFavoriteFolders = onShowFavoriteFolders
        self.onShowCoinPicker = onShowCoinPicker
        self.onOpenCommentComposer = onOpenCommentComposer
        self.onShowDanmakuSettings = onShowDanmakuSettings
        self.onPresentPlayerMoreControls = onPresentPlayerMoreControls
        self.onDismissPlayerMoreControls = onDismissPlayerMoreControls
        self.onReply = onReply
        self.onToggleDanmaku = onToggleDanmaku
        self.onNavigateBack = onNavigateBack
        self.rotationCoordinator = rotationCoordinator
        contentModel = VideoDetailSwiftUIContainerModel(
            viewModel: viewModel,
            runtimeSettings: runtimeSettings,
            rotationCoordinator: rotationCoordinator,
            initialContentTab: selectedContentTab.wrappedValue
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        addChild(hostingController)
        hostingController.safeAreaRegions = []
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hostingController.didMove(toParent: self)
#if DEBUG
        rotationDiagnosticsAccessibilityView.isAccessibilityElement = true
        rotationDiagnosticsAccessibilityView.accessibilityIdentifier = "ui.videoDetail.rotationDiagnostics"
        rotationDiagnosticsAccessibilityView.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        rotationDiagnosticsAccessibilityView.alpha = 0.01
        view.addSubview(rotationDiagnosticsAccessibilityView)
#endif
        contentModel.$activePlayerViewModel
            .receive(on: RunLoop.main)
            .sink { [weak self] player in
                self?.playbackDiagnostics.observe(player: player)
            }
            .store(in: &cancellables)
        playbackDiagnostics.begin(
            metricsID: viewModel.detail.bvid,
            title: viewModel.detail.title
        )
        Task { await viewModel.load() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let insets = view.safeAreaInsets
        if contentModel.rootSafeAreaInsets != insets {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.view.safeAreaInsets == insets else { return }
                self.contentModel.rootSafeAreaInsets = insets
                self.contentModel.contentState.bottomInset = insets.bottom
            }
        }
    }

    var activePlayerViewModel: PlayerStateViewModel? {
        contentModel.activePlayerViewModel
    }

    var playerFrame: CGRect {
        contentModel.playerFrame
    }

    var isPortraitVideo: Bool {
        (viewModel.detail.dimension?.aspectRatio ?? (16.0 / 9.0)) < 0.9
    }

    func setSecondaryContentMounted(_ mounted: Bool) {
        contentModel.setSecondaryContentMounted(mounted)
    }

    func setBackgroundRenderFreezeActive(_ active: Bool) {
        contentModel.setBackgroundRenderFreezeActive(active)
    }

    func beginSystemRotation(toLandscape: Bool) {
        contentModel.beginSystemRotation(toLandscape: toLandscape)
    }

    func finishSystemRotation() {
        contentModel.finishSystemRotation()
    }

    func recoverStableLayout() {
        contentModel.recoverStableLayout()
    }

    func dismissPlayerMoreControls() {
        onDismissPlayerMoreControls()
    }

    func presentPlayerMoreControls(onDismiss: @escaping () -> Void) {
        guard let player = activePlayerViewModel else {
            onDismiss()
            return
        }
        onPresentPlayerMoreControls(player, onDismiss)
    }

    func navigateBack() {
        onNavigateBack()
    }

    func suppressContentActionsDuringSystemBackGesture() {
        contentModel.contentState.suppressesInteractiveContentActions = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.contentModel.contentState.suppressesInteractiveContentActions = false
        }
    }

    func markRotationStarted(toLandscape: Bool) {
        playbackDiagnostics.markRotationStarted(toLandscape: toLandscape)
    }

    func markRotationFinished(toLandscape: Bool) {
        playbackDiagnostics.markRotationFinished(toLandscape: toLandscape)
        publishLatestRotationDiagnostic()
    }

    func markRotationRecovered(reason: String) {
        playbackDiagnostics.markRotationRecovered(reason: reason)
        publishLatestRotationDiagnostic()
    }

    func markPageDisappeared() {
        playbackDiagnostics.markPageDisappeared()
        publishLatestRotationDiagnostic()
    }

    func prepareForDismantle() {
        onDismissPlayerMoreControls()
        contentModel.setBackgroundRenderFreezeActive(false)
        playbackDiagnostics.markPageDisappeared()
        publishLatestRotationDiagnostic()
    }

    private func makeRootView() -> VideoDetailSwiftUIContainer {
        VideoDetailSwiftUIContainer(
            viewModel: viewModel,
            model: contentModel,
            runtimeSettings: runtimeSettings,
            rotationCoordinator: rotationCoordinator,
            selectedContentTab: selectedContentTab,
            dependencies: dependencies,
            onShowNetworkDiagnostics: onShowNetworkDiagnostics,
            onShowFavoriteFolders: onShowFavoriteFolders,
            onShowCoinPicker: onShowCoinPicker,
            onOpenCommentComposer: onOpenCommentComposer,
            onReply: onReply,
            openVideoOwnerRoute: openVideoOwnerRoute,
            onShowMoreControls: { [weak self] onDismiss in
                self?.presentPlayerMoreControls(onDismiss: onDismiss)
                    ?? onDismiss()
            },
            onDismissMoreControls: onDismissPlayerMoreControls,
            onRequestFullscreen: { [weak self] in
                self?.rotationDelegate?.requestVideoDetailFullscreen()
            },
            onExitFullscreen: { [weak self] in
                self?.rotationDelegate?.requestVideoDetailExitFullscreen()
            },
            onToggleDanmaku: onToggleDanmaku,
            onShowDanmakuSettings: onShowDanmakuSettings,
            onNavigateBack: { [weak self] in
                self?.rotationDelegate?.navigateBackFromVideoDetail()
            }
        )
    }

    private func publishLatestRotationDiagnostic() {
#if DEBUG
        guard let record = playbackDiagnostics.completedRotationRecords.last,
              let data = try? JSONEncoder().encode(record),
              let value = String(data: data, encoding: .utf8)
        else { return }
        rotationDiagnosticsAccessibilityView.accessibilityValue = value
#endif
    }
}
