import Combine
import SwiftUI

struct MineView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var libraryStore: LibraryStore
    @StateObject private var holder = MineViewModelHolder()
    @State private var isShowingWebLogin = false
    @State private var isShowingQRCodeLogin = false

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
                Label("默认选择当前可播放的最高画质", systemImage: "play.rectangle")

                Toggle(isOn: Binding(
                    get: { libraryStore.defaultDanmakuEnabled },
                    set: { libraryStore.setDefaultDanmakuEnabled($0) }
                )) {
                    Label("默认开启弹幕", systemImage: "text.bubble")
                }

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
            AsyncImage(url: sessionStore.user?.face.flatMap { URL(string: $0.biliAvatarThumbnailURL(size: 128)) }) { image in
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
            AsyncImage(url: item.pic.flatMap { URL(string: $0.biliCoverThumbnailURL(width: 320, height: 200)) }) { image in
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
        .nativeTopScrollEdgeEffect()
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
