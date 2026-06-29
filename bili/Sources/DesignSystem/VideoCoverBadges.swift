import SwiftUI

enum VideoCoverOverlayStyle: String, CaseIterable, Identifiable {
    case gradient
    case durationBackground

    static let storageKey = "cc.bili.display.videoCoverOverlayStyle.v1"
    static let defaultStyle: VideoCoverOverlayStyle = .gradient
    static let badgeBackgroundOpacity = 0.36
    static let badgeBorderOpacity = 0.14

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gradient:
            return "封面渐变遮罩"
        case .durationBackground:
            return "仅时长底色"
        }
    }

    var subtitle: String {
        switch self {
        case .gradient:
            return "封面底部加黑色渐变，时长保持玻璃样式"
        case .durationBackground:
            return "不遮住封面，只给时长加半透黑底"
        }
    }

    static func normalized(rawValue: String?) -> VideoCoverOverlayStyle {
        guard let rawValue,
              let style = VideoCoverOverlayStyle(rawValue: rawValue)
        else { return defaultStyle }
        return style
    }
}

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
    @AppStorage(VideoCoverOverlayStyle.storageKey) private var overlayStyleRawValue = VideoCoverOverlayStyle.defaultStyle.rawValue
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
            .modifier(VideoCoverBadgeBackground(style: overlayStyle, shape: Capsule()))
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: maxWidth, alignment: .trailing)
            .clipped()
            .accessibilityLabel("视频时长 \(duration)")
    }

    private var overlayStyle: VideoCoverOverlayStyle {
        VideoCoverOverlayStyle.normalized(rawValue: overlayStyleRawValue)
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
    @AppStorage(VideoCoverOverlayStyle.storageKey) private var overlayStyleRawValue = VideoCoverOverlayStyle.defaultStyle.rawValue
    var size: CGFloat = 40
    var iconSize: CGFloat = 15

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            Image(systemName: "play.fill")
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: 1)
                .frame(width: size, height: size)
                .modifier(VideoCoverBadgeBackground(style: overlayStyle, shape: Circle()))
                .videoCoverControlShadow()
                .accessibilityHidden(true)
        }
    }

    private var overlayStyle: VideoCoverOverlayStyle {
        VideoCoverOverlayStyle.normalized(rawValue: overlayStyleRawValue)
    }
}

struct VideoCoverBottomScrim: View {
    @AppStorage(VideoCoverOverlayStyle.storageKey) private var overlayStyleRawValue = VideoCoverOverlayStyle.defaultStyle.rawValue
    var opacity: Double = 0.20
    var heightFraction: CGFloat = 1.0 / 4.0

    var body: some View {
        Group {
            if overlayStyle == .gradient {
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
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var overlayStyle: VideoCoverOverlayStyle {
        VideoCoverOverlayStyle.normalized(rawValue: overlayStyleRawValue)
    }
}

private struct VideoCoverBadgeBackground<BadgeShape: InsettableShape>: ViewModifier {
    let style: VideoCoverOverlayStyle
    let shape: BadgeShape

    func body(content: Content) -> some View {
        switch style {
        case .gradient:
            content.biliPlayerClearGlass(interactive: false, in: shape)
        case .durationBackground:
            content
                .background(.black.opacity(VideoCoverOverlayStyle.badgeBackgroundOpacity), in: shape)
                .overlay {
                    shape
                        .strokeBorder(.white.opacity(VideoCoverOverlayStyle.badgeBorderOpacity), lineWidth: 0.6)
                }
        }
    }
}

private extension View {
    func videoCoverControlShadow() -> some View {
        shadow(color: .black.opacity(0.28), radius: 8, x: 0, y: 4)
            .shadow(color: .black.opacity(0.16), radius: 2, x: 0, y: 1)
    }
}
