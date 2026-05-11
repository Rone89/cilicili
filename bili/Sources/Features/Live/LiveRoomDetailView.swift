import Combine
import SwiftUI

struct LiveRoomDetailView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    let seedRoom: LiveRoom
    @StateObject private var holder = LiveRoomViewModelHolder()

    var body: some View {
        Group {
            if let viewModel = holder.viewModel {
                content(viewModel)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task {
                        holder.configure(room: seedRoom, api: dependencies.api)
                    }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .nativeTopNavigationChrome()
        .toolbarBackground(.hidden, for: .navigationBar)
        .background(Color(.systemGroupedBackground))
        .hidesRootTabBarOnPush()
    }

    @ViewBuilder
    private func content(_ viewModel: LiveRoomViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                playerSection(viewModel)

                LiveRoomInfoCard(viewModel: viewModel)
                    .padding(.horizontal, 12)

                LiveDanmakuHistoryCard(messages: viewModel.danmakuMessages)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 20)
            }
        }
        .background(Color(.systemGroupedBackground))
        .overlay {
            if case .failed(let message) = viewModel.state, viewModel.streamURL == nil {
                ErrorStateView(title: "直播加载失败", message: message, retry: viewModel.reload)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground).opacity(0.96))
            }
        }
        .onAppear {
            viewModel.startLoading()
        }
    }

    @ViewBuilder
    private func playerSection(_ viewModel: LiveRoomViewModel) -> some View {
        ZStack {
            if let streamURL = viewModel.streamURL {
                BiliPlayerView(
                    videoURL: streamURL,
                    title: viewModel.title,
                    danmakus: viewModel.danmakuItems,
                    referer: "https://live.bilibili.com/\(viewModel.roomID)",
                    presentation: .embedded,
                    embeddedAspectRatio: 16 / 9
                )
            } else {
                liveLoadingPlaceholder(viewModel)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }

    @ViewBuilder
    private func liveLoadingPlaceholder(_ viewModel: LiveRoomViewModel) -> some View {
        Color.black
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                VStack(spacing: 10) {
                    if case .failed(let message) = viewModel.state {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.86))
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.78))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        Button("重试", action: viewModel.reload)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                        .tint(.pink)
                    } else {
                        ProgressView()
                            .tint(.white)
                        Text("正在进入直播间")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.78))
                    }
                }
            }
    }
}

@MainActor
private final class LiveRoomViewModelHolder: ObservableObject {
    @Published var viewModel: LiveRoomViewModel?

    func configure(room: LiveRoom, api: BiliAPIClient) {
        guard viewModel == nil else { return }
        viewModel = LiveRoomViewModel(seedRoom: room, api: api)
    }
}

@MainActor
final class LiveRoomViewModel: ObservableObject {
    @Published private(set) var roomSummary: LiveRoomSummary?
    @Published private(set) var roomInfo: LiveRoomInfo?
    @Published private(set) var anchorInfo: LiveAnchorInfoData?
    @Published private(set) var streamURL: URL?
    @Published private(set) var danmakuMessages: [LiveDanmakuMessage] = []
    @Published var state: LoadingState = .idle

    let seedRoom: LiveRoom
    private let api: BiliAPIClient
    private var loadingTask: Task<Void, Never>?
    private var metadataTask: Task<Void, Never>?

    init(seedRoom: LiveRoom, api: BiliAPIClient) {
        self.seedRoom = seedRoom
        self.api = api
    }

    deinit {
        loadingTask?.cancel()
        metadataTask?.cancel()
    }

    var roomID: Int {
        roomInfo?.roomID ?? roomSummary?.roomID ?? seedRoom.roomID
    }

    var title: String {
        let value = roomInfo?.title ?? roomSummary?.title ?? seedRoom.title
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "直播间" : value
    }

    var coverURL: String? {
        (roomInfo?.displayCover ?? roomSummary?.cover ?? seedRoom.displayCover)?.normalizedBiliURL()
    }

