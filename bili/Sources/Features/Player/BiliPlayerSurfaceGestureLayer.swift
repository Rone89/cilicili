import SwiftUI

struct BiliPlayerSurfaceGestureLayer<Content: View>: View {
    let content: Content
    let onSingleTap: () -> Void
    let onDoubleTap: () -> Void
    let onBeginSpeedBoost: () -> Void
    let onEndSpeedBoost: () -> Void

    var body: some View {
        content
            .contentShape(Rectangle())
            .gesture(
                TapGesture(count: 2)
                    .exclusively(before: TapGesture(count: 1))
                    .onEnded { value in
                        switch value {
                        case .first:
                            onSingleTap()
                        case .second:
                            onDoubleTap()
                        }
                    }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.28, maximumDistance: 80)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onChanged { value in
                        guard case .second(true, _) = value else { return }
                        onBeginSpeedBoost()
                    }
                    .onEnded { _ in
                        onEndSpeedBoost()
                    }
            )
    }
}
