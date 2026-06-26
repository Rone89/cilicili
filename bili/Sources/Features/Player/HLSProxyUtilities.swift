import Foundation

extension Array where Element == URL {
    nonisolated func removingDuplicates() -> [URL] {
        var seen = Set<String>()
        var result = [URL]()
        for url in self {
            let key = url.absoluteString
            guard seen.insert(key).inserted else { continue }
            result.append(url)
        }
        return result
    }
}

extension Array {
    nonisolated subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct HLSProxyRequest: Sendable {
    let method: String
    let path: String
    let range: HTTPByteRange?
    let shouldCloseConnection: Bool

    nonisolated init?(data: Data) {
        guard let rawRequest = String(data: data, encoding: .utf8) else { return nil }
        let lines = rawRequest.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count >= 2 else { return nil }

        method = requestParts[0]
        let rawPath = requestParts[1]
        let httpVersion = requestParts.indices.contains(2) ? requestParts[2].lowercased() : "http/1.0"
        path = URLComponents(string: "http://127.0.0.1\(rawPath)")?.path ?? rawPath

        var parsedRange: HTTPByteRange?
        var connectionValue: String?
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            switch key {
            case "range":
                parsedRange = HTTPByteRange(httpHeaderValue: value)
            case "connection":
                connectionValue = value.lowercased()
            default:
                break
            }
        }
        range = parsedRange
        if connectionValue?.contains("close") == true {
            shouldCloseConnection = true
        } else if httpVersion == "http/1.1" {
            shouldCloseConnection = false
        } else {
            shouldCloseConnection = connectionValue?.contains("keep-alive") != true
        }
    }
}