    var areaText: String? {
        [roomInfo?.parentAreaName ?? seedRoom.parentAreaName, roomInfo?.areaName ?? seedRoom.areaName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
            .nilIfEmpty
    }

    var onlineText: String {
        let online = roomInfo?.online ?? roomSummary?.online ?? seedRoom.online
        guard let online, online > 0 else { return "在线人数 -" }
        return "在线 \(BiliFormatters.compactCount(online))"
    }

    var liveTimeText: String? {
        roomInfo?.liveTime?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var descriptionText: String? {
        roomInfo?.description?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var anchorName: String {
        anchorInfo?.info?.uname?.nilIfEmpty ?? seedRoom.uname
    }

    var anchorFace: String? {
        anchorInfo?.info?.face?.normalizedBiliURL() ?? seedRoom.face?.normalizedBiliURL()
    }

    var isFollowingAnchor: Bool {
        (anchorInfo?.relationInfo?.attention ?? 0) > 0
    }

    var isLive: Bool {
        if let roomInfo {
            return roomInfo.isLive
        }
        if let liveStatus = roomSummary?.liveStatus {
            return liveStatus == 1
        }
        return seedRoom.isLive
    }

    var danmakuItems: [DanmakuItem] {
        danmakuMessages.enumerated().map { index, message in
            DanmakuItem(
                time: TimeInterval(index * 2),
                mode: 1,
                fontSize: 25,
                color: 0xFFFFFF,
                text: message.text
            )
        }
    }

    func startLoading() {
        guard streamURL == nil else { return }
        guard loadingTask == nil else { return }
        loadingTask = Task { [weak self] in
            await self?.loadFromNetwork()
        }
    }

    func reload() {
        loadingTask?.cancel()
        metadataTask?.cancel()
        loadingTask = nil
        metadataTask = nil
        streamURL = nil
        state = .idle
        startLoading()
    }

    private func loadFromNetwork() async {
        guard streamURL == nil else {
            loadingTask = nil
            return
        }
        state = .loading
        defer {
            loadingTask = nil
        }
        let api = self.api
        let roomID: Int
        if seedRoom.roomID > 0 {
            roomID = seedRoom.roomID
        } else if let uid = seedRoom.uid, uid > 0 {
            do {
                let summary = try await api.fetchLiveRoomSummary(uid: uid)
                guard !Task.isCancelled else { return }
                roomSummary = summary
                roomID = summary.roomID
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed("没有找到这个 UP 的直播间")
                return
            }
        } else {
            state = .failed("这条直播动态缺少直播间信息")
            return
        }

        metadataTask = Task { [weak self] in
            guard let self else { return }
            await self.loadRoomMetadata(roomID: roomID)
        }

        do {
            let streamURL = try await withTimeout(seconds: 8) {
                try await api.fetchLiveStreamURL(roomID: roomID)
            }
            guard !Task.isCancelled else { return }
            self.streamURL = streamURL
            state = .loaded
        } catch {
            guard !Task.isCancelled else { return }
            if roomInfo?.isLive == false {
                state = .failed("这个直播间当前未开播")
            } else {
                state = .failed("没有获取到可播放的直播流：\(error.localizedDescription)")
            }
        }
    }

    private func loadRoomMetadata(roomID: Int) async {
        let api = self.api
        async let roomInfoTask: LiveRoomInfo? = optionalFetch { try await api.fetchLiveRoomInfo(roomID: roomID) }
        async let anchorInfoTask: LiveAnchorInfoData? = optionalFetch { try await api.fetchLiveAnchorInfo(roomID: roomID) }
        async let danmakuTask: [LiveDanmakuMessage] = optionalFetchArray { try await api.fetchLiveDanmakuHistory(roomID: roomID) }

        roomInfo = await roomInfoTask
        anchorInfo = await anchorInfoTask
        danmakuMessages = await danmakuTask
    }

    private func withTimeout<T: Sendable>(
        seconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw BiliAPIError.api(code: -1, message: "直播取流超时")
            }
            guard let result = try await group.next() else {
                throw BiliAPIError.missingPayload
            }
            group.cancelAll()
            return result
        }
    }

    private func optionalFetch<T>(_ operation: @escaping () async throws -> T) async -> T? {
        do {
            return try await operation()
        } catch {
            return nil
        }
    }

    private func optionalFetchArray<T>(_ operation: @escaping () async throws -> [T]) async -> [T] {
        do {
            return try await operation()
        } catch {
            return []
        }
    }
}

private struct LiveRoomInfoCard: View {
    @ObservedObject var viewModel: LiveRoomViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                AsyncImage(url: viewModel.anchorFace.flatMap(URL.init(string:))) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 42, height: 42)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(viewModel.anchorName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if viewModel.isFollowingAnchor {
                            Text("已关注")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.pink)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.pink.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: 8) {
                        Label(viewModel.isLive ? "直播中" : "未开播", systemImage: viewModel.isLive ? "dot.radiowaves.left.and.right" : "pause.circle")
                            .foregroundStyle(viewModel.isLive ? .pink : .secondary)

                        Text(viewModel.onlineText)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            Text(viewModel.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if let areaText = viewModel.areaText {
                    Label(areaText, systemImage: "tag")
                }
                if let liveTimeText = viewModel.liveTimeText {
                    Label(liveTimeText, systemImage: "clock")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let descriptionText = viewModel.descriptionText {
                Text(descriptionText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct LiveDanmakuHistoryCard: View {
    let messages: [LiveDanmakuMessage]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("弹幕", systemImage: "text.bubble")
                    .font(.headline)
                Spacer()
                Text(messages.isEmpty ? "暂无" : "\(messages.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if messages.isEmpty {
                Text("暂时没有历史弹幕")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(messages.prefix(30)) { message in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(message.nickname?.nilIfEmpty ?? "用户")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Text(message.text)
                                .font(.footnote)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
