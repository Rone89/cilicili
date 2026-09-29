import SwiftUI
import UIKit

enum CommentInteractionSettings {
    // Keep the persisted key so the user's existing switch choice survives the gesture change.
    static let longPressActionsEnabledKey = "cc.bili.commentTapActionsEnabled.v1"
}

@MainActor
enum CommentCopyAction {
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}

private struct CommentCopyContextMenu: ViewModifier {
    let text: String?
    let title: String

    func body(content: Content) -> some View {
        if let copyText = text?.commentCopyText {
            content.contextMenu {
                Button {
                    CommentCopyAction.copy(copyText)
                } label: {
                    Label(title, systemImage: "doc.on.doc")
                }
            }
        } else {
            content
        }
    }
}

extension View {
    func commentCopyContextMenu(
        text: String?,
        title: String
    ) -> some View {
        modifier(
            CommentCopyContextMenu(
                text: text,
                title: title
            )
        )
    }

    func commentActionsMenu(
        longPressEnabled: Bool,
        text: String?,
        copyTitle: String,
        replyAction: (() -> Void)?
    ) -> some View {
        modifier(
            CommentActionsMenu(
                longPressEnabled: longPressEnabled,
                text: text,
                copyTitle: copyTitle,
                replyAction: replyAction
            )
        )
    }
}

private struct CommentActionsMenu: ViewModifier {
    let longPressEnabled: Bool
    let text: String?
    let copyTitle: String
    let replyAction: (() -> Void)?

    func body(content: Content) -> some View {
        if longPressEnabled && (text?.commentCopyText != nil || replyAction != nil) {
            content.contextMenu {
                if let copyText = text?.commentCopyText {
                    Button(copyTitle) {
                        CommentCopyAction.copy(copyText)
                    }
                }
                if let replyAction {
                    Button("回复", action: replyAction)
                }
            }
        } else {
            content
        }
    }
}

private extension String {
    var commentCopyText: String? {
        let value = removingHTMLTags()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
