import SwiftUI
import UIKit

struct BiliEmoteText: View {
    let content: CommentContent?
    let font: Font
    let textColor: Color
    let emoteSize: CGFloat
    let leadingName: String?
    let leadingNameColor: Color

    @Environment(\.lineLimit) private var lineLimit

    init(
        content: CommentContent?,
        font: Font = .subheadline,
        textColor: Color = .primary,
        emoteSize: CGFloat = 22,
        leadingName: String? = nil,
        leadingNameColor: Color = .pink
    ) {
        self.content = content
        self.font = font
        self.textColor = textColor
        self.emoteSize = emoteSize
        self.leadingName = leadingName
        self.leadingNameColor = leadingNameColor
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
            )
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resolvedUIFont: UIFont {
        let textStyle: UIFont.TextStyle = emoteSize <= 18 ? .caption1 : .subheadline
        return UIFont.preferredFont(forTextStyle: textStyle)
    }
}

private struct BiliAttributedEmoteLabel: UIViewRepresentable {
    let input: BiliEmoteRenderInput

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.backgroundColor = .clear
        label.adjustsFontForContentSizeCategory = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.numberOfLines = input.lineLimit ?? 0
        label.lineBreakMode = input.lineLimit == nil ? .byCharWrapping : .byTruncatingTail

        let renderResult = context.coordinator.render(input)
        if context.coordinator.appliedRenderKey != renderResult.key {
            label.attributedText = renderResult.attributedString
            label.invalidateIntrinsicContentSize()
            context.coordinator.appliedRenderKey = renderResult.key
        }

        context.coordinator.currentInput = input
        context.coordinator.loadMissingImages(renderResult.missingImageURLs, into: label)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        let width = max(proposal.width ?? uiView.bounds.width, 1)
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

            let result = input.render()
            cachedInputKey = input.cacheKey
            cachedRenderResult = result
            return result
        }

        func loadMissingImages(_ urls: [URL], into label: UILabel) {
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

private struct BiliEmoteRenderInput {
    let content: CommentContent?
    let baseFont: UIFont
    let textColor: UIColor
    let accentColor: UIColor
    let leadingName: String?
    let leadingNameColor: UIColor
    let emoteSize: CGFloat
    let lineLimit: Int?

    private var message: String {
        content?.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var cacheKey: String {
        let emoteKey = (content?.emotes ?? [:])
            .map { "\($0.key)=\($0.value.displayURL ?? "")" }
            .sorted()
            .joined(separator: "|")
        return [
            message,
            emoteKey,
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
        style.lineBreakMode = lineLimit == nil ? .byCharWrapping : .byTruncatingTail
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
                result.append(attributedText(String(text[cursor...]), color: color(for: role), font: font(for: role)))
                break
            }

            result.append(attributedText(String(text[cursor..<open]), color: color(for: role), font: font(for: role)))

            let token = String(text[open...close])
            if let emote = content?.emote(for: token) {
                result.append(emoteAttachment(for: token, emote: emote, missingImageURLs: &missingImageURLs))
            } else {
                result.append(attributedText(token, color: color(for: role), font: font(for: role)))
            }
            cursor = text.index(after: close)
        }
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

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return nil }
            cache.setObject(image, forKey: url as NSURL)
            return image
        } catch {
            return nil
        }
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
