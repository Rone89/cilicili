import Combine
import Foundation

typealias DashStream = DASHStream

enum PlayerKernelType: String, CaseIterable, Identifiable, Codable, Sendable {
    case ksPlayer
    case avPlayer

    nonisolated static let storageKey = PlayerRenderingEnginePreference.storageKey
    nonisolated static let defaultValue: PlayerKernelType = .avPlayer

    nonisolated var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .ksPlayer:
            return "KSPlayer"
        case .avPlayer:
            return "AVPlayer"
        }
    }

    nonisolated var normalizedForFormalPlayback: PlayerKernelType {
        switch self {
        case .ksPlayer, .avPlayer:
            return .avPlayer
        }
    }

    nonisolated var renderingEnginePreference: PlayerRenderingEnginePreference {
        .avPlayer
    }

    nonisolated init(preference _: PlayerRenderingEnginePreference) {
        self = .avPlayer
    }

    nonisolated static func stored(in userDefaults: UserDefaults = .standard) -> PlayerKernelType {
        if let rawValue = userDefaults.string(forKey: storageKey),
           let kernel = PlayerKernelType(rawValue: rawValue) {
            return kernel.normalizedForFormalPlayback
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
    nonisolated static let allCases: [VideoCodecPreference] = [.auto, .forceHEVC, .forceH264]

    nonisolated var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .auto, .forceAV1:
            return "自动（HEVC 优先）"
        case .forceHEVC:
            return "仅 HEVC"
        case .forceH264:
            return "仅 H.264"
        }
    }

    nonisolated var detail: String {
        switch self {
        case .auto, .forceAV1:
            return "按 HEVC、H.264 的顺序选择可硬解视频流。"
        case .forceHEVC:
            return "只请求和选择 HEVC；不可用时提示播放失败。"
        case .forceH264:
            return "只请求和选择 H.264；不可用时提示播放失败。"
        }
    }

    nonisolated var codecOrder: [VideoCodecFamily] {
        switch self {
        case .auto, .forceAV1:
            return [.hevc, .h264, .unknown]
        case .forceHEVC:
            return [.hevc]
        case .forceH264:
            return [.h264]
        }
    }

    nonisolated var forcedCodecFamily: VideoCodecFamily? {
        switch self {
        case .auto, .forceAV1:
            return nil
        case .forceHEVC:
            return .hevc
        case .forceH264:
            return .h264
        }
    }

    nonisolated var forcedUnavailableMessage: String? {
        switch self {
        case .auto, .forceAV1:
            return nil
        case .forceHEVC:
            return "当前视频没有可硬解 HEVC 播放地址，可在设置中切换为自动或 H.264。"
        case .forceH264:
            return "当前视频没有可硬解 H.264 播放地址，可在设置中切换为自动或 HEVC。"
        }
    }

    nonisolated var normalizedForPlayback: VideoCodecPreference {
        self == .forceAV1 ? .auto : self
    }

    nonisolated static func stored(in userDefaults: UserDefaults = .standard) -> VideoCodecPreference {
        if let rawValue = userDefaults.string(forKey: storageKey),
           let preference = VideoCodecPreference(rawValue: rawValue) {
            return preference.normalizedForPlayback
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
    static func preferredDirectKernel(
        for _: DashStream,
        requestedKernel _: PlayerKernelType
    ) -> PlayerKernelType {
        .avPlayer
    }

    static func prefersHardwareDecodedPlayback(
        for stream: DashStream,
        on kernel: PlayerKernelType
    ) -> Bool {
        guard stream.isHardwareDecodingCompatibleVideo else { return false }

        switch preferredDirectKernel(for: stream, requestedKernel: kernel) {
        case .avPlayer, .ksPlayer:
            return true
        }
    }

    static func shouldRejectDirectPlayback(
        of stream: DashStream,
        on kernel: PlayerKernelType
    ) -> Bool {
        switch kernel {
        case .avPlayer, .ksPlayer:
            return false
        }
    }

    static func shouldRequireHardwareDecode(
        for stream: DashStream,
        on kernel: PlayerKernelType
    ) -> Bool {
        switch kernel {
        case .avPlayer, .ksPlayer:
            return false
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
            .filter { _, stream in
                guard stream.url != nil else { return false }
                guard stream.videoCodecFamily != .av1 else { return false }
                if let forcedCodecFamily = preference.forcedCodecFamily,
                   stream.videoCodecFamily != forcedCodecFamily {
                    return false
                }
                return true
            }
        guard !playableStreams.isEmpty else { return nil }

        let streams = playableStreams.map(\.element)
        let codecOrder = effectiveCodecOrder(
            for: preference,
            kernel: kernel,
            streams: streams
        )
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
        kernel _: PlayerKernelType,
        streams _: [DashStream] = []
    ) -> [VideoCodecFamily] {
        return preference.codecOrder
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
        let normalizedKernel = kernel.normalizedForFormalPlayback
        guard preferredKernel != normalizedKernel
            || userDefaults.string(forKey: PlayerKernelType.storageKey) != normalizedKernel.rawValue
        else { return }
        preferredKernel = normalizedKernel
        userDefaults.set(normalizedKernel.rawValue, forKey: PlayerKernelType.storageKey)
    }

    func setVideoCodecPreference(_ preference: VideoCodecPreference) {
        let normalizedPreference = preference.normalizedForPlayback
        guard videoCodecPreference != normalizedPreference
            || userDefaults.string(forKey: VideoCodecPreference.storageKey) != normalizedPreference.rawValue
        else { return }
        videoCodecPreference = normalizedPreference
        userDefaults.set(normalizedPreference.rawValue, forKey: VideoCodecPreference.storageKey)
    }

    func reload() {
        preferredKernel = PlayerKernelType.stored(in: userDefaults)
        videoCodecPreference = VideoCodecPreference.stored(in: userDefaults)
    }
}
