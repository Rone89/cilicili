import SwiftUI

struct PlayerNativeProgressSlider: View {
    @ObservedObject var clock: PlayerPlaybackClock
    let canSeek: Bool
    let sliderVisualScale: CGFloat
    let onScrubStart: (Double) -> Void
    let onScrubChanged: (Double) -> Void
    let onScrubEnded: (Double) -> Void

    @State private var scrubbingState = PlayerNativeProgressScrubbingState()
    private let scrubChangeReportDelta = 0.004

    private var progressBinding: Binding<Double> {
        Binding(
            get: {
                scrubbingState.isEditing ? scrubbingState.editingProgress : clock.progress
            },
            set: { newValue in
                let clampedValue = min(max(newValue, 0), 1)
                if !scrubbingState.isEditing {
                    beginScrub(at: clampedValue)
                }
                scrubbingState.editingProgress = clampedValue
                reportScrubChanged(clampedValue)
            }
        )
    }

    var body: some View {
        ZStack {
            ProgressView(value: displayProgress, total: 1)
                .progressViewStyle(.linear)
                .tint(.white)
                .opacity(scrubbingState.isEditing ? 0 : 1)
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
            .opacity(scrubbingState.isEditing ? 1 : 0.001)
            .allowsHitTesting(false)

            PlayerNativeProgressGestureCaptureLayer(
                isEnabled: effectiveCanSeek,
                onScrubChanged: { progress in
                    beginScrub(at: progress)
                    reportScrubChanged(progress)
                },
                onScrubEnded: { progress in
                    finishScrub(at: progress)
                }
            )
        }
        .disabled(!effectiveCanSeek)
        .onChange(of: effectiveCanSeek) { _, canSeek in
            if !canSeek {
                scrubbingState.reset()
            }
        }
        .controlSize(.mini)
        .scaleEffect(y: sliderVisualScale, anchor: .center)
        .accessibilityLabel("播放进度")
    }

    private var displayProgress: Double {
        min(max(scrubbingState.isEditing ? scrubbingState.editingProgress : clock.progress, 0), 1)
    }

    private var effectiveCanSeek: Bool {
        canSeek && (clock.duration ?? 0) > 0
    }

    private func beginScrub(at progress: Double) {
        scrubbingState.beginScrub(
            at: progress,
            canSeek: effectiveCanSeek,
            onScrubStart: onScrubStart
        )
    }

    private func finishScrub(at progress: Double) {
        scrubbingState.finishScrub(
            at: progress,
            canSeek: effectiveCanSeek,
            onScrubEnded: onScrubEnded
        )
    }

    private func reportScrubChanged(_ progress: Double) {
        guard scrubbingState.shouldReportChange(
            at: progress,
            minimumDelta: scrubChangeReportDelta
        ) else { return }
        onScrubChanged(progress)
    }
}
