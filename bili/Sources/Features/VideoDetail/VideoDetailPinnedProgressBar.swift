import Combine
import SwiftUI
import UIKit

struct VideoDetailPinnedProgressBar: View {
    static let height: CGFloat = 18
    static let visibleHeight: CGFloat = 3

    let playerViewModel: PlayerStateViewModel
    let onPrepareSeek: (Double) -> Void

    init(
        playerViewModel: PlayerStateViewModel,
        onPrepareSeek: @escaping (Double) -> Void
    ) {
        self.playerViewModel = playerViewModel
        self.onPrepareSeek = onPrepareSeek
    }

    var body: some View {
        VideoDetailPinnedProgressControl(
            playerViewModel: playerViewModel,
            onPrepareSeek: { progress, _ in
                onPrepareSeek(progress)
            },
            onSeek: { progress in
                playerViewModel.seekAfterUserScrub(to: progress)
            }
        )
        .frame(height: Self.height)
    }
}

struct VideoDetailPinnedProgressPlaceholder: View {
    var body: some View {
        VideoDetailPinnedStaticProgressTrack(progress: 0)
            .accessibilityHidden(true)
    }
}

private struct VideoDetailPinnedProgressControl: UIViewRepresentable {
    let playerViewModel: PlayerStateViewModel
    let onPrepareSeek: (Double, Bool) -> Void
    let onSeek: (Double) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> VideoDetailPinnedProgressControlView {
        let view = VideoDetailPinnedProgressControlView()
        context.coordinator.bind(
            playerViewModel: playerViewModel,
            view: view,
            onPrepareSeek: onPrepareSeek,
            onSeek: onSeek
        )
        return view
    }

    func updateUIView(_ uiView: VideoDetailPinnedProgressControlView, context: Context) {
        context.coordinator.bind(
            playerViewModel: playerViewModel,
            view: uiView,
            onPrepareSeek: onPrepareSeek,
            onSeek: onSeek
        )
    }

    static func dismantleUIView(_ uiView: VideoDetailPinnedProgressControlView, coordinator: Coordinator) {
        coordinator.unbind()
        uiView.resetCallbacks()
    }

    @MainActor
    final class Coordinator {
        private weak var boundPlayerViewModel: PlayerStateViewModel?
        private var cancellables = Set<AnyCancellable>()

        func bind(
            playerViewModel: PlayerStateViewModel,
            view: VideoDetailPinnedProgressControlView,
            onPrepareSeek: @escaping (Double, Bool) -> Void,
            onSeek: @escaping (Double) -> Void
        ) {
            view.onPrepareSeek = onPrepareSeek
            view.onSeek = onSeek

            guard boundPlayerViewModel !== playerViewModel else {
                view.apply(playerViewModel: playerViewModel, force: false)
                return
            }

            cancellables.removeAll()
            boundPlayerViewModel = playerViewModel
            view.apply(playerViewModel: playerViewModel, force: true)

            playerViewModel.$isSeekable
                .removeDuplicates()
                .sink { [weak view, weak playerViewModel] _ in
                    guard let playerViewModel else { return }
                    view?.apply(playerViewModel: playerViewModel, force: false)
                }
                .store(in: &cancellables)

            playerViewModel.$duration
                .removeDuplicates()
                .sink { [weak view, weak playerViewModel] _ in
                    guard let playerViewModel else { return }
                    view?.apply(playerViewModel: playerViewModel, force: false)
                }
                .store(in: &cancellables)

            playerViewModel.playbackClock.$currentTime
                .removeDuplicates { abs($0 - $1) < 0.08 }
                .sink { [weak view, weak playerViewModel] _ in
                    guard let playerViewModel else { return }
                    view?.apply(playerViewModel: playerViewModel, force: false)
                }
                .store(in: &cancellables)

            playerViewModel.playbackClock.$duration
                .removeDuplicates { lhs, rhs in
                    switch (lhs, rhs) {
                    case (nil, nil):
                        return true
                    case let (left?, right?):
                        return abs(left - right) < 0.4
                    default:
                        return false
                    }
                }
                .sink { [weak view, weak playerViewModel] _ in
                    guard let playerViewModel else { return }
                    view?.apply(playerViewModel: playerViewModel, force: false)
                }
                .store(in: &cancellables)
        }

        func unbind() {
            cancellables.removeAll()
            boundPlayerViewModel = nil
        }
    }
}

@MainActor
private final class VideoDetailPinnedProgressControlView: UIView {
    private let backgroundTrackLayer = CALayer()
    private let progressLayer = CALayer()
    private var progress: Double = 0
    private var canSeek = false
    private var currentTime: TimeInterval = 0
    private var duration: TimeInterval?
    private var isScrubbing = false
    private var scrubProgress = 0.0
    private var lastPreparedProgress = -1.0

    var onPrepareSeek: ((Double, Bool) -> Void)?
    var onSeek: ((Double) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
        configureGestures()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutTrackLayers()
    }

    func apply(playerViewModel: PlayerStateViewModel, force: Bool) {
        let clock = playerViewModel.playbackClock
        let resolvedDuration = clock.duration ?? playerViewModel.displayDuration
        let resolvedCurrentTime = max(clock.currentTime, 0)
        let resolvedProgress: Double
        if let resolvedDuration, resolvedDuration > 0 {
            resolvedProgress = Self.clamped(resolvedCurrentTime / resolvedDuration)
        } else {
            resolvedProgress = 0
        }

        currentTime = resolvedCurrentTime
        duration = resolvedDuration
        canSeek = playerViewModel.canSeek && (resolvedDuration ?? 0) > 0
        isUserInteractionEnabled = canSeek
        accessibilityTraits = canSeek ? [.adjustable] : [.notEnabled]
        updateAccessibilityValue()

        guard force || !isScrubbing else { return }
        setProgress(resolvedProgress, force: force)
    }

