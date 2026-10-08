import SwiftUI

struct DynamicCommentText: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let content: CommentContent?
    let font: Font
    let textColor: Color
    let emoteSize: CGFloat
    let leadingName: String?
    let leadingNameColor: Color
    let typographyRole: AppTypography.Role?
    let onNonLinkTap: (() -> Void)?

    init(
        content: CommentContent?,
        font: Font,
        textColor: Color,
        emoteSize: CGFloat,
        leadingName: String? = nil,
        leadingNameColor: Color = .pink,
        typographyRole: AppTypography.Role? = nil,
        onNonLinkTap: (() -> Void)? = nil
    ) {
        self.content = content
        self.font = font
        self.textColor = textColor
        self.emoteSize = emoteSize
        self.leadingName = leadingName
        self.leadingNameColor = leadingNameColor
        self.typographyRole = typographyRole
        self.onNonLinkTap = onNonLinkTap
    }

    var body: some View {
        BiliEmoteText(
            content: content,
            font: resolvedFont,
            textColor: textColor,
            emoteSize: emoteSize,
            leadingName: leadingName,
            leadingNameColor: leadingNameColor,
            lineSpacing: CommentTypography.bodyLineSpacing,
            typographyRole: typographyRole,
            onNonLinkTap: onNonLinkTap
        )
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }

    private var resolvedFont: Font {
        guard let typographyRole else {
            return font
        }
        return Font(typographyRole.uiFont(contentSizeCategory: dynamicTypeSize.uiContentSizeCategory))
    }
}

enum DynamicCommentTextBuilder {
    static func nameAndMessage(
        name: String,
        message: String,
        font: Font,
        contentColor: Color,
        nameColor: Color = .secondary,
        replyTargetColor: Color
    ) -> AttributedString {
        var user = AttributedString("\(name)：")
        user.font = font.weight(.semibold)
        user.foregroundColor = nameColor

        return user + replyMessage(
            message,
            font: font,
            contentColor: contentColor,
            replyTargetColor: replyTargetColor
        )
    }

    static func replyMessage(
        _ message: String,
        font: Font,
        contentColor: Color,
        replyTargetColor: Color = .secondary
    ) -> AttributedString {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let split = replyPrefixSplit(in: text) else {
            var content = AttributedString(text)
            content.font = font
            content.foregroundColor = contentColor
            return content
        }

        var verb = AttributedString("回复 ")
        verb.font = font
        verb.foregroundColor = contentColor

        var target = AttributedString(split.target)
        target.font = font.weight(.semibold)
        target.foregroundColor = replyTargetColor

        var separator = AttributedString(split.separator)
        separator.font = font
        separator.foregroundColor = contentColor

        var content = AttributedString(split.content)
        content.font = font
        content.foregroundColor = contentColor

        return verb + target + separator + content
    }

    static func hasReplyTarget(in message: String?) -> Bool {
        guard let message else { return false }
        return replyPrefixSplit(in: message.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    private static func replyPrefixSplit(in message: String) -> (target: String, separator: String, content: String)? {
        let supportedVerbs = ["回复", "回覆", "回復"]
        guard let verb = supportedVerbs.first(where: { message.hasPrefix($0) }) else { return nil }

        var cursor = message.index(message.startIndex, offsetBy: verb.count)
        while cursor < message.endIndex, message[cursor].isWhitespace {
            cursor = message.index(after: cursor)
        }

        guard cursor < message.endIndex, message[cursor] == "@" else { return nil }
        guard let colon = message[cursor...].firstIndex(where: { $0 == ":" || $0 == "：" }) else { return nil }

        let prefixEnd = message.index(after: colon)
        let target = String(message[cursor..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = String(message[colon..<prefixEnd])
        let content = String(message[prefixEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return nil }
        return (target, separator, content)
    }
}
