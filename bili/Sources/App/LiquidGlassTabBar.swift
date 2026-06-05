import SwiftUI

extension View {
    @ViewBuilder
    func rootFloatingTabBarContentPadding(extra: CGFloat = 0) -> some View {
        safeAreaPadding(.bottom, RootFloatingTabBarMetrics.contentBottomPadding + extra)
    }

    @ViewBuilder
    func nativeTopNavigationChrome() -> some View {
        toolbarBackground(.automatic, for: .navigationBar)
    }

    @ViewBuilder
    func nativeTopScrollEdgeEffect() -> some View {
        modifier(TopScrollEdgeEffect())
    }

    @ViewBuilder
    func liquidGlassTabBarBackground(isDark: Bool = false) -> some View {
        self
    }

    @ViewBuilder
    func biliGlassEffect<S: Shape>(
        tint: Color = Color(.systemBackground).opacity(0.18),
        interactive: Bool = false,
        in shape: S
    ) -> some View {
        glassEffect(
            .regular
                .tint(tint)
                .interactive(interactive),
            in: shape
        )
    }

    @ViewBuilder
    func biliGlassButtonStyle(prominent: Bool = false) -> some View {
        if prominent {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.glass)
        }
    }

    @ViewBuilder
    func biliPlayerGlassButtonStyle(prominent: Bool = false) -> some View {
        buttonBorderShape(.capsule)
            .biliGlassButtonStyle(prominent: prominent)
    }

    @ViewBuilder
    func biliPlayerYouTubePillStyle(prominent: Bool = false) -> some View {
        buttonStyle(.plain)
            .background {
                Capsule()
                    .fill(.black.opacity(prominent ? 0.48 : 0.34))
            }
            .overlay {
                Capsule()
                    .stroke(.white.opacity(prominent ? 0.12 : 0.08), lineWidth: 0.5)
            }
            .contentShape(Capsule())
    }
}

struct TopScrollEdgeEffect: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        content.scrollEdgeEffectStyle(.soft, for: .top)
    }
}

enum RootFloatingTabBarMetrics {
    static let contentBottomPadding: CGFloat = 92
}
