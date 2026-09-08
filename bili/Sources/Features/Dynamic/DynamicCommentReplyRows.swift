import SwiftUI

struct DynamicCommentReplyRootView: View {
    @Environment(\.usesDynamicDetailCommentSpacing) private var usesRefinedSpacing

    let comment: Comment
    let reply: (() -> Void)?
    private let display: DynamicCommentRowDisplayModel

    init(
        comment: Comment,
        reply: (() -> Void)? = nil
    ) {
        self.comment = comment
        self.reply = reply
        self.display = DynamicCommentRowDisplayModel(comment: comment)
    }

    var body: some View {
        DynamicCommentFullRowReplyTarget(
            action: reply,
            accessibilityLabel: "回复 \(display.authorName) 的评论"
        ) {
            HStack(alignment: .top, spacing: 10) {
                DynamicCommentAvatar(
                    urlString: display.avatarURLString,
                    owner: display.authorOwner,
                    size: 40
                )

                VStack(alignment: .leading, spacing: usesRefinedSpacing ? 0 : 6) {
                    DynamicCommentReplyAuthorLine(
                        comment: comment,
                        display: display,
                        showsLike: true,
                        avatarHeight: 40
                    )
                    DynamicCommentText(
                        content: comment.content,
                        font: .subheadline,
                        textColor: .primary,
                        emoteSize: 22,
                        lineSpacing: 1,
                        typographyRole: .commentBody,
                        onNonLinkTap: reply
                    )
                    .padding(.top, usesRefinedSpacing ? 4 : 0)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: usesRefinedSpacing ? nil : 44,
                        alignment: .leading
                    )
                    .fixedSize(horizontal: false, vertical: true)

                    if usesRefinedSpacing {
                        if !display.pictures.isEmpty {
                            DynamicCommentImageGrid(images: display.pictures)
                                .padding(.top, 8)
                        }
                    } else {
                        DynamicCommentImageGrid(images: display.pictures)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            }
            .padding(.vertical, usesRefinedSpacing ? 10 : 0)
        }
    }
}

struct DynamicCommentReplyDetailRow: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    @Environment(\.usesDynamicDetailCommentSpacing) private var usesRefinedSpacing

    let item: DynamicCommentReplyItem
    let showDialog: (() -> Void)?
    let replyAction: (() -> Void)?

    private var reply: Comment {
        item.reply
    }

    private var display: DynamicCommentRowDisplayModel {
        item.display
    }

    init(
        item: DynamicCommentReplyItem,
        showDialog: (() -> Void)?,
        reply: (() -> Void)? = nil
    ) {
        self.item = item
        self.showDialog = showDialog
        self.replyAction = reply
    }

    var body: some View {
        DynamicCommentFullRowReplyTarget(
            action: replyAction,
            accessibilityLabel: "回复 \(display.authorName) 的评论"
        ) {
            HStack(alignment: .top, spacing: 10) {
                DynamicCommentAvatar(
                    urlString: display.avatarURLString,
                    owner: display.authorOwner,
                    size: 36
                )

                VStack(alignment: .leading, spacing: usesRefinedSpacing ? 0 : 8) {
                    DynamicCommentReplyAuthorLine(
                        comment: reply,
                        display: display,
                        showsLike: true
                    )
                    .accessibilityIdentifier("ui.dynamicComments.reply.author.\(item.id)")
                    DynamicCommentText(
                        content: reply.content,
                        font: .subheadline,
                        textColor: .primary,
                        emoteSize: 22,
                        lineSpacing: 1,
                        typographyRole: .commentBody,
                        onNonLinkTap: replyAction
                    )
                    .padding(.top, usesRefinedSpacing ? 4 : 0)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: usesRefinedSpacing ? nil : 44,
                        alignment: .leading
                    )
                    .fixedSize(horizontal: false, vertical: true)

                    if usesRefinedSpacing {
                        if !display.pictures.isEmpty {
                            DynamicCommentImageGrid(images: display.pictures)
                                .padding(.top, 8)
                        }
                    } else {
                        DynamicCommentImageGrid(images: display.pictures)
                    }

                    if let showDialog {
                        Button(action: showDialog) {
                            Label("查看对话", systemImage: "text.bubble")
                                .appTypography(.action, fallback: .caption.weight(.semibold))
                                .frame(height: 26)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(appTintColor)
                        .padding(.top, usesRefinedSpacing ? 8 : 2)
                        .zIndex(1)
                        .dynamicCommentHitArea(.control)
                        .accessibilityIdentifier("dynamic.comment.reply.showDialog.\(item.id)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            }
            .padding(.vertical, usesRefinedSpacing ? 10 : 9)
        }
    }
}

struct DynamicCommentDialogRow: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    @Environment(\.usesDynamicDetailCommentSpacing) private var usesRefinedSpacing

    let item: DynamicCommentDialogItem
    let isFocused: Bool
    let replyAction: (() -> Void)?

    private var reply: Comment {
        item.reply
    }

    private var display: DynamicCommentRowDisplayModel {
        item.display
    }

    init(
        item: DynamicCommentDialogItem,
        isFocused: Bool,
        reply: (() -> Void)? = nil
    ) {
        self.item = item
        self.isFocused = isFocused
        replyAction = reply
    }

    var body: some View {
        DynamicCommentFullRowReplyTarget(
            action: replyAction,
            accessibilityLabel: "回复 \(display.authorName) 的评论"
        ) {
            HStack(alignment: .top, spacing: 10) {
                DynamicCommentAvatar(
                    urlString: display.avatarURLString,
                    owner: display.authorOwner,
                    size: 36
                )

                VStack(alignment: .leading, spacing: usesRefinedSpacing ? 0 : 11) {
                    DynamicCommentReplyAuthorLine(comment: reply, display: display, showsLike: true)
                        .accessibilityIdentifier("ui.dynamicComments.dialog.author.\(item.id)")
                    DynamicCommentText(
                        content: reply.content,
                        font: .subheadline,
                        textColor: .primary,
                        emoteSize: 22,
                        lineSpacing: 2,
                        typographyRole: .commentBody,
                        onNonLinkTap: replyAction
                    )
                    .padding(.top, usesRefinedSpacing ? 4 : 0)
                    .fixedSize(horizontal: false, vertical: true)

                    if usesRefinedSpacing {
                        if !display.pictures.isEmpty {
                            DynamicCommentImageGrid(images: display.pictures)
                                .padding(.top, 8)
                        }
                    } else {
                        DynamicCommentImageGrid(images: display.pictures)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            }
        }
        .padding(.vertical, 10)
        .background(isFocused ? appTintColor.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
