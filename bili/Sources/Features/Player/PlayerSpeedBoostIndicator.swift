import SwiftUI

struct PlayerSpeedBoostIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let phase: PlayerSpeedBoostPhase
    let displayedRate: BiliPlaybackRate
    var displayedRateTitle: String? = nil
    var isLockTargetHighlighted: Bool = false
    var onUnlock: (() -> Void)? = nil

    private var rateTitle: String {
        displayedRateTitle ?? displayedRate.title
    }

    var body: some View {
        Group {
            if phase == .locked, let onUnlock {
                Button(action: onUnlock) {
                    pillContent
                }
                .buttonStyle(.plain)
            } else {
                pillContent
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(phase == .locked ? .isButton : .updatesFrequently)
        .accessibilityIdentifier("ui.player.speedBoostIndicator")
        .scaleEffect(phase == .boosting || phase == .locked ? 1 : 0.96)
        .opacity(phase == .restoring ? 0.82 : 1)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: phase)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: rateTitle)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: isLockTargetHighlighted)
    }

    private var pillContent: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                Text(primaryText)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
            }
            .biliLiquidGlassForeground(shadowOpacity: 0.20)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .biliPlayerClearGlass(interactive: phase == .locked && onUnlock != nil, in: Capsule())
            .overlay {
                if phase == .boosting && isLockTargetHighlighted {
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.75), lineWidth: 1.2)
                }
            }

            if phase == .boosting {
                Text(isLockTargetHighlighted ? "松手锁定倍速" : "左右滑调速 · 上滑锁定")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.45), in: Capsule())
            }
        }
    }

    private var primaryText: String {
        switch phase {
        case .locked:
            return "\(rateTitle) · 点击恢复"
        case .boosting, .restoring, .idle:
            return rateTitle
        }
    }

    private var systemImage: String {
        switch phase {
        case .boosting:
            return isLockTargetHighlighted ? "lock.fill" : "forward.fill"
        case .locked:
            return "lock.fill"
        case .restoring, .idle:
            return "arrow.uturn.backward"
        }
    }

    private var accessibilityLabel: String {
        switch phase {
        case .boosting:
            return isLockTargetHighlighted
                ? "\(rateTitle) 播放中，松手锁定倍速"
                : "\(rateTitle) 加速播放中"
        case .locked:
            return "\(rateTitle) 倍速已锁定，点击恢复原倍速"
        case .restoring, .idle:
            return "已恢复 \(rateTitle) 播放"
        }
    }
}
