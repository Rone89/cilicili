import SwiftUI

struct DynamicCommentReplyRootView: View {
    let comment: Comment
    private let display: DynamicCommentRowDisplayModel

    init(comment: Comment) {
        self.comment = comment
        self.display = DynamicCommentRowDisplayModel(comment: comment)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            DynamicCommentAvatar(urlString: display.avatarURLString, size: 40)

            VStack(alignment: .leading, spacing: 8) {
                DynamicCommentReplyAuthorLine(display: display, showsLike: false)
                DynamicCommentReplyBody(comment: comment, display: display)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
    }
}

struct DynamicCommentReplyDetailRow: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    let item: DynamicCommentReplyItem
    let showDialog: (() -> Void)?

    private var reply: Comment {
        item.reply
    }

    private var display: DynamicCommentRowDisplayModel {
        item.display
    }

    init(item: DynamicCommentReplyItem, showDialog: (() -> Void)?) {
        self.item = item
        self.showDialog = showDialog
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            DynamicCommentAvatar(urlString: display.avatarURLString, size: 36)

            VStack(alignment: .leading, spacing: 6) {
                DynamicCommentReplyAuthorLine(display: display, showsLike: true)
                DynamicCommentReplyBody(comment: reply, display: display)

                if let showDialog {
                    Button(action: showDialog) {
                        Label("查看对话", systemImage: "text.bubble")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(appTintColor)
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
        .padding(.vertical, 12)
    }
}

struct DynamicCommentDialogRow: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    let item: DynamicCommentDialogItem
    let isFocused: Bool

    private var reply: Comment {
        item.reply
    }

    private var display: DynamicCommentRowDisplayModel {
        item.display
    }

    init(item: DynamicCommentDialogItem, isFocused: Bool) {
        self.item = item
        self.isFocused = isFocused
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            DynamicCommentAvatar(urlString: display.avatarURLString, size: 36)

            VStack(alignment: .leading, spacing: 6) {
                DynamicCommentReplyAuthorLine(display: display, showsLike: true)
                DynamicCommentReplyBody(comment: reply, display: display)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, isFocused ? 10 : 0)
        .background(isFocused ? appTintColor.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
