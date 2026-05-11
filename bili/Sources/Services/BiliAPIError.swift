import Foundation

enum BiliAPIError: LocalizedError {
    case invalidURL
    case emptyData
    case api(code: Int, message: String?)
    case missingPayload
    case missingSESSDATA
    case missingCSRF
    case emptyPlayURL

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .emptyData:
            return "Empty response"
        case .api(let code, let message):
            return "API \(code): \(message ?? "Unknown error")"
        case .missingPayload:
            return "Missing response data"
        case .missingSESSDATA:
            return "Login cookie not found"
        case .missingCSRF:
            return "登录 Cookie 中缺少 bili_jct，无法提交互动操作"
        case .emptyPlayURL:
            return "播放接口没有返回清晰度或播放地址"
        }
    }
}
