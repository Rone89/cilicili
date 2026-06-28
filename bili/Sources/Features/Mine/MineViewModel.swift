import Foundation
import Combine

@MainActor
final class MineViewModel: ObservableObject {
    @Published var state: LoadingState = .idle
    @Published var loginMessage = ""
    @Published var qrLoginState: QRCodeLoginState = .idle
    @Published var historyState: LoadingState = .idle
    @Published var favoriteState: LoadingState = .idle
    @Published var accountHistory: [AccountVideoEntry] = [] {
        didSet { accountLibraryRevision &+= 1 }
    }
    @Published var accountFavorites: [AccountVideoEntry] = [] {
        didSet { accountLibraryRevision &+= 1 }
    }
    @Published var favoriteFolders: [FavoriteFolder] = [] {
        didSet { accountLibraryRevision &+= 1 }
    }
    @Published var favoriteFolderEntries: [Int: [AccountVideoEntry]] = [:] {
        didSet { favoriteFolderRevision &+= 1 }
    }
    @Published var favoriteFolderEntryStates: [Int: LoadingState] = [:] {
        didSet { favoriteFolderRevision &+= 1 }
    }
    @Published private(set) var accountLibraryRevision = 0
    @Published private(set) var favoriteFolderRevision = 0

    private let api: BiliAPIClient
    private let sessionStore: SessionStore
    private var qrLoginTask: Task<Void, Never>?

    init(api: BiliAPIClient, sessionStore: SessionStore) {
        self.api = api
        self.sessionStore = sessionStore
    }

    func refreshUser() async {
        guard sessionStore.isLoggedIn else { return }
        do {
            let user = try await api.fetchNavUser()
            if user.isLogin == true {
                sessionStore.updateUser(user)
                await refreshAccountLibrary()
            } else {
                try? sessionStore.logout()
                loginMessage = "登录已失效，请重新登录"
            }
        } catch {
            sessionStore.updateUser(nil)
        }
    }

    func refreshAccountLibrary() async {
        guard sessionStore.isLoggedIn else {
            accountHistory = []
            accountFavorites = []
            favoriteFolders = []
            favoriteFolderEntries = [:]
            favoriteFolderEntryStates = [:]
            historyState = .idle
            favoriteState = .idle
            return
        }

        async let history: Void = refreshHistory()
        async let favorites: Void = refreshFavorites()
        _ = await (history, favorites)
    }

    func refreshHistory() async {
        guard sessionStore.isLoggedIn else { return }
        historyState = .loading
        do {
            accountHistory = try await api.fetchAccountHistory()
            historyState = .loaded
        } catch {
            historyState = .failed(error.localizedDescription)
        }
    }

    func refreshFavorites() async {
        guard sessionStore.isLoggedIn else { return }
        favoriteState = .loading
        do {
            favoriteFolders = try await api.fetchFavoriteFolders()
            accountFavorites = try await api.fetchAccountFavorites()
            favoriteState = .loaded
        } catch {
            favoriteState = .failed(error.localizedDescription)
        }
    }

    func refreshFavoriteFolder(_ folder: FavoriteFolder) async {
        guard sessionStore.isLoggedIn else { return }
        favoriteFolderEntryStates[folder.id] = .loading
        do {
            let entries = try await api.fetchFavoriteFolderVideos(folderID: folder.id)
            favoriteFolderEntries[folder.id] = entries
            favoriteFolderEntryStates[folder.id] = .loaded
        } catch {
            favoriteFolderEntryStates[folder.id] = .failed(error.localizedDescription)
        }
    }

    func completeWebLogin(with cookies: [HTTPCookie]) async {
        do {
            cancelQRCodeLogin()
            try sessionStore.saveLoginCookies(cookies, credentialKind: .web)
            loginMessage = "网页登录成功，首页推荐建议优先选择网页端。"
            await refreshUser()
        } catch {
            loginMessage = error.localizedDescription
        }
    }

    func logout() {
        cancelQRCodeLogin()
        try? sessionStore.logout()
        BiliWebCookieStore.clearLoginCookies()
        accountHistory = []
        accountFavorites = []
        favoriteFolders = []
        favoriteFolderEntries = [:]
        favoriteFolderEntryStates = [:]
        historyState = .idle
        favoriteState = .idle
        loginMessage = ""
        qrLoginState = .idle
    }

    func startQRCodeLogin() async {
        cancelQRCodeLogin()
        qrLoginState = .loading
        loginMessage = ""

        do {
            let info = try await api.generateAppQRCodeLogin()
            guard !Task.isCancelled else { return }
            let autoConfirmMessage: String
            do {
                try await api.confirmAppQRCodeLoginWithCurrentSession(authCode: info.qrcodeKey)
                autoConfirmMessage = ""
            } catch {
                autoConfirmMessage = error.localizedDescription
            }
            guard !Task.isCancelled else { return }
            if autoConfirmMessage.isEmpty {
                qrLoginState = .scanned(info, "已用当前账号确认，正在获取移动端凭证")
            } else {
                qrLoginState = .waiting(info, "自动确认未完成：\(autoConfirmMessage)。可用 B 站扫码或打开确认")
            }
            qrLoginTask = Task { [weak self] in
                await self?.pollQRCodeLogin(info)
            }
        } catch {
            qrLoginState = .failed(error.localizedDescription)
        }
    }

