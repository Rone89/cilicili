import Foundation
import SwiftUI
import UIKit

struct PlaybackNetworkDiagnosticsSheet: View {
    @ObservedObject var diagnosticsStore: VideoDetailNetworkDiagnosticsRenderStore
    @ObservedObject var relatedStore: VideoDetailRelatedRenderStore
    @ObservedObject var libraryStore: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var performanceObserver: PlayerPerformanceSessionObserver
    @State private var isProbingPlaybackCDN = false
    @State private var probeMessage: String?
    @State private var copiedMessage: String?
    @State private var cacheSummary: ResourceCacheSummary?
    @State private var playbackURLPreferenceSnapshots: [PlaybackURLPreferenceSnapshot] = []
    @State private var hlsBridgeSourceSnapshots: [HLSBridgeSourceDiagnosticsSnapshot] = []

    init(
        diagnosticsStore: VideoDetailNetworkDiagnosticsRenderStore,
        relatedStore: VideoDetailRelatedRenderStore,
        libraryStore: LibraryStore
    ) {
        self.diagnosticsStore = diagnosticsStore
        self.relatedStore = relatedStore
        self.libraryStore = libraryStore
        _performanceObserver = StateObject(
            wrappedValue: PlayerPerformanceSessionObserver(
                metricsID: diagnosticsStore.metricsID,
                isAutoOptimizationEnabled: libraryStore.isPlaybackAutoOptimizationEnabled
            )
        )
    }

    private var variant: PlayVariant? {
        diagnosticsStore.selectedPlayVariant
    }

    private var playerViewModel: PlayerStateViewModel? {
        diagnosticsStore.playerViewModel
    }

    private var playbackEnvironment: PlaybackEnvironment {
        PlaybackEnvironment.current
    }

    private var performanceSession: PlayerPerformanceSession? {
        performanceObserver.session
    }

    private var playbackAdaptationProfile: PlayerPlaybackAdaptationProfile {
        performanceObserver.playbackAdaptationProfile
    }

