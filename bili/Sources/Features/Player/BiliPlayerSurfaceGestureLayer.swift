import SwiftUI
import UIKit

struct BiliPlayerSurfaceGestureLayer<Content: View>: View {
    let content: Content
    let clock: PlayerPlaybackClock
    let durationHint: TimeInterval?
    let canSeek: Bool
    let allowsDoubleTapPlaybackToggle: Bool
    let onSingleTap: () -> Void
    let onDoubleTap: () -> Void
    let onBeginSpeedBoost: () -> Bool
    let onEndSpeedBoost: (PlayerSpeedBoostEndReason) -> Void
    let onHorizontalSeekStart: (Double) -> Void
    let onHorizontalSeekChanged: (Double, CGFloat) -> Void
    let onHorizontalSeekEnded: (Double) -> Void
    let onHorizontalSeekCancelled: () -> Void
    let onHorizontalSeekCancelPendingChanged: (Bool) -> Void

    @StateObject private var systemControlsController = PlayerSystemControlsController()
    @State private var verticalAdjustmentTarget: PlayerSurfaceVerticalAdjustmentTarget?
    @State private var verticalAdjustmentValue: Float?
    @State private var isVerticalAdjusting = false
    @State private var hardwareVolumeIndicatorValue: Float?
    @State private var hardwareVolumeIndicatorDismissTask: Task<Void, Never>?
    @State private var lastGestureRequestedVolume: Float?

    var body: some View {
        ZStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            PlayerSystemControlsHost(controller: systemControlsController)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            BiliPlayerUIKitSurfaceGestureOverlay(
                clock: clock,
                durationHint: durationHint,
                canSeek: canSeek,
                allowsDoubleTapPlaybackToggle: allowsDoubleTapPlaybackToggle,
                onSingleTap: onSingleTap,
                onDoubleTap: onDoubleTap,
                onBeginSpeedBoost: onBeginSpeedBoost,
                onEndSpeedBoost: onEndSpeedBoost,
                onHorizontalSeekStart: onHorizontalSeekStart,
                onHorizontalSeekChanged: onHorizontalSeekChanged,
                onHorizontalSeekEnded: onHorizontalSeekEnded,
                onHorizontalSeekCancelled: onHorizontalSeekCancelled,
                onHorizontalSeekCancelPendingChanged: onHorizontalSeekCancelPendingChanged,
                systemValueProvider: { target in
                    systemValue(for: target)
                },
                onVerticalAdjustmentBegan: { target, value in
                    isVerticalAdjusting = true
                    dismissHardwareVolumeIndicator()
                    verticalAdjustmentTarget = target
                    verticalAdjustmentValue = value
                },
                onVerticalAdjustmentChanged: { target, value in
                    verticalAdjustmentTarget = target
                    verticalAdjustmentValue = value
                    applySystemValue(value, for: target)
                },
                onVerticalAdjustmentEnded: {
                    isVerticalAdjusting = false
                    verticalAdjustmentTarget = nil
                    verticalAdjustmentValue = nil
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)

            if isVerticalAdjusting,
               let verticalAdjustmentTarget,
               let verticalAdjustmentValue {
                PlayerSurfaceVerticalAdjustmentIndicator(
                    target: verticalAdjustmentTarget,
                    value: verticalAdjustmentValue
                )
                .allowsHitTesting(false)
            } else if let hardwareVolumeIndicatorValue {
                PlayerSurfaceVerticalAdjustmentIndicator(
                    target: .volume,
                    value: hardwareVolumeIndicatorValue
                )
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onChange(of: systemControlsController.outputVolume) { previousValue, currentValue in
            handleOutputVolumeChange(previousValue: previousValue, currentValue: currentValue)
        }
        .onDisappear {
            dismissHardwareVolumeIndicator()
        }
        .accessibilityElement()
        .accessibilityLabel("播放器画面")
        .accessibilityIdentifier("ui.player.surface")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            onSingleTap()
        }
    }

    private func systemValue(for target: PlayerSurfaceVerticalAdjustmentTarget) -> Float? {
        switch target {
        case .brightness:
            return systemControlsController.displayBrightness
        case .volume:
            return systemControlsController.outputVolume
        }
    }

    private func applySystemValue(_ value: Float, for target: PlayerSurfaceVerticalAdjustmentTarget) {
        switch target {
        case .brightness:
            systemControlsController.setDisplayBrightness(value)
        case .volume:
            lastGestureRequestedVolume = value
            systemControlsController.setOutputVolume(value)
        }
    }

    private func handleOutputVolumeChange(previousValue: Float, currentValue: Float) {
        if isVerticalAdjusting {
            return
        }
        if let lastGestureRequestedVolume,
           abs(lastGestureRequestedVolume - currentValue) <= 0.0001 {
            self.lastGestureRequestedVolume = nil
            return
        }
        lastGestureRequestedVolume = nil
        guard PlayerSurfaceVerticalAdjustmentPolicy.shouldPresentHardwareVolumeIndicator(
            previousValue: previousValue,
            currentValue: currentValue,
            isVerticalAdjusting: isVerticalAdjusting
        ) else { return }

        hardwareVolumeIndicatorDismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.14)) {
            hardwareVolumeIndicatorValue = currentValue
        }
        hardwareVolumeIndicatorDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.16)) {
                hardwareVolumeIndicatorValue = nil
            }
        }
    }

    private func dismissHardwareVolumeIndicator() {
        hardwareVolumeIndicatorDismissTask?.cancel()
        hardwareVolumeIndicatorDismissTask = nil
        hardwareVolumeIndicatorValue = nil
    }
}

