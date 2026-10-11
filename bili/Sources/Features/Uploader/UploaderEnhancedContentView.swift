import SwiftUI

struct UploaderEnhancedContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    let owner: VideoOwner
    @ObservedObject var viewModel: UploaderViewModel
    let allowsPullToRefresh: Bool
    let showsToolbarRefreshButton: Bool
    @State private var selectedSection: SpaceSection = .home
    @State private var contentWidth: CGFloat = 0

    private var metrics: HomeFeedLayoutMetrics {
        HomeFeedLayoutMetrics(mode: .doubleColumn, containerWidth: contentWidth,
                              standardHorizontalInset: libraryStore.standardPageHorizontalInset)
    }

    private let visibleBannerHeight: CGFloat = 120

    private var backgroundURL: URL? {
        let overview = viewModel.spaceOverview
        let source = colorScheme == .dark
            ? overview?.nightBackgroundURL ?? overview?.backgroundURL : overview?.backgroundURL
        return source.flatMap { URL(string: $0.biliImageThumbnailURL(maxSide: 960)) }
    }

    var body: some View {
        GeometryReader { geometry in
            scrollContent
                .background(alignment: .top) {
                    if let backgroundURL {
                        // Outside the ScrollView: pull-to-refresh moves content, never the banner.
                        CachedRemoteImage(url: backgroundURL, targetPixelSize: 960) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Rectangle().fill(.quaternary)
                        }
                        .frame(width: geometry.size.width,
                               height: visibleBannerHeight + geometry.safeAreaInsets.top)
                        .clipped()
                        .offset(y: -geometry.safeAreaInsets.top)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
        }
        .background(.background)
        .toolbarBackground(backgroundURL == nil ? .automatic : .hidden, for: .navigationBar)
        .task { await viewModel.loadInitial() }
        .task(id: selectedSection) {
            switch selectedSection {
            case .home: break
            case .videos: await viewModel.loadVideosIfNeeded()
            case .dynamics: await viewModel.loadDynamicsIfNeeded()
            case .collections: await viewModel.loadSeasonSeriesIfNeeded()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: URL(string: "https://space.bilibili.com/\(owner.mid)")!) {
                        Label("分享个人空间", systemImage: "square.and.arrow.up")
                    }
                    if showsToolbarRefreshButton {
                        Button { Task { await refreshSelectedSection() } } label: {
                            Label("刷新", systemImage: "arrow.clockwise")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("个人空间操作")
            }
        }
    }

    @ViewBuilder private var scrollContent: some View {
        if allowsPullToRefresh {
            baseScrollContent.refreshable { await refreshSelectedSection() }
        } else { baseScrollContent }
    }

    private var baseScrollContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                UploaderContentWidthReader()
                if backgroundURL != nil {
                    Color.clear.frame(height: visibleBannerHeight)
                        .accessibilityHidden(true)
                }
                LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                    UploaderEnhancedHeaderView(owner: owner, viewModel: viewModel)
                        .padding(.top, backgroundURL == nil ? 12 : 14)
                    Section {
                        selectedContent
                    } header: {
                        Picker("空间内容", selection: $selectedSection) {
                            ForEach(SpaceSection.allCases) { section in
                                Text(section.title).tag(section)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, libraryStore.standardPageHorizontalInset)
                        .padding(.vertical, 8)
                        .background(.background)
                        .accessibilityIdentifier("uploader.space.sections")
                    }
                }
                .padding(.bottom, 24)
                .background(.background)
            }
        }
        .onPreferenceChange(UploaderContentWidthPreferenceKey.self) { width in
            let rounded = width.rounded(.down)
            if abs(rounded - contentWidth) > 0.5 { contentWidth = rounded }
        }
    }

    @ViewBuilder private var selectedContent: some View {
        switch selectedSection {
        case .home:
            UploaderSpaceOverviewContent(viewModel: viewModel, metrics: metrics) { selectedSection = .videos }
        case .videos:
            UploaderVideosSection(viewModel: viewModel, metrics: metrics)
        case .dynamics:
            UploaderDynamicsSection(api: dependencies.api, viewModel: viewModel,
                                   contentWidth: contentWidth,
                                   horizontalInset: libraryStore.standardPageHorizontalInset)
        case .collections:
            UploaderSeasonSeriesSection(viewModel: viewModel,
                                        horizontalInset: libraryStore.standardPageHorizontalInset)
        }
    }

    private func refreshSelectedSection() async {
        switch selectedSection {
        case .home: await viewModel.loadSpaceOverview(force: true)
        case .videos: await viewModel.refresh()
        case .dynamics: await viewModel.refreshDynamics()
        case .collections: await viewModel.refreshSeasonSeries()
        }
    }
}

private enum SpaceSection: String, CaseIterable, Identifiable {
    case home, dynamics, videos, collections
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: "主页"
        case .dynamics: "动态"
        case .videos: "投稿"
        case .collections: "合集"
        }
    }
}

