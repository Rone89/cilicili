import SwiftUI
import UIKit

struct BiliEmoteText: View {
    let content: CommentContent?
    let font: Font
    let textColor: Color
    let emoteSize: CGFloat
    let leadingName: String?
    let leadingNameColor: Color
    let showsLinkButtons: Bool

    @Environment(\.lineLimit) private var lineLimit
    @Environment(\.openAppURLAction) private var openAppURL

    init(
        content: CommentContent?,
        font: Font = .subheadline,
        textColor: Color = .primary,
        emoteSize: CGFloat = 22,
        leadingName: String? = nil,
        leadingNameColor: Color = .pink,
        showsLinkButtons: Bool = true
    ) {
        self.content = content
        self.font = font
        self.textColor = textColor
        self.emoteSize = emoteSize
        self.leadingName = leadingName
        self.leadingNameColor = leadingNameColor
        self.showsLinkButtons = showsLinkButtons
    }

    var body: some View {
        BiliAttributedEmoteLabel(
            input: BiliEmoteRenderInput(
                content: content,
                baseFont: resolvedUIFont,
                textColor: UIColor(textColor),
                accentColor: .systemPink,
                leadingName: leadingName,
                leadingNameColor: UIColor(leadingNameColor),
                emoteSize: emoteSize,
                lineLimit: lineLimit
            ),
            onURLTap: { url in
                openAppURL?(url)
            }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resolvedUIFont: UIFont {
        let textStyle: UIFont.TextStyle = emoteSize <= 18 ? .caption1 : .subheadline
        return UIFont.preferredFont(forTextStyle: textStyle)
    }
}

struct BiliLinkedText: View {
    let text: String
    let font: UIFont
    let textColor: Color
    let lineLimit: Int?

    @Environment(\.openAppURLAction) private var openAppURL

    init(
        _ text: String,
        font: UIFont = UIFont.preferredFont(forTextStyle: .body),
        textColor: Color = .primary,
        lineLimit: Int? = nil
    ) {
        self.text = text
        self.font = font
        self.textColor = textColor
        self.lineLimit = lineLimit
    }

    var body: some View {
        BiliAttributedEmoteLabel(
            input: BiliEmoteRenderInput(
                content: nil,
                plainText: text,
                baseFont: font,
                textColor: UIColor(textColor),
                accentColor: .systemPink,
                leadingName: nil,
                leadingNameColor: .secondaryLabel,
                emoteSize: font.lineHeight,
                lineLimit: lineLimit
            ),
            onURLTap: { url in
                openAppURL?(url)
            }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BiliAttributedEmoteLabel: UIViewRepresentable {
    let input: BiliEmoteRenderInput
    let onURLTap: (URL) -> Void
    private static let sharedRenderCache = BiliEmoteRenderCache()

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> BiliInteractiveAttributedLabel {
        let label = BiliInteractiveAttributedLabel()
        label.backgroundColor = .clear
        label.adjustsFontForContentSizeCategory = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }

    func updateUIView(_ label: BiliInteractiveAttributedLabel, context: Context) {
        label.onLinkTap = onURLTap
        label.numberOfLines = input.lineLimit ?? 0
        label.lineBreakMode = .byWordWrapping

        let renderResult = context.coordinator.render(input)
        if context.coordinator.appliedRenderKey != renderResult.key {
            label.attributedText = renderResult.attributedString
            label.invalidateIntrinsicContentSize()
            context.coordinator.appliedRenderKey = renderResult.key
        }

        context.coordinator.currentInput = input
        context.coordinator.loadMissingImages(renderResult.missingImageURLs, into: label)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: BiliInteractiveAttributedLabel, context: Context) -> CGSize? {
        guard let width = proposal.width ?? (uiView.bounds.width > 1 ? uiView.bounds.width : nil),
              width > 1
        else { return nil }
        uiView.preferredMaxLayoutWidth = width
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }

    final class Coordinator {
        var currentInput: BiliEmoteRenderInput?
        var appliedRenderKey: String?
        private var cachedInputKey: String?
        private var cachedRenderResult: BiliEmoteRenderResult?
        private var imageTasks: [URL: Task<Void, Never>] = [:]

        func render(_ input: BiliEmoteRenderInput) -> BiliEmoteRenderResult {
            if cachedInputKey == input.cacheKey, let cachedRenderResult {
                return cachedRenderResult
            }

            if let result = BiliAttributedEmoteLabel.sharedRenderCache.result(for: input.cacheKey) {
                cachedInputKey = input.cacheKey
                cachedRenderResult = result
                return result
            }

            let result = input.render()
            if result.missingImageURLs.isEmpty {
                BiliAttributedEmoteLabel.sharedRenderCache.set(result, for: input.cacheKey)
            }
            cachedInputKey = input.cacheKey
            cachedRenderResult = result
            return result
        }

        func loadMissingImages(_ urls: [URL], into label: BiliInteractiveAttributedLabel) {
            guard !urls.isEmpty else { return }

            for url in urls where imageTasks[url] == nil {
                imageTasks[url] = Task { [weak self, weak label] in
                    _ = await BiliEmoteImageStore.shared.image(for: url)

                    await MainActor.run {
                        guard let self else { return }
                        self.imageTasks[url] = nil
                        guard let label, let currentInput = self.currentInput else { return }
                        self.cachedInputKey = nil
                        let renderResult = self.render(currentInput)
                        if renderResult.missingImageURLs.isEmpty {
                            BiliAttributedEmoteLabel.sharedRenderCache.set(renderResult, for: currentInput.cacheKey)
                        }
                        self.appliedRenderKey = renderResult.key
                        label.attributedText = renderResult.attributedString
                        label.invalidateIntrinsicContentSize()
                    }
                }
            }
        }

        deinit {
            imageTasks.values.forEach { $0.cancel() }
        }
    }
}

extension NSAttributedString.Key {
    static let biliMentionURL = NSAttributedString.Key("BiliMentionURL")
}

final class BiliInteractiveAttributedLabel: UILabel {
    var onLinkTap: ((URL) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        installTapRecognizer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installTapRecognizer()
    }

    private func installTapRecognizer() {
        isUserInteractionEnabled = true
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(recognizer)
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              let attributedText,
              attributedText.length > 0,
              let onLinkTap,
              let characterIndex = characterIndex(at: recognizer.location(in: self)),
              characterIndex >= 0,
              characterIndex < attributedText.length
        else { return }

        let attribute = attributedText.attribute(.biliMentionURL, at: characterIndex, effectiveRange: nil)
        let url: URL?
        if let directURL = attribute as? URL {
            url = directURL
        } else if let string = attribute as? String {
            url = URL(string: string)
        } else {
            url = nil
        }

        if let url {
            onLinkTap(url)
        }
    }

    private func characterIndex(at point: CGPoint) -> Int? {
        guard let attributedText, attributedText.length > 0, bounds.width > 0 else {
            return nil
        }

        let textStorage = NSTextStorage(attributedString: attributedText)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: bounds.size)
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = numberOfLines
        textContainer.lineBreakMode = lineBreakMode
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        let usedRect = layoutManager.usedRect(for: textContainer)
        let xOffset: CGFloat
        switch textAlignment {
        case .center:
            xOffset = max((bounds.width - usedRect.width) / 2 - usedRect.minX, 0)
        case .right:
            xOffset = max(bounds.width - usedRect.width - usedRect.minX, 0)
        default:
            xOffset = -usedRect.minX
        }
        let yOffset = max((bounds.height - usedRect.height) / 2 - usedRect.minY, 0)
        let textPoint = CGPoint(x: point.x - xOffset, y: point.y - yOffset)
        guard usedRect.insetBy(dx: -8, dy: -8).contains(textPoint) else {
            return nil
        }

        let glyphIndex = layoutManager.glyphIndex(for: textPoint, in: textContainer)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
        guard glyphRect.insetBy(dx: -10, dy: -8).contains(textPoint) else {
            return nil
        }
        return layoutManager.characterIndexForGlyph(at: glyphIndex)
    }
}

enum BiliMentionTextRenderer {
    static let mentionColor = UIColor.systemBlue

    static func attributedString(
        for text: String,
        baseColor: UIColor,
        font: UIFont,
        mentions: [BiliMention]
    ) -> NSAttributedString {
        inlineAttributedString(
            for: text,
            baseColor: baseColor,
            font: font,
            mentions: mentions
        )
    }

    static func inlineAttributedString(
        for text: String,
        baseColor: UIColor,
        font: UIFont,
        mentions: [BiliMention]
    ) -> NSAttributedString {
        guard !text.isEmpty else { return NSAttributedString(string: "") }

        let runs = inlineRuns(in: text, mentions: mentions)
        guard !runs.isEmpty else {
            return plain(text, color: baseColor, font: font)
        }

        let nsText = text as NSString
        let result = NSMutableAttributedString()
        var cursor = 0
        for run in runs {
            guard run.range.location >= cursor else { continue }
            if run.range.location > cursor {
                let plainText = nsText.substring(with: NSRange(location: cursor, length: run.range.location - cursor))
                result.append(plain(plainText, color: baseColor, font: font))
            }

            switch run.kind {
            case .mention(let url):
                let displayText = nsText.substring(with: run.range)
                result.append(linkStyledText(displayText, url: url, font: font))
            case .link(let url):
                let rawTitle = nsText.substring(with: run.range)
                let displayTitle = AppLinkRouter.inlineTitle(for: url, title: rawTitle)
                result.append(linkStyledText(displayTitle, url: url, font: font))
            }
            cursor = run.range.location + run.range.length
        }

        if cursor < nsText.length {
            result.append(plain(nsText.substring(from: cursor), color: baseColor, font: font))
        }
        return result
    }

    static func linkAttributedString(title rawTitle: String, url: URL, font: UIFont) -> NSAttributedString {
        linkStyledText(AppLinkRouter.inlineTitle(for: url, title: rawTitle), url: url, font: font)
    }

    private static func plain(_ text: String, color: UIColor, font: UIFont) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color
            ]
        )
    }

    private static func linkStyledText(_ text: String, url: URL?, font: UIFont) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: mentionColor
        ]
        if let url {
            attributes[.biliMentionURL] = url
        }
        return NSAttributedString(string: text, attributes: attributes)
    }

    private static func inlineRuns(in text: String, mentions: [BiliMention]) -> [BiliInlineTextRun] {
        var runs = mentionRanges(in: text, mentions: mentions).map {
            BiliInlineTextRun(range: $0.range, kind: .mention($0.url))
        }

        for match in BiliTextLinkExtractor.matches(in: text) {
            guard !runs.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) else {
                continue
            }
            runs.append(BiliInlineTextRun(range: match.range, kind: .link(match.url)))
        }

        return runs.sorted { lhs, rhs in
            if lhs.range.location == rhs.range.location {
                return lhs.range.length > rhs.range.length
            }
            return lhs.range.location < rhs.range.location
        }
    }

    private static func mentionRanges(
        in text: String,
        mentions: [BiliMention]
    ) -> [(range: NSRange, url: URL?)] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var result = [(range: NSRange, url: URL?)]()

        for mention in mentions {
            var searchRange = fullRange
            while searchRange.length > 0 {
                let range = nsText.range(of: mention.text, options: [], range: searchRange)
                guard range.location != NSNotFound else { break }
                append(range: range, url: mention.destinationURL, to: &result)
                let nextLocation = range.location + max(range.length, 1)
                searchRange = NSRange(location: nextLocation, length: max(nsText.length - nextLocation, 0))
            }
        }

        if let regex = try? NSRegularExpression(pattern: #"@[^@\s\[\]：:，。！？!?；;、()（）]+"#) {
            for match in regex.matches(in: text, range: fullRange) {
                append(range: match.range, url: nil, to: &result)
            }
        }

        return result.sorted { lhs, rhs in
            if lhs.range.location == rhs.range.location {
                return lhs.range.length > rhs.range.length
            }
            return lhs.range.location < rhs.range.location
        }
    }

    private static func append(
        range: NSRange,
        url: URL?,
        to result: inout [(range: NSRange, url: URL?)]
    ) {
        guard range.location != NSNotFound, range.length > 1 else { return }
        guard !result.contains(where: { NSIntersectionRange($0.range, range).length > 0 }) else {
            return
        }
        result.append((range, url))
    }

    private struct BiliInlineTextRun {
        let range: NSRange
        let kind: Kind

        enum Kind {
            case mention(URL?)
            case link(URL)
        }
    }
}

