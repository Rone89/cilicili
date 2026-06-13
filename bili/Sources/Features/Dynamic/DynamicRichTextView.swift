import SwiftUI
import UIKit

struct DynamicRichTextView: View {
    let segments: [DynamicTextSegment]
    let font: UIFont
    let textColor: Color
    let emoteSize: CGFloat
    let maxLines: Int?
    let preferredWidth: CGFloat?
    private let textInput: DynamicAttributedTextInput
    @Environment(\.openAppURLAction) private var openAppURL

    init(
        segments: [DynamicTextSegment],
        font: UIFont,
        textColor: Color,
        emoteSize: CGFloat,
        maxLines: Int?,
        preferredWidth: CGFloat? = nil
    ) {
        self.segments = segments
        self.font = font
        self.textColor = textColor
        self.emoteSize = emoteSize
        self.maxLines = maxLines
        self.preferredWidth = preferredWidth

        self.textInput = DynamicAttributedTextInput(
            segments: segments.isEmpty ? [.text(" ")] : segments,
            baseFont: font,
            textColor: UIColor(textColor),
            emoteSize: emoteSize,
            maxLines: maxLines
        )
    }

    init(input: DynamicAttributedTextInput, preferredWidth: CGFloat? = nil) {
        self.segments = input.segments
        self.font = input.baseFont
        self.textColor = Color(input.textColor)
        self.emoteSize = input.emoteSize
        self.maxLines = input.maxLines
        self.preferredWidth = preferredWidth
        self.textInput = input
    }

