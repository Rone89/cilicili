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
            dimension: nil,
            historyResumeTime: resumeTime,
            historyCID: cid
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
    @Published private(set) var playbackAutoOptimizationMode: PlaybackAutoOptimizationMode
    @Published private(set) var playbackCDNPreference: PlaybackCDNPreference
    @Published private(set) var playbackNetworkAddressFamilyPreference: PlaybackNetworkAddressFamilyPreference
    @Published private(set) var playbackCDNProbeSnapshot: PlaybackCDNProbeSnapshot?
    @Published private(set) var blocksAdDynamics: Bool
    @Published private(set) var blocksGoodsDynamics: Bool
    @Published private(set) var blocksGoodsComments: Bool
    @Published private(set) var blockedDynamicKeywords: [String]
    @Published private(set) var danmakuEnabled: Bool
    @Published private(set) var danmakuSettings: DanmakuSettings
    @Published private(set) var sponsorBlockEnabled: Bool
    @Published private(set) var playerPerformanceOverlayEnabled: Bool
    @Published private(set) var showsVideoDetailNetworkDiagnosticsButton: Bool
    @Published private(set) var showsVideoDetailPinnedProgressBar: Bool
    @Published private(set) var incognitoModeEnabled: Bool
    @Published private(set) var guestModeEnabled: Bool
    @Published private(set) var minimizesTabBarOnScroll: Bool
    @Published private(set) var homeRefreshTriggerDistance: Double
    @Published private(set) var homeFeedLayout: HomeFeedLayout

    private let userDefaults: UserDefaults
    private static let appearanceModeKey = "cc.bili.appearance.mode.v1"
    private static let defaultPlaybackRateKey = "cc.bili.playback.defaultPlaybackRate.v1"
    private static let preferredVideoQualityKey = "cc.bili.playback.preferredVideoQuality.v1"
    private static let playbackAutoOptimizationModeKey = "cc.bili.playback.autoOptimizationMode.v1"
    private static let playbackCDNPreferenceKey = "cc.bili.playback.cdnPreference.v1"
    private static let playbackNetworkAddressFamilyPreferenceKey = "cc.bili.playback.networkAddressFamilyPreference.v1"
    private static let playbackCDNProbeSnapshotKey = "cc.bili.playback.cdnProbeSnapshot.v1"
    private static let playbackCDNProbeSnapshotsByContextKey = "cc.bili.playback.cdnProbeSnapshotsByContext.v1"
    private static let blocksAdDynamicsKey = "cc.bili.content.blocksAdDynamics.v1"
    private static let blocksGoodsDynamicsKey = "cc.bili.content.blocksGoodsDynamics.v1"
    private static let blocksGoodsCommentsKey = "cc.bili.content.blocksGoodsComments.v1"
    private static let blockedDynamicKeywordsKey = "cc.bili.content.blockedDynamicKeywords.v1"
    private static let danmakuEnabledKey = "cc.bili.playback.danmakuEnabled.v1"
    private static let danmakuSettingsKey = "cc.bili.playback.danmakuSettings.v1"
    private static let sponsorBlockEnabledKey = "cc.bili.playback.sponsorBlockEnabled.v1"
    private static let playerPerformanceOverlayEnabledKey = "cc.bili.playback.performanceOverlayEnabled.v1"
    private static let showsVideoDetailNetworkDiagnosticsButtonKey = "cc.bili.videoDetail.showsNetworkDiagnosticsButton.v1"
    private static let showsVideoDetailPinnedProgressBarKey = "cc.bili.videoDetail.showsPinnedProgressBar.v1"
    private static let incognitoModeEnabledKey = "cc.bili.privacy.incognitoModeEnabled.v1"
    private static let guestModeEnabledKey = "cc.bili.privacy.guestModeEnabled.v1"
    private static let minimizesTabBarOnScrollKey = "cc.bili.display.minimizesTabBarOnScroll.v1"
    private static let homeRefreshTriggerDistanceKey = "cc.bili.home.refreshTriggerDistance.v1"
    private static let homeFeedLayoutKey = "cc.bili.home.feedLayout.v1"
    private static let supportedPlaybackRates = [0.75, 1.0, 1.25, 1.5, 2.0]
    static let defaultPreferredVideoQuality = 112
    static let supportedVideoQualities = [129, 127, 126, 125, 120, 116, 112, 80, 74, 64, 32, 16, 6]
    static let homeRefreshDistanceRange: ClosedRange<Double> = 70...180
    static let defaultHomeRefreshTriggerDistance = 110.0
    private static let temporaryPlaybackCDNAvoidanceDuration: TimeInterval = 10 * 60
    private var playbackCDNProbeSnapshotsByContext: [String: PlaybackCDNProbeSnapshot] = [:]
    private var temporarilyAvoidedPlaybackCDNPreferences: [PlaybackCDNPreference: Date] = [:]

    var effectivePlaybackCDNPreference: PlaybackCDNPreference {
        effectivePlaybackCDNPreference(for: playbackCDNPreference)
    }

    var isPlaybackAutoOptimizationEnabled: Bool {
        playbackAutoOptimizationMode.isEnabled
    }

    var automaticPlaybackCDNRecommendation: PlaybackCDNPreference? {
        playbackCDNRecommendation(allowExpired: false)
    }

    var activePlaybackCDNAvoidanceDescription: String? {
        let now = Date()
        let activeAvoidances = temporarilyAvoidedPlaybackCDNPreferences
            .filter { $0.value > now }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value < rhs.value
                }
                return lhs.key.title < rhs.key.title
            }
        guard !activeAvoidances.isEmpty else { return nil }
        return activeAvoidances
            .map { preference, expiresAt in
                "\(preference.title) 至 \(expiresAt.formatted(date: .omitted, time: .shortened))"
            }
            .joined(separator: "、")
    }

    var playbackCDNProbeSnapshotForCurrentContext: PlaybackCDNProbeSnapshot? {
        playbackCDNProbeSnapshotsByContext[currentPlaybackCDNProbeContextKey]
    }

    var needsPlaybackCDNProbeRefresh: Bool {
        guard playbackCDNPreference == .automatic else { return false }
        guard let snapshot = playbackCDNProbeSnapshotForCurrentContext else { return true }
        if snapshot.isExpired() { return true }
        if snapshot.recommendedPreference == nil,
           snapshot.isExpired(freshnessInterval: 15 * 60) {
            return true
        }
        return false
    }

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
        self.playbackAutoOptimizationMode = PlaybackAutoOptimizationMode(
            rawValue: userDefaults.string(forKey: Self.playbackAutoOptimizationModeKey) ?? ""
        ) ?? .automatic
        self.playbackCDNPreference = PlaybackCDNPreference(
            rawValue: userDefaults.string(forKey: Self.playbackCDNPreferenceKey) ?? ""
        ) ?? .automatic
        let storedAddressFamilyPreference = PlaybackNetworkAddressFamilyPreference(
            rawValue: userDefaults.string(forKey: Self.playbackNetworkAddressFamilyPreferenceKey) ?? ""
        ) ?? .automatic
        self.playbackNetworkAddressFamilyPreference = storedAddressFamilyPreference
        let currentProbeContextKey = Self.playbackCDNProbeContextKey(
            networkClass: PlaybackEnvironment.current.networkClass,
            addressFamilyPreference: storedAddressFamilyPreference
        )
        if let contextData = userDefaults.data(forKey: Self.playbackCDNProbeSnapshotsByContextKey),
           let snapshots = try? JSONDecoder().decode([String: PlaybackCDNProbeSnapshot].self, from: contextData) {
            self.playbackCDNProbeSnapshotsByContext = snapshots
            self.playbackCDNProbeSnapshot = snapshots[currentProbeContextKey]
        } else if let probeSnapshotData = userDefaults.data(forKey: Self.playbackCDNProbeSnapshotKey),
                  let probeSnapshot = try? JSONDecoder().decode(PlaybackCDNProbeSnapshot.self, from: probeSnapshotData) {
            self.playbackCDNProbeSnapshotsByContext = [currentProbeContextKey: probeSnapshot]
            self.playbackCDNProbeSnapshot = probeSnapshot
        } else {
            self.playbackCDNProbeSnapshot = nil
        }
        self.blocksAdDynamics = userDefaults.object(forKey: Self.blocksAdDynamicsKey) as? Bool ?? true
        self.blocksGoodsDynamics = userDefaults.object(forKey: Self.blocksGoodsDynamicsKey) as? Bool ?? true
        self.blocksGoodsComments = userDefaults.object(forKey: Self.blocksGoodsCommentsKey) as? Bool ?? true
        self.blockedDynamicKeywords = Self.normalizedBlockedDynamicKeywords(
            userDefaults.stringArray(forKey: Self.blockedDynamicKeywordsKey) ?? []
        )
        self.danmakuEnabled = userDefaults.object(forKey: Self.danmakuEnabledKey) as? Bool ?? true
        if let settingsData = userDefaults.data(forKey: Self.danmakuSettingsKey),
           let settings = try? JSONDecoder().decode(DanmakuSettings.self, from: settingsData) {
            self.danmakuSettings = settings.normalized
        } else {
            self.danmakuSettings = .default
        }
        self.sponsorBlockEnabled = userDefaults.object(forKey: Self.sponsorBlockEnabledKey) as? Bool ?? false
        self.playerPerformanceOverlayEnabled = userDefaults.object(forKey: Self.playerPerformanceOverlayEnabledKey) as? Bool ?? false
        self.showsVideoDetailNetworkDiagnosticsButton = userDefaults.object(forKey: Self.showsVideoDetailNetworkDiagnosticsButtonKey) as? Bool ?? true
        self.showsVideoDetailPinnedProgressBar = userDefaults.object(forKey: Self.showsVideoDetailPinnedProgressBarKey) as? Bool ?? true
        self.incognitoModeEnabled = userDefaults.object(forKey: Self.incognitoModeEnabledKey) as? Bool ?? false
        self.guestModeEnabled = userDefaults.object(forKey: Self.guestModeEnabledKey) as? Bool ?? false
        self.minimizesTabBarOnScroll = userDefaults.object(forKey: Self.minimizesTabBarOnScrollKey) as? Bool ?? true
        self.homeRefreshTriggerDistance = Self.normalizedHomeRefreshDistance(
            userDefaults.object(forKey: Self.homeRefreshTriggerDistanceKey) as? Double ?? Self.defaultHomeRefreshTriggerDistance
        )
        self.homeFeedLayout = HomeFeedLayout(
            rawValue: userDefaults.string(forKey: Self.homeFeedLayoutKey) ?? ""
        ) ?? .singleColumn
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

    func setPlaybackAutoOptimizationMode(_ mode: PlaybackAutoOptimizationMode) {
        playbackAutoOptimizationMode = mode
        userDefaults.set(mode.rawValue, forKey: Self.playbackAutoOptimizationModeKey)
    }

    func setPlaybackCDNPreference(_ preference: PlaybackCDNPreference) {
        playbackCDNPreference = preference
        clearTemporaryPlaybackCDNAvoidance()
        userDefaults.set(preference.rawValue, forKey: Self.playbackCDNPreferenceKey)
    }

    func setPlaybackNetworkAddressFamilyPreference(_ preference: PlaybackNetworkAddressFamilyPreference) {
        playbackNetworkAddressFamilyPreference = preference
        userDefaults.set(preference.rawValue, forKey: Self.playbackNetworkAddressFamilyPreferenceKey)
        clearTemporaryPlaybackCDNAvoidance()
        clearPlaybackCDNProbeSnapshots()
    }

    func effectivePlaybackCDNPreference(for preference: PlaybackCDNPreference) -> PlaybackCDNPreference {
        guard preference == .automatic else { return preference }
        return playbackCDNRecommendation(allowExpired: false) ?? .automatic
    }

    @discardableResult
    func temporarilyAvoidAutomaticPlaybackCDN(
        _ preference: PlaybackCDNPreference,
        duration: TimeInterval = 10 * 60
    ) -> Bool {
        guard playbackCDNPreference == .automatic,
              preference.isManualHost
        else { return false }
        let expiration = Date().addingTimeInterval(max(30, duration))
        temporarilyAvoidedPlaybackCDNPreferences[preference] = expiration
        objectWillChange.send()
        return true
    }

    func setPlaybackCDNProbeSnapshot(_ snapshot: PlaybackCDNProbeSnapshot?) {
        playbackCDNProbeSnapshot = snapshot
        let contextKey = currentPlaybackCDNProbeContextKey
        if let snapshot {
            playbackCDNProbeSnapshotsByContext[contextKey] = snapshot
            if let data = try? JSONEncoder().encode(snapshot) {
                userDefaults.set(data, forKey: Self.playbackCDNProbeSnapshotKey)
            }
        } else {
            playbackCDNProbeSnapshotsByContext[contextKey] = nil
            userDefaults.removeObject(forKey: Self.playbackCDNProbeSnapshotKey)
        }
        persistPlaybackCDNProbeSnapshotsByContext()
    }

    func syncPlaybackCDNProbeSnapshotForCurrentContext() {
        let currentSnapshot = playbackCDNProbeSnapshotsByContext[currentPlaybackCDNProbeContextKey]
        guard playbackCDNProbeSnapshot != currentSnapshot else { return }
        playbackCDNProbeSnapshot = currentSnapshot
    }

    private func playbackCDNRecommendation(allowExpired: Bool) -> PlaybackCDNPreference? {
        guard let snapshot = playbackCDNProbeSnapshotForCurrentContext,
              allowExpired || !snapshot.isExpired()
        else { return nil }
        var seenPreferences = Set<PlaybackCDNPreference>()
        var candidates = [PlaybackCDNPreference]()
        func appendCandidate(_ preference: PlaybackCDNPreference?) {
            guard let preference,
                  snapshot.result(for: preference)?.didSucceed == true,
                  seenPreferences.insert(preference).inserted
            else { return }
            candidates.append(preference)
        }
        appendCandidate(snapshot.recommendedPreference)
        snapshot.successfulResults.forEach { appendCandidate($0.preference) }
        return candidates.first { !isPlaybackCDNTemporarilyAvoided($0) }
    }

    private func isPlaybackCDNTemporarilyAvoided(_ preference: PlaybackCDNPreference, now: Date = Date()) -> Bool {
        guard let expiresAt = temporarilyAvoidedPlaybackCDNPreferences[preference] else { return false }
        return expiresAt > now
    }

    private func clearTemporaryPlaybackCDNAvoidance() {
        guard !temporarilyAvoidedPlaybackCDNPreferences.isEmpty else { return }
        temporarilyAvoidedPlaybackCDNPreferences.removeAll()
        objectWillChange.send()
    }

    private var currentPlaybackCDNProbeContextKey: String {
        Self.playbackCDNProbeContextKey(
            networkClass: PlaybackEnvironment.current.networkClass,
            addressFamilyPreference: playbackNetworkAddressFamilyPreference
        )
    }

    private func clearPlaybackCDNProbeSnapshots() {
        playbackCDNProbeSnapshot = nil
        playbackCDNProbeSnapshotsByContext.removeAll()
        userDefaults.removeObject(forKey: Self.playbackCDNProbeSnapshotKey)
        userDefaults.removeObject(forKey: Self.playbackCDNProbeSnapshotsByContextKey)
    }

    private func persistPlaybackCDNProbeSnapshotsByContext() {
        guard !playbackCDNProbeSnapshotsByContext.isEmpty,
              let data = try? JSONEncoder().encode(playbackCDNProbeSnapshotsByContext)
        else {
            userDefaults.removeObject(forKey: Self.playbackCDNProbeSnapshotsByContextKey)
            return
        }
        userDefaults.set(data, forKey: Self.playbackCDNProbeSnapshotsByContextKey)
    }

    private static func playbackCDNProbeContextKey(
        networkClass: PlaybackEnvironment.NetworkClass,
        addressFamilyPreference: PlaybackNetworkAddressFamilyPreference
    ) -> String {
        "\(networkClass.cacheKey)|\(addressFamilyPreference.rawValue)"
    }

    func setBlocksAdDynamics(_ isEnabled: Bool) {
        blocksAdDynamics = isEnabled
        userDefaults.set(isEnabled, forKey: Self.blocksAdDynamicsKey)
    }

    func setBlocksGoodsDynamics(_ isEnabled: Bool) {
        blocksGoodsDynamics = isEnabled
        userDefaults.set(isEnabled, forKey: Self.blocksGoodsDynamicsKey)
    }

    func setBlocksGoodsComments(_ isEnabled: Bool) {
        blocksGoodsComments = isEnabled
        userDefaults.set(isEnabled, forKey: Self.blocksGoodsCommentsKey)
    }

    func setBlockedDynamicKeywords(_ keywords: [String]) {
        blockedDynamicKeywords = Self.normalizedBlockedDynamicKeywords(keywords)
        persistBlockedDynamicKeywords()
    }

    func addBlockedDynamicKeyword(_ keyword: String) {
        let normalizedKeyword = Self.normalizedBlockedDynamicKeyword(keyword)
        guard !normalizedKeyword.isEmpty else { return }
        guard !blockedDynamicKeywords.contains(where: { Self.blockedDynamicKeywordKey($0) == Self.blockedDynamicKeywordKey(normalizedKeyword) }) else {
            return
        }
        blockedDynamicKeywords.append(normalizedKeyword)
        persistBlockedDynamicKeywords()
    }

    func removeBlockedDynamicKeyword(_ keyword: String) {
        let keywordKey = Self.blockedDynamicKeywordKey(keyword)
        let updated = blockedDynamicKeywords.filter { Self.blockedDynamicKeywordKey($0) != keywordKey }
        guard updated.count != blockedDynamicKeywords.count else { return }
        blockedDynamicKeywords = updated
        persistBlockedDynamicKeywords()
    }

    func removeBlockedDynamicKeywords(at offsets: IndexSet) {
        guard !offsets.isEmpty else { return }
        blockedDynamicKeywords.remove(atOffsets: offsets)
        persistBlockedDynamicKeywords()
    }

    func clearBlockedDynamicKeywords() {
        guard !blockedDynamicKeywords.isEmpty else { return }
        blockedDynamicKeywords = []
        persistBlockedDynamicKeywords()
    }

    func setDanmakuEnabled(_ isEnabled: Bool) {
        danmakuEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: Self.danmakuEnabledKey)
    }

    func setDanmakuSettings(_ settings: DanmakuSettings) {
        let normalizedSettings = settings.normalized
        danmakuSettings = normalizedSettings
        guard let data = try? JSONEncoder().encode(normalizedSettings) else { return }
        userDefaults.set(data, forKey: Self.danmakuSettingsKey)
    }

    func setSponsorBlockEnabled(_ isEnabled: Bool) {
        sponsorBlockEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: Self.sponsorBlockEnabledKey)
    }

    func setPlayerPerformanceOverlayEnabled(_ isEnabled: Bool) {
        playerPerformanceOverlayEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: Self.playerPerformanceOverlayEnabledKey)
    }

    func setShowsVideoDetailNetworkDiagnosticsButton(_ isEnabled: Bool) {
        showsVideoDetailNetworkDiagnosticsButton = isEnabled
        userDefaults.set(isEnabled, forKey: Self.showsVideoDetailNetworkDiagnosticsButtonKey)
    }

    func setShowsVideoDetailPinnedProgressBar(_ isEnabled: Bool) {
        showsVideoDetailPinnedProgressBar = isEnabled
        userDefaults.set(isEnabled, forKey: Self.showsVideoDetailPinnedProgressBarKey)
    }

    func setIncognitoModeEnabled(_ isEnabled: Bool) {
        incognitoModeEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: Self.incognitoModeEnabledKey)
    }

    func setGuestModeEnabled(_ isEnabled: Bool) {
        guestModeEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: Self.guestModeEnabledKey)
    }

    func setMinimizesTabBarOnScroll(_ isEnabled: Bool) {
        minimizesTabBarOnScroll = isEnabled
        userDefaults.set(isEnabled, forKey: Self.minimizesTabBarOnScrollKey)
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
        case 129:
            return "HDR Vivid"
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

    private func persistBlockedDynamicKeywords() {
        guard !blockedDynamicKeywords.isEmpty else {
            userDefaults.removeObject(forKey: Self.blockedDynamicKeywordsKey)
            return
        }
        userDefaults.set(blockedDynamicKeywords, forKey: Self.blockedDynamicKeywordsKey)
    }

    private static func normalizedBlockedDynamicKeywords(_ keywords: [String]) -> [String] {
        var seen = Set<String>()
        return keywords.compactMap { keyword in
            let normalized = normalizedBlockedDynamicKeyword(keyword)
            guard !normalized.isEmpty else { return nil }
            let key = blockedDynamicKeywordKey(normalized)
            guard seen.insert(key).inserted else { return nil }
            return normalized
        }
    }

    private static func normalizedBlockedDynamicKeyword(_ keyword: String) -> String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func blockedDynamicKeywordKey(_ keyword: String) -> String {
        normalizedBlockedDynamicKeyword(keyword).folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
    }
}

private extension PlaybackEnvironment.NetworkClass {
    var cacheKey: String {
        switch self {
        case .wifi:
            return "wifi"
        case .cellular:
            return "cellular"
        case .constrained:
            return "constrained"
        case .unknown:
            return "unknown"
        }
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
