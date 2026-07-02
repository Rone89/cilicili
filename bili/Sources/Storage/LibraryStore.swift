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
    @Published private(set) var appTintColorHex: String
    @Published private(set) var defaultPlaybackRate: Double
    @Published private(set) var preferredVideoQuality: Int?
    @Published private(set) var playbackAutoOptimizationMode: PlaybackAutoOptimizationMode
    @Published private(set) var playbackStreamSourcePreference: PlaybackStreamSourcePreference
    @Published private(set) var playerRenderingEnginePreference: PlayerRenderingEnginePreference
    @Published private(set) var videoCodecPreference: VideoCodecPreference
    @Published private(set) var playbackCDNPreference: PlaybackCDNPreference
    @Published private(set) var playbackCustomCDNHost: String?
    @Published private(set) var playbackCDNProbeRefreshPolicy: PlaybackCDNProbeRefreshPolicy
    @Published private(set) var playbackCDNProbeRefreshIntervalMinutes: Int
    @Published private(set) var playbackNetworkAddressFamilyPreference: PlaybackNetworkAddressFamilyPreference
    @Published private(set) var playbackCDNProbeSnapshot: PlaybackCDNProbeSnapshot?
    @Published private(set) var blocksAdDynamics: Bool
    @Published private(set) var blocksGoodsDynamics: Bool
    @Published private(set) var blocksGoodsComments: Bool
    @Published private(set) var blockedDynamicKeywords: [String]
    @Published private(set) var danmakuEnabled: Bool
    @Published private(set) var danmakuSettings: DanmakuSettings
    @Published private(set) var sponsorBlockEnabled: Bool
    @Published private(set) var pictureInPictureEnabled: Bool
    @Published private(set) var playerPerformanceOverlayEnabled: Bool
    @Published private(set) var showsVideoDetailNetworkDiagnosticsButton: Bool
    @Published private(set) var showsVideoDetailPinnedProgressBar: Bool
    @Published private(set) var incognitoModeEnabled: Bool
    @Published private(set) var guestModeEnabled: Bool
    @Published private(set) var minimizesTabBarOnScroll: Bool
    @Published private(set) var scrollEdgeEffectPreference: AppScrollEdgeEffectPreference
    @Published private(set) var videoCoverOverlayStyle: VideoCoverOverlayStyle
    @Published private(set) var force120HzScrollingEnabled: Bool
    @Published private(set) var visibleRootTabs: [AppTab]
    @Published private(set) var homeRefreshTriggerDistance: Double
    @Published private(set) var homeFeedLayout: HomeFeedLayout
    @Published private(set) var homeRecommendFeedSourcePreference: HomeRecommendFeedSourcePreference
    @Published private(set) var showsHotSearches: Bool

    private let userDefaults: UserDefaults
    private static let appearanceModeKey = "cc.bili.appearance.mode.v1"
    private static let appTintColorHexKey = "cc.bili.appearance.tintColorHex.v1"
    private static let appTintColorDefaultMigrationKey = "cc.bili.appearance.tintColorDefaultPinkMigration.v1"
    private static let appTintColorDefaultToneMigrationKey = "cc.bili.appearance.tintColorDefaultToneMigration.v2"
    private static let defaultPlaybackRateKey = "cc.bili.playback.defaultPlaybackRate.v1"
    private static let preferredVideoQualityKey = "cc.bili.playback.preferredVideoQuality.v1"
    private static let playbackAutoOptimizationModeKey = "cc.bili.playback.autoOptimizationMode.v1"
    private static let playbackStreamSourcePreferenceKey = "cc.bili.playback.streamSourcePreference.v1"
    private static let playerRenderingEnginePreferenceKey = PlayerRenderingEnginePreference.storageKey
    private static let videoCodecPreferenceKey = VideoCodecPreference.storageKey
    private static let playbackCDNPreferenceKey = "cc.bili.playback.cdnPreference.v1"
    private static let playbackCustomCDNHostKey = PlaybackCDNPreference.customHostStorageKey
    private static let playbackCDNProbeRefreshPolicyKey = "cc.bili.playback.cdnProbeRefreshPolicy.v1"
    private static let playbackCDNProbeRefreshIntervalMinutesKey = "cc.bili.playback.cdnProbeRefreshIntervalMinutes.v1"
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
    private static let pictureInPictureEnabledKey = "cc.bili.playback.pictureInPictureEnabled.v1"
    private static let playerPerformanceOverlayEnabledKey = "cc.bili.playback.performanceOverlayEnabled.v1"
    private static let showsVideoDetailNetworkDiagnosticsButtonKey = "cc.bili.videoDetail.showsNetworkDiagnosticsButton.v1"
    private static let showsVideoDetailPinnedProgressBarKey = "cc.bili.videoDetail.showsPinnedProgressBar.v1"
    private static let incognitoModeEnabledKey = "cc.bili.privacy.incognitoModeEnabled.v1"
    private static let guestModeEnabledKey = "cc.bili.privacy.guestModeEnabled.v1"
    private static let minimizesTabBarOnScrollKey = "cc.bili.display.minimizesTabBarOnScroll.v1"
    private static let scrollEdgeEffectPreferenceKey = "cc.bili.display.scrollEdgeEffectPreference.v1"
    private static let videoCoverOverlayStyleKey = VideoCoverOverlayStyle.storageKey
    private static let force120HzScrollingEnabledKey = RefreshRateManager.isEnabledKey
    private static let visibleRootTabsKey = "cc.bili.display.visibleRootTabs.v1"
    private static let homeRefreshTriggerDistanceKey = "cc.bili.home.refreshTriggerDistance.v1"
    private static let homeFeedLayoutKey = "cc.bili.home.feedLayout.v1"
    private static let homeRecommendFeedSourcePreferenceKey = "cc.bili.home.recommendFeedSourcePreference.v1"
    private static let showsHotSearchesKey = "cc.bili.search.showsHotSearches.v1"
    private static let supportedPlaybackRates = [0.75, 1.0, 1.25, 1.5, 2.0]
    nonisolated static let defaultPreferredVideoQuality = 112
    nonisolated static let defaultAppTintColorHex = AppThemeTintColor.defaultHex
    nonisolated static let defaultPlaybackStreamSourcePreference: PlaybackStreamSourcePreference = .app
    nonisolated static let defaultHomeRecommendFeedSourcePreference: HomeRecommendFeedSourcePreference = .app
    nonisolated static let supportedVideoQualities = BiliVideoQuality.supportedQualities
    nonisolated static let playbackCDNProbeRefreshIntervalRange: ClosedRange<Int> = 15...1440
    nonisolated static let defaultPlaybackCDNProbeRefreshIntervalMinutes = 120
    nonisolated static let homeRefreshDistanceRange: ClosedRange<Double> = 70...180
    nonisolated static let defaultHomeRefreshTriggerDistance = 110.0
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

    var appTintColor: Color {
        AppThemeTintColor.color(for: appTintColorHex)
    }

    var needsPlaybackCDNProbeRefresh: Bool {
        guard playbackCDNPreference == .automatic else { return false }
        guard let snapshot = playbackCDNProbeSnapshotForCurrentContext else { return true }
        if snapshot.isExpired(freshnessInterval: playbackCDNProbeRefreshInterval) { return true }
        if snapshot.recommendedPreference == nil,
           snapshot.isExpired(freshnessInterval: 15 * 60) {
            return true
        }
        return false
    }

    var playbackCDNProbeRefreshInterval: TimeInterval {
        TimeInterval(playbackCDNProbeRefreshIntervalMinutes * 60)
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.appearanceMode = AppAppearanceMode(
            rawValue: userDefaults.string(forKey: Self.appearanceModeKey) ?? ""
        ) ?? .system
        let storedAppTintColorHex = AppThemeTintColor.normalizedHex(
            userDefaults.string(forKey: Self.appTintColorHexKey)
        )
        let hasMigratedAppTintDefault = userDefaults.bool(forKey: Self.appTintColorDefaultToneMigrationKey)
        if let storedAppTintColorHex,
           !hasMigratedAppTintDefault,
           AppThemeTintColor.legacyDefaultHexes.contains(storedAppTintColorHex) {
            self.appTintColorHex = Self.defaultAppTintColorHex
            userDefaults.set(Self.defaultAppTintColorHex, forKey: Self.appTintColorHexKey)
        } else {
            self.appTintColorHex = storedAppTintColorHex ?? Self.defaultAppTintColorHex
        }
        userDefaults.set(true, forKey: Self.appTintColorDefaultToneMigrationKey)
        userDefaults.set(true, forKey: Self.appTintColorDefaultMigrationKey)
        self.defaultPlaybackRate = Self.normalizedPlaybackRate(userDefaults.object(forKey: Self.defaultPlaybackRateKey) as? Double ?? 1.0)
        if let storedVideoQuality = userDefaults.object(forKey: Self.preferredVideoQualityKey) as? Int {
            self.preferredVideoQuality = storedVideoQuality == 0 ? nil : Self.normalizedVideoQuality(storedVideoQuality)
        } else {
            self.preferredVideoQuality = Self.defaultPreferredVideoQuality
        }
        self.playbackAutoOptimizationMode = PlaybackAutoOptimizationMode(
            rawValue: userDefaults.string(forKey: Self.playbackAutoOptimizationModeKey) ?? ""
        ) ?? .automatic
        self.playbackStreamSourcePreference = PlaybackStreamSourcePreference(
            rawValue: userDefaults.string(forKey: Self.playbackStreamSourcePreferenceKey) ?? ""
        ) ?? Self.defaultPlaybackStreamSourcePreference
        self.playerRenderingEnginePreference = PlayerRenderingEnginePreference.stored(in: userDefaults)
        self.videoCodecPreference = VideoCodecPreference.stored(in: userDefaults)
        self.playbackCDNPreference = PlaybackCDNPreference(
            rawValue: userDefaults.string(forKey: Self.playbackCDNPreferenceKey) ?? ""
        ) ?? .automatic
        self.playbackCustomCDNHost = PlaybackCDNPreference.normalizedCustomHost(
            userDefaults.string(forKey: Self.playbackCustomCDNHostKey)
        )
        self.playbackCDNProbeRefreshPolicy = PlaybackCDNProbeRefreshPolicy(
            rawValue: userDefaults.string(forKey: Self.playbackCDNProbeRefreshPolicyKey) ?? ""
        ) ?? .interval
        self.playbackCDNProbeRefreshIntervalMinutes = Self.normalizedPlaybackCDNProbeRefreshIntervalMinutes(
            userDefaults.object(forKey: Self.playbackCDNProbeRefreshIntervalMinutesKey) as? Int
                ?? Self.defaultPlaybackCDNProbeRefreshIntervalMinutes
        )
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
        self.pictureInPictureEnabled = userDefaults.object(forKey: Self.pictureInPictureEnabledKey) as? Bool ?? false
        self.playerPerformanceOverlayEnabled = userDefaults.object(forKey: Self.playerPerformanceOverlayEnabledKey) as? Bool ?? false
        self.showsVideoDetailNetworkDiagnosticsButton = userDefaults.object(forKey: Self.showsVideoDetailNetworkDiagnosticsButtonKey) as? Bool ?? false
        self.showsVideoDetailPinnedProgressBar = userDefaults.object(forKey: Self.showsVideoDetailPinnedProgressBarKey) as? Bool ?? false
        self.incognitoModeEnabled = userDefaults.object(forKey: Self.incognitoModeEnabledKey) as? Bool ?? false
        self.guestModeEnabled = userDefaults.object(forKey: Self.guestModeEnabledKey) as? Bool ?? false
        self.minimizesTabBarOnScroll = userDefaults.object(forKey: Self.minimizesTabBarOnScrollKey) as? Bool ?? true
        self.scrollEdgeEffectPreference = AppScrollEdgeEffectPreference(
            rawValue: userDefaults.string(forKey: Self.scrollEdgeEffectPreferenceKey) ?? ""
        ) ?? .soft
        self.videoCoverOverlayStyle = VideoCoverOverlayStyle.normalized(
            rawValue: userDefaults.string(forKey: Self.videoCoverOverlayStyleKey)
        )
        self.force120HzScrollingEnabled = userDefaults.object(forKey: Self.force120HzScrollingEnabledKey) as? Bool ?? false
        self.visibleRootTabs = Self.normalizedVisibleRootTabs(
            userDefaults.stringArray(forKey: Self.visibleRootTabsKey)
        )
        self.homeRefreshTriggerDistance = Self.normalizedHomeRefreshDistance(
            userDefaults.object(forKey: Self.homeRefreshTriggerDistanceKey) as? Double ?? Self.defaultHomeRefreshTriggerDistance
        )
        self.homeFeedLayout = HomeFeedLayout(
            rawValue: userDefaults.string(forKey: Self.homeFeedLayoutKey) ?? ""
        ) ?? .singleColumn
        self.homeRecommendFeedSourcePreference = HomeRecommendFeedSourcePreference(
            rawValue: userDefaults.string(forKey: Self.homeRecommendFeedSourcePreferenceKey) ?? ""
        ) ?? Self.defaultHomeRecommendFeedSourcePreference
        self.showsHotSearches = userDefaults.object(forKey: Self.showsHotSearchesKey) as? Bool ?? true
    }

    func setAppearanceMode(_ mode: AppAppearanceMode) {
        appearanceMode = mode
        userDefaults.set(mode.rawValue, forKey: Self.appearanceModeKey)
    }

    @discardableResult
    func setAppTintColorHex(_ hex: String) -> Bool {
        guard let normalizedHex = AppThemeTintColor.normalizedHex(hex) else { return false }
        appTintColorHex = normalizedHex
        userDefaults.set(normalizedHex, forKey: Self.appTintColorHexKey)
        return true
    }

    func setAppTintColor(_ color: Color) {
        guard let hex = AppThemeTintColor.hexString(from: color) else { return }
        setAppTintColorHex(hex)
    }

    func resetAppTintColor() {
        setAppTintColorHex(Self.defaultAppTintColorHex)
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

    func setPlaybackStreamSourcePreference(_ preference: PlaybackStreamSourcePreference) {
        playbackStreamSourcePreference = preference
        userDefaults.set(preference.rawValue, forKey: Self.playbackStreamSourcePreferenceKey)
    }

    func setPlayerRenderingEnginePreference(_ preference: PlayerRenderingEnginePreference) {
        let normalizedPreference = preference.normalizedForFormalPlayback
        playerRenderingEnginePreference = normalizedPreference
        userDefaults.set(normalizedPreference.rawValue, forKey: Self.playerRenderingEnginePreferenceKey)
        PlayerSettings.shared.reload()
    }

    func setVideoCodecPreference(_ preference: VideoCodecPreference) {
        let normalizedPreference = preference.normalizedForPlayback
        videoCodecPreference = normalizedPreference
        userDefaults.set(normalizedPreference.rawValue, forKey: Self.videoCodecPreferenceKey)
        PlayerSettings.shared.reload()
    }

    func setHomeRecommendFeedSourcePreference(_ preference: HomeRecommendFeedSourcePreference) {
        homeRecommendFeedSourcePreference = preference
        userDefaults.set(preference.rawValue, forKey: Self.homeRecommendFeedSourcePreferenceKey)
    }

    func setPlaybackCDNPreference(_ preference: PlaybackCDNPreference) {
        playbackCDNPreference = preference
        clearTemporaryPlaybackCDNAvoidance()
        userDefaults.set(preference.rawValue, forKey: Self.playbackCDNPreferenceKey)
    }

    func setPlaybackCustomCDNHost(_ host: String?) {
        let normalizedHost = PlaybackCDNPreference.normalizedCustomHost(host)
        guard playbackCustomCDNHost != normalizedHost else { return }
        playbackCustomCDNHost = normalizedHost
        clearTemporaryPlaybackCDNAvoidance()
        clearPlaybackCDNProbeSnapshots()
        if let normalizedHost {
            userDefaults.set(normalizedHost, forKey: Self.playbackCustomCDNHostKey)
        } else {
            userDefaults.removeObject(forKey: Self.playbackCustomCDNHostKey)
        }
    }

    func setPlaybackCDNProbeRefreshPolicy(_ policy: PlaybackCDNProbeRefreshPolicy) {
        playbackCDNProbeRefreshPolicy = policy
        userDefaults.set(policy.rawValue, forKey: Self.playbackCDNProbeRefreshPolicyKey)
    }

    func setPlaybackCDNProbeRefreshIntervalMinutes(_ minutes: Int) {
        let normalizedMinutes = Self.normalizedPlaybackCDNProbeRefreshIntervalMinutes(minutes)
        playbackCDNProbeRefreshIntervalMinutes = normalizedMinutes
        userDefaults.set(normalizedMinutes, forKey: Self.playbackCDNProbeRefreshIntervalMinutesKey)
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
              allowExpired || !snapshot.isExpired(freshnessInterval: playbackCDNProbeRefreshInterval)
        else { return nil }
        var seenPreferences = Set<PlaybackCDNPreference>()
        var candidates = [PlaybackCDNPreference]()
        func appendCandidate(_ preference: PlaybackCDNPreference?) {
            guard let preference,
                  snapshot.result(for: preference)?.isActionableForPlaybackRecommendation == true,
                  seenPreferences.insert(preference).inserted
            else { return }
            candidates.append(preference)
        }
        appendCandidate(snapshot.recommendedPreference)
        snapshot.actionableResults.forEach { appendCandidate($0.preference) }
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

    func setPictureInPictureEnabled(_ isEnabled: Bool) {
        pictureInPictureEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: Self.pictureInPictureEnabledKey)
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

    func setScrollEdgeEffectPreference(_ preference: AppScrollEdgeEffectPreference) {
        scrollEdgeEffectPreference = preference
        userDefaults.set(preference.rawValue, forKey: Self.scrollEdgeEffectPreferenceKey)
    }

    func setVideoCoverOverlayStyle(_ style: VideoCoverOverlayStyle) {
        videoCoverOverlayStyle = style
        userDefaults.set(style.rawValue, forKey: Self.videoCoverOverlayStyleKey)
    }

    func setForce120HzScrollingEnabled(_ isEnabled: Bool) {
        force120HzScrollingEnabled = isEnabled
        RefreshRateManager.shared.setForce120HzEnabled(isEnabled)
    }

    func setRootTab(_ tab: AppTab, isVisible: Bool) {
        guard tab.canHideFromRootTabBar else { return }
        var tabs = visibleRootTabs
        if isVisible {
            if !tabs.contains(tab) {
                let defaultIndex = AppTab.defaultVisibleTabs.firstIndex(of: tab) ?? tabs.count
                let insertionIndex = tabs.firstIndex { existing in
                    let existingIndex = AppTab.defaultVisibleTabs.firstIndex(of: existing) ?? Int.max
                    return existingIndex > defaultIndex
                } ?? tabs.count
                tabs.insert(tab, at: insertionIndex)
            }
        } else {
            tabs.removeAll { $0 == tab }
        }
        setVisibleRootTabs(tabs)
    }

    func resetVisibleRootTabs() {
        setVisibleRootTabs(AppTab.defaultVisibleTabs)
    }

    private func setVisibleRootTabs(_ tabs: [AppTab]) {
        let normalized = AppTab.normalizedVisibleTabs(tabs)
        guard normalized != visibleRootTabs else { return }
        visibleRootTabs = normalized
        userDefaults.set(normalized.map(\.rawValue), forKey: Self.visibleRootTabsKey)
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

    func setShowsHotSearches(_ isEnabled: Bool) {
        showsHotSearches = isEnabled
        userDefaults.set(isEnabled, forKey: Self.showsHotSearchesKey)
    }

    private static func normalizedPlaybackRate(_ rate: Double) -> Double {
        supportedPlaybackRates.contains(rate) ? rate : 1.0
    }

    private static func normalizedVideoQuality(_ quality: Int?) -> Int? {
        guard let quality, supportedVideoQualities.contains(quality) else { return nil }
        return quality
    }

    private static func normalizedPlaybackCDNProbeRefreshIntervalMinutes(_ minutes: Int) -> Int {
        min(max(minutes, playbackCDNProbeRefreshIntervalRange.lowerBound), playbackCDNProbeRefreshIntervalRange.upperBound)
    }

    private static func normalizedVisibleRootTabs(_ rawValues: [String]?) -> [AppTab] {
        guard let rawValues, !rawValues.isEmpty else {
            return AppTab.defaultVisibleTabs
        }
        let tabs = rawValues.compactMap(AppTab.init(rawValue:))
        return AppTab.normalizedVisibleTabs(tabs)
    }

    static func videoQualityTitle(_ quality: Int?) -> String {
        BiliVideoQuality.title(for: quality)
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

enum AppScrollEdgeEffectPreference: String, CaseIterable, Identifiable {
    case soft
    case hard
    case automatic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .soft:
            return "Soft"
        case .hard:
            return "Hard"
        case .automatic:
            return "Automatic"
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
