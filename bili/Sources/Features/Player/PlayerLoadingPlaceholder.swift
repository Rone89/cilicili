import SwiftUI

struct PlayerLoadingPlaceholder: View {
    let progress: Double
    let message: String
    let isFinishing: Bool
    var secondaryMessage: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let accentColor = Color(red: 1.0, green: 0.36, blue: 0.58)

    private var normalizedProgress: Double {
        min(max(progress, 0), 1)
    }

    private var displayMessage: String {
        isFinishing ? "即将开始播放" : message
    }

    private var supportingMessage: String {
        if let secondaryMessage {
            return secondaryMessage
        }
        if isFinishing {
            return "正在切入画面"
        }
        switch normalizedProgress {
        case ..<0.16:
            return "准备请求"
        case ..<0.45:
            return "正在建立连接"
        case ..<0.78:
            return "正在准备音视频轨道"
        case ..<0.96:
            return "等待首帧"
        default:
            return "马上开始"
        }
    }

    private var supportingIcon: String {
        secondaryMessage == nil ? "bolt.horizontal.circle" : "wifi.exclamationmark"
    }

    private var progressPercent: Int {
        Int((normalizedProgress * 100).rounded())
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 8) {
                    HStack(spacing: 9) {
                        PlayerLoadingSpinner(size: 22, lineWidth: 2.3, accentColor: Self.accentColor)

                        Text(displayMessage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .contentTransition(.opacity)
                    }

                    if secondaryMessage != nil || normalizedProgress >= 0.18 || isFinishing {
                        Label(supportingMessage, systemImage: supportingIcon)
                            .font(.caption2.weight(.medium))
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(secondaryMessage == nil ? Color.white.opacity(0.54) : Color.white.opacity(0.72))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .contentTransition(.opacity)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, 22)

                Spacer(minLength: 0)
            }
            .opacity(isFinishing ? 0.74 : 1)
            .scaleEffect(isFinishing ? 0.98 : 1)
            .blur(radius: isFinishing && !reduceMotion ? 0.35 : 0)
            .animation(.smooth(duration: 0.22), value: isFinishing)
            .animation(.smooth(duration: 0.22), value: normalizedProgress)

            VStack(spacing: 5) {
                PlayerLoadingProgressBar(
                    progress: normalizedProgress,
                    width: nil,
                    height: 2.5,
                    accentColor: Self.accentColor
                )

                Text("\(progressPercent)%")
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(.white.opacity(0.48))
                    .contentTransition(.numericText())
                    .accessibilityLabel("加载进度 \(progressPercent)%")
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
            .opacity(isFinishing ? 0.4 : 1)
            .animation(.smooth(duration: 0.22), value: isFinishing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PlayerLoadingSpinner: View {
    var size: CGFloat = 28
    var lineWidth: CGFloat = 2.4
    var accentColor = Color(red: 1.0, green: 0.36, blue: 0.58)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.14), lineWidth: lineWidth)

            Circle()
                .trim(from: 0.12, to: 0.80)
                .stroke(
                    accentColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(reduceMotion ? 0 : (isAnimating ? 360 : 0)))
        }
        .frame(width: size, height: size)
        .shadow(color: accentColor.opacity(0.26), radius: 6, y: 1)
        .animation(
            reduceMotion ? nil : .linear(duration: 1.05).repeatForever(autoreverses: false),
            value: isAnimating
        )
        .onAppear {
            isAnimating = !reduceMotion
        }
        .onDisappear {
            isAnimating = false
        }
        .accessibilityHidden(true)
    }
}

struct PlayerLoadingProgressBar: View {
    let progress: Double
    var width: CGFloat? = 150
    var height: CGFloat = 3
    var accentColor = Color(red: 1.0, green: 0.36, blue: 0.58)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulseOffset: CGFloat = -1

    private var normalizedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let fillWidth = normalizedProgress <= 0 ? 0 : max(height, proxy.size.width * normalizedProgress)
            let pulseWidth = max(24, proxy.size.width * 0.18)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.14))

                Capsule()
                    .fill(accentColor)
                    .frame(width: fillWidth)
                    .shadow(color: accentColor.opacity(0.28), radius: 5, y: 1)

                if !reduceMotion && normalizedProgress < 0.985 {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.42), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: pulseWidth)
                        .offset(x: pulseOffset * (proxy.size.width + pulseWidth) - pulseWidth)
                        .blendMode(.plusLighter)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(width: width, height: height)
        .animation(.smooth(duration: 0.22), value: normalizedProgress)
        .onAppear {
            guard !reduceMotion else { return }
            pulseOffset = 1
        }
        .onDisappear {
            pulseOffset = -1
        }
        .animation(
            reduceMotion ? nil : .linear(duration: 1.35).repeatForever(autoreverses: false),
            value: pulseOffset
        )
        .accessibilityHidden(true)
    }
}
