import DanmakuKit
import UIKit

final class DanmakuKitTextCellModel: DanmakuCellModel {
    #if DEBUG
    var debugDiagnostics: DanmakuRendererDiagnostics?
    #endif
    let cellClass: DanmakuCell.Type = DanmakuKitTextCell.self
    let item: DanmakuItem
    let size: CGSize
    var track: UInt?
    let displayTime: Double
    let type: DanmakuCellType
    let identifier: String
    let attributedText: NSAttributedString
    let missingEmoteURLs: [URL]
    let font: UIFont

    init(
        item: DanmakuItem,
        fontScale: Double,
        fontWeight: DanmakuFontWeightOption,
        opacity: Double,
        viewportWidth: CGFloat,
        displayTime: TimeInterval
    ) {
        self.item = item
        identifier = item.id
        self.displayTime = displayTime
        if item.isTopAnchored {
            type = .top
        } else if item.isBottomAnchored {
            type = .bottom
        } else {
            type = .floating
        }
        let uiFont = DanmakuRenderPolicy.font(for: item, viewportWidth: viewportWidth,
            scale: fontScale, weight: fontWeight)
        font = uiFont
        let color = UIColor(
            red: CGFloat((item.color >> 16) & 0xFF) / 255,
            green: CGFloat((item.color >> 8) & 0xFF) / 255,
            blue: CGFloat(item.color & 0xFF) / 255,
            alpha: CGFloat(min(max(opacity, 0.25), 1))
        )
        let textShadow = NSShadow()
        textShadow.shadowColor = UIColor.black.withAlphaComponent(min(max(opacity * 0.86, 0.25), 0.9))
        textShadow.shadowOffset = CGSize(width: 0, height: 1)
        textShadow.shadowBlurRadius = 1.4
        let rendered = Self.render(
            item.text,
            emotes: item.inlineEmotes,
            font: uiFont,
            color: color,
            shadow: textShadow
        )
        attributedText = rendered.attributedText
        missingEmoteURLs = rendered.missingImageURLs
        let textSize = attributedText.boundingRect(
            with: CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).size
        size = CGSize(
            width: ceil(max(textSize.width, uiFont.pointSize) + 12),
            height: ceil(max(textSize.height, uiFont.lineHeight) + 6)
        )
    }

    func isEqual(to cellModel: DanmakuCellModel) -> Bool {
        identifier == cellModel.identifier
    }

    private static func render(
        _ text: String,
        emotes: [String: BiliInlineEmote],
        font: UIFont,
        color: UIColor,
        shadow: NSShadow
    ) -> (attributedText: NSAttributedString, missingImageURLs: [URL]) {
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .shadow: shadow
        ]
        guard !text.isEmpty, !emotes.isEmpty else {
            return (NSAttributedString(string: text, attributes: baseAttributes), [])
        }

        let result = NSMutableAttributedString(string: "")
        var missingImageURLs = [URL]()
        var cursor = text.startIndex
        let tokens = emotes.keys.filter { !$0.isEmpty }

