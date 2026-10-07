import UIKit
import XCTest
@testable import bili

final class DynamicRichTextInteractionTests: XCTestCase {
    @MainActor
    func testReadingSpacingChangesRenderCacheAndMeasuredHeightWithoutChangingFont() throws {
        let original = DynamicAttributedTextInput.dynamicFeedBody(
            segments: [.text("第一行\n第二行\n第三行")], emoteSize: 23, maxLines: nil
        ).resolvingTypography(contentSizeCategory: .large)
        let off = original.replacingLineSpacing(FeedTypography.bodyLineSpacing(readingExperimentEnabled: false))
        let on = original.replacingLineSpacing(FeedTypography.bodyLineSpacing(readingExperimentEnabled: true))
        XCTAssertEqual(off, original)
        XCTAssertEqual(off.cacheKey, original.cacheKey)
        XCTAssertNotEqual(off, on)
        XCTAssertNotEqual(off.cacheKey, on.cacheKey)
        XCTAssertEqual(off.baseFont, on.baseFont)

        let coordinator = DynamicAttributedTextLabel.Coordinator()
        let offRender = coordinator.render(off)
        let onRender = coordinator.render(on)
        XCTAssertNotEqual(offRender.key, onRender.key)
        let style = try XCTUnwrap(onRender.attributedString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(style.minimumLineHeight, on.baseFont.lineHeight + 3, accuracy: 0.001)
        XCTAssertEqual(style.maximumLineHeight, style.minimumLineHeight)
        XCTAssertEqual(coordinator.render(off).key, offRender.key)
        XCTAssertEqual(coordinator.render(off).attributedString, offRender.attributedString)
        let offLabel = makeLabel(input: off, attributedString: offRender.attributedString)
        let onLabel = makeLabel(input: on, attributedString: onRender.attributedString)
        XCTAssertEqual(onLabel.bounds.height - offLabel.bounds.height, 9, accuracy: 1)
    }

    @MainActor
    func testReadingSpacingKeepsMixedGlyphBaselinesAndEmoteBoundsAcrossDynamicType() throws {
        let input = DynamicAttributedTextInput.dynamicFeedBody(segments: [
            .text("中文 CJK\nEnglish 123\n🥰👨‍👩‍👧‍👦🏳️‍🌈\n𰻞 العربية\n"),
            .emoji(text: "[表情]", url: "https://example.com/spacing-emote"),
            .text("\n"), .mention(text: "@用户", mid: 1, url: nil),
            .text("\n"), .link(title: "链接", url: "https://example.com/")
        ], emoteSize: 40, maxLines: nil)
        for category in [UIContentSizeCategory.large, .extraExtraExtraLarge, .accessibilityExtraExtraExtraLarge] {
            let off = input.resolvingTypography(contentSizeCategory: category)
            let on = input.replacingLineSpacing(3).resolvingTypography(contentSizeCategory: category)
            XCTAssertEqual(off.baseFont.pointSize, on.baseFont.pointSize)
            let offRender = off.render().attributedString
            let onRender = on.render().attributedString
            let offBaselines = baselineOffsets(for: offRender, fittingWidth: 2_000)
            let baselines = baselineOffsets(for: onRender, fittingWidth: 2_000)
            XCTAssertEqual(baselines.count, 7)
            // Fallback fonts have their own glyph metrics. The experiment must add
            // exactly 3pt per line without introducing any new baseline variation.
            for index in baselines.indices {
                XCTAssertEqual(baselines[index] - offBaselines[index], CGFloat(index + 1) * 3, accuracy: 0.01)
            }
            var offBounds: CGRect?
            var onBounds: CGRect?
            offRender.enumerateAttribute(.attachment, in: fullRange(in: offRender)) { value, _, _ in
                if let attachment = value as? NSTextAttachment { offBounds = attachment.bounds }
            }
            onRender.enumerateAttribute(.attachment, in: fullRange(in: onRender)) { value, _, _ in
                if let attachment = value as? NSTextAttachment { onBounds = attachment.bounds }
            }
            XCTAssertNotNil(onBounds)
            XCTAssertEqual(onBounds, offBounds)
        }
    }

    @MainActor
    func testReadingSpacingKeepsSixLineLimitAndExpandedMeasurementConsistent() {
        for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
            for spacing in [CGFloat(0), 3] {
                for count in [2, 6, 7] {
                    let text = (1...count).map { "第\($0)行" }.joined(separator: "\n")
                    let collapsed = DynamicAttributedTextInput.dynamicFeedBody(
                        segments: [.text(text)], emoteSize: 23, maxLines: 6
                    ).replacingLineSpacing(spacing).resolvingTypography(contentSizeCategory: category)
                    let expanded = DynamicAttributedTextInput.dynamicFeedBody(
                        segments: [.text(text)], emoteSize: 23, maxLines: nil
                    ).replacingLineSpacing(spacing).resolvingTypography(contentSizeCategory: category)
                    XCTAssertEqual(collapsed.exceedsMaximumLineCount(fittingWidth: 320), count > 6)
                    let collapsedLabel = makeLabel(input: collapsed, attributedString: collapsed.render().attributedString)
                    let expandedLabel = makeLabel(input: expanded, attributedString: expanded.render().attributedString)
                    let offInput = collapsed.replacingLineSpacing(0)
                    let offLabel = makeLabel(input: offInput, attributedString: offInput.render().attributedString)
                    XCTAssertEqual(collapsedLabel.bounds.height - offLabel.bounds.height,
                                   CGFloat(min(count, 6)) * spacing, accuracy: 1)
                    if count > 6 { XCTAssertGreaterThan(expandedLabel.bounds.height, collapsedLabel.bounds.height) }
                    else { XCTAssertEqual(expandedLabel.bounds.height, collapsedLabel.bounds.height) }
                }
                let wrapped = DynamicAttributedTextInput.dynamicFeedBody(
                    segments: [.text(String(repeating: "长正文自动换行。", count: 40))], emoteSize: 23, maxLines: 6
                ).replacingLineSpacing(spacing).resolvingTypography(contentSizeCategory: category)
                XCTAssertTrue(wrapped.exceedsMaximumLineCount(fittingWidth: 120))
                XCTAssertFalse(wrapped.exceedsMaximumLineCount(fittingWidth: 10_000))
            }
        }
    }

