import SwiftUI

struct VideoDetailActionStripIconButton: View {
    let accessibilityTitle: String
    let systemImage: String
    let foregroundStyle: Color
    let isDisabled: Bool
    let action: () -> Void
    let usesPlainStyle: Bool

    init(
        accessibilityTitle: String,
        systemImage: String,
        foregroundStyle: Color,
        isDisabled: Bool,
        action: @escaping () -> Void,
        usesPlainStyle: Bool = false
    ) {
        self.accessibilityTitle = accessibilityTitle
        self.systemImage = systemImage
        self.foregroundStyle = foregroundStyle
        self.isDisabled = isDisabled
        self.action = action
        self.usesPlainStyle = usesPlainStyle
    }

    var body: some View {
        Button(action: action) {
            VideoDetailActionStripIconLabel(
                systemImage: systemImage,
                foregroundStyle: foregroundStyle,
                side: usesPlainStyle
                    ? VideoDetailActionStrip.Metrics.plainActionLabelSide
                    : VideoDetailActionStrip.Metrics.actionLabelSide,
                iconSize: usesPlainStyle
                    ? VideoDetailActionStrip.Metrics.plainIconSize
                    : VideoDetailActionStrip.Metrics.iconSize
            )
        }
        .videoDetailActionStripButtonAppearance(
            shape: .circle,
            usesPlainStyle: usesPlainStyle,
            tint: usesPlainStyle ? foregroundStyle : nil
        )
        // Keep the full column tappable while the icon remains visually unadorned.
        .contentShape(Rectangle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.52 : 1)
        .accessibilityLabel(accessibilityTitle)
    }
}

enum VideoDetailActionStripButtonShape {
    case circle
    case capsule
}

private struct VideoDetailActionStripButtonAppearanceModifier: ViewModifier {
    let shape: VideoDetailActionStripButtonShape
    let usesPlainStyle: Bool
    let prominent: Bool
    let tint: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        if usesPlainStyle {
            switch shape {
            case .circle:
                content
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.regular)
                    .tint(tint ?? .secondary)
            case .capsule:
                if prominent {
                    content
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .controlSize(.regular)
                        .tint(tint ?? .secondary)
                } else {
                    content
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.regular)
                        .tint(tint ?? .secondary)
                }
            }
        } else {
            switch shape {
            case .circle:
                content
                    .buttonBorderShape(.circle)
                    .controlSize(.mini)
                    .biliGlassButtonStyle(prominent: prominent)
            case .capsule:
                content
                    .buttonBorderShape(.capsule)
                    .controlSize(.mini)
                    .biliGlassButtonStyle(prominent: prominent)
            }
        }
    }
}

extension View {
    func videoDetailActionStripButtonAppearance(
        shape: VideoDetailActionStripButtonShape,
        usesPlainStyle: Bool,
        prominent: Bool = false,
        tint: Color? = nil
    ) -> some View {
        modifier(
            VideoDetailActionStripButtonAppearanceModifier(
                shape: shape,
                usesPlainStyle: usesPlainStyle,
                prominent: prominent,
                tint: tint
            )
        )
    }
}
