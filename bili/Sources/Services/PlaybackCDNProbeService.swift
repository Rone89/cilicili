import Foundation

struct PlaybackCDNProbeResult: Identifiable, Codable, Equatable, Sendable {
    let preference: PlaybackCDNPreference
    let elapsedMilliseconds: Int?
    let didSucceed: Bool
    let errorDescription: String?

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

    static func probeAll() async -> [PlaybackCDNProbeResult] {
        let candidates = PlaybackCDNPreference.manualProbeCandidates
        return await withTaskGroup(of: PlaybackCDNProbeResult.self) { group in
            for candidate in candidates {
                group.addTask {
                    await probe(candidate)
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

    static func recommendedPreference() async -> (preference: PlaybackCDNPreference?, results: [PlaybackCDNProbeResult]) {
        let results = await probeAll()
        let recommendation = results.first {
            $0.didSucceed && $0.elapsedMilliseconds != nil
        }?.preference
        return (recommendation, results)
    }

    static func recommendedSnapshot() async -> PlaybackCDNProbeSnapshot {
        let recommendation = await recommendedPreference()
        return PlaybackCDNProbeSnapshot(
            probedAt: Date(),
            recommendedPreference: recommendation.preference,
            results: recommendation.results
        )
    }

    private static func probe(_ preference: PlaybackCDNPreference) async -> PlaybackCDNProbeResult {
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
                errorDescription: didSucceed ? nil : "HTTP \(statusCode)"
            )
        } catch {
            return PlaybackCDNProbeResult(
                preference: preference,
                elapsedMilliseconds: nil,
                didSucceed: false,
                errorDescription: error.localizedDescription
            )
        }
    }
}
