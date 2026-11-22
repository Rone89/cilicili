import SwiftUI
import UIKit

struct PlaybackDetailChromeHiddenPreferenceKey: PreferenceKey {
    static var defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

private struct PlaybackDetailViewChrome: ViewModifier {
    let navigationBarVisibility: Visibility?
    let hidesBackButton: Bool

    func body(content: Content) -> some View {
        content
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(hidesBackButton)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .playbackDetailNavigationBarVisibility(navigationBarVisibility)
    }
}

private struct PlaybackDetailNavigationBarVisibilityModifier: ViewModifier {
    let visibility: Visibility?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let visibility {
            content.toolbar(visibility, for: .navigationBar)
        } else {
            content
        }
    }
}

private struct PlaybackDetailSystemChrome: ViewModifier {
    @Environment(\.isDuoUnfoldedInnerDisplay) private var isDuoInnerDisplay
    let isHidden: Bool
    let statusBarStyle: UIStatusBarStyle

    func body(content: Content) -> some View {
        let effectiveHidden = isHidden || isDuoInnerDisplay
        content
            .adaptiveDuoFullscreenChrome(isHidden: effectiveHidden)
            .background {
                StatusBarStyleBridge(style: statusBarStyle, isHidden: effectiveHidden)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    @ViewBuilder
    func playbackUnderTransparentNavigationBar(_ enabled: Bool) -> some View {
        if enabled {
            safeAreaPadding(.top, UIApplication.shared.playbackDetailForegroundKeyWindow?.safeAreaInsets.top ?? 0)
                .ignoresSafeArea(.container, edges: .top)
        } else {
            self
        }
    }

    func playbackDetailViewChrome(
        navigationBarVisibility: Visibility? = nil,
        hidesBackButton: Bool = false
    ) -> some View {
        modifier(
            PlaybackDetailViewChrome(
                navigationBarVisibility: navigationBarVisibility,
                hidesBackButton: hidesBackButton
            )
        )
    }

    func playbackDetailNavigationBarVisibility(_ visibility: Visibility?) -> some View {
        modifier(PlaybackDetailNavigationBarVisibilityModifier(visibility: visibility))
    }

    func playbackDetailSystemChrome(
        isHidden: Bool,
        statusBarStyle: UIStatusBarStyle = .lightContent
    ) -> some View {
        modifier(
            PlaybackDetailSystemChrome(
                isHidden: isHidden,
                statusBarStyle: statusBarStyle
            )
        )
    }
}

extension UIView {
    func playbackSafeAreaInsets(underTransparentNavigationBar enabled: Bool) -> UIEdgeInsets {
        var insets = safeAreaInsets
        if enabled, let window {
            let windowSafeTop = convert(window.safeAreaLayoutGuide.layoutFrame, from: window).minY
            insets.top = min(insets.top, max(0, windowSafeTop))
        }
        return insets
    }
}

@MainActor
final class PlaybackNavigationBarTouchPassthrough {
    private weak var navigationBar: UINavigationBar?
    private var previousInteraction = true

    func begin(in navigationController: UINavigationController?) {
        guard navigationBar == nil, let bar = navigationController?.navigationBar else { return }
        previousInteraction = bar.isUserInteractionEnabled
        navigationBar = bar
        bar.isUserInteractionEnabled = false
    }

    func end() {
        navigationBar?.isUserInteractionEnabled = previousInteraction
        navigationBar = nil
    }
}
