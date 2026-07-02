import SwiftUI

struct MinePlaybackPreferenceSection<ProbeSummary: View>: View {
    @ObservedObject var libraryStore: LibraryStore
    let playbackPreferenceSummary: AnyView
    let playbackCDNProbeRefreshIntervalTitle: String
    let isProbingPlaybackCDN: Bool
    let playbackCDNProbeMessage: String?
    let probePlaybackCDN: () -> Void
    @Binding var showsAdvancedPlaybackSettings: Bool
    @Binding var playbackCustomCDNHostDraft: String
    let commitPlaybackCustomCDNHost: () -> Void
    @ViewBuilder let probeSummary: () -> ProbeSummary

    var body: some View {
        Section {
            playbackPreferenceSummary
            playbackAutoOptimizationPicker
            pictureInPictureToggle
            preferredVideoQualityPicker
            videoCodecPreferencePicker
            defaultPlaybackRatePicker
        } header: {
            Text("播放体验")
        } footer: {
            Text("默认保持智能播放加速开启，普通观看不需要调整高级线路。")
        }

        Section {
            advancedPlaybackSettingsToggle
            if showsAdvancedPlaybackSettings {
                playbackStreamSourcePicker
                playbackCDNPicker
                playbackCustomCDNHostEditor
                playbackCDNProbeRefreshPolicyPicker
                playbackCDNProbeRefreshPolicyDetail
                playbackNetworkAddressFamilyPicker
                playbackNetworkAddressFamilyNotice
                playbackCDNProbeButton
                playbackCDNProbeMessageText
                probeSummary()
            } else {
                advancedPlaybackSummary
            }
        } header: {
            Text("高级播放设置")
        } footer: {
            Text(showsAdvancedPlaybackSettings ? "高级选项会影响播放线路、取流来源和诊断信息；不确定时保持自动即可。" : "遇到地区网络异常或需要诊断时再打开。")
        }
    }

    private var advancedPlaybackSettingsToggle: some View {
        Toggle(isOn: $showsAdvancedPlaybackSettings) {
            Label("显示高级选项", systemImage: "slider.horizontal.3")
        }
        .animation(.easeInOut(duration: 0.2), value: showsAdvancedPlaybackSettings)
    }

