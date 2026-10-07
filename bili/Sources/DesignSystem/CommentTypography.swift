import SwiftUI

enum CommentTypography {
    static let bodyLineSpacing: CGFloat = 2

    static func resolvedBodyLineSpacing(legacy: CGFloat, experimentEnabled: Bool) -> CGFloat {
        experimentEnabled ? bodyLineSpacing : legacy
    }
}

/// Comment-only entry point. Other uses of BiliEmoteText retain their own typography.
struct CommentBodyText: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let content: CommentContent?
    var font: Font = .subheadline
    var textColor: Color = .primary
    var emoteSize: CGFloat = 22
    var leadingName: String? = nil
    var leadingNameColor: Color = .pink
    var showsLinkButtons: Bool = true
    var legacyLineSpacing: CGFloat = 0
    var legacyOuterLineSpacing: CGFloat? = nil
    var typographyRole: AppTypography.Role? = .commentBody
    var onNonLinkTap: (() -> Void)? = nil

    var body: some View {
        let enabled = libraryStore.commentTextTypographyUnificationExperimentEnabled
        let text = BiliEmoteText(
            content: content, font: font, textColor: textColor, emoteSize: emoteSize,
            leadingName: leadingName, leadingNameColor: leadingNameColor,
            lineSpacing: CommentTypography.resolvedBodyLineSpacing(legacy: legacyLineSpacing, experimentEnabled: enabled),
            showsLinkButtons: showsLinkButtons, typographyRole: typographyRole,
            onNonLinkTap: onNonLinkTap
        )
        if !enabled, let legacyOuterLineSpacing {
            text.lineSpacing(legacyOuterLineSpacing)
        } else {
            text
        }
    }
}