    func cancelQRCodeLogin() {
        qrLoginTask?.cancel()
        qrLoginTask = nil
    }

    func sendAppSMSCode(phone: String, countryCode: String) async throws -> String {
        cancelQRCodeLogin()
        let info = try await api.sendAppSMSCode(
            phone: Self.normalizedPhone(phone),
            countryCode: Self.normalizedCountryCode(countryCode)
        )
        guard let captchaKey = info.captchaKey, !captchaKey.isEmpty else {
            throw BiliAPIError.missingPayload
        }
        return captchaKey
    }

    func completeAppSMSLogin(
        phone: String,
        countryCode: String,
        code: String,
        captchaKey: String
    ) async throws {
        cancelQRCodeLogin()
        let loginData = try await api.loginWithAppSMS(
            phone: Self.normalizedPhone(phone),
            countryCode: Self.normalizedCountryCode(countryCode),
            code: code.trimmingCharacters(in: .whitespacesAndNewlines),
            captchaKey: captchaKey
        )
        let cookieValues = loginData.loginCookieValues
        guard !cookieValues.isEmpty else {
            throw BiliAPIError.missingPayload
        }
        try sessionStore.saveLoginCookies(cookieValues, credentialKind: .appSMS)
        guard sessionStore.isLoggedIn else {
            throw BiliAPIError.missingSESSDATA
        }
        if sessionStore.appAccessKey() == nil {
            loginMessage = "登录成功，但没有拿到 access_key"
        } else {
            loginMessage = "短信登录成功，App 端推荐会更接近官方客户端。"
        }
        await refreshUser()
    }

    private func pollQRCodeLogin(_ info: QRCodeLoginInfo) async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }

            do {
                let result = try await api.pollAppQRCodeLogin(authCode: info.qrcodeKey)
                switch result.status {
                case .waitingForScan:
                    if case .waiting = qrLoginState {
                        break
                    }
                    qrLoginState = .waiting(info, result.message ?? "请使用 B 站客户端扫码")
                case .waitingForConfirm:
                    qrLoginState = .scanned(info, result.message ?? "已扫码，请在手机上确认")
                case .expired:
                    qrLoginState = .expired(result.message ?? "二维码已过期")
                    return
                case .confirmed:
                    guard let loginData = result.loginData else {
                        qrLoginState = .failed("登录成功但没有拿到移动端凭证，请改用网页登录。")
                        return
                    }
                    let cookieValues = loginData.loginCookieValues
                    guard !cookieValues.isEmpty else {
                        qrLoginState = .failed("登录成功但没有拿到 Cookie，请改用网页登录。")
                        return
                    }
                    try sessionStore.saveLoginCookies(cookieValues, credentialKind: .appQRCodeTV)
                    guard sessionStore.isLoggedIn else {
                        qrLoginState = .failed("登录成功但没有拿到 Cookie，请改用网页登录。")
                        return
                    }
                    if sessionStore.appAccessKey() == nil {
                        loginMessage = "登录成功，但没有拿到 access_key"
                        qrLoginState = .succeeded("登录成功，但移动端凭证缺失")
                    } else {
                        loginMessage = "扫码登录成功；如 App 端推荐不准，可改用短信登录或网页端推荐。"
                        qrLoginState = .succeeded("扫码登录成功")
                    }
                    await refreshUser()
                    return
                case .unknown(let code):
                    let message = result.message ?? "未知状态"
                    qrLoginState = .waiting(info, "\(message) (\(code))")
                }
            } catch {
                if !Task.isCancelled, !Self.isTransientQRCodePollingError(error) {
                    qrLoginState = .waiting(info, error.localizedDescription)
                }
            }
        }
    }

    private nonisolated static func normalizedPhone(_ value: String) -> String {
        value
            .filter { $0.isNumber }
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func normalizedCountryCode(_ value: String) -> String {
        let digits = value.filter { $0.isNumber }
        return digits.isEmpty ? "86" : digits
    }

    private nonisolated static func isTransientQRCodePollingError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        let code = URLError.Code(rawValue: nsError.code)
        switch code {
        case .networkConnectionLost, .notConnectedToInternet, .timedOut, .cancelled:
            return true
        default:
            return false
        }
    }
}

enum QRCodeLoginState: Equatable {
    case idle
    case loading
    case waiting(QRCodeLoginInfo, String)
    case scanned(QRCodeLoginInfo, String)
    case expired(String)
    case succeeded(String)
    case failed(String)

    var codeInfo: QRCodeLoginInfo? {
        switch self {
        case .waiting(let info, _), .scanned(let info, _):
            return info
        default:
            return nil
        }
    }

    var message: String {
        switch self {
        case .idle:
            return ""
        case .loading:
            return "正在生成二维码"
        case .waiting(_, let message), .scanned(_, let message), .expired(let message), .succeeded(let message), .failed(let message):
            return message
        }
    }
}
