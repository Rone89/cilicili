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
    @Published private(set) var isTransferredToSystemMiniPlayer = false
    @Published private(set) var videoAspectRatio: CGFloat
    @Published private(set) var currentPlayerHeight: CGFloat?
    private(set) var lastScrollOffset: CGFloat = 0
    @Published private(set) var isCollapsedChromeActive = false
    @Published private(set) var isPlaybackActiveSnapshot = false
    @Published private(set) var isBareSurfaceTransitionActive = false
    @Published private(set) var retainsChromeDuringBareSurfaceTransition = false
    private(set) var playerFrame = CGRect.zero
    private(set) var splitContentFrame = CGRect.zero
    private(set) var isTwoColumnSplitActive = false
    private(set) var inlineSheetHeightFraction: CGFloat = 0.94
    private(set) var stackedBelowPlayerSheetMaxHeight: CGFloat?
    private var lastHorizontalSizeClass: UserInterfaceSizeClass?
    var onSplitContentGeometryChange: ((CGRect, Bool, CGFloat, CGFloat?) -> Void)?
    #if DEBUG
        let playerFrameUpdates = CurrentValueSubject<CGRect, Never>(.zero)
    #endif
    @Published private(set) var navigationHistory: NavigationHistoryContext?
    @Published var rootSafeAreaInsets = UIEdgeInsets.zero
    private(set) var lastEmbeddedSafeAreaInsets: UIEdgeInsets?
    private(set) var interactiveScrollOffset: CGFloat = 0

    private var cancellables = Set<AnyCancellable>()
    private var playbackStateCancellables = Set<AnyCancellable>()
    private var aspectRatioCancellables = Set<AnyCancellable>()
    private var scrollOffsets: [VideoDetailContentTab: CGFloat] = [:]
    private var interactiveScrollOffsets: [VideoDetailContentTab: CGFloat] = [:]
    private var visitedContentTabs: Set<VideoDetailContentTab>
    private var activeContentTab: VideoDetailContentTab
    private var pendingInteractiveTab: VideoDetailContentTab?
    private var pendingInteractiveTabOffset: CGFloat = 0
    private var isBackgroundRenderFreezeActive = false
    private var layoutSynchronizationScheduled = false
    private var pendingLayout: VideoDetailShellLayout?
    /// 上一次嵌入（非全屏）布局的内容区尺寸。进入全屏布局时内容区沿用该尺寸，
    /// 其中的 UIKit 评论表在旋转前后宽度不变，行高缓存与滚动几何完整存活。
    private var lastEmbeddedContentSize: CGSize?

    init(
        viewModel: VideoDetailViewModel,
        initialVideo: VideoItem,
        runtimeSettings: VideoDetailRuntimeSettingsStore,
        rotationCoordinator: PlaybackRotationCoordinator,
        initialContentTab: VideoDetailContentTab
    ) {
        self.viewModel = viewModel
        self.runtimeSettings = runtimeSettings
        self.rotationCoordinator = rotationCoordinator
        contentUpdateGate = VideoDetailContentUpdateGate()
        let isTransferred = viewModel.didTransferToSystemMiniPlayer
        let initialPlayerViewModel = isTransferred ? nil : viewModel.playbackSession.activePlayer
        videoAspectRatio =
            VideoDetailInitialVideoGeometry.metadataAspectRatio(for: initialVideo)
            ?? VideoDetailInitialVideoGeometry.metadataAspectRatio(for: viewModel.detail)
            ?? initialPlayerViewModel?.videoAspectRatio
            ?? VideoDetailInitialVideoGeometry.defaultAspectRatio
        isTransferredToSystemMiniPlayer = isTransferred
        activePlayerViewModel = initialPlayerViewModel
        surfacePlayerViewModel = initialPlayerViewModel
        visitedContentTabs = [initialContentTab]
        activeContentTab = initialContentTab
        bind()
        bindVideoAspectRatio(to: initialPlayerViewModel)
        bindPlaybackState(to: initialPlayerViewModel)
    }

    func updateNavigationHistory(_ history: NavigationHistoryContext?) {
        guard navigationHistory?.controller !== history?.controller else { return }
        navigationHistory = history
    }

    var isInteractiveScrollCollapseActive: Bool {
        VideoDetailShellLayout.supportsInteractiveCollapse(
            videoAspectRatio: videoAspectRatio,
            isPlaybackActive: isPlaybackActiveSnapshot
        )
    }

    func setSecondaryContentMounted(_ mounted: Bool) {
        guard contentState.mountsSecondaryContent != mounted else { return }
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
            if let lastEmbeddedSafeAreaInsets {
                applyRootSafeAreaInsetsWithoutAnimation(lastEmbeddedSafeAreaInsets)
            }
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

    /// 全屏/横屏布局不消费顶部安全区，也不展示竖屏底部内容区。仅在非全屏竖屏态
    /// 采集并保留嵌入安全区，确保横屏退回竖屏首帧即有正确顶栏安全区而不偏上。
    func canApplySafeAreaInsets(
        _ insets: UIEdgeInsets,
        isPortraitContainer: Bool
    ) -> Bool {
        guard !rotationCoordinator.layoutLandscape,
              !rotationCoordinator.isPortraitFullscreen,
              isPortraitContainer
        else { return false }
        if rotationCoordinator.isTransitioning,
           insets.top <= 0,
           rootSafeAreaInsets.top > 0 || (lastEmbeddedSafeAreaInsets?.top ?? 0) > 0 {
            return false
        }
        return true
    }

    func applySafeAreaInsetsIfAppropriate(
        _ insets: UIEdgeInsets,
        isPortraitContainer: Bool
    ) {
        guard canApplySafeAreaInsets(insets, isPortraitContainer: isPortraitContainer) else {
            return
        }
        lastEmbeddedSafeAreaInsets = insets
        applyRootSafeAreaInsetsWithoutAnimation(insets)
    }

    private func applyRootSafeAreaInsetsWithoutAnimation(_ insets: UIEdgeInsets) {
        guard rootSafeAreaInsets != insets || contentState.bottomInset != insets.bottom else {
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if rootSafeAreaInsets != insets {
                rootSafeAreaInsets = insets
            }
            if contentState.bottomInset != insets.bottom {
                contentState.bottomInset = insets.bottom
            }
        }
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
        safeAreaBottom: CGFloat = 0,
        safeAreaLeading: CGFloat = 0,
        safeAreaTrailing: CGFloat = 0,
        horizontalSizeClass: UserInterfaceSizeClass? = nil,
        rotationCoordinator: PlaybackRotationCoordinator
    ) -> VideoDetailShellLayout {
        lastHorizontalSizeClass = horizontalSizeClass
        let adaptiveEnabled = runtimeSettings.adaptiveLargeScreenLayoutExperimentEnabled
        let targetMode = AdaptiveLayoutPolicy.videoDetailMode(
            containerSize: size,
            horizontalSizeClass: horizontalSizeClass,
            isFullscreenActive: rotationCoordinator.layoutLandscape || rotationCoordinator.isPortraitFullscreen,
            adaptiveEnabled: adaptiveEnabled
        )
        let effectiveCompactWidth = AdaptiveLayoutPolicy.duoFoldedContentHorizontalBounds(
            containerBounds: CGRect(origin: .zero, size: size),
            safeAreaInsets: EdgeInsets(
                top: safeAreaTop,
                leading: safeAreaLeading,
                bottom: safeAreaBottom,
                trailing: safeAreaTrailing
            )
        )?.width ?? size.width
        let effectiveCompactBounds = CGSize(width: effectiveCompactWidth, height: size.height)
        let effectiveInteractiveOffset =
            (targetMode == .compactStacked && isInteractiveScrollCollapseActive)
            ? interactiveScrollOffset
            : nil
        let effectivePlayerHeight =
            effectiveInteractiveOffset.map {
                interactivePlayerHeight(forOffset: $0, bounds: effectiveCompactBounds)
            } ?? currentPlayerHeight
        let layout = VideoDetailShellLayout.resolve(
            bounds: CGRect(origin: .zero, size: size),
            safeAreaTop: safeAreaTop,
            safeAreaBottom: safeAreaBottom,
            safeAreaLeading: safeAreaLeading,
            safeAreaTrailing: safeAreaTrailing,
            videoAspectRatio: videoAspectRatio,
            currentPlayerHeight: effectivePlayerHeight,
            isPlaybackActive: isPlaybackActiveForLayout,
            isLandscape: rotationCoordinator.layoutLandscape,
            isPortraitFullscreen: rotationCoordinator.isPortraitFullscreen,
            fullscreenContentFrameSize: lastEmbeddedContentSize,
            horizontalSizeClass: horizontalSizeClass,
            adaptiveLargeScreenEnabled: adaptiveEnabled
        )
        if !layout.usesFullscreenLayout {
            lastEmbeddedContentSize = layout.contentFrame.size
        }
        return layout
    }

    func storedInteractiveScrollOffset(for tab: VideoDetailContentTab) -> CGFloat {
        interactiveScrollOffsets[tab] ?? 0
    }

    func shouldShowCollapsedChrome(
        for layout: VideoDetailShellLayout,
        bounds: CGSize
    ) -> Bool {
        guard layout.adaptiveMode == .compactStacked else { return false }
        guard !isPlaybackActiveSnapshot else { return false }
        guard isInteractiveScrollCollapseActive else { return isCollapsedChromeActive }
        let standard = VideoDetailShellLayout.standardPlayerHeight(forWidth: bounds.width)
        return !rotationCoordinator.layoutLandscape
            && layout.playerFrame.height <= standard - 4
            && layout.playerFrame.height > 0
    }

    func collapsedChromeOpacity(
        for layout: VideoDetailShellLayout,
        bounds: CGSize
    ) -> Double {
        guard !isPlaybackActiveSnapshot,
            !rotationCoordinator.layoutLandscape,
            shouldShowCollapsedChrome(for: layout, bounds: bounds)
        else { return 0 }

        let standard = VideoDetailShellLayout.standardPlayerHeight(forWidth: bounds.width)
        let minimum = minimumPlayerHeight(forWidth: bounds.width)
        let distance = max(standard - minimum, 1)
        return max(0, min(1, Double((standard - layout.playerFrame.height) / distance)))
    }

    func synchronize(layout: VideoDetailShellLayout) {
        #if DEBUG
            if playerFrame != layout.playerFrame {
                print(
                    "[VideoDetailGeometry] coordinates=SwiftUI-root playerFrame=\(layout.playerFrame) "
                        + "contentFrame=\(layout.contentFrame) safeArea=\(rootSafeAreaInsets)"
                )
            }
        #endif
        if playerFrame != layout.playerFrame {
            playerFrame = layout.playerFrame
            #if DEBUG
                playerFrameUpdates.send(playerFrame)
            #endif
        }
        let nextStackedBelowPlayerHeight: CGFloat? = if layout.adaptiveMode == .compactStacked, !layout.usesFullscreenLayout {
            VideoDetailSheetHeightPolicy.belowVideoDetentHeight(
                containerHeight: layout.contentFrame.maxY,
                playerBottomY: layout.playerFrame.maxY,
                bottomSafeAreaInset: rootSafeAreaInsets.bottom
            )
        } else {
            nil
        }

        let nextInlineFrame: CGRect
        let nextInlineActive: Bool
        let nextInlineHeightFraction: CGFloat
        if layout.adaptiveMode == .twoColumnSplit, !layout.usesFullscreenLayout {
            nextInlineFrame = layout.contentFrame
            nextInlineActive = true
            nextInlineHeightFraction = 0.94
        } else if layout.adaptiveMode == .compactStacked,
                  !layout.usesFullscreenLayout,
                  lastHorizontalSizeClass == .regular || layout.usesDuoFoldedHorizontalBounds {
            // Regular-width portrait (unfolded iPhone Duo / iPad portrait) or folded iPhone Duo
            // cover display: system `.sheet` spans full width (covering Duo's right chrome rail)
            // or floats centered over the video. Anchor inline sheets strictly inside
            // `layout.contentFrame` below `playerFrame.maxY` using the native `UIGlassEffect` host.
            let belowY = layout.playerFrame.maxY
            let belowHeight = max(layout.contentFrame.maxY - belowY, 0)
            nextInlineFrame = CGRect(
                x: layout.contentFrame.minX,
                y: belowY,
                width: layout.contentFrame.width,
                height: belowHeight
            )
            nextInlineActive = belowHeight >= 160
            nextInlineHeightFraction = 1.0
        } else {
            nextInlineFrame = .zero
            nextInlineActive = false
            nextInlineHeightFraction = 0.94
        }

        let geometryChanged = splitContentFrame != nextInlineFrame
            || isTwoColumnSplitActive != nextInlineActive
            || abs(inlineSheetHeightFraction - nextInlineHeightFraction) > 0.005
            || stackedBelowPlayerSheetMaxHeight != nextStackedBelowPlayerHeight
        if geometryChanged {
            splitContentFrame = nextInlineFrame
            isTwoColumnSplitActive = nextInlineActive
            inlineSheetHeightFraction = nextInlineHeightFraction
            stackedBelowPlayerSheetMaxHeight = nextStackedBelowPlayerHeight
            onSplitContentGeometryChange?(
                nextInlineFrame,
                nextInlineActive,
                nextInlineHeightFraction,
                nextStackedBelowPlayerHeight
            )
        }
        if contentState.hidesBottomToolbar != layout.usesFullscreenLayout {
            contentState.hidesBottomToolbar = layout.usesFullscreenLayout
        }
        let targetBottomInset = layout.adaptiveMode == .twoColumnSplit
            ? max(rootSafeAreaInsets.bottom, 20)
            : rootSafeAreaInsets.bottom
        if abs(contentState.bottomInset - targetBottomInset) > 0.5 {
            contentState.bottomInset = targetBottomInset
        }
        guard let contentTopInset = layout.contentTopInset else { return }
        guard abs(contentState.topInset - contentTopInset) > 0.5 else { return }
        contentState.topInset = contentTopInset
    }

    func scheduleLayoutSynchronization(_ layout: VideoDetailShellLayout) {
        pendingLayout = layout
        guard !layoutSynchronizationScheduled else { return }
        layoutSynchronizationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.layoutSynchronizationScheduled = false
            guard let layout = self.pendingLayout else { return }
            self.pendingLayout = nil
            self.synchronize(layout: layout)
        }
    }

    func handleSelectedTabChange(
        _ tab: VideoDetailContentTab,
        bounds: CGSize,
        rotationCoordinator: PlaybackRotationCoordinator
    ) {
        activeContentTab = tab
        guard !rotationCoordinator.isTransitioning,
            !rotationCoordinator.layoutLandscape,
            !rotationCoordinator.isPortraitFullscreen
        else { return }

        if isInteractiveScrollCollapseActive {
            let targetOffset: CGFloat
            if pendingInteractiveTab == tab {
                targetOffset = pendingInteractiveTabOffset
            } else {
                targetOffset = prepareInteractiveTabChange(to: tab, bounds: bounds)
            }
            contentState.requestScrollAdjustment(tab: tab, offset: targetOffset)
            return
        }

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

    @discardableResult
    func prepareInteractiveTabChange(
        to tab: VideoDetailContentTab,
        bounds: CGSize
    ) -> CGFloat {
        guard isInteractiveScrollCollapseActive else { return 0 }

        let expanded = expandedPlayerHeight(bounds: bounds)
        let minimum = minimumPlayerHeight(forWidth: bounds.width)
        let currentMetrics = VideoDetailShellLayout.interactiveScrollMetrics(
            scrollOffset: interactiveScrollOffset,
            expandedPlayerHeight: expanded,
            minimumPlayerHeight: minimum
        )
        let storedOffset = storedInteractiveScrollOffset(for: tab)
        let targetOffset: CGFloat
        if storedOffset > currentMetrics.collapseDistance + 0.5 {
            targetOffset = storedOffset
        } else {
            targetOffset = currentMetrics.collapseOffset
        }
        guard
            pendingInteractiveTab != tab
                || abs(pendingInteractiveTabOffset - targetOffset) > 0.5
        else { return targetOffset }
        pendingInteractiveTab = tab
        pendingInteractiveTabOffset = targetOffset
        setInteractiveScrollOffset(targetOffset, for: tab)
        updateCollapsedChrome(bounds: bounds)
        return targetOffset
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

    func recordInteractiveScrollOffset(
        tab: VideoDetailContentTab,
        offset: CGFloat,
        selectedTab: VideoDetailContentTab,
        bounds: CGSize
    ) {
        applyInteractiveScrollOffset(
            tab: tab,
            offset: offset,
            selectedTab: selectedTab,
            bounds: bounds
        )
    }

    private func applyInteractiveScrollOffset(
        tab: VideoDetailContentTab,
        offset: CGFloat,
        selectedTab: VideoDetailContentTab,
        bounds: CGSize
    ) {
        let normalizedOffset = max(0, offset)
        activeContentTab = selectedTab
        guard tab == selectedTab else {
            interactiveScrollOffsets[tab] = normalizedOffset
            return
        }

        if pendingInteractiveTab == tab {
            guard normalizedOffset + 0.5 >= pendingInteractiveTabOffset else { return }
            pendingInteractiveTab = nil
            pendingInteractiveTabOffset = 0
        }

        let previousHeight = interactivePlayerHeight(forOffset: interactiveScrollOffset, bounds: bounds)
        let nextHeight = interactivePlayerHeight(forOffset: normalizedOffset, bounds: bounds)
        setInteractiveScrollOffset(
            normalizedOffset,
            for: tab,
            updatesLayout: isInteractiveScrollCollapseActive && abs(previousHeight - nextHeight) > 0.5
        )
        updateCollapsedChrome(bounds: bounds)
    }

    func handleInteractiveScrollPhase(
        tab: VideoDetailContentTab,
        phase: ScrollPhase,
        selectedTab: VideoDetailContentTab
    ) {
        guard tab == selectedTab else { return }
        if phase == .tracking || phase == .interacting {
            pendingInteractiveTab = nil
            pendingInteractiveTabOffset = 0
        }
    }

    func updateCollapsedChrome(bounds: CGSize) {
        let playerHeight: CGFloat
        if isInteractiveScrollCollapseActive {
            playerHeight = interactivePlayerHeight(
                forOffset: interactiveScrollOffset,
                bounds: bounds
            )
        } else {
            playerHeight = resolvedPlayerHeight(bounds: bounds)
        }
        let standard = VideoDetailShellLayout.standardPlayerHeight(forWidth: bounds.width)
        let showsCollapsedChrome =
            !rotationCoordinator.layoutLandscape
            && !isPlaybackActiveSnapshot
            && playerHeight <= standard - 4
            && playerHeight > 0
        if isCollapsedChromeActive != showsCollapsedChrome {
            isCollapsedChromeActive = showsCollapsedChrome
        }
    }

    private var isPlaybackActive: Bool {
        isPlaybackActiveSnapshot
    }

    private var isPlaybackActiveForLayout: Bool {
        isPlaybackActive
    }

    private func bind() {
        viewModel.$detail
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] detail in
                guard let self else { return }
                // The content tree only needs rebuilding when the detail's
                // structure changes. Interaction, comments, playback and
                // recommendations update through their narrow render stores.
                // Rebuilding for every view-model publication makes the
                // intrinsic-sized hosting view repeatedly relayout on entry.
                self.contentUpdateGate.receiveUpdate()
                let ratio =
                    VideoDetailInitialVideoGeometry.metadataAspectRatio(for: detail)
                    ?? self.surfacePlayerViewModel?.videoAspectRatio
                guard let ratio, ratio.isFinite, ratio > 0.1,
                    abs(self.videoAspectRatio - ratio) > 0.001
                else { return }
                self.videoAspectRatio = ratio
                self.currentPlayerHeight = nil
            }
            .store(in: &cancellables)

        viewModel.$selectedCID
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak contentUpdateGate] _ in
                contentUpdateGate?.receiveUpdate()
            }
            .store(in: &cancellables)

        viewModel.playbackSession.$activePlayer
            .receive(on: RunLoop.main)
            .sink { [weak self] player in
                guard let self else { return }
                self.activePlayerViewModel = player
                if let player, !self.viewModel.didTransferToSystemMiniPlayer {
                    self.surfacePlayerViewModel = player
                    self.isTransferredToSystemMiniPlayer = false
                } else if self.viewModel.didTransferToSystemMiniPlayer {
                    self.surfacePlayerViewModel = nil
                    self.isTransferredToSystemMiniPlayer = true
                }
                self.bindVideoAspectRatio(to: player)
                self.bindPlaybackState(
                    to: player ?? (self.isTransferredToSystemMiniPlayer ? nil : self.surfacePlayerViewModel)
                )
            }
            .store(in: &cancellables)
    }

    private func bindVideoAspectRatio(to player: PlayerStateViewModel?) {
        aspectRatioCancellables.removeAll()
        guard let player else { return }

        applyPlayerAspectRatioIfNeeded(player.videoAspectRatio)
        player.$videoPresentationSize
            .receive(on: RunLoop.main)
            .sink { [weak self, weak player] _ in
                guard let self, let player else { return }
                self.applyPlayerAspectRatioIfNeeded(player.videoAspectRatio)
            }
            .store(in: &aspectRatioCancellables)
    }

    private func applyPlayerAspectRatioIfNeeded(_ ratio: CGFloat?) {
        guard VideoDetailInitialVideoGeometry.metadataAspectRatio(for: viewModel.detail) == nil,
            let ratio,
            ratio.isFinite,
            ratio > 0.1,
            abs(videoAspectRatio - ratio) > 0.001
        else { return }
        videoAspectRatio = ratio
        currentPlayerHeight = nil
    }

    private func bindPlaybackState(to player: PlayerStateViewModel?) {
        playbackStateCancellables.removeAll()
        guard let player else {
            updatePlaybackActivity(false)
            return
        }

        let updatePlaybackState: (Bool, Bool) -> Void = { [weak self] isPlaying, isUserSeeking in
            self?.updatePlaybackActivity(isPlaying || isUserSeeking)
        }
        updatePlaybackState(player.isPlaying, player.isUserSeeking)
        player.$isPlaying
            .combineLatest(player.$isUserSeeking)
            .removeDuplicates { lhs, rhs in lhs == rhs }
            .sink { isPlaying, isUserSeeking in
                updatePlaybackState(isPlaying, isUserSeeking)
            }
            .store(in: &playbackStateCancellables)
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
            isPlaybackActive: isPlaybackActiveForLayout,
            videoAspectRatio: videoAspectRatio
        )
    }

    private func resolvedPlayerHeight(bounds: CGSize) -> CGFloat {
        VideoDetailShellLayout.resolvedPlayerHeight(
            bounds: bounds,
            videoAspectRatio: videoAspectRatio,
            currentPlayerHeight: currentPlayerHeight,
            isPlaybackActive: isPlaybackActiveForLayout
        )
    }

    func interactiveScrollContentMinimumPlayerHeight(forWidth width: CGFloat) -> CGFloat {
        if VideoDetailShellLayout.usesFullWidthAspectRatioVideo(
            videoAspectRatio: videoAspectRatio
        ) {
            return VideoDetailShellLayout.standardPlayerHeight(forWidth: width)
        }
        // Preserve the production scroll extent across play/pause changes.
        return VideoDetailShellLayout.collapsedToolbarHeight
    }

    private func applyPlayerHeight(forOffset offset: CGFloat, bounds: CGSize) {
        let target = interactivePlayerHeight(forOffset: offset, bounds: bounds)
        guard currentPlayerHeight.map({ abs($0 - target) > 0.5 }) ?? true else { return }
        currentPlayerHeight = target
    }

    private func interactivePlayerHeight(forOffset offset: CGFloat, bounds: CGSize) -> CGFloat {
        let expanded = expandedPlayerHeight(bounds: bounds)
        let minimum = minimumPlayerHeight(forWidth: bounds.width)
        let target = max(minimum, min(expanded, expanded - offset))
        return target
    }

    private func setInteractiveScrollOffset(
        _ offset: CGFloat,
        for tab: VideoDetailContentTab,
        updatesLayout: Bool = true
    ) {
        let normalizedOffset = max(0, offset)
        interactiveScrollOffsets[tab] = normalizedOffset
        guard abs(interactiveScrollOffset - normalizedOffset) > 0.5 else { return }
        if updatesLayout { objectWillChange.send() }
        interactiveScrollOffset = normalizedOffset
    }

    private func updatePlaybackActivity(_ isActive: Bool) {
        let wasInteractive = isInteractiveScrollCollapseActive
        guard isPlaybackActiveSnapshot != isActive else { return }

        if wasInteractive {
            lastScrollOffset = interactiveScrollOffset
        }
        isPlaybackActiveSnapshot = isActive

        guard !wasInteractive, isInteractiveScrollCollapseActive else { return }
        setInteractiveScrollOffset(lastScrollOffset, for: activeContentTab)
    }

}

