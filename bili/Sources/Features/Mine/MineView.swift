import Combine
import SwiftUI

struct MineView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var libraryStore: LibraryStore
    @StateObject private var holder = MineViewModelHolder()
    @State private var isShowingWebLogin = false
    @State private var isShowingQRCodeLogin = false
    @State private var isProbingPlaybackCDN = false
    @State private var playbackCDNProbeResults: [PlaybackCDNProbeResult] = []
    @State private var playbackCDNProbeMessage: String?
    @State private var playbackCDNProbeTask: Task<Void, Never>?
    @State private var isShowingPlaybackCDNProbeDetails = false

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
        .navigationBarTitleDisplayMode(.large)
        .nativeTopNavigationChrome()
        .sheet(isPresented: $isShowingWebLogin) {
            if let viewModel = holder.viewModel {
                BiliWebLoginView { cookies in
                    Task {
                        await viewModel.completeWebLogin(with: cookies)
                        isShowingWebLogin = false
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingQRCodeLogin) {
            if let viewModel = holder.viewModel {
                QRCodeLoginView(viewModel: viewModel)
            }
        }
        .onDisappear {
            playbackCDNProbeTask?.cancel()
            playbackCDNProbeTask = nil
            isProbingPlaybackCDN = false
        }
        .task {
            refreshPlaybackCDNProbeIfNeeded()
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
                isProbingPlaybackCDN = false
                playbackCDNProbeTask = nil
            }
        }
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
        return libraryStore.playbackCDNProbeSnapshot
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
                    Label("自动选择当前使用 \(activeRecommendation.title)", systemImage: "bolt.horizontal")
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
        List {
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
                VStack(alignment: .leading, spacing: 10) {
                    Label("外观", systemImage: "circle.lefthalf.filled")

                    Picker("外观", selection: Binding(
                        get: { libraryStore.appearanceMode },
                        set: { libraryStore.setAppearanceMode($0) }
                    )) {
                        ForEach(AppAppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 10) {
                    Label("首页布局", systemImage: "rectangle.grid.1x2")

                    Picker("首页布局", selection: Binding(
                        get: { libraryStore.homeFeedLayout },
                        set: { libraryStore.setHomeFeedLayout($0) }
                    )) {
                        ForEach(HomeFeedLayout.allCases) { layout in
                            Label(layout.title, systemImage: layout.systemImage).tag(layout)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("首页下拉刷新距离", systemImage: "arrow.down.circle")
                        Spacer()
                        Text("\(Int(libraryStore.homeRefreshTriggerDistance))")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { libraryStore.homeRefreshTriggerDistance },
                            set: { libraryStore.setHomeRefreshTriggerDistance($0) }
                        ),
                        in: LibraryStore.homeRefreshDistanceRange,
                        step: 5
                    )
                }
                .padding(.vertical, 4)
            }

            Section("播放偏好") {
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

                Text(libraryStore.playbackAutoOptimizationMode.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

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

                Text(libraryStore.playbackNetworkAddressFamilyPreference.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("如果视频加载慢或容易缓冲，可以切换 CDN 线路。默认自动会优先使用 24 小时内测速推荐的线路；没有新鲜测速结果时保留接口返回顺序。手动选择后会优先使用对应 CDN，并保留原始/备用地址作为回退。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if libraryStore.playbackNetworkAddressFamilyPreference != .automatic,
                   libraryStore.playbackCDNProbeSnapshot == nil {
                    Label("网络协议已切换，请重新测速 CDN 以生成匹配的新推荐。", systemImage: "arrow.triangle.2.circlepath")
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
            }

            Section("内容过滤") {
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
        .nativeTopScrollEdgeEffect()
        .task {
            await viewModel.refreshUser()
        }
    }

    private func accountLibrarySection(_ viewModel: MineViewModel) -> some View {
        Section("账号内容") {
            NavigationLink {
                AccountLibraryListPage(kind: .history, viewModel: viewModel)
            } label: {
                AccountLibraryEntryRow(
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

            NavigationLink {
                AccountLibraryListPage(kind: .favorites, viewModel: viewModel)
            } label: {
                AccountLibraryEntryRow(
                    title: "账号收藏",
                    systemImage: "star",
                    status: libraryStatusText(
                        isLoggedIn: sessionStore.isLoggedIn,
                        state: viewModel.favoriteState,
                        count: viewModel.accountFavorites.count,
                        emptyTitle: "暂无收藏"
                    )
                )
            }
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
            CachedRemoteImage(
                url: sessionStore.user?.face.flatMap { URL(string: $0.biliAvatarThumbnailURL(size: 128)) },
                targetPixelSize: 128
            ) { image in
                image.resizable().scaledToFill()
            } placeholder: {
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
                    isShowingQRCodeLogin = true
                } label: {
                    Label("扫码登录", systemImage: "qrcode")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.pink)

                Button {
                    isShowingWebLogin = true
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

private struct LibraryVideoRow: View {
    let item: AccountVideoEntry
    let timestampTitle: String

    var body: some View {
        HStack(spacing: 12) {
            CachedRemoteImage(
                url: item.pic.flatMap { URL(string: $0.biliCoverThumbnailURL(width: 320, height: 200)) },
                targetPixelSize: 320
            ) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.gray.opacity(0.14)
            }
            .frame(width: 96, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
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

                if let resumeTime = item.resumeTime {
                    VStack(alignment: .leading, spacing: 3) {
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
        .padding(.vertical, 4)
    }
}

private enum AccountLibraryKind {
    case history
    case favorites

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

private struct AccountLibraryEntryRow: View {
    let title: String
    let systemImage: String
    let status: String

    var body: some View {
        Label {
            HStack {
                Text(title)
                Spacer(minLength: 12)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.pink)
        }
        .padding(.vertical, 4)
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
            if store.events.isEmpty {
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

                if !store.sessions.isEmpty {
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
        case .buffering: return "hourglass"
        case .network: return "network"
        case .mediaCache: return "externaldrive.fill.badge.checkmark"
        case .failed: return "exclamationmark.triangle"
        }
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
                metric("播放地址", milliseconds: session.playURLMilliseconds, icon: "link")
                metric("Prepare", milliseconds: session.prepareMilliseconds, icon: "gearshape")
            }

            HStack(spacing: 8) {
                Label("\(session.bufferCount) 次缓冲", systemImage: "hourglass")
                if let selectedQualityMessage = session.selectedQualityMessage {
                    Text(selectedQualityMessage)
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(session.bufferCount > 0 ? .orange : .secondary)

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

            if let mediaCacheMessage = session.mediaCacheMessage {
                Text(mediaCacheMessage)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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

@MainActor
final class MineViewModelHolder: ObservableObject {
    @Published var viewModel: MineViewModel?
    private var cancellable: AnyCancellable?

    func configure(api: BiliAPIClient, sessionStore: SessionStore) {
        if viewModel == nil {
            let viewModel = MineViewModel(api: api, sessionStore: sessionStore)
            self.viewModel = viewModel
            cancellable = viewModel.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
    }
}