private final class BiliEmoteRenderCache {
    private let cache = NSCache<NSString, BiliEmoteRenderCacheEntry>()

    init() {
        cache.countLimit = 700
    }

    func result(for key: String) -> BiliEmoteRenderResult? {
        cache.object(forKey: key as NSString)?.result
    }

    func set(_ result: BiliEmoteRenderResult, for key: String) {
        cache.setObject(BiliEmoteRenderCacheEntry(result: result), forKey: key as NSString)
    }
}

private final class BiliEmoteRenderCacheEntry {
    let result: BiliEmoteRenderResult

    init(result: BiliEmoteRenderResult) {
        self.result = result
    }
}

private struct BiliEmoteRenderInput {
    let content: CommentContent?
    let plainText: String?
    let baseFont: UIFont
    let textColor: UIColor
    let accentColor: UIColor
    let leadingName: String?
    let leadingNameColor: UIColor
    let emoteSize: CGFloat
    let lineLimit: Int?

    init(
        content: CommentContent?,
        plainText: String? = nil,
        baseFont: UIFont,
        textColor: UIColor,
        accentColor: UIColor,
        leadingName: String?,
        leadingNameColor: UIColor,
        emoteSize: CGFloat,
        lineLimit: Int?
    ) {
        self.content = content
        self.plainText = plainText
        self.baseFont = baseFont
        self.textColor = textColor
        self.accentColor = accentColor
        self.leadingName = leadingName
        self.leadingNameColor = leadingNameColor
        self.emoteSize = emoteSize
        self.lineLimit = lineLimit
    }