        while cursor < text.endIndex,
              let match = nextEmote(in: text, from: cursor, tokens: tokens, emotes: emotes) {
            if cursor < match.range.lowerBound {
                result.append(NSAttributedString(string: String(text[cursor..<match.range.lowerBound]), attributes: baseAttributes))
            }
            result.append(
                attachment(
                    for: match.emote,
                    token: String(text[match.range]),
                    font: font,
                    color: color,
                    shadow: shadow,
                    missingImageURLs: &missingImageURLs
                )
            )
            cursor = match.range.upperBound
        }
        if cursor < text.endIndex {
            result.append(NSAttributedString(string: String(text[cursor...]), attributes: baseAttributes))
        }
        if result.length == 0 {
            result.append(NSAttributedString(string: text, attributes: baseAttributes))
        }
        return (result, Array(Set(missingImageURLs)))
    }

    private static func nextEmote(
        in text: String,
        from start: String.Index,
        tokens: [String],
        emotes: [String: BiliInlineEmote]
    ) -> (range: Range<String.Index>, emote: BiliInlineEmote)? {
        let tokenMatch = tokens.compactMap { token -> (Range<String.Index>, BiliInlineEmote)? in
            guard let range = text.range(of: token, options: .literal, range: start..<text.endIndex),
                  let emote = emotes[token]
            else { return nil }
            return (range, emote)
        }.min { lhs, rhs in
            if lhs.0.lowerBound != rhs.0.lowerBound {
                return lhs.0.lowerBound < rhs.0.lowerBound
            }
            return text.distance(from: lhs.0.lowerBound, to: lhs.0.upperBound)
                > text.distance(from: rhs.0.lowerBound, to: rhs.0.upperBound)
        }

        var bracketMatch: (Range<String.Index>, BiliInlineEmote)?
        if let open = text[start...].firstIndex(of: "["),
           let close = text[open...].firstIndex(of: "]") {
            let range = open..<text.index(after: close)
            if let emote = emotes[String(text[range])] {
                bracketMatch = (range, emote)
            }
        }

        switch (tokenMatch, bracketMatch) {
        case let (token?, bracket?):
            if token.0.lowerBound == bracket.0.lowerBound {
                return text.distance(from: token.0.lowerBound, to: token.0.upperBound)
                    >= text.distance(from: bracket.0.lowerBound, to: bracket.0.upperBound)
                    ? (token.0, token.1)
                    : bracket
            }
            return token.0.lowerBound < bracket.0.lowerBound ? token : bracket
        case let (token?, nil):
            return token
        case let (nil, bracket?):
            return bracket
        case (nil, nil):
            return nil
        }
    }

    private static func attachment(
        for emote: BiliInlineEmote,
        token: String,
        font: UIFont,
        color: UIColor,
        shadow: NSShadow,
        missingImageURLs: inout [URL]
    ) -> NSAttributedString {
        guard let urlString = emote.displayURL,
              let url = URL(string: urlString)
        else {
            return NSAttributedString(
                string: token,
                attributes: [.font: font, .foregroundColor: color, .shadow: shadow]
            )
        }

        let fontEnvelopeHeight = font.ascender - font.descender
        let emoteSize = min(font.lineHeight, fontEnvelopeHeight)
        let verticalInset = max((fontEnvelopeHeight - emoteSize) / 2, 0)
        let attachment = NSTextAttachment()
        if let image = BiliEmoteImageStore.shared.cachedImage(for: url) {
            attachment.image = image
        } else {
            attachment.image = BiliEmoteImageStore.shared.placeholderImage(size: emoteSize)
            missingImageURLs.append(url)
        }
        let aspectRatio = CGFloat(
            max(emote.width ?? Double(emoteSize), 1) / max(emote.height ?? Double(emoteSize), 1)
        )
        let attachmentWidth = min(max(emoteSize * aspectRatio, emoteSize * 0.75), emoteSize * 4)
        attachment.bounds = CGRect(
            x: 0,
            y: font.descender + verticalInset,
            width: attachmentWidth,
            height: emoteSize
        )
        let result = NSMutableAttributedString(attachment: attachment)
        result.addAttributes(
            [.font: font, .foregroundColor: color, .shadow: shadow],
            range: NSRange(location: 0, length: result.length)
        )
        return result
    }
}

final class DanmakuKitTextCell: DanmakuCell {
    #if DEBUG
    private var drawDiagnostics: DanmakuRendererDiagnostics?
    private var drawCaptureID: UUID?
    #endif
    private var displayRequestedAt: CFTimeInterval?

    required init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        layer.isOpaque = false
        // Draw before the new position animation is presented. Async drawing can
        // otherwise finish after the cell has already crossed the right edge.
        displayAsync = false
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func displaying(_ context: CGContext, _ size: CGSize, _ isCancelled: Bool) {
        guard !isCancelled, let model = model as? DanmakuKitTextCellModel else { return }
        let textBounds = model.attributedText.boundingRect(
            with: CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let origin = CGPoint(x: 6, y: max(0, (size.height - textBounds.height) * 0.5))
        model.attributedText.draw(at: origin)
    }

    override func willDisplay() {
        displayRequestedAt = CACurrentMediaTime()
        #if DEBUG
        drawDiagnostics = (model as? DanmakuKitTextCellModel)?.debugDiagnostics ?? .shared
        drawCaptureID = drawDiagnostics?.captureID
        #endif
    }

    override func didDisplay(_ finished: Bool) {
        guard let displayRequestedAt,
              let identifier = (model as? DanmakuKitTextCellModel)?.identifier
        else { return }
        let elapsed = max(0, CACurrentMediaTime() - displayRequestedAt) * 1_000
        self.displayRequestedAt = nil
        #if DEBUG
        let diagnostics = drawDiagnostics ?? .shared
        let captureID = drawCaptureID
        drawDiagnostics = nil
        drawCaptureID = nil
        #else
        let diagnostics = DanmakuRendererDiagnostics.shared
        let captureID: UUID? = nil
        #endif
        guard finished else { return }
        Task { @MainActor [weak diagnostics] in
            diagnostics?.recordDanmakuKitCellDraw(
                identifier: identifier,
                milliseconds: elapsed, captureID: captureID
            )
        }
    }
}
