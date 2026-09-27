import Foundation

struct DanmakuSettings: Codable, Equatable, Sendable {
    var loadFactor: Double
    var hidesInPortrait: Bool
    var danmakuKit: DanmakuKitRenderSettings

    nonisolated init(
        loadFactor: Double = 1.0,
        hidesInPortrait: Bool = true,
        danmakuKit: DanmakuKitRenderSettings = .default
    ) {
        self.loadFactor = loadFactor
        self.hidesInPortrait = hidesInPortrait
        self.danmakuKit = danmakuKit
    }

    nonisolated init(
        fontScale: Double,
        opacity: Double,
        displayArea: DanmakuDisplayArea,
        fontWeight: DanmakuFontWeightOption,
        loadFactor: Double = 1.0,
        hidesInPortrait: Bool = true,
        allowsDanmakuOverlap: Bool = false,
        danmakuKit: DanmakuKitRenderSettings? = nil
    ) {
        self.init(
            loadFactor: loadFactor,
            hidesInPortrait: hidesInPortrait,
            danmakuKit: danmakuKit ?? DanmakuKitRenderSettings(
                displayArea: displayArea,
                allowsDanmakuOverlap: allowsDanmakuOverlap,
                fontScale: fontScale,
                fontWeight: fontWeight,
                opacity: opacity
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        // Legacy flattened values remain decodable for existing installations.
        case fontScale
        case opacity
        case displayArea
        case fontWeight
        case loadFactor
        case hidesInPortrait
        case allowsDanmakuOverlap
        case danmakuKit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.loadFactor = try container.decodeIfPresent(Double.self, forKey: .loadFactor) ?? 1.0
        self.hidesInPortrait = try container.decodeIfPresent(Bool.self, forKey: .hidesInPortrait) ?? true
        var kitSettings = try container.decodeIfPresent(DanmakuKitRenderSettings.self, forKey: .danmakuKit) ?? .default
        let legacyDisplayArea = try container.decodeIfPresent(DanmakuDisplayArea.self, forKey: .displayArea)
        let legacyAllowsOverlap = try container.decodeIfPresent(Bool.self, forKey: .allowsDanmakuOverlap)
        let legacyFontScale = try container.decodeIfPresent(Double.self, forKey: .fontScale)
        let legacyFontWeight = try container.decodeIfPresent(DanmakuFontWeightOption.self, forKey: .fontWeight)
        let legacyOpacity = try container.decodeIfPresent(Double.self, forKey: .opacity)

        if let kitDecoder = try? container.superDecoder(forKey: .danmakuKit),
           let kitContainer = try? kitDecoder.container(keyedBy: DanmakuKitRenderSettings.CodingKeys.self) {
            if !kitContainer.contains(.displayArea), let legacyDisplayArea { kitSettings.displayArea = legacyDisplayArea }
            if !kitContainer.contains(.allowsDanmakuOverlap), let legacyAllowsOverlap { kitSettings.allowsDanmakuOverlap = legacyAllowsOverlap }
            if !kitContainer.contains(.fontScale), let legacyFontScale { kitSettings.fontScale = legacyFontScale }
            if !kitContainer.contains(.fontWeight), let legacyFontWeight { kitSettings.fontWeight = legacyFontWeight }
            if !kitContainer.contains(.opacity), let legacyOpacity { kitSettings.opacity = legacyOpacity }
        } else {
            if let legacyDisplayArea { kitSettings.displayArea = legacyDisplayArea }
            if let legacyAllowsOverlap { kitSettings.allowsDanmakuOverlap = legacyAllowsOverlap }
            if let legacyFontScale { kitSettings.fontScale = legacyFontScale }
            if let legacyFontWeight { kitSettings.fontWeight = legacyFontWeight }
            if let legacyOpacity { kitSettings.opacity = legacyOpacity }
        }
        self.danmakuKit = kitSettings
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(loadFactor, forKey: .loadFactor)
        try container.encode(hidesInPortrait, forKey: .hidesInPortrait)
        try container.encode(danmakuKit, forKey: .danmakuKit)
    }

    static let `default` = DanmakuSettings(
        loadFactor: 1.0,
        hidesInPortrait: true,
        danmakuKit: .default
    )

    nonisolated var normalized: DanmakuSettings {
        DanmakuSettings(
            loadFactor: min(max(loadFactor, 0.35), 1.0),
            hidesInPortrait: hidesInPortrait,
            danmakuKit: danmakuKit.normalized
        )
    }
}

nonisolated struct DanmakuKitRenderSettings: Codable, Equatable, Sendable {
    var displayArea: DanmakuDisplayArea
    var allowsDanmakuOverlap: Bool
    var fontScale: Double
    var fontWeight: DanmakuFontWeightOption
    var opacity: Double
    var trackHeight: Double
    var topPadding: Double
    var bottomPadding: Double
    var enablesFloating: Bool
    var enablesTop: Bool
    var enablesBottom: Bool

    nonisolated init(
        displayArea: DanmakuDisplayArea = .topHalf,
        allowsDanmakuOverlap: Bool = false,
        fontScale: Double = 1.0,
        fontWeight: DanmakuFontWeightOption = .semibold,
        opacity: Double = 0.92,
        trackHeight: Double = 30,
        topPadding: Double = 0,
        bottomPadding: Double = 0,
        enablesFloating: Bool = true,
        enablesTop: Bool = true,
        enablesBottom: Bool = true
    ) {
        self.displayArea = displayArea
        self.allowsDanmakuOverlap = allowsDanmakuOverlap
        self.fontScale = fontScale
        self.fontWeight = fontWeight
        self.opacity = opacity
        self.trackHeight = trackHeight
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
        self.enablesFloating = enablesFloating
        self.enablesTop = enablesTop
        self.enablesBottom = enablesBottom
    }

    enum CodingKeys: String, CodingKey {
        case displayArea
        case allowsDanmakuOverlap
        case fontScale
        case fontWeight
        case opacity
        case trackHeight
        case topPadding
        case bottomPadding
        case enablesFloating
        case enablesTop
        case enablesBottom
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            displayArea: try container.decodeIfPresent(DanmakuDisplayArea.self, forKey: .displayArea) ?? .topHalf,
            allowsDanmakuOverlap: try container.decodeIfPresent(Bool.self, forKey: .allowsDanmakuOverlap) ?? false,
            fontScale: try container.decodeIfPresent(Double.self, forKey: .fontScale) ?? 1.0,
            fontWeight: try container.decodeIfPresent(DanmakuFontWeightOption.self, forKey: .fontWeight) ?? .semibold,
            opacity: try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.92,
            trackHeight: try container.decodeIfPresent(Double.self, forKey: .trackHeight) ?? 30,
            topPadding: try container.decodeIfPresent(Double.self, forKey: .topPadding) ?? 0,
            bottomPadding: try container.decodeIfPresent(Double.self, forKey: .bottomPadding) ?? 0,
            enablesFloating: try container.decodeIfPresent(Bool.self, forKey: .enablesFloating) ?? true,
            enablesTop: try container.decodeIfPresent(Bool.self, forKey: .enablesTop) ?? true,
            enablesBottom: try container.decodeIfPresent(Bool.self, forKey: .enablesBottom) ?? true
        )
    }

    nonisolated static let `default` = DanmakuKitRenderSettings()

    nonisolated var normalized: DanmakuKitRenderSettings {
        DanmakuKitRenderSettings(
            displayArea: displayArea.normalized,
            allowsDanmakuOverlap: allowsDanmakuOverlap,
            fontScale: min(max(fontScale.isFinite ? fontScale : 1.0, 0.7), 1.45),
            fontWeight: fontWeight,
            opacity: min(max(opacity.isFinite ? opacity : 0.92, 0.25), 1.0),
            trackHeight: min(max(trackHeight.isFinite ? trackHeight : 30, 22), 60),
            topPadding: min(max(topPadding.isFinite ? topPadding : 0, 0), 100),
            bottomPadding: min(max(bottomPadding.isFinite ? bottomPadding : 0, 0), 100),
            enablesFloating: enablesFloating,
            enablesTop: enablesTop,
            enablesBottom: enablesBottom
        )
    }
}

nonisolated struct BiliInlineEmote: Hashable, Sendable {
    let token: String
    let url: String
    let width: Double?
    let height: Double?

    init(
        token: String,
        url: String,
        width: Double? = nil,
        height: Double? = nil
    ) {
        self.token = token
        self.url = url
        self.width = width
        self.height = height
    }

    var displayURL: String? {
        url.normalizedBiliURL()
    }
}

nonisolated struct DanmakuDisplayArea: Codable, Equatable, Hashable, Identifiable, Sendable {
    let fraction: Double

    init(fraction: Double) {
        self.fraction = min(max(fraction.isFinite ? fraction : 0.5, 0.1), 1.0)
    }

    static let topQuarter = DanmakuDisplayArea(fraction: 0.25)
    static let topHalf = DanmakuDisplayArea(fraction: 0.5)
    static let topThreeQuarters = DanmakuDisplayArea(fraction: 0.75)
    static let center = DanmakuDisplayArea(fraction: 0.5)
    static let full = DanmakuDisplayArea(fraction: 1.0)

    var id: Int { Int((fraction * 100).rounded()) }
    var title: String { "\(id)%" }
    nonisolated var normalized: DanmakuDisplayArea { self }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let fraction = try? container.decode(Double.self) {
            self.init(fraction: fraction)
            return
        }

        let legacyValue = try container.decode(String.self)
        let fraction: Double
        switch legacyValue {
        case "topQuarter": fraction = 0.25
        case "topHalf", "center": fraction = 0.5
        case "topThreeQuarters": fraction = 0.75
        case "full": fraction = 1.0
        default:
            guard let decodedFraction = Double(legacyValue) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown danmaku display area: \(legacyValue)"
                )
            }
            fraction = decodedFraction
        }
        self.init(fraction: fraction)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(fraction)
    }
}

