import Combine
import SwiftUI

struct LiveView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @StateObject private var holder = LiveViewModelHolder()

    var body: some View {
        Group {
            if let viewModel = holder.viewModel {
                LiveFeedView(viewModel: viewModel)
            } else {
                ScrollView {
                    LiveFeedSkeletonGrid()
                }
                .nativeTopScrollEdgeEffect()
                    .background(Color(.systemBackground))
                    .task {
                        holder.configure(api: dependencies.api)
                    }
            }
        }
        .rootNavigationTitle("直播")
        .nativeTopNavigationChrome()
    }
}

private struct LiveFeedView: View {
    @ObservedObject var viewModel: LiveViewModel

    private let columns = [
        GridItem(.flexible(minimum: 0), spacing: 12),
        GridItem(.flexible(minimum: 0), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if viewModel.rooms.isEmpty && viewModel.state.isLoading {
                    loadingState
                } else if viewModel.rooms.isEmpty {
                    emptyState
                } else {
                    roomGrid
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 22)
        }
        .nativeTopScrollEdgeEffect()
        .scrollBounceBehavior(.always, axes: .vertical)
        .background(Color(.systemBackground))
        .refreshable {
            await viewModel.refresh()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    if viewModel.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(viewModel.isRefreshing || (viewModel.rooms.isEmpty && viewModel.state.isLoading))
                .accessibilityLabel("刷新推荐直播间")
            }
        }
        .task {
            await viewModel.loadInitial()
        }
        .overlay {
            if case .failed(let message) = viewModel.state, viewModel.rooms.isEmpty {
                ErrorStateView(title: "直播加载失败", message: message) {
                    Task { await viewModel.refresh() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground).opacity(0.96))
            }
        }
    }

    private var loadingState: some View {
        LiveFeedSkeletonGrid(columns: columns, horizontalPadding: 0, topPadding: 0)
            .allowsHitTesting(false)
    }

    private var emptyState: some View {
        EmptyStateView(
            title: viewModel.emptyTitle,
            systemImage: "play.tv",
            message: viewModel.emptyMessage
        )
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    private var roomGrid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(viewModel.rooms) { room in
                NavigationLink(value: room) {
                    LiveRoomCard(room: room)
                }
                .buttonStyle(.plain)
                .onAppear {
                    Task { await viewModel.loadMoreIfNeeded(current: room) }
                }
            }

            if viewModel.isLoadingMore {
                ForEach(0..<2, id: \.self) { _ in
                    LiveRoomSkeletonCard()
                        .allowsHitTesting(false)
                }
            } else if let message = viewModel.loadMoreMessage {
                LiveFeedFooter(text: message, showsProgress: false)
                    .gridCellColumns(columns.count)
            }
        }
    }
}

private struct LiveFeedSkeletonGrid: View {
    var columns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    var horizontalPadding: CGFloat = 16
    var topPadding: CGFloat = 10

    var body: some View {
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(0..<6, id: \.self) { _ in
                LiveRoomSkeletonCard()
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topPadding)
        .padding(.bottom, 22)
    }
}

private struct LiveRoomCard: View {
    let room: LiveRoom

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            cover

