import CryptoKit
import Foundation

struct WBIKeys: Codable, Sendable {
    let imgKey: String
    let subKey: String
}

enum WBISigner {
    private static let mixinKeyEncTab: [Int] = [
        46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
        27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
        37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
        22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52
    ]

    static func sign(_ params: [String: String], keys: WBIKeys, timestamp: Int = Int(Date().timeIntervalSince1970)) -> [String: String] {
        let mixinKey = Self.mixinKey(imgKey: keys.imgKey, subKey: keys.subKey)
        var all = params
        all["wts"] = String(timestamp)

        let query = all.keys
            .sorted()
            .map { key -> String in
                let value = signValue(all[key] ?? "")
                return "\(key)=\(value)"
            }
            .joined(separator: "&")

        all["w_rid"] = md5(query + mixinKey)
        return all
    }

    private static func mixinKey(imgKey: String, subKey: String) -> String {
        let raw = Array(imgKey + subKey)
        return mixinKeyEncTab
            .prefix(32)
            .compactMap { index in raw.indices.contains(index) ? raw[index] : nil }
            .map(String.init)
            .joined()
    }

    private static func signValue(_ value: String) -> String {
        let sanitized = value.replacingOccurrences(of: "[!'()*]", with: "", options: .regularExpression)
        return sanitized.addingPercentEncoding(withAllowedCharacters: .wbiQueryValueAllowed) ?? sanitized
    }

    private static func md5(_ value: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private extension CharacterSet {
    static let wbiQueryValueAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
}
