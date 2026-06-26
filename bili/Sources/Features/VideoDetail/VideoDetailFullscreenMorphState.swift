import SwiftUI
import UIKit

struct VideoDetailFullscreenMorphState {
    enum Phase: Equatable {
        case entering
        case exiting
    }

    let phase: Phase
    let snapshot: PlaybackTransitionSnapshot
    let sourceFrame: CGRect
    let targetFrame: CGRect
    let orientation: UIDeviceOrientation
    let usesWindowMask: Bool
    var progress: Double
    var opacity: Double

    var isActive: Bool {
        opacity > 0
    }
}

struct VideoDetailPlayerSurfaceFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .null

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        guard next.width > 1, next.height > 1 else { return }
        value = next
    }
}

extension View {
    func videoDetailReportPlayerSurfaceFrame() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: VideoDetailPlayerSurfaceFramePreferenceKey.self,
                    value: proxy.frame(in: .global)
                )
            }
        )
    }
}
