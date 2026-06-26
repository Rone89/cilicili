import SwiftUI

struct DynamicActionButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(isSelected ? .pink : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct DynamicActionPill: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, minHeight: 28)
                .padding(.horizontal, 3)
        }
        .biliGlassButtonStyle(prominent: isSelected)
        .controlSize(.small)
        .tint(isSelected ? .pink : .secondary)
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
            .glassEffect(.regular.tint(.white.opacity(0.18)).interactive(false), in: Capsule())
            .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
            .accessibilityLabel(message)
    }
}
