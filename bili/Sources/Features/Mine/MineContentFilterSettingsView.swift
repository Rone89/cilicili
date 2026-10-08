import SwiftUI

struct MineContentFilterSettingsView: View {
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var sessionStore: SessionStore
    let api: BiliAPIClient

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { libraryStore.blocksAdDynamics },
                    set: { libraryStore.setBlocksAdDynamics($0) }
                )) {
                    MineSettingsLabel("屏蔽广告动态", systemImage: "megaphone.badge.minus")
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.blocksGoodsDynamics },
                    set: { libraryStore.setBlocksGoodsDynamics($0) }
                )) {
                    MineSettingsLabel("屏蔽带货动态", systemImage: "bag.badge.minus")
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.blocksGoodsComments },
                    set: { libraryStore.setBlocksGoodsComments($0) }
                )) {
                    MineSettingsLabel("屏蔽带货评论", systemImage: "text.bubble.badge.minus")
                }

                NavigationLink {
                    DynamicKeywordFilterSettingsView(libraryStore: libraryStore)
                } label: {
                    PlainSettingsNavigationRow(
                        title: "自定义动态关键词",
                        subtitle: "\(libraryStore.blockedDynamicKeywords.count) 个关键词",
                    )
                }

                Text("广告动态会按常见推广关键词过滤；带货动态会按 B 站商品组件和商品元数据过滤；自定义关键词会匹配动态正文、标题和转发内容。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                NavigationLink("黑名单管理") {
                    AccountBlacklistSettingsView(sessionStore: sessionStore, libraryStore: libraryStore, api: api)
                }
            }

            Section("推荐过滤") {
                NavigationLink {
                    LocalBlockedUPSettingsView(libraryStore: libraryStore, api: api)
                } label: {
                    PlainSettingsNavigationRow(
                        title: "本地已屏蔽的 UP 主",
                        subtitle: "\(libraryStore.blockedHomeRecommendationUPMIDs.count) 位 UP 主"
                    )
                }

                Picker(selection: Binding(
                    get: { libraryStore.recommendMinimumDurationSeconds },
                    set: { libraryStore.setRecommendMinimumDurationSeconds($0) }
                )) {
                    ForEach(LibraryStore.supportedRecommendMinimumDurations, id: \.self) { seconds in
                        Text(recommendDurationTitle(seconds)).tag(seconds)
                    }
                } label: {
                    MineSettingsLabel("最短时长", systemImage: "timer")
                }
                .pickerStyle(.menu)

                Picker(selection: Binding(
                    get: { libraryStore.recommendMinimumViewCount },
                    set: { libraryStore.setRecommendMinimumViewCount($0) }
                )) {
                    ForEach(LibraryStore.supportedRecommendMinimumViews, id: \.self) { count in
                        Text(recommendViewTitle(count)).tag(count)
                    }
                } label: {
                    MineSettingsLabel("最低播放量", systemImage: "play.circle")
                }
                .pickerStyle(.menu)

                Picker(selection: Binding(
                    get: { libraryStore.recommendMinimumLikeRatioPercent },
                    set: { libraryStore.setRecommendMinimumLikeRatioPercent($0) }
                )) {
                    ForEach(LibraryStore.supportedRecommendMinimumLikeRatios, id: \.self) { percent in
                        Text(recommendLikeRatioTitle(percent)).tag(percent)
                    }
                } label: {
                    MineSettingsLabel("最低点赞率", systemImage: "hand.thumbsup")
                }
                .pickerStyle(.menu)

                NavigationLink {
                    RecommendKeywordFilterSettingsView(libraryStore: libraryStore)
                } label: {
                    PlainSettingsNavigationRow(
                        title: "标题关键词",
                        subtitle: "\(libraryStore.blockedRecommendKeywords.count) 个关键词",
                    )
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.appliesRecommendFiltersToRelatedVideos },
                    set: { libraryStore.setAppliesRecommendFiltersToRelatedVideos($0) }
                )) {
                    MineSettingsLabel("应用到相关推荐", systemImage: "rectangle.stack.badge.minus")
                }

                Text("默认只过滤首页推荐；打开后也会过滤视频详情页相关推荐。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(libraryStore.appTintColor)
        .formStyle(.grouped)
        .standardPageHorizontalContentMargins(libraryStore.standardPageHorizontalInset)
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
    }

    private func recommendDurationTitle(_ seconds: Int) -> String {
        seconds == 0 ? "不过滤" : "\(seconds) 秒"
    }

    private func recommendViewTitle(_ count: Int) -> String {
        count == 0 ? "不过滤" : "\(count)"
    }

    private func recommendLikeRatioTitle(_ percent: Int) -> String {
        percent == 0 ? "不过滤" : "\(percent)%"
    }
}

private struct LocalBlockedUPSettingsView: View {
    @ObservedObject var libraryStore: LibraryStore
    let api: BiliAPIClient

