import SwiftUI

struct VideoDetailPinnedProgressBar: View {
    static let height: CGFloat = 18
    static let visibleHeight: CGFloat = 3

    @ObservedObject private var playerViewModel: PlayerStateViewModel
    @ObservedObject private var playbackClock: PlayerPlaybackClock
    let onPrepareSeek: (Double) -> Void
    @State private var isScrubbing = false
    @State private var scrubProgress = 0.0
    @State private var lastPreparedProgress = -1.0

    init(
        playerViewModel: PlayerStateViewModel,
        onPrepareSeek: @escaping (Double) -> Void
    ) {
        _playerViewModel = ObservedObject(wrappedValue: playerViewModel)
        _playbackClock = ObservedObject(wrappedValue: playerViewModel.playbackClock)
        self.onPrepareSeek = onPrepareSeek
    }

    var body: some View {
        GeometryReader { proxy in
            VideoDetailPinnedStaticProgressTrack(progress: displayedProgress)
                .contentShape(Rectangle())
                .gesture(progressDragGesture(width: proxy.size.width))
                .accessibilityElement()
                .accessibilityLabel("视频进度")
                .accessibilityValue(accessibilityValue)
                .accessibilityAdjustableAction { direction in
                    guard canSeek else { return }
                    switch direction {
                    case .increment:
                        seek(to: displayedProgress + accessibilityStep)
                    case .decrement:
                        seek(to: displayedProgress - accessibilityStep)
                    default:
                        break
                    }
                }
                .allowsHitTesting(canSeek)
                .disabled(!canSeek)
        }
        .frame(height: Self.height)
    }

    private func progressDragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard canSeek else { return }
                let progress = progress(at: value.location.x, in: width)
                if !isScrubbing {
                    prepareSeekWarmupIfNeeded(progress, force: true)
                }
                isScrubbing = true
                scrubProgress = progress
                prepareSeekWarmupIfNeeded(progress)
            }
            .onEnded { value in
                guard canSeek else { return }
                let progress = progress(at: value.location.x, in: width)
                isScrubbing = false
                Haptics.light()
                seek(to: progress)
            }
    }

    private func progress(at locationX: CGFloat, in width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Self.clamped(Double(locationX / width))
    }

    private func seek(to progress: Double) {
        let clampedProgress = Self.clamped(progress)
        scrubProgress = clampedProgress
        prepareSeekWarmupIfNeeded(clampedProgress, force: true)
        playerViewModel.seekAfterUserScrub(to: clampedProgress)
        lastPreparedProgress = -1
    }

    private func prepareSeekWarmupIfNeeded(_ progress: Double, force: Bool = false) {
        let clampedProgress = Self.clamped(progress)
        guard force || abs(clampedProgress - lastPreparedProgress) >= 0.015 else { return }
        lastPreparedProgress = clampedProgress
        onPrepareSeek(clampedProgress)
    }

    private var displayedProgress: Double {
        guard isScrubbing else { return playbackProgress }
        return Self.clamped(scrubProgress)
    }

    private var playbackProgress: Double {
        guard let duration = resolvedDuration, duration > 0 else { return 0 }
        return Self.clamped(max(playbackClock.currentTime, 0) / duration)
    }

    private var resolvedDuration: TimeInterval? {
        playbackClock.duration ?? playerViewModel.displayDuration
    }

    private var canSeek: Bool {
        playerViewModel.canSeek && (resolvedDuration ?? 0) > 0
    }

    private var displayedTime: TimeInterval {
        guard isScrubbing, let duration = resolvedDuration, duration > 0 else {
            return max(playbackClock.currentTime, 0)
        }
        return displayedProgress * duration
    }

    private var accessibilityStep: Double {
        guard let duration = resolvedDuration, duration > 0 else { return 0.05 }
        return min(max(10 / duration, 0.01), 0.10)
    }

    private var accessibilityValue: String {
        let current = BiliFormatters.duration(Int(displayedTime.rounded()))
        guard let duration = resolvedDuration, duration > 0 else {
            return current
        }
        return "\(current) / \(BiliFormatters.duration(Int(duration.rounded())))"
    }

    private static func clamped(_ progress: Double) -> Double {
        min(max(progress, 0), 1)
    }
}

struct VideoDetailPinnedProgressPlaceholder: View {
    var body: some View {
        VideoDetailPinnedStaticProgressTrack(progress: 0)
            .accessibilityHidden(true)
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
