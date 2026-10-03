import Combine
import SwiftUI
import UIKit

struct DanmakuOverlayView: UIViewRepresentable {
    fileprivate struct ConfigurationSignature: Equatable {
        let itemsRevision: Int
        let metalRendererEnabled: Bool
        let currentTimeBucket: Int?
        let isPlaying: Bool
        let playbackRateTenths: Int
        let isEnabled: Bool
        let hasPresentedPlayback: Bool
        let isLoadShedding: Bool
        let settings: DanmakuSettings
        let topInsetTenths: Int
        let bottomInsetTenths: Int

        init(
            itemsRevision: Int,
            metalRendererEnabled: Bool,
            currentTime: TimeInterval,
            usesExternalClock: Bool,
            isPlaying: Bool,
            playbackRate: Double,
            isEnabled: Bool,
            hasPresentedPlayback: Bool,
            isLoadShedding: Bool,
            settings: DanmakuSettings,
            topInset: CGFloat,
            bottomInset: CGFloat
        ) {
            self.itemsRevision = itemsRevision
            self.metalRendererEnabled = metalRendererEnabled
            // When a PlayerPlaybackClock is bound, UIKit receives time ticks directly.
            // Without one, keep a coarse time bucket so live-style callers can resync.
            currentTimeBucket = usesExternalClock ? nil : Int(max(0, currentTime) * 2)
            self.isPlaying = isPlaying
            playbackRateTenths = Int((max(playbackRate, 0.1) * 10).rounded())
            self.isEnabled = isEnabled
            self.hasPresentedPlayback = hasPresentedPlayback
            self.isLoadShedding = isLoadShedding
            self.settings = settings.normalized
            topInsetTenths = Int((max(0, topInset) * 10).rounded())
            bottomInsetTenths = Int((max(0, bottomInset) * 10).rounded())
        }
    }

    let metalRendererEnabled: Bool
    let items: [DanmakuItem]
    let itemsRevision: Int
    let currentTime: TimeInterval
    let isPlaying: Bool
    let playbackRate: Double
    let isEnabled: Bool
    let hasPresentedPlayback: Bool
    let isLoadShedding: Bool
    let settings: DanmakuSettings
    let topInset: CGFloat
    let bottomInset: CGFloat
    let isLayoutTransitioning: Bool
    let playbackClock: PlayerPlaybackClock?
    let onPlaybackTime: ((TimeInterval, Bool) -> Void)?