    var body: some View {
        List {
            Section {
                if libraryStore.blockedHomeRecommendationUPMIDs.isEmpty {
                    Text("暂无本地屏蔽的 UP 主")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(libraryStore.blockedHomeRecommendationUPMIDs.sorted(), id: \.self) { mid in
                        HStack {
                            Text(libraryStore.blockedHomeRecommendationUPNames[String(mid)] ?? "名称暂不可用")
                            Spacer(minLength: 8)
                            Button("解除屏蔽") {
                                libraryStore.unblockHomeRecommendationUP(mid: mid)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("解除屏蔽 \(libraryStore.blockedHomeRecommendationUPNames[String(mid)] ?? "该 UP 主")")
                        }
                    }
                    .onDelete { offsets in
                        let mids = libraryStore.blockedHomeRecommendationUPMIDs.sorted()
                        for index in offsets { libraryStore.unblockHomeRecommendationUP(mid: mids[index]) }
                    }
                }
            } header: {
                Text("本地已屏蔽的 UP 主")
            } footer: {
                Text("仅管理本机首页推荐屏蔽，不会解除 Bilibili 服务器拉黑。解除后，该 UP 的内容可在后续推荐中再次出现。首页推荐反馈实验关闭时，本地屏蔽数据仍保留，但不参与推荐过滤。")
            }
        }
        .tint(libraryStore.appTintColor)
        .listStyle(.insetGrouped)
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
        .task {
            for mid in libraryStore.blockedHomeRecommendationUPMIDs.sorted() {
                guard !Task.isCancelled else { return }
                if libraryStore.blockedHomeRecommendationUPNames[String(mid)] == nil,
                   let name = try? await api.fetchUploaderName(mid: Int(mid)) {
                    libraryStore.updateBlockedHomeRecommendationUPName(mid: mid, name: name)
                }
            }
        }
    }
}

private struct AccountBlacklistSettingsView: View {
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var libraryStore: LibraryStore
    let api: BiliAPIClient
    @State private var users: [AccountBlockedUser] = []
    @State private var nextPage = 1
    @State private var hasMore = false
    @State private var loading = false
    @State private var loadID = UUID()
    @State private var errorMessage: String?
    @State private var pendingRemoval: AccountBlockedUser?
    @State private var removing = false

    var body: some View {
        List {
            Section {
                if sessionStore.mainAccountMID == nil {
                    Text("请先登录账户").foregroundStyle(.secondary)
                } else {
                    ForEach(users) { user in
                        HStack {
                            Text(user.uname)
                            Spacer()
                            Button("解除拉黑") { pendingRemoval = user }
                                .buttonStyle(.borderless)
                                .disabled(removing)
                        }
                    }
                    if loading { ProgressView() }
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.secondary)
                        Button("重试") { Task { await load(reset: users.isEmpty) } }.disabled(loading)
                    } else if users.isEmpty && !loading {
                        Text("暂无已拉黑用户").foregroundStyle(.secondary)
                    }
                    if hasMore { Button("加载更多") { Task { await load(reset: false) } }.disabled(loading || removing) }
                }
            } header: {
                Text("账户黑名单")
            } footer: {
                Text("管理当前主账户在 Bilibili 已拉黑的用户。解除账户拉黑不会解除本机推荐屏蔽。")
            }
        }
        .tint(libraryStore.appTintColor)
        .listStyle(.insetGrouped)
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
        .task(id: sessionStore.mainAccountMID) { await load(reset: true) }
        .refreshable { await load(reset: true) }
        .confirmationDialog("解除拉黑「\(pendingRemoval?.uname ?? "")」？", isPresented: Binding(
            get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }
        ), titleVisibility: .visible) {
            if let user = pendingRemoval {
                Button("解除拉黑", role: .destructive) { Task { await unblock(user) } }
            }
            Button("取消", role: .cancel) { pendingRemoval = nil }
        }
    }

    @MainActor private func load(reset: Bool) async {
        guard reset || (!loading && !removing) else { return }
        let requestID = UUID()
        loadID = requestID
        if reset { users = []; nextPage = 1; hasMore = false; pendingRemoval = nil; errorMessage = nil; loading = false }
        guard let account = sessionStore.mainAccountMID else { return }
        loading = true
        errorMessage = nil
        let page = reset ? 1 : nextPage
        do {
            let result = try await api.fetchAccountBlacklist(page: page, expectedAccountMID: account)
            guard !Task.isCancelled, loadID == requestID, sessionStore.mainAccountMID == account else { return }
            let incoming = result.list ?? []
            let known = Set(users.map(\.mid))
            users += incoming.filter { !known.contains($0.mid) }
            nextPage = page + 1
            hasMore = !incoming.isEmpty && page * 50 < result.total
        } catch {
            if !Task.isCancelled, loadID == requestID, sessionStore.mainAccountMID == account { errorMessage = error.localizedDescription }
        }
        if loadID == requestID, sessionStore.mainAccountMID == account { loading = false }
    }

    @MainActor private func unblock(_ user: AccountBlockedUser) async {
        guard let account = sessionStore.mainAccountMID, !removing else { return }
        removing = true
        pendingRemoval = nil
        do {
            try await api.unblockUploader(mid: user.mid, expectedAccountMID: account)
            guard sessionStore.mainAccountMID == account else { removing = false; return }
            // Reload pagination after mutation so shifted server pages cannot skip a user.
            removing = false
            await load(reset: true)
        } catch {
            if sessionStore.mainAccountMID == account { errorMessage = error.localizedDescription }
            removing = false
        }
    }
}
