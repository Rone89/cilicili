import Combine
import Foundation

typealias DashStream = DASHStream

enum PlayerKernelType: String, CaseIterable, Identifiable, Codable, Sendable {
    case ksPlayer
    case avPlayer

    nonisolated static let storageKey = PlayerRenderingEnginePreference.storageKey
    nonisolated static let defaultValue: PlayerKernelType = .ksPlayer

    nonisolated var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .ksPlayer:
            return "KSPlayer"
        case .avPlayer:
            return "AVPlayer"
        }
    }

    nonisolated var renderingEnginePreference: PlayerRenderingEnginePreference {
        switch self {
        case .ksPlayer:
            return .ksPlayer
        case .avPlayer:
            return .avPlayer
        }
    }

    nonisolated init(preference: PlayerRenderingEnginePreference) {
        switch preference {
        case .ksPlayer:
            self = .ksPlayer
        case .avPlayer:
            self = .avPlayer
        case .automatic:
            self = Self.defaultValue
        }
    }

    nonisolated static func stored(in userDefaults: UserDefaults = .standard) -> PlayerKernelType {
        if let rawValue = userDefaults.string(forKey: storageKey),
           let kernel = PlayerKernelType(rawValue: rawValue) {
            return kernel
        }
        return defaultValue
    }
}

enum VideoCodecPreference: String, CaseIterable, Identifiable, Codable, Sendable {
    case auto
    case forceAV1
    case forceHEVC
    case forceH264

    nonisolated static let storageKey = "cc.bili.playback.videoCodecPreference.v1"
    nonisolated static let defaultValue: VideoCodecPreference = .auto

    nonisolated var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .auto:
            return "自动"
        case .forceAV1:
            return "优先 AV1"
        case .forceHEVC:
            return "优先 HEVC"
        case .forceH264:
            return "优先 H.264"
        }
    }

    nonisolated var detail: String {
        switch self {
        case .auto:
            return "AV1 > HEVC > H.264"
        case .forceAV1:
            return "请求 AV1，不可用时降级到 HEVC / H.264。"
        case .forceHEVC:
            return "请求 HEVC，不可用时优先降级到 H.264。"
        case .forceH264:
            return "请求 H.264，不可用时选择可用视频轨避免黑屏。"
        }
    }

    nonisolated var codecOrder: [VideoCodecFamily] {
        switch self {
        case .auto, .forceAV1:
            return [.av1, .hevc, .h264, .unknown]
        case .forceHEVC:
            return [.hevc, .h264, .av1, .unknown]
        case .forceH264:
            return [.h264, .hevc, .av1, .unknown]
        }
    }

    nonisolated static func stored(in userDefaults: UserDefaults = .standard) -> VideoCodecPreference {
        if let rawValue = userDefaults.string(forKey: storageKey),
           let preference = VideoCodecPreference(rawValue: rawValue) {
            return preference
        }
        return defaultValue
    }
}

enum VideoCodecFamily: Int, CaseIterable, Sendable {
    case unknown = 0
    case h264 = 1
    case hevc = 2
    case av1 = 3

    nonisolated var title: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .h264:
            return "H.264"
        case .hevc:
            return "HEVC"
        case .av1:
            return "AV1"
        }
    }
}

nonisolated enum PlayerKernelPlaybackSupport {
    static func shouldPreferAV1Selection(on kernel: PlayerKernelType) -> Bool {
        switch kernel {
        case .avPlayer:
            return PlaybackCodecPolicy.canDecodeAV1
        case .ksPlayer:
            return PlaybackCodecPolicy.canUseKSPlayerDirectAV1VideoToolbox
        }
    }

    static func preferredDirectKernel(
        for stream: DashStream,
        requestedKernel: PlayerKernelType
    ) -> PlayerKernelType {
        switch requestedKernel {
        case .avPlayer:
            return .avPlayer
        case .ksPlayer:
            guard stream.isAV1VideoCodec else { return .ksPlayer }
            return PlaybackCodecPolicy.canUseKSPlayerDirectAV1VideoToolbox ? .ksPlayer : .avPlayer
        }
    }

    static func prefersHardwareDecodedPlayback(
        for stream: DashStream,
        on kernel: PlayerKernelType
    ) -> Bool {
        guard stream.isHardwareDecodingCompatibleVideo else { return false }

        switch preferredDirectKernel(for: stream, requestedKernel: kernel) {
        case .avPlayer:
            return true
        case .ksPlayer:
            if stream.isAV1VideoCodec {
                return PlaybackCodecPolicy.canUseKSPlayerDirectAV1VideoToolbox
            }
            return true
        }
    }

    static func shouldRejectDirectPlayback(
        of stream: DashStream,
        on kernel: PlayerKernelType
    ) -> Bool {
        switch kernel {
        case .avPlayer:
            return false
        case .ksPlayer:
            return stream.isAV1VideoCodec && !PlaybackCodecPolicy.canUseKSPlayerDirectAV1VideoToolbox
        }
    }

    static func shouldRequireHardwareDecode(
        for stream: DashStream,
        on kernel: PlayerKernelType
    ) -> Bool {
        switch kernel {
        case .avPlayer:
            return false
        case .ksPlayer:
            return stream.isAV1VideoCodec
        }
    }
}

