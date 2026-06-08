import Combine
import SwiftUI

struct MineView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var libraryStore: LibraryStore
    @StateObject private var holder = MineViewModelHolder()
    @State private var loginSheet: LoginSheet?
    @State private var isProbingPlaybackCDN = false
    @State private var playbackCDNProbeResults: [PlaybackCDNProbeResult] = []
    @State private var playbackCDNProbeMessage: String?
    @State private var playbackCDNProbeTask: Task<Void, Never>?
    @State private var isShowingPlaybackCDNProbeDetails = false
    @State private var playbackURLPreferenceSnapshots: [PlaybackURLPreferenceSnapshot] = []
    @State private var isShowingPlaybackURLPreferenceDetails = false

    var body: some View {
        Group {
            if let viewModel = holder.viewModel {
                content(viewModel)
            } else {
                ProgressView()
                    .task {
                        holder.configure(api: dependencies.api, sessionStore: sessionStore)
                    }
            }
        }
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.inline)
        .nativeTopNavigationChrome()
        .sheet(item: $loginSheet) { sheet in
            if let viewModel = holder.viewModel {
                switch sheet {
                case .web:
                    BiliWebLoginView { cookies in
                        Task {
                            await viewModel.completeWebLogin(with: cookies)
                            loginSheet = nil
                        }
                    }
                case .qrCode:
                    QRCodeLoginView(viewModel: viewModel)
                }
            }
        }
        .onDisappear {
            playbackCDNProbeTask?.cancel()
            playbackCDNProbeTask = nil
            isProbingPlaybackCDN = false
        }
        .task {
            refreshPlaybackURLPreferenceSnapshots()
            refreshPlaybackCDNProbeIfNeeded()
        }
        .navigationDestination(for: AccountLibraryKind.self) { kind in
            if let viewModel = holder.viewModel {
                AccountLibraryListPage(kind: kind, viewModel: viewModel)
            }
        }
    }

    private func probePlaybackCDN() {
        startPlaybackCDNProbe(isAutomatic: false)
    }

    private func refreshPlaybackCDNProbeIfNeeded() {
        guard playbackCDNProbeTask == nil else { return }
        guard libraryStore.needsPlaybackCDNProbeRefresh else { return }
        startPlaybackCDNProbe(isAutomatic: true)
    }

    private func startPlaybackCDNProbe(isAutomatic: Bool) {
        guard !isProbingPlaybackCDN else { return }
        isProbingPlaybackCDN = true
        playbackCDNProbeMessage = isAutomatic ? "CDN 测速已过期，正在自动刷新..." : "正在测试 CDN 线路..."
        if !isAutomatic {
            playbackCDNProbeResults = []
        }

        playbackCDNProbeTask?.cancel()
        playbackCDNProbeTask = Task {
            let addressFamilyPreference = await MainActor.run {
                libraryStore.playbackNetworkAddressFamilyPreference
            }
            let snapshot = await PlaybackCDNProbeService.recommendedSnapshot(
                addressFamilyPreference: addressFamilyPreference
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                playbackCDNProbeResults = snapshot.results
                libraryStore.setPlaybackCDNProbeSnapshot(snapshot)
                if let preference = snapshot.recommendedPreference,
                   let elapsed = snapshot.result(for: preference)?.elapsedMilliseconds {
                    if !isAutomatic {
                        libraryStore.setPlaybackCDNPreference(preference)
                    }
                    playbackCDNProbeMessage = isAutomatic
                        ? "已自动刷新 CDN：\(preference.title)，\(elapsed) ms"
                        : "已推荐 \(preference.title)，\(elapsed) ms"
                } else {
                    playbackCDNProbeMessage = "未找到可用 CDN，已保留当前设置"
                }
                refreshPlaybackURLPreferenceSnapshots()
                isProbingPlaybackCDN = false
                playbackCDNProbeTask = nil
            }
        }
    }

    private func refreshPlaybackURLPreferenceSnapshots() {
        playbackURLPreferenceSnapshots = PlaybackURLPreferenceStore.shared.rankedSnapshots(limit: 8)
    }

    private var activePlaybackCDNProbeSnapshot: PlaybackCDNProbeSnapshot? {
        if !playbackCDNProbeResults.isEmpty {
            return PlaybackCDNProbeSnapshot(
                probedAt: Date(),
                recommendedPreference: playbackCDNProbeResults.first {
                    $0.didSucceed && $0.elapsedMilliseconds != nil
                }?.preference,
                results: playbackCDNProbeResults
            )
        }
        return libraryStore.playbackCDNProbeSnapshotForCurrentContext
    }

    @ViewBuilder
    private var playbackCDNProbeSummary: some View {
        if let snapshot = activePlaybackCDNProbeSnapshot {
            VStack(alignment: .leading, spacing: 8) {
                if let recommendation = snapshot.recommendedPreference,
                   let result = snapshot.result(for: recommendation),
                   let elapsed = result.elapsedMilliseconds {
                    HStack {
                        Label(recommendation.title, systemImage: "checkmark.seal")
                        Spacer()
                        Text("\(elapsed) ms")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Text("上次测速 \(snapshot.probedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(snapshot.isExpired() ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))

                if libraryStore.playbackCDNPreference == .automatic,
                   let activeRecommendation = libraryStore.automaticPlaybackCDNRecommendation {
                    Label("测速参考 \(activeRecommendation.title)", systemImage: "bolt.horizontal")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if libraryStore.playbackNetworkAddressFamilyPreference != .automatic {
                    Label("协议偏好 \(libraryStore.playbackNetworkAddressFamilyPreference.title)", systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if snapshot.isExpired() {
                    Label("CDN 测速结果已超过 24 小时，建议重新测速", systemImage: "clock.badge.exclamationmark")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                DisclosureGroup(isExpanded: $isShowingPlaybackCDNProbeDetails) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(snapshot.results) { result in
                            playbackCDNProbeResultRow(result)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Label("CDN 测速排行", systemImage: "list.number")
                        .font(.caption)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func playbackCDNProbeResultRow(_ result: PlaybackCDNProbeResult) -> some View {
        HStack {
            Text(result.preference.title)
                .lineLimit(1)
            Spacer()
            if let elapsed = result.elapsedMilliseconds {
                Text("\(elapsed) ms")
                    .monospacedDigit()
            } else {
                Text(result.errorDescription ?? "失败")
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(result.didSucceed ? .secondary : .tertiary)
    }

    @ViewBuilder
    private func content(_ viewModel: MineViewModel) -> some View {
        Form {
            Section {
                if sessionStore.isLoggedIn {
                    loggedInHeader
                    Button(role: .destructive) {
                        viewModel.logout()
                    } label: {
                        Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } else {
                    loginPanel(viewModel)
                }
            }

            accountLibrarySection(viewModel)

            Section("显示") {
                Picker(selection: Binding(
                    get: { libraryStore.appearanceMode },
                    set: { libraryStore.setAppearanceMode($0) }
                )) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                } label: {
                    Label("外观", systemImage: "circle.lefthalf.filled")
                }

                Picker(selection: Binding(
                    get: { libraryStore.homeFeedLayout },
                    set: { libraryStore.setHomeFeedLayout($0) }
                )) {
                    ForEach(HomeFeedLayout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                } label: {
                    Label("首页布局", systemImage: "rectangle.grid.1x2")
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.minimizesTabBarOnScroll },
                    set: { libraryStore.setMinimizesTabBarOnScroll($0) }
                )) {
                    Label("滑动时缩小底部 Tab", systemImage: "arrow.down.right.and.arrow.up.left")
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("首页下拉刷新距离", systemImage: "arrow.down.circle")
                        Spacer()
                        Text("\(Int(libraryStore.homeRefreshTriggerDistance)) pt")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { libraryStore.homeRefreshTriggerDistance },
                            set: { libraryStore.setHomeRefreshTriggerDistance($0) }
                        ),
                        in: LibraryStore.homeRefreshDistanceRange,
                        step: 5
                    ) {
                        Text("首页下拉刷新距离")
                    } minimumValueLabel: {
                        Text("近")
                    } maximumValueLabel: {
                        Text("远")
                    }

                    HStack {
                        Text("下拉达到设定距离后会刷新推荐内容。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 12)
                        Button("默认") {
                            libraryStore.setHomeRefreshTriggerDistance(
                                LibraryStore.defaultHomeRefreshTriggerDistance
                            )
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Section {
                playbackPreferenceSummary

                Picker(selection: Binding(
                    get: { libraryStore.playbackAutoOptimizationMode },
                    set: { libraryStore.setPlaybackAutoOptimizationMode($0) }
                )) {
                    ForEach(PlaybackAutoOptimizationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                } label: {
                    Label("播放自动优化", systemImage: "wand.and.stars")
                }
                .pickerStyle(.navigationLink)

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

                if libraryStore.playbackNetworkAddressFamilyPreference != .automatic,
                   libraryStore.playbackCDNProbeSnapshotForCurrentContext == nil {
                    Label("网络协议已切换，请重新测速 CDN 以生成匹配的新参考。", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Button {
                    probePlaybackCDN()
                } label: {
                    Label(isProbingPlaybackCDN ? "测速中" : "测速并推荐 CDN", systemImage: "speedometer")
                }
                .disabled(isProbingPlaybackCDN)

                if let playbackCDNProbeMessage {
                    Text(playbackCDNProbeMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                playbackCDNProbeSummary
                playbackURLPreferenceSummary

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

                Toggle(isOn: Binding(
                    get: { libraryStore.sponsorBlockEnabled },
                    set: { libraryStore.setSponsorBlockEnabled($0) }
                )) {
                    Label("空降助手", systemImage: "forward.end")
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.playerPerformanceOverlayEnabled },
                    set: { libraryStore.setPlayerPerformanceOverlayEnabled($0) }
                )) {
                    Label("播放性能浮层", systemImage: "waveform.path.ecg.rectangle")
                }

                NavigationLink {
                    PlayerPerformanceLogView()
                } label: {
                    Label("播放性能日志", systemImage: "speedometer")
                }

                NavigationLink {
                    ResourceCacheManagementView()
                } label: {
                    Label("资源缓存", systemImage: "internaldrive")
                }
            } header: {
                Text("播放偏好")
            } footer: {
                Text("自动模式会优先保留接口下发的播放地址候选，再根据真实播放记录和启动探测微调排序。测速结果用于诊断和手动推荐；手动选择 CDN 或协议后，播放仍会保留备用地址作为回退。")
            }

            Section("内容过滤") {
                Toggle(isOn: Binding(
                    get: { libraryStore.blocksAdDynamics },
                    set: { libraryStore.setBlocksAdDynamics($0) }
                )) {
                    Label("屏蔽广告动态", systemImage: "megaphone.badge.minus")
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.blocksGoodsDynamics },
                    set: { libraryStore.setBlocksGoodsDynamics($0) }
                )) {
                    Label("屏蔽带货动态", systemImage: "bag.badge.minus")
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.blocksGoodsComments },
                    set: { libraryStore.setBlocksGoodsComments($0) }
                )) {
                    Label("屏蔽带货评论", systemImage: "text.bubble.badge.minus")
                }

                NavigationLink {
                    DynamicKeywordFilterSettingsView(libraryStore: libraryStore)
                } label: {
                    HStack {
                        Label("自定义动态关键词", systemImage: "line.3.horizontal.decrease.circle")
                        Spacer()
                        Text("\(libraryStore.blockedDynamicKeywords.count) 个")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("广告动态会按常见推广关键词过滤；带货动态会按 B 站商品组件和商品元数据过滤；自定义关键词会匹配动态正文、标题和转发内容。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("隐私") {
                Toggle(isOn: Binding(
                    get: { libraryStore.incognitoModeEnabled },
                    set: { libraryStore.setIncognitoModeEnabled($0) }
                )) {
                    Label("无痕模式", systemImage: "eye.slash")
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.guestModeEnabled },
                    set: { libraryStore.setGuestModeEnabled($0) }
                )) {
                    Label("游客模式", systemImage: "person.crop.circle.badge.questionmark")
                }

                Text("无痕模式下播放取流仍使用账号信息，但不会上报观看进度到云端历史。游客模式会让首页推荐流按未登录状态请求，不使用账号数据生成推荐。点赞、投币、收藏、关注等账号操作不受影响。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .nativeTopScrollEdgeEffect()
        .task {
            refreshPlaybackURLPreferenceSnapshots()
            await viewModel.refreshUser()
        }
    }

    @ViewBuilder
    private var playbackURLPreferenceSummary: some View {
        if let bestSnapshot = playbackURLPreferenceSnapshots.first {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label("真实播放优先", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(bestSnapshot.host)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text("根据 AVPlayer 实际码率、传输耗时和新增 stall，在接口候选地址内自动修正 CDN Host 排序。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                DisclosureGroup(isExpanded: $isShowingPlaybackURLPreferenceDetails) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(playbackURLPreferenceSnapshots) { snapshot in
                            playbackURLPreferenceSnapshotRow(snapshot)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Label("真实播放排行", systemImage: "list.bullet.rectangle")
                        .font(.caption)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func playbackURLPreferenceSnapshotRow(_ snapshot: PlaybackURLPreferenceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(snapshot.host)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(snapshot.averageMilliseconds) ms")
                    .font(.caption.monospacedDigit())
            }

            HStack(spacing: 8) {
                Text(snapshot.networkTitle)
                Text(playbackURLThroughputText(snapshot.averageKilobytesPerSecond))
                Text("失败 \(snapshot.failureRatePercent)%")
                Text("\(snapshot.attemptCount) 样本")
            }
            .font(.caption2)
            .foregroundStyle(snapshot.failureCount > 0 ? .orange : .secondary)
            .lineLimit(1)

            Text("最近 \(snapshot.lastUpdatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }

    private func playbackURLThroughputText(_ kilobytesPerSecond: Int) -> String {
        guard kilobytesPerSecond > 0 else { return "吞吐 -" }
        if kilobytesPerSecond >= 1024 {
            return String(format: "%.1f MB/s", Double(kilobytesPerSecond) / 1024)
        }
        return "\(kilobytesPerSecond) KB/s"
    }

    private var playbackPreferenceSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("当前策略", systemImage: "wand.and.stars")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(libraryStore.playbackAutoOptimizationMode.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(libraryStore.playbackAutoOptimizationMode.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                MinePlaybackPreferenceChip(
                    title: LibraryStore.videoQualityTitle(libraryStore.preferredVideoQuality),
                    systemImage: "play.rectangle"
                )
                MinePlaybackPreferenceChip(
                    title: libraryStore.playbackCDNPreference.title,
                    systemImage: "network"
                )
                MinePlaybackPreferenceChip(
                    title: libraryStore.playbackNetworkAddressFamilyPreference.title,
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
            }
        }
        .padding(.vertical, 4)
    }

    private func accountLibrarySection(_ viewModel: MineViewModel) -> some View {
        Section {
            LazyVGrid(columns: [
                GridItem(.flexible(minimum: 0), spacing: 10),
                GridItem(.flexible(minimum: 0), spacing: 10)
            ], spacing: 10) {
                NavigationLink(value: AccountLibraryKind.history) {
                    AccountLibraryQuickEntry(
                        title: "观看记录",
                        systemImage: "clock.arrow.circlepath",
                        status: libraryStatusText(
                            isLoggedIn: sessionStore.isLoggedIn,
                            state: viewModel.historyState,
                            count: viewModel.accountHistory.count,
                            emptyTitle: "暂无记录"
                        )
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(value: AccountLibraryKind.favorites) {
                    AccountLibraryQuickEntry(
                        title: "账号收藏",
                        systemImage: "star",
                        status: libraryStatusText(
                            isLoggedIn: sessionStore.isLoggedIn,
                            state: viewModel.favoriteState,
                            count: viewModel.favoriteFolders.count,
                            emptyTitle: "暂无收藏"
                        )
                    )
                }
                .buttonStyle(.plain)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        } header: {
            Text("账号内容")
        }
    }

    private func libraryStatusText(isLoggedIn: Bool, state: LoadingState, count: Int, emptyTitle: String) -> String {
        guard isLoggedIn else { return "登录后同步" }
        if state.isLoading, count == 0 { return "同步中" }
        if case .failed = state, count == 0 { return "同步失败" }
        if count == 0 { return emptyTitle }
        return "\(count) 条"
    }

    private var loggedInHeader: some View {
        HStack(spacing: 12) {
            AvatarRemoteImage(urlString: sessionStore.user?.face, pixelSize: 128) {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(sessionStore.user?.uname ?? "Logged in")
                    .font(.headline)
                Text("UID \(sessionStore.user?.mid ?? 0)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func loginPanel(_ viewModel: MineViewModel) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "globe")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.pink)

            Text(viewModel.loginMessage.isEmpty ? "使用 B 站扫码或网页登录，登录后会自动保存 Cookie。" : viewModel.loginMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                Button {
                    loginSheet = .qrCode
                } label: {
                    Label("扫码登录", systemImage: "qrcode")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.pink)

                Button {
                    loginSheet = .web
                } label: {
                    Label("网页登录", systemImage: "person.crop.circle.badge.checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
    }
}

private enum LoginSheet: Identifiable, Hashable {
    case qrCode
    case web

    var id: Self { self }
}

private struct LibraryVideoRow: View {
    let item: AccountVideoEntry
    let timestampTitle: String

    var body: some View {
        HStack(spacing: 10) {
            let sourceURLString = item.pic?.normalizedBiliURL()
            CachedRemoteImage(
                url: sourceURLString.flatMap { URL(string: $0.biliCoverThumbnailURL(width: 288, height: 180)) },
                fallbackURL: sourceURLString.flatMap(URL.init(string:)),
                targetPixelSize: 288
            ) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.gray.opacity(0.14)
            }
            .frame(width: 92, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .mediaShadow(.subtle)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                if let ownerName = item.owner?.name, !ownerName.isEmpty {
                    Text(ownerName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Label(BiliFormatters.compactCount(item.stat?.view), systemImage: "play.rectangle")
                    Text("\(timestampTitle) \(item.savedAt.formatted(date: .numeric, time: .shortened))")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if let resumeTime = item.resumeTime {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("看到 \(BiliFormatters.duration(Int(resumeTime)))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.pink)

                        if let progress = item.playbackProgress {
                            ProgressView(value: progress)
                                .tint(.pink)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }
}

private struct FavoriteFolderRow: View {
    let folder: FavoriteFolder

    var body: some View {
        HStack(spacing: 10) {
            folderCover

            VStack(alignment: .leading, spacing: 4) {
                Text(folder.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Label("\(folder.mediaCount ?? 0) 个内容", systemImage: "play.rectangle.stack")
                    if folder.isFavorited {
                        Label("已收藏当前视频", systemImage: "star.fill")
                            .foregroundStyle(.pink)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if let intro = folder.intro?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !intro.isEmpty {
                    Text(intro)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var folderCover: some View {
        if let cover = folder.cover?.normalizedBiliURL(),
           let url = URL(string: cover.biliCoverThumbnailURL(width: 240, height: 240)) {
            CachedRemoteImage(url: url, fallbackURL: URL(string: cover), targetPixelSize: 240) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                folderPlaceholder
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .mediaShadow(.subtle)
        } else {
            folderPlaceholder
        }
    }

    private var folderPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.pink.opacity(0.12))
            .frame(width: 54, height: 54)
            .overlay {
                Image(systemName: "folder.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.pink)
            }
    }
}

private enum AccountLibraryKind: Hashable, Identifiable {
    case history
    case favorites

    var id: Self { self }

    var title: String {
        switch self {
        case .history:
            return "观看记录"
        case .favorites:
            return "账号收藏"
        }
    }

    var systemImage: String {
        switch self {
        case .history:
            return "clock.arrow.circlepath"
        case .favorites:
            return "star"
        }
    }

    var timestampTitle: String {
        switch self {
        case .history:
            return "最近观看"
        case .favorites:
            return "收藏时间"
        }
    }

    var emptyTitle: String {
        switch self {
        case .history:
            return "账号里还没有观看记录"
        case .favorites:
            return "账号收藏夹还没有内容"
        }
    }

    var loggedOutTitle: String {
        switch self {
        case .history:
            return "登录后同步账号观看记录"
        case .favorites:
            return "登录后同步账号收藏"
        }
    }

    var loadingTitle: String {
        switch self {
        case .history:
            return "正在同步观看记录"
        case .favorites:
            return "正在同步账号收藏"
        }
    }

    var errorTitle: String {
        switch self {
        case .history:
            return "观看记录同步失败"
        case .favorites:
            return "账号收藏同步失败"
        }
    }
}

private struct AccountLibraryQuickEntry: View {
    let title: String
    let systemImage: String
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.pink)
                .frame(width: 28, height: 28)
                .background(.pink.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.10), lineWidth: 0.5)
        }
    }
}

private struct MinePlaybackPreferenceChip: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color(uiColor: .separator).opacity(0.10), lineWidth: 0.5)
            }
    }
}

private struct AccountLibraryListPage: View {
    let kind: AccountLibraryKind
    @ObservedObject var viewModel: MineViewModel
    @EnvironmentObject private var sessionStore: SessionStore

    var body: some View {
        List {
            Section {
                content
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(!sessionStore.isLoggedIn || state.isLoading)
            }
        }
        .task {
            await loadIfNeeded()
        }
        .refreshable {
            await reload()
        }
    }

    @ViewBuilder
    private var content: some View {
        if !sessionStore.isLoggedIn {
            LibraryEmptyRow(title: kind.loggedOutTitle, systemImage: kind.systemImage)
        } else if items.isEmpty && state.isLoading {
            LibraryLoadingRow(title: kind.loadingTitle)
        } else if items.isEmpty, case .failed(let message) = state {
            LibraryErrorRow(title: kind.errorTitle, message: message) {
                Task { await reload() }
            }
        } else if kind == .favorites {
            favoriteFolderContent
        } else if items.isEmpty {
            LibraryEmptyRow(title: kind.emptyTitle, systemImage: kind.systemImage)
        } else {
            ForEach(items) { item in
                VideoRouteLink(item.videoItem) {
                    LibraryVideoRow(item: item, timestampTitle: kind.timestampTitle)
                }
            }

            if state.isLoading {
                LibraryLoadingRow(title: kind.loadingTitle)
            } else if case .failed(let message) = state {
                LibraryErrorRow(title: kind.errorTitle, message: message) {
                    Task { await reload() }
                }
            }
        }
    }

    @ViewBuilder
    private var favoriteFolderContent: some View {
        if favoriteFolders.isEmpty {
            LibraryEmptyRow(title: kind.emptyTitle, systemImage: kind.systemImage)
        } else {
            ForEach(favoriteFolders) { folder in
                NavigationLink {
                    FavoriteFolderContentPage(folder: folder, viewModel: viewModel)
                } label: {
                    FavoriteFolderRow(folder: folder)
                }
            }
        }
    }

    private var items: [AccountVideoEntry] {
        switch kind {
        case .history:
            return viewModel.accountHistory
        case .favorites:
            return viewModel.accountFavorites
        }
    }

    private var state: LoadingState {
        switch kind {
        case .history:
            return viewModel.historyState
        case .favorites:
            return viewModel.favoriteState
        }
    }

    private var favoriteFolders: [FavoriteFolder] {
        viewModel.favoriteFolders
    }

    private func loadIfNeeded() async {
        guard sessionStore.isLoggedIn, items.isEmpty, !state.isLoading else { return }
        await reload()
    }

    private func reload() async {
        switch kind {
        case .history:
            await viewModel.refreshHistory()
        case .favorites:
            await viewModel.refreshFavorites()
        }
    }
}

private struct FavoriteFolderContentPage: View {
    let folder: FavoriteFolder
    @ObservedObject var viewModel: MineViewModel
    @EnvironmentObject private var sessionStore: SessionStore

    var body: some View {
        List {
            Section {
                content
            } header: {
                if let count = folder.mediaCount {
                    Text("\(count) 个内容")
                }
            }
        }
        .navigationTitle(folder.displayTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(!sessionStore.isLoggedIn || state.isLoading)
            }
        }
        .task {
            await loadIfNeeded()
        }
        .refreshable {
            await reload()
        }
    }

    @ViewBuilder
    private var content: some View {
        if !sessionStore.isLoggedIn {
            LibraryEmptyRow(title: "登录后同步账号收藏", systemImage: "star")
        } else if items.isEmpty && state.isLoading {
            LibraryLoadingRow(title: "正在同步收藏夹")
        } else if items.isEmpty, case .failed(let message) = state {
            LibraryErrorRow(title: "收藏夹同步失败", message: message) {
                Task { await reload() }
            }
        } else if items.isEmpty {
            LibraryEmptyRow(title: "这个收藏夹还没有视频", systemImage: "folder")
        } else {
            ForEach(items) { item in
                VideoRouteLink(item.videoItem) {
                    LibraryVideoRow(item: item, timestampTitle: "收藏时间")
                }
            }

            if state.isLoading {
                LibraryLoadingRow(title: "正在同步收藏夹")
            } else if case .failed(let message) = state {
                LibraryErrorRow(title: "收藏夹同步失败", message: message) {
                    Task { await reload() }
                }
            }
        }
    }

    private var items: [AccountVideoEntry] {
        viewModel.favoriteFolderEntries[folder.id] ?? []
    }

    private var state: LoadingState {
        viewModel.favoriteFolderEntryStates[folder.id] ?? .idle
    }

    private func loadIfNeeded() async {
        guard sessionStore.isLoggedIn, items.isEmpty, !state.isLoading else { return }
        await reload()
    }

    private func reload() async {
        await viewModel.refreshFavoriteFolder(folder)
    }
}

private struct LibraryEmptyRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
    }
}

private struct LibraryLoadingRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

private struct LibraryErrorRow: View {
    let title: String
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "exclamationmark.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Button(action: retry) {
                Label("重试", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 6)
    }
}

private struct PlayerPerformanceLogView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @StateObject private var store = PlayerPerformanceStore.shared

    var body: some View {
        List {
            if store.events.isEmpty && store.sessions.isEmpty {
                ContentUnavailableView(
                    "暂无播放记录",
                    systemImage: "speedometer",
                    description: Text("播放自动优化会在后台使用这些记录调整开播画质、预加载和 CDN 复测。")
                )
            } else {
                Section("自动优化") {
                    PlayerAutoOptimizationSummaryRow(
                        profile: store.playbackAdaptationProfile(
                            isEnabled: libraryStore.isPlaybackAutoOptimizationEnabled
                        )
                    )
                }

                let sampleGroups = store.startupSampleGroups()
                if !sampleGroups.isEmpty {
                    Section("启动样本") {
                        ForEach(Array(sampleGroups.enumerated()), id: \.element.id) { index, group in
                            PlayerPerformanceSampleGroupRow(group: group, isRecommended: index == 0)
                        }
                    }
                }

                if !store.sessions.isEmpty {
                    let exceptionSessions = store.sessions.filter {
                        $0.failureMessage != nil
                            || $0.bufferCount >= 2
                            || $0.seekCount >= 12
                            || $0.resumeRecoverySlowCount > 0
                            || $0.seekRecoverySlowCount > 0
                            || ($0.accessLogStallCount ?? 0) > 0
                    }
                    if !exceptionSessions.isEmpty {
                        Section("最近异常") {
                            ForEach(exceptionSessions.prefix(5)) { session in
                                PlayerPerformanceExceptionRow(session: session)
                            }
                        }
                    }

                    Section("最近视频") {
                        ForEach(store.sessions) { session in
                            PlayerPerformanceSessionRow(session: session)
                        }
                    }
                }

                Section {
                    ForEach(store.events.reversed()) { event in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Label(event.kind.title, systemImage: systemImage(for: event.kind))
                                    .font(.subheadline.weight(.semibold))
                                Spacer(minLength: 8)
                                Text(event.date, style: .time)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            if let title = event.title, !title.isEmpty {
                                Text(title)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                            }

                            HStack(spacing: 8) {
                                Text(event.metricsID)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)

                                if let message = event.message, !message.isEmpty {
                                    Text(message)
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("最近 \(store.events.count) 条")
                }
            }
        }
        .navigationTitle("播放性能")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("清空") {
                    store.clear()
                }
                .disabled(store.events.isEmpty)
            }
        }
    }

    private func systemImage(for kind: PlayerPerformanceEvent.Kind) -> String {
        switch kind {
        case .routeOpen: return "arrow.up.forward.app"
        case .detailLoadStart, .detailLoaded: return "doc.text.magnifyingglass"
        case .playURLStart, .playURLLoaded: return "link"
        case .playerCreated: return "play.rectangle"
        case .prepareRequested, .mediaPrepared, .prepareReturned: return "gearshape"
        case .playRequested: return "play.fill"
        case .firstFrame: return "bolt.fill"
        case .startupBreakdown: return "chart.bar.xaxis"
        case .buffering: return "hourglass"
        case .network: return "network"
        case .accessLog: return "dot.radiowaves.left.and.right"
        case .mediaCache: return "externaldrive.fill.badge.checkmark"
        case .manifestStage: return "waveform.path.ecg.rectangle"
        case .qualitySupplement: return "arrow.triangle.2.circlepath"
        case .resumeDecision: return "clock.arrow.circlepath"
        case .resumeRecovery: return "checkmark.circle"
        case .seek: return "forward.frame"
        case .seekRecovery: return "speedometer"
        case .speedBoost: return "forward.fill"
        case .failed: return "exclamationmark.triangle"
        }
    }
}

private struct ResourceCacheManagementView: View {
    @State private var summary: ResourceCacheSummary?
    @State private var isWorking = false

    var body: some View {
        List {
            Section("统计") {
                if let summary {
                    cacheRow("PlayURL", "\(summary.playURL.count)/\(summary.playURL.capacity)", "命中 \(summary.playURL.hits) · 未命中 \(summary.playURL.misses)")
                    cacheRow("图片", "\(summary.image.memoryEntryCount) 张", "磁盘 \(formatBytes(summary.image.diskUsage)) / \(formatBytes(summary.image.diskCapacity))")
                    cacheRow("API", formatBytes(summary.api.diskUsage), "内存 \(formatBytes(summary.api.memoryUsage))")
                    cacheRow("播放片段", "\(summary.progressiveMedia.entryCount) 段", "\(formatBytes(summary.progressiveMedia.estimatedBytes)) / \(formatBytes(summary.progressiveMedia.byteCapacity))")
                    cacheRow("字幕/弹幕", "\(summary.subtitlesAndDanmaku.subtitleCount + summary.subtitlesAndDanmaku.danmakuSegmentCount) 项", "\(formatBytes(summary.subtitlesAndDanmaku.estimatedBytes)) / \(formatBytes(summary.subtitlesAndDanmaku.byteCapacity))")
                } else {
                    ProgressView()
                }
            }

            Section("清理") {
                Button {
                    performClear {
                        await ResourceCacheCenter.clearPlayURL()
                    }
                } label: {
                    Label("清理播放源缓存", systemImage: "link.badge.minus")
                }

                Button {
                    performClear {
                        await ResourceCacheCenter.clearImages(includeDisk: true)
                    }
                } label: {
                    Label("清理图片缓存", systemImage: "photo.badge.arrow.down")
                }

                Button {
                    performClear {
                        await ResourceCacheCenter.clearAPI()
                    }
                } label: {
                    Label("清理 API 缓存", systemImage: "network.badge.shield.half.filled")
                }

                Button {
                    performClear {
                        await ResourceCacheCenter.clearProgressiveMedia()
                    }
                } label: {
                    Label("清理播放片段缓存", systemImage: "externaldrive.badge.minus")
                }

                Button {
                    performClear {
                        await ResourceCacheCenter.clearSubtitlesAndDanmaku()
                    }
                } label: {
                    Label("清理字幕/弹幕缓存", systemImage: "text.bubble")
                }

                Button(role: .destructive) {
                    performClear {
                        await ResourceCacheCenter.clearAll()
                    }
                } label: {
                    Label("清理全部资源缓存", systemImage: "trash")
                }
            }
        }
        .navigationTitle("资源缓存")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isWorking)
        .task {
            await reload()
        }
        .refreshable {
            await reload()
        }
    }

    private func cacheRow(_ title: String, _ value: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(value)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    private func performClear(_ operation: @escaping () async -> Void) {
        Task {
            isWorking = true
            await operation()
            await reload()
            isWorking = false
        }
    }

    private func reload() async {
        summary = await ResourceCacheCenter.summary()
    }

    private func formatBytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

private struct PlayerPerformanceSampleGroupRow: View {
    let group: PlayerPerformanceSampleGroup
    let isRecommended: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(group.title, systemImage: isRecommended ? "checkmark.seal.fill" : "chart.bar.xaxis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(headerColor)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if isRecommended {
                    Text("样本较优")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            Text(group.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                alignment: .leading,
                spacing: 8
            ) {
                metric("总首帧", milliseconds: group.averageFirstFrameMilliseconds, icon: "bolt.fill")
                metric("播放器首帧", milliseconds: group.averagePlayerFirstFrameMilliseconds, icon: "play.rectangle")
                metric("播放地址", milliseconds: group.averagePlayURLMilliseconds, icon: "link")
                metric("Prepare", milliseconds: group.averagePrepareMilliseconds, icon: "gearshape")
                metric("Seek 恢复", milliseconds: group.averageSeekRecoveryMilliseconds, icon: "speedometer")
                coverageMetric
                bitrateMetric
            }

            if group.issueCount > 0 {
                Text(issueSummary)
                    .font(.caption2)
                    .foregroundStyle(issueColor)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }

    private var coverageMetric: some View {
        HStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text("Seek 缓冲")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(coverageText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(coverageColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bitrateMetric: some View {
        HStack(spacing: 6) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text("实际码率")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(bitrateText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(bitrateColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(_ title: String, milliseconds: Int?, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(millisecondsText(milliseconds))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(metricColor(milliseconds))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerColor: Color {
        if group.failedCount > 0 || group.slowStartupCount > 1 || group.accessLogStallCount > 0 {
            return .orange
        }
        return isRecommended ? .green : .primary
    }

    private var issueColor: Color {
        group.failedCount > 0 ? .red : .orange
    }

    private var issueSummary: String {
        var parts: [String] = []
        if group.slowStartupCount > 0 {
            parts.append("慢启动 \(group.slowStartupCount)")
        }
        if group.failedCount > 0 {
            parts.append("失败 \(group.failedCount)")
        }
        if group.bufferCount > 0 {
            parts.append("缓冲 \(group.bufferCount)")
        }
        if group.seekRecoverySlowCount > 0 {
            parts.append("Seek 慢恢复 \(group.seekRecoverySlowCount)")
        }
        if group.accessLogStallCount > 0 {
            parts.append("系统 Stall \(group.accessLogStallCount)")
        }
        if group.speedBoostInterruptionCount > 0 {
            parts.append("倍速中断 \(group.speedBoostInterruptionCount)")
        }
        return parts.joined(separator: " · ")
    }

    private var coverageText: String {
        guard let coverage = group.averageSeekBufferReadyCoveragePercent else { return "-" }
        return "\(coverage)%"
    }

    private var coverageColor: Color {
        guard let coverage = group.averageSeekBufferReadyCoveragePercent else { return .secondary }
        if coverage < 70 {
            return .orange
        }
        return .green
    }

    private var bitrateText: String {
        guard let kbps = group.averageObservedBitrateKilobitsPerSecond, kbps > 0 else { return "-" }
        if kbps >= 1_000 {
            return String(format: "%.1fMbps", Double(kbps) / 1_000)
        }
        return "\(kbps)Kbps"
    }

    private var bitrateColor: Color {
        guard let kbps = group.averageObservedBitrateKilobitsPerSecond, kbps > 0 else { return .secondary }
        if kbps < 900 {
            return .orange
        }
        return .green
    }

    private func millisecondsText(_ value: Int?) -> String {
        guard let value else { return "-" }
        if value >= 1000 {
            return String(format: "%.2fs", Double(value) / 1000)
        }
        return "\(value)ms"
    }

    private func metricColor(_ value: Int?) -> Color {
        guard let value else { return .secondary }
        if value >= 2500 {
            return .red
        }
        if value >= 1400 {
            return .orange
        }
        return .green
    }
}

private struct PlayerAutoOptimizationSummaryRow: View {
    let profile: PlayerPlaybackAdaptationProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(profileTitle, systemImage: "wand.and.stars")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(profileColor)

            Text(profileMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var profileTitle: String {
        guard profile.isEnabled else {
            return "当前策略：已关闭"
        }
        switch profile.level {
        case .normal:
            return "当前策略：正常"
        case .fallback:
            return "当前策略：快速回退"
        case .cautious:
            return "当前策略：谨慎加载"
        case .slow:
            return "当前策略：慢网保护"
        }
    }

    private var profileMessage: String {
        guard profile.isEnabled else {
            return "不会根据历史表现自动调整画质、预加载或 CDN 复测。"
        }
        switch profile.level {
        case .normal:
            return "保持默认画质和正常预加载。"
        case .fallback:
            return "优先使用缓存回退，减少首屏等待。"
        case .cautious:
            return "降低开播画质上限并减少后台预加载。"
        case .slow:
            return "强制轻量开播，暂停非必要预热，并触发 CDN 复测。"
        }
    }

    private var profileColor: Color {
        guard profile.isEnabled else {
            return .secondary
        }
        switch profile.level {
        case .normal:
            return .green
        case .fallback:
            return .blue
        case .cautious:
            return .orange
        case .slow:
            return .red
        }
    }
}

private struct PlayerPerformanceSessionRow: View {
    let session: PlayerPerformanceSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(session.title ?? session.metricsID)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text(session.lastUpdatedAt, style: .time)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                alignment: .leading,
                spacing: 8
            ) {
                metric("总首帧", milliseconds: session.firstFrameTotalMilliseconds, icon: "bolt.fill")
                metric("播放器首帧", milliseconds: session.firstFramePlayerMilliseconds, icon: "play.rectangle")
                metric("详情", milliseconds: session.detailLoadMilliseconds, icon: "doc.text.magnifyingglass")
                metric("播放地址", milliseconds: session.playURLMilliseconds, icon: "link")
                metric("Prepare", milliseconds: session.prepareMilliseconds, icon: "gearshape")
                metric("续播 Seek", milliseconds: session.resumeApplyMilliseconds, icon: "clock.arrow.circlepath")
                metric("续播落点", milliseconds: session.lastResumeRecoveryMilliseconds, icon: "checkmark.circle")
            }

            HStack(spacing: 8) {
                Label("\(session.bufferCount) 次缓冲", systemImage: "hourglass")
                if session.resumeRecoveryCount > 0 {
                    Label("\(session.resumeRecoveryCount) 次续播验证", systemImage: "checkmark.circle")
                }
                if session.seekRecoveryCount > 0 {
                    Label("\(session.seekRecoveryCount) 次 Seek 恢复", systemImage: "speedometer")
                }
                if let detailSourceMessage = session.detailSourceMessage {
                    Text(detailSourceMessage)
                        .lineLimit(1)
                }
                if let selectedQualityMessage = session.selectedQualityMessage {
                    Text(selectedQualityMessage)
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle((session.bufferCount > 0 || session.resumeRecoverySlowCount > 0 || session.seekRecoverySlowCount > 0 || (session.accessLogStallCount ?? 0) > 0) ? .orange : .secondary)

            if let cdnHostMessage = session.cdnHostMessage {
                Label(cdnHostMessage, systemImage: "network")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let networkMessage = session.networkMessage {
                Text(networkMessage)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let accessLogMessage = session.accessLogMessage {
                Text(accessLogMessage)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle((session.accessLogStallCount ?? 0) > 0 ? .orange : .secondary)
                    .lineLimit(3)
            }

            if let mediaCacheMessage = session.mediaCacheMessage {
                Text(mediaCacheMessage)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let manifestStageMessage = session.manifestStageMessage {
                Text(manifestStageMessage)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if let prepareStageMessage = session.prepareStageMessage {
                Text(prepareStageMessage)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let qualitySupplementMessage = session.qualitySupplementMessage {
                Text(qualitySupplementMessage)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }

            if let resumeRecoveryMessage = session.resumeRecoveryMessage {
                Text(resumeRecoveryMessage)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(session.resumeRecoverySlowCount > 0 ? .orange : .secondary)
                    .lineLimit(3)
            }

            if let seekRecoveryMessage = session.seekRecoveryMessage {
                Text(seekRecoveryMessage)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(session.seekRecoverySlowCount > 0 ? .orange : .secondary)
                    .lineLimit(3)
            }

            if !session.timeline.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("时间线")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(session.timeline.suffix(6)) { entry in
                        Text(entry.compactDescription)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            if let failureMessage = session.failureMessage {
                Label(failureMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }

    private func metric(_ title: String, milliseconds: Int?, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(millisecondsText(milliseconds))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(metricColor(milliseconds))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func millisecondsText(_ value: Int?) -> String {
        guard let value else { return "-" }
        if value >= 1000 {
            return String(format: "%.2fs", Double(value) / 1000)
        }
        return "\(value)ms"
    }

    private func metricColor(_ value: Int?) -> Color {
        guard let value else { return .secondary }
        if value >= 2500 {
            return .red
        }
        if value >= 1400 {
            return .orange
        }
        return .green
    }
}

private struct PlayerPerformanceExceptionRow: View {
    let session: PlayerPerformanceSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label(session.title ?? session.metricsID, systemImage: exceptionIcon)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(session.lastUpdatedAt, style: .time)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(exceptionSummary)
                .font(.caption)
                .foregroundStyle(exceptionColor)
                .lineLimit(2)

            if let last = session.timeline.last {
                Text(last.compactDescription)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var exceptionIcon: String {
        if session.failureMessage != nil { return "exclamationmark.triangle" }
        if session.bufferCount >= 2 { return "hourglass" }
        if session.resumeRecoverySlowCount > 0 { return "clock.arrow.circlepath" }
        if session.seekRecoverySlowCount > 0 { return "speedometer" }
        if (session.accessLogStallCount ?? 0) > 0 { return "dot.radiowaves.left.and.right" }
        return "forward.frame"
    }

    private var exceptionSummary: String {
        if let failureMessage = session.failureMessage {
            return failureMessage
        }
        if session.bufferCount >= 2 {
            return "缓冲 \(session.bufferCount) 次，建议检查 CDN 或降低启动画质。"
        }
        if session.resumeRecoverySlowCount > 0 {
            return "续播落点偏慢 \(session.resumeRecoverySlowCount) 次，已进入更保守的开播保护策略。"
        }
        if session.seekRecoverySlowCount > 0 {
            return "Seek 恢复偏慢 \(session.seekRecoverySlowCount) 次，已进入更保守的播放保护策略。"
        }
        if let accessLogStallCount = session.accessLogStallCount, accessLogStallCount > 0 {
            return "系统 AccessLog 记录 stall \(accessLogStallCount) 次，建议复测 CDN 或降低开播画质。"
        }
        return "Seek \(session.seekCount) 次，已进入更保守的播放保护策略。"
    }

    private var exceptionColor: Color {
        session.failureMessage != nil ? .red : .orange
    }
}

@MainActor
final class MineViewModelHolder: ObservableObject {
    @Published var viewModel: MineViewModel?
    private var cancellable: AnyCancellable?
    private var lastSnapshot: MineRenderSnapshot?

    func configure(api: BiliAPIClient, sessionStore: SessionStore) {
        if viewModel == nil {
            let viewModel = MineViewModel(api: api, sessionStore: sessionStore)
            self.viewModel = viewModel
            lastSnapshot = MineRenderSnapshot(viewModel)
            cancellable = viewModel.objectWillChange.sink { [weak self] _ in
                Task { @MainActor [weak self, weak viewModel] in
                    guard let self, let viewModel else { return }
                    let snapshot = MineRenderSnapshot(viewModel)
                    guard snapshot != self.lastSnapshot else { return }
                    self.lastSnapshot = snapshot
                    self.objectWillChange.send()
                }
            }
        }
    }
}

private struct MineRenderSnapshot: Equatable {
    let state: LoadingState
    let loginMessage: String
    let qrLoginState: QRCodeLoginState
    let historyState: LoadingState
    let favoriteState: LoadingState
    let accountLibraryRevision: Int
    let favoriteFolderRevision: Int

    init(_ viewModel: MineViewModel) {
        state = viewModel.state
        loginMessage = viewModel.loginMessage
        qrLoginState = viewModel.qrLoginState
        historyState = viewModel.historyState
        favoriteState = viewModel.favoriteState
        accountLibraryRevision = viewModel.accountLibraryRevision
        favoriteFolderRevision = viewModel.favoriteFolderRevision
    }
}
