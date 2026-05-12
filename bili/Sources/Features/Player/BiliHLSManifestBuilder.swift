import Foundation

struct BiliHLSPlaybackManifest: Sendable {
    let masterPlaylistURL: URL
    let bridge: LocalHLSBridge?
    let progressiveLoader: BiliHeaderResourceLoaderDelegate?
    let headers: [String: String]
    let mediaTimeOffset: TimeInterval
}

enum BiliHLSManifestBuilderError: LocalizedError {
    case missingVideoURL
    case missingAudioURL
    case unsupportedCodec
    case manifestGenerationFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingVideoURL:
            return "DASH video URL is missing."
        case .missingAudioURL:
            return "DASH audio URL is missing."
        case .unsupportedCodec:
            return "This DASH codec is not supported by Apple's hardware decoder."
        case .manifestGenerationFailed(let message):
            return "Failed to generate local HLS manifest: \(message)"
        }
    }
}

enum BiliHLSManifestBuilder {
    static func make(source: PlayerStreamSource) async throws -> BiliHLSPlaybackManifest {
        guard let videoURL = source.videoURL else {
            PlayerMetricsLog.logger.error("pillarboxDashRejected reason=missingVideoURL")
            throw BiliHLSManifestBuilderError.missingVideoURL
        }
        guard let audioURL = source.audioURL else {
            return try await makeProgressiveManifest(videoURL: videoURL, source: source)
        }
        try validateHardwareDecoding(for: source)

        let headers = source.httpHeaders
        let bridge: LocalHLSBridge
        do {
            bridge = try await LocalHLSBridge.make(
                videoTrack: HLSBridgeTrack(
                    url: videoURL,
                    fallbackURLs: source.videoStream?.backupPlayURLs ?? [],
                    stream: source.videoStream,
                    mediaType: .video,
                    dynamicRange: source.dynamicRange
                ),
                audioTrack: HLSBridgeTrack(
                    url: audioURL,
                    fallbackURLs: source.audioStream?.backupPlayURLs ?? [],
                    stream: source.audioStream,
                    mediaType: .audio
                ),
                durationHint: source.durationHint,
                headers: headers,
                metricsID: source.metricsID
            )
        } catch {
            PlayerMetricsLog.logger.error(
                "pillarboxManifestFailed error=\(error.localizedDescription, privacy: .public)"
            )
            throw BiliHLSManifestBuilderError.manifestGenerationFailed(error.localizedDescription)
        }

        return BiliHLSPlaybackManifest(
            masterPlaylistURL: bridge.masterPlaylistURL,
            bridge: bridge,
            progressiveLoader: nil,
            headers: headers,
            mediaTimeOffset: bridge.mediaTimeOffset
        )
    }

    static func httpHeaders(referer: String) -> [String: String] {
        [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1",
            "Referer": referer,
            "Origin": "https://www.bilibili.com",
            "Accept": "*/*",
            "Accept-Language": "zh-CN,zh;q=0.9"
        ]
    }

    private static func makeProgressiveManifest(
        videoURL: URL,
        source: PlayerStreamSource
    ) async throws -> BiliHLSPlaybackManifest {
        try validateHardwareDecoding(for: source)
        let headers = source.httpHeaders
        let loader = BiliHeaderResourceLoaderDelegate(originalURL: videoURL, headers: headers)
        return BiliHLSPlaybackManifest(
            masterPlaylistURL: loader.assetURL,
            bridge: nil,
            progressiveLoader: loader,
            headers: headers,
            mediaTimeOffset: 0
        )
    }

    private static func validateHardwareDecoding(for source: PlayerStreamSource) throws {
        if let videoStream = source.videoStream {
            guard videoStream.isHardwareDecodingCompatibleVideo else {
                PlayerMetricsLog.logger.error(
                    "pillarboxDashRejected media=video codec=\(videoStream.codecs ?? "-", privacy: .public) codecid=\(videoStream.codecid ?? -1, privacy: .public)"
                )
                throw BiliHLSManifestBuilderError.unsupportedCodec
            }
        } else if source.audioURL != nil {
            PlayerMetricsLog.logger.error("pillarboxDashRejected media=video codec=missing")
            throw BiliHLSManifestBuilderError.unsupportedCodec
        }

        if let audioStream = source.audioStream {
            guard audioStream.isHardwareDecodingCompatibleAudio else {
                PlayerMetricsLog.logger.error(
                    "pillarboxDashRejected media=audio codec=\(audioStream.codecs ?? "-", privacy: .public) codecid=\(audioStream.codecid ?? -1, privacy: .public)"
                )
                throw BiliHLSManifestBuilderError.unsupportedCodec
            }
        } else if source.audioURL != nil {
            PlayerMetricsLog.logger.error("pillarboxDashRejected media=audio codec=missing")
            throw BiliHLSManifestBuilderError.missingAudioURL
        }
    }
}
