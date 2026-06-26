import SwiftUI

struct VideoCoverGlassBadge<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.86)
            .allowsTightening(true)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .glassEffect(
                .regular,
                in: .capsule
            )
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: 146, alignment: .leading)
            .clipped()
    }
}

struct VideoCoverDurationBadge: View {
    let duration: String
    private let maxWidth: CGFloat

    init(_ duration: String, maxWidth: CGFloat = 96) {
        self.duration = duration
        self.maxWidth = maxWidth
    }

    var body: some View {
        Text(duration)
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.86)
            .allowsTightening(true)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .biliPlayerClearGlass(interactive: false, in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: maxWidth, alignment: .trailing)
            .clipped()
            .accessibilityLabel("视频时长 \(duration)")
    }
}

struct VideoCoverViewCountBadge: View {
    let viewText: String

    init(_ viewText: String) {
        self.viewText = viewText
    }

    var body: some View {
        Label(viewText, systemImage: "play.fill")
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.86)
            .allowsTightening(true)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .glassEffect(
                .regular,
                in: .capsule
            )
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: 112, alignment: .leading)
            .clipped()
            .accessibilityLabel("观看次数 \(viewText)")
    }
}

struct VideoCoverPlayBadge: View {
    var size: CGFloat = 40
    var iconSize: CGFloat = 15

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            Image(systemName: "play.fill")
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: 1)
                .frame(width: size, height: size)
                .biliPlayerClearGlass(interactive: false, in: Circle())
                .videoCoverControlShadow()
                .accessibilityHidden(true)
        }
    }
}

struct VideoCoverBottomScrim: View {
    var opacity: Double = 0.20
    var heightFraction: CGFloat = 1.0 / 4.0

    var body: some View {
        GeometryReader { proxy in
            LinearGradient(
                colors: [
                    .clear,
                    .black.opacity(opacity)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: max(proxy.size.height * min(max(heightFraction, 0), 1), 0))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private extension View {
    func videoCoverControlShadow() -> some View {
        shadow(color: .black.opacity(0.28), radius: 8, x: 0, y: 4)
            .shadow(color: .black.opacity(0.16), radius: 2, x: 0, y: 1)
    }
}
