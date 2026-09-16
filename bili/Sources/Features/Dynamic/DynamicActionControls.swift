import SwiftUI

struct DynamicActionButton: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(isSelected ? appTintColor : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .dynamicActionHitTarget()
        }
        .buttonStyle(.plain)
    }
}

struct DynamicActionPill: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    @Environment(\.videoDetailActionButtonStyle) private var actionButtonStyle
    let title: String
    let systemImage: String
    let isSelected: Bool
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        let usesPlainStyle = actionButtonStyle.usesPlainStyle
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, minHeight: 28)
                .padding(.horizontal, 3)
                .dynamicActionHitTarget()
        }
        .dynamicActionButtonAppearance(
            usesPlainStyle: usesPlainStyle,
            prominent: isSelected
        )
        .tint(isSelected ? appTintColor : .secondary)
        .disabled(isDisabled)
    }
}

struct DynamicActionPillLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .allowsTightening(true)
            .frame(maxWidth: .infinity, minHeight: 28)
            .padding(.horizontal, 3)
            .dynamicActionHitTarget()
    }
}

extension View {
    @ViewBuilder
    func dynamicActionButtonAppearance(
        usesPlainStyle: Bool,
        prominent: Bool
    ) -> some View {
        if usesPlainStyle {
            self
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
        } else {
            self
                .biliGlassButtonStyle(prominent: prominent)
                .controlSize(.small)
        }
    }

    /// Preserve the compact visual pill while giving the underlying control
    /// the 44pt minimum touch target used by the system.
    func dynamicActionHitTarget() -> some View {
        padding(.vertical, 8)
            .contentShape(Rectangle())
            .padding(.vertical, -8)
    }
}

struct DynamicActionFeedbackToast: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .biliGlassEffect(interactive: false, in: Capsule())
            .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
            .accessibilityLabel(message)
    }
}
