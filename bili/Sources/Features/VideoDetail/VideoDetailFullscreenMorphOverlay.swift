import SwiftUI

struct VideoDetailFullscreenMorphOverlay: View {
    let state: VideoDetailFullscreenMorphState?

    var body: some View {
        if let state, state.isActive, !state.usesWindowMask {
            ZStack {
                Color.black
                    .opacity(backdropOpacity(for: state))
                    .ignoresSafeArea()

                snapshotImage(for: state)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .zIndex(200)
        }
    }

    @ViewBuilder
    private func snapshotImage(for state: VideoDetailFullscreenMorphState) -> some View {
        GeometryReader { proxy in
            let containerFrame = proxy.frame(in: .global)
            let frame = interpolatedFrame(
                for: state,
                containerFrame: containerFrame,
                fallbackSize: proxy.size
            )
            Image(uiImage: state.snapshot.image)
                .resizable()
                .aspectRatio(snapshotAspectRatio(state.snapshot.image.size), contentMode: .fit)
                .frame(width: frame.width, height: frame.height)
                .clipped()
                .position(x: frame.midX, y: frame.midY)
                .opacity(state.opacity)
                .animation(
                    VideoDetailFullscreenCoordinator.morphTransitionAnimation,
                    value: state.progress
                )
        }
    }

    private func backdropOpacity(for state: VideoDetailFullscreenMorphState) -> Double {
        switch state.phase {
        case .entering:
            return state.opacity
        case .exiting:
            return state.opacity * max(0.28, 1 - state.progress * 0.72)
        }
    }

    private func interpolatedFrame(
        for state: VideoDetailFullscreenMorphState,
        containerFrame: CGRect,
        fallbackSize: CGSize
    ) -> CGRect {
        let source = localFrame(state.sourceFrame, in: containerFrame, fallbackSize: fallbackSize)
        let target = localFrame(state.targetFrame, in: containerFrame, fallbackSize: fallbackSize)
        let progress = min(max(state.progress, 0), 1)
        return CGRect(
            x: lerp(source.minX, target.minX, progress),
            y: lerp(source.minY, target.minY, progress),
            width: lerp(source.width, target.width, progress),
            height: lerp(source.height, target.height, progress)
        )
    }

    private func localFrame(
        _ frame: CGRect,
        in containerFrame: CGRect,
        fallbackSize: CGSize
    ) -> CGRect {
        guard frame.width > 1, frame.height > 1, !frame.isNull, !frame.isInfinite else {
            return CGRect(origin: .zero, size: fallbackSize)
        }
        return frame.offsetBy(dx: -containerFrame.minX, dy: -containerFrame.minY)
    }

    private func snapshotAspectRatio(_ size: CGSize) -> CGFloat {
        guard size.width > 1, size.height > 1 else { return 16.0 / 9.0 }
        return size.width / size.height
    }

    private func lerp(_ start: CGFloat, _ end: CGFloat, _ progress: Double) -> CGFloat {
        start + (end - start) * CGFloat(progress)
    }

}
