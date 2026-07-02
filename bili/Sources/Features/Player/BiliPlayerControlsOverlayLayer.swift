import SwiftUI
import UIKit

struct BiliPlayerControlsOverlayLayer: View {
    let state: BiliPlayerSurfaceChromeState
    let playbackControls: AnyView

    var body: some View {
        let safeAreaInsets = PlayerControlsSafeAreaInsets.current(isFullscreenActive: state.isFullscreenActive)
        let topInset = max(safeAreaInsets.top, state.contentInsets.top)
        let leadingInset = max(safeAreaInsets.leading, state.contentInsets.leading)
        let bottomInset = max(safeAreaInsets.bottom, state.contentInsets.bottom)
        let trailingInset = max(safeAreaInsets.trailing, state.contentInsets.trailing)
        ZStack(alignment: .bottom) {
            if state.showsActivePlaybackControls, let topLeadingControlsAccessory = state.topLeadingControlsAccessory {
                topLeadingControlsAccessory
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, topControlsPadding + topInset)
                    .padding(.leading, horizontalControlsPadding + leadingInset)
                    .transition(.opacity)
                    .zIndex(8)
            }

            if state.showsActivePlaybackControls, let topTrailingControlsAccessory = state.topTrailingControlsAccessory {
                topTrailingControlsAccessory
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, topControlsPadding + topInset)
                    .padding(.trailing, horizontalControlsPadding + trailingInset)
                    .transition(.opacity)
                    .zIndex(8)
            }

            if state.showsActivePlaybackControls {
                playbackControls
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.leading, horizontalControlsPadding + leadingInset)
                    .padding(.trailing, horizontalControlsPadding + trailingInset)
                    .padding(.bottom, bottomControlsPadding + state.controlsBottomLift + bottomInset)
                    .transition(.opacity)
                    .zIndex(7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(state.playbackControlsOpacity)
        .allowsHitTesting(state.playbackControlsAllowsHitTesting)
    }

    private var usesFullscreenChromeSpacing: Bool {
        state.presentation == .fullScreen || state.isFullscreenActive
    }

    private var topControlsPadding: CGFloat {
        usesFullscreenChromeSpacing ? 14 : 10
    }

    private var horizontalControlsPadding: CGFloat {
        usesFullscreenChromeSpacing ? 14 : 10
    }

    private var bottomControlsPadding: CGFloat {
        usesFullscreenChromeSpacing ? 14 : 8
    }
}

private struct PlayerControlsSafeAreaInsets {
    let top: CGFloat
    let leading: CGFloat
    let bottom: CGFloat
    let trailing: CGFloat

    static func current(isFullscreenActive: Bool) -> PlayerControlsSafeAreaInsets {
        guard isFullscreenActive,
              let insets = UIApplication.shared.biliPlayerForegroundKeyWindow?.safeAreaInsets
        else { return .zero }

        return PlayerControlsSafeAreaInsets(
            top: max(insets.top, 0),
            leading: max(insets.left, 0),
            bottom: max(insets.bottom, 0),
            trailing: max(insets.right, 0)
        )
    }

    private static let zero = PlayerControlsSafeAreaInsets(
        top: 0,
        leading: 0,
        bottom: 0,
        trailing: 0
    )
}

private extension UIApplication {
    var biliPlayerForegroundKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}
