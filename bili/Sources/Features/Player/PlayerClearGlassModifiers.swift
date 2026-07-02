import SwiftUI

extension View {
    @ViewBuilder
    func biliPlayerCompactGlassCircle(metrics: PlayerNativeControlMetrics) -> some View {
        buttonStyle(.plain)
            .contentShape(Circle())
            .biliPlayerClearGlass(interactive: true, in: Circle())
            .biliPlayerExpandedHitTarget(metrics: metrics)
    }

    @ViewBuilder
    func biliPlayerCompactGlassCapsule(metrics: PlayerNativeControlMetrics) -> some View {
        buttonStyle(.plain)
            .contentShape(Capsule())
            .biliPlayerClearGlass(interactive: true, in: Capsule())
            .biliPlayerExpandedHitTarget(metrics: metrics)
    }

    @ViewBuilder
    func biliPlayerClearGlass<S: Shape>(
        interactive: Bool,
        in shape: S
    ) -> some View {
        if #available(iOS 26, *) {
            glassEffect(
                .clear
                    .interactive(interactive),
                in: shape
            )
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }

    func biliPlayerExpandedHitTarget(horizontal: CGFloat = 4, vertical: CGFloat = 8) -> some View {
        padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .contentShape(Rectangle())
            .padding(.horizontal, -horizontal)
            .padding(.vertical, -vertical)
    }

    func biliPlayerExpandedHitTarget(metrics: PlayerNativeControlMetrics) -> some View {
        let horizontal = max((44 - metrics.controlHeight) / 2, 4)
        let vertical = max((44 - metrics.controlHeight) / 2, 8)
        return biliPlayerExpandedHitTarget(horizontal: horizontal, vertical: vertical)
    }
}
