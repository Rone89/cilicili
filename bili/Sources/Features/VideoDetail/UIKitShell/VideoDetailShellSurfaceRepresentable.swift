import Combine
import SwiftUI
import UIKit

/// 把详情页播放器 surface 宿主接入 SwiftUI。
///
/// SwiftUI 只更新输入值，`UIViewRepresentable` 的 UIKit view identity 在整个
/// 详情页生命周期内保持不变。清晰度切换只原位换绑新的 PlayerStateViewModel。
@MainActor
struct VideoDetailShellSurfaceRepresentable: UIViewRepresentable {
    let playerViewModel: PlayerStateViewModel
    let detailViewModel: VideoDetailViewModel
    let dependencies: AppDependencies
    let runtimeSettings: VideoDetailRuntimeSettingsStore
    let rotationCoordinator: PlaybackRotationCoordinator
    let videoAspectRatio: CGFloat
    let danmakuCanvasSize: CGSize?
    let isBareSurfaceTransitionActive: Bool
    let retainsChromeDuringBareSurfaceTransition: Bool
    let isCollapsedChromeActive: Bool
    let onShowMoreControls: (@escaping () -> Void) -> Void
    let onDismissMoreControls: () -> Void
    let onRequestFullscreen: () -> Void
    let onExitFullscreen: () -> Void
    let onToggleDanmaku: () -> Void
    let onShowDanmakuSettings: () -> Void
    let onNavigateBack: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> VideoDetailShellSurfaceHost {
        let host = makeHost()
        host.setDanmakuCanvasSize(danmakuCanvasSize)
        context.coordinator.configure(host: host, playerViewModel: playerViewModel)
        context.coordinator.attachIfPossible(to: host)
        return host
    }

    func updateUIView(
        _ uiView: VideoDetailShellSurfaceHost,
        context: Context
    ) {
        let coordinator = context.coordinator
        coordinator.configure(host: uiView, playerViewModel: playerViewModel)
        guard !uiView.isTornDown else { return }
        coordinator.scheduleConfigurationIfNeeded(
            playerViewModel: playerViewModel,
            videoAspectRatio: videoAspectRatio,
            danmakuCanvasSize: danmakuCanvasSize,
            isCollapsedChromeActive: isCollapsedChromeActive,
            isBareSurfaceTransitionActive: isBareSurfaceTransitionActive,
            retainsChromeDuringBareSurfaceTransition: retainsChromeDuringBareSurfaceTransition
        )
        coordinator.attachIfPossible(to: uiView)
    }

    static func dismantleUIView(
        _ uiView: VideoDetailShellSurfaceHost,
        coordinator: Coordinator
    ) {
        coordinator.dismantle()
        uiView.tearDown()
    }

    private func makeHost() -> VideoDetailShellSurfaceHost {
        VideoDetailShellSurfaceHost(
            playerViewModel: playerViewModel,
            detailViewModel: detailViewModel,
            dependencies: dependencies,
            runtimeSettings: runtimeSettings,
            rotationCoordinator: rotationCoordinator,
            onShowMoreControls: onShowMoreControls,
            onDismissMoreControls: onDismissMoreControls,
            onRequestFullscreen: onRequestFullscreen,
            onExitFullscreen: onExitFullscreen,
            onToggleDanmaku: onToggleDanmaku,
            onShowDanmakuSettings: onShowDanmakuSettings,
            onNavigateBack: onNavigateBack
        )
    }

    @MainActor
    final class Coordinator {
        private weak var host: VideoDetailShellSurfaceHost?
        private weak var observedPlayer: PlayerStateViewModel?
        private weak var configuredPlayer: PlayerStateViewModel?
        private var configuredAspectRatio: CGFloat?
        private var configuredDanmakuCanvasSize: CGSize?
        private var configuredCollapsedChrome: Bool?
        private var configuredBareSurface: Bool?
        private var configuredRetainsChrome: Bool?
        private var playerCancellable: AnyCancellable?
        private var attachmentRetry: Task<Void, Never>?
        private var prewarmWorkItem: DispatchWorkItem?
        private var prewarmGeneration = 0
        private var isAttached = false
        private var isPrewarmScheduled = false
        private var isConfigurationUpdateScheduled = false

        func configure(
            host: VideoDetailShellSurfaceHost,
            playerViewModel: PlayerStateViewModel
        ) {
            let hostChanged = self.host !== host
            if hostChanged {
                isAttached = false
                cancelScheduledPrewarm()
                isPrewarmScheduled = false
            }
            self.host = host
            guard observedPlayer !== playerViewModel else {
                if hostChanged, playerViewModel.hasPresentedPlayback {
                    schedulePrewarm(for: playerViewModel, on: host)
                }
                return
            }
            cancelScheduledPrewarm()
            playerCancellable = nil
            observedPlayer = playerViewModel
            isPrewarmScheduled = false
            playerCancellable = playerViewModel.$hasPresentedPlayback
                .removeDuplicates()
                .filter { $0 }
                .prefix(1)
                .sink { [weak self] _ in
                    guard let self, let host = self.host else { return }
                    self.schedulePrewarm(for: playerViewModel, on: host)
                }
        }