private struct UploaderSpaceOverviewContent: View {
    @ObservedObject var viewModel: UploaderViewModel
    let metrics: HomeFeedLayoutMetrics
    let showVideos: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if case .failed(let message) = viewModel.spaceOverviewState {
                ErrorStateView(title: "主页概览加载失败", message: message) {
                    Task { await viewModel.loadSpaceOverview(force: true) }
                }
                .padding(.horizontal, metrics.feedHorizontalPadding)
            }
            if let overview = viewModel.spaceOverview {
                videoSection("投稿", group: overview.archive, defaultMID: viewModel.seedOwner.mid, limit: 4,
                             showMore: true)
                favoritesSection(overview)
                videoSection("最近点赞的视频", group: overview.likes, defaultMID: 0, limit: 2,
                             isPublic: overview.privacy?.likesVisible)
                videoSection("最近投币的视频", group: overview.coins, defaultMID: 0, limit: 2,
                             isPublic: overview.privacy?.coinsVisible)
                bangumiSection(overview)
                if !overview.hasPreviewContent {
                    EmptyStateView(title: "暂无内容概览", systemImage: "person.crop.rectangle",
                                   message: "可切换到动态、投稿或合集查看公开内容。")
                        .frame(maxWidth: .infinity)
                }
            } else if viewModel.spaceOverviewState.isLoading {
                HomeFeedSkeletonSection(metrics: metrics)
            }
        }
    }

    @ViewBuilder private func videoSection(
        _ title: String, group: UploaderSpaceVideoGroup?, defaultMID: Int, limit: Int,
        isPublic: Bool? = nil, showMore: Bool = false
    ) -> some View {
        let videos = group?.items.compactMap { $0.video(defaultMID: defaultMID) } ?? []
        if !videos.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                heading(title, count: group?.count, isPublic: isPublic, showMore: showMore)
                LazyVGrid(columns: metrics.feedColumns, spacing: metrics.feedSpacing) {
                    ForEach(Array(videos.prefix(limit).enumerated()), id: \.offset) { _, video in
                        VideoRouteLink(video) {
                            HomeFeedVideoCardLabel(metrics: metrics, display: VideoCardDisplayModel(video: video),
                                                   showsAuthorIdentity: false, usesGenericAuthorIcon: false)
                        }
                    }
                }
            }
            .padding(.horizontal, metrics.feedHorizontalPadding)
        }
    }

    private func heading(_ title: String, count: Int?, isPublic: Bool? = nil, showMore: Bool = false) -> some View {
        HStack {
            Text(title).font(.headline)
            if let count { Text(BiliFormatters.compactCount(count)).foregroundStyle(.secondary) }
            if viewModel.isOwnSpace, isPublic == false {
                Image(systemName: "eye.slash").foregroundStyle(.secondary).accessibilityLabel("仅自己可见")
            }
            Spacer(minLength: 0)
            if showMore {
                Button(action: showVideos) { Label("查看更多", systemImage: "chevron.right") }
                    .font(.subheadline)
            }
        }
    }

    @ViewBuilder private func favoritesSection(_ overview: UploaderSpaceOverview) -> some View {
        if let favorites = overview.favorites, !favorites.items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                heading("收藏", count: favorites.count, isPublic: overview.privacy?.favoritesVisible)
                ForEach(Array(favorites.items.prefix(2).enumerated()), id: \.offset) { _, item in
                    if item.folder.id > 0 {
                        // Same canonical folder share URL used by PiliPlus's favorite detail page.
                        Link(destination: URL(string: "https://www.bilibili.com/medialist/detail/ml\(item.folder.id)")!) {
                            HStack(spacing: 12) {
                                SpacePreviewCover(urlString: item.folder.cover)
                                    .frame(width: 120, height: 76)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.folder.title ?? "收藏夹").font(.subheadline.weight(.semibold))
                                    HStack(spacing: 6) {
                                        if let count = item.count ?? item.folder.mediaCount { Text("\(count) 个内容") }
                                        if let isPublic = item.isPublic { Text(isPublic ? "公开" : "私密") }
                                    }
                                    .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("在浏览器打开收藏夹")
                    }
                }
            }
            .padding(.horizontal, metrics.feedHorizontalPadding)
        }
    }

    @ViewBuilder private func bangumiSection(_ overview: UploaderSpaceOverview) -> some View {
        let items = overview.bangumi?.items.filter { $0.seasonID != nil } ?? []
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                heading("追番", count: overview.bangumi?.count, isPublic: overview.privacy?.bangumiVisible)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { _, item in
                            SpaceSeasonPreview(item: item)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, metrics.feedHorizontalPadding)
        }
    }
}

private struct SpaceSeasonPreview: View {
    @Environment(\.openPgcSeasonRouteAction) private var openSeason
    let item: UploaderSpaceVideoPreview
    var body: some View {
        if let id = item.seasonID {
            let route = PgcSeasonRoute(seasonID: id, title: item.archive.title, cover: item.archive.cover)
            Group {
                if let openSeason {
                    Button { openSeason(route) } label: { label }
                } else { NavigationLink(value: route) { label } }
            }
            .buttonStyle(.plain)
        }
    }
    private var label: some View {
        VStack(alignment: .leading, spacing: 6) {
            SpacePreviewCover(urlString: item.archive.cover).frame(width: 112, height: 150)
            Text(item.archive.title).font(.subheadline).lineLimit(2)
        }
        .frame(width: 112, alignment: .leading)
    }
}

private struct SpacePreviewCover: View {
    let urlString: String?
    var body: some View {
        CachedRemoteImage(url: urlString.flatMap { URL(string: $0.biliImageThumbnailURL(maxSide: 480)) }, targetPixelSize: 480) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Rectangle().fill(.quaternary)
                .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
