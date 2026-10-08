#if DEBUG
import SwiftUI

struct UITestCommentSpacingFixtureView: View {
    @StateObject private var libraryStore: LibraryStore
    init() {
        let suite = "cc.bili.ui-tests.comment-spacing"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        _libraryStore = StateObject(wrappedValue: LibraryStore(userDefaults: defaults))
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(Self.samples.enumerated()), id: \.offset) { index, message in
                        CommentSpacingSampleRow(id: String(index), message: message)
                    }
                }.padding(20)
            }
            .navigationTitle("评论行距验证")

        }
        .environmentObject(libraryStore)
        .environment(\.dynamicTypeSize, ProcessInfo.processInfo.arguments.contains("--comment-spacing-accessibility") ? .accessibility3 : .large)
    }
    private static let samples = [
        "单行中文评论", "第一行中文\n第二行中文\n第三行中文",
        "中文 English 123\n中英文混排", "🥰👨‍👩‍👧‍👦\n原生 emoji 🐈",
        "图片表情 [doge]\n第二行 [doge]", "@用户\n提及用户的评论",
        "https://example.com\n包含链接的评论", "回复 @用户：正文\n第二行正文",
        "第一行 [doge]\n第二行 @用户\n第三行 🥰𰻞"
    ]
}

private struct CommentSpacingSampleRow: View {
    let id: String
    let content: CommentContent
    @State private var dynamicHeight: CGFloat = 0
    @State private var videoHeight: CGFloat = 0
    init(id: String, message: String) {
        self.id = id
        let json: [String: Any] = ["message": message, "at_name_to_mid": ["用户": 1],
            "emote": ["[doge]": ["text": "[doge]", "url": "https://i0.hdslb.com/bfs/emote/6ea59c827c414b4a2955fe79e0f6fd3dcd515e24.png"]]]
        content = try! JSONDecoder.bili.decode(CommentContent.self, from: JSONSerialization.data(withJSONObject: json))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("样例 \(id)")
            DynamicCommentText(content: content, font: .subheadline, textColor: .primary, emoteSize: 21, typographyRole: .commentBody)
                .commentActionsMenu(longPressEnabled: true, text: content.message, copyTitle: "复制评论", replyAction: nil)
                .accessibilityIdentifier("comment.sample.dynamic.\(id)")
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { _, value in dynamicHeight = value }
            Text(String(format: "%.1f", dynamicHeight)).accessibilityIdentifier("comment.height.dynamic.\(id)")
            CommentBodyText(content: content, emoteSize: 21)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { _, value in videoHeight = value }
            Text(String(format: "%.1f", videoHeight)).accessibilityIdentifier("comment.height.video.\(id)")
        }
    }
}
#endif