    var body: some View {
        NavigationStack {
            Form {
                actionsSection
                cdnSection
                hlsBridgeSection
                loadingMetricsSection
                resumeSection
                streamSection
                playerSection
                baselineSection
                environmentSection
                probeSection
            }
            .navigationTitle("网络诊断")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .task {
                refreshPlaybackURLPreferenceSnapshots()
                await refreshHLSBridgeSourceSnapshots()
                cacheSummary = await ResourceCacheCenter.summary()
            }
            .task(id: variant?.id) {
                await refreshHLSBridgeSourceSnapshots()
            }
            .onChange(of: diagnosticsStore.metricsID) { _, metricsID in
                performanceObserver.updateContext(
                    metricsID: metricsID,
                    isAutoOptimizationEnabled: libraryStore.isPlaybackAutoOptimizationEnabled
                )
                Task {
                    await refreshHLSBridgeSourceSnapshots()
                }
            }
            .onChange(of: libraryStore.isPlaybackAutoOptimizationEnabled) { _, isEnabled in
                performanceObserver.updateContext(
                    metricsID: diagnosticsStore.metricsID,
                    isAutoOptimizationEnabled: isEnabled
                )
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                copyDiagnostics()
            } label: {
                Label(copiedMessage ?? "复制诊断信息", systemImage: "doc.on.doc")
            }

            Button {
                probePlaybackCDN()
            } label: {
                Label(isProbingPlaybackCDN ? "CDN 测速中" : "重新测速 CDN", systemImage: "speedometer")
            }
            .disabled(isProbingPlaybackCDN)

            if let probeMessage {
                Text(probeMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var cdnSection: some View {
        Section("CDN") {
            diagnosticRow("当前使用", libraryStore.effectivePlaybackCDNPreference.title)
            diagnosticRow("设置模式", libraryStore.playbackCDNPreference.title)
            diagnosticRow("网络协议", libraryStore.playbackNetworkAddressFamilyPreference.title)

            if libraryStore.playbackCDNPreference == .automatic {
                diagnosticRow(
                    "自动推荐",
                    libraryStore.automaticPlaybackCDNRecommendation?.title ?? "暂无可用推荐"
                )
            }

            diagnosticRow("视频 Host", variant?.videoURL?.host ?? "未获取")

            if let audioURL = variant?.audioURL {
                diagnosticRow("音频 Host", audioURL.host ?? "未知")
            }

            if let currentHostSnapshot {
                diagnosticMultilineRow("当前 Host 历史", playbackURLPreferenceSummary(currentHostSnapshot))
            }

            if !playbackURLPreferenceSnapshots.isEmpty {
                DisclosureGroup {
                    ForEach(playbackURLPreferenceSnapshots.prefix(6)) { snapshot in
                        diagnosticURLPreferenceRow(snapshot)
                    }
                } label: {
                    Label("真实播放排行", systemImage: "list.bullet.rectangle")
                }
            }
        }
    }

    private var currentHostSnapshot: PlaybackURLPreferenceSnapshot? {
        guard let host = variant?.videoURL?.host else { return nil }
        let normalizedHost = host.lowercased()
        return playbackURLPreferenceSnapshots.first { $0.host == normalizedHost }
            ?? PlaybackURLPreferenceStore.shared.snapshot(forHost: normalizedHost)
    }

    private var hlsBridgeCandidateURLs: [URL] {
        guard let variant else { return [] }
        let cdnPreference = libraryStore.effectivePlaybackCDNPreference
        var urls: [URL] = []
        var seen = Set<URL>()
        func append(_ url: URL?) {
            guard let url, seen.insert(url).inserted else { return }
            urls.append(url)
        }
        append(variant.videoURL)
        for url in variant.videoStream?.backupPlayURLs(cdnPreference: cdnPreference) ?? [] {
            append(url)
        }
        append(variant.audioURL)
        for url in variant.audioStream?.backupPlayURLs(cdnPreference: cdnPreference) ?? [] {
            append(url)
        }
        return urls
    }

    @ViewBuilder
    private var hlsBridgeSection: some View {
        if variant?.audioURL != nil {
            Section("HLSBridge") {
                if hlsBridgeSourceSnapshots.isEmpty {
                    Text("等待 HLSBridge 线路样本")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(hlsBridgeSourceSnapshots.prefix(8)) { snapshot in
                        diagnosticHLSBridgeSourceRow(snapshot)
                    }
                }
            }
        }
    }

    private var loadingMetricsSection: some View {
        Section("加载耗时") {
            diagnosticRow("视频详情", formattedMilliseconds(diagnosticsStore.detailLoadElapsedMilliseconds))
            diagnosticRow("播放地址", formattedMilliseconds(diagnosticsStore.playURLElapsedMilliseconds))
            diagnosticRow("相关推荐", formattedMilliseconds(diagnosticsStore.relatedElapsedMilliseconds))
            diagnosticRow("取流来源", playURLSourceTitle)

            if relatedStore.lastLoadTimedOut {
                Label("相关推荐最近一次加载超时，已停止等待并保留主播放优先。", systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var resumeSection: some View {
        let diagnostics = diagnosticsStore.resumeDiagnostics
        return Section("续播") {
            diagnosticRow("来源", diagnostics.sourceTitle)
            diagnosticRow("目标", formattedResumeTime(diagnostics.targetTime))
            diagnosticRow("CID", diagnostics.cid.map(String.init) ?? "未确定")
            diagnosticRow("状态", diagnostics.statusTitle)
            if let currentTime = diagnostics.currentTime {
                diagnosticRow("当前位置", formattedResumeTime(currentTime))
            }
            diagnosticMultilineRow("决策原因", diagnostics.reason)
        }
    }

    private var streamSection: some View {
        Section("当前流") {
            diagnosticRow("清晰度", variant?.title ?? "未选择")
            diagnosticRow("封装模式", streamModeTitle)
            diagnosticRow("编码", variant?.codec?.nilIfEmpty ?? "未知")
            diagnosticRow("分辨率", variant?.resolution?.nilIfEmpty ?? "未知")
            diagnosticRow("帧率", frameRateTitle)
            diagnosticRow("带宽", bandwidthTitle)

            if let subtitle = variant?.subtitle, !subtitle.isEmpty {
                diagnosticMultilineRow("档位信息", subtitle)
            }
        }
    }

    @ViewBuilder
    private var playerSection: some View {
        if let playerViewModel {
            PlaybackNetworkPlayerSection(
                playerViewModel: playerViewModel,
                fallbackMessage: diagnosticsStore.playbackFallbackMessage
            )
        } else {
            Section("播放器") {
                diagnosticRow("状态", "等待播放器")
                diagnosticRow("阶段", "等待播放器")
                if let fallbackMessage = diagnosticsStore.playbackFallbackMessage, !fallbackMessage.isEmpty {
                    diagnosticMultilineRow("降级信息", fallbackMessage)
                }
            }
        }
    }

    private var baselineSection: some View {
        let profile = playbackAdaptationProfile
        let session = performanceSession
        return Section("性能基线") {
            diagnosticRow("自适应等级", profile.diagnosticTitle)
            diagnosticRow("启动清晰度上限", profile.startupQualityCeilingTitle)
            diagnosticRow("后台预加载额度", "\(profile.backgroundPreloadLimit)")
            diagnosticRow("弹幕负载", String(format: "%.0f%%", profile.danmakuLoadFactor * 100))
            diagnosticRow("保守视频策略", profile.prefersEnergyEfficientVideo ? "启用" : "未启用")

            if let session {
                diagnosticRow("总首帧", formattedMilliseconds(session.firstFrameTotalMilliseconds))
                diagnosticRow("播放器首帧", formattedMilliseconds(session.firstFramePlayerMilliseconds))
                diagnosticRow("取流耗时", formattedMilliseconds(session.playURLMilliseconds))
                diagnosticRow("取流来源", startupPlayURLTitle(for: session))
                diagnosticRow("Prepare", formattedMilliseconds(session.prepareMilliseconds))
                diagnosticRow("HLS Route", startupRoutePlanTitle(for: session))
                if session.startupRoutePrebuildState != nil {
                    diagnosticRow("Route 预构建", startupRoutePrebuildTitle(for: session))
                }
                diagnosticRow("启动包", startupPackageTitle(for: session))
                diagnosticRow("首片预热", startupRangeWarmTitle(for: session))
                if let startupBreakdownMessage = session.startupBreakdownMessage {
                    diagnosticMultilineRow("首帧分段", startupBreakdownMessage)
                }
                if let resumeApplyMilliseconds = session.resumeApplyMilliseconds {
                    diagnosticRow("续播 Seek", formattedMilliseconds(resumeApplyMilliseconds))
                }
                if session.resumeRecoveryCount > 0 {
                    diagnosticRow("续播验证", "\(session.resumeRecoveryCount) 次，慢 \(session.resumeRecoverySlowCount) 次")
                }
                if let lastResumeRecoveryMilliseconds = session.lastResumeRecoveryMilliseconds {
                    diagnosticRow("续播落点", formattedMilliseconds(lastResumeRecoveryMilliseconds))
                }
                diagnosticRow("缓冲次数", "\(session.bufferCount)")
                diagnosticRow("Seek 次数", "\(session.seekCount)")
                if session.seekRecoveryCount > 0 {
                    diagnosticRow("Seek 恢复", "\(session.seekRecoveryCount) 次")
                }
                if session.speedBoostCount > 0 {
                    diagnosticRow("长按倍速", "\(session.speedBoostCount) 次，中断 \(session.speedBoostInterruptionCount) 次")
                }
                if let seekMessage = session.seekMessage {
                    diagnosticMultilineRow("最近 Seek", seekMessage)
                }
                if let resumeRecoveryMessage = session.resumeRecoveryMessage {
                    diagnosticMultilineRow("最近续播验证", resumeRecoveryMessage)
                }
                if let seekRecoveryMessage = session.seekRecoveryMessage {
                    diagnosticMultilineRow("最近恢复", seekRecoveryMessage)
                }
                if let accessLogMessage = session.accessLogMessage {
                    diagnosticMultilineRow("AccessLog", accessLogMessage)
                }
                if let speedBoostMessage = session.speedBoostMessage {
                    diagnosticMultilineRow("最近倍速", speedBoostMessage)
                }
                if let qualitySupplementMessage = session.qualitySupplementMessage {
                    diagnosticMultilineRow("质量补充", qualitySupplementMessage)
                }
                if !session.timeline.isEmpty {
                    diagnosticMultilineRow(
                        "播放时间线",
                        session.timeline.suffix(8).map(\.compactDescription).joined(separator: "\n")
                    )
                }
            } else {
                Text("等待播放性能事件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let cacheSummary {
                diagnosticRow(
                    "API SWR 缓存",
                    "\(cacheSummary.apiMemory.count) 条 · \(formattedBytes(cacheSummary.apiMemory.estimatedBytes))"
                )
                diagnosticRow(
                    "API 命中",
                    "fresh \(cacheSummary.apiMemory.hits) · stale \(cacheSummary.apiMemory.staleHits) · miss \(cacheSummary.apiMemory.misses)"
                )
                diagnosticRow(
                    "媒体缓存",
                    "\(cacheSummary.progressiveMedia.entryCount) 段 · \(formattedBytes(cacheSummary.progressiveMedia.estimatedBytes))"
                )
                diagnosticRow(
                    "图片缓存",
                    "\(cacheSummary.image.memoryEntryCount) 张 · \(formattedBytes(cacheSummary.image.diskUsage))"
                )
            } else {
                Text("正在读取缓存基线...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var environmentSection: some View {
        Section("设备网络") {
            diagnosticRow("播放自动优化", libraryStore.playbackAutoOptimizationMode.title)
            diagnosticRow("网络类型", playbackEnvironment.networkClass.diagnosticTitle)
            diagnosticRow("省电模式", playbackEnvironment.isLowPowerModeEnabled ? "开启" : "关闭")
            diagnosticRow("温控限制", playbackEnvironment.isThermallyConstrained ? "已触发" : "未触发")
            diagnosticRow("保守播放策略", playbackEnvironment.shouldPreferConservativePlayback ? "启用" : "未启用")
        }
    }

    @ViewBuilder
    private var probeSection: some View {
        Section("最近测速") {
            if let snapshot = libraryStore.playbackCDNProbeSnapshotForCurrentContext {
                diagnosticRow(
                    "测速时间",
                    snapshot.probedAt.formatted(date: .abbreviated, time: .shortened)
                )
                diagnosticRow("有效状态", snapshot.isExpired() ? "已过期" : "有效")
                diagnosticRow("推荐 CDN", snapshot.recommendedPreference?.title ?? "暂无推荐")

                if let recommendation = snapshot.recommendedPreference,
                   let result = snapshot.result(for: recommendation) {
                    diagnosticRow("推荐延迟", result.elapsedMilliseconds.map { "\($0) ms" } ?? "失败")
                }

                if !snapshot.successfulResults.isEmpty {
                    DisclosureGroup {
                        ForEach(snapshot.results.prefix(8)) { result in
                            diagnosticProbeResultRow(result)
                        }
                    } label: {
                        Label("测速排行", systemImage: "list.number")
                    }
                }

                if snapshot.isExpired() {
                    Label("测速结果超过 24 小时，自动 CDN 可能需要重新测速。", systemImage: "clock.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else {
                ContentUnavailableView(
                    "暂无 CDN 测速结果",
                    systemImage: "network.slash",
                    description: Text("进入我的页面执行一次 CDN 测速后，这里会显示推荐节点和延迟。")
                )
            }
        }
    }

    private var streamModeTitle: String {
        guard let variant else { return "未获取" }
        if variant.videoStream != nil || variant.audioStream != nil {
            return variant.audioURL == nil ? "DASH 视频流" : "DASH 音视频分离"
        }
        return "Progressive 单流"
    }

    private var frameRateTitle: String {
        guard let frameRate = variant?.frameRate?.nilIfEmpty else { return "未知" }
        return frameRate.localizedCaseInsensitiveContains("fps") ? frameRate : "\(frameRate) fps"
    }

    private var bandwidthTitle: String {
        guard let bandwidth = variant?.bandwidth, bandwidth > 0 else { return "未知" }
        let mbps = Double(bandwidth) / 1_000_000
        return "\(String(format: "%.2f", mbps)) Mbps"
    }

    private var playerStateTitle: String {
        guard let playerViewModel else { return "等待播放器" }
        if playerViewModel.errorMessage?.isEmpty == false {
            return "播放错误"
        }
        if playerViewModel.isPreparing {
            return "准备中"
        }
        if playerViewModel.isBuffering {
            return "缓冲中"
        }
        if playerViewModel.isPlaying {
            return "播放中"
        }
        return "暂停/待播"
    }

    private var playURLSourceTitle: String {
        playURLSourceTitle(diagnosticsStore.lastPlayURLSource)
    }

    private func playURLSourceTitle(_ source: String?) -> String {
        switch source {
        case "playableCache":
            return "可播放缓存"
        case "playableCachePreferredMiss":
            return "可播放缓存，画质待刷新"
        case "playableCacheStaleWhileRefresh":
            return "可播放缓存，后台刷新"
        case "cache":
            return "缓存"
        case "cachePreferredMiss":
            return "缓存，画质待刷新"
        case "pendingCache":
            return "预加载结果"
        case "pendingCachePreferredMiss":
            return "预加载结果，画质待刷新"
        case "pendingCacheStaleWhileRefresh":
            return "预加载结果，后台刷新"
        case "detailWarmCache":
            return "详情预热缓存"
        case "network":
            return "网络请求"
        case "playableCacheFallbackAfterNetworkFailure":
            return "可播放缓存降级"
        case "cacheFallbackAfterNetworkFailure":
            return "缓存降级"
        case "pendingCacheFallbackAfterNetworkFailure":
            return "预加载缓存降级"
        case "stalePlayableCacheAfterNetworkFailure":
            return "过期可播放缓存降级"
        case "memoryPlayableCacheAfterNetworkFailure":
            return "内存可播放缓存降级"
        case "startupRecovery":
            return "启动取流恢复"
        case "networkRecovery":
            return "完整取流恢复"
        case "networkOrCache":
            return "网络/缓存"
        case let source?:
            return source
        case nil:
            return "未获取"
        }
    }

    private func startupPlayURLTitle(for session: PlayerPerformanceSession) -> String {
        let source = session.startupPlayURLSource ?? session.startupSource
        var parts = [playURLSourceTitle(source)]
        if let count = session.startupPlayURLVariantCount {
            parts.append("\(count) 档")
        }
        return parts.joined(separator: " · ")
    }

    private func startupRoutePlanTitle(for session: PlayerPerformanceSession) -> String {
        formattedStartupState(session.startupRoutePlanState, milliseconds: session.startupRoutePlanMilliseconds)
    }

    private func startupRoutePrebuildTitle(for session: PlayerPerformanceSession) -> String {
        formattedStartupState(session.startupRoutePrebuildState, milliseconds: session.startupRoutePrebuildMilliseconds)
    }

    private func startupPackageTitle(for session: PlayerPerformanceSession) -> String {
        var parts: [String] = []
        if let routePlan = session.startupPackageRoutePlanState {
            parts.append("Route \(startupStateTitle(routePlan))")
        }
        if let range = session.startupPackageRangeState {
            parts.append("Range \(startupStateTitle(range))")
        }
        return parts.isEmpty ? "未记录" : parts.joined(separator: " · ")
    }

    private func startupRangeWarmTitle(for session: PlayerPerformanceSession) -> String {
        if let state = session.startupRangeWarmState {
            return formattedStartupState(state, milliseconds: session.startupRangeWarmMilliseconds)
        }
        return formattedStartupState(session.startupPackageRangeState, milliseconds: nil)
    }

    private func formattedStartupState(_ state: String?, milliseconds: Int?) -> String {
        guard let state else { return "未记录" }
        var title = startupStateTitle(state)
        if let milliseconds {
            title += " · \(formattedMilliseconds(milliseconds))"
        }
        return title
    }

    private func startupStateTitle(_ state: String) -> String {
        switch state {
        case "hit":
            return "命中"
        case "pending":
            return "等待中"
        case "miss":
            return "未命中"
        case "uncached":
            return "未缓存"
        case "skippedPending":
            return "已有任务"
        case "ready":
            return "已就绪"
        case "skip", "skipped":
            return "跳过"
        default:
            return state
        }
    }

    private func diagnosticRow(_ title: String, _ value: String) -> some View {
        LabeledContent {
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        } label: {
            Text(title)
        }
    }

    private func diagnosticMultilineRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedResumeTime(_ time: TimeInterval?) -> String {
        guard let time, time.isFinite, time > 0 else { return "无" }
        return "\(BiliFormatters.duration(Int(time.rounded()))) · \(String(format: "%.1fs", time))"
    }

    private func diagnosticProbeResultRow(_ result: PlaybackCDNProbeResult) -> some View {
        HStack(spacing: 8) {
            Image(systemName: result.didSucceed ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(result.didSucceed ? .green : .secondary)
            Text(result.preference.title)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let addressFamily = result.addressFamily {
                Text(addressFamily.title)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            Text(result.elapsedMilliseconds.map { "\($0) ms" } ?? result.errorDescription ?? "失败")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func diagnosticHLSBridgeSourceRow(_ snapshot: HLSBridgeSourceDiagnosticsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("#\(snapshot.order)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Text(snapshot.host)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                Spacer(minLength: 8)
                if snapshot.isSessionAvoided {
                    Text("避让")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Text(snapshot.averageMilliseconds.map { "\($0) ms" } ?? "-")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(hlsBridgeSourceSummary(snapshot))
                .font(.caption2)
                .foregroundStyle(snapshot.isSessionAvoided || snapshot.failureCount > 0 ? .orange : .secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 3)
    }

    private func formattedMilliseconds(_ value: Int?) -> String {
        guard let value else { return "未记录" }
        if value >= 1000 {
            return String(format: "%.2f s", Double(value) / 1000)
        }
        return "\(value) ms"
    }

    private func formattedBytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func copyDiagnostics() {
        UIPasteboard.general.string = diagnosticsText
        copiedMessage = "已复制诊断信息"
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copiedMessage = nil
        }
    }

    private func probePlaybackCDN() {
        guard !isProbingPlaybackCDN else { return }
        isProbingPlaybackCDN = true
        probeMessage = "正在测试 CDN 线路..."
        Task {
            let addressFamilyPreference = await MainActor.run {
                libraryStore.playbackNetworkAddressFamilyPreference
            }
            let snapshot = await PlaybackCDNProbeService.recommendedSnapshot(
                addressFamilyPreference: addressFamilyPreference
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                libraryStore.setPlaybackCDNProbeSnapshot(snapshot)
                if let preference = snapshot.recommendedPreference,
                   let elapsed = snapshot.result(for: preference)?.elapsedMilliseconds {
                    libraryStore.setPlaybackCDNPreference(preference)
                    probeMessage = "已推荐 \(preference.title)，\(elapsed) ms"
                } else {
                    probeMessage = "未找到可用 CDN，已保留当前设置"
                }
                refreshPlaybackURLPreferenceSnapshots()
                isProbingPlaybackCDN = false
            }
        }
    }

    private func refreshPlaybackURLPreferenceSnapshots() {
        playbackURLPreferenceSnapshots = PlaybackURLPreferenceStore.shared.rankedSnapshots(limit: 8)
    }

    @MainActor
    private func refreshHLSBridgeSourceSnapshots() async {
        let urls = hlsBridgeCandidateURLs
        guard !urls.isEmpty else {
            hlsBridgeSourceSnapshots = []
            return
        }
        hlsBridgeSourceSnapshots = await LocalHLSBridge.sourceDiagnostics(for: urls)
    }

    private var diagnosticsText: String {
        var lines = [String]()
        lines.append("播放器网络诊断")
        lines.append("视频：\(diagnosticsStore.videoTitle)")
        lines.append("BVID：\(diagnosticsStore.metricsID)")
        lines.append("当前 CDN：\(libraryStore.effectivePlaybackCDNPreference.title)")
        lines.append("CDN 设置：\(libraryStore.playbackCDNPreference.title)")
        lines.append("网络协议：\(libraryStore.playbackNetworkAddressFamilyPreference.title)")
        lines.append("播放自动优化：\(libraryStore.playbackAutoOptimizationMode.title)")
        lines.append("视频 Host：\(variant?.videoURL?.host ?? "未获取")")
        lines.append("音频 Host：\(variant?.audioURL?.host ?? "未获取")")
        if let currentHostSnapshot {
            lines.append("当前 Host 历史：\(playbackURLPreferenceSummary(currentHostSnapshot))")
        }
        if !playbackURLPreferenceSnapshots.isEmpty {
            lines.append("真实播放排行：")
            lines.append(contentsOf: playbackURLPreferenceSnapshots.prefix(6).map { "  \($0.host) · \(playbackURLPreferenceSummary($0))" })
        }
        if !hlsBridgeSourceSnapshots.isEmpty {
            lines.append("HLSBridge 线路：")
            lines.append(contentsOf: hlsBridgeSourceSnapshots.prefix(8).map { "  #\($0.order) \($0.host) · \(hlsBridgeSourceSummary($0))" })
        }
        lines.append("清晰度：\(variant?.title ?? "未选择")")
        lines.append("封装模式：\(streamModeTitle)")
        lines.append("编码：\(variant?.codec?.nilIfEmpty ?? "未知")")
        lines.append("分辨率：\(variant?.resolution?.nilIfEmpty ?? "未知")")
        lines.append("帧率：\(frameRateTitle)")
        lines.append("带宽：\(bandwidthTitle)")
        lines.append("视频详情耗时：\(formattedMilliseconds(diagnosticsStore.detailLoadElapsedMilliseconds))")
        lines.append("播放地址耗时：\(formattedMilliseconds(diagnosticsStore.playURLElapsedMilliseconds))")
        lines.append("相关推荐耗时：\(formattedMilliseconds(diagnosticsStore.relatedElapsedMilliseconds))")
        lines.append("取流来源：\(playURLSourceTitle)")
        lines.append("续播来源：\(diagnosticsStore.resumeDiagnostics.sourceTitle)")
        lines.append("续播目标：\(formattedResumeTime(diagnosticsStore.resumeDiagnostics.targetTime))")
        lines.append("续播 CID：\(diagnosticsStore.resumeDiagnostics.cid.map(String.init) ?? "未确定")")
        lines.append("续播状态：\(diagnosticsStore.resumeDiagnostics.statusTitle)")
        lines.append("续播原因：\(diagnosticsStore.resumeDiagnostics.reason)")
        let profile = playbackAdaptationProfile
        lines.append("自适应等级：\(profile.diagnosticTitle)")
        lines.append("启动清晰度上限：\(profile.startupQualityCeilingTitle)")
        lines.append("后台预加载额度：\(profile.backgroundPreloadLimit)")
        lines.append("弹幕负载：\(String(format: "%.0f%%", profile.danmakuLoadFactor * 100))")
        if let session = performanceSession {
            lines.append("总首帧：\(formattedMilliseconds(session.firstFrameTotalMilliseconds))")
            lines.append("播放器首帧：\(formattedMilliseconds(session.firstFramePlayerMilliseconds))")
            lines.append("启动取流来源：\(startupPlayURLTitle(for: session))")
            lines.append("HLS Route：\(startupRoutePlanTitle(for: session))")
            if session.startupRoutePrebuildState != nil {
                lines.append("Route 预构建：\(startupRoutePrebuildTitle(for: session))")
            }
            lines.append("启动包：\(startupPackageTitle(for: session))")
            lines.append("首片预热：\(startupRangeWarmTitle(for: session))")
            if let startupBreakdownMessage = session.startupBreakdownMessage {
                lines.append("首帧分段：\(startupBreakdownMessage)")
            }
            if let resumeApplyMilliseconds = session.resumeApplyMilliseconds {
                lines.append("续播 Seek：\(formattedMilliseconds(resumeApplyMilliseconds))")
            }
            if session.resumeRecoveryCount > 0 {
                lines.append("续播验证：\(session.resumeRecoveryCount) 次，慢 \(session.resumeRecoverySlowCount) 次")
            }
            if let lastResumeRecoveryMilliseconds = session.lastResumeRecoveryMilliseconds {
                lines.append("续播落点：\(formattedMilliseconds(lastResumeRecoveryMilliseconds))")
            }
            lines.append("Seek 次数：\(session.seekCount)")
            if session.seekRecoveryCount > 0 {
                lines.append("Seek 恢复：\(session.seekRecoveryCount) 次")
            }
            if let accessLogMessage = session.accessLogMessage {
                lines.append("AccessLog：\(accessLogMessage)")
            }
            if session.speedBoostCount > 0 {
                lines.append("长按倍速：\(session.speedBoostCount) 次，中断 \(session.speedBoostInterruptionCount) 次")
            }
            if !session.timeline.isEmpty {
                lines.append("播放时间线：")
                lines.append(contentsOf: session.timeline.suffix(8).map { "  \($0.compactDescription)" })
            }
            if let seekMessage = session.seekMessage {
                lines.append("最近 Seek：\(seekMessage)")
            }
            if let resumeRecoveryMessage = session.resumeRecoveryMessage {
                lines.append("最近续播验证：\(resumeRecoveryMessage)")
            }
            if let seekRecoveryMessage = session.seekRecoveryMessage {
                lines.append("最近恢复：\(seekRecoveryMessage)")
            }
            if let speedBoostMessage = session.speedBoostMessage {
                lines.append("最近倍速：\(speedBoostMessage)")
            }
        }
        if let cacheSummary {
            lines.append("API SWR 缓存：\(cacheSummary.apiMemory.count) 条，\(formattedBytes(cacheSummary.apiMemory.estimatedBytes))")
            lines.append("API SWR 命中：fresh \(cacheSummary.apiMemory.hits)，stale \(cacheSummary.apiMemory.staleHits)，miss \(cacheSummary.apiMemory.misses)")
            lines.append("媒体缓存：\(cacheSummary.progressiveMedia.entryCount) 段，\(formattedBytes(cacheSummary.progressiveMedia.estimatedBytes))")
            lines.append("图片缓存：\(cacheSummary.image.memoryEntryCount) 张，\(formattedBytes(cacheSummary.image.diskUsage))")
        }
        lines.append("播放器状态：\(playerStateTitle)")
        lines.append("播放器引擎：\(playerViewModel?.engineDiagnostics.engineName ?? "未知")")
        lines.append("解码路径：\(playerViewModel?.engineDiagnostics.decodePath.title ?? "未知")")
        lines.append("异步硬解：\(playerViewModel?.engineDiagnostics.asynchronousDecompressionEnabled == true ? "开启" : "关闭")")
        if let diagnostics = playerViewModel?.engineDiagnostics,
           diagnostics.hlsVideoVariantCount > 0 {
            lines.append("HLS 档位：\(hlsVariantText(diagnostics))")
        }
        lines.append("准备耗时：\(formattedMilliseconds(playerViewModel?.prepareElapsedMilliseconds))")
        lines.append("首帧耗时：\(formattedMilliseconds(playerViewModel?.firstFrameElapsedMilliseconds))")
        lines.append("缓冲次数：\(playerViewModel?.bufferingCount ?? 0)")
        lines.append("最近缓冲：\(formattedMilliseconds(playerViewModel?.lastBufferingElapsedMilliseconds))")
        lines.append("网络类型：\(playbackEnvironment.networkClass.diagnosticTitle)")
        lines.append("省电模式：\(playbackEnvironment.isLowPowerModeEnabled ? "开启" : "关闭")")
        lines.append("温控限制：\(playbackEnvironment.isThermallyConstrained ? "已触发" : "未触发")")
        if let snapshot = libraryStore.playbackCDNProbeSnapshotForCurrentContext {
            lines.append("测速时间：\(snapshot.probedAt.formatted(date: .abbreviated, time: .shortened))")
            lines.append("测速推荐：\(snapshot.recommendedPreference?.title ?? "暂无推荐")")
            lines.append("测速是否过期：\(snapshot.isExpired() ? "是" : "否")")
        }
        if let errorMessage = playerViewModel?.errorMessage, !errorMessage.isEmpty {
            lines.append("播放器错误：\(errorMessage)")
        }
        if let fallbackMessage = diagnosticsStore.playbackFallbackMessage, !fallbackMessage.isEmpty {
            lines.append("降级信息：\(fallbackMessage)")
        }
        return lines.joined(separator: "\n")
    }

    private func hlsVariantText(_ diagnostics: PlayerEngineDiagnostics) -> String {
        let count = diagnostics.hlsVideoVariantCount
        let qualities = diagnostics.hlsVideoVariantQualities
            .map { "q\($0)" }
            .joined(separator: "/")
        guard !qualities.isEmpty else { return "\(count) 档" }
        return "\(count) 档 · \(qualities)"
    }

    private func diagnosticURLPreferenceRow(_ snapshot: PlaybackURLPreferenceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(snapshot.host)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(snapshot.averageMilliseconds) ms")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(playbackURLPreferenceSummary(snapshot))
                .font(.caption2)
                .foregroundStyle(snapshot.failureCount > 0 ? .orange : .secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 3)
    }

    private func playbackURLPreferenceSummary(_ snapshot: PlaybackURLPreferenceSnapshot) -> String {
        "\(snapshot.networkTitle) · \(playbackURLThroughputText(snapshot.averageKilobytesPerSecond)) · 失败 \(snapshot.failureRatePercent)% · \(snapshot.attemptCount) 样本 · \(snapshot.lastUpdatedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private func hlsBridgeSourceSummary(_ snapshot: HLSBridgeSourceDiagnosticsSnapshot) -> String {
        var parts = [
            playbackURLThroughputText(snapshot.averageKilobytesPerSecond),
            "失败 \(snapshot.failureRatePercent)%",
            "\(snapshot.attemptCount) 样本"
        ]
        if snapshot.isSessionAvoided {
            let expires = snapshot.avoidanceExpiresAt.map {
                $0.formatted(date: .omitted, time: .shortened)
            } ?? "-"
            parts.append("避让 \(snapshot.avoidanceReason ?? "-") 至 \(expires)")
        }
        return parts.joined(separator: " · ")
    }

    private func playbackURLThroughputText(_ kilobytesPerSecond: Int) -> String {
        guard kilobytesPerSecond > 0 else { return "吞吐 -" }
        if kilobytesPerSecond >= 1024 {
            return String(format: "%.1f MB/s", Double(kilobytesPerSecond) / 1024)
        }
        return "\(kilobytesPerSecond) KB/s"
    }
}

private extension PlaybackEnvironment.NetworkClass {
    var diagnosticTitle: String {
        switch self {
        case .wifi:
            return "Wi-Fi"
        case .cellular:
            return "蜂窝网络"
        case .constrained:
            return "受限网络"
        case .unknown:
            return "未知"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
