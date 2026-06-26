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
        .accessibilityLabel("返回")
    }
}