    var body: some View {
        if let plainText = textInput.nativePlainText {
            Text(textInput.nativeAttributedPlainText(plainText))
                .font(textInput.nativeSwiftUIFont)
                .foregroundStyle(Color(textInput.textColor))
                .lineLimit(textInput.maxLines)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(plainText)
        } else {
            DynamicAttributedTextLabel(
                input: textInput,
                preferredWidth: preferredWidth,
                onURLTap: { url in
                    openAppURL?(url)
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DynamicAttributedTextInput: Equatable {
    let segments: [DynamicTextSegment]
    let baseFont: UIFont
    let textColor: UIColor
    let emoteSize: CGFloat
    let maxLines: Int?
    static let feedBodyFont = UIFontMetrics(forTextStyle: .body)
        .scaledFont(for: .systemFont(ofSize: 15, weight: .regular))

    static func dynamicFeedHeadline(
        segments: [DynamicTextSegment],
        emoteSize: CGFloat,
        maxLines: Int?
    ) -> DynamicAttributedTextInput {
        DynamicAttributedTextInput(
            segments: segments.isEmpty ? [.text(" ")] : segments,
            baseFont: Self.feedBodyFont,
            textColor: .label,
            emoteSize: emoteSize,
            maxLines: maxLines
        )
    }

    static func == (lhs: DynamicAttributedTextInput, rhs: DynamicAttributedTextInput) -> Bool {
        lhs.segments == rhs.segments
            && lhs.baseFont.fontName == rhs.baseFont.fontName
            && lhs.baseFont.pointSize == rhs.baseFont.pointSize
            && lhs.textColor == rhs.textColor
            && lhs.emoteSize == rhs.emoteSize
            && lhs.maxLines == rhs.maxLines
    }

    var cacheKey: String {
        let segmentKey = segments
            .map { segment -> String in
                switch segment {
                case .text(let text):
                    return "t:\(text)"
                case .emoji(let text, let url):
                    return "e:\(text):\(url ?? "")"
                case .link(let text, let url):
                    return "l:\(text):\(url)"
                case .mention(let text, let mid, let url):
                    return "m:\(text):\(mid.map(String.init) ?? ""):\(url ?? "")"
                }
            }
            .joined(separator: "\u{1f}")
        return [
            segmentKey,
            baseFont.fontName,
            "\(baseFont.pointSize)",
            "\(textColor.dynamicRGBAKey)",
            "\(emoteSize)",
            "\(maxLines ?? -1)"
        ].joined(separator: "\u{1e}")
    }

    var nativePlainText: String? {
        var text = ""
        for segment in segments {
            guard case .text(let value) = segment else { return nil }
            text += value
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var nativeSwiftUIFont: Font {
        .custom(baseFont.fontName, size: baseFont.pointSize, relativeTo: .body)
    }

    func nativeAttributedPlainText(_ text: String) -> AttributedString {
        DynamicTextLineBreakStyle.attributedString(
            for: text,
            lineLimit: maxLines,
            lineSpacing: 2
        )
    }

    func render() -> (attributedString: NSAttributedString, missingImageURLs: [URL]) {
        let result = NSMutableAttributedString()
        var missingImageURLs = [URL]()

        for segment in segments {
            switch segment {
            case .text(let text):
                result.append(attributedText(text))
            case .emoji(let text, let url):
                result.append(emoteAttachment(for: text, urlString: url, missingImageURLs: &missingImageURLs))
            case .link(let title, let rawURL):
                if let normalized = AppLinkRouter.normalizedHTTPURLString(rawURL),
                   let url = URL(string: normalized) {
                    result.append(BiliMentionTextRenderer.linkAttributedString(title: title, url: url, font: baseFont))
                } else {
                    result.append(attributedText(title))
                }
            case .mention(let text, let mid, let url):
                let mention = BiliMention(text: text, mid: mid, url: url)
                result.append(
                    BiliMentionTextRenderer.attributedString(
                        for: text,
                        baseColor: textColor,
                        font: baseFont,
                        mentions: [mention].compactMap { $0 }
                    )
                )
            }
        }

        if result.length == 0 {
            result.append(attributedText(" "))
        }

        result.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: result.length))
        return (result, Array(Set(missingImageURLs)))
    }

    private var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.lineBreakMode = lineBreakMode
        style.lineBreakStrategy = lineBreakStrategy
        return style
    }

    var lineBreakMode: NSLineBreakMode {
        plainTextForLineBreaking.prefersCharacterWrappingForCJKText ? .byCharWrapping : .byWordWrapping
    }

    var lineBreakStrategy: NSParagraphStyle.LineBreakStrategy {
        plainTextForLineBreaking.prefersCharacterWrappingForCJKText ? [] : .standard
    }

    private var plainTextForLineBreaking: String {
        segments
            .map { segment -> String in
                switch segment {
                case .text(let text):
                    text
                case .emoji(let text, _):
                    text
                case .link(let title, _):
                    title
                case .mention(let text, _, _):
                    text
                }
            }
            .joined()
    }

    private func attributedText(_ text: String) -> NSAttributedString {
        BiliMentionTextRenderer.attributedString(
            for: text,
            baseColor: textColor,
            font: baseFont,
            mentions: []
        )
    }

    private func emoteAttachment(for token: String, urlString: String?, missingImageURLs: inout [URL]) -> NSAttributedString {
        guard let urlString, let url = URL(string: urlString) else {
            return attributedText(token)
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
}

private struct DynamicAttributedTextLabel: UIViewRepresentable {
    let input: DynamicAttributedTextInput
    let preferredWidth: CGFloat?
    let onURLTap: (URL) -> Void
    private static let sharedRenderCache = DynamicAttributedTextRenderCache()

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> DynamicTextKitAttributedLabel {
        let label = DynamicTextKitAttributedLabel()
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }

    func updateUIView(_ label: DynamicTextKitAttributedLabel, context: Context) {
        label.onLinkTap = onURLTap
        label.numberOfLines = input.maxLines ?? 0
        label.lineBreakMode = input.lineBreakMode
        let renderResult = context.coordinator.render(input)
        if context.coordinator.appliedRenderKey != renderResult.key {
            label.attributedText = renderResult.attributedString
            label.invalidateIntrinsicContentSize()
            context.coordinator.appliedRenderKey = renderResult.key
        }
        context.coordinator.currentInput = input
        context.coordinator.loadMissingImages(renderResult.missingImageURLs, into: label)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: DynamicTextKitAttributedLabel, context: Context) -> CGSize? {
        guard let width = context.coordinator.measuredWidth(
            proposedWidth: proposal.width,
            preferredWidth: preferredWidth,
            boundsWidth: uiView.bounds.width
        ) else {
            context.coordinator.lastMeasuredWidth = nil
            return nil
        }

        context.coordinator.lastMeasuredWidth = width
        return uiView.measuredSize(fittingWidth: width)
    }

    final class Coordinator {
        var currentInput: DynamicAttributedTextInput?
        var appliedRenderKey: String?
        var lastMeasuredWidth: CGFloat?
        private var cachedInputKey: String?
        private var cachedRenderResult: DynamicAttributedTextRenderResult?
        private var imageTasks: [URL: Task<Void, Never>] = [:]

        func measuredWidth(proposedWidth: CGFloat?, preferredWidth: CGFloat?, boundsWidth: CGFloat) -> CGFloat? {
            let preferred = validWidth(preferredWidth)
            let proposed = validWidth(proposedWidth)

            if let preferred {
                return ceil(max(preferred, proposed ?? 0))
            }

            if let proposed {
                return ceil(proposed)
            }

            if boundsWidth.isFinite, boundsWidth > 1 {
                return ceil(boundsWidth)
            }

            if let lastMeasuredWidth, lastMeasuredWidth.isFinite, lastMeasuredWidth > 1 {
                return ceil(lastMeasuredWidth)
            }

            return nil
        }

        private func validWidth(_ width: CGFloat?) -> CGFloat? {
            guard let width, width.isFinite, width > 1 else { return nil }
            return width
        }

        func render(_ input: DynamicAttributedTextInput) -> DynamicAttributedTextRenderResult {
            if cachedInputKey == input.cacheKey, let cachedRenderResult {
                return cachedRenderResult
            }

            if let result = DynamicAttributedTextLabel.sharedRenderCache.result(for: input.cacheKey) {
                cachedInputKey = input.cacheKey
                cachedRenderResult = result
                return result
            }

            let result = input.render()
            let renderResult = DynamicAttributedTextRenderResult(
                key: input.cacheKey + "|" + result.missingImageURLs.map(\.absoluteString).sorted().joined(separator: ","),
                attributedString: result.attributedString,
                missingImageURLs: result.missingImageURLs
            )
            if result.missingImageURLs.isEmpty {
                DynamicAttributedTextLabel.sharedRenderCache.set(renderResult, for: input.cacheKey)
            }
            cachedInputKey = input.cacheKey
            cachedRenderResult = renderResult
            return renderResult
        }

        func loadMissingImages(_ urls: [URL], into label: DynamicTextKitAttributedLabel) {
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
                            DynamicAttributedTextLabel.sharedRenderCache.set(renderResult, for: currentInput.cacheKey)
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

private final class DynamicTextKitAttributedLabel: UIView {
    var attributedText: NSAttributedString? {
        didSet {
            textStorage.setAttributedString(attributedText ?? NSAttributedString())
            accessibilityLabel = attributedText?.string
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
        }
    }

    var numberOfLines = 0 {
        didSet {
            guard oldValue != numberOfLines else { return }
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
        }
    }

    var lineBreakMode: NSLineBreakMode = .byWordWrapping {
        didSet {
            guard oldValue != lineBreakMode else { return }
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
        }
    }

    var onLinkTap: ((URL) -> Void)?

    private let textStorage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let textContainer = NSTextContainer(size: .zero)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureTextSystem()
        installTapRecognizer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureTextSystem()
        installTapRecognizer()
    }

    override var intrinsicContentSize: CGSize {
        guard bounds.width > 1 else {
            return CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
        }
        return measuredSize(fittingWidth: bounds.width)
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard textStorage.length > 0, bounds.width > 1 else { return }

        configureTextContainer(size: CGSize(width: bounds.width, height: bounds.height))
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        layoutManager.drawBackground(forGlyphRange: glyphRange, at: .zero)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: .zero)
    }

    func measuredSize(fittingWidth width: CGFloat) -> CGSize {
        guard width.isFinite, width > 1, textStorage.length > 0 else {
            return CGSize(width: max(ceil(width), 0), height: 0)
        }

        configureTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return CGSize(width: ceil(width), height: ceil(usedRect.height))
    }

    private func configureTextSystem() {
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
    }

    private func installTapRecognizer() {
        isUserInteractionEnabled = true
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(recognizer)
    }

    private func configureTextContainer(size: CGSize) {
        textContainer.size = CGSize(
            width: max(size.width, 0),
            height: max(size.height, 0)
        )
        textContainer.maximumNumberOfLines = numberOfLines
        textContainer.lineBreakMode = lineBreakMode
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              let onLinkTap,
              let characterIndex = characterIndex(at: recognizer.location(in: self)),
              characterIndex >= 0,
              characterIndex < textStorage.length
        else { return }

        let attribute = textStorage.attribute(.biliMentionURL, at: characterIndex, effectiveRange: nil)
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
        guard textStorage.length > 0, bounds.width > 1 else { return nil }

        configureTextContainer(size: bounds.size)
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        guard usedRect.insetBy(dx: -8, dy: -8).contains(point) else { return nil }

        let glyphIndex = layoutManager.glyphIndex(for: point, in: textContainer)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
        guard glyphRect.insetBy(dx: -10, dy: -8).contains(point) else { return nil }
        return layoutManager.characterIndexForGlyph(at: glyphIndex)
    }
}

private final class DynamicAttributedTextRenderCache {
    private let cache = NSCache<NSString, DynamicAttributedTextRenderCacheEntry>()

    init() {
        cache.countLimit = 900
    }

    func result(for key: String) -> DynamicAttributedTextRenderResult? {
        cache.object(forKey: key as NSString)?.result
    }

    func set(_ result: DynamicAttributedTextRenderResult, for key: String) {
        cache.setObject(DynamicAttributedTextRenderCacheEntry(result: result), forKey: key as NSString)
    }
}

private final class DynamicAttributedTextRenderCacheEntry {
    let result: DynamicAttributedTextRenderResult

    init(result: DynamicAttributedTextRenderResult) {
        self.result = result
    }
}

private struct DynamicAttributedTextRenderResult {
    let key: String
    let attributedString: NSAttributedString
    let missingImageURLs: [URL]
}

private extension UIColor {
    var dynamicRGBAKey: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return "\(red),\(green),\(blue),\(alpha)"
    }
}
