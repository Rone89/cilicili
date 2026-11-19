import UIKit

/// Renderer-independent rules; the existing DanmakuKit path keeps its values.
enum DanmakuRenderPolicy {
    static func supports(_ item: DanmakuItem, settings: DanmakuSettings) -> Bool {
        guard item.isSupported,
              !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if item.isScrolling { return settings.danmakuKit.enablesFloating }
        if item.isTopAnchored { return settings.danmakuKit.enablesTop }
        return settings.danmakuKit.enablesBottom
    }

    nonisolated static func duration(for item: DanmakuItem, viewportWidth: CGFloat) -> TimeInterval {
        item.isScrolling ? (viewportWidth > 640 ? 8.4 : 7.2) : 4.2
    }

    /// 滚动弹幕固定速度（pt/秒）：时长 =（画布宽 + 位图宽）/ 速度。
    /// 速度取横屏既有校准（(852+187)/8.4 ≈ 124），竖屏画布窄则时长自然缩短，
    /// 观感速度两个方向一致；弹幕位图随文本长度变化，飞行距离同步伸缩。
    nonisolated static func scrollDuration(viewportWidth: CGFloat, bitmapWidth: CGFloat) -> TimeInterval {
        let canvasWidth = max(viewportWidth, 1)
        let width = max(bitmapWidth, 1)
        return Double((canvasWidth + width) / 124)
    }

    nonisolated static func font(for item: DanmakuItem, viewportWidth: CGFloat, scale: Double,
                                  weight: DanmakuFontWeightOption) -> UIFont {
        let compact: CGFloat = viewportWidth > 640 ? 0.86 : 0.70
        let maximum: CGFloat = viewportWidth > 640 ? 24 : 18
        let minimum: CGFloat = viewportWidth > 640 ? 15 : 13
        let pointSize = min(max(CGFloat(item.fontSize) * compact * CGFloat(scale), minimum * 0.9), maximum * 1.35)
        let uiWeight: UIFont.Weight
        switch weight {
        case .light: uiWeight = .light
        case .regular: uiWeight = .regular
        case .medium: uiWeight = .medium
        case .semibold: uiWeight = .semibold
        case .bold: uiWeight = .bold
        case .heavy: uiWeight = .heavy
        case .black: uiWeight = .black
        }
        return UIFont.systemFont(ofSize: pointSize, weight: uiWeight)
    }

    static func maximumActiveCount(width: CGFloat, settings: DanmakuSettings,
                                   rate: Double, loadShedding: Bool) -> Int {
        let kit = settings.danmakuKit
        let isUnlimited = kit.isUnlimitedVisibleCount
        let baseCap = Double(isUnlimited
            ? DanmakuKitRenderSettings.unlimitedProtectionCeiling
            : kit.normalizedMaxVisibleCount)
        let widthFactor = width > 640 ? 1.0 : 0.70
        let environment = PlaybackEnvironment.current
        let sheddingFactor = loadShedding ? 0.55 : 1.0
        let rateFactor = isUnlimited ? 1.0 : (rate >= 1.75 ? 0.72 : (rate > 1.15 ? 0.85 : 1.0))
        let thermalFactor: Double
        if environment.isThermallyConstrained || environment.isLowPowerModeEnabled {
            thermalFactor = min(settings.loadFactor, isUnlimited ? 0.70 : 0.55)
        } else if environment.isThermallyElevated {
            thermalFactor = min(settings.loadFactor, isUnlimited ? 0.85 : 0.72)
        } else if environment.shouldPreferConservativePlayback {
            thermalFactor = min(settings.loadFactor, isUnlimited ? 0.90 : 0.80)
        } else {
            thermalFactor = isUnlimited ? 1.0 : settings.loadFactor
        }
        let resolved = Int((baseCap * widthFactor * thermalFactor * sheddingFactor * rateFactor).rounded())
        return max(loadShedding ? 8 : 12, resolved)
    }
}

/// 可跨并发域传递的已解包表情位图快照。
nonisolated struct DanmakuEmoteBitmap: Sendable {
    let cgImage: CGImage
    let scale: CGFloat

    var uiImage: UIImage {
        UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
}

/// 弹幕内嵌表情与文字属性串生成器（纯计算，支持在后台预热任务中无锁执行）。
nonisolated enum DanmakuEmoteAttributedTextRenderer {
    static func render(
        _ text: String,
        emotes: [String: BiliInlineEmote],
        font: UIFont,
        color: UIColor,
        shadow: NSShadow,
        cachedImageForURL: (URL) -> UIImage?,
        placeholderImageForSize: ((CGFloat) -> UIImage)? = nil
    ) -> (attributedText: NSAttributedString, missingImageURLs: [URL]) {
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .shadow: shadow,
        ]
        guard !text.isEmpty, !emotes.isEmpty else {
            return (NSAttributedString(string: text, attributes: baseAttributes), [])
        }

        let result = NSMutableAttributedString(string: "")
        var missingImageURLs = [URL]()
        var cursor = text.startIndex
        let tokens = emotes.keys.filter { !$0.isEmpty }
        let resolvePlaceholder = placeholderImageForSize ?? { Self.placeholderImage(size: $0) }

        while cursor < text.endIndex,
              let match = nextEmote(in: text, from: cursor, tokens: tokens, emotes: emotes) {
            if cursor < match.range.lowerBound {
                result.append(
                    NSAttributedString(
                        string: String(text[cursor..<match.range.lowerBound]),
                        attributes: baseAttributes
                    )
                )
            }
            result.append(
                attachment(
                    for: match.emote,
                    token: String(text[match.range]),
                    font: font,
                    color: color,
                    shadow: shadow,
                    cachedImageForURL: cachedImageForURL,
                    placeholderImageForSize: resolvePlaceholder,
                    missingImageURLs: &missingImageURLs
                )
            )
            cursor = match.range.upperBound
        }
        if cursor < text.endIndex {
            result.append(
                NSAttributedString(string: String(text[cursor...]), attributes: baseAttributes)
            )
        }
        if result.length == 0 {
            result.append(NSAttributedString(string: text, attributes: baseAttributes))
        }
        return (result, Array(Set(missingImageURLs)))
    }

    static func placeholderImage(size: CGFloat) -> UIImage {
        let clampedSize = max(size, 4)
        return UIGraphicsImageRenderer(size: CGSize(width: clampedSize, height: clampedSize)).image { _ in
            UIColor.systemPink.withAlphaComponent(0.12).setFill()
            UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: clampedSize - 2, height: clampedSize - 2)).fill()
            UIColor.systemPink.withAlphaComponent(0.35).setStroke()
            UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: clampedSize - 2, height: clampedSize - 2)).stroke()
        }
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
        cachedImageForURL: (URL) -> UIImage?,
        placeholderImageForSize: (CGFloat) -> UIImage,
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
        if let image = cachedImageForURL(url) {
            attachment.image = image
        } else {
            attachment.image = placeholderImageForSize(emoteSize)
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
