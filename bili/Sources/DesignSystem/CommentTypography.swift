import SwiftUI

enum CommentTypography {
    static let bodyLineSpacing: CGFloat = 2
}

/// Comment-only entry point. Other uses of BiliEmoteText retain their own typography.
struct CommentBodyText: View {
    let content: CommentContent?
    var font: Font = .subheadline
    var textColor: Color = .primary
    var emoteSize: CGFloat = 22
    var leadingName: String? = nil
    var leadingNameColor: Color = .pink
    var showsLinkButtons: Bool = true
    var typographyRole: AppTypography.Role? = .commentBody
    var onNonLinkTap: (() -> Void)? = nil

    var body: some View {
        BiliEmoteText(
            content: content, font: font, textColor: textColor, emoteSize: emoteSize,
            leadingName: leadingName, leadingNameColor: leadingNameColor,
            lineSpacing: CommentTypography.bodyLineSpacing,
            showsLinkButtons: showsLinkButtons, typographyRole: typographyRole,
            onNonLinkTap: onNonLinkTap
        )
    }
}
