#if DEBUG
import SwiftUI

struct UITestCommentLocationFixtureView: View {
    private let isDynamic = ProcessInfo.processInfo.arguments.contains("--comment-location-dynamic")

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isDynamic {
                        DynamicCommentRowHeader(comment: Self.main, display: DynamicCommentRowDisplayModel(comment: Self.main))
                        DynamicCommentReplyRootView(comment: Self.root)
                        DynamicCommentReplyDetailRow(
                            item: DynamicCommentReplyItem(reply: Self.reply, rootComment: Self.root),
                            showDialog: nil
                        )
                        DynamicCommentDialogRow(item: DynamicCommentDialogItem(reply: Self.dialog), isFocused: false)
                        DynamicCommentRowHeader(comment: Self.missing, display: DynamicCommentRowDisplayModel(comment: Self.missing))
                    } else {
                        CommentRowHeader(comment: Self.main, display: VideoDetailCommentDisplayModel(comment: Self.main))
                        CommentReplyRootView(comment: Self.root)
                        CommentReplyDetailRow(
                            item: VideoDetailCommentReplyDisplayItem(
                                id: Self.reply.id,
                                reply: Self.reply,
                                display: VideoDetailCommentDisplayModel(comment: Self.reply),
                                canShowDialog: false
                            ),
                            showDialog: nil
                        )
                        CommentDialogRow(item: VideoDetailCommentDialogDisplayItem(reply: Self.dialog), isFocused: false)
                        CommentRowHeader(comment: Self.missing, display: VideoDetailCommentDisplayModel(comment: Self.missing))
                    }
                }
                .padding(20)
            }
            .navigationTitle("评论属地验证")
        }
    }

    private static let main = sample(1, name: "主评论", location: "IP属地：广东")
    private static let root = sample(2, name: "回复根评论", location: "IP属地：上海")
    private static let reply = sample(3, name: "回复", location: "IP属地：北京")
    private static let dialog = sample(4, name: "对话", location: "IP属地：四川")
    private static let missing = sample(5, name: "无属地的评论", location: nil)

    private static func sample(_ id: Int, name: String, location: String?) -> Comment {
        var json: [String: Any] = [
            "rpid": id,
            "member": ["uname": name],
            "content": ["message": "测试正文"],
            "ctime": 1_700_000_000,
        ]
        if let location {
            json["reply_control"] = ["location": location]
        }
        return try! JSONDecoder().decode(Comment.self, from: JSONSerialization.data(withJSONObject: json))
    }
}
#endif
