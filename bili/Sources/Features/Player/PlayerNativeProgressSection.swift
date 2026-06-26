import SwiftUI

struct PlayerNativeProgressSection: View {
    let metrics: PlayerNativeControlMetrics
    @ObservedObject var clock: PlayerPlaybackClock
    let canSeek: Bool
    let sliderVisualScale: CGFloat
    let onScrubStart: (Double) -> Void
    let onScrubChanged: (Double) -> Void
    let onScrubEnded: (Double) -> Void

    var body: some View {
        PlayerNativeProgressSlider(
            clock: clock,
            canSeek: canSeek,
            sliderVisualScale: sliderVisualScale,
            onScrubStart: onScrubStart,
            onScrubChanged: onScrubChanged,
            onScrubEnded: onScrubEnded
        )
        .padding(.horizontal, metrics.sliderHorizontalPadding)
        .frame(height: metrics.progressControlHeight)
    }
}