nonisolated enum DashStreamDispatcher {
    static func selectBestStream(
        from streams: [DashStream],
        preference: VideoCodecPreference,
        kernel: PlayerKernelType = PlayerKernelType.stored()
    ) -> DashStream? {
        let playableStreams = streams.enumerated()
            .filter { _, stream in stream.url != nil }
        guard !playableStreams.isEmpty else { return nil }

        let codecOrder = effectiveCodecOrder(for: preference, kernel: kernel)
        return playableStreams
            .min { lhs, rhs in
                rankingTuple(
                    for: lhs.element,
                    originalIndex: lhs.offset,
                    codecOrder: codecOrder,
                    kernel: kernel
                ) < rankingTuple(
                    for: rhs.element,
                    originalIndex: rhs.offset,
                    codecOrder: codecOrder,
                    kernel: kernel
                )
            }?
            .element
    }

    private static func effectiveCodecOrder(
        for preference: VideoCodecPreference,
        kernel: PlayerKernelType
    ) -> [VideoCodecFamily] {
        guard PlayerKernelPlaybackSupport.shouldPreferAV1Selection(on: kernel) else {
            return demotingAV1(in: preference.codecOrder)
        }
        return preference.codecOrder
    }

    private static func demotingAV1(in order: [VideoCodecFamily]) -> [VideoCodecFamily] {
        guard let av1Index = order.firstIndex(of: .av1) else { return order }
        var adjusted = order
        adjusted.remove(at: av1Index)
        if let unknownIndex = adjusted.firstIndex(of: .unknown) {
            adjusted.insert(.av1, at: unknownIndex)
        } else {
            adjusted.append(.av1)
        }
        return adjusted
    }

    private static func rankingTuple(
        for stream: DashStream,
        originalIndex: Int,
        codecOrder: [VideoCodecFamily],
        kernel: PlayerKernelType
    ) -> StreamRankingTuple {
        let family = stream.videoCodecFamily
        let codecIndex = codecOrder.firstIndex(of: family) ?? codecOrder.count
        return StreamRankingTuple(
            codecIndex: codecIndex,
            hardwarePenalty: PlayerKernelPlaybackSupport.prefersHardwareDecodedPlayback(
                for: stream,
                on: kernel
            ) ? 0 : 1,
            negativeBandwidth: -(stream.bandwidth ?? 0),
            originalIndex: originalIndex
        )
    }
}

nonisolated private struct StreamRankingTuple: Comparable {
    let codecIndex: Int
    let hardwarePenalty: Int
    let negativeBandwidth: Int
    let originalIndex: Int

    static func < (lhs: StreamRankingTuple, rhs: StreamRankingTuple) -> Bool {
        if lhs.codecIndex != rhs.codecIndex {
            return lhs.codecIndex < rhs.codecIndex
        }
        if lhs.hardwarePenalty != rhs.hardwarePenalty {
            return lhs.hardwarePenalty < rhs.hardwarePenalty
        }
        if lhs.negativeBandwidth != rhs.negativeBandwidth {
            return lhs.negativeBandwidth < rhs.negativeBandwidth
        }
        return lhs.originalIndex < rhs.originalIndex
    }
}

extension DASHStream {
    nonisolated init(
        id: Int?,
        url: URL,
        backupURLs: [URL] = [],
        bandwidth: Int? = nil,
        codecs: String?,
        codecid: Int? = nil,
        width: Int? = nil,
        height: Int? = nil,
        frameRate: String? = nil,
        mimeType: String? = nil,
        segmentBase: DASHSegmentBase? = nil
    ) {
        self.id = id
        self.baseURL = url.absoluteString
        self.backupURL = backupURLs.map(\.absoluteString)
        self.bandwidth = bandwidth
        self.codecs = codecs
        self.codecid = codecid
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.mimeType = mimeType
        self.segmentBase = segmentBase
    }

    nonisolated var url: URL? {
        playURL
    }

    nonisolated var videoCodecFamily: VideoCodecFamily {
        if isAV1VideoCodec {
            return .av1
        }
        if isHEVCVideoCodec {
            return .hevc
        }
        if isAVCVideoCodec {
            return .h264
        }
        return .unknown
    }
}

@MainActor
final class PlayerSettings: ObservableObject {
    static let shared = PlayerSettings()

    @Published private(set) var preferredKernel: PlayerKernelType
    @Published private(set) var videoCodecPreference: VideoCodecPreference

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.preferredKernel = PlayerKernelType.stored(in: userDefaults)
        self.videoCodecPreference = VideoCodecPreference.stored(in: userDefaults)
    }

    func setPreferredKernel(_ kernel: PlayerKernelType) {
        guard preferredKernel != kernel else { return }
        preferredKernel = kernel
        userDefaults.set(kernel.rawValue, forKey: PlayerKernelType.storageKey)
    }

    func setVideoCodecPreference(_ preference: VideoCodecPreference) {
        guard videoCodecPreference != preference else { return }
        videoCodecPreference = preference
        userDefaults.set(preference.rawValue, forKey: VideoCodecPreference.storageKey)
    }

    func reload() {
        preferredKernel = PlayerKernelType.stored(in: userDefaults)
        videoCodecPreference = VideoCodecPreference.stored(in: userDefaults)
    }
}
