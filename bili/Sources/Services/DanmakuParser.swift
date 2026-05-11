import Foundation

enum DanmakuParser {
    private static let maxParsedItems = 800

    static func parse(xml: String) -> [DanmakuItem] {
        let pattern = #"<d p="([^"]+)">([^<]*)</d>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let nsRange = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        var items = [DanmakuItem]()
        items.reserveCapacity(min(maxParsedItems, 240))

        for match in regex.matches(in: xml, range: nsRange) {
            guard
                let pRange = Range(match.range(at: 1), in: xml),
                let textRange = Range(match.range(at: 2), in: xml)
            else {
                continue
            }
            let attrs = xml[pRange].split(separator: ",")
            guard attrs.count >= 4 else {
                continue
            }
            let text = String(xml[textRange])
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&quot;", with: "\"")

            items.append(DanmakuItem(
                time: TimeInterval(Double(attrs[0]) ?? 0),
                mode: Int(attrs[1]) ?? 1,
                fontSize: Int(attrs[2]) ?? 25,
                color: Int(attrs[3]) ?? 0xffffff,
                text: text
            ))
            if items.count >= maxParsedItems {
                break
            }
        }
        return items
    }
}
