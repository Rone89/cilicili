import Foundation

struct DanmakuItem: Identifiable, Hashable, Sendable {
    let id: String
    let time: TimeInterval
    let mode: Int
    let fontSize: Double
    let color: UInt32
    let text: String

    var isScrolling: Bool {
        mode == 1 || mode == 2 || mode == 3
    }

    var isBottomAnchored: Bool {
        mode == 4
    }

    var isTopAnchored: Bool {
        mode == 5
    }

    var isSupported: Bool {
        isScrolling || isBottomAnchored || isTopAnchored
    }
}

final class DanmakuXMLParser: NSObject, XMLParserDelegate {
    private let cid: Int
    private let maxItems: Int
    private var items: [DanmakuItem] = []
    private var currentAttributes: [String: String]?
    private var currentText = ""
    private var elementIndex = 0
    private var parseError: Error?

    init(cid: Int, maxItems: Int = 6_000) {
        self.cid = cid
        self.maxItems = maxItems
    }

    func parse(data: Data) throws -> [DanmakuItem] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw parser.parserError ?? parseError ?? BiliAPIError.emptyData
        }
        return items
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "d", items.count < maxItems else { return }
        currentAttributes = attributeDict
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard currentAttributes != nil else { return }
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName == "d", let attributes = currentAttributes else { return }
        defer {
            currentAttributes = nil
            currentText = ""
        }

        guard items.count < maxItems,
              let parameter = attributes["p"],
              let item = Self.makeItem(
                cid: cid,
                elementIndex: elementIndex,
                parameter: parameter,
                text: currentText
              )
        else {
            elementIndex += 1
            return
        }
        elementIndex += 1
        guard item.isSupported else { return }
        items.append(item)
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }

    private static func makeItem(
        cid: Int,
        elementIndex: Int,
        parameter: String,
        text: String
    ) -> DanmakuItem? {
        let parts = parameter.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count >= 4,
              let time = TimeInterval(String(parts[0])),
              let mode = Int(String(parts[1]))
        else { return nil }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }

        let fontSize = Double(String(parts[2])) ?? 25
        let color = UInt32(String(parts[3])) ?? 0xFF_FF_FF
        let id: String
        if parts.count > 7, !parts[7].isEmpty {
            id = "\(cid)-\(parts[7])-\(elementIndex)"
        } else {
            id = "\(cid)-\(elementIndex)"
        }

        return DanmakuItem(
            id: id,
            time: max(0, time),
            mode: mode,
            fontSize: fontSize,
            color: color,
            text: trimmedText
        )
    }
}