nonisolated enum DanmakuFontWeightOption: String, Codable, CaseIterable, Identifiable, Sendable {
    case light
    case regular
    case medium
    case semibold
    case bold
    case heavy
    case black

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light:
            return "细体"
        case .regular:
            return "常规"
        case .medium:
            return "中等"
        case .semibold:
            return "中粗"
        case .bold:
            return "粗体"
        case .heavy:
            return "重体"
        case .black:
            return "特粗"
        }
    }
}

nonisolated struct DanmakuItem: Identifiable, Hashable, Sendable {
    let id: String
    let time: TimeInterval
    let mode: Int
    let fontSize: Double
    let color: UInt32
    let text: String
    let senderName: String?
    let inlineEmotes: [String: BiliInlineEmote]

    init(
        id: String,
        time: TimeInterval,
        mode: Int,
        fontSize: Double,
        color: UInt32,
        text: String,
        senderName: String? = nil,
        inlineEmotes: [String: BiliInlineEmote] = [:]
    ) {
        self.id = id
        self.time = time
        self.mode = mode
        self.fontSize = fontSize
        self.color = color
        self.text = text
        self.senderName = senderName
        self.inlineEmotes = inlineEmotes
    }

    nonisolated var isScrolling: Bool {
        mode == 1 || mode == 2 || mode == 3
    }

    nonisolated var isBottomAnchored: Bool {
        mode == 4
    }

    nonisolated var isTopAnchored: Bool {
        mode == 5
    }

    nonisolated var isSupported: Bool {
        isScrolling || isBottomAnchored || isTopAnchored
    }
}

