import Foundation
import Combine

@MainActor
final class MineViewModel: ObservableObject {
    @Published var state: LoadingState = .idle
    @Published var loginMessage = ""
    @Published var qrLoginState: QRCodeLoginState = .idle
    @Published var historyState: LoadingState = .idle
    @Published var favoriteState: LoadingState = .idle
    @Published var accountHistory: [AccountVideoEntry] = []
    @Published var accountFavorites: [AccountVideoEntry] = []

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
            accountFavorites = try await api.fetchAccountFavorites()
            favoriteState = .loaded
        } catch {
            favoriteState = .failed(error.localizedDescription)
        }
    }

    func completeWebLogin(with cookies: [HTTPCookie]) async {
        do {
            cancelQRCodeLogin()
            try sessionStore.saveLoginCookies(cookies)
            loginMessage = "登录成功"
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
            let info = try await api.generateQRCodeLogin()
            guard !Task.isCancelled else { return }
            qrLoginState = .waiting(info, "请使用 B 站客户端扫码")
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

    private func pollQRCodeLogin(_ info: QRCodeLoginInfo) async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }

            do {
                let result = try await api.pollQRCodeLogin(qrcodeKey: info.qrcodeKey)
                switch result.data.status {
                case .waitingForScan:
                    if case .waiting = qrLoginState {
                        break
                    }
                    qrLoginState = .waiting(info, result.data.message ?? "请使用 B 站客户端扫码")
                case .waitingForConfirm:
                    qrLoginState = .scanned(info, result.data.message ?? "已扫码，请在手机上确认")
                case .expired:
                    qrLoginState = .expired(result.data.message ?? "二维码已过期")
                    return
                case .confirmed:
                    if !result.cookies.isEmpty {
                        try sessionStore.saveLoginCookies(result.cookies)
                    } else {
                        let cookieValues = result.data.cookieValuesFromURL
                        guard !cookieValues.isEmpty else {
                            qrLoginState = .failed("登录成功但没有拿到 Cookie，请改用网页登录。")
                            return
                        }
                        try sessionStore.saveLoginCookies(cookieValues)
                    }
                    guard sessionStore.isLoggedIn else {
                        qrLoginState = .failed("登录成功但没有拿到 Cookie，请改用网页登录。")
                        return
                    }
                    loginMessage = "登录成功"
                    qrLoginState = .succeeded("登录成功")
                    await refreshUser()
                    return
                case .unknown(let code):
                    let message = result.data.message ?? "未知状态"
                    qrLoginState = .failed("二维码登录失败：\(message) (\(code))")
                    return
                }
            } catch {
                if !Task.isCancelled {
                    qrLoginState = .failed(error.localizedDescription)
                }
                return
            }
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