    private var advancedPlaybackSummary: some View {
        HStack(spacing: 8) {
            Label("当前线路", systemImage: "network")
            Spacer(minLength: 8)
            Text(advancedPlaybackSummaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }

    private var advancedPlaybackSummaryText: String {
        let cdnTitle = libraryStore.playbackCDNPreference == .automatic
            ? "智能选择"
            : libraryStore.playbackCDNPreference.title
        let networkTitle = libraryStore.playbackNetworkAddressFamilyPreference == .automatic
            ? "自动网络"
            : libraryStore.playbackNetworkAddressFamilyPreference.title
        return "\(cdnTitle) · \(networkTitle)"
    }

    private var playbackAutoOptimizationPicker: some View {
        Picker(selection: Binding(
            get: { libraryStore.playbackAutoOptimizationMode },
            set: { libraryStore.setPlaybackAutoOptimizationMode($0) }
        )) {
            ForEach(PlaybackAutoOptimizationMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        } label: {
            Label("智能播放加速", systemImage: "wand.and.stars")
        }
        .pickerStyle(.navigationLink)
    }

    private var pictureInPictureToggle: some View {
        Toggle(isOn: Binding(
            get: { libraryStore.pictureInPictureEnabled },
            set: { libraryStore.setPictureInPictureEnabled($0) }
        )) {
            Label("画中画播放", systemImage: "pip")
        }
    }

    private var preferredVideoQualityPicker: some View {
        Picker(selection: Binding<Int>(
            get: { libraryStore.preferredVideoQuality ?? 0 },
            set: { libraryStore.setPreferredVideoQuality($0 == 0 ? nil : $0) }
        )) {
            Text(LibraryStore.videoQualityTitle(nil)).tag(0)
            ForEach(LibraryStore.supportedVideoQualities, id: \.self) { quality in
                Text(LibraryStore.videoQualityTitle(quality)).tag(quality)
            }
        } label: {
            Label("默认画质", systemImage: "play.rectangle")
        }
        .pickerStyle(.navigationLink)
    }

    private var videoCodecPreferencePicker: some View {
        Picker(selection: Binding(
            get: { libraryStore.videoCodecPreference },
            set: { libraryStore.setVideoCodecPreference($0) }
        )) {
            ForEach(VideoCodecPreference.allCases) { preference in
                Text(preference.title).tag(preference)
            }
        } label: {
            Label("首选编码", systemImage: "film.stack")
        }
        .pickerStyle(.navigationLink)
    }

    private var playbackStreamSourcePicker: some View {
        Picker(selection: Binding(
            get: { libraryStore.playbackStreamSourcePreference },
            set: { libraryStore.setPlaybackStreamSourcePreference($0) }
        )) {
            ForEach(PlaybackStreamSourcePreference.allCases) { source in
                Text(source.title).tag(source)
            }
        } label: {
            Label("播放取流来源", systemImage: "antenna.radiowaves.left.and.right")
        }
        .pickerStyle(.navigationLink)
    }

    private var playbackCDNPicker: some View {
        Picker(selection: Binding(
            get: { libraryStore.playbackCDNPreference },
            set: { libraryStore.setPlaybackCDNPreference($0) }
        )) {
            ForEach(PlaybackCDNPreference.allCases) { preference in
                Text(preference.title).tag(preference)
            }
        } label: {
            Label("CDN 线路", systemImage: "network")
        }
        .pickerStyle(.navigationLink)
    }

    @ViewBuilder
    private var playbackCustomCDNHostEditor: some View {
        if libraryStore.playbackCDNPreference == .custom {
            TextField(
                "upos-sz-mirrorali.bilivideo.com",
                text: $playbackCustomCDNHostDraft
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .onSubmit(commitPlaybackCustomCDNHost)

            if let normalizedCustomCDNHost {
                LabeledContent("自定义 Host", value: normalizedCustomCDNHost)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !playbackCustomCDNHostDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label("Host 格式无效", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button(action: commitPlaybackCustomCDNHost) {
                Label("应用自定义 CDN", systemImage: "checkmark.circle")
            }
            .disabled(isCustomCDNHostDraftInvalid)
        }
    }

    private var normalizedCustomCDNHost: String? {
        PlaybackCDNPreference.normalizedCustomHost(playbackCustomCDNHostDraft)
    }

    private var isCustomCDNHostDraftInvalid: Bool {
        let trimmedHost = playbackCustomCDNHostDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedHost.isEmpty && normalizedCustomCDNHost == nil
    }

    private var playbackCDNProbeRefreshPolicyPicker: some View {
        Picker(selection: Binding(
            get: { libraryStore.playbackCDNProbeRefreshPolicy },
            set: { libraryStore.setPlaybackCDNProbeRefreshPolicy($0) }
        )) {
            ForEach(PlaybackCDNProbeRefreshPolicy.allCases) { policy in
                Text(policy.title).tag(policy)
            }
        } label: {
            Label("CDN 自动测速", systemImage: "arrow.triangle.2.circlepath")
        }
        .pickerStyle(.navigationLink)
    }

    @ViewBuilder
    private var playbackCDNProbeRefreshPolicyDetail: some View {
        if libraryStore.playbackCDNProbeRefreshPolicy == .interval {
            Stepper(
                value: Binding(
                    get: { libraryStore.playbackCDNProbeRefreshIntervalMinutes },
                    set: { libraryStore.setPlaybackCDNProbeRefreshIntervalMinutes($0) }
                ),
                in: LibraryStore.playbackCDNProbeRefreshIntervalRange,
                step: 15
            ) {
                Label(
                    "测速间隔 \(playbackCDNProbeRefreshIntervalTitle)",
                    systemImage: "timer"
                )
            }
        } else {
            Label("App 启动或回到前台时会刷新 CDN 参考；没有真实播放地址时只做 Host 弱参考，不更新自动推荐。", systemImage: "bolt.horizontal")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var playbackNetworkAddressFamilyPicker: some View {
        Picker(selection: Binding(
            get: { libraryStore.playbackNetworkAddressFamilyPreference },
            set: { libraryStore.setPlaybackNetworkAddressFamilyPreference($0) }
        )) {
            ForEach(PlaybackNetworkAddressFamilyPreference.allCases) { preference in
                Text(preference.title).tag(preference)
            }
        } label: {
            Label("网络协议", systemImage: "point.3.connected.trianglepath.dotted")
        }
        .pickerStyle(.navigationLink)
    }

    @ViewBuilder
    private var playbackNetworkAddressFamilyNotice: some View {
        if libraryStore.playbackNetworkAddressFamilyPreference != .automatic,
           libraryStore.playbackCDNProbeSnapshotForCurrentContext == nil {
            Label("网络协议已切换，请重新测速 CDN 以生成匹配的新参考。", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private var playbackCDNProbeButton: some View {
        Button(action: probePlaybackCDN) {
            Label(isProbingPlaybackCDN ? "测速中" : "测试 CDN 连通性", systemImage: "speedometer")
        }
        .disabled(isProbingPlaybackCDN)
    }

    @ViewBuilder
    private var playbackCDNProbeMessageText: some View {
        if let playbackCDNProbeMessage {
            Text(playbackCDNProbeMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var defaultPlaybackRatePicker: some View {
        Picker(selection: Binding(
            get: { libraryStore.defaultPlaybackRate },
            set: { libraryStore.setDefaultPlaybackRate($0) }
        )) {
            ForEach(BiliPlaybackRate.allCases) { rate in
                Text(rate.title).tag(rate.rawValue)
            }
        } label: {
            Label("默认倍速", systemImage: "speedometer")
        }
        .pickerStyle(.navigationLink)
    }
}
