import SwiftUI

struct CommentMetricBadge: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    let text: String
    let systemImage: String
    let isHighlighted: Bool

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .foregroundStyle(isHighlighted ? appTintColor : .secondary)
            .frame(height: 24)
    }
}
