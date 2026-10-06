import Foundation

nonisolated enum CellularBiliTrafficCompatibility {
    enum HostClassification: String, Equatable, Sendable {
        case bili
        case external
        case unknown

        var diagnosticTitle: String {
            switch self {
            case .bili:
                "B站域名"
            case .external:
                "外部域名"
            case .unknown:
                "未知"
            }
        }
    }

    struct RuntimeState: Equatable, Sendable {
        let isCellularNetwork: Bool

        static let inactive = RuntimeState(isCellularNetwork: false)

        var isActive: Bool { isCellularNetwork }

        var diagnosticSummary: String {
            isActive ? "cellularBiliDomainsFirst" : "originalOrder"
        }

        var userFacingStatus: String {
            isActive ? "蜂窝网络：优先 B 站域名" : "Wi-Fi/其他网络：保持原线路排序"
        }
    }

    static var currentState: RuntimeState {
        RuntimeState(isCellularNetwork: NetworkPathSnapshot.shared.usesCellular)
    }

    static func classify(host: String?) -> HostClassification {
        guard let host = normalizedHost(host) else { return .unknown }
        if approvedBiliDomains.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            return .bili
        }
        return .external
    }

    static func prioritizedURLs(_ urls: [URL], isCellularNetwork: Bool) -> [URL] {
        guard isCellularNetwork else { return urls }

        var biliURLs = [URL]()
        var fallbackURLs = [URL]()
        for url in urls {
            if classify(host: url.host) == .bili {
                biliURLs.append(url)
            } else {
                fallbackURLs.append(url)
            }
        }
        return biliURLs.isEmpty ? urls : biliURLs + fallbackURLs
    }

    static func prioritizedURLsForCurrentEnvironment(_ urls: [URL]) -> [URL] {
        prioritizedURLs(urls, isCellularNetwork: currentState.isCellularNetwork)
    }

    static func sourceHostSummary(videoHost: String?, audioHost: String?) -> String {
        let video = classify(host: videoHost).diagnosticTitle
        let audio = classify(host: audioHost).diagnosticTitle
        return "video=\(video) audio=\(audio)"
    }

    static func hasExternalMediaHost(videoHost: String?, audioHost: String?) -> Bool {
        [videoHost, audioHost].contains { classify(host: $0) == .external }
    }

    private static let approvedBiliDomains = [
        "bilibili.com",
        "bilivideo.com",
        "bilivideo.cn",
        "bilivideo.net",
        "acgvideo.com",
        "acgvideo.cn"
    ]

    private static func normalizedHost(_ host: String?) -> String? {
        guard let host = host?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased(),
              !host.isEmpty
        else { return nil }
        return host
    }
}
