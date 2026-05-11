import SwiftUI

extension View {
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
        toolbarBackground(.clear, for: .tabBar)
            .toolbarBackgroundVisibility(.visible, for: .tabBar)
            .toolbarColorScheme(isDark ? .dark : .light, for: .tabBar)
    }

    @ViewBuilder
    func biliGlassEffect<S: Shape>(
        tint: Color = Color(.systemBackground).opacity(0.18),
        interactive: Bool = true,
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
}

struct TopScrollEdgeEffect: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        content.scrollEdgeEffectStyle(.soft, for: .top)
    }
}