            Text(title)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36, alignment: .topLeading)

            HStack(spacing: 5) {
                anchorAvatar

                Text(anchorName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(height: 19, alignment: .leading)

            Group {
                if let areaText {
                    Text(areaText)
                } else {
                    Text(" ")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 14, maxHeight: 14, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var cover: some View {
        Color.gray.opacity(0.14)
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                coverImage
            }
            .overlay(alignment: .topLeading) {
                LiveRoomStatusBadge()
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay(alignment: .bottomTrailing) {
                if let onlineText {
                    LiveRoomOnlineBadge(text: onlineText)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .mediaShadow(.control)
    }

    private var coverImage: some View {
        CachedRemoteImage(
            url: coverURL,
            fallbackURL: fallbackCoverURL,
            targetPixelSize: 420,
            animatesAppearance: false
        ) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            coverFallbackPlaceholder
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder
    private var coverFallbackPlaceholder: some View {
        if let avatarCoverFallbackURL {
            CachedRemoteImage(
                url: avatarCoverFallbackURL,
                targetPixelSize: 420,
                animatesAppearance: false
            ) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                coverPlaceholderBase
            }
        } else {
            coverPlaceholderBase
        }
    }

    private var coverPlaceholderBase: some View {
        Color.gray.opacity(0.14)
            .overlay {
                Image(systemName: "play.tv")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
    }

    private var anchorAvatar: some View {
        AvatarRemoteImage(urlString: room.face, pixelSize: 56) {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(.secondary.opacity(0.72))
        }
        .frame(width: 19, height: 19)
        .clipShape(Circle())
    }

    private var coverURL: URL? {
        primaryCoverURLString
            .map { $0.biliCoverThumbnailURL(width: 420, height: 236) }
            .flatMap(URL.init(string:))
    }

    private var fallbackCoverURL: URL? {
        fallbackCoverURLString
            .map { $0.biliCoverThumbnailURL(width: 420, height: 236) }
            .flatMap(URL.init(string:))
    }

    private var avatarCoverFallbackURL: URL? {
        guard let face = room.face?.normalizedBiliURL() else { return nil }
        return URL(string: face.biliAvatarThumbnailURL(size: 240))
    }

    private var primaryCoverURLString: String? {
        room.coverCandidates.first
    }

    private var fallbackCoverURLString: String? {
        room.coverCandidates.dropFirst().first
    }

    private var title: String {
        room.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "直播间"
    }

    private var anchorName: String {
        room.uname.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "UP 主"
    }

    private var onlineText: String? {
        guard let online = room.online, online > 0 else { return nil }
        return BiliFormatters.compactCount(online)
    }

    private var areaText: String? {
        [room.parentAreaName, room.areaName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            .joined(separator: " / ")
            .nilIfEmpty
    }

    private var accessibilityLabel: String {
        [title, anchorName, areaText, onlineText.map { "\($0)人在线" }]
            .compactMap { $0 }
            .joined(separator: "，")
    }
}

private struct LiveRoomStatusBadge: View {
    var body: some View {
        Label("直播中", systemImage: "dot.radiowaves.left.and.right")
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(.primary)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .allowsTightening(true)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .glassEffect(.regular, in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: 76, alignment: .leading)
            .clipped()
    }
}

private struct LiveRoomOnlineBadge: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "person.2.fill")
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.primary)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .allowsTightening(true)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .glassEffect(.regular, in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: 86, alignment: .leading)
            .clipped()
    }
}

private struct LiveFeedFooter: View {
    let text: String
    let showsProgress: Bool

    var body: some View {
        HStack(spacing: 8) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            }

            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

@MainActor
private final class LiveViewModelHolder: ObservableObject {
    @Published var viewModel: LiveViewModel?
    private var cancellable: AnyCancellable?
    private var lastSnapshot: LiveRenderSnapshot?

    func configure(api: BiliAPIClient) {
        guard viewModel == nil else { return }
        let viewModel = LiveViewModel(api: api)
        self.viewModel = viewModel
        lastSnapshot = LiveRenderSnapshot(viewModel)
        cancellable = viewModel.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self, weak viewModel] in
                guard let self, let viewModel else { return }
                let snapshot = LiveRenderSnapshot(viewModel)
                guard snapshot != self.lastSnapshot else { return }
                self.lastSnapshot = snapshot
                self.objectWillChange.send()
            }
        }
    }
}

@MainActor
private final class LiveViewModel: ObservableObject {
    @Published private(set) var rooms: [LiveRoom] = [] {
        didSet { roomsRevision &+= 1 }
    }
    @Published var state: LoadingState = .idle
    @Published private(set) var isLoadingMore = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var loadMoreMessage: String?
    @Published private(set) var roomsRevision = 0

    private let api: BiliAPIClient
    private var page = 1
    private var hasMore = true
    private var generation = 0
    private var refreshIndex = 0
    private let pageSize = 20
    private var imagePrefetchTask: Task<Void, Never>?

    init(api: BiliAPIClient) {
        self.api = api
    }

    deinit {
        imagePrefetchTask?.cancel()
    }

    var emptyTitle: String {
        "暂无直播"
    }

    var emptyMessage: String {
        if case .failed(let message) = state {
            return message
        }
        return "下拉刷新或稍后再来看看。"
    }

    func loadInitial() async {
        guard rooms.isEmpty, !state.isLoading else { return }
        await loadFirstPage(isUserInitiated: false)
    }

    func refresh() async {
        guard !isRefreshing else { return }
        await loadFirstPage(isUserInitiated: true)
    }

    func loadMoreIfNeeded(current room: LiveRoom) async {
        guard rooms.last?.id == room.id else { return }
        await loadMore()
    }

    private func loadFirstPage(isUserInitiated: Bool) async {
        generation &+= 1
        refreshIndex &+= 1
        let currentGeneration = generation
        let currentRefreshIndex = refreshIndex
        let previousRooms = rooms
        let previousPage = page
        let previousHasMore = hasMore
        isRefreshing = isUserInitiated
        isLoadingMore = false
        loadMoreMessage = nil
        state = .loading
        await loadPage(
            1,
            reset: true,
            generation: currentGeneration,
            refreshIndex: currentRefreshIndex,
            previousRooms: previousRooms,
            previousPage: previousPage,
            previousHasMore: previousHasMore
        )
    }

    private func loadMore() async {
        guard hasMore, !state.isLoading, !isLoadingMore else { return }
        let currentGeneration = generation
        let nextPage = page
        loadMoreMessage = nil
        isLoadingMore = true
        await loadPage(
            nextPage,
            reset: false,
            generation: currentGeneration,
            refreshIndex: refreshIndex,
            previousRooms: rooms,
            previousPage: page,
            previousHasMore: hasMore
        )
    }

    private func loadPage(
        _ targetPage: Int,
        reset: Bool,
        generation targetGeneration: Int,
        refreshIndex targetRefreshIndex: Int,
        previousRooms: [LiveRoom],
        previousPage: Int,
        previousHasMore: Bool
    ) async {
        defer {
            if targetGeneration == generation {
                isLoadingMore = false
                isRefreshing = false
            }
        }

        do {
            let fetchedRooms = try await api.fetchLiveRooms(
                page: targetPage,
                refreshIndex: targetRefreshIndex
            )
            guard targetGeneration == generation else { return }

            if reset {
                rooms = Self.uniqued(fetchedRooms)
            } else {
                rooms = Self.appendingUnique(fetchedRooms, to: rooms)
            }

            scheduleImagePrefetch(for: reset ? rooms : fetchedRooms)
            page = targetPage + 1
            hasMore = fetchedRooms.count >= pageSize
            state = .loaded
        } catch {
            guard targetGeneration == generation else { return }
            let message = error.localizedDescription
            if reset, !previousRooms.isEmpty {
                rooms = previousRooms
                page = previousPage
                hasMore = previousHasMore
                loadMoreMessage = "刷新失败，已保留当前推荐"
                state = .loaded
            } else if reset || rooms.isEmpty {
                state = .failed(message)
            } else {
                loadMoreMessage = "加载更多失败，稍后再试"
                state = .loaded
            }
        }
    }

    private static func uniqued(_ rooms: [LiveRoom]) -> [LiveRoom] {
        appendingUnique(rooms, to: [])
    }

    private static func appendingUnique(_ newRooms: [LiveRoom], to existingRooms: [LiveRoom]) -> [LiveRoom] {
        var seen = Set(existingRooms.map(\.roomID))
        var result = existingRooms
        for room in newRooms where seen.insert(room.roomID).inserted {
            result.append(room)
        }
        return result
    }

    private func scheduleImagePrefetch(for rooms: [LiveRoom]) {
        imagePrefetchTask?.cancel()
        let environment = PlaybackEnvironment.current
        let plan = imagePrefetchPlan(for: rooms, limit: environment.shouldPreferConservativePlayback ? 6 : 10)
        guard !plan.coverSources.isEmpty || !plan.avatarSources.isEmpty else { return }
        imagePrefetchTask = Task(priority: .utility) {
            async let coverPrefetch: Void = RemoteImageCache.shared.prefetch(
                plan.coverSources,
                targetPixelSize: 420,
                maximumConcurrentLoads: environment.shouldPreferConservativePlayback ? 1 : 2
            )
            async let avatarPrefetch: Void = RemoteImageCache.shared.prefetch(
                plan.avatarSources,
                targetPixelSize: 56,
                maximumConcurrentLoads: 1
            )
            _ = await (coverPrefetch, avatarPrefetch)
        }
    }

    private func imagePrefetchPlan(
        for rooms: [LiveRoom],
        limit: Int
    ) -> (coverSources: [RemoteImageSource], avatarSources: [RemoteImageSource]) {
        var seenCovers = Set<String>()
        var seenAvatars = Set<String>()
        var coverSources = [RemoteImageSource]()
        var avatarSources = [RemoteImageSource]()

        for room in rooms.prefix(limit) {
            if let coverSource = coverSource(for: room),
               seenCovers.insert(coverSource.identity).inserted {
                coverSources.append(coverSource.source)
            }

            if let face = room.face?.normalizedBiliURL(),
               let url = URL(string: face.biliAvatarThumbnailURL(size: 56)),
               seenAvatars.insert(face).inserted {
                avatarSources.append(RemoteImageSource(url: url, fallbackURL: URL(string: face)))
            }
        }

        return (coverSources, avatarSources)
    }

    private func coverSource(for room: LiveRoom) -> (identity: String, source: RemoteImageSource)? {
        let coverCandidates = room.coverCandidates
        if let cover = coverCandidates.first,
           let url = URL(string: cover.biliCoverThumbnailURL(width: 420, height: 236)) {
            let fallbackURL: URL?
            if coverCandidates.count > 1 {
                fallbackURL = URL(string: coverCandidates[1].biliCoverThumbnailURL(width: 420, height: 236))
            } else if let face = room.face?.normalizedBiliURL() {
                fallbackURL = URL(string: face.biliAvatarThumbnailURL(size: 240))
            } else {
                fallbackURL = nil
            }
            return (coverCandidates.joined(separator: "|"), RemoteImageSource(url: url, fallbackURL: fallbackURL))
        }

        guard let face = room.face?.normalizedBiliURL(),
              let url = URL(string: face.biliImageThumbnailURL(maxSide: 420))
        else { return nil }
        return ("avatar|\(face)", RemoteImageSource(url: url, fallbackURL: URL(string: face)))
    }
}

private struct LiveRenderSnapshot: Equatable {
    let state: LoadingState
    let isLoadingMore: Bool
    let isRefreshing: Bool
    let loadMoreMessage: String?
    let roomCount: Int
    let firstRoomID: Int?
    let lastRoomID: Int?
    let roomsRevision: Int

    init(_ viewModel: LiveViewModel) {
        state = viewModel.state
        isLoadingMore = viewModel.isLoadingMore
        isRefreshing = viewModel.isRefreshing
        loadMoreMessage = viewModel.loadMoreMessage
        roomCount = viewModel.rooms.count
        firstRoomID = viewModel.rooms.first?.roomID
        lastRoomID = viewModel.rooms.last?.roomID
        roomsRevision = viewModel.roomsRevision
    }
}

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
