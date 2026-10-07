#if DEBUG
import SwiftUI

/// Production body views, production spacing, and examples A–I for spacing validation.
struct UITestDynamicSpacingFixtureView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var path = NavigationPath()
    @State private var expanded: [String: Bool] = [:]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(Self.samples, id: \.id) { sample in
                        DynamicSpacingSampleRow(sample: sample, isExpanded: Binding(
                            get: { expanded[sample.id, default: false] },
                            set: { expanded[sample.id] = $0 }
                        ))
                    }
                    DynamicSpacingOriginalRow()
                    DynamicSpacingCommentRow()
                }
                .padding(20)
            }
            .navigationTitle("动态间距验证")
            .dynamicDetailDestinations(path: $path, api: dependencies.api)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("动态详情", value: DynamicDetailTarget.loaded(Self.detailItem))
                        .accessibilityIdentifier("spacing.detail")
                }
            }
        }
        .environment(\.dynamicTypeSize, ProcessInfo.processInfo.arguments.contains("--spacing-accessibility") ? .accessibility3 : .large)
    }

    private static let detailItem: DynamicFeedItem = {
        let text = (1...9).map { "详情第\($0)行全文" }.joined(separator: "\n")
        let originalText = (1...9).map { "原文第\($0)行全文" }.joined(separator: "\n")
        let json: [String: Any] = [
            "id_str": "spacing-detail", "type": "DYNAMIC_TYPE_FORWARD",
            "modules": ["module_dynamic": ["desc": ["text": text]]],
            "orig": ["id_str": "spacing-original", "type": "DYNAMIC_TYPE_WORD",
                     "modules": ["module_dynamic": ["desc": ["text": originalText]]]]
        ]
        return try! JSONDecoder.bili.decode(DynamicFeedItem.self, from: JSONSerialization.data(withJSONObject: json))
    }()

    private static let samples: [DynamicSpacingSample] = [
        .init(id: "A", segments: [.text("第一行纯中文正文\n第二行纯中文正文")]),
        .init(id: "B", segments: [.text(String(repeating: "这是一段需要自动折行的长中文动态正文。", count: 9))]),
        .init(id: "C", segments: [.text("中文与 English 12345\n混合文字和数字，保持原来的字号")]),
        .init(id: "D", segments: [.text("🥰🎉👨‍👩‍👧‍👦🏳️‍🌈\n原生 emoji 和普通文字 🐈\n𰻞 العربية Unicode fallback")]),
        .init(id: "E", segments: [.text("第一行\n带 Bilibili 图片表情 "), .emoji(text: "[doge]", url: "https://i0.hdslb.com/bfs/emote/6ea59c827c414b4a2955fe79e0f6fd3dcd515e24.png"), .text("\n第三行")]),
        .init(id: "F", segments: [.mention(text: "@测试用户", mid: 1, url: nil), .text(" 分享了内容\n"), .link(title: "查看链接", url: "https://example.com/"), .text(" 与普通正文一起显示")]),
        .init(id: "G", segments: [.text("第一段\n\n第二段")]),
        .init(id: "H", segments: [.text("第一段\n\n\n\n第二段")]),
        .init(id: "I", segments: [.text((1...9).map { "第\($0)行：展开与收起的正文" }.joined(separator: "\n"))])
    ]
}

private struct DynamicSpacingSample {
    let id: String
    let segments: [DynamicTextSegment]
}

private struct DynamicSpacingSampleRow: View {
    let sample: DynamicSpacingSample
    @Binding var isExpanded: Bool
    @State private var height: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(sample.id).font(.headline)
            DynamicFeedTextContent(
                collapsedInput: .dynamicFeedBody(segments: sample.segments, emoteSize: 23, maxLines: 6),
                expandedInput: .dynamicFeedBody(segments: sample.segments, emoteSize: 23, maxLines: nil),
                copyText: DynamicTextSegment.displayText(from: sample.segments),
                preferredWidth: nil, onOpenDetail: nil, isExpanded: $isExpanded
            )
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { _, value in height = value }
            Text(String(format: "%.1f", height)).font(.caption2)
                .accessibilityIdentifier("spacing.height.\(sample.id)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spacing.card.\(sample.id)")
    }
}

private struct DynamicSpacingOriginalRow: View {
    @State private var height: CGFloat = 0
    private let item = try! JSONDecoder.bili.decode(DynamicOriginalItem.self, from: Data(
        #"{"id_str":"123456789","type":"DYNAMIC_TYPE_WORD","modules":{"module_dynamic":{"desc":{"text":"转发原文第一行\n原文第二行"}}}}"#.utf8
    ))

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("转发原文：原生 Text 路径")
            DynamicOriginalPreview(item: item, parentID: "fixture")
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { _, value in height = value }
            Text(String(format: "%.1f", height)).accessibilityIdentifier("spacing.height.original")
        }
    }
}

private struct DynamicSpacingCommentRow: View {
    @State private var height: CGFloat = 0
    private let content = try! JSONDecoder.bili.decode(CommentContent.self, from: Data(#"{"message":"评论第一行\n评论第二行"}"#.utf8))

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("评论对照")
            DynamicCommentText(content: content, font: .system(size: 15), textColor: .primary, emoteSize: 20)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { _, value in height = value }
            Text(String(format: "%.1f", height)).accessibilityIdentifier("spacing.height.comment")
        }
    }
}
#endif