nonisolated final class DanmakuXMLParser: NSObject, XMLParserDelegate {
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

nonisolated struct DanmakuSegmentProtobufParser {
    private let cid: Int
    private let segmentIndex: Int
    private let maxItems: Int

    init(cid: Int, segmentIndex: Int, maxItems: Int = 2_200) {
        self.cid = cid
        self.segmentIndex = segmentIndex
        self.maxItems = maxItems
    }

    func parse(data: Data) throws -> [DanmakuItem] {
        guard !data.isEmpty else { return [] }
        var reader = ProtobufWireReader(data: data)
        var items = [DanmakuItem]()
        var elementIndex = 0
        items.reserveCapacity(min(maxItems, 600))

        while !reader.isAtEnd, items.count < maxItems {
            let key = try reader.readVarint()
            let fieldNumber = Int(key >> 3)
            let wireType = Int(key & 0x7)
            if fieldNumber == 1, wireType == ProtobufWireType.lengthDelimited {
                let payload = try reader.readLengthDelimited()
                if let item = try parseElement(payload, elementIndex: elementIndex) {
                    items.append(item)
                }
                elementIndex += 1
            } else {
                try reader.skipField(wireType: wireType)
            }
        }

        return items
    }

    private func parseElement(_ payload: [UInt8], elementIndex: Int) throws -> DanmakuItem? {
        var reader = ProtobufWireReader(bytes: payload)
        var numericID: UInt64?
        var idString: String?
        var progressMilliseconds: UInt64?
        var mode = 1
        var fontSize = 25.0
        var color: UInt32 = 0xFF_FF_FF
        var content = ""

        while !reader.isAtEnd {
            let key = try reader.readVarint()
            let fieldNumber = Int(key >> 3)
            let wireType = Int(key & 0x7)

            switch (fieldNumber, wireType) {
            case (1, ProtobufWireType.varint):
                numericID = try reader.readVarint()
            case (2, ProtobufWireType.varint):
                progressMilliseconds = try reader.readVarint()
            case (3, ProtobufWireType.varint):
                mode = Int(try reader.readVarint())
            case (4, ProtobufWireType.varint):
                fontSize = Double(try reader.readVarint())
            case (5, ProtobufWireType.varint):
                color = UInt32(truncatingIfNeeded: try reader.readVarint())
            case (7, ProtobufWireType.lengthDelimited):
                content = try reader.readString()
            case (12, ProtobufWireType.lengthDelimited):
                idString = try reader.readString()
            default:
                try reader.skipField(wireType: wireType)
            }
        }

        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              let progressMilliseconds
        else { return nil }

        let itemID: String
        if let idString, !idString.isEmpty {
            itemID = "\(cid)-seg\(segmentIndex)-\(idString)"
        } else if let numericID {
            itemID = "\(cid)-seg\(segmentIndex)-\(numericID)"
        } else {
            itemID = "\(cid)-seg\(segmentIndex)-\(elementIndex)"
        }

        let item = DanmakuItem(
            id: itemID,
            time: TimeInterval(progressMilliseconds) / 1000,
            mode: mode,
            fontSize: fontSize,
            color: color,
            text: text
        )
        return item.isSupported ? item : nil
    }
}

nonisolated private enum ProtobufWireType {
    static let varint = 0
    static let fixed64 = 1
    static let lengthDelimited = 2
    static let fixed32 = 5
}

nonisolated private struct ProtobufWireReader {
    private let bytes: [UInt8]
    private var index = 0

    init(data: Data) {
        self.bytes = Array(data)
    }

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    var isAtEnd: Bool {
        index >= bytes.count
    }

    mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0

        while shift < 64 {
            guard index < bytes.count else { throw BiliAPIError.emptyData }
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                return result
            }
            shift += 7
        }

        throw BiliAPIError.emptyData
    }

    mutating func readLengthDelimited() throws -> [UInt8] {
        let length = Int(try readVarint())
        guard length >= 0, index + length <= bytes.count else {
            throw BiliAPIError.emptyData
        }
        let slice = Array(bytes[index..<index + length])
        index += length
        return slice
    }

    mutating func readString() throws -> String {
        let payload = try readLengthDelimited()
        return String(decoding: payload, as: UTF8.self)
    }

    mutating func skipField(wireType: Int) throws {
        switch wireType {
        case ProtobufWireType.varint:
            _ = try readVarint()
        case ProtobufWireType.fixed64:
            try skipBytes(8)
        case ProtobufWireType.lengthDelimited:
            let length = Int(try readVarint())
            try skipBytes(length)
        case ProtobufWireType.fixed32:
            try skipBytes(4)
        default:
            throw BiliAPIError.emptyData
        }
    }

    private mutating func skipBytes(_ count: Int) throws {
        guard count >= 0, index + count <= bytes.count else {
            throw BiliAPIError.emptyData
        }
        index += count
    }
}
