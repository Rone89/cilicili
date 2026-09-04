import SwiftUI

/// Shared primary title treatment for playback detail pages.
struct PlaybackDetailTitleText: View {
    @Environment(\.appTypographyMode) private var typographyMode

    let text: String
    let lineLimit: Int?
    let typographyRole: AppTypography.Role

    init(
        text: String,
        lineLimit: Int? = 1,
        typographyRole: AppTypography.Role = .videoDetailTitle
    ) {
        self.text = text
        self.lineLimit = lineLimit
        self.typographyRole = typographyRole
    }

    var body: some View {
        Text(text)
            .appTypography(typographyRole, fallback: .callout.weight(.semibold))
            .lineSpacing(typographyMode == .nativeRefined ? 0 : 1.5)
            .foregroundStyle(.primary)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
