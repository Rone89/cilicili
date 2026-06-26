import SwiftUI

struct PlayerNativeProgressGestureCaptureLayer: View {
    let isEnabled: Bool
    let onScrubChanged: (Double) -> Void
    let onScrubEnded: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard isEnabled else { return }
                            onScrubChanged(
                                PlayerNativeProgressScrubCalculator.progress(
                                    locationX: value.location.x,
                                    width: proxy.size.width
                                )
                            )
                        }
                        .onEnded { value in
                            guard isEnabled else { return }
                            onScrubEnded(
                                PlayerNativeProgressScrubCalculator.progress(
                                    locationX: value.location.x,
                                    width: proxy.size.width
                                )
                            )
                        }
                )
                .allowsHitTesting(isEnabled)
        }
    }
}