    private var message: String {
        (plainText ?? content?.message)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var mentions: [BiliMention] {
        content?.mentions ?? []
    }

    var cacheKey: String {
        let emoteKey = (content?.emotes ?? [:])
            .map { "\($0.key)=\($0.value.displayURL ?? "")" }
            .sorted()
            .joined(separator: "|")
        let mentionKey = mentions
            .map { "\($0.text)=\($0.mid.map(String.init) ?? ""):\($0.url ?? "")" }
            .sorted()
            .joined(separator: "|")
        return [
            message,
            emoteKey,
            mentionKey,
            leadingName ?? "",
            "\(baseFont.pointSize)",
            "\(textColor.rgbaCacheKey)",
            "\(leadingNameColor.rgbaCacheKey)",
            "\(emoteSize)",
            "\(lineLimit ?? -1)"
        ].joined(separator: "\u{1f}")
    }

    func render() -> BiliEmoteRenderResult {
        let result = NSMutableAttributedString(string: "")
        var missingImageURLs = [URL]()

        if let leadingName, !leadingName.isEmpty {
            result.append(attributedText("\(leadingName)：", color: leadingNameColor, font: emphasisFont))
        }

        for span in styledSpans(message.isEmpty ? " " : message) {
            append(span.text, role: span.role, to: result, missingImageURLs: &missingImageURLs)
        }

        result.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: result.length))
        let uniqueURLs = Array(Set(missingImageURLs))
        return BiliEmoteRenderResult(
            key: cacheKey + "|" + uniqueURLs.map(\.absoluteString).sorted().joined(separator: ","),
            attributedString: result,
            missingImageURLs: uniqueURLs
        )
    }

    private var emphasisFont: UIFont {
        UIFont.systemFont(ofSize: baseFont.pointSize, weight: .semibold)
    }

    private var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.lineBreakMode = .byWordWrapping
        return style
    }

    private func append(
        _ text: String,
        role: BiliEmoteTextRole,
        to result: NSMutableAttributedString,
        missingImageURLs: inout [URL]
    ) {
        guard !text.isEmpty else { return }

        var cursor = text.startIndex
        while cursor < text.endIndex {
            guard let open = text[cursor...].firstIndex(of: "["),
                  let close = text[open...].firstIndex(of: "]")
            else {
                result.append(attributedText(String(text[cursor...]), role: role))
                break
            }

            result.append(attributedText(String(text[cursor..<open]), role: role))

            let token = String(text[open...close])
            if let emote = content?.emote(for: token) {
                result.append(emoteAttachment(for: token, emote: emote, missingImageURLs: &missingImageURLs))
            } else {
                result.append(attributedText(token, role: role))
            }
            cursor = text.index(after: close)
        }
    }

    private func attributedText(_ text: String, role: BiliEmoteTextRole) -> NSAttributedString {
        BiliMentionTextRenderer.inlineAttributedString(
            for: text,
            baseColor: color(for: role),
            font: font(for: role),
            mentions: mentions
        )
    }

    private func attributedText(_ text: String, color: UIColor, font: UIFont) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color
            ]
        )
    }

    private func emoteAttachment(
        for token: String,
        emote: CommentEmote,
        missingImageURLs: inout [URL]
    ) -> NSAttributedString {
        guard let urlString = emote.displayURL, let url = URL(string: urlString) else {
            return attributedText(token, color: textColor, font: baseFont)
        }

        let attachment = NSTextAttachment()
        if let image = BiliEmoteImageStore.shared.cachedImage(for: url) {
            attachment.image = image
        } else {
            attachment.image = BiliEmoteImageStore.shared.placeholderImage(size: emoteSize)
            missingImageURLs.append(url)
        }
        attachment.bounds = CGRect(
            x: 0,
            y: (baseFont.capHeight - emoteSize) / 2,
            width: emoteSize,
            height: emoteSize
        )
        return NSAttributedString(attachment: attachment)
    }

    private func font(for role: BiliEmoteTextRole) -> UIFont {
        role == .accent ? emphasisFont : baseFont
    }

    private func color(for role: BiliEmoteTextRole) -> UIColor {
        role == .accent ? accentColor : textColor
    }

    private func styledSpans(_ message: String) -> [(text: String, role: BiliEmoteTextRole)] {
        guard let split = replyPrefixSplit(in: message) else {
            return [(message, .normal)]
        }
        return [
            ("回复 ", .normal),
            (split.target, .accent),
            (split.separator, .normal),
            (split.content, .normal)
        ].filter { !$0.text.isEmpty }
    }

    private func replyPrefixSplit(in message: String) -> (target: String, separator: String, content: String)? {
        let supportedVerbs = ["回复", "回覆", "回復"]
        guard let verb = supportedVerbs.first(where: { message.hasPrefix($0) }) else { return nil }

        var cursor = message.index(message.startIndex, offsetBy: verb.count)
        while cursor < message.endIndex, message[cursor].isWhitespace {
            cursor = message.index(after: cursor)
        }

        guard cursor < message.endIndex, message[cursor] == "@" else { return nil }
        guard let colon = message[cursor...].firstIndex(where: { $0 == ":" || $0 == "：" }) else { return nil }

        let prefixEnd = message.index(after: colon)
        let target = String(message[cursor..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = String(message[colon..<prefixEnd])
        let content = String(message[prefixEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return nil }
        return (target, separator, content)
    }
}

private struct BiliEmoteRenderResult {
    let key: String
    let attributedString: NSAttributedString
    let missingImageURLs: [URL]
}

private enum BiliEmoteTextRole {
    case normal
    case accent
}

private extension UIColor {
    var rgbaCacheKey: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return "\(red),\(green),\(blue),\(alpha)"
    }
}

final class BiliEmoteImageStore {
    static let shared = BiliEmoteImageStore()

    private let cache = NSCache<NSURL, UIImage>()
    private let placeholderCache = NSCache<NSNumber, UIImage>()

    private init() {
        cache.countLimit = 240
        placeholderCache.countLimit = 8
    }

    func cachedImage(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        if let cachedImage = cachedImage(for: url) {
            return cachedImage
        }

        if let image = await RemoteImageCache.shared.load(
            url: url,
            scale: 2,
            targetPixelSize: 96
        ) {
            cache.setObject(image, forKey: url as NSURL)
            return image
        }

        return nil
    }

    func placeholderImage(size: CGFloat) -> UIImage {
        let key = NSNumber(value: Double(size))
        if let cachedImage = placeholderCache.object(forKey: key) {
            return cachedImage
        }

        let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { context in
            UIColor.systemPink.withAlphaComponent(0.12).setFill()
            UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: size - 2, height: size - 2)).fill()
            UIColor.systemPink.withAlphaComponent(0.35).setStroke()
            UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: size - 2, height: size - 2)).stroke()
        }
        placeholderCache.setObject(image, forKey: key)
        return image
    }
}
