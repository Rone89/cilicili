import SwiftUI

extension View {
    @ViewBuilder
    func biliPlayerCompactGlassCircle(metrics: PlayerNativeControlMetrics) -> some View {
        buttonStyle(.plain)
            .contentShape(Circle())
            .biliPlayerClearGlass(interactive: true, in: Circle())
    }

    @ViewBuilder
    func biliPlayerCompactGlassCapsule(metrics: PlayerNativeControlMetrics) -> some View {
        buttonStyle(.plain)
            .contentShape(Capsule())
            .biliPlayerClearGlass(interactive: true, in: Capsule())
    }

    @ViewBuilder
    func biliPlayerClearGlass<S: Shape>(
        interactive: Bool,
        in shape: S
    ) -> some View {
        glassEffect(
            .clear
                .interactive(interactive),
            in: shape
        )
    }
}
