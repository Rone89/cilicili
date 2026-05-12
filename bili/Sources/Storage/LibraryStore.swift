import Foundation
import Combine
import SwiftUI

struct StoredVideo: Identifiable, Codable, Hashable {
    var id: String { bvid }

    let bvid: String
    let aid: Int?
    let title: String
    let pic: String?
    let desc: String?
    let duration: Int?
    let pubdate: Int?
    let ownerMID: Int?
    let ownerName: String?
    let ownerFace: String?
    let viewCount: Int?
    let cid: Int?
    let savedAt: Date
    let playbackTime: TimeInterval?
    let playbackDuration: TimeInterval?

    init(
        video: VideoItem,
        savedAt: Date,
        cid: Int? = nil,
        playbackTime: TimeInterval? = nil,
        playbackDuration: TimeInterval? = nil
    ) {
        self.bvid = video.bvid
        self.aid = video.aid
        self.title = video.title
        self.pic = video.pic
        self.desc = video.desc
        self.duration = video.duration
        self.pubdate = video.pubdate
        self.ownerMID = video.owner?.mid
        self.ownerName = video.owner?.name
        self.ownerFace = video.owner?.face
        self.viewCount = video.stat?.view
        self.cid = cid ?? video.cid
        self.savedAt = savedAt
        self.playbackTime = playbackTime
        self.playbackDuration = playbackDuration
    }

    var videoItem: VideoItem {
        VideoItem(
            bvid: bvid,
            aid: aid,
            title: title,
            pic: pic,
            desc: desc,
            duration: duration,
            pubdate: pubdate,
            owner: owner,
            stat: VideoStat(view: viewCount, reply: nil, like: nil, coin: nil, favorite: nil),
            cid: cid,
            pages: nil,
            dimension: nil
        )
    }

    var resumeTime: TimeInterval? {
        guard let playbackTime, playbackTime >= 10 else { return nil }
        if let playbackDuration, playbackDuration > 0 {
            let remaining = playbackDuration - playbackTime
            guard remaining > 15, playbackTime / playbackDuration < 0.96 else { return nil }
        }
        return playbackTime
    }

    var playbackProgress: Double? {
        guard let playbackTime, playbackTime > 0 else { return nil }
        guard let playbackDuration, playbackDuration > 0 else { return nil }
        return min(max(playbackTime / playbackDuration, 0), 1)
    }

    private var owner: VideoOwner? {
        guard ownerMID != nil || ownerName != nil || ownerFace != nil else { return nil }
        return VideoOwner(mid: ownerMID ?? 0, name: ownerName ?? "", face: ownerFace)
    }
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var appearanceMode: AppAppearanceMode
    @Published private(set) var defaultPlaybackRate: Double
    @Published private(set) var preferredVideoQuality: Int?
    @Published private(set) var blocksGoodsDynamics: Bool
    @Published private(set) var blocksGoodsComments: Bool
    @Published private(set) var sponsorBlockEnabled: Bool
    @Published private(set) var playerPerformanceOverlayEnabled: Bool
    @Published private(set) var incognitoModeEnabled: Bool
    @Published private(set) var guestModeEnabled: Bool
    @Published private(set) var homeRefreshTriggerDistance: Double
    @Published private(set) var homeFeedLayout: HomeFeedLayout

