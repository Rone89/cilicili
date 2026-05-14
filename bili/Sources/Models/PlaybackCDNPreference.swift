import Foundation

enum PlaybackCDNPreference: String, CaseIterable, Identifiable, Codable, Sendable {
    case automatic
    case baseURL
    case backupURL
    case ali
    case alib
    case alio1
    case cos
    case cosb
    case coso1
    case hw
    case hwb
    case hwo1
    case hw08c
    case hw08h
    case hw08ct
    case tfHW
    case tfTX
    case akamai
    case aliov
    case cosov
    case hwov
    case hkBCache

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            return "自动选择"
        case .baseURL:
            return "基础 URL"
        case .backupURL:
            return "备用 URL"
        case .ali:
            return "阿里云 ali"
        case .alib:
            return "阿里云 alib"
        case .alio1:
            return "阿里云 alio1"
        case .cos:
            return "腾讯云 cos"
        case .cosb:
            return "腾讯云 cosb"
        case .coso1:
            return "腾讯云 coso1"
        case .hw:
            return "华为云 hw"
        case .hwb:
            return "华为云 hwb"
        case .hwo1:
            return "华为云 hwo1"
        case .hw08c:
            return "华为云 08c"
        case .hw08h:
            return "华为云 08h"
        case .hw08ct:
            return "华为云 08ct"
        case .tfHW:
            return "华为云 tf_hw"
        case .tfTX:
            return "腾讯云 tf_tx"
        case .akamai:
            return "Akamai 海外"
        case .aliov:
            return "阿里云海外 aliov"
        case .cosov:
            return "腾讯云海外 cosov"
        case .hwov:
            return "华为云海外 hwov"
        case .hkBCache:
            return "Bilibili 香港"
        }
    }

    var detail: String {
        switch self {
        case .automatic:
            return "保留接口返回顺序，失败时使用备用地址"
        case .baseURL:
            return "优先使用接口返回的原始地址"
        case .backupURL:
            return "优先使用接口返回的备用地址"
        case .ali, .alib, .alio1:
            return "阿里云 CDN"
        case .cos, .cosb, .coso1, .tfTX:
            return "腾讯云 CDN"
        case .hw, .hwb, .hwo1, .hw08c, .hw08h, .hw08ct, .tfHW:
            return "华为云 CDN"
        case .akamai, .aliov, .cosov, .hwov, .hkBCache:
            return "海外或跨境 CDN"
        }
    }

    var host: String? {
        switch self {
        case .automatic, .baseURL, .backupURL:
            return nil
        case .ali:
            return "upos-sz-mirrorali.bilivideo.com"
        case .alib:
            return "upos-sz-mirroralib.bilivideo.com"
        case .alio1:
            return "upos-sz-mirroralio1.bilivideo.com"
        case .cos:
            return "upos-sz-mirrorcos.bilivideo.com"
        case .cosb:
            return "upos-sz-mirrorcosb.bilivideo.com"
        case .coso1:
            return "upos-sz-mirrorcoso1.bilivideo.com"
        case .hw:
            return "upos-sz-mirrorhw.bilivideo.com"
        case .hwb:
            return "upos-sz-mirrorhwb.bilivideo.com"
        case .hwo1:
            return "upos-sz-mirrorhwo1.bilivideo.com"
        case .hw08c:
            return "upos-sz-mirror08c.bilivideo.com"
        case .hw08h:
            return "upos-sz-mirror08h.bilivideo.com"
        case .hw08ct:
            return "upos-sz-mirror08ct.bilivideo.com"
        case .tfHW:
            return "upos-tf-all-hw.bilivideo.com"
        case .tfTX:
            return "upos-tf-all-tx.bilivideo.com"
        case .akamai:
            return "upos-hz-mirrorakam.akamaized.net"
        case .aliov:
            return "upos-sz-mirroraliov.bilivideo.com"
        case .cosov:
            return "upos-sz-mirrorcosov.bilivideo.com"
        case .hwov:
            return "upos-sz-mirrorhwov.bilivideo.com"
        case .hkBCache:
            return "cn-hk-eq-bcache-01.bilivideo.com"
        }
    }

    var isManualHost: Bool {
        host != nil
    }

    func preferredURLs(primary: URL?, backups: [URL]) -> (primary: URL?, backups: [URL]) {
        let candidates = ([primary].compactMap { $0 } + backups).removingDuplicateURLs()
        guard !candidates.isEmpty else { return (primary, backups) }

        switch self {
        case .automatic, .baseURL:
            return (candidates.first, Array(candidates.dropFirst()))
        case .backupURL:
            let backupFirst = backups.removingDuplicateURLs() + [primary].compactMap { $0 }
            let ordered = backupFirst.removingDuplicateURLs()
            return (ordered.first, Array(ordered.dropFirst()))
        default:
            guard let host,
                  let rewritten = candidates.first?.rewritingHost(host)
            else {
                return (candidates.first, Array(candidates.dropFirst()))
            }
            let ordered = ([rewritten] + candidates).removingDuplicateURLs()
            return (ordered.first, Array(ordered.dropFirst()))
        }
    }
}

private extension URL {
    func rewritingHost(_ host: String) -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.host = host
        return components.url
    }
}

private extension Array where Element == URL {
    func removingDuplicateURLs() -> [URL] {
        var seen = Set<String>()
        return filter { url in
            seen.insert(url.absoluteString).inserted
        }
    }
}
