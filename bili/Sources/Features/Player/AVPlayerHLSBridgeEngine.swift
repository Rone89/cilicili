import AVFoundation
import AVKit
import Network
import UIKit

@MainActor
final class AVPlayerHLSBridgeEngine: PlayerRenderingEngine {
    private let player = AVPlayer()
    private var backgroundObserver: Any?
    private var foregroundObserver: Any?
    private weak var surfaceView: UIView?
    private weak var playerLayer: AVPlayerLayer?
    private var playerItem: AVPlayerItem?
    private var source: PlayerStreamSource?
    private var hlsBridge: LocalHLSBridge?
    private var retainedAssets: [AVAsset] = []
    private var currentRate: Float = 1

    var hasMedia: Bool {
        player.currentItem != nil
    }

    var needsMediaRecovery: Bool {
        guard let item = player.currentItem else { return false }
        return item.status == .failed
    }

    init() {
        configureAudioSession()
        observeAppLifecycle()
    }

    deinit {
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
    }

    func attachSurface(_ surface: UIView) {
        surfaceView = surface
        let layer = ensurePlayerLayer(in: surface)
        layer.player = player
        refreshSurfaceLayout()
    }

    func detachSurface(_ surface: UIView) {
        guard surfaceView === surface else { return }
        playerLayer?.player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        surfaceView = nil
    }

    func refreshSurfaceLayout() {
        playerLayer?.frame = surfaceView?.bounds ?? .zero
    }

    func recoverSurface() {
        configureAudioSession()
        guard let surfaceView else { return }
        let layer = ensurePlayerLayer(in: surfaceView)
        layer.player = nil
        layer.player = player
        layer.isHidden = false
        layer.opacity = 1
        refreshSurfaceLayout()
        layer.setNeedsLayout()
        layer.setNeedsDisplay()
    }

    func prepare(source: PlayerStreamSource) async throws {
        configureAudioSession()
        self.source = source
        let prepared = try await Self.makePlayerItem(source: source)
        guard !Task.isCancelled else { return }
        playerItem = prepared.item
        hlsBridge = prepared.bridge
        retainedAssets = prepared.assets
        let item = prepared.item
        player.replaceCurrentItem(with: item)
        player.automaticallyWaitsToMinimizeStalling = false
        if let surfaceView {
            ensurePlayerLayer(in: surfaceView).player = player
            refreshSurfaceLayout()
        }
    }

    func play() {
        guard player.currentItem != nil else { return }
        configureAudioSession()
        player.play()
        player.rate = currentRate
    }

    func pause() {
        player.pause()
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        playerItem = nil
        source = nil
        hlsBridge = nil
        retainedAssets = []
        playerLayer?.player = nil
    }

    func setPlaybackRate(_ rate: Double) {
        currentRate = Float(rate)
        if player.rate > 0 {
            player.rate = currentRate
        }
    }

    func seek(toTime time: TimeInterval) -> TimeInterval? {
        guard player.currentItem != nil else { return nil }
        let target = max(time, 0)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        return target
    }

    func seek(toProgress progress: Double, duration: TimeInterval?) -> TimeInterval? {
        guard player.currentItem != nil else { return nil }
        let resolvedDuration = resolvedDuration(durationHint: duration)
        guard resolvedDuration > 0 else { return nil }
        let target = min(max(progress, 0), 1) * resolvedDuration
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        return target
    }

    func seek(by interval: TimeInterval, from currentTime: TimeInterval, duration: TimeInterval?) -> TimeInterval? {
        guard player.currentItem != nil else { return nil }
        let resolvedDuration = resolvedDuration(durationHint: duration)
        let target = resolvedDuration > 0
            ? min(max(currentTime + interval, 0), resolvedDuration)
            : max(currentTime + interval, 0)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        return target
    }

