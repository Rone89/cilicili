import Foundation
import Combine

nonisolated enum LoginCredentialKind: String, Codable, Sendable {
    case unknown
    case web
    case appQRCodeTV
    case appSMS
}

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessdata: String?
    @Published private(set) var accessKey: String?
    @Published private(set) var loginCredentialKind: LoginCredentialKind
    @Published private(set) var user: NavUserInfo?

    private let keychain: KeychainStore
    private let sessdataKey = "SESSDATA"
    private let accessKeyKey = "ACCESS_KEY"
    private let loginCookieHeaderKey = "LOGIN_COOKIE_HEADER"
    private let loginCredentialKindKey = "LOGIN_CREDENTIAL_KIND"
    private let buvidKey = "buvid3"
    private var loginCookieHeader: String?

    init(keychain: KeychainStore? = nil) {
        let keychain = keychain ?? KeychainStore()
        self.keychain = keychain
        self.sessdata = try? keychain.read(sessdataKey)
        self.accessKey = try? keychain.read(accessKeyKey)
        self.loginCookieHeader = try? keychain.read(loginCookieHeaderKey)
        if let rawKind = try? keychain.read(loginCredentialKindKey),
           let kind = LoginCredentialKind(rawValue: rawKind) {
            self.loginCredentialKind = kind
        } else {
            self.loginCredentialKind = .unknown
        }
    }

    var isLoggedIn: Bool {
        sessdata?.isEmpty == false
    }

    func cookieHeader() -> String {
        var values = [String]()
        if let loginCookieHeader, !loginCookieHeader.isEmpty {
            if !loginCookieHeader.contains("buvid3=") {
                values.append("buvid3=\(buvid3())")
            }
            values.append(loginCookieHeader)
        } else {
            values.append("buvid3=\(buvid3())")
            if let sessdata, !sessdata.isEmpty {
                values.append("SESSDATA=\(sessdata)")
            }
        }
        return values.joined(separator: "; ")
    }

    func anonymousCookieHeader() -> String {
        "buvid3=\(buvid3())"
    }

    func appAccessKey() -> String? {
        guard let accessKey = accessKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accessKey.isEmpty
        else { return nil }
        return accessKey
    }

    func recommendCacheIdentityKey(guestModeEnabled: Bool) -> String {
        if guestModeEnabled {
            return "guest-\(buvid3())"
        }
        let credentialSuffix = "login-\(loginCredentialKind.rawValue)"
        if let mid = Self.cookieValue(named: "DedeUserID", in: cookieHeader()) {
            return "mid-\(mid)|\(credentialSuffix)"
        }
        if isLoggedIn {
            return "auth-cookie|\(credentialSuffix)"
        }
        return "anon-\(buvid3())"
    }

    func saveBuvid3(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UserDefaults.standard.set(trimmed, forKey: buvidKey)
    }

    func csrfToken() -> String? {
        cookieHeader()
            .split(separator: ";")
            .compactMap { item -> String? in
                let pair = item.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard pair.count == 2, pair[0] == "bili_jct", !pair[1].isEmpty else { return nil }
                return pair[1]
            }
            .first
    }

    func saveSESSDATA(_ value: String) throws {
        try keychain.save(value, for: sessdataKey)
        sessdata = value
    }

    func saveLoginCookies(_ cookies: [HTTPCookie], credentialKind: LoginCredentialKind? = nil) throws {
        let values = cookies.reduce(into: [String: String]()) { result, cookie in
            result[cookie.name] = cookie.value
        }
        try saveLoginCookies(values, credentialKind: credentialKind)
    }

    func saveLoginCookies(_ cookies: [String: String], credentialKind: LoginCredentialKind? = nil) throws {
        let allowedNames = [
            "buvid3",
            "buvid4",
            "b_nut",
            "buvid_fp",
            "buvid_fp_plain",
            "_uuid",
            "b_lsid",
            "bili_ticket",
            "bili_ticket_expires",
            "DedeUserID",
            "DedeUserID__ckMd5",
            "SESSDATA",
            "bili_jct",
            "sid",
            "CURRENT_FNVAL",
            "CURRENT_QUALITY"
        ]
        let header = allowedNames
            .compactMap { name -> String? in
                guard let value = cookies[name], !value.isEmpty else { return nil }
                return "\(name)=\(value)"
            }
            .joined(separator: "; ")

        if let sessdata = cookies["SESSDATA"], !sessdata.isEmpty {
            try keychain.save(sessdata, for: sessdataKey)
            self.sessdata = sessdata
        }
        if let accessKey = cookies["access_key"], !accessKey.isEmpty {
            try keychain.save(accessKey, for: accessKeyKey)
            self.accessKey = accessKey
        }
        if !header.isEmpty {
            try keychain.save(header, for: loginCookieHeaderKey)
            loginCookieHeader = header
        }
        if let credentialKind {
            try keychain.save(credentialKind.rawValue, for: loginCredentialKindKey)
            self.loginCredentialKind = credentialKind
        }
    }

    func updateUser(_ user: NavUserInfo?) {
        self.user = user
    }

    func logout() throws {
        try keychain.delete(sessdataKey)
        try keychain.delete(accessKeyKey)
        try keychain.delete(loginCookieHeaderKey)
        try keychain.delete(loginCredentialKindKey)
        sessdata = nil
        accessKey = nil
        loginCookieHeader = nil
        loginCredentialKind = .unknown
        user = nil
    }

    func buvid3() -> String {
        if let existing = UserDefaults.standard.string(forKey: buvidKey), !existing.isEmpty {
            return existing
        }
        let newValue = UUID().uuidString.lowercased() + "infoc"
        UserDefaults.standard.set(newValue, forKey: buvidKey)
        return newValue
    }

    private nonisolated static func cookieValue(named name: String, in header: String) -> String? {
        header
            .split(separator: ";")
            .compactMap { item -> String? in
                let pair = item.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard pair.count == 2, pair[0] == name, !pair[1].isEmpty else { return nil }
                return pair[1]
            }
            .first
    }
}
