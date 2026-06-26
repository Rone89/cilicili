import SwiftUI

struct BiliPlayerSurfaceOverlayLayer: View {
    let state: BiliPlayerSurfaceChromeState

    var body: some View {
        ZStack {
            if let surfaceOverlay = state.surfaceOverlay {
                surfaceOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(1)
            }

            if state.showsPlayerLoadingChrome {
                PlayerStartupLoadingChrome(isBuffering: state.isBuffering)
                    .padding(state.presentation == .embedded ? 12 : 16)
                    .zIndex(2)
            }

            if let errorMessage = state.errorMessage {
                PlayerPlaybackErrorChrome(message: errorMessage)
                    .padding(state.presentation == .embedded ? 10 : 16)
                    .zIndex(3)
            }

            if state.showsRotationSnapshot {
                PlayerRotationTransitionSnapshotView(
                    snapshot: state.rotationSnapshot,
                    fallbackCoverURL: state.rotationFallbackCoverURL,
                    constrainsToVideoAspect: state.constrainsRotationSnapshotToVideoAspect
                )
                .background(Color.black)
                .opacity(state.rotationSnapshotOpacity)
                .zIndex(7)
            }

            if state.showsInlineLoadingProgress {
                PlayerInlineLoadingIndicator(
                    message: state.isUserSeeking ? "正在定位" : "正在缓冲"
                )
                .padding(.top, state.presentation == .embedded ? 10 : 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(6)
            }

            if state.isSpeedBoostActive {
                PlayerSpeedBoostIndicator()
                    .padding(.top, state.presentation == .embedded ? 10 : 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

private extension BiliPlayerSurfaceChromeState {
    var showsRotationSnapshot: Bool {
        rotationSnapshotOpacity > 0
            && rotationSnapshot != nil
    }
}