private struct BiliPlayerUIKitSurfaceGestureOverlay: UIViewRepresentable {
    let clock: PlayerPlaybackClock
    let durationHint: TimeInterval?
    let canSeek: Bool
    let allowsDoubleTapPlaybackToggle: Bool
    let onSingleTap: () -> Void
    let onDoubleTap: () -> Void
    let onBeginSpeedBoost: () -> Bool
    let onEndSpeedBoost: (PlayerSpeedBoostEndReason) -> Void
    let onHorizontalSeekStart: (Double) -> Void
    let onHorizontalSeekChanged: (Double, CGFloat) -> Void
    let onHorizontalSeekEnded: (Double) -> Void
    let onHorizontalSeekCancelled: () -> Void
    let onHorizontalSeekCancelPendingChanged: (Bool) -> Void
    let systemValueProvider: (PlayerSurfaceVerticalAdjustmentTarget) -> Float?
    let onVerticalAdjustmentBegan: (PlayerSurfaceVerticalAdjustmentTarget, Float) -> Void
    let onVerticalAdjustmentChanged: (PlayerSurfaceVerticalAdjustmentTarget, Float) -> Void
    let onVerticalAdjustmentEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isOpaque = false
        context.coordinator.install(on: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.update(parent: self, on: uiView)
    }