    func seekAfterUserScrub(toProgress progress: Double, duration: TimeInterval?) async -> TimeInterval? {
        guard player.currentItem != nil else { return nil }
        let resolvedDuration = resolvedDuration(durationHint: duration)
        guard resolvedDuration > 0 else { return nil }
        let target = min(max(progress, 0), 1) * resolvedDuration
        let targetTime = CMTime(seconds: target, preferredTimescale: 600)
        let finished = await withCheckedContinuation { continuation in
            player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                continuation.resume(returning: finished)
            }
        }
        return finished ? target : nil
    }

    func snapshot(durationHint: TimeInterval?) -> PlayerPlaybackSnapshot {
        let currentSeconds = player.currentTime().seconds
        let durationSeconds = resolvedDuration(durationHint: durationHint)
        let status = player.currentItem?.status
        return PlayerPlaybackSnapshot(
            currentTime: currentSeconds.isFinite && currentSeconds >= 0 ? currentSeconds : nil,
            duration: durationSeconds > 0 ? durationSeconds : durationHint,
            isPlaying: player.rate > 0,
            isSeekable: status == .readyToPlay || (durationHint ?? 0) > 0
        )
    }

    func pictureInPictureContentSource() -> AVPictureInPictureController.ContentSource? {
        guard let playerLayer else { return nil }
        return AVPictureInPictureController.ContentSource(playerLayer: playerLayer)
    }

    private func ensurePlayerLayer(in surface: UIView) -> AVPlayerLayer {
        if let playerLayer {
            if playerLayer.superlayer !== surface.layer {
                playerLayer.removeFromSuperlayer()
                surface.layer.insertSublayer(playerLayer, at: 0)
            }
            if playerLayer.player == nil {
                playerLayer.player = player
            }
            return playerLayer
        }

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = UIColor.black.cgColor
        surface.layer.insertSublayer(layer, at: 0)
        playerLayer = layer
        return layer
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            // Playback can still proceed if the simulator or system declines the session update.
        }
    }

    private func observeAppLifecycle() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.configureAudioSession()
            }
        }

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recoverSurface()
            }
        }
    }

    private func resolvedDuration(durationHint: TimeInterval?) -> TimeInterval {
        let itemDuration = player.currentItem?.duration.seconds ?? 0
        if itemDuration.isFinite, itemDuration > 0 {
            return itemDuration
        }
        return durationHint ?? source?.durationHint ?? 0
    }

    private nonisolated static func makePlayerItem(source: PlayerStreamSource) async throws -> PreparedPlayerItem {
        guard let videoURL = source.videoURL else {
            throw PlayerEngineError.missingVideoURL
        }

        let headers = httpHeaders(referer: source.referer)

        if let audioURL = source.audioURL {
            let hlsBridge = try? await LocalHLSBridge.make(
                videoTrack: HLSBridgeTrack(
                    url: videoURL,
                    stream: source.videoStream,
                    mediaType: .video
                ),
                audioTrack: HLSBridgeTrack(
                    url: audioURL,
                    stream: source.audioStream,
                    mediaType: .audio
                ),
                durationHint: source.durationHint,
                headers: headers
            )
            if let hlsBridge {
                let asset = AVURLAsset(
                    url: hlsBridge.masterPlaylistURL,
                    options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
                )
                let item = AVPlayerItem(asset: asset)
                item.preferredForwardBufferDuration = 2
                return PreparedPlayerItem(item: item, bridge: hlsBridge, assets: [asset])
            }

            let composition = try await makeComposition(videoURL: videoURL, audioURL: audioURL, headers: headers)
            let item = AVPlayerItem(asset: composition)
            item.preferredForwardBufferDuration = 2
            return PreparedPlayerItem(item: item, bridge: nil, assets: [composition])
        }

        let asset = AVURLAsset(url: videoURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 2
        return PreparedPlayerItem(item: item, bridge: nil, assets: [asset])
    }

    private nonisolated static func makeComposition(
        videoURL: URL,
        audioURL: URL,
        headers: [String: String]
    ) async throws -> AVMutableComposition {
        let options = ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let videoAsset = AVURLAsset(url: videoURL, options: options)
        let audioAsset = AVURLAsset(url: audioURL, options: options)

        async let videoTracks = videoAsset.loadTracks(withMediaType: .video)
        async let audioTracks = audioAsset.loadTracks(withMediaType: .audio)
        async let videoDuration = videoAsset.load(.duration)
        async let audioDuration = audioAsset.load(.duration)

        guard let sourceVideoTrack = try await videoTracks.first else {
            throw PlayerEngineError.unsupportedMedia
        }
        let sourceAudioTrack = try await audioTracks.first
        let duration = try await minFinite(videoDuration, audioDuration)
        let composition = AVMutableComposition()
        let range = CMTimeRange(start: .zero, duration: duration)

        if let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try videoTrack.insertTimeRange(range, of: sourceVideoTrack, at: .zero)
            videoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        }

        if let sourceAudioTrack,
           let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try audioTrack.insertTimeRange(range, of: sourceAudioTrack, at: .zero)
        }

        return composition
    }

    private nonisolated static func minFinite(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
        let left = lhs.seconds
        let right = rhs.seconds
        if left.isFinite, right.isFinite, left > 0, right > 0 {
            return left <= right ? lhs : rhs
        }
        if left.isFinite, left > 0 {
            return lhs
        }
        if right.isFinite, right > 0 {
            return rhs
        }
        return .positiveInfinity
    }

    private nonisolated static func httpHeaders(referer: String) -> [String: String] {
        [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1",
            "Referer": referer,
            "Origin": "https://www.bilibili.com"
        ]
    }
}