@MainActor
private struct VideoDetailInteractivePlayerLayer: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject var model: VideoDetailSwiftUIContainerModel
    @ObservedObject var rotationCoordinator: PlaybackRotationCoordinator
    let viewModel: VideoDetailViewModel
    let size: CGSize
    let safeAreaTop: CGFloat
    let safeAreaBottom: CGFloat
    let safeAreaLeading: CGFloat
    let safeAreaTrailing: CGFloat
    let selectedContentTab: VideoDetailContentTab
    let dependencies: AppDependencies
    let runtimeSettings: VideoDetailRuntimeSettingsStore
    let onShowMoreControls: (@escaping () -> Void) -> Void
    let onDismissMoreControls: () -> Void
    let onRequestFullscreen: () -> Void
    let onExitFullscreen: () -> Void
    let onToggleDanmaku: () -> Void
    let onShowDanmakuSettings: () -> Void
    let onNavigateBack: () -> Void

    var body: some View {
        let layout = model.layout(
            in: size,
            safeAreaTop: safeAreaTop,
            safeAreaBottom: safeAreaBottom,
            safeAreaLeading: safeAreaLeading,
            safeAreaTrailing: safeAreaTrailing,
            horizontalSizeClass: horizontalSizeClass,
            rotationCoordinator: rotationCoordinator
        )
        let collapsedBounds = layout.contentFrame.size
        let showsCollapsedChrome = model.shouldShowCollapsedChrome(
            for: layout,
            bounds: collapsedBounds
        )
        let collapsedChromeOpacity = model.collapsedChromeOpacity(
            for: layout,
            bounds: collapsedBounds
        )

        let suppressesRotationAnimation = rotationCoordinator.isTransitioning || layout.usesFullscreenLayout

        let isMiniPlayerTransferred =
            model.isTransferredToSystemMiniPlayer || viewModel.didTransferToSystemMiniPlayer

        ZStack(alignment: .topLeading) {
            // Keep the player stage opaque while the stable player/surface is
            // still being created or while centered in two-column split mode.
            Color.black
                .frame(width: layout.playerStageFrame.width, height: layout.playerStageFrame.height)
                .position(x: layout.playerStageFrame.midX, y: layout.playerStageFrame.midY)
                .allowsHitTesting(false)
                .disablingRotationTransaction(suppressesRotationAnimation)
                .zIndex(1)

            if let playerViewModel = model.surfacePlayerViewModel, !isMiniPlayerTransferred {
                VideoDetailShellSurfaceRepresentable(
                    playerViewModel: playerViewModel,
                    detailViewModel: viewModel,
                    dependencies: dependencies,
                    runtimeSettings: runtimeSettings,
                    rotationCoordinator: rotationCoordinator,
                    videoAspectRatio: model.videoAspectRatio,
                    danmakuCanvasSize: layout.usesFullscreenLayout ? nil : layout.danmakuCanvasSize,
                    isBareSurfaceTransitionActive: model.isBareSurfaceTransitionActive,
                    retainsChromeDuringBareSurfaceTransition: model.retainsChromeDuringBareSurfaceTransition,
                    isCollapsedChromeActive: showsCollapsedChrome,
                    onShowMoreControls: onShowMoreControls,
                    onDismissMoreControls: onDismissMoreControls,
                    onRequestFullscreen: onRequestFullscreen,
                    onExitFullscreen: onExitFullscreen,
                    onToggleDanmaku: onToggleDanmaku,
                    onShowDanmakuSettings: onShowDanmakuSettings
                )
                .environment(\.colorScheme, .dark)
                .frame(width: layout.playerFrame.width, height: layout.playerFrame.height)
                .position(x: layout.playerFrame.midX, y: layout.playerFrame.midY)
                .disablingRotationTransaction(suppressesRotationAnimation)
                .zIndex(2)

                if showsCollapsedChrome && !layout.usesFullscreenLayout {
                    VideoDetailShellCollapsedBar(
                        playerViewModel: playerViewModel,
                        opacity: collapsedChromeOpacity,
                        onNavigateBack: onNavigateBack,
                        onRequestFullscreen: onRequestFullscreen
                    )
                    .frame(width: layout.playerFrame.width, height: layout.playerFrame.height)
                    .position(x: layout.playerFrame.midX, y: layout.playerFrame.midY)
                    .disablingRotationTransaction(suppressesRotationAnimation)
                    .zIndex(3)
                }
            } else if isMiniPlayerTransferred {
                VideoDetailMiniPlayerTransitionSurfaceFallback(
                    snapshot: viewModel.playbackTransitionSnapshot
                )
                .frame(width: layout.playerFrame.width, height: layout.playerFrame.height)
                .position(x: layout.playerFrame.midX, y: layout.playerFrame.midY)
                .allowsHitTesting(false)
                .disablingRotationTransaction(suppressesRotationAnimation)
                .zIndex(2)
            } else {
                Group {
                    if let episodeID = viewModel.detail.pgcEpisodeID {
                        VideoDetailPgcResolutionPlaceholder(
                            store: viewModel.playbackRenderStore.placeholderStore,
                            episodeID: episodeID,
                            retry: { await viewModel.load() }
                        )
                    } else {
                        PlayerLoadingPlaceholder(
                            progress: 0.08,
                            message: "加载视频信息",
                            isFinishing: false,
                            showsProgress: false
                        )
                        .allowsHitTesting(false)
                    }
                }
                .frame(width: layout.playerFrame.width, height: layout.playerFrame.height)
                .position(x: layout.playerFrame.midX, y: layout.playerFrame.midY)
                .disablingRotationTransaction(suppressesRotationAnimation)
                .zIndex(2)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .onChange(of: layout) { _, newLayout in
            guard newLayout.playerFrame != model.playerFrame
                || newLayout.contentFrame != model.splitContentFrame
                || (newLayout.adaptiveMode == .twoColumnSplit) != model.isTwoColumnSplitActive
            else { return }
            model.scheduleLayoutSynchronization(newLayout)
        }
    }
}

@MainActor
private struct VideoDetailMiniPlayerTransitionSurfaceFallback: View {
    let snapshot: PlaybackTransitionSnapshot?

    var body: some View {
        ZStack {
            Color.black
            if let snapshot {
                Image(uiImage: snapshot.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .clipped()
    }
}

@MainActor
struct VideoDetailSwiftUIContainer: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let viewModel: VideoDetailViewModel
    @ObservedObject var model: VideoDetailSwiftUIContainerModel
    @ObservedObject var runtimeSettings: VideoDetailRuntimeSettingsStore
    @ObservedObject var rotationCoordinator: PlaybackRotationCoordinator
    @Binding var selectedContentTab: VideoDetailContentTab
    @Binding var sheetRoute: VideoDetailSheetRoute?
    let splitColumnOverlay: VideoDetailSplitColumnOverlayController
    let submitReply: (DynamicCommentComposerTarget, String, [DynamicCommentImage]?) async throws -> Void
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
                safeAreaBottom: model.rootSafeAreaInsets.bottom,
                safeAreaLeading: model.rootSafeAreaInsets.left,
                safeAreaTrailing: model.rootSafeAreaInsets.right,
                horizontalSizeClass: horizontalSizeClass,
                rotationCoordinator: rotationCoordinator
            )
            let isInteractiveScrollCollapseEnabled =
                layout.adaptiveMode == .compactStacked && model.isInteractiveScrollCollapseActive
            let contentHorizontalInset = runtimeSettings.adaptiveLargeScreenLayoutExperimentEnabled
                ? AdaptiveLayoutPolicy.horizontalInset(
                    for: layout.contentFrame.width,
                    horizontalSizeClass: horizontalSizeClass,
                    containerHeight: layout.contentFrame.height,
                    adaptiveEnabled: true
                )
                : dependencies.libraryStore.standardPageHorizontalInset
            let contentBounds = layout.contentFrame.size

            ZStack(alignment: .topLeading) {
                VideoDetailShellContentView(
                    viewModel: viewModel,
                    updateGate: model.contentUpdateGate,
                    runtimeSettings: runtimeSettings,
                    state: model.contentState,
                    layoutWidth: layout.contentFrame.width,
                    placesTopInsetInScrollContent: true,
                    standardHorizontalInset: contentHorizontalInset,
                    // Keep scroll extent and the experimental collapse floor consistent,
                    // without changing either when playback pauses.
                    interactiveMinimumPlayerHeight: layout.adaptiveMode == .twoColumnSplit
                        ? 0
                        : model.interactiveScrollContentMinimumPlayerHeight(forWidth: layout.contentFrame.width),
                    selectedContentTab: $selectedContentTab,
                    onShowNetworkDiagnostics: onShowNetworkDiagnostics,
                    onShowFavoriteFolders: onShowFavoriteFolders,
                    onShowCoinPicker: onShowCoinPicker,
                    onOpenCommentComposer: onOpenCommentComposer,
                    onReply: onReply,
                    openVideoOwnerRoute: openVideoOwnerRoute,
                    onSelectedTabChange: { tab in
                        if isInteractiveScrollCollapseEnabled {
                            model.prepareInteractiveTabChange(to: tab, bounds: contentBounds)
                        }
                        DispatchQueue.main.async {
                            model.handleSelectedTabChange(
                                tab,
                                bounds: contentBounds,
                                rotationCoordinator: rotationCoordinator
                            )
                        }
                    },
                    onSelectionWillChange: { tab in
                        guard isInteractiveScrollCollapseEnabled else { return }
                        model.prepareInteractiveTabChange(to: tab, bounds: contentBounds)
                    },
                    onScrollOffsetChange: { tab, offset in
                        if isInteractiveScrollCollapseEnabled {
                            model.recordInteractiveScrollOffset(
                                tab: tab,
                                offset: offset,
                                selectedTab: selectedContentTab,
                                bounds: contentBounds
                            )
                        } else if layout.adaptiveMode == .compactStacked {
                            DispatchQueue.main.async {
                                model.handleScrollOffset(
                                    tab: tab,
                                    offset: offset,
                                    selectedTab: selectedContentTab,
                                    bounds: contentBounds,
                                    rotationCoordinator: rotationCoordinator
                                )
                            }
                        }
                    },
                    onScrollPhaseChange: { tab, phase in
                        guard isInteractiveScrollCollapseEnabled else { return }
                        model.handleInteractiveScrollPhase(
                            tab: tab,
                            phase: phase,
                            selectedTab: selectedContentTab
                        )
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
                .disablingRotationTransaction(
                    rotationCoordinator.isTransitioning || layout.usesFullscreenLayout
                )

                VideoDetailInteractivePlayerLayer(
                    model: model,
                    rotationCoordinator: rotationCoordinator,
                    viewModel: viewModel,
                    size: proxy.size,
                    safeAreaTop: model.rootSafeAreaInsets.top,
                    safeAreaBottom: model.rootSafeAreaInsets.bottom,
                    safeAreaLeading: model.rootSafeAreaInsets.left,
                    safeAreaTrailing: model.rootSafeAreaInsets.right,
                    selectedContentTab: selectedContentTab,
                    dependencies: dependencies,
                    runtimeSettings: runtimeSettings,
                    onShowMoreControls: onShowMoreControls,
                    onDismissMoreControls: onDismissMoreControls,
                    onRequestFullscreen: onRequestFullscreen,
                    onExitFullscreen: onExitFullscreen,
                    onToggleDanmaku: onToggleDanmaku,
                    onShowDanmakuSettings: onShowDanmakuSettings,
                    onNavigateBack: onNavigateBack
                )

                if layout.adaptiveMode == .twoColumnSplit, !layout.usesFullscreenLayout {
                    VideoDetailSplitColumnBottomToolbar(
                        navigationHistory: model.navigationHistory,
                        onNavigateBack: onNavigateBack,
                        selection: $selectedContentTab,
                        onOpenCommentComposer: { onOpenCommentComposer(nil) }
                    )
                    .frame(width: layout.contentFrame.width)
                    .frame(
                        width: layout.contentFrame.width,
                        height: layout.contentFrame.height,
                        alignment: .bottom
                    )
                    .position(x: layout.contentFrame.midX, y: layout.contentFrame.midY)
                    .zIndex(4)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .onAppear {
                DispatchQueue.main.async {
                    model.synchronize(layout: layout)
                    model.updateCollapsedChrome(bounds: contentBounds)
                }
            }
        }
        .background(Color.black)
        .environment(\.videoDetailSplitColumnOverlay, splitColumnOverlay)
        .environment(\.navigationHistoryContext, model.navigationHistory)
        .environment(\.navigationHistoryBackAction, model.navigationHistory != nil ? onNavigateBack : nil)
        .environment(
            \.videoDetailActionButtonStyle,
            dependencies.libraryStore.videoDetailActionButtonStyle
        )
    }
}

@MainActor
private extension View {
    func disablingRotationTransaction(_ isDisabled: Bool) -> some View {
        transaction { transaction in
            if isDisabled {
                transaction.animation = nil
            }
        }
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
    private var selectedContentTab: Binding<VideoDetailContentTab>
    private var lastSelectedContentTab: VideoDetailContentTab
    private var sheetRoute: Binding<VideoDetailSheetRoute?>
    private var lastSheetRouteID: UUID?
    private let splitColumnOverlay: VideoDetailSplitColumnOverlayController
    private let submitReply: (DynamicCommentComposerTarget, String, [DynamicCommentImage]?) async throws -> Void
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
    private var onNavigateBack: () -> Void
    private let usesTransparentNavigationBar: Bool
    private let playbackDiagnostics = VideoDetailPlaybackDiagnostics()
    private var cancellables = Set<AnyCancellable>()

    #if DEBUG
        private let rotationDiagnosticsAccessibilityView = UILabel()
        private let playerFrameDiagnosticsAccessibilityView = UIView()
    #endif

    private lazy var hostingController: UIHostingController<VideoDetailSwiftUIContainer> = {
        UIHostingController(rootView: makeRootView())
    }()

    private lazy var splitSheetContainer: VideoDetailSplitColumnSheetContainerController = {
        VideoDetailSplitColumnSheetContainerController(
            overlay: splitColumnOverlay,
            viewModel: viewModel,
            dependencies: dependencies,
            submitReply: submitReply,
            onDismissCommentThreadRoute: { [weak self] in
                guard let self else { return }
                if case .commentThread = self.sheetRoute.wrappedValue {
                    self.sheetRoute.wrappedValue = nil
                }
            }
        )
    }()

    init(
        initialVideo: VideoItem,
        viewModel: VideoDetailViewModel,
        runtimeSettings: VideoDetailRuntimeSettingsStore,
        dependencies: AppDependencies,
        rotationCoordinator: PlaybackRotationCoordinator,
        openVideoOwnerRoute: ((VideoOwner) -> Void)?,
        selectedContentTab: Binding<VideoDetailContentTab>,
        sheetRoute: Binding<VideoDetailSheetRoute?> = .constant(nil),
        splitColumnOverlay: VideoDetailSplitColumnOverlayController = VideoDetailSplitColumnOverlayController(),
        submitReply: @escaping (DynamicCommentComposerTarget, String, [DynamicCommentImage]?) async throws -> Void = { _, _, _ in },
        onShowNetworkDiagnostics: @escaping () -> Void,
        onShowFavoriteFolders: @escaping () -> Void,
        onShowCoinPicker: @escaping () -> Void,
        onOpenCommentComposer: @escaping (Comment?) -> Void,
        onShowDanmakuSettings: @escaping () -> Void,
        onPresentPlayerMoreControls: @escaping (PlayerStateViewModel, @escaping () -> Void) -> Void,
        onDismissPlayerMoreControls: @escaping () -> Void,
        onReply: @escaping (Comment) -> Void,
        onToggleDanmaku: @escaping () -> Void,
        usesTransparentNavigationBar: Bool,
        onNavigateBack: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.runtimeSettings = runtimeSettings
        self.dependencies = dependencies
        self.selectedContentTab = selectedContentTab
        self.lastSelectedContentTab = selectedContentTab.wrappedValue
        self.sheetRoute = sheetRoute
        self.lastSheetRouteID = sheetRoute.wrappedValue?.id
        self.splitColumnOverlay = splitColumnOverlay
        self.submitReply = submitReply
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
        self.usesTransparentNavigationBar = usesTransparentNavigationBar
        self.rotationCoordinator = rotationCoordinator
        contentModel = VideoDetailSwiftUIContainerModel(
            viewModel: viewModel,
            initialVideo: initialVideo,
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
        addChild(splitSheetContainer)
        splitSheetContainer.view.frame = contentModel.splitContentFrame
        splitSheetContainer.view.isHidden = !contentModel.isTwoColumnSplitActive
        view.addSubview(splitSheetContainer.view)
        splitSheetContainer.didMove(toParent: self)
        splitColumnOverlay.updateStackedBelowPlayerSheetMaxHeight(
            contentModel.stackedBelowPlayerSheetMaxHeight
        )
        contentModel.onSplitContentGeometryChange = { [weak self] frame, isSplitActive, heightFraction, stackedMaxHeight in
            guard let self else { return }
            self.splitColumnOverlay.updateStackedBelowPlayerSheetMaxHeight(stackedMaxHeight)
            self.splitSheetContainer.updateGeometry(
                frame: frame,
                isSplitActive: isSplitActive,
                sheetHeightFraction: heightFraction
            )
        }
        syncSplitSheetCommentThread()
        #if DEBUG
            rotationDiagnosticsAccessibilityView.isAccessibilityElement = true
            rotationDiagnosticsAccessibilityView.accessibilityIdentifier = "ui.videoDetail.rotationDiagnostics"
            rotationDiagnosticsAccessibilityView.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
            rotationDiagnosticsAccessibilityView.alpha = 0.01
            view.addSubview(rotationDiagnosticsAccessibilityView)
            playerFrameDiagnosticsAccessibilityView.isAccessibilityElement = true
            playerFrameDiagnosticsAccessibilityView.accessibilityIdentifier = "ui.videoDetail.playerFrame"
            playerFrameDiagnosticsAccessibilityView.isUserInteractionEnabled = false
            playerFrameDiagnosticsAccessibilityView.alpha = 0.01
            view.addSubview(playerFrameDiagnosticsAccessibilityView)
            contentModel.playerFrameUpdates
                .receive(on: RunLoop.main)
                .sink { [weak self] frame in
                    guard let self else { return }
                    self.playerFrameDiagnosticsAccessibilityView.frame = frame
                    self.playerFrameDiagnosticsAccessibilityView.accessibilityValue = "height=\(frame.height)"
                }
                .store(in: &cancellables)
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
        scheduleRootSafeAreaInsetsSyncIfNeeded()
    }

    private func scheduleRootSafeAreaInsetsSyncIfNeeded() {
        let insets = playerSafeAreaInsets
        let isPortraitContainer = isPortraitContainerBounds
        guard shouldConsiderSafeAreaInsetsUpdate(
            insets,
            isPortraitContainer: isPortraitContainer
        ) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.playerSafeAreaInsets == insets
            else { return }
            self.contentModel.applySafeAreaInsetsIfAppropriate(
                insets,
                isPortraitContainer: self.isPortraitContainerBounds
            )
        }
    }

    private func syncRootSafeAreaInsetsImmediatelyIfNeeded() {
        guard view.window != nil,
              !rotationCoordinator.layoutLandscape,
              !rotationCoordinator.isPortraitFullscreen,
              !rotationCoordinator.isTransitioning,
              isPortraitContainerBounds
        else {
            view.setNeedsLayout()
            return
        }
        view.setNeedsLayout()
        view.layoutIfNeeded()
        contentModel.applySafeAreaInsetsIfAppropriate(
            playerSafeAreaInsets,
            isPortraitContainer: isPortraitContainerBounds
        )
    }

    private var isPortraitContainerBounds: Bool {
        guard view.bounds.width > 0 else { return false }
        if view.bounds.height >= view.bounds.width {
            return true
        }
        return AdaptiveLayoutPolicy.treatsLandscapeRotationAsSplitDetail(
            containerSize: view.bounds.size,
            traitCollection: traitCollection,
            adaptiveEnabled: runtimeSettings.adaptiveLargeScreenLayoutExperimentEnabled
        )
    }

    private func shouldConsiderSafeAreaInsetsUpdate(
        _ insets: UIEdgeInsets,
        isPortraitContainer: Bool
    ) -> Bool {
        guard contentModel.canApplySafeAreaInsets(insets, isPortraitContainer: isPortraitContainer) else {
            return false
        }
        return contentModel.rootSafeAreaInsets != insets
            || contentModel.contentState.bottomInset != insets.bottom
    }

    private var playerSafeAreaInsets: UIEdgeInsets {
        view.playbackSafeAreaInsets(underTransparentNavigationBar: usesTransparentNavigationBar)
    }

    var activePlayerViewModel: PlayerStateViewModel? {
        contentModel.activePlayerViewModel
    }

    var playerFrame: CGRect {
        contentModel.playerFrame
    }

    var isPortraitVideo: Bool {
        contentModel.videoAspectRatio < 0.9
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
        syncRootSafeAreaInsetsImmediatelyIfNeeded()
    }

    func recoverStableLayout() {
        contentModel.recoverStableLayout()
        syncRootSafeAreaInsetsImmediatelyIfNeeded()
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

    func updateNavigateBackAction(_ action: @escaping () -> Void) {
        onNavigateBack = action
    }

    var hasActiveSplitColumnOverlay: Bool {
        splitSheetContainer.hasVisibleOverlay || splitColumnOverlay.hasActiveOverlay
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

    func markSystemTransitionEnded() {
        playbackDiagnostics.markSystemTransitionEnded()
    }

    func markRotationFinished(toLandscape: Bool, actualOrientation: String?) {
        playbackDiagnostics.markRotationFinished(
            toLandscape: toLandscape,
            actualOrientation: actualOrientation
        )
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

    func updateSelectedContentTab(_ binding: Binding<VideoDetailContentTab>) {
        let selection = binding.wrappedValue
        selectedContentTab = binding
        guard selection != lastSelectedContentTab else { return }
        lastSelectedContentTab = selection
        // The outer toolbar belongs to a different SwiftUI root. Refresh the
        // retained host with its current binding when that toolbar changes tabs.
        // This preserves the hosting controller, model and player identities.
        hostingController.rootView = makeRootView()
    }

    func updateSheetRoute(_ binding: Binding<VideoDetailSheetRoute?>) {
        let nextID = binding.wrappedValue?.id
        sheetRoute = binding
        guard nextID != lastSheetRouteID else { return }
        lastSheetRouteID = nextID
        syncSplitSheetCommentThread()
    }

    private func syncSplitSheetCommentThread() {
        if case .commentThread(let presentation) = sheetRoute.wrappedValue {
            splitSheetContainer.updateCommentThreadPresentation(presentation)
        } else {
            splitSheetContainer.updateCommentThreadPresentation(nil)
        }
    }

    private func makeRootView() -> VideoDetailSwiftUIContainer {
        VideoDetailSwiftUIContainer(
            viewModel: viewModel,
            model: contentModel,
            runtimeSettings: runtimeSettings,
            rotationCoordinator: rotationCoordinator,
            selectedContentTab: selectedContentTab,
            sheetRoute: sheetRoute,
            splitColumnOverlay: splitColumnOverlay,
            submitReply: submitReply,
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
