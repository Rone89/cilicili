import Foundation

struct DanmakuSettings: Codable, Equatable, Sendable {
    var fontScale: Double
    var opacity: Double
    var displayArea: DanmakuDisplayArea
    var fontWeight: DanmakuFontWeightOption
    var loadFactor: Double

    init(
        fontScale: Double,
        opacity: Double,
        displayArea: DanmakuDisplayArea,
        fontWeight: DanmakuFontWeightOption,
        loadFactor: Double = 1.0
    ) {
        self.fontScale = fontScale
        self.opacity = opacity
        self.displayArea = displayArea
        self.fontWeight = fontWeight
        self.loadFactor = loadFactor
    }

    private enum CodingKeys: String, CodingKey {
        case fontScale
        case opacity
        case displayArea
        case fontWeight
        case loadFactor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.fontScale = try container.decode(Double.self, forKey: .fontScale)
        self.opacity = try container.decode(Double.self, forKey: .opacity)
        self.displayArea = try container.decode(DanmakuDisplayArea.self, forKey: .displayArea)
        self.fontWeight = try container.decode(DanmakuFontWeightOption.self, forKey: .fontWeight)
        self.loadFactor = try container.decodeIfPresent(Double.self, forKey: .loadFactor) ?? 1.0
    }

    static let `default` = DanmakuSettings(
        fontScale: 1.0,
        opacity: 0.92,
        displayArea: .topHalf,
        fontWeight: .semibold,
        loadFactor: 1.0
    )

    var normalized: DanmakuSettings {
        DanmakuSettings(
            fontScale: min(max(fontScale, 0.7), 1.45),
            opacity: min(max(opacity, 0.25), 1.0),
            displayArea: displayArea,
            fontWeight: fontWeight,
            loadFactor: min(max(loadFactor, 0.35), 1.0)
        )
    }
}

enum DanmakuDisplayArea: String, Codable, CaseIterable, Identifiable, Sendable {
    case topHalf
    case center
    case full

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topHalf:
            return "上半屏"
        case .center:
            return "居中"
        case .full:
            return "全屏"
        }
    }
}

enum DanmakuFontWeightOption: String, Codable, CaseIterable, Identifiable, Sendable {
    case regular
    case semibold
    case bold

    var id: String { rawValue }

    var title: String {
        switch self {
        case .regular:
            return "常规"
        case .semibold:
            return "中粗"
        case .bold:
            return "粗体"
        }
    }
}

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