private struct PreparedPlayerItem {
    let item: AVPlayerItem
    let bridge: LocalHLSBridge?
    let assets: [AVAsset]
}

private struct LocalHLSBridge: Sendable {
    let masterPlaylistURL: URL
    let server: LocalHLSProxyServer

    nonisolated static func make(
        videoTrack: HLSBridgeTrack,
        audioTrack: HLSBridgeTrack,
        durationHint: TimeInterval?,
        headers: [String: String]
    ) async throws -> LocalHLSBridge {
        async let videoRenditionTask = makeRendition(for: videoTrack, durationHint: durationHint, headers: headers)
        async let audioRenditionTask = makeRendition(for: audioTrack, durationHint: durationHint, headers: headers)
        let (videoRendition, audioRendition) = try await (videoRenditionTask, audioRenditionTask)

        let server = try LocalHLSProxyServer.make(headers: headers)
        let baseURL = server.baseURL
        let videoPlaylistURL = baseURL.appendingPathComponent("video.m3u8")
        let audioPlaylistURL = baseURL.appendingPathComponent("audio.m3u8")
        let masterPlaylistURL = baseURL.appendingPathComponent("master.m3u8")
        let videoPlaylist = videoRendition.playlist(baseURL: baseURL, routePrefix: "video")
        let audioPlaylist = audioRendition.playlist(baseURL: baseURL, routePrefix: "audio")
        let masterPlaylist = """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="audio",DEFAULT=YES,AUTOSELECT=YES,URI="\(audioPlaylistURL.absoluteString)"
        #EXT-X-STREAM-INF:BANDWIDTH=\(videoRendition.bandwidth),CODECS="\(videoRendition.codec),\(audioRendition.codec)",AUDIO="audio"
        \(videoPlaylistURL.absoluteString)
        """

        var routes: [String: HLSProxyRoute] = [
            "/master.m3u8": .data(Data(masterPlaylist.utf8), contentType: "application/vnd.apple.mpegurl"),
            "/video.m3u8": .data(Data(videoPlaylist.utf8), contentType: "application/vnd.apple.mpegurl"),
            "/audio.m3u8": .data(Data(audioPlaylist.utf8), contentType: "application/vnd.apple.mpegurl")
        ]
        videoRendition.registerRoutes(routePrefix: "video", into: &routes)
        audioRendition.registerRoutes(routePrefix: "audio", into: &routes)
        server.updateRoutes(routes)
        try await server.start()

        return LocalHLSBridge(masterPlaylistURL: masterPlaylistURL, server: server)
    }

    private nonisolated static func makeRendition(
        for track: HLSBridgeTrack,
        durationHint: TimeInterval?,
        headers: [String: String]
    ) async throws -> HLSRendition {
        guard let segmentBase = track.stream?.segmentBase,
              let initialization = segmentBase.initializationByteRange,
              let indexRange = segmentBase.indexByteRange
        else {
            throw PlayerEngineError.unsupportedMedia
        }

        let indexData = try await fetchByteRange(indexRange, from: track.url, headers: headers)
        let references = try SIDXParser.parseReferences(from: indexData, sidxStartOffset: indexRange.start)
        guard !references.isEmpty else {
            throw PlayerEngineError.unsupportedMedia
        }

        return HLSRendition(
            sourceURL: track.url,
            mediaType: track.mediaType,
            initialization: initialization,
            references: references,
            targetDuration: max(references.map(\.duration).max() ?? durationHint ?? 1, 1),
            bandwidth: max(track.stream?.bandwidth ?? 0, 128_000),
            codec: normalizedCodec(track.stream?.codecs, mediaType: track.mediaType)
        )
    }

