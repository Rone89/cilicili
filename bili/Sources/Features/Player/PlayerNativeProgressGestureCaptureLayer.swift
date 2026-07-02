import SwiftUI

struct PlayerNativeProgressGestureCaptureLayer: View {
    let isEnabled: Bool
    let onScrubChanged: (Double) -> Void
    let onScrubEnded: (Double) -> Void
    private let dragActivationDistance: CGFloat = 4

    @State private var dragStartX: CGFloat?
    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard isEnabled else { return }
                            let startX = dragStartX ?? value.startLocation.x
                            dragStartX = startX
                            guard isDragging || abs(value.location.x - startX) >= dragActivationDistance else {
                                return
                            }
                            isDragging = true
                            onScrubChanged(progress(for: value.location.x, width: proxy.size.width))
                        }
                        .onEnded { value in
                            if isEnabled {
                                onScrubEnded(progress(for: value.location.x, width: proxy.size.width))
                            }
                            dragStartX = nil
                            isDragging = false
                        }
                )
                .allowsHitTesting(isEnabled)
        }
    }

    private func progress(for locationX: CGFloat, width: CGFloat) -> Double {
        PlayerNativeProgressScrubCalculator.progress(locationX: locationX, width: width)
    }
}