        func scheduleConfigurationIfNeeded(
            playerViewModel: PlayerStateViewModel,
            videoAspectRatio: CGFloat,
            danmakuCanvasSize: CGSize?,
            isCollapsedChromeActive: Bool,
            isBareSurfaceTransitionActive: Bool,
            retainsChromeDuringBareSurfaceTransition: Bool
        ) {
            if let host, host.usesDirectUIKitSurfaceExperiment {
                if isBareSurfaceTransitionActive,
                   isPrewarmScheduled,
                   !host.isRotationChromePrewarmed {
                    cancelScheduledPrewarm()
                    // The current rotation will lay out the retained chrome. Do not
                    // let a delayed prewarm run inside the system transition.
                    isPrewarmScheduled = false
                } else if !isBareSurfaceTransitionActive,
                          !isPrewarmScheduled,
                          !host.isRotationChromePrewarmed,
                          playerViewModel.hasPresentedPlayback {
                    // If a rotation canceled the initial prewarm, schedule it again
                    // once the direct-surface host has left its transition state.
                    schedulePrewarm(for: playerViewModel, on: host)
                }
            }
            let changed = configuredPlayer !== playerViewModel
                || configuredAspectRatio != videoAspectRatio
                || configuredDanmakuCanvasSize != danmakuCanvasSize
                || configuredCollapsedChrome != isCollapsedChromeActive
                || configuredBareSurface != isBareSurfaceTransitionActive
                || configuredRetainsChrome != retainsChromeDuringBareSurfaceTransition
            guard changed else { return }

            configuredPlayer = playerViewModel
            configuredAspectRatio = videoAspectRatio
            configuredDanmakuCanvasSize = danmakuCanvasSize
            configuredCollapsedChrome = isCollapsedChromeActive
            configuredBareSurface = isBareSurfaceTransitionActive
            configuredRetainsChrome = retainsChromeDuringBareSurfaceTransition
            guard !isConfigurationUpdateScheduled else { return }

            isConfigurationUpdateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let host = self.host,
                      let playerViewModel = self.configuredPlayer,
                      !host.isTornDown
                else {
                    self?.isConfigurationUpdateScheduled = false
                    return
                }

                host.setPlayerViewModel(playerViewModel)
                host.setDanmakuCanvasSize(self.configuredDanmakuCanvasSize)
                if let videoAspectRatio = self.configuredAspectRatio {
                    host.setVideoAspectRatio(videoAspectRatio)
                }
                if let isCollapsedChromeActive = self.configuredCollapsedChrome {
                    host.setCollapsedChromeActive(isCollapsedChromeActive)
                }
                if let isBareSurfaceTransitionActive = self.configuredBareSurface {
                    host.setBareSurfaceTransitionActive(
                        isBareSurfaceTransitionActive,
                        retainsChromeTree: self.configuredRetainsChrome ?? false
                    )
                    if isBareSurfaceTransitionActive {
                        host.cancelRotationChromePrewarm()
                    }
                }
                self.isConfigurationUpdateScheduled = false
            }
        }

        func attachIfPossible(to host: VideoDetailShellSurfaceHost) {
            guard !isAttached else { return }
            guard let parent = nearestViewController(from: host) else {
                scheduleAttachmentRetry(for: host)
                return
            }
            cancelAttachmentRetry()
            host.attach(to: parent)
            isAttached = true
        }

        func cancelAttachmentRetry() {
            attachmentRetry?.cancel()
            attachmentRetry = nil
        }

        func dismantle() {
            cancelAttachmentRetry()
            cancelScheduledPrewarm()
            playerCancellable = nil
            observedPlayer = nil
            configuredPlayer = nil
            configuredAspectRatio = nil
            configuredDanmakuCanvasSize = nil
            configuredCollapsedChrome = nil
            configuredBareSurface = nil
            configuredRetainsChrome = nil
            isConfigurationUpdateScheduled = false
            host = nil
            isAttached = false
        }

        private func schedulePrewarm(
            for playerViewModel: PlayerStateViewModel,
            on host: VideoDetailShellSurfaceHost
        ) {
            guard !isPrewarmScheduled else { return }
            isPrewarmScheduled = true
            prewarmGeneration &+= 1
            let generation = prewarmGeneration
            let workItem = DispatchWorkItem { [weak self, weak host, weak playerViewModel] in
                guard let self,
                      let host,
                      let playerViewModel,
                      self.prewarmGeneration == generation,
                      self.host === host,
                      self.observedPlayer === playerViewModel
                else { return }
                self.prewarmWorkItem = nil
                host.prewarmRotationChrome()
            }
            prewarmWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
        }

        private func cancelScheduledPrewarm() {
            prewarmGeneration &+= 1
            prewarmWorkItem?.cancel()
            prewarmWorkItem = nil
        }

        private func scheduleAttachmentRetry(for host: VideoDetailShellSurfaceHost) {
            guard attachmentRetry == nil else { return }
            attachmentRetry = Task { @MainActor [weak self, weak host] in
                for _ in 0..<8 {
                    guard !Task.isCancelled else { return }
                    try? await Task.sleep(for: .milliseconds(16))
                    guard let self, let host, !Task.isCancelled else { return }
                    if self.nearestViewController(from: host) != nil {
                        self.attachmentRetry = nil
                        self.attachIfPossible(to: host)
                        return
                    }
                }
                self?.attachmentRetry = nil
            }
        }

        private func nearestViewController(from view: UIView) -> UIViewController? {
            var responder: UIResponder? = view
            while let current = responder {
                if let viewController = current as? UIViewController {
                    return viewController
                }
                responder = current.next
            }
            return nil
        }
    }
}
