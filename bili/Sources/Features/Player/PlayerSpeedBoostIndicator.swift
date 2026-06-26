import SwiftUI

struct PlayerSpeedBoostIndicator: View {
    var body: some View {
        Label("2.0x", systemImage: "forward.fill")
            .font(.caption.weight(.bold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .biliPlayerClearGlass(interactive: false, in: Capsule())
            .accessibilityLabel("二倍速播放中")
    }
}
