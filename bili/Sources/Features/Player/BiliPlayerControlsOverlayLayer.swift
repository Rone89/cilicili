import SwiftUI
import UIKit

struct BiliPlayerControlsOverlayLayer: View {
    let state: BiliPlayerSurfaceChromeState
    let playbackControls: AnyView

    var body: some View {
        let safeAreaInsets = PlayerControlsSafeAreaInsets.current(isFullscreenActive: state.isFullscreenActive)
        ZStack(alignment: .bottom) {
            if state.showsActivePlaybackControls, let topLeadingControlsAccessory = state.topLeadingControlsAccessory {
                topLeadingControlsAccessory
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, topControlsPadding + safeAreaInsets.top)
                    .padding(.leading, horizontalControlsPadding + safeAreaInsets.leading)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
                    .zIndex(8)
            }

            if state.showsActivePlaybackControls, let topTrailingControlsAccessory = state.topTrailingControlsAccessory {
                topTrailingControlsAccessory
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, topControlsPadding + safeAreaInsets.top)
                    .padding(.trailing, horizontalControlsPadding + safeAreaInsets.trailing)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
                    .zIndex(8)
            }

            if state.showsActivePlaybackControls {
                BiliPlayerControlsBottomScrim(
                    presentation: state.presentation,
                    isFullscreenActive: state.isFullscreenActive,
                    safeAreaBottomInset: safeAreaInsets.bottom,
                    bottomLift: state.controlsBottomLift
                )
                .transition(.opacity)
                .zIndex(6)

                playbackControls
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.leading, horizontalControlsPadding + safeAreaInsets.leading)
                    .padding(.trailing, horizontalControlsPadding + safeAreaInsets.trailing)
                    .padding(.bottom, bottomControlsPadding + state.controlsBottomLift + safeAreaInsets.bottom)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

private struct BiliPlayerControlsBottomScrim: View {
    let presentation: BiliPlayerPresentation
    let isFullscreenActive: Bool
    let safeAreaBottomInset: CGFloat
    let bottomLift: CGFloat

    private var height: CGFloat {
        let baseHeight: CGFloat = (presentation == .embedded && !isFullscreenActive) ? 44 : 52
        return baseHeight + max(bottomLift, 0) + safeAreaBottomInset
    }

    var body: some View {
        LinearGradient(
            colors: [
                .clear,
                .black.opacity(0.20)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
