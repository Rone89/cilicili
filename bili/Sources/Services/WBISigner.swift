import CryptoKit
import Foundation

nonisolated struct WBIKeys: Codable, Sendable {
    let imgKey: String
    let subKey: String
}

nonisolated enum WBISigner {
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

nonisolated enum BiliAppSigner {
    enum Profile: Sendable {
        case androidPhone
        case androidHD

        var appKey: String {
            switch self {
            case .androidPhone:
                return "1d8b6e7d45233436"
            case .androidHD:
                return "dfca71928277209b"
            }
        }

        var appSecret: String {
            switch self {
            case .androidPhone:
                return "560c52ccd288fed045859ed18bffd973"
            case .androidHD:
                return "b5475a8825547a4fc26c7d518eaaa02e"
            }
        }

        var build: String {
            switch self {
            case .androidPhone:
                return "7610300"
            case .androidHD:
                return "2001100"
            }
        }

        var mobiApp: String {
            switch self {
            case .androidPhone:
                return "android"
            case .androidHD:
                return "android_hd"
            }
        }

        var device: String {
            switch self {
            case .androidPhone:
                return "phone"
            case .androidHD:
                return "pad"
            }
        }

        var displayName: String {
            switch self {
            case .androidPhone:
                return "android-phone"
            case .androidHD:
                return "android-hd"
            }
        }

        var userAgent: String {
            switch self {
            case .androidPhone:
                return "Mozilla/5.0 BiliDroid/7.61.0 (bbcallen@gmail.com) os/android model/phone mobi_app/android build/7610300 channel/master innerVer/7610300 osVer/15 network/2"
            case .androidHD:
                return "Mozilla/5.0 BiliDroid/2.0.1 (bbcallen@gmail.com) os/android model/android_hd mobi_app/android_hd build/2001100 channel/master innerVer/2001100 osVer/15 network/2"
            }
        }
    }

    static func sign(
        _ params: [String: String],
        profile: Profile = .androidHD,
        timestamp: Int = Int(Date().timeIntervalSince1970)
    ) -> [String: String] {
        var all = params
        all["appkey"] = profile.appKey
        all["ts"] = String(timestamp)

        let query = all.keys
            .sorted()
            .map { key -> String in
                "\(appSignValue(key))=\(appSignValue(all[key] ?? ""))"
            }
            .joined(separator: "&")

        all["sign"] = md5(query + profile.appSecret)
        return all
    }

    private static func appSignValue(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .biliAppQueryValueAllowed) ?? value
    }

    private static func md5(_ value: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

nonisolated private extension CharacterSet {
    static let wbiQueryValueAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
    static let biliAppQueryValueAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
}
