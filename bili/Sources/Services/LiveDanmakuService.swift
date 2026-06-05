import Compression
import Foundation
import OSLog

nonisolated enum LiveDanmakuDiagnosticPhase: Equatable, Sendable {
    case idle
    case fetchingConfig
    case connecting
    case authenticating
    case waitingForPackets
    case receiving
    case rendering
    case reconnecting
    case stopped
    case failed

    var title: String {
        switch self {
        case .idle:
            return "待启动"
        case .fetchingConfig:
            return "取配置"
        case .connecting:
            return "连接中"
        case .authenticating:
            return "鉴权中"
        case .waitingForPackets:
            return "等收包"
        case .receiving:
            return "接收中"
        case .rendering:
            return "已渲染"
        case .reconnecting:
            return "重连中"
        case .stopped:
            return "已停止"
        case .failed:
            return "异常"
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            return "pause.circle"
        case .fetchingConfig:
            return "arrow.down.circle"
        case .connecting:
            return "network"
        case .authenticating:
            return "key.horizontal"
        case .waitingForPackets:
            return "clock"
        case .receiving:
            return "waveform.path.ecg"
        case .rendering:
            return "checkmark.circle.fill"
        case .reconnecting:
            return "arrow.clockwise"
        case .stopped:
            return "stop.circle"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }
}

nonisolated enum LiveDanmakuDiagnosticEvent: Sendable {
    case serviceStarted(roomID: Int)
    case contextReady(uid: Int, hasCookie: Bool, hasBuvid: Bool)
    case configRequestStarted
    case configLoaded(hostCount: Int, hasToken: Bool, selectedEndpoint: String?)
    case webSocketResumed(endpoint: String)
    case authSent(hasToken: Bool)
    case heartbeatStarted
    case heartbeatSent
    case messageReceived(byteCount: Int)
    case packetReceived(operation: Int, version: Int, bodyBytes: Int)
    case authReply
    case heartbeatReply
    case commandPacket(version: Int, bodyBytes: Int)
    case commandReceived(name: String)
    case danmakuParsed(text: String)
    case itemsDelivered(count: Int)
    case inflateSucceeded(version: Int, byteCount: Int)
    case inflateFailed(version: Int)
    case jsonParseFailed(byteCount: Int)
    case reconnectScheduled(error: String)
    case stopped
    case renderState(isDanmakuEnabled: Bool, overlayItemCount: Int, hasPresentedPlayback: Bool)
}

nonisolated struct LiveDanmakuDiagnosticSnapshot: Equatable, Sendable {
    var roomID: Int
    var phase: LiveDanmakuDiagnosticPhase
    var startedAt: Date
    var updatedAt: Date
    var uid: Int
    var hasCookie: Bool
    var hasBuvid: Bool
    var hostCount: Int
    var hasToken: Bool
    var selectedEndpoint: String?
    var heartbeatSentCount: Int
    var heartbeatReplyCount: Int
    var rawMessageCount: Int
    var rawBytesReceived: Int
    var packetCount: Int
    var authReplyCount: Int
    var commandPacketCount: Int
    var commandCount: Int
    var danmakuCommandCount: Int
    var parsedItemCount: Int
    var deliveredItemCount: Int
    var overlayItemCount: Int
    var inflateSuccessCount: Int
    var inflateFailureCount: Int
    var jsonParseFailureCount: Int
    var reconnectCount: Int
    var isDanmakuEnabled: Bool
    var hasPresentedPlayback: Bool
    var lastCommandName: String?
    var lastDanmakuText: String?
    var lastError: String?
    var lastPacketAt: Date?
    var lastHeartbeatReplyAt: Date?
    var lastDeliveredAt: Date?

    init(roomID: Int) {
        let now = Date()
        self.roomID = roomID
        self.phase = .idle
        self.startedAt = now
        self.updatedAt = now
        self.uid = 0
        self.hasCookie = false
        self.hasBuvid = false
        self.hostCount = 0
        self.hasToken = false
        self.selectedEndpoint = nil
        self.heartbeatSentCount = 0
        self.heartbeatReplyCount = 0
        self.rawMessageCount = 0
        self.rawBytesReceived = 0
        self.packetCount = 0
        self.authReplyCount = 0
        self.commandPacketCount = 0
        self.commandCount = 0
        self.danmakuCommandCount = 0
        self.parsedItemCount = 0
        self.deliveredItemCount = 0
        self.overlayItemCount = 0
        self.inflateSuccessCount = 0
        self.inflateFailureCount = 0
        self.jsonParseFailureCount = 0
        self.reconnectCount = 0
        self.isDanmakuEnabled = true
        self.hasPresentedPlayback = false
        self.lastCommandName = nil
        self.lastDanmakuText = nil
        self.lastError = nil
        self.lastPacketAt = nil
        self.lastHeartbeatReplyAt = nil
        self.lastDeliveredAt = nil
    }

    var selectedEndpointHost: String {
        guard let selectedEndpoint, !selectedEndpoint.isEmpty else { return "-" }
        return URL(string: selectedEndpoint)?.host ?? selectedEndpoint
    }

    var configSummary: String {
        if hostCount > 0 || selectedEndpoint != nil {
            let hostText = hostCount > 0 ? "\(hostCount) 节点" : "默认节点"
            return "\(hostText) · \(hasToken ? "有 token" : "无 token")"
        }
        if phase == .fetchingConfig {
            return "请求中"
        }
        return "未获取"
    }

    var connectionSummary: String {
        if phase == .connecting || phase == .authenticating || phase == .waitingForPackets || rawMessageCount > 0 {
            return selectedEndpointHost
        }
        if phase == .reconnecting {
            return "等待重连"
        }
        return "-"
    }

    var receiveSummary: String {
        "\(rawMessageCount) 消息 · \(packetCount) 包"
    }

    var commandSummary: String {
        "\(commandCount) 命令 · \(danmakuCommandCount) 弹幕"
    }

    var renderSummary: String {
        guard isDanmakuEnabled else { return "弹幕关闭" }
        if deliveredItemCount > 0 || overlayItemCount > 0 {
            return "\(overlayItemCount) 条在覆盖层"
        }
        return "未收到可渲染弹幕"
    }

    var conclusion: String {
        if !isDanmakuEnabled {
            return "弹幕开关已关闭，覆盖层不会渲染。"
        }
        if phase == .failed, let lastError {
            return "弹幕链路异常：\(lastError)"
        }
        if phase == .fetchingConfig || (hostCount == 0 && rawMessageCount == 0) {
            return "正在获取直播弹幕配置。"
        }
        if phase == .connecting || phase == .authenticating {
            return "已拿到配置，正在建立弹幕 WebSocket。"
        }
        if rawMessageCount == 0 {
            if reconnectCount > 0, let lastError {
                return "WebSocket 暂无回包，正在重连：\(lastError)"
            }
            return "WebSocket 已启动，正在等待服务端回包。"
        }
        if deliveredItemCount > 0 && overlayItemCount == 0 {
            return "弹幕已交给 UI，但覆盖层列表为空。"
        }
        if deliveredItemCount > 0 && !hasPresentedPlayback {
            return "弹幕链路正常，播放器首帧未完成时可能暂时看不到。"
        }
        if deliveredItemCount > 0 {
            return "直播弹幕链路正常。"
        }
        if danmakuCommandCount > 0 {
            return "已经解析到弹幕，但还没有交给 UI 覆盖层。"
        }
        if commandCount > 0 && danmakuCommandCount == 0 {
            if let lastCommandName {
                return "收到直播命令，但暂时没有可渲染文本；最后命令 \(lastCommandName)。"
            }
            return "收到直播命令，但暂时没有可渲染文本。"
        }
        if inflateFailureCount > 0 && commandCount == 0 {
            return "收到命令包但解压失败，优先检查压缩协议。"
        }
        if jsonParseFailureCount > 0 && commandCount == 0 {
            return "收到命令包但 JSON 解析失败，优先检查消息格式。"
        }
        if packetCount > 0 && commandPacketCount == 0 {
            return "连接正常，目前只收到心跳/系统包。"
        }
        if authReplyCount == 0 {
            return "已经收到服务端数据，但还没有识别到鉴权回包。"
        }
        return "链路已建立，正在等待直播间弹幕。"
    }

    mutating func apply(_ event: LiveDanmakuDiagnosticEvent) {
        let now = Date()
        updatedAt = now
        switch event {
        case .serviceStarted(let roomID):
            self = LiveDanmakuDiagnosticSnapshot(roomID: roomID)
            phase = .fetchingConfig
            startedAt = now
            updatedAt = now
        case .contextReady(let uid, let hasCookie, let hasBuvid):
            self.uid = uid
            self.hasCookie = hasCookie
            self.hasBuvid = hasBuvid
        case .configRequestStarted:
            phase = .fetchingConfig
            lastError = nil
        case .configLoaded(let hostCount, let hasToken, let selectedEndpoint):
            self.hostCount = hostCount
            self.hasToken = hasToken
            self.selectedEndpoint = selectedEndpoint
            phase = .connecting
            lastError = nil
        case .webSocketResumed(let endpoint):
            selectedEndpoint = endpoint
            phase = .authenticating
        case .authSent(let hasToken):
            self.hasToken = hasToken
            phase = .authenticating
        case .heartbeatStarted:
            phase = .waitingForPackets
        case .heartbeatSent:
            heartbeatSentCount += 1
        case .messageReceived(let byteCount):
            rawMessageCount += 1
            rawBytesReceived += byteCount
            lastPacketAt = now
            if phase != .rendering {
                phase = .receiving
            }
        case .packetReceived:
            packetCount += 1
            lastPacketAt = now
        case .authReply:
            authReplyCount += 1
            if phase != .rendering {
                phase = .waitingForPackets
            }
        case .heartbeatReply:
            heartbeatReplyCount += 1
            lastHeartbeatReplyAt = now
        case .commandPacket:
            commandPacketCount += 1
        case .commandReceived(let name):
            commandCount += 1
            lastCommandName = name
        case .danmakuParsed(let text):
            danmakuCommandCount += 1
            parsedItemCount += 1
            lastDanmakuText = text
        case .itemsDelivered(let count):
            deliveredItemCount += count
            lastDeliveredAt = now
            phase = .rendering
        case .inflateSucceeded:
            inflateSuccessCount += 1
        case .inflateFailed:
            inflateFailureCount += 1
        case .jsonParseFailed:
            jsonParseFailureCount += 1
        case .reconnectScheduled(let error):
            reconnectCount += 1
            lastError = error
            phase = .reconnecting
        case .stopped:
            phase = .stopped
        case .renderState(let isDanmakuEnabled, let overlayItemCount, let hasPresentedPlayback):
            self.isDanmakuEnabled = isDanmakuEnabled
            self.overlayItemCount = overlayItemCount
            self.hasPresentedPlayback = hasPresentedPlayback
        }
    }
}

nonisolated final class LiveDanmakuService: @unchecked Sendable {
    typealias ItemHandler = @MainActor ([DanmakuItem]) -> Void
    typealias DiagnosticHandler = @MainActor (LiveDanmakuDiagnosticEvent) -> Void

    private enum Operation {
        static let heartbeat = 2
        static let heartbeatReply = 3
        static let command = 5
        static let auth = 7
        static let authReply = 8
    }

    private struct Packet {
        let version: Int
        let operation: Int
        let body: Data
    }

    private struct ParseResult {
        var items: [DanmakuItem] = []
        var events: [LiveDanmakuDiagnosticEvent] = []

        mutating func append(_ other: ParseResult) {
            items.append(contentsOf: other.items)
            events.append(contentsOf: other.events)
        }
    }

    private struct LiveMessagePayload {
        let text: String
        let color: UInt32
        let mode: Int
        let fontSize: Double
    }

    private let roomID: Int
    private let api: BiliAPIClient
    private let session: URLSession
    private let onItems: ItemHandler
    private let onDiagnostics: DiagnosticHandler?
    private let logger = Logger(subsystem: "cc.bili", category: "LiveDanmaku")
    private let stateQueue = DispatchQueue(label: "cc.bili.live-danmaku.state")
    private var task: URLSessionWebSocketTask?
    private var heartbeatTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var isStopped = false
    private var sequence = 0
    private var reconnectAttempt = 0
    private let startDate = Date()

    init(
        roomID: Int,
        api: BiliAPIClient,
        onDiagnostics: DiagnosticHandler? = nil,
        onItems: @escaping ItemHandler
    ) {
        self.roomID = roomID
        self.api = api
        self.onDiagnostics = onDiagnostics
        self.onItems = onItems
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
    }

    deinit {
        stop()
        session.invalidateAndCancel()
    }

    func start() {
        stateQueue.async { [weak self] in
            guard let self, self.task == nil, !self.isStopped else { return }
            self.emitDiagnostic(.serviceStarted(roomID: self.roomID))
            self.connect()
        }
    }

    func stop() {
        stateQueue.sync {
            isStopped = true
            heartbeatTask?.cancel()
            receiveTask?.cancel()
            reconnectTask?.cancel()
            heartbeatTask = nil
            receiveTask = nil
            reconnectTask = nil
            reconnectAttempt = 0
            task?.cancel(with: .goingAway, reason: nil)
            task = nil
            emitDiagnostic(.stopped)
        }
    }

    private func connect() {
        receiveTask?.cancel()
        heartbeatTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            do {
                let context = await api.liveDanmakuClientContext(roomID: roomID)
                emitDiagnostic(
                    .contextReady(
                        uid: context.uid,
                        hasCookie: !context.cookieHeader.isEmpty,
                        hasBuvid: !context.buvid.isEmpty
                    )
                )
                emitDiagnostic(.configRequestStarted)
                let info = try await api.fetchLiveDanmakuConnectionInfo(
                    roomID: roomID,
                    cookieHeader: context.cookieHeader
                )
                let url = info.hostList.compactMap(\.webSocketURL).first
                    ?? URL(string: "wss://broadcastlv.chat.bilibili.com:443/sub")
                guard let url else { throw BiliAPIError.invalidURL }
                emitDiagnostic(
                    .configLoaded(
                        hostCount: info.hostList.count,
                        hasToken: info.token?.isEmpty == false,
                        selectedEndpoint: url.absoluteString
                    )
                )

                var request = URLRequest(url: url)
                request.timeoutInterval = 8
                context.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

                let webSocketTask = session.webSocketTask(with: request)
                guard await setTask(webSocketTask) else { return }
                webSocketTask.resume()
                emitDiagnostic(.webSocketResumed(endpoint: url.absoluteString))
                try await sendAuth(token: info.token, context: context, on: webSocketTask)
                await startHeartbeat(on: webSocketTask)
                try await receiveLoop(webSocketTask)
            } catch {
                emitDiagnostic(.reconnectScheduled(error: error.localizedDescription))
                logger.warning("liveDanmaku reconnect room=\(self.roomID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                await scheduleReconnectIfNeeded()
            }
        }
    }

    private func emitDiagnostic(_ event: LiveDanmakuDiagnosticEvent) {
        guard let onDiagnostics else { return }
        Task { @MainActor in
            onDiagnostics(event)
        }
    }

    private func setTask(_ webSocketTask: URLSessionWebSocketTask) async -> Bool {
        await withCheckedContinuation { continuation in
            stateQueue.async { [weak self] in
                guard let self, !self.isStopped else {
                    webSocketTask.cancel(with: .goingAway, reason: nil)
                    continuation.resume(returning: false)
                    return
                }
                self.task?.cancel(with: .goingAway, reason: nil)
                self.task = webSocketTask
                continuation.resume(returning: true)
            }
        }
    }

    private func isCurrentTask(_ webSocketTask: URLSessionWebSocketTask) async -> Bool {
        await withCheckedContinuation { continuation in
            stateQueue.async { [weak self] in
                guard let self, !self.isStopped else {
                    continuation.resume(returning: false)
                    return
                }
                continuation.resume(returning: self.task === webSocketTask)
            }
        }
    }

    private func sendAuth(
        token: String?,
        context: LiveDanmakuClientContext,
        on webSocketTask: URLSessionWebSocketTask
    ) async throws {
        let payload: [String: Any] = [
            "uid": context.uid,
            "roomid": roomID,
            "protover": 3,
            "platform": "web",
            "clientver": "1.14.3",
            "type": 2,
            "buvid": context.buvid,
            "key": token ?? ""
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        try await sendPacket(operation: Operation.auth, body: body, on: webSocketTask)
        emitDiagnostic(.authSent(hasToken: token?.isEmpty == false))
    }

    private func startHeartbeat(on webSocketTask: URLSessionWebSocketTask) async {
        heartbeatTask?.cancel()
        emitDiagnostic(.heartbeatStarted)
        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                guard await self.isCurrentTask(webSocketTask) else { return }
                do {
                    try await self.sendPacket(
                        operation: Operation.heartbeat,
                        body: Data("[object Object]".utf8),
                        on: webSocketTask
                    )
                    self.emitDiagnostic(.heartbeatSent)
                } catch {
                    self.emitDiagnostic(.reconnectScheduled(error: error.localizedDescription))
                }
            }
        }
    }

    private func sendPacket(
        operation: Int,
        body: Data,
        on webSocketTask: URLSessionWebSocketTask
    ) async throws {
        let packet = Self.encodePacket(operation: operation, body: body)
        try await webSocketTask.send(.data(packet))
    }

    private func receiveLoop(_ webSocketTask: URLSessionWebSocketTask) async throws {
        while !Task.isCancelled {
            let message = try await webSocketTask.receive()
            let data: Data?
            switch message {
            case .data(let value):
                data = value
            case .string(let value):
                data = Data(value.utf8)
            @unknown default:
                data = nil
            }
            guard let data else { continue }
            markConnectionHealthy()
            emitDiagnostic(.messageReceived(byteCount: data.count))
            let result = Self.parseItems(from: data, roomID: roomID, startDate: startDate)
            result.events.forEach(emitDiagnostic)
            let items = result.items
            guard !items.isEmpty else { continue }
            emitDiagnostic(.itemsDelivered(count: items.count))
            await onItems(items)
        }
    }

    private func scheduleReconnectIfNeeded() async {
        await withCheckedContinuation { continuation in
            stateQueue.async { [weak self] in
                guard let self, !self.isStopped else {
                    continuation.resume()
                    return
                }
                self.task?.cancel(with: .goingAway, reason: nil)
                self.task = nil
                self.heartbeatTask?.cancel()
                self.heartbeatTask = nil
                self.reconnectTask?.cancel()
                let delayNanoseconds = Self.reconnectDelayNanoseconds(for: self.reconnectAttempt)
                self.reconnectAttempt = min(self.reconnectAttempt + 1, 5)
                self.reconnectTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: delayNanoseconds)
                    guard !Task.isCancelled else { return }
                    self?.stateQueue.async { [weak self] in
                        guard let self, !self.isStopped, self.task == nil else { return }
                        self.connect()
                    }
                }
                continuation.resume()
            }
        }
    }

    private func markConnectionHealthy() {
        stateQueue.async { [weak self] in
            self?.reconnectAttempt = 0
        }
    }

    private static func reconnectDelayNanoseconds(for attempt: Int) -> UInt64 {
        let delays: [UInt64] = [
            2_000_000_000,
            4_000_000_000,
            8_000_000_000,
            15_000_000_000,
            30_000_000_000,
            45_000_000_000
        ]
        return delays[min(max(attempt, 0), delays.count - 1)]
    }

    private static func encodePacket(operation: Int, body: Data) -> Data {
        var data = Data()
        data.appendBigEndianUInt32(UInt32(16 + body.count))
        data.appendBigEndianUInt16(16)
        data.appendBigEndianUInt16(1)
        data.appendBigEndianUInt32(UInt32(operation))
        data.appendBigEndianUInt32(1)
        data.append(body)
        return data
    }

    private static func parseItems(from data: Data, roomID: Int, startDate: Date) -> ParseResult {
        var result = ParseResult()
        for packet in parsePackets(from: data) {
            result.events.append(
                .packetReceived(
                    operation: packet.operation,
                    version: packet.version,
                    bodyBytes: packet.body.count
                )
            )
            switch packet.operation {
            case Operation.command:
                result.events.append(.commandPacket(version: packet.version, bodyBytes: packet.body.count))
                result.append(parseCommandPacket(packet, roomID: roomID, startDate: startDate))
            case Operation.authReply:
                result.events.append(.authReply)
            case Operation.heartbeatReply:
                result.events.append(.heartbeatReply)
            default:
                break
            }
        }
        return result
    }

    private static func parseCommandPacket(_ packet: Packet, roomID: Int, startDate: Date) -> ParseResult {
        switch packet.version {
        case 0, 1:
            return parseJSONCommands(packet.body, roomID: roomID, startDate: startDate)
        case 2:
            guard let inflated = inflate(packet.body, algorithm: COMPRESSION_ZLIB) else {
                return ParseResult(events: [.inflateFailed(version: packet.version)])
            }
            var result = ParseResult(events: [.inflateSucceeded(version: packet.version, byteCount: inflated.count)])
            result.append(parseInflatedCommandBody(inflated, roomID: roomID, startDate: startDate))
            return result
        case 3:
            guard let inflated = inflate(packet.body, algorithm: COMPRESSION_BROTLI)
                ?? inflate(packet.body, algorithm: COMPRESSION_ZLIB)
            else {
                return ParseResult(events: [.inflateFailed(version: packet.version)])
            }
            var result = ParseResult(events: [.inflateSucceeded(version: packet.version, byteCount: inflated.count)])
            result.append(parseInflatedCommandBody(inflated, roomID: roomID, startDate: startDate))
            return result
        default:
            return ParseResult()
        }
    }

    private static func parseInflatedCommandBody(_ data: Data, roomID: Int, startDate: Date) -> ParseResult {
        let nestedItems = parseItems(from: data, roomID: roomID, startDate: startDate)
        if !nestedItems.items.isEmpty {
            return nestedItems
        }
        var result = nestedItems
        result.append(parseJSONCommands(data, roomID: roomID, startDate: startDate))
        return result
    }

    private static func parsePackets(from data: Data) -> [Packet] {
        var packets: [Packet] = []
        var offset = 0
        let bytes = [UInt8](data)
        while offset + 16 <= bytes.count {
            let packetLength = Int(bytes.bigEndianUInt32(at: offset))
            let headerLength = Int(bytes.bigEndianUInt16(at: offset + 4))
            let version = Int(bytes.bigEndianUInt16(at: offset + 6))
            let operation = Int(bytes.bigEndianUInt32(at: offset + 8))
            guard packetLength >= headerLength,
                  headerLength >= 16,
                  offset + packetLength <= bytes.count
            else { break }
            let body = Data(bytes[(offset + headerLength)..<(offset + packetLength)])
            packets.append(Packet(version: version, operation: operation, body: body))
            offset += packetLength
        }
        return packets
    }

    private static func parseJSONCommands(_ data: Data, roomID: Int, startDate: Date) -> ParseResult {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return ParseResult(events: [.jsonParseFailed(byteCount: data.count)])
        }
        if let commands = object as? [[String: Any]] {
            var result = ParseResult()
            for command in commands {
                result.append(parseJSONCommand(command, roomID: roomID, startDate: startDate))
            }
            return result
        }
        guard let command = object as? [String: Any] else { return ParseResult() }
        return parseJSONCommand(command, roomID: roomID, startDate: startDate)
    }

    private static func parseJSONCommand(_ object: [String: Any], roomID: Int, startDate: Date) -> ParseResult {
        guard let command = object["cmd"] as? String else { return ParseResult() }
        var result = ParseResult(events: [.commandReceived(name: command)])
        guard let payload = liveMessagePayload(for: command, object: object) else { return result }

        let trimmedText = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return result }
        let currentTime = max(0, Date().timeIntervalSince(startDate))
        let commandID = command.replacingOccurrences(
            of: #"[^A-Za-z0-9_:-]"#,
            with: "-",
            options: .regularExpression
        )
        let id = "live-\(roomID)-\(Int(currentTime * 1000))-\(commandID)-\(UUID().uuidString)"
        result.items = [
            DanmakuItem(
                id: id,
                time: currentTime,
                mode: payload.mode,
                fontSize: payload.fontSize,
                color: payload.color,
                text: trimmedText
            )
        ]
        result.events.append(.danmakuParsed(text: trimmedText))
        return result
    }

    private static func liveMessagePayload(for command: String, object: [String: Any]) -> LiveMessagePayload? {
        let baseCommand = commandBaseName(command)
        switch baseCommand {
        case "DANMU_MSG":
            return danmakuMessagePayload(from: object)
        case "SUPER_CHAT_MESSAGE", "SUPER_CHAT_MESSAGE_JPN":
            return superChatMessagePayload(from: object)
        case "DM_INTERACTION":
            return textMessagePayload(
                from: object,
                keys: ["msg", "message", "content", "text", "desc"],
                color: 0x7DD3FC
            )
        case "INTERACT_WORD":
            return interactWordPayload(from: object)
        case "ENTRY_EFFECT":
            return entryEffectPayload(from: object)
        case "NOTICE_MSG":
            return noticeMessagePayload(from: object)
        case "SEND_GIFT", "COMBO_SEND":
            return giftMessagePayload(from: object)
        case "GUARD_BUY":
            return guardBuyPayload(from: object)
        default:
            return nil
        }
    }

    private static func commandBaseName(_ command: String) -> String {
        guard let separatorIndex = command.firstIndex(of: ":") else { return command }
        return String(command[..<separatorIndex])
    }

    private static func danmakuMessagePayload(from object: [String: Any]) -> LiveMessagePayload? {
        guard let info = object["info"] as? [Any],
              info.count > 1,
              let text = info[1] as? String,
              let normalizedText = normalizedMessageText(text)
        else { return nil }
        return LiveMessagePayload(
            text: normalizedText,
            color: color(from: info),
            mode: 1,
            fontSize: 25
        )
    }

    private static func superChatMessagePayload(from object: [String: Any]) -> LiveMessagePayload? {
        let data = object["data"] as? [String: Any]
        let text = firstString(
            in: data,
            keys: ["message", "message_jpn", "message_trans", "msg", "content"]
        )
        guard let text else { return nil }
        let color = firstColor(
            in: data,
            keys: ["background_bottom_color", "background_color", "message_color"],
            defaultColor: 0xFACC15
        )
        return LiveMessagePayload(text: text, color: color, mode: 5, fontSize: 25)
    }

    private static func interactWordPayload(from object: [String: Any]) -> LiveMessagePayload? {
        guard let data = object["data"] as? [String: Any] else { return nil }
        if let text = firstString(in: data, keys: ["msg", "message", "content", "text"]) {
            return LiveMessagePayload(text: text, color: 0xE5E7EB, mode: 1, fontSize: 24)
        }
        guard let userName = firstString(in: data, keys: ["uname", "user_name", "username", "name"]),
              let action = interactWordAction(from: data)
        else { return nil }
        return LiveMessagePayload(text: "\(userName) \(action)", color: 0xE5E7EB, mode: 1, fontSize: 24)
    }

    private static func interactWordAction(from data: [String: Any]) -> String? {
        switch intValue(data["msg_type"]) {
        case 1:
            return "进入直播间"
        case 2:
            return "关注了直播间"
        case 3:
            return "分享了直播间"
        case 4:
            return "特别关注进入直播间"
        default:
            return nil
        }
    }

    private static func entryEffectPayload(from object: [String: Any]) -> LiveMessagePayload? {
        guard let data = object["data"] as? [String: Any] else { return nil }
        guard var text = firstString(in: data, keys: ["copy_writing", "msg", "content", "text"]) else {
            return nil
        }
        if let userName = nestedUserName(in: data), text.contains("<%user_name%>") {
            text = text.replacingOccurrences(of: "<%user_name%>", with: userName)
        }
        guard let normalizedText = normalizedMessageText(text) else { return nil }
        return LiveMessagePayload(text: normalizedText, color: 0xFDE68A, mode: 1, fontSize: 24)
    }

    private static func noticeMessagePayload(from object: [String: Any]) -> LiveMessagePayload? {
        let text = firstString(
            in: object,
            keys: ["msg_common", "msg_self", "message", "msg", "content"]
        )
        guard let text else { return nil }
        return LiveMessagePayload(text: text, color: 0xFDE68A, mode: 5, fontSize: 24)
    }

    private static func giftMessagePayload(from object: [String: Any]) -> LiveMessagePayload? {
        guard let data = object["data"] as? [String: Any],
              let userName = firstString(in: data, keys: ["uname", "user_name", "username", "name"]),
              let giftName = firstString(in: data, keys: ["giftName", "gift_name", "gift"])
        else { return nil }
        let action = firstString(in: data, keys: ["action"]) ?? "送出"
        let count = max(1, intValue(data["num"]) ?? intValue(data["total_num"]) ?? intValue(data["combo_num"]) ?? 1)
        let countText = count > 1 ? "\(count) 个 " : ""
        return LiveMessagePayload(
            text: "\(userName) \(action) \(countText)\(giftName)",
            color: 0xF9A8D4,
            mode: 1,
            fontSize: 24
        )
    }

    private static func guardBuyPayload(from object: [String: Any]) -> LiveMessagePayload? {
        guard let data = object["data"] as? [String: Any],
              let userName = firstString(in: data, keys: ["username", "uname", "user_name", "name"])
        else { return nil }
        let guardName: String
        switch intValue(data["guard_level"]) {
        case 1:
            guardName = "总督"
        case 2:
            guardName = "提督"
        case 3:
            guardName = "舰长"
        default:
            guardName = "大航海"
        }
        return LiveMessagePayload(text: "\(userName) 开通了\(guardName)", color: 0xFCA5A5, mode: 5, fontSize: 24)
    }

    private static func textMessagePayload(
        from object: [String: Any],
        keys: [String],
        color: UInt32
    ) -> LiveMessagePayload? {
        guard let data = object["data"] as? [String: Any] else { return nil }
        guard let text = firstString(in: data, keys: keys)
            ?? firstString(in: data["data"] as? [String: Any], keys: keys)
        else { return nil }
        return LiveMessagePayload(text: text, color: color, mode: 1, fontSize: 24)
    }

    private static func color(from info: [Any]) -> UInt32 {
        guard let metadata = info.first as? [Any],
              metadata.count > 3
        else { return 0xFF_FF_FF }
        if let color = metadata[3] as? UInt32 {
            return color
        }
        if let color = metadata[3] as? Int, color > 0 {
            return UInt32(color)
        }
        return 0xFF_FF_FF
    }

    private static func firstString(in dictionary: [String: Any]?, keys: [String]) -> String? {
        guard let dictionary else { return nil }
        for key in keys {
            guard let value = stringValue(dictionary[key]),
                  let normalizedValue = normalizedMessageText(value)
            else { continue }
            return normalizedValue
        }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String {
            return value
        }
        return nil
    }

    private static func normalizedMessageText(_ text: String) -> String? {
        let withoutTags = text.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )
        let collapsed = withoutTags.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func firstColor(
        in dictionary: [String: Any]?,
        keys: [String],
        defaultColor: UInt32
    ) -> UInt32 {
        guard let dictionary else { return defaultColor }
        for key in keys {
            if let color = colorValue(dictionary[key]) {
                return color
            }
        }
        return defaultColor
    }

    private static func colorValue(_ value: Any?) -> UInt32? {
        if let value = value as? UInt32 {
            return value
        }
        if let value = value as? Int, value > 0 {
            return UInt32(value)
        }
        if let value = value as? NSNumber, value.intValue > 0 {
            return UInt32(value.intValue)
        }
        guard let value = value as? String else { return nil }
        let sanitized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard !sanitized.isEmpty else { return nil }
        return UInt32(sanitized, radix: 16)
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        if let value = value as? String {
            return Int(value)
        }
        return nil
    }

    private static func nestedUserName(in dictionary: [String: Any]) -> String? {
        if let userName = firstString(in: dictionary, keys: ["uname", "user_name", "username", "name"]) {
            return userName
        }
        if let uinfo = dictionary["uinfo"] as? [String: Any] {
            if let userName = firstString(in: uinfo, keys: ["uname", "user_name", "username", "name"]) {
                return userName
            }
            if let base = uinfo["base"] as? [String: Any] {
                return firstString(in: base, keys: ["uname", "user_name", "username", "name"])
            }
        }
        return nil
    }

    private static func inflate(_ data: Data, algorithm: compression_algorithm) -> Data? {
        guard !data.isEmpty else { return nil }
        let inflated: Data? = data.withUnsafeBytes { sourceBuffer -> Data? in
            guard let sourcePointer = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else { return nil }
            let chunkSize = 64 * 1024
            let destinationPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
            defer { destinationPointer.deallocate() }

            var stream = compression_stream(
                dst_ptr: destinationPointer,
                dst_size: chunkSize,
                src_ptr: sourcePointer,
                src_size: data.count,
                state: nil
            )
            let status = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, algorithm)
            guard status != COMPRESSION_STATUS_ERROR else { return nil }
            defer { compression_stream_destroy(&stream) }

            var output = Data()
            while true {
                let status = compression_stream_process(&stream, 0)
                switch status {
                case COMPRESSION_STATUS_OK:
                    output.append(destinationPointer, count: chunkSize - stream.dst_size)
                    stream.dst_ptr = destinationPointer
                    stream.dst_size = chunkSize
                case COMPRESSION_STATUS_END:
                    output.append(destinationPointer, count: chunkSize - stream.dst_size)
                    return output
                default:
                    return nil
                }
            }
        }
        return inflated
    }
}

nonisolated private extension Data {
    mutating func appendBigEndianUInt16(_ value: UInt16) {
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func appendBigEndianUInt32(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }
}

nonisolated private extension Array where Element == UInt8 {
    func bigEndianUInt16(at index: Int) -> UInt16 {
        (UInt16(self[index]) << 8) | UInt16(self[index + 1])
    }

    func bigEndianUInt32(at index: Int) -> UInt32 {
        (UInt32(self[index]) << 24)
            | (UInt32(self[index + 1]) << 16)
            | (UInt32(self[index + 2]) << 8)
            | UInt32(self[index + 3])
    }
}