    func resetCallbacks() {
        onPrepareSeek = nil
        onSeek = nil
    }

    override func accessibilityIncrement() {
        guard canSeek else { return }
        seek(to: displayedProgress + accessibilityStep)
    }

    override func accessibilityDecrement() {
        guard canSeek else { return }
        seek(to: displayedProgress - accessibilityStep)
    }

    private func configureView() {
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        accessibilityLabel = "视频进度"
        accessibilityTraits = [.adjustable]

        backgroundTrackLayer.backgroundColor = UIColor.white.withAlphaComponent(0.24).cgColor
        progressLayer.backgroundColor = UIColor(red: 1.0, green: 0.36, blue: 0.58, alpha: 1).cgColor
        [backgroundTrackLayer, progressLayer].forEach {
            $0.cornerCurve = .continuous
            layer.addSublayer($0)
        }
    }

    private func configureGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.require(toFail: pan)
        addGestureRecognizer(tap)
    }

    private func layoutTrackLayers() {
        let trackHeight = VideoDetailPinnedProgressBar.visibleHeight
        let y = max(0, bounds.height - trackHeight)
        let fullFrame = CGRect(x: 0, y: y, width: bounds.width, height: trackHeight)
        CATransaction.performWithoutAnimation {
            backgroundTrackLayer.frame = fullFrame
            progressLayer.frame = CGRect(
                x: 0,
                y: y,
                width: bounds.width * displayedProgress,
                height: trackHeight
            )
            backgroundTrackLayer.cornerRadius = trackHeight / 2
            progressLayer.cornerRadius = trackHeight / 2
        }
    }

    private func setProgress(_ nextProgress: Double, force: Bool) {
        let clampedProgress = Self.clamped(nextProgress)
        guard force || abs(clampedProgress - progress) > 0.0008 else { return }
        progress = clampedProgress
        CATransaction.performWithoutAnimation {
            progressLayer.frame.size.width = bounds.width * clampedProgress
        }
        updateAccessibilityValue()
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard canSeek else { return }
        let targetProgress = progress(at: recognizer.location(in: self).x)
        Haptics.light()
        seek(to: targetProgress)
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard canSeek else { return }
        let targetProgress = progress(at: recognizer.location(in: self).x)
        switch recognizer.state {
        case .began:
            isScrubbing = true
            scrubProgress = targetProgress
            setProgress(targetProgress, force: true)
            prepareSeekWarmupIfNeeded(targetProgress, force: true)
        case .changed:
            scrubProgress = targetProgress
            setProgress(targetProgress, force: true)
            prepareSeekWarmupIfNeeded(targetProgress)
        case .ended:
            isScrubbing = false
            Haptics.light()
            seek(to: targetProgress)
        case .cancelled, .failed:
            isScrubbing = false
            setProgress(progress, force: true)
            lastPreparedProgress = -1
        default:
            break
        }
    }

    private func seek(to progress: Double) {
        let clampedProgress = Self.clamped(progress)
        scrubProgress = clampedProgress
        setProgress(clampedProgress, force: true)
        prepareSeekWarmupIfNeeded(clampedProgress, force: true)
        onSeek?(clampedProgress)
        lastPreparedProgress = -1
    }

    private func prepareSeekWarmupIfNeeded(_ progress: Double, force: Bool = false) {
        let clampedProgress = Self.clamped(progress)
        guard force || abs(clampedProgress - lastPreparedProgress) >= 0.015 else { return }
        lastPreparedProgress = clampedProgress
        onPrepareSeek?(clampedProgress, force)
    }

    private func progress(at locationX: CGFloat) -> Double {
        guard bounds.width > 0 else { return 0 }
        return Self.clamped(Double(locationX / bounds.width))
    }

    private var displayedProgress: Double {
        Self.clamped(isScrubbing ? scrubProgress : progress)
    }

    private var displayedTime: TimeInterval {
        guard isScrubbing, let duration, duration > 0 else {
            return currentTime
        }
        return displayedProgress * duration
    }

    private var accessibilityStep: Double {
        guard let duration, duration > 0 else { return 0.05 }
        return min(max(10 / duration, 0.01), 0.10)
    }

    private func updateAccessibilityValue() {
        let current = BiliFormatters.duration(Int(displayedTime.rounded()))
        guard let duration, duration > 0 else {
            accessibilityValue = current
            return
        }
        accessibilityValue = "\(current) / \(BiliFormatters.duration(Int(duration.rounded())))"
    }

    private static func clamped(_ progress: Double) -> Double {
        min(max(progress, 0), 1)
    }
}

private struct VideoDetailPinnedStaticProgressTrack: View {
    let progress: Double

    var body: some View {
        let clampedProgress = min(max(progress, 0), 1)

        ZStack(alignment: .bottomLeading) {
            Color.clear

            Capsule()
                .fill(Color.white.opacity(0.24))
                .frame(height: VideoDetailPinnedProgressBar.visibleHeight)

            Capsule()
                .fill(Color(red: 1.0, green: 0.36, blue: 0.58))
                .frame(maxWidth: .infinity)
                .frame(height: VideoDetailPinnedProgressBar.visibleHeight)
                .scaleEffect(x: clampedProgress, y: 1, anchor: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .frame(height: VideoDetailPinnedProgressBar.height)
    }
}

private extension CATransaction {
    static func performWithoutAnimation(_ updates: () -> Void) {
        begin()
        setDisableActions(true)
        updates()
        commit()
    }
}