    @MainActor
    func testParagraphExperimentDoesNotInferBlocksFromInlineNodes() throws {
        let plain = try JSONDecoder().decode(DynamicText.self, from: Data(#"{"text":"第一段\n\n第二段\n\n\n第三段"}"#.utf8))
        XCTAssertEqual(plain.segments, [.text("第一段\n\n第二段\n\n\n第三段")])
        // The decoder drops a standalone whitespace-only rich-text node.
        // Such input cannot reliably distinguish paragraph boundaries from runs.
        let rich = try JSONDecoder().decode(DynamicText.self, from: Data(#"{"rich_text_nodes":[{"type":"RICH_TEXT_NODE_TYPE_TEXT","text":"第一段"},{"type":"RICH_TEXT_NODE_TYPE_TEXT","text":"\n\n"},{"type":"RICH_TEXT_NODE_TYPE_TEXT","text":"第二段"}]}"#.utf8))
        XCTAssertEqual(rich.segments, [.text("第一段第二段")])
        let input = DynamicAttributedTextInput.dynamicFeedBody(segments: plain.segments, emoteSize: 23, maxLines: nil)
            .replacingLineSpacing(3)
        let rendered = input.render().attributedString
        XCTAssertEqual(rendered.string, "第一段\n\n第二段\n\n\n第三段")
        rendered.enumerateAttribute(.paragraphStyle, in: fullRange(in: rendered)) { value, _, _ in
            let style = value as? NSParagraphStyle
            XCTAssertEqual(style?.paragraphSpacing, 0)
            XCTAssertEqual(style?.paragraphSpacingBefore, 0)
        }
    }

    @MainActor
    func testPlainTextTapTriggersNonLinkFallback() throws {
        let input = makeInput(segments: [.text("普通正文")])
        let rendered = input.render().attributedString
        let label = makeLabel(input: input, attributedString: rendered)
        var detailFallbackCount = 0
        var linkTapCount = 0
        label.onNonLinkTap = {
            detailFallbackCount += 1
        }
        label.onLinkTap = { _ in
            linkTapCount += 1
        }

        label.handleTap(at: midpoint(of: fullRange(in: rendered), in: rendered, label: label))

        XCTAssertEqual(detailFallbackCount, 1)
        XCTAssertEqual(linkTapCount, 0)
    }

    @MainActor
    func testBiliMentionURLTapOnlyTriggersLinkCallback() throws {
        let expectedURL = try XCTUnwrap(URL(string: "https://example.com/mention"))
        let input = makeInput(
            segments: [
                .text("普通正文 "),
                .link(title: "链接", url: expectedURL.absoluteString)
            ]
        )
        let rendered = input.render().attributedString
        let label = makeLabel(input: input, attributedString: rendered)
        var tappedURL: URL?
        var detailFallbackCount = 0
        label.onLinkTap = { tappedURL = $0 }
        label.onNonLinkTap = {
            detailFallbackCount += 1
        }

        let linkRange = try XCTUnwrap(rangeOfBiliMentionURL(in: rendered))
        label.handleTap(at: midpoint(of: linkRange, in: rendered, label: label))

        XCTAssertEqual(tappedURL, expectedURL)
        XCTAssertEqual(detailFallbackCount, 0)
    }

    @MainActor
    func testTextInputDetectsContentBeyondItsMaximumLineCount() {
        let input = DynamicAttributedTextInput(
            segments: [.text("1\n2\n3\n4\n5\n6\n7")],
            baseFont: UIFont.systemFont(ofSize: 17),
            textColor: .label,
            emoteSize: 20,
            maxLines: 6,
            typographyRole: nil
        )

        XCTAssertTrue(input.exceedsMaximumLineCount(fittingWidth: 320))
    }

    @MainActor
    func testTextInputUsesActualLayoutInsteadOfCharacterCount() {
        let input = DynamicAttributedTextInput(
            segments: [.text(String(repeating: "字", count: 121))],
            baseFont: UIFont.systemFont(ofSize: 17),
            textColor: .label,
            emoteSize: 20,
            maxLines: 6,
            typographyRole: nil
        )

        XCTAssertFalse(input.exceedsMaximumLineCount(fittingWidth: 2_000))
        XCTAssertTrue(input.exceedsMaximumLineCount(fittingWidth: 120))
    }

    @MainActor
    func testTextInputDoesNotTreatFourNewlinesAsSixLineOverflow() {
        let input = DynamicAttributedTextInput(
            segments: [.text("一\n二\n三\n四\n五")],
            baseFont: UIFont.systemFont(ofSize: 17),
            textColor: .label,
            emoteSize: 20,
            maxLines: 6,
            typographyRole: nil
        )

        XCTAssertFalse(input.exceedsMaximumLineCount(fittingWidth: 320))
    }

    @MainActor
    func testTextKitLabelClipsCollapsedContentToMaximumLines() {
        let font = UIFont.systemFont(ofSize: 17)
        let text = "一\n二\n三\n四\n五\n六\n七"
        let collapsedInput = DynamicAttributedTextInput(
            segments: [.text(text)],
            baseFont: font,
            textColor: .label,
            emoteSize: 20,
            maxLines: 6,
            typographyRole: nil
        )
        let expandedInput = DynamicAttributedTextInput(
            segments: [.text(text)],
            baseFont: font,
            textColor: .label,
            emoteSize: 20,
            maxLines: nil,
            typographyRole: nil
        )

        let collapsedLabel = makeLabel(
            input: collapsedInput,
            attributedString: collapsedInput.render().attributedString
        )
        let expandedLabel = makeLabel(
            input: expandedInput,
            attributedString: expandedInput.render().attributedString
        )

        XCTAssertLessThan(
            collapsedLabel.bounds.height,
            expandedLabel.bounds.height
        )
    }

    @MainActor
    func testTextKitLabelClipsWrappedCollapsedContentToMaximumLines() {
        let font = UIFont.systemFont(ofSize: 17)
        let text = String(repeating: "这是一段用于验证动态文本换行的内容。", count: 8)
        let collapsedInput = DynamicAttributedTextInput(
            segments: [.text(text)],
            baseFont: font,
            textColor: .label,
            emoteSize: 20,
            maxLines: 6,
            typographyRole: nil
        )
        let expandedInput = DynamicAttributedTextInput(
            segments: [.text(text)],
            baseFont: font,
            textColor: .label,
            emoteSize: 20,
            maxLines: nil,
            typographyRole: nil
        )

        let collapsedLabel = makeLabel(
            input: collapsedInput,
            attributedString: collapsedInput.render().attributedString
        )
        let expandedLabel = makeLabel(
            input: expandedInput,
            attributedString: expandedInput.render().attributedString
        )

        XCTAssertLessThan(
            collapsedLabel.bounds.height,
            expandedLabel.bounds.height,
            "collapsed=\(collapsedLabel.bounds.height), expanded=\(expandedLabel.bounds.height)"
        )
    }

    @MainActor
    func testTextInputIgnoresTrailingWhitespaceLine() {
        let input = DynamicAttributedTextInput(
            segments: [.text("一\n二\n三\n四\n五\n六\n")],
            baseFont: UIFont.systemFont(ofSize: 17),
            textColor: .label,
            emoteSize: 20,
            maxLines: 6,
            typographyRole: nil
        )

        XCTAssertFalse(input.exceedsMaximumLineCount(fittingWidth: 320))
    }

    @MainActor
    func testDynamicTextNormalizesCarriageReturnLineEndings() throws {
        let data = Data(#"{"text":"第一行\r\n第二行\r第三行"}"#.utf8)
        let dynamicText = try JSONDecoder().decode(DynamicText.self, from: data)

        XCTAssertEqual(dynamicText.segments, [.text("第一行\n第二行\n第三行")])
    }

    @MainActor
    func testDynamicTextIgnoresTrailingWhitespaceWhenCountingCollapsedLines() throws {
        let data = Data(#"{"text":" \n一\n二\n三\n四\n五\n六\n \t"}"#.utf8)
        let dynamicText = try JSONDecoder().decode(DynamicText.self, from: data)

        XCTAssertEqual(dynamicText.segments, [.text("一\n二\n三\n四\n五\n六")])

        let input = DynamicAttributedTextInput(
            segments: dynamicText.segments,
            baseFont: UIFont.systemFont(ofSize: 17),
            textColor: .label,
            emoteSize: 20,
            maxLines: 6,
            typographyRole: nil
        )
        XCTAssertFalse(input.exceedsMaximumLineCount(fittingWidth: 320))
    }

    @MainActor
    func testDynamicFeedLineSpacingUsesEqualFixedLineBoxes() throws {
        let font = UIFont.systemFont(ofSize: 15)
        let input = DynamicAttributedTextInput(
            segments: [.text("这是会自动换行的第一段文字这是会自动换行的第一段文字\n第二段含原生表情🥰")],
            baseFont: font,
            textColor: .label,
            emoteSize: 20,
            maxLines: nil,
            typographyRole: nil,
            lineSpacing: 2
        )

        let rendered = input.render().attributedString
        let paragraphStyle = try XCTUnwrap(
            rendered.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        )
        let expectedLineHeight = font.lineHeight + 2

        XCTAssertEqual(paragraphStyle.minimumLineHeight, expectedLineHeight, accuracy: 0.001)
        XCTAssertEqual(paragraphStyle.maximumLineHeight, expectedLineHeight, accuracy: 0.001)

        let baselines = baselineOffsets(for: rendered, fittingWidth: 120)
        XCTAssertGreaterThanOrEqual(baselines.count, 3)
        for (current, previous) in zip(baselines.dropFirst(), baselines) {
            XCTAssertEqual(current - previous, expectedLineHeight, accuracy: 0.001)
        }
    }

    @MainActor
    func testDynamicFeedEmoteAttachmentFitsBodyLineHeight() throws {
        let font = UIFont.systemFont(ofSize: 17)
        let input = DynamicAttributedTextInput(
            segments: [.emoji(text: "[大表情]", url: "https://example.com/emote")],
            baseFont: font,
            textColor: .label,
            emoteSize: 40,
            maxLines: nil,
            typographyRole: nil
        )

        let rendered = input.render().attributedString
        let attachment = try XCTUnwrap(
            rendered.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
        )

        let expectedSize = min(font.lineHeight, font.ascender - font.descender)
        XCTAssertEqual(attachment.bounds.height, expectedSize, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(attachment.bounds.minY, font.descender - 0.001)
        XCTAssertLessThanOrEqual(attachment.bounds.maxY, font.ascender + 0.001)
    }

    @MainActor
    func testDynamicFeedEmoteAttachmentUsesBodyFontMetrics() throws {
        let font = UIFont.systemFont(ofSize: 17)
        let input = DynamicAttributedTextInput(
            segments: [.emoji(text: "[表情]", url: "https://example.com/emote")],
            baseFont: font,
            textColor: .label,
            emoteSize: 20,
            maxLines: nil,
            typographyRole: nil
        )

        let rendered = input.render().attributedString
        let appliedFont = try XCTUnwrap(
            rendered.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        )

        XCTAssertEqual(appliedFont.fontName, font.fontName)
        XCTAssertEqual(appliedFont.pointSize, font.pointSize, accuracy: 0.001)
    }

    @MainActor
    func testDynamicFeedEmoteAttachmentKeepsEqualLineBaselines() throws {
        let font = UIFont.systemFont(ofSize: 17)
        let lineSpacing: CGFloat = 2
        let input = DynamicAttributedTextInput(
            segments: [
                .text("第一行\n第二行"),
                .emoji(text: "[大表情]", url: "https://example.com/emote"),
                .text("\n第三行")
            ],
            baseFont: font,
            textColor: .label,
            emoteSize: 40,
            maxLines: nil,
            typographyRole: nil,
            lineSpacing: lineSpacing
        )

        let baselines = baselineOffsets(for: input.render().attributedString, fittingWidth: 320)
        let expectedLineHeight = font.lineHeight + lineSpacing

        XCTAssertEqual(baselines.count, 3)
        for (current, previous) in zip(baselines.dropFirst(), baselines) {
            XCTAssertEqual(current - previous, expectedLineHeight, accuracy: 0.001)
        }
    }

    @MainActor
    private func makeInput(segments: [DynamicTextSegment]) -> DynamicAttributedTextInput {
        DynamicAttributedTextInput(
            segments: segments,
            baseFont: UIFont.systemFont(ofSize: 17),
            textColor: .label,
            emoteSize: 20,
            maxLines: nil,
            typographyRole: nil
        )
    }

    @MainActor
    private func makeLabel(
        input: DynamicAttributedTextInput,
        attributedString: NSAttributedString
    ) -> DynamicTextKitAttributedLabel {
        let label = DynamicTextKitAttributedLabel()
        label.numberOfLines = input.maxLines ?? 0
        label.lineBreakMode = input.lineBreakMode
        label.attributedText = attributedString
        let width: CGFloat = 320
        let size = label.measuredSize(fittingWidth: width)
        label.frame = CGRect(origin: .zero, size: size)
        label.layoutIfNeeded()
        return label
    }

    private func fullRange(in attributedString: NSAttributedString) -> NSRange {
        NSRange(location: 0, length: attributedString.length)
    }

    private func rangeOfBiliMentionURL(in attributedString: NSAttributedString) -> NSRange? {
        var result: NSRange?
        attributedString.enumerateAttribute(
            .biliMentionURL,
            in: fullRange(in: attributedString)
        ) { value, range, stop in
            guard value != nil else { return }
            result = range
            stop.pointee = true
        }
        return result
    }

    private func midpoint(
        of characterRange: NSRange,
        in attributedString: NSAttributedString,
        label: DynamicTextKitAttributedLabel
    ) -> CGPoint {
        let textStorage = NSTextStorage(attributedString: attributedString)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: label.bounds.size)
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = label.numberOfLines
        textContainer.lineBreakMode = label.lineBreakMode
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: characterRange,
            actualCharacterRange: nil
        )
        let firstGlyph = NSRange(location: glyphRange.location, length: 1)
        let rect = layoutManager.boundingRect(forGlyphRange: firstGlyph, in: textContainer)
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    private func baselineOffsets(
        for attributedString: NSAttributedString,
        fittingWidth width: CGFloat
    ) -> [CGFloat] {
        let textStorage = NSTextStorage(attributedString: attributedString)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            size: CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        var baselines = [CGFloat]()
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) {
            rect,
            _,
            _,
            lineGlyphRange,
            _ in
            let glyphLocation = layoutManager.location(forGlyphAt: lineGlyphRange.location)
            baselines.append(rect.minY + glyphLocation.y)
        }
        return baselines
    }
}
