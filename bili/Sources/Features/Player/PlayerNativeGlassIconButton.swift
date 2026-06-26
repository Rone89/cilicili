import SwiftUI

struct PlayerNativeGlassIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    let metrics: PlayerNativeControlMetrics
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: metrics.iconSize, weight: .semibold))
                .frame(
                    width: metrics.controlHeight,
                    height: metrics.controlHeight
                )
        }
        .biliPlayerCompactGlassCircle(metrics: metrics)
        .accessibilityLabel(accessibilityLabel)
    }
}
