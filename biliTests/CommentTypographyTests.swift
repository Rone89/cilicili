import UIKit
import XCTest
@testable import bili

@MainActor
final class CommentTypographyTests: XCTestCase {
    func testProductionCommentBodySpacing() {
        XCTAssertEqual(CommentTypography.bodyLineSpacing, 2)
        XCTAssertEqual(AppTypography.Role.commentBody.pointSize, 15)
    }

    func testFixedLineBoxesCacheMeasurementAndAttachmentsAcrossDynamicType() throws {
        for category in [UIContentSizeCategory.large, .extraExtraExtraLarge, .accessibilityExtraExtraExtraLarge] {
            let font = AppTypography.Role.commentBody.uiFont(contentSizeCategory: category)
            let off = try input(spacing: 0, font: font)
            let on = try input(spacing: CommentTypography.bodyLineSpacing, font: font)
            XCTAssertNotEqual(off.cacheKey, on.cacheKey)
            let a = off.render().attributedString
            let b = on.render().attributedString
            b.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: b.length)) { value, _, _ in
                let style = value as? NSParagraphStyle
                XCTAssertEqual(style?.minimumLineHeight ?? 0, font.lineHeight + 2, accuracy: 0.001)
                XCTAssertEqual(style?.maximumLineHeight, style?.minimumLineHeight)
                XCTAssertEqual(style?.paragraphSpacing, 0)
                XCTAssertEqual(style?.paragraphSpacingBefore, 0)
            }
            func bounds(_ text: NSAttributedString) -> [CGRect] {
                var result: [CGRect] = []
                text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
                    if let attachment = value as? NSTextAttachment { result.append(attachment.bounds) }
                }
                return result
            }
            XCTAssertFalse(bounds(b).isEmpty)
            XCTAssertEqual(bounds(a), bounds(b))
            let offLabel = label(a, font: font)
            let onLabel = label(b, font: font)
            XCTAssertGreaterThan(onLabel.bounds.height, offLabel.bounds.height)
            XCTAssertEqual(AppTypography.Role.commentBody.pointSize, 15)
        }
    }

    func testHitTestingUsesRenderedParagraphStyleForLinksMentionsAndPlainBody() throws {
        for spacing in [CGFloat(0), 1, 2] {
            let rendered = try input(spacing: spacing, font: .systemFont(ofSize: 15)).render().attributedString
            let view = label(rendered, font: .systemFont(ofSize: 15))
            var plainTaps = 0
            var links: [URL] = []
            view.onNonLinkTap = { plainTaps += 1 }
            view.onLinkTap = { links.append($0) }
            view.handleTap(at: point(at: 0, text: rendered, label: view))
            XCTAssertEqual(plainTaps, 1)
            rendered.enumerateAttribute(.biliMentionURL, in: NSRange(location: 0, length: rendered.length)) { value, range, _ in
                guard let url = value as? URL else { return }
                view.handleTap(at: point(at: range.location, text: rendered, label: view))
                XCTAssertEqual(links.last, url)
            }
            XCTAssertGreaterThanOrEqual(links.count, 2)
            XCTAssertEqual(plainTaps, 1)
        }
    }

    private func input(spacing: CGFloat, font: UIFont) throws -> BiliEmoteRenderInput {
        let data = Data(#"{"message":"普通中文 English 123\n@用户\nhttps://example.com\n回复 @用户：正文\n[doge] 🥰𰻞","at_name_to_mid":{"用户":1},"emote":{"[doge]":{"text":"[doge]","url":"https://example.com/doge.png"}}}"#.utf8)
        return BiliEmoteRenderInput(content: try JSONDecoder.bili.decode(CommentContent.self, from: data), inlineEmotes: [:], baseFont: font, textColor: .label, accentColor: .systemPink, leadingName: nil, leadingNameColor: .secondaryLabel, leadingNameFont: nil, emoteSize: 22, lineLimit: nil, lineSpacing: spacing)
    }

    private func label(_ text: NSAttributedString, font: UIFont) -> BiliInteractiveAttributedLabel {
        let view = BiliInteractiveAttributedLabel(frame: .zero)
        view.font = font
        view.numberOfLines = 0
        view.attributedText = text
        view.frame = CGRect(origin: .zero, size: view.sizeThatFits(CGSize(width: 1000, height: CGFloat.greatestFiniteMagnitude)))
        return view
    }

    private func point(at index: Int, text: NSAttributedString, label: UILabel) -> CGPoint {
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: label.bounds.size)
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        let glyph = manager.glyphIndexForCharacter(at: index)
        let rect = manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        return CGPoint(x: rect.midX - used.minX, y: rect.midY + max((label.bounds.height - used.height) / 2 - used.minY, 0))
    }
}
