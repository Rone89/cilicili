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
                side: VideoDetailActionStrip.Metrics.actionLabelSide,
                iconSize: VideoDetailActionStrip.Metrics.iconSize
            )
        }
        .videoDetailActionStripButtonAppearance(
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

private struct VideoDetailActionStripButtonAppearanceModifier: ViewModifier {
    let usesPlainStyle: Bool
    let tint: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        if usesPlainStyle {
            content
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.regular)
                .tint(tint ?? .secondary)
        } else {
            content
                .buttonBorderShape(.circle)
                .controlSize(.regular)
                .biliGlassButtonStyle()
        }
    }
}

extension View {
    func videoDetailActionStripButtonAppearance(
        usesPlainStyle: Bool,
        tint: Color? = nil
    ) -> some View {
        modifier(VideoDetailActionStripButtonAppearanceModifier(usesPlainStyle: usesPlainStyle, tint: tint))
    }
}