    static func dismantleUIView(_: UIView, coordinator: Coordinator) {
        coordinator.cancelActiveInteractions(speedBoostReason: .disappear)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private enum PanMode {
            case undecided
            case ignored
            case seeking(duration: TimeInterval)
            case adjusting(target: PlayerSurfaceVerticalAdjustmentTarget, initialValue: Float)
        }

        private var parent: BiliPlayerUIKitSurfaceGestureOverlay
        private lazy var singleTapGesture = UITapGestureRecognizer(
            target: self,
            action: #selector(handleSingleTap(_:))
        )
        private lazy var doubleTapGesture = UITapGestureRecognizer(
            target: self,
            action: #selector(handleDoubleTap(_:))
        )
        private lazy var panGesture = UIPanGestureRecognizer(
            target: self,
            action: #selector(handlePan(_:))
        )
        private lazy var longPressGesture = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleLongPress(_:))
        )

        private var panMode: PanMode = .undecided
        private var panStartLocation: CGPoint = .zero
        private var lastHorizontalTranslationX: CGFloat = 0
        private var currentSeekProgress: Double?
        private var isHorizontalSeekCancelPending = false
        private var isSpeedBoostActive = false

        init(parent: BiliPlayerUIKitSurfaceGestureOverlay) {
            self.parent = parent
            super.init()
        }

        func install(on view: UIView) {
            singleTapGesture.numberOfTapsRequired = 1
            singleTapGesture.cancelsTouchesInView = false
            singleTapGesture.delaysTouchesBegan = false
            singleTapGesture.delegate = self

            doubleTapGesture.numberOfTapsRequired = 2
            doubleTapGesture.cancelsTouchesInView = false
            doubleTapGesture.delaysTouchesBegan = false
            doubleTapGesture.delegate = self

            panGesture.maximumNumberOfTouches = 1
            panGesture.cancelsTouchesInView = true
            panGesture.delaysTouchesBegan = false
            panGesture.delaysTouchesEnded = false
            panGesture.delegate = self

            longPressGesture.minimumPressDuration = 0.28
            longPressGesture.allowableMovement = 24
            longPressGesture.cancelsTouchesInView = true
            longPressGesture.delaysTouchesBegan = false
            longPressGesture.delaysTouchesEnded = true
            longPressGesture.delegate = self

            view.addGestureRecognizer(singleTapGesture)
            view.addGestureRecognizer(doubleTapGesture)
            view.addGestureRecognizer(panGesture)
            view.addGestureRecognizer(longPressGesture)
            syncDoubleTapRequirement()
        }

        func update(parent: BiliPlayerUIKitSurfaceGestureOverlay, on _: UIView) {
            self.parent = parent
            syncDoubleTapRequirement()
        }

        private func syncDoubleTapRequirement() {
            doubleTapGesture.isEnabled = parent.allowsDoubleTapPlaybackToggle
            if parent.allowsDoubleTapPlaybackToggle {
                singleTapGesture.require(toFail: doubleTapGesture)
            }
        }

        func cancelActiveInteractions(speedBoostReason: PlayerSpeedBoostEndReason) {
            if case .seeking = panMode {
                parent.onHorizontalSeekCancelled()
                parent.clock.clearSeekPreview()
            } else if case .adjusting = panMode {
                parent.onVerticalAdjustmentEnded()
            }
            resetPanState()
            if isSpeedBoostActive {
                isSpeedBoostActive = false
                parent.onEndSpeedBoost(speedBoostReason)
            }
        }

        @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, !isSpeedBoostActive else { return }
            parent.onSingleTap()
        }

        @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended,
                  let view = gesture.view,
                  !isSpeedBoostActive
            else { return }
            let location = gesture.location(in: view)
            if PlayerDoubleTapGesturePolicy.shouldTogglePlayback(
                locationX: location.x,
                width: view.bounds.width
            ) {
                parent.onDoubleTap()
            } else {
                parent.onSingleTap()
            }
        }

        @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began:
                guard !isSpeedBoostActive, !isPanInteractionActive else { return }
                let didBegin = parent.onBeginSpeedBoost()
                isSpeedBoostActive = didBegin
                if didBegin, case .undecided = panMode {
                    panMode = .ignored
                }
            case .ended:
                guard isSpeedBoostActive else { return }
                isSpeedBoostActive = false
                parent.onEndSpeedBoost(.gestureEnded)
            case .cancelled, .failed:
                guard isSpeedBoostActive else { return }
                isSpeedBoostActive = false
                parent.onEndSpeedBoost(.systemInterrupted)
            default:
                break
            }
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            switch gesture.state {
            case .began:
                panStartLocation = gesture.location(in: view)
                lastHorizontalTranslationX = 0
                currentSeekProgress = nil
                isHorizontalSeekCancelPending = false
                panMode = isSpeedBoostActive ? .ignored : .undecided
            case .changed:
                guard !isSpeedBoostActive else { return }
                let translation = gesture.translation(in: view)
                let location = gesture.location(in: view)
                let velocity = gesture.velocity(in: view)
                let size = view.bounds.size
                if case .undecided = panMode {
                    beginPanIfNeeded(
                        translation: translation,
                        location: location,
                        size: size
                    )
                }
                updatePan(
                    translation: translation,
                    location: location,
                    velocity: velocity,
                    size: size
                )
            case .ended:
                finishPan(
                    commitsSeek: !isSpeedBoostActive,
                    gesture: gesture,
                    in: view
                )
            case .cancelled, .failed:
                finishPan(commitsSeek: false, gesture: gesture, in: view)
            default:
                break
            }
        }

        private var isPanInteractionActive: Bool {
            switch panMode {
            case .seeking, .adjusting:
                return true
            case .undecided, .ignored:
                return false
            }
        }

        private func beginPanIfNeeded(
            translation: CGPoint,
            location: CGPoint,
            size: CGSize
        ) {
            guard let axis = PlayerSurfaceGestureAxisPolicy.axis(
                translation: CGSize(width: translation.x, height: translation.y),
                activationDistance: 8,
                dominanceRatio: 2.0
            ) else { return }

            switch axis {
            case .horizontal:
                guard parent.canSeek,
                      let duration = parent.clock.duration ?? parent.durationHint,
                      duration > 0,
                      size.width > 0
                else {
                    panMode = .ignored
                    return
                }
                let startProgress = min(max(parent.clock.progress, 0), 1)
                panMode = .seeking(duration: duration)
                lastHorizontalTranslationX = 0
                currentSeekProgress = startProgress
                isHorizontalSeekCancelPending = Self.horizontalSeekShouldCancel(
                    at: location,
                    size: size
                )
                parent.clock.updateSeekPreview(progress: startProgress, force: true)
                parent.onHorizontalSeekStart(startProgress)
                parent.onHorizontalSeekCancelPendingChanged(isHorizontalSeekCancelPending)
            case .vertical:
                guard let target = PlayerSurfaceVerticalAdjustmentPolicy.target(
                    startLocationX: panStartLocation.x,
                    width: size.width
                ),
                let initialValue = parent.systemValueProvider(target)
                else {
                    panMode = .ignored
                    return
                }
                panMode = .adjusting(target: target, initialValue: initialValue)
                parent.onVerticalAdjustmentBegan(target, initialValue)
            }
        }

        private func updatePan(
            translation: CGPoint,
            location: CGPoint,
            velocity: CGPoint,
            size: CGSize
        ) {
            switch panMode {
            case let .seeking(duration):
                guard size.width > 0 else { return }
                let stepDX = translation.x - lastHorizontalTranslationX
                lastHorizontalTranslationX = translation.x
                let baseProgress = currentSeekProgress ?? parent.clock.progress
                let effectiveSeconds = PlayerHorizontalSeekSensitivity.effectiveSecondsPerFullWidth(
                    duration: duration,
                    horizontalVelocity: velocity.x
                )
                let progressDelta = Double(stepDX / size.width) * effectiveSeconds / duration
                let progress = min(max(baseProgress + progressDelta, 0), 1)
                currentSeekProgress = progress
                parent.clock.updateSeekPreview(progress: progress)
                let cancelPending = Self.horizontalSeekShouldCancel(at: location, size: size)
                if cancelPending != isHorizontalSeekCancelPending {
                    isHorizontalSeekCancelPending = cancelPending
                    parent.onHorizontalSeekCancelPendingChanged(cancelPending)
                }
                parent.onHorizontalSeekChanged(progress, velocity.x)
            case let .adjusting(target, initialValue):
                let value = PlayerSurfaceVerticalAdjustmentPolicy.adjustedValue(
                    initialValue: initialValue,
                    verticalTranslation: translation.y,
                    height: size.height
                )
                parent.onVerticalAdjustmentChanged(target, value)
            case .undecided, .ignored:
                break
            }
        }

        private func finishPan(
            commitsSeek: Bool,
            gesture: UIPanGestureRecognizer,
            in view: UIView
        ) {
            switch panMode {
            case .seeking:
                if commitsSeek {
                    updatePan(
                        translation: gesture.translation(in: view),
                        location: gesture.location(in: view),
                        velocity: gesture.velocity(in: view),
                        size: view.bounds.size
                    )
                }
                if commitsSeek, !isHorizontalSeekCancelPending {
                    let progress = currentSeekProgress ?? parent.clock.progress
                    parent.onHorizontalSeekEnded(progress)
                } else {
                    parent.onHorizontalSeekCancelled()
                    parent.clock.clearSeekPreview()
                }
            case .adjusting:
                parent.onVerticalAdjustmentEnded()
            case .undecided, .ignored:
                break
            }
            resetPanState()
        }

        private func resetPanState() {
            panMode = .undecided
            panStartLocation = .zero
            lastHorizontalTranslationX = 0
            currentSeekProgress = nil
            isHorizontalSeekCancelPending = false
        }

        private static func horizontalSeekShouldCancel(at location: CGPoint, size: CGSize) -> Bool {
            guard size.width > 0, size.height > 0 else { return false }
            let topCancelHeight = size.height * 0.125
            let edgeCancelWidth = size.width * 0.125
            return location.y <= topCancelHeight
                && (location.x <= edgeCancelWidth || location.x >= size.width - edgeCancelWidth)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            if (gestureRecognizer === panGesture && otherGestureRecognizer === longPressGesture)
                || (gestureRecognizer === longPressGesture && otherGestureRecognizer === panGesture) {
                return true
            }
            return false
        }
    }
}

struct PlayerSurfaceVerticalAdjustmentIndicator: View {
    let target: PlayerSurfaceVerticalAdjustmentTarget
    let value: Float

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
            Text("\(Int((value * 100).rounded()))%")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
            ProgressView(value: Double(value), total: 1)
                .tint(.white)
                .frame(width: 86)
        }
        .biliLiquidGlassForeground(shadowOpacity: 0.20)
        .padding(14)
        .frame(minWidth: 112)
        .biliPlayerClearGlass(interactive: false, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel(target.accessibilityLabel)
        .accessibilityValue("\(Int((value * 100).rounded()))%")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var systemImage: String {
        switch target {
        case .brightness:
            return "sun.max.fill"
        case .volume:
            if value <= 0.01 { return "speaker.slash.fill" }
            return value < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"
        }
    }
}