    init(
        items: [DanmakuItem],
        itemsRevision: Int,
        currentTime: TimeInterval = 0,
        isPlaying: Bool,
        playbackRate: Double,
        isEnabled: Bool,
        hasPresentedPlayback: Bool,
        isLoadShedding: Bool = false,
        settings: DanmakuSettings,
        topInset: CGFloat,
        bottomInset: CGFloat,
        isLayoutTransitioning: Bool = false,
        playbackClock: PlayerPlaybackClock? = nil,
        onPlaybackTime: ((TimeInterval, Bool) -> Void)? = nil,
        metalRendererEnabled: Bool = false
    ) {
        self.metalRendererEnabled = metalRendererEnabled
        self.items = items
        self.itemsRevision = itemsRevision
        self.currentTime = currentTime
        self.isPlaying = isPlaying
        self.playbackRate = playbackRate
        self.isEnabled = isEnabled
        self.hasPresentedPlayback = hasPresentedPlayback
        self.isLoadShedding = isLoadShedding
        self.settings = settings
        self.topInset = topInset
        self.bottomInset = bottomInset
        self.isLayoutTransitioning = isLayoutTransitioning
        self.playbackClock = playbackClock
        self.onPlaybackTime = onPlaybackTime
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> DanmakuRendererHostView {
        let view = DanmakuRendererHostView(frame: .zero)
        view.selectRenderer(metalEnabled: metalRendererEnabled)
        view.setLayoutTransitioning(isLayoutTransitioning)
        let resolvedCurrentTime = playbackClock?.currentTime ?? currentTime
        let signature = configurationSignature(resolvedCurrentTime: resolvedCurrentTime)
        view.apply(configuration: DanmakuOverlayConfiguration(
            items: items,
            itemsRevision: itemsRevision,
            currentTime: resolvedCurrentTime,
            isPlaying: isPlaying,
            playbackRate: playbackRate,
            isEnabled: isEnabled,
            hasPresentedPlayback: hasPresentedPlayback,
            isLoadShedding: isLoadShedding,
            settings: settings,
            topInset: topInset,
            bottomInset: bottomInset
        ))
        context.coordinator.markApplied(signature)
        context.coordinator.bind(clock: playbackClock, uiView: view, onPlaybackTime: onPlaybackTime)
        return view
    }

    func updateUIView(_ uiView: DanmakuRendererHostView, context: Context) {
        uiView.selectRenderer(metalEnabled: metalRendererEnabled)
        if isLayoutTransitioning {
            uiView.setLayoutTransitioning(true)
        }
        let resolvedCurrentTime = playbackClock?.currentTime ?? currentTime
        let signature = configurationSignature(resolvedCurrentTime: resolvedCurrentTime)
        if context.coordinator.shouldApply(signature) {
            uiView.apply(configuration: DanmakuOverlayConfiguration(
                items: items,
                itemsRevision: itemsRevision,
                currentTime: resolvedCurrentTime,
                isPlaying: isPlaying,
                playbackRate: playbackRate,
                isEnabled: isEnabled,
                hasPresentedPlayback: hasPresentedPlayback,
                isLoadShedding: isLoadShedding,
                settings: settings,
                topInset: topInset,
                bottomInset: bottomInset
            ))
            context.coordinator.markApplied(signature)
        }
        if !isLayoutTransitioning {
            uiView.setLayoutTransitioning(false)
        }
        context.coordinator.bind(clock: playbackClock, uiView: uiView, onPlaybackTime: onPlaybackTime)
    }

    private func configurationSignature(resolvedCurrentTime: TimeInterval) -> ConfigurationSignature {
        ConfigurationSignature(
            itemsRevision: itemsRevision,
            metalRendererEnabled: metalRendererEnabled,
            currentTime: resolvedCurrentTime,
            usesExternalClock: playbackClock != nil,
            isPlaying: isPlaying,
            playbackRate: playbackRate,
            isEnabled: isEnabled,
            hasPresentedPlayback: hasPresentedPlayback,
            isLoadShedding: isLoadShedding,
            settings: settings,
            topInset: topInset,
            bottomInset: bottomInset
        )
    }

    static func dismantleUIView(_ uiView: DanmakuRendererHostView, coordinator: Coordinator) {
        coordinator.unbind()
        uiView.stop()
    }

    @MainActor
    final class Coordinator {
        private weak var boundClock: PlayerPlaybackClock?
        private var clockCancellable: AnyCancellable?
        private var onPlaybackTime: ((TimeInterval, Bool) -> Void)?
        private var lastReportedPlaybackSecond: Int?
        private var isLoadShedding = false
        private var lastAppliedSignature: ConfigurationSignature?

        fileprivate func shouldApply(_ signature: ConfigurationSignature) -> Bool {
            lastAppliedSignature != signature
        }

        fileprivate func markApplied(_ signature: ConfigurationSignature) {
            lastAppliedSignature = signature
        }

        func bind(
            clock: PlayerPlaybackClock?,
            uiView: DanmakuRendererHostView,
            onPlaybackTime: ((TimeInterval, Bool) -> Void)?
        ) {
            self.onPlaybackTime = onPlaybackTime
            self.isLoadShedding = uiView.isLoadSheddingValue
            guard boundClock !== clock else { return }

            clockCancellable?.cancel()
            boundClock = clock

            guard let clock else { return }
            uiView.synchronizePlaybackTime(clock.currentTime, force: true)
            reportPlaybackTime(clock.currentTime, force: true)
            clockCancellable = clock.$currentTime
                .removeDuplicates { abs($0 - $1) < 0.05 }
                .sink { [weak self, weak uiView] time in
                    uiView?.synchronizePlaybackTime(time)
                    self?.reportPlaybackTime(time)
                }
        }

        func unbind() {
            clockCancellable?.cancel()
            clockCancellable = nil
            boundClock = nil
            lastReportedPlaybackSecond = nil
            lastAppliedSignature = nil
            onPlaybackTime = nil
        }

        private func reportPlaybackTime(_ playbackTime: TimeInterval, force: Bool = false) {
            guard let onPlaybackTime else { return }
            let sanitizedTime = max(0, playbackTime)
            let secondBucket = Int(sanitizedTime.rounded(.down))
            guard force || lastReportedPlaybackSecond != secondBucket else { return }
            lastReportedPlaybackSecond = secondBucket
            onPlaybackTime(sanitizedTime, isLoadShedding)
        }
    }
}
