import SwiftUI

struct PlayerSpeedBoostIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let phase: PlayerSpeedBoostPhase
    let displayedRate: BiliPlaybackRate

    var body: some View {
        Label(displayedRate.title, systemImage: systemImage)
            .font(.caption.weight(.bold))
            .labelStyle(.titleAndIcon)
            .contentTransition(reduceMotion ? .identity : .numericText())
            .biliLiquidGlassForeground(shadowOpacity: 0.20)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .biliPlayerClearGlass(interactive: false, in: Capsule())
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.updatesFrequently)
            .scaleEffect(phase == .boosting ? 1 : 0.96)
            .opacity(phase == .boosting ? 1 : 0.82)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: phase)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: displayedRate)
    }

    private var systemImage: String {
        phase == .boosting ? "forward.fill" : "arrow.uturn.backward"
    }

    private var accessibilityLabel: String {
        phase == .boosting
            ? "二倍速播放中"
            : "已恢复 \(displayedRate.title) 播放"
    }
}