    private let userDefaults: UserDefaults
    private static let appearanceModeKey = "cc.bili.appearance.mode.v1"
    private static let defaultPlaybackRateKey = "cc.bili.playback.defaultPlaybackRate.v1"
    private static let preferredVideoQualityKey = "cc.bili.playback.preferredVideoQuality.v1"
    private static let blocksGoodsDynamicsKey = "cc.bili.content.blocksGoodsDynamics.v1"
    private static let blocksGoodsCommentsKey = "cc.bili.content.blocksGoodsComments.v1"
    private static let sponsorBlockEnabledKey = "cc.bili.playback.sponsorBlockEnabled.v1"
    private static let playerPerformanceOverlayEnabledKey = "cc.bili.playback.performanceOverlayEnabled.v1"
    private static let incognitoModeEnabledKey = "cc.bili.privacy.incognitoModeEnabled.v1"
    private static let guestModeEnabledKey = "cc.bili.privacy.guestModeEnabled.v1"
    private static let homeRefreshTriggerDistanceKey = "cc.bili.home.refreshTriggerDistance.v1"
    private static let homeFeedLayoutKey = "cc.bili.home.feedLayout.v1"
    private static let supportedPlaybackRates = [0.75, 1.0, 1.25, 1.5, 2.0]
    static let defaultPreferredVideoQuality = 112
    static let supportedVideoQualities = [127, 126, 125, 120, 116, 112, 80, 74, 64, 32, 16, 6]
    static let homeRefreshDistanceRange: ClosedRange<Double> = 70...180
    static let defaultHomeRefreshTriggerDistance = 110.0

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.appearanceMode = AppAppearanceMode(
            rawValue: userDefaults.string(forKey: Self.appearanceModeKey) ?? ""
        ) ?? .system
        self.defaultPlaybackRate = Self.normalizedPlaybackRate(userDefaults.object(forKey: Self.defaultPlaybackRateKey) as? Double ?? 1.0)
        if let storedVideoQuality = userDefaults.object(forKey: Self.preferredVideoQualityKey) as? Int {
            self.preferredVideoQuality = storedVideoQuality == 0 ? nil : Self.normalizedVideoQuality(storedVideoQuality)
        } else {
            self.preferredVideoQuality = Self.defaultPreferredVideoQuality
        }
        self.blocksGoodsDynamics = userDefaults.object(forKey: Self.blocksGoodsDynamicsKey) as? Bool ?? true
        self.blocksGoodsComments = userDefaults.object(forKey: Self.blocksGoodsCommentsKey) as? Bool ?? true
        self.sponsorBlockEnabled = userDefaults.object(forKey: Self.sponsorBlockEnabledKey) as? Bool ?? false
        self.playerPerformanceOverlayEnabled = userDefaults.object(forKey: Self.playerPerformanceOverlayEnabledKey) as? Bool ?? false
        self.incognitoModeEnabled = userDefaults.object(forKey: Self.incognitoModeEnabledKey) as? Bool ?? false
        self.guestModeEnabled = userDefaults.object(forKey: Self.guestModeEnabledKey) as? Bool ?? false
        self.homeRefreshTriggerDistance = Self.normalizedHomeRefreshDistance(
            userDefaults.object(forKey: Self.homeRefreshTriggerDistanceKey) as? Double ?? Self.defaultHomeRefreshTriggerDistance
        )
        self.homeFeedLayout = HomeFeedLayout(
            rawValue: userDefaults.string(forKey: Self.homeFeedLayoutKey) ?? ""
        ) ?? .doubleColumn
    }

    func setAppearanceMode(_ mode: AppAppearanceMode) {
        appearanceMode = mode
        userDefaults.set(mode.rawValue, forKey: Self.appearanceModeKey)
    }

    func setDefaultPlaybackRate(_ rate: Double) {
        let normalizedRate = Self.normalizedPlaybackRate(rate)
        defaultPlaybackRate = normalizedRate
        userDefaults.set(normalizedRate, forKey: Self.defaultPlaybackRateKey)
    }

    func setPreferredVideoQuality(_ quality: Int?) {
        let normalizedQuality = Self.normalizedVideoQuality(quality)
        preferredVideoQuality = normalizedQuality
        if let normalizedQuality {
            userDefaults.set(normalizedQuality, forKey: Self.preferredVideoQualityKey)
        } else {
            userDefaults.set(0, forKey: Self.preferredVideoQualityKey)
        }
    }

    func setBlocksGoodsDynamics(_ isEnabled: Bool) {
        blocksGoodsDynamics = isEnabled
        userDefaults.set(isEnabled, forKey: Self.blocksGoodsDynamicsKey)
    }

    func setBlocksGoodsComments(_ isEnabled: Bool) {
        blocksGoodsComments = isEnabled
        userDefaults.set(isEnabled, forKey: Self.blocksGoodsCommentsKey)
    }

    func setSponsorBlockEnabled(_ isEnabled: Bool) {
        sponsorBlockEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: Self.sponsorBlockEnabledKey)
    }

    func setPlayerPerformanceOverlayEnabled(_ isEnabled: Bool) {
        playerPerformanceOverlayEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: Self.playerPerformanceOverlayEnabledKey)
    }

    func setIncognitoModeEnabled(_ isEnabled: Bool) {
        incognitoModeEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: Self.incognitoModeEnabledKey)
    }

    func setGuestModeEnabled(_ isEnabled: Bool) {
        guestModeEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: Self.guestModeEnabledKey)
    }

    func setHomeRefreshTriggerDistance(_ distance: Double) {
        let normalizedDistance = Self.normalizedHomeRefreshDistance(distance)
        homeRefreshTriggerDistance = normalizedDistance
        userDefaults.set(normalizedDistance, forKey: Self.homeRefreshTriggerDistanceKey)
    }

    func setHomeFeedLayout(_ layout: HomeFeedLayout) {
        homeFeedLayout = layout
        userDefaults.set(layout.rawValue, forKey: Self.homeFeedLayoutKey)
    }

    private static func normalizedPlaybackRate(_ rate: Double) -> Double {
        supportedPlaybackRates.contains(rate) ? rate : 1.0
    }

    private static func normalizedVideoQuality(_ quality: Int?) -> Int? {
        guard let quality, supportedVideoQualities.contains(quality) else { return nil }
        return quality
    }

    static func videoQualityTitle(_ quality: Int?) -> String {
        guard let quality else { return "自动（快速开播）" }
        switch quality {
        case 127:
            return "超高清 8K"
        case 126:
            return "杜比视界"
        case 125:
            return "真彩 HDR"
        case 120:
            return "超清 4K"
        case 116:
            return "1080P 高帧率"
        case 112:
            return "1080P 高码率"
        case 80:
            return "1080P"
        case 74:
            return "720P 高帧率"
        case 64:
            return "720P"
        case 32:
            return "480P"
        case 16:
            return "360P"
        case 6:
            return "240P"
        default:
            return "清晰度 \(quality)"
        }
    }

    private static func normalizedHomeRefreshDistance(_ distance: Double) -> Double {
        min(max(distance, homeRefreshDistanceRange.lowerBound), homeRefreshDistanceRange.upperBound)
    }
}

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "跟随系统"
        case .light:
            return "浅色"
        case .dark:
            return "深色"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

enum HomeFeedLayout: String, CaseIterable, Identifiable {
    case doubleColumn
    case singleColumn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .doubleColumn:
            return "双列"
        case .singleColumn:
            return "单列"
        }
    }

    var systemImage: String {
        switch self {
        case .doubleColumn:
            return "square.grid.2x2"
        case .singleColumn:
            return "rectangle.grid.1x2"
        }
    }
}
