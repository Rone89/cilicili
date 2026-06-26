import SwiftUI

@MainActor
struct VideoDetailPinnedDynamicPlayerHeaderNavigationActions {
    let onExitFullscreen: (() -> Void)?
    let onNavigateBack: () -> Void

    func handleBackButtonTap() {
        if let onExitFullscreen {
            onExitFullscreen()
        } else {
            onNavigateBack()
        }
    }
}

@MainActor
struct VideoDetailPinnedDynamicPlayerHeaderPlaybackActions {
    let isPlaybackActive: Binding<Bool>

    func updatePlaybackActive(_ isActive: Bool) {
        guard isPlaybackActive.wrappedValue != isActive else { return }
        withAnimation(.smooth(duration: 0.22)) {
            isPlaybackActive.wrappedValue = isActive
        }
    }
}
