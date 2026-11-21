import CoreGraphics
import Foundation

nonisolated enum ArticleContentParser {
    // MARK: - Opus Paragraphs

    static func parseOpusParagraphs(_ paragraphs: [DynamicJSONValue]) -> [ArticleBlock] {
        var blocks: [ArticleBlock] = []
        for (index, rawParagraph) in paragraphs.enumerated() {
            guard let object = rawParagraph.objectValueForDynamicParsing else { continue }
            let paraType = object["para_type"]?.intValueForDynamicParsing ?? 1
            let alignment = alignment(from: object["align"]?.intValueForDynamicParsing)

            switch paraType {
            case 1:
                let runs = parseOpusTextRuns(object["text"])
                guard !runs.isEmpty else { continue }
                if isOpusHeadingParagraph(object["text"], runs: runs) {
                    let combined = runs.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
                    if !combined.isEmpty {
                        blocks.append(.heading(id: "opus-h-\(index)", level: 2, text: combined))
                    }
                } else {
                    blocks.append(.paragraph(id: "opus-p-\(index)", runs: runs, alignment: alignment))
                }

            case 2:
                let pics = opusPics(from: object["pic"])
                for (picIndex, pic) in pics.enumerated() {
                    blocks.append(
                        .image(
                            id: "opus-img-\(index)-\(picIndex)",
                            url: pic.url,
                            caption: pic.caption,
                            width: pic.width,
                            height: pic.height
                        )
                    )
                }

            case 3:
                blocks.append(.divider(id: "opus-div-\(index)"))

            case 4:
                let runs = parseOpusTextRuns(object["text"])
                if !runs.isEmpty {
                    blocks.append(.blockquote(id: "opus-q-\(index)", runs: runs))
                }

            case 5:
                if let listObj = object["list"]?.objectValueForDynamicParsing,
                   case .array(let rawItems)? = listObj["items"] {
                    let ordered = (listObj["style"]?.intValueForDynamicParsing ?? 0) == 1
                    let items = rawItems.compactMap { item -> [ArticleTextRun]? in
                        if let nodes = item.objectValueForDynamicParsing?["nodes"] {
                            let runs = parseOpusTextNodes(nodes)
                            return runs.isEmpty ? nil : runs
                        }
                        let runs = parseOpusTextRuns(item)
                        return runs.isEmpty ? nil : runs
                    }
                    if !items.isEmpty {
                        blocks.append(.list(id: "opus-list-\(index)", ordered: ordered, items: items))
                    }
                }

            case 6:
                if let cardObj = object["link_card"]?.objectValueForDynamicParsing?["card"]?.objectValueForDynamicParsing
                    ?? object["link_card"]?.objectValueForDynamicParsing {
                    let cardType = cardObj["type"]?.textValueForDynamicParsing
                    let common = cardObj["common"]?.objectValueForDynamicParsing
                        ?? cardObj["ugc"]?.objectValueForDynamicParsing
                        ?? cardObj["opus"]?.objectValueForDynamicParsing
                        ?? cardObj["goods"]?.objectValueForDynamicParsing
                        ?? cardObj
                    let title = common["title"]?.textValueForDynamicParsing
                        ?? common["head_text"]?.textValueForDynamicParsing
                        ?? common["desc"]?.textValueForDynamicParsing
                        ?? "相关内容"
                    let subtitle = common["desc_first"]?.textValueForDynamicParsing
                        ?? common["desc_second"]?.textValueForDynamicParsing
                        ?? common["sub_title"]?.textValueForDynamicParsing
                        ?? cardType
                    let cover = common["cover"]?.textValueForDynamicParsing
                        .map { $0.normalizedBiliURL() }
                        .flatMap(URL.init(string:))
                    let url = (common["jump_url"]?.textValueForDynamicParsing
                        ?? common["uri"]?.textValueForDynamicParsing
                        ?? cardObj["jump_url"]?.textValueForDynamicParsing)
                        .flatMap(normalizedWebURL)
                    blocks.append(
                        .linkCard(
                            id: "opus-card-\(index)",
                            title: title,
                            subtitle: subtitle,
                            coverURL: cover,
                            url: url
                        )
                    )
                }

            case 7:
                if let codeObj = object["code"]?.objectValueForDynamicParsing,
                   let content = codeObj["content"]?.textValueForDynamicParsing,
                   !content.isEmpty {
                    let lang = codeObj["lang"]?.textValueForDynamicParsing
                    blocks.append(.code(id: "opus-code-\(index)", language: lang, text: content))
                }

            default:
                let runs = parseOpusTextRuns(object["text"])
                if !runs.isEmpty {
                    blocks.append(.paragraph(id: "opus-p-\(index)", runs: runs, alignment: alignment))
                }
            }
        }
        return blocks
    }

    private static func alignment(from raw: Int?) -> ArticleTextAlignment {
        switch raw {
        case 1: return .center
        case 2: return .trailing
        default: return .leading
        }
    }

    private static func isOpusHeadingParagraph(_ rawText: DynamicJSONValue?, runs: [ArticleTextRun]) -> Bool {
        guard let nodes = rawText?.objectValueForDynamicParsing?["nodes"],
              case .array(let array) = nodes,
              !array.isEmpty
        else { return false }
        let hasLargeWord = array.contains { node in
            guard let word = node.objectValueForDynamicParsing?["word"]?.objectValueForDynamicParsing else {
                return false
            }
            let fontSize = word["font_size"]?.intValueForDynamicParsing ?? 0
            return fontSize >= 20
        }
        return hasLargeWord && runs.map(\.text).joined().count <= 80
    }

    private static func parseOpusTextRuns(_ rawText: DynamicJSONValue?) -> [ArticleTextRun] {
        guard let textObj = rawText?.objectValueForDynamicParsing else { return [] }
        return parseOpusTextNodes(textObj["nodes"])
    }

    private static func parseOpusTextNodes(_ rawNodes: DynamicJSONValue?) -> [ArticleTextRun] {
        guard case .array(let nodes)? = rawNodes else { return [] }
        var runs: [ArticleTextRun] = []

        for node in nodes {
            guard let obj = node.objectValueForDynamicParsing else { continue }
            let nodeType = obj["type"]?.textValueForDynamicParsing ?? ""
            if nodeType == "TEXT_NODE_TYPE_WORD" || obj["word"] != nil {
                guard let word = obj["word"]?.objectValueForDynamicParsing,
                      let words = word["words"]?.textValueForDynamicParsing,
                      !words.isEmpty
                else { continue }
                let style = word["style"]?.objectValueForDynamicParsing
                runs.append(
                    ArticleTextRun(
                        text: words,
                        isBold: boolFlag(style?["bold"]),
                        isItalic: boolFlag(style?["italic"]),
                        isStrikethrough: boolFlag(style?["strikethrough"]),
                        linkURL: nil
                    )
                )
            } else if nodeType == "TEXT_NODE_TYPE_RICH" || obj["rich"] != nil {
                guard let rich = obj["rich"]?.objectValueForDynamicParsing else { continue }
                let text = rich["orig_text"]?.textValueForDynamicParsing
                    ?? rich["text"]?.textValueForDynamicParsing
                    ?? ""
                guard !text.isEmpty else { continue }
                let linkURL = rich["jump_url"]?.textValueForDynamicParsing.flatMap(normalizedWebURL)
                let style = rich["style"]?.objectValueForDynamicParsing
                runs.append(
                    ArticleTextRun(
                        text: text,
                        isBold: boolFlag(style?["bold"]),
                        isItalic: boolFlag(style?["italic"]),
                        isStrikethrough: boolFlag(style?["strikethrough"]),
                        linkURL: linkURL
                    )
                )
            } else if nodeType == "TEXT_NODE_TYPE_EMOJI" || obj["emoji"] != nil {
                if let emojiText = obj["emoji"]?.objectValueForDynamicParsing?["text"]?.textValueForDynamicParsing,
                   !emojiText.isEmpty {
                    runs.append(ArticleTextRun(text: emojiText))
                }
            }
        }
        return runs
    }

    private static func opusPics(from rawPic: DynamicJSONValue?) -> [(url: URL, caption: String?, width: CGFloat?, height: CGFloat?)] {
        guard let picObj = rawPic?.objectValueForDynamicParsing,
              case .array(let rawPics)? = picObj["pics"]
        else { return [] }
        return rawPics.compactMap { entry in
            guard let obj = entry.objectValueForDynamicParsing,
                  let rawURL = obj["url"]?.textValueForDynamicParsing?.normalizedBiliURL(),
                  let url = URL(string: rawURL)
            else { return nil }
            let width = obj["width"]?.intValueForDynamicParsing.map(CGFloat.init)
            let height = obj["height"]?.intValueForDynamicParsing.map(CGFloat.init)
            let caption = obj["caption"]?.textValueForDynamicParsing?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (url, caption?.isEmpty == true ? nil : caption, width, height)
        }
    }

    private static func boolFlag(_ value: DynamicJSONValue?) -> Bool {
        guard let value else { return false }
        if case .bool(let flag) = value { return flag }
        return (value.intValueForDynamicParsing ?? 0) != 0
    }

    // MARK: - Classic HTML

    static func parseHTML(_ html: String) -> [ArticleBlock] {
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var blocks: [ArticleBlock] = []
        var blockCounter = 0

        func nextID(_ prefix: String) -> String {
            blockCounter += 1
            return "\(prefix)-\(blockCounter)"
        }

        // Tokenize top-level and nested HTML tags cleanly.
        let tokens = tokenizeHTML(html)
        var index = 0

        func appendParagraphRuns(_ runs: [ArticleTextRun], alignment: ArticleTextAlignment = .leading) {
            let trimmedRuns = trimBoundaryWhitespace(runs)
            guard !trimmedRuns.isEmpty else { return }
            blocks.append(.paragraph(id: nextID("html-p"), runs: trimmedRuns, alignment: alignment))
        }

        while index < tokens.count {
            let token = tokens[index]
            switch token {
            case .text(let rawText):
                let decoded = decodeHTMLEntities(rawText).trimmingCharacters(in: .whitespacesAndNewlines)
                if !decoded.isEmpty {
                    appendParagraphRuns([ArticleTextRun(text: decoded)])
                }
                index += 1

            case .tag(let name, let attrs, let isClosing, let isSelfClosing):
                if isClosing {
                    index += 1
                    continue
                }
                switch name {
                case "hr":
                    blocks.append(.divider(id: nextID("html-hr")))
                    index += 1

                case "img":
                    if let imgBlock = makeImageBlock(id: nextID("html-img"), attrs: attrs, caption: nil) {
                        blocks.append(imgBlock)
                    }
                    index += 1

                case "figure":
                    let (inner, nextIdx) = collectUntilClosing("figure", tokens: tokens, from: index + 1)
                    let imgTag = inner.first {
                        if case .tag("img", _, false, _) = $0 { return true }
                        return false
                    }
                    let captionText = extractPlainText(from: inner, insideTag: "figcaption")
                    if case .tag(_, let imgAttrs, _, _) = imgTag,
                       let imgBlock = makeImageBlock(id: nextID("html-fig"), attrs: imgAttrs, caption: captionText) {
                        blocks.append(imgBlock)
                    }
                    index = nextIdx

                case "h1", "h2", "h3", "h4":
                    let level = Int(String(name.dropFirst())) ?? 2
                    let (inner, nextIdx) = isSelfClosing
                        ? ([], index + 1)
                        : collectUntilClosing(name, tokens: tokens, from: index + 1)
                    let text = extractPlainText(from: inner).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        blocks.append(.heading(id: nextID("html-h"), level: level, text: text))
                    }
                    index = nextIdx

                case "blockquote":
                    let (inner, nextIdx) = isSelfClosing
                        ? ([], index + 1)
                        : collectUntilClosing("blockquote", tokens: tokens, from: index + 1)
                    let runs = trimBoundaryWhitespace(parseInlineTokens(inner))
                    if !runs.isEmpty {
                        blocks.append(.blockquote(id: nextID("html-q"), runs: runs))
                    }
                    index = nextIdx

                case "pre":
                    let (inner, nextIdx) = isSelfClosing
                        ? ([], index + 1)
                        : collectUntilClosing("pre", tokens: tokens, from: index + 1)
                    let text = extractPlainText(from: inner, preservesLineBreaks: true)
                        .trimmingCharacters(in: .newlines)
                    if !text.isEmpty {
                        blocks.append(.code(id: nextID("html-code"), language: attrs["data-lang"], text: text))
                    }
                    index = nextIdx

                case "ul", "ol":
                    let ordered = name == "ol"
                    let (inner, nextIdx) = isSelfClosing
                        ? ([], index + 1)
                        : collectUntilClosing(name, tokens: tokens, from: index + 1)
                    let listItems = extractListItems(from: inner)
                    if !listItems.isEmpty {
                        blocks.append(.list(id: nextID("html-list"), ordered: ordered, items: listItems))
                    }
                    index = nextIdx

                case "p":
                    let (inner, nextIdx) = isSelfClosing
                        ? ([], index + 1)
                        : collectUntilClosing("p", tokens: tokens, from: index + 1)
                    let alignment = htmlAlignment(from: attrs["style"])
                    // Split paragraph if an inline <img> is embedded inside <p>
                    var currentInline: [HTMLToken] = []
                    for item in inner {
                        if case .tag("img", let imgAttrs, false, _) = item {
                            appendParagraphRuns(parseInlineTokens(currentInline), alignment: alignment)
                            currentInline.removeAll()
                            if let imgBlock = makeImageBlock(id: nextID("html-pimg"), attrs: imgAttrs, caption: nil) {
                                blocks.append(imgBlock)
                            }
                        } else {
                            currentInline.append(item)
                        }
                    }
                    appendParagraphRuns(parseInlineTokens(currentInline), alignment: alignment)
                    index = nextIdx

                default:
                    if isSelfClosing {
                        index += 1
                    } else {
                        let (inner, nextIdx) = collectUntilClosing(name, tokens: tokens, from: index + 1)
                        let hasBlockChild = inner.contains {
                            if case .tag(let child, _, false, _) = $0 {
                                return ["p", "figure", "img", "h1", "h2", "h3", "h4", "blockquote", "pre", "ul", "ol", "hr", "div"].contains(child)
                            }
                            return false
                        }
                        if hasBlockChild {
                            index += 1
                        } else {
                            appendParagraphRuns(parseInlineTokens(inner))
                            index = nextIdx
                        }
                    }
                }
            }
        }
        return blocks
    }

    private enum HTMLToken {
        case text(String)
        case tag(name: String, attributes: [String: String], isClosing: Bool, isSelfClosing: Bool)
    }

    private static func tokenizeHTML(_ html: String) -> [HTMLToken] {
        var tokens: [HTMLToken] = []
        var cursor = html.startIndex
        let selfClosingTags: Set<String> = ["img", "br", "hr", "meta", "link", "input", "source"]

        while cursor < html.endIndex {
            guard let ltIndex = html[cursor...].firstIndex(of: "<") else {
                let tail = String(html[cursor...])
                if !tail.isEmpty { tokens.append(.text(tail)) }
                break
            }
            if ltIndex > cursor {
                tokens.append(.text(String(html[cursor..<ltIndex])))
            }
            guard let gtIndex = html[ltIndex...].firstIndex(of: ">") else {
                tokens.append(.text(String(html[ltIndex...])))
                break
            }
            let rawTag = String(html[html.index(after: ltIndex)..<gtIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            cursor = html.index(after: gtIndex)

            if rawTag.isEmpty || rawTag.hasPrefix("!") || rawTag.hasPrefix("?") {
                continue
            }
            let isClosing = rawTag.hasPrefix("/")
            let body = isClosing ? String(rawTag.dropFirst()).trimmingCharacters(in: .whitespaces) : rawTag
            let isExplicitSelfClosing = body.hasSuffix("/")
            let cleanBody = isExplicitSelfClosing ? String(body.dropLast()).trimmingCharacters(in: .whitespaces) : body

            let parts = cleanBody.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            guard let tagNameRaw = parts.first else { continue }
            let tagName = tagNameRaw.lowercased()
            let attrs = parts.count > 1 ? parseHTMLAttributes(String(parts[1])) : [:]
            tokens.append(
                .tag(
                    name: tagName,
                    attributes: attrs,
                    isClosing: isClosing,
                    isSelfClosing: isExplicitSelfClosing || selfClosingTags.contains(tagName)
                )
            )
        }
        return tokens
    }

    private static func parseHTMLAttributes(_ raw: String) -> [String: String] {
        var result: [String: String] = [:]
        guard let regex = try? NSRegularExpression(
            pattern: #"([a-zA-Z0-9_-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))"#
        ) else { return result }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        for match in regex.matches(in: raw, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: raw) else { continue }
            let key = raw[keyRange].lowercased()
            let valueRange = [2, 3, 4]
                .compactMap { Range(match.range(at: $0), in: raw) }
                .first
            let value = valueRange.map { decodeHTMLEntities(String(raw[$0])) } ?? ""
            result[key] = value
        }
        return result
    }

    private static func collectUntilClosing(
        _ tagName: String,
        tokens: [HTMLToken],
        from startIndex: Int
    ) -> ([HTMLToken], Int) {
        var depth = 1
        var collected: [HTMLToken] = []
        var idx = startIndex
        while idx < tokens.count {
            let token = tokens[idx]
            if case .tag(let name, _, let isClosing, let isSelfClosing) = token, name == tagName {
                if isClosing {
                    depth -= 1
                    if depth == 0 {
                        return (collected, idx + 1)
                    }
                } else if !isSelfClosing {
                    depth += 1
                }
            }
            collected.append(token)
            idx += 1
        }
        return (collected, idx)
    }

    private static func makeImageBlock(id: String, attrs: [String: String], caption: String?) -> ArticleBlock? {
        let rawSource = (attrs["data-src"]?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? (attrs["src"]?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        guard let rawSource else { return nil }
        let normalized = rawSource.normalizedBiliURL()
        guard let url = URL(string: normalized), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return nil
        }
        let width = attrs["width"].flatMap(Double.init).map { CGFloat($0) }
        let height = attrs["height"].flatMap(Double.init).map { CGFloat($0) }
        let cleanCaption = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .image(
            id: id,
            url: url,
            caption: cleanCaption?.isEmpty == true ? nil : cleanCaption,
            width: width,
            height: height
        )
    }

    private static func extractListItems(from tokens: [HTMLToken]) -> [[ArticleTextRun]] {
        var items: [[ArticleTextRun]] = []
        var idx = 0
        while idx < tokens.count {
            if case .tag("li", _, false, let isSelfClosing) = tokens[idx] {
                let (inner, nextIdx) = isSelfClosing ? ([], idx + 1) : collectUntilClosing("li", tokens: tokens, from: idx + 1)
                let runs = trimBoundaryWhitespace(parseInlineTokens(inner))
                if !runs.isEmpty { items.append(runs) }
                idx = nextIdx
            } else {
                idx += 1
            }
        }
        return items
    }

    private static func extractPlainText(
        from tokens: [HTMLToken],
        insideTag targetTag: String? = nil,
        preservesLineBreaks: Bool = false
    ) -> String {
        if let targetTag {
            var idx = 0
            while idx < tokens.count {
                if case .tag(let name, _, false, let isSelfClosing) = tokens[idx], name == targetTag {
                    let (inner, _) = isSelfClosing ? ([], idx + 1) : collectUntilClosing(name, tokens: tokens, from: idx + 1)
                    return extractPlainText(from: inner, preservesLineBreaks: preservesLineBreaks)
                }
                idx += 1
            }
            return ""
        }
        var buffer = ""
        for token in tokens {
            switch token {
            case .text(let text):
                buffer += decodeHTMLEntities(text)
            case .tag(let name, _, let isClosing, _):
                if !isClosing && name == "br" {
                    buffer += "\n"
                } else if preservesLineBreaks && isClosing && (name == "p" || name == "div") {
                    buffer += "\n"
                }
            }
        }
        return buffer
    }

    private static func parseInlineTokens(_ tokens: [HTMLToken]) -> [ArticleTextRun] {
        var runs: [ArticleTextRun] = []
        var boldDepth = 0
        var italicDepth = 0
        var strikeDepth = 0
        var codeDepth = 0
        var linkStack: [URL?] = []

        for token in tokens {
            switch token {
            case .text(let raw):
                let decoded = decodeHTMLEntities(raw)
                if !decoded.isEmpty {
                    runs.append(
                        ArticleTextRun(
                            text: decoded,
                            isBold: boldDepth > 0,
                            isItalic: italicDepth > 0,
                            isStrikethrough: strikeDepth > 0,
                            isCode: codeDepth > 0,
                            linkURL: linkStack.last ?? nil
                        )
                    )
                }
            case .tag(let name, let attrs, let isClosing, _):
                switch name {
                case "br":
                    if !isClosing {
                        runs.append(ArticleTextRun(text: "\n"))
                    }
                case "strong", "b":
                    boldDepth = max(0, boldDepth + (isClosing ? -1 : 1))
                case "em", "i":
                    italicDepth = max(0, italicDepth + (isClosing ? -1 : 1))
                case "del", "s", "strike":
                    strikeDepth = max(0, strikeDepth + (isClosing ? -1 : 1))
                case "code":
                    codeDepth = max(0, codeDepth + (isClosing ? -1 : 1))
                case "a":
                    if isClosing {
                        if !linkStack.isEmpty { linkStack.removeLast() }
                    } else {
                        linkStack.append(attrs["href"].flatMap(normalizedWebURL))
                    }
                default:
                    break
                }
            }
        }
        return runs
    }

    private static func trimBoundaryWhitespace(_ runs: [ArticleTextRun]) -> [ArticleTextRun] {
        var result = runs
        while let first = result.first {
            let trimmed = first.text.replacingOccurrences(of: #"^\s+"#, with: "", options: .regularExpression)
            if trimmed.isEmpty {
                result.removeFirst()
            } else {
                result[0] = ArticleTextRun(
                    text: trimmed,
                    isBold: first.isBold,
                    isItalic: first.isItalic,
                    isStrikethrough: first.isStrikethrough,
                    isCode: first.isCode,
                    linkURL: first.linkURL
                )
                break
            }
        }
        while let last = result.last {
            let trimmed = last.text.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
            if trimmed.isEmpty {
                result.removeLast()
            } else {
                result[result.count - 1] = ArticleTextRun(
                    text: trimmed,
                    isBold: last.isBold,
                    isItalic: last.isItalic,
                    isStrikethrough: last.isStrikethrough,
                    isCode: last.isCode,
                    linkURL: last.linkURL
                )
                break
            }
        }
        return result
    }

    private static func htmlAlignment(from style: String?) -> ArticleTextAlignment {
        guard let lower = style?.lowercased() else { return .leading }
        if lower.contains("text-align:center") || lower.contains("text-align: center") {
            return .center
        }
        if lower.contains("text-align:right") || lower.contains("text-align: right") {
            return .trailing
        }
        return .leading
    }

    private static func normalizedWebURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.hasPrefix("//") ? "https:" + trimmed : trimmed
        guard let url = URL(string: normalized),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil
        else { return nil }
        return url
    }

    static func decodeHTMLEntities(_ text: String) -> String {
        var output = text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
        guard let regex = try? NSRegularExpression(pattern: #"&#(x?[0-9a-fA-F]+);"#) else {
            return output
        }
        let matches = regex.matches(in: output, range: NSRange(output.startIndex..<output.endIndex, in: output))
        for match in matches.reversed() {
            guard let fullRange = Range(match.range(at: 0), in: output),
                  let codeRange = Range(match.range(at: 1), in: output)
            else { continue }
            let rawCode = String(output[codeRange])
            let scalarValue: UInt32?
            if rawCode.lowercased().hasPrefix("x") {
                scalarValue = UInt32(rawCode.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(rawCode, radix: 10)
            }
            if let scalarValue, let scalar = UnicodeScalar(scalarValue) {
                output.replaceSubrange(fullRange, with: String(scalar))
            }
        }
        return output
    }
}