    fileprivate nonisolated static func fetchByteRange(
        _ range: HTTPByteRange,
        from url: URL,
        headers: [String: String]
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 20
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.setValue("bytes=\(range.start)-\(range.endInclusive)", forHTTPHeaderField: "Range")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw PlayerEngineError.unsupportedMedia
        }
        return data
    }

    private nonisolated static func normalizedCodec(_ codec: String?, mediaType: HLSBridgeTrack.MediaType) -> String {
        guard let codec, !codec.isEmpty else {
            switch mediaType {
            case .audio:
                return "mp4a.40.2"
            case .video:
                return "avc1.640028"
            }
        }
        return codec
    }

    fileprivate nonisolated static func formatDuration(_ duration: TimeInterval) -> String {
        String(format: "%.6f", max(duration, 0.001))
    }
}

private struct HLSBridgeTrack: Sendable {
    enum MediaType: Sendable {
        case video
        case audio
    }

    let url: URL
    let stream: DASHStream?
    let mediaType: MediaType
}

private struct HLSRendition: Sendable {
    let sourceURL: URL
    let mediaType: HLSBridgeTrack.MediaType
    let initialization: HTTPByteRange
    let references: [SIDXParser.Reference]
    let targetDuration: TimeInterval
    let bandwidth: Int
    let codec: String

    nonisolated func playlist(baseURL: URL, routePrefix: String) -> String {
        let initURL = mediaURL(baseURL: baseURL, routePrefix: routePrefix, component: "init.mp4")
        let playlistSegments = references.enumerated().map { index, reference in
            let segmentURL = mediaURL(baseURL: baseURL, routePrefix: routePrefix, component: "segment-\(index).m4s")
            return """
            #EXTINF:\(LocalHLSBridge.formatDuration(reference.duration)),
            \(segmentURL.absoluteString)
            """
        }

        return """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-PLAYLIST-TYPE:VOD
        #EXT-X-TARGETDURATION:\(Int(ceil(targetDuration)))
        #EXT-X-MAP:URI="\(initURL.absoluteString)"
        \(playlistSegments.joined(separator: "\n"))
        #EXT-X-ENDLIST
        """
    }

    nonisolated func registerRoutes(routePrefix: String, into routes: inout [String: HLSProxyRoute]) {
        let contentType = mediaType == .audio ? "audio/mp4" : "video/mp4"
        routes["/media/\(routePrefix)/init.mp4"] = .remoteByteRange(
            url: sourceURL,
            range: initialization,
            contentType: contentType
        )

        for (index, reference) in references.enumerated() {
            routes["/media/\(routePrefix)/segment-\(index).m4s"] = .remoteByteRange(
                url: sourceURL,
                range: reference.range,
                contentType: contentType
            )
        }
    }

    nonisolated private func mediaURL(baseURL: URL, routePrefix: String, component: String) -> URL {
        baseURL
            .appendingPathComponent("media")
            .appendingPathComponent(routePrefix)
            .appendingPathComponent(component)
    }
}

private enum HLSProxyRoute: Sendable {
    case data(Data, contentType: String)
    case remoteByteRange(url: URL, range: HTTPByteRange, contentType: String)
}

private final class LocalHLSProxyServer: @unchecked Sendable {
    let baseURL: URL

    private let headers: [String: String]
    private let listener: NWListener
    private let queue: DispatchQueue
    private var routes: [String: HLSProxyRoute] = [:]
    private var isStarted = false

