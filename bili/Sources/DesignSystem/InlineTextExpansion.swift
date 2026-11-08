import UIKit

enum InlineTextExpansion {
    static let link = URL(string: "bili-inline-action://expand")!
    static let title = "展开"

    static func preview(
        _ text: NSAttributedString,
        width: CGFloat,
        lineLimit: Int,
        tint: UIColor
    ) -> NSAttributedString? {
        guard text.length > 0, width > 1, width.isFinite, lineLimit > 0 else { return nil }

        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = lineLimit + 1
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)

        func lineEnd(after limit: Int) -> Int? {
            let glyphs = manager.glyphRange(for: container)
            var count = 0
            var end: Int?
            manager.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, range, stop in
                count += 1
                if count == limit {
                    end = manager.characterIndexForGlyph(at: range.location)
                    stop.pointee = true
                }
            }
            return end
        }

        guard var end = lineEnd(after: lineLimit + 1), end > 0 else { return nil }
        let characters = text.string as NSString
        let attributes = text.attributes(at: end - 1, effectiveRange: nil)
        let suffix = NSMutableAttributedString(string: "… " + title, attributes: attributes)
        let wholeSuffix = NSRange(location: 0, length: suffix.length)
        suffix.removeAttribute(.attachment, range: wholeSuffix)
        suffix.removeAttribute(.biliMentionURL, range: wholeSuffix)
        let actionRange = NSRange(location: 2, length: (title as NSString).length)
        suffix.addAttribute(.biliMentionURL, value: link, range: actionRange)
        suffix.addAttribute(.foregroundColor, value: tint, range: actionRange)

        while end > 0 {
            let previous = characters.rangeOfComposedCharacterSequence(at: end - 1)
            if characters.substring(with: previous).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                end = previous.location
                continue
            }
            let candidate = NSMutableAttributedString(attributedString: text.attributedSubstring(from: NSRange(location: 0, length: end)))
            candidate.append(suffix)
            storage.setAttributedString(candidate)
            if lineEnd(after: lineLimit + 1) == nil {
                let glyphs = manager.glyphRange(
                    forCharacterRange: NSRange(location: end, length: suffix.length),
                    actualCharacterRange: nil
                )
                var line = NSRange()
                manager.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: &line)
                if NSMaxRange(glyphs) <= NSMaxRange(line) {
                    return candidate
                }
            }
            end = previous.location
        }

        return suffix
    }
}
