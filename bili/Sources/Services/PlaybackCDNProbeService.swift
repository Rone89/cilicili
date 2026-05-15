import Foundation
import Darwin

struct PlaybackCDNProbeResult: Identifiable, Codable, Equatable, Sendable {
    let preference: PlaybackCDNPreference
    let elapsedMilliseconds: Int?
    let didSucceed: Bool
    let errorDescription: String?
    let addressFamily: PlaybackNetworkAddressFamily?

    private enum CodingKeys: String, CodingKey {
        case preference
        case elapsedMilliseconds
        case didSucceed
        case errorDescription
        case addressFamily
    }

    init(
        preference: PlaybackCDNPreference,
        elapsedMilliseconds: Int?,
        didSucceed: Bool,
        errorDescription: String?,
        addressFamily: PlaybackNetworkAddressFamily? = nil
    ) {
        self.preference = preference
        self.elapsedMilliseconds = elapsedMilliseconds
        self.didSucceed = didSucceed
        self.errorDescription = errorDescription
        self.addressFamily = addressFamily
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.preference = try container.decode(PlaybackCDNPreference.self, forKey: .preference)
        self.elapsedMilliseconds = try container.decodeIfPresent(Int.self, forKey: .elapsedMilliseconds)
        self.didSucceed = try container.decode(Bool.self, forKey: .didSucceed)
        self.errorDescription = try container.decodeIfPresent(String.self, forKey: .errorDescription)
        self.addressFamily = try container.decodeIfPresent(PlaybackNetworkAddressFamily.self, forKey: .addressFamily)
    }

    var id: PlaybackCDNPreference { preference }
}

struct PlaybackCDNProbeSnapshot: Codable, Equatable, Sendable {
    static let defaultFreshnessInterval: TimeInterval = 24 * 60 * 60

    let probedAt: Date
    let recommendedPreference: PlaybackCDNPreference?
    let results: [PlaybackCDNProbeResult]

    var successfulResults: [PlaybackCDNProbeResult] {
        results.filter { $0.didSucceed && $0.elapsedMilliseconds != nil }
    }

    func result(for preference: PlaybackCDNPreference) -> PlaybackCDNProbeResult? {
        results.first { $0.preference == preference }
    }

    func isExpired(now: Date = Date(), freshnessInterval: TimeInterval = Self.defaultFreshnessInterval) -> Bool {
        now.timeIntervalSince(probedAt) >= freshnessInterval
    }
}

enum PlaybackCDNProbeService {
    private static let probePath = "/upgcxcode/00/00/1/1.m4s"
    private static let timeout: TimeInterval = 2.2

    static func probeAll(
        addressFamilyPreference: PlaybackNetworkAddressFamilyPreference = .automatic
    ) async -> [PlaybackCDNProbeResult] {
        let candidates = PlaybackCDNPreference.manualProbeCandidates
        return await withTaskGroup(of: PlaybackCDNProbeResult.self) { group in
            for candidate in candidates {
                group.addTask(priority: .utility) {
                    await probe(
                        candidate,
                        addressFamilyPreference: addressFamilyPreference
                    )
                }
            }

            var results = [PlaybackCDNProbeResult]()
            for await result in group {
                results.append(result)
            }
            return results.sorted { lhs, rhs in
                switch (lhs.elapsedMilliseconds, rhs.elapsedMilliseconds) {
                case let (left?, right?):
                    return left < right
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return lhs.preference.title < rhs.preference.title
                }
            }
        }
    }

    static func recommendedPreference(
        addressFamilyPreference: PlaybackNetworkAddressFamilyPreference = .automatic
    ) async -> (preference: PlaybackCDNPreference?, results: [PlaybackCDNProbeResult]) {
        let results = await probeAll(addressFamilyPreference: addressFamilyPreference)
        let recommendation = results.first {
            $0.didSucceed && $0.elapsedMilliseconds != nil
        }?.preference
        return (recommendation, results)
    }

    static func recommendedSnapshot(
        addressFamilyPreference: PlaybackNetworkAddressFamilyPreference = .automatic
    ) async -> PlaybackCDNProbeSnapshot {
        let recommendation = await recommendedPreference(
            addressFamilyPreference: addressFamilyPreference
        )
        return PlaybackCDNProbeSnapshot(
            probedAt: Date(),
            recommendedPreference: recommendation.preference,
            results: recommendation.results
        )
    }

    private static func probe(
        _ preference: PlaybackCDNPreference,
        addressFamilyPreference: PlaybackNetworkAddressFamilyPreference
    ) async -> PlaybackCDNProbeResult {
        guard let host = preference.host,
              let url = URL(string: "https://\(host)\(probePath)")
        else {
            return PlaybackCDNProbeResult(
                preference: preference,
                elapsedMilliseconds: nil,
                didSucceed: false,
                errorDescription: "missing host"
            )
        }

        if let requiredFamily = addressFamilyPreference.requiredFamily {
            do {
                let resolvedFamilies = try resolvedAddressFamilies(for: host)
                guard resolvedFamilies.contains(requiredFamily) else {
                    return PlaybackCDNProbeResult(
                        preference: preference,
                        elapsedMilliseconds: nil,
                        didSucceed: false,
                        errorDescription: "no \(requiredFamily.title) address",
                        addressFamily: nil
                    )
                }
            } catch {
                return PlaybackCDNProbeResult(
                    preference: preference,
                    elapsedMilliseconds: nil,
                    didSucceed: false,
                    errorDescription: "DNS \(error.localizedDescription)",
                    addressFamily: nil
                )
            }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        let start = Date()
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let didSucceed = (200..<400).contains(statusCode) || statusCode == 403
            return PlaybackCDNProbeResult(
                preference: preference,
                elapsedMilliseconds: elapsed,
                didSucceed: didSucceed,
                errorDescription: didSucceed ? nil : "HTTP \(statusCode)",
                addressFamily: addressFamilyPreference.requiredFamily
            )
        } catch {
            return PlaybackCDNProbeResult(
                preference: preference,
                elapsedMilliseconds: nil,
                didSucceed: false,
                errorDescription: error.localizedDescription,
                addressFamily: addressFamilyPreference.requiredFamily
            )
        }
    }

    private static func resolvedAddressFamilies(for host: String) throws -> Set<PlaybackNetworkAddressFamily> {
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_UNSPEC,
            ai_socktype: 0,
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &result)
        guard status == 0 else {
            throw DNSResolutionError(code: status)
        }
        defer {
            if let result {
                freeaddrinfo(result)
            }
        }

        var families = Set<PlaybackNetworkAddressFamily>()
        var pointer = result
        while let current = pointer {
            switch current.pointee.ai_family {
            case AF_INET:
                families.insert(.ipv4)
            case AF_INET6:
                families.insert(.ipv6)
            default:
                break
            }
            pointer = current.pointee.ai_next
        }
        return families
    }
}

private struct DNSResolutionError: LocalizedError {
    let code: Int32

    var errorDescription: String? {
        String(cString: gai_strerror(code))
    }
}