    nonisolated private init(port: UInt16, headers: [String: String]) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port),
              let baseURL = URL(string: "http://127.0.0.1:\(port)")
        else {
            throw PlayerEngineError.unsupportedMedia
        }
        self.baseURL = baseURL
        self.headers = headers
        self.listener = try NWListener(using: .tcp, on: endpointPort)
        self.queue = DispatchQueue(label: "cc.bili.local-hls.\(port)", qos: .userInitiated)
    }

    deinit {
        listener.cancel()
    }

    nonisolated static func make(headers: [String: String]) throws -> LocalHLSProxyServer {
        var lastError: Error?
        for _ in 0..<24 {
            let port = UInt16.random(in: 49152...61000)
            do {
                return try LocalHLSProxyServer(port: port, headers: headers)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? PlayerEngineError.unsupportedMedia
    }

    nonisolated func updateRoutes(_ routes: [String: HLSProxyRoute]) {
        queue.async { [weak self] in
            self?.routes = routes
        }
    }

    nonisolated func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: PlayerEngineError.unsupportedMedia)
                    return
                }
                guard !self.isStarted else {
                    continuation.resume()
                    return
                }
                self.isStarted = true

                var didResume = false
                self.listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        guard !didResume else { return }
                        didResume = true
                        continuation.resume()
                    case let .failed(error):
                        guard !didResume else { return }
                        didResume = true
                        continuation.resume(throwing: error)
                    case .cancelled:
                        break
                    default:
                        break
                    }
                }
                self.listener.newConnectionHandler = { [weak self] connection in
                    self?.handleConnection(connection)
                }
                self.listener.start(queue: self.queue)
            }
        }
    }

    nonisolated private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(from: connection, accumulatedData: Data())
    }

    nonisolated private func receiveRequest(from connection: NWConnection, accumulatedData: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if error != nil {
                connection.cancel()
                return
            }

            var requestData = accumulatedData
            if let data {
                requestData.append(data)
            }

            if requestData.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.respond(to: connection, requestData: requestData)
            } else if isComplete || requestData.count > 64 * 1024 {
                self.sendError(400, reason: "Bad Request", to: connection)
            } else {
                self.receiveRequest(from: connection, accumulatedData: requestData)
            }
        }
    }

    nonisolated private func respond(to connection: NWConnection, requestData: Data) {
        guard let request = HLSProxyRequest(data: requestData) else {
            sendError(400, reason: "Bad Request", to: connection)
            return
        }

        guard request.method == "GET" || request.method == "HEAD" else {
            sendError(405, reason: "Method Not Allowed", to: connection)
            return
        }

        guard let route = routes[request.path] else {
            sendError(404, reason: "Not Found", to: connection)
            return
        }

        switch route {
        case let .data(data, contentType):
            sendData(data, contentType: contentType, request: request, to: connection)
        case let .remoteByteRange(url, sourceRange, contentType):
            Task.detached(priority: .userInitiated) { [headers] in
                do {
                    let resolvedRange = request.range?.clamped(toLength: sourceRange.length)
                    let fetchRange: HTTPByteRange
                    if let resolvedRange {
                        fetchRange = HTTPByteRange(
                            start: sourceRange.start + resolvedRange.start,
                            endInclusive: sourceRange.start + resolvedRange.endInclusive
                        )
                    } else {
                        fetchRange = sourceRange
                    }
                    let data: Data
                    if let cached = await VideoRangeCache.shared.data(url: url, range: fetchRange) {
                        data = cached
                    } else {
                        data = try await LocalHLSBridge.fetchByteRange(fetchRange, from: url, headers: headers)
                        await VideoRangeCache.shared.store(data, url: url, range: fetchRange)
                    }
                    self.queue.async {
                        self.sendData(
                            data,
                            contentType: contentType,
                            request: request,
                            totalLength: sourceRange.length,
                            servedRange: resolvedRange,
                            to: connection
                        )
                    }
                } catch {
                    self.queue.async {
                        self.sendError(502, reason: "Bad Gateway", to: connection)
                    }
                }
            }
        }
    }

    nonisolated private func sendData(
        _ data: Data,
        contentType: String,
        request: HLSProxyRequest,
        totalLength: Int64? = nil,
        servedRange: HTTPByteRange? = nil,
        to connection: NWConnection
    ) {
        let body = request.method == "HEAD" ? Data() : data
        var headers = [
            "Content-Type": contentType,
            "Content-Length": "\(data.count)",
            "Accept-Ranges": "bytes",
            "Cache-Control": "no-store",
            "Connection": "close"
        ]
        let statusLine: String
        if let servedRange, let totalLength {
            statusLine = "HTTP/1.1 206 Partial Content"
            headers["Content-Range"] = "bytes \(servedRange.start)-\(servedRange.endInclusive)/\(totalLength)"
        } else {
            statusLine = "HTTP/1.1 200 OK"
        }
        sendResponse(statusLine: statusLine, headers: headers, body: body, to: connection)
    }

    nonisolated private func sendError(_ statusCode: Int, reason: String, to connection: NWConnection) {
        let body = Data(reason.utf8)
        sendResponse(
            statusLine: "HTTP/1.1 \(statusCode) \(reason)",
            headers: [
                "Content-Type": "text/plain; charset=utf-8",
                "Content-Length": "\(body.count)",
                "Connection": "close"
            ],
            body: body,
            to: connection
        )
    }

    nonisolated private func sendResponse(
        statusLine: String,
        headers: [String: String],
        body: Data,
        to connection: NWConnection
    ) {
        let headerText = ([statusLine] + headers.map { "\($0.key): \($0.value)" })
            .joined(separator: "\r\n") + "\r\n\r\n"
        var response = Data(headerText.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

private struct HLSProxyRequest: Sendable {
    let method: String
    let path: String
    let range: HTTPByteRange?

    init?(data: Data) {
        guard let rawRequest = String(data: data, encoding: .utf8) else { return nil }
        let lines = rawRequest.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count >= 2 else { return nil }

        method = requestParts[0]
        let rawPath = requestParts[1]
        path = URLComponents(string: "http://127.0.0.1\(rawPath)")?.path ?? rawPath

        var parsedRange: HTTPByteRange?
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            if parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "range" {
                parsedRange = HTTPByteRange(httpHeaderValue: parts[1])
                break
            }
        }
        range = parsedRange
    }
}

private struct SIDXParser {
    struct Reference {
        let range: HTTPByteRange
        let duration: TimeInterval
    }

    nonisolated static func parseReferences(from data: Data, sidxStartOffset: Int64) throws -> [Reference] {
        let bytes = [UInt8](data)
        guard bytes.count >= 12 else { throw PlayerEngineError.unsupportedMedia }

        var offset = 0
        if String(bytes: bytes[4..<min(8, bytes.count)], encoding: .ascii) != "sidx" {
            while offset + 8 <= bytes.count {
                let size = Int(readUInt32(bytes, offset: offset))
                guard size >= 8, offset + size <= bytes.count else { break }
                let type = String(bytes: bytes[(offset + 4)..<(offset + 8)], encoding: .ascii)
                if type == "sidx" {
                    break
                }
                offset += size
            }
        }

        guard offset + 12 <= bytes.count,
              String(bytes: bytes[(offset + 4)..<(offset + 8)], encoding: .ascii) == "sidx"
        else {
            throw PlayerEngineError.unsupportedMedia
        }

        let boxSize = Int64(readUInt32(bytes, offset: offset))
        let version = bytes[offset + 8]
        var cursor = offset + 12
        guard cursor + 8 <= bytes.count else { throw PlayerEngineError.unsupportedMedia }
        cursor += 4
        let timescale = Double(readUInt32(bytes, offset: cursor))
        cursor += 4
        guard timescale > 0 else { throw PlayerEngineError.unsupportedMedia }

        let firstOffset: Int64
        if version == 0 {
            guard cursor + 8 <= bytes.count else { throw PlayerEngineError.unsupportedMedia }
            cursor += 4
            firstOffset = Int64(readUInt32(bytes, offset: cursor))
            cursor += 4
        } else {
            guard cursor + 16 <= bytes.count else { throw PlayerEngineError.unsupportedMedia }
            cursor += 8
            firstOffset = Int64(readUInt64(bytes, offset: cursor))
            cursor += 8
        }

        cursor += 2
        guard cursor + 2 <= bytes.count else { throw PlayerEngineError.unsupportedMedia }
        let referenceCount = Int(readUInt16(bytes, offset: cursor))
        cursor += 2

        var mediaOffset = sidxStartOffset + boxSize + firstOffset
        var references = [Reference]()
        references.reserveCapacity(referenceCount)

        for _ in 0..<referenceCount {
            guard cursor + 12 <= bytes.count else { break }
            let typeAndSize = readUInt32(bytes, offset: cursor)
            cursor += 4
            let isSubsegment = (typeAndSize & 0x8000_0000) != 0
            let size = Int64(typeAndSize & 0x7fff_ffff)
            let duration = TimeInterval(readUInt32(bytes, offset: cursor)) / timescale
            cursor += 4
            cursor += 4
            guard !isSubsegment, size > 0 else { continue }
            references.append(Reference(
                range: HTTPByteRange(start: mediaOffset, endInclusive: mediaOffset + size - 1),
                duration: duration
            ))
            mediaOffset += size
        }

        return references
    }

    private nonisolated static func readUInt16(_ bytes: [UInt8], offset: Int) -> UInt16 {
        (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    private nonisolated static func readUInt32(_ bytes: [UInt8], offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }

    private nonisolated static func readUInt64(_ bytes: [UInt8], offset: Int) -> UInt64 {
        (UInt64(readUInt32(bytes, offset: offset)) << 32)
            | UInt64(readUInt32(bytes, offset: offset + 4))
    }
}
