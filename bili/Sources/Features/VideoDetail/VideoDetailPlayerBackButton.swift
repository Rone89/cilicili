import SwiftUI

struct VideoDetailPlayerBackButton: View {
    @Environment(\.playerNativeControlMetrics) private var controlMetrics
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.light()
            action()
        }) {
            Image(systemName: "chevron.left")
                .font(.system(size: controlMetrics.iconSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(
                    width: controlMetrics.controlHeight,
                    height: controlMetrics.controlHeight
                )
        }
        .biliPlayerCompactGlassCircle(metrics: controlMetrics)
        .frame(width: 44, height: controlMetrics.controlHeight, alignment: .leading)
        .biliPlayerExpandedHitTarget(horizontal: 0, vertical: verticalHitPadding)
        .accessibilityLabel("返回")
    }

    private var verticalHitPadding: CGFloat {
        max((44 - controlMetrics.controlHeight) / 2, 8)
    }
}
