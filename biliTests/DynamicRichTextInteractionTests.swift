import UIKit
import XCTest
@testable import bili

final class DynamicRichTextInteractionTests: XCTestCase {
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
}
