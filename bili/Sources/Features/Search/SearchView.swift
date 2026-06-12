import SwiftUI
import Combine

struct SearchView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @StateObject private var holder = SearchViewModelHolder()

    var body: some View {
        Group {
            if let viewModel = holder.viewModel {
                content(viewModel)
            } else {
                SearchLoadingList()
                    .task {
                        holder.configure(api: dependencies.api)
                    }
            }
        }
        .rootNavigationTitle("搜索")
        .nativeTopNavigationChrome()
    }

    @ViewBuilder
    private func content(_ viewModel: SearchViewModel) -> some View {
        searchList(viewModel)
            .searchable(
                text: Binding(
                    get: { viewModel.query },
                    set: { query in
                        viewModel.query = query
                        viewModel.queryChanged()
                    }
                ),
                placement: .automatic,
                prompt: "搜索视频、UP主、番剧、影视、专栏"
            )
            .searchScopes(Binding(
                get: { viewModel.selectedScope },
                set: { scope in
                    Task { await viewModel.selectScope(scope) }
                }
            )) {
                ForEach(SearchScope.allCases) { scope in
                    Text(scope.title)
                        .tag(scope)
                }
            }
            .searchSuggestions {
                ForEach(viewModel.suggestions) { item in
                    Label(item.value, systemImage: "magnifyingglass")
                        .searchCompletion(item.value)
                }
            }
            .onSubmit(of: .search) {
                Task { await viewModel.search() }
            }
            .overlay {
                if case .failed(let message) = viewModel.state, viewModel.results.isEmpty {
                    ErrorStateView(title: "搜索失败", message: message) {
                        Task { await viewModel.search() }
                    }
                }
            }
            .task {
                await viewModel.loadHotSearch()
            }
    }

    private func searchList(_ viewModel: SearchViewModel) -> some View {
        List {
            if viewModel.showsDiscovery {
                if viewModel.state.isLoading {
                    loadingSection(viewModel)
                }

                if viewModel.hotSearches.isEmpty {
                    EmptyStateView(title: "暂无热门搜索", systemImage: "magnifyingglass", message: "输入关键词后搜索。")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(Array(viewModel.hotSearches.enumerated()), id: \.element.id) { index, item in
                            Button {
                                Task { await viewModel.search(item.keyword) }
                            } label: {
                                SearchHotSearchRow(item: item, index: index)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("热门搜索第 \(index + 1) 名，\(item.showName ?? item.keyword)")
                        }
                    } header: {
                        SearchSectionHeader(title: "热门搜索", systemImage: "flame")
                    }
                }
            } else if viewModel.results.isEmpty && viewModel.state.isLoading {
                loadingSection(viewModel)
            } else if viewModel.showsEmptyResults {
                EmptyStateView(
                    title: "没有找到\(viewModel.selectedScope.title)",
                    systemImage: viewModel.selectedScope.systemImage,
                    message: "换个关键词或切换搜索类型试试。"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .listRowBackground(Color.clear)
            } else {
                if viewModel.selectedScope.supportsOrder {
                    sortSection(viewModel)
                }

                Section {
                    let results = viewModel.results
                    let lastResultID = results.last?.id
                    ForEach(results) { result in
                        resultRow(result)
                            .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
                            .searchLoadMoreTask(if: result.id == lastResultID, id: result.id) {
                                await viewModel.loadMoreIfNeeded(current: result)
                            }
                    }

                    if viewModel.state.isLoading {
                        ForEach(0..<2, id: \.self) { _ in
                            SearchResultSkeletonRow()
                                .allowsHitTesting(false)
                        }
                    }
                } header: {
                    SearchSectionHeader(title: viewModel.resultSectionTitle, systemImage: viewModel.selectedScope.systemImage)
                }
            }
        }
        .nativeTopScrollEdgeEffect()
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .refreshable {
            if viewModel.showsDiscovery {
                await viewModel.loadHotSearch()
            } else {
                await viewModel.search(viewModel.query)
            }
        }
    }

    private func loadingSection(_ viewModel: SearchViewModel) -> some View {
        Section {
            ForEach(0..<4, id: \.self) { _ in
                SearchResultSkeletonRow()
                    .allowsHitTesting(false)
            }
        } header: {
            SearchSectionHeader(title: "正在搜索", systemImage: "magnifyingglass")
        }
    }

    private func sortSection(_ viewModel: SearchViewModel) -> some View {
        Section {
            Picker(
                "排序",
                selection: Binding(
                    get: { viewModel.selectedOrder },
                    set: { order in
                        Task { await viewModel.selectOrder(order) }
                    }
                )
            ) {
                ForEach(SearchSortOrder.allCases) { order in
                    Text(order.shortTitle)
                        .tag(order)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .padding(.vertical, 2)
        } header: {
            SearchSectionHeader(title: "排序", systemImage: "arrow.up.arrow.down")
        }
    }

    @ViewBuilder
    private func resultRow(_ result: SearchResultItem) -> some View {
        switch result {
        case .video(let video):
            VideoRouteLink(video) {
                SearchVideoResultRow(video: video)
            }
        case .user(let user):
            NavigationLink(value: user.owner) {
                SearchUserResultRow(user: user)
            }
        case .bangumi(let media):
            externalMediaRow(media, kind: "番剧")
        case .movie(let media):
            externalMediaRow(media, kind: "影视")
        case .article(let article):
            if let url = article.destinationURL {
                Link(destination: url) {
                    SearchArticleResultRow(article: article)
                }
            } else {
                SearchArticleResultRow(article: article)
            }
        }
    }

    @ViewBuilder
    private func externalMediaRow(_ media: SearchMediaItem, kind: String) -> some View {
        if let url = media.destinationURL {
            Link(destination: url) {
                SearchMediaResultRow(media: media, kind: kind)
            }
        } else {
            SearchMediaResultRow(media: media, kind: kind)
        }
    }
}

private struct SearchLoadingList: View {
    var body: some View {
        List {
            Section {
                ForEach(0..<4, id: \.self) { _ in
                    SearchResultSkeletonRow()
                }
            } header: {
                SearchSectionHeader(title: "搜索", systemImage: "magnifyingglass")
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .nativeTopScrollEdgeEffect()
    }
}

private struct SearchSectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .textCase(nil)
    }
}

private struct SearchHotSearchRow: View {
    let item: HotSearchItem
    let index: Int

    var body: some View {
        HStack(spacing: 12) {
            SearchRankBadge(index: index)

            Text(item.showName ?? item.keyword)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Image(systemName: "magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct SearchRankBadge: View {
    let index: Int

    private var rankColor: Color {
        switch index {
        case 0:
            return .pink
        case 1:
            return .orange
        case 2:
            return .yellow
        default:
            return .secondary
        }
    }

    var body: some View {
        Text("\(index + 1)")
            .font(.caption2.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(index < 3 ? .white : rankColor)
            .frame(width: 22, height: 22)
            .background {
                if index < 3 {
                    Circle()
                        .fill(rankColor.gradient)
                } else {
                    Circle()
                        .fill(Color(.tertiarySystemFill))
                }
            }
            .accessibilityHidden(true)
    }
}

private struct SearchVideoResultRow: View {
    private let display: VideoCardDisplayModel

    init(video: VideoItem) {
        self.display = VideoCardDisplayModel(video: video)
    }

    var body: some View {
        VideoCompactListRow(
            display: display,
            coverSize: CGSize(width: 118, height: 66),
            coverCornerRadius: 10,
            showsCoverBorder: true,
            titleMinHeight: 36,
            authorStyle: .icon("person.crop.circle"),
            metadataStyle: .search
        )
    }
}

private struct SearchUserResultRow: View {
    let user: SearchUserItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarRemoteImage(urlString: user.face, pixelSize: 112) {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
            .frame(width: 54, height: 54)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(.quaternary, lineWidth: 0.7)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(user.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    if user.isFollowing == true {
                        Label("已关注", systemImage: "checkmark.circle.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.pink)
                    }
                }

                if let sign = user.sign, !sign.isEmpty {
                    Text(sign)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let officialDescription = user.officialDescription, !officialDescription.isEmpty {
                    Text(officialDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 12) {
                    SearchMetadataLabel(text: BiliFormatters.compactCount(user.fans), systemImage: "person.2")
                    SearchMetadataLabel(text: BiliFormatters.compactCount(user.videos), systemImage: "play.square.stack")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
        }
        .contentShape(Rectangle())
    }
}

private struct SearchMediaResultRow: View {
    let media: SearchMediaItem
    let kind: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CachedRemoteImage(
                url: media.cover.flatMap { URL(string: $0.biliCoverThumbnailURL(width: 216, height: 288)) },
                fallbackURL: media.cover.map { $0.normalizedBiliURL() }.flatMap(URL.init(string:)),
                targetPixelSize: 288,
                animatesAppearance: false
            ) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                SearchImagePlaceholder(systemImage: "film")
            }
            .frame(width: 76, height: 102)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.quaternary, lineWidth: 0.7)
            }
            .mediaShadow(.subtle)

            VStack(alignment: .leading, spacing: 5) {
                Text(media.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    SearchSoftPill(media.typeName ?? kind)
                    if let rating = media.rating, !rating.isEmpty {
                        SearchSoftPill("\(rating)分", tint: .pink)
                    }
                    if let indexShow = media.indexShow, !indexShow.isEmpty {
                        Text(indexShow)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if let stylesText = media.stylesText, !stylesText.isEmpty {
                    Text(stylesText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let description = media.description, !description.isEmpty {
                    Text(description.removingHTMLTags())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 102, alignment: .topLeading)
        }
        .contentShape(Rectangle())
    }
}

private struct SearchArticleResultRow: View {
    let article: SearchArticleItem

    private var publishDate: String {
        BiliFormatters.publishDate(article.pubTime)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            let sourceURLString = article.imageURLs.first?.normalizedBiliURL()
            CachedRemoteImage(
                url: sourceURLString.flatMap { URL(string: $0.biliCoverThumbnailURL(width: 228, height: 228)) },
                fallbackURL: sourceURLString.flatMap(URL.init(string:)),
                targetPixelSize: 228,
                animatesAppearance: false
            ) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                SearchImagePlaceholder(systemImage: "doc.text")
            }
            .frame(width: 78, height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.quaternary, lineWidth: 0.7)
            }
            .mediaShadow(.subtle)

            VStack(alignment: .leading, spacing: 5) {
                Text(article.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let author = article.author, !author.isEmpty {
                        Text(author)
                    }
                    if publishDate != "-" {
                        Text(publishDate)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if let description = article.description, !description.isEmpty {
                    Text(description.removingHTMLTags())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 12) {
                    SearchMetadataLabel(text: BiliFormatters.compactCount(article.view), systemImage: "eye")
                    SearchMetadataLabel(text: BiliFormatters.compactCount(article.reply), systemImage: "bubble.left")
                    SearchMetadataLabel(text: BiliFormatters.compactCount(article.like), systemImage: "hand.thumbsup")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        }
        .contentShape(Rectangle())
    }
}

private struct SearchMetadataLabel: View {
    let text: String
    let systemImage: String

    @ViewBuilder
    var body: some View {
        if !text.isEmpty, text != "-" {
            Label(text, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
        }
    }
}

private struct SearchSoftPill: View {
    let text: String
    let tint: Color

    init(_ text: String, tint: Color = .secondary) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(.tertiarySystemFill), in: Capsule())
    }
}

private struct SearchImagePlaceholder: View {
    let systemImage: String

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(.tertiarySystemFill))
            .overlay {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
    }
}

private extension View {
    @ViewBuilder
    func searchLoadMoreTask<ID: Equatable>(
        if condition: Bool,
        id: ID,
        action: @escaping () async -> Void
    ) -> some View {
        if condition {
            task(id: id) {
                await action()
            }
        } else {
            self
        }
    }
}

@MainActor
final class SearchViewModelHolder: ObservableObject {
    @Published var viewModel: SearchViewModel?
    private var cancellable: AnyCancellable?
    private var lastSnapshot: SearchRenderSnapshot?

    func configure(api: BiliAPIClient) {
        if viewModel == nil {
            let viewModel = SearchViewModel(api: api)
            self.viewModel = viewModel
            lastSnapshot = SearchRenderSnapshot(viewModel)
            cancellable = viewModel.objectWillChange.sink { [weak self] _ in
                Task { @MainActor [weak self, weak viewModel] in
                    guard let self, let viewModel else { return }
                    let snapshot = SearchRenderSnapshot(viewModel)
                    guard snapshot != self.lastSnapshot else { return }
                    self.lastSnapshot = snapshot
                    self.objectWillChange.send()
                }
            }
        }
    }
}

private struct SearchRenderSnapshot: Equatable {
    let query: String
    let selectedScope: SearchScope
    let selectedOrder: SearchSortOrder
    let state: LoadingState
    let hotSearchCount: Int
    let hotSearchRevision: Int
    let suggestionCount: Int
    let suggestionRevision: Int
    let resultCount: Int
    let firstResultID: String?
    let lastResultID: String?
    let resultRevision: Int

    init(_ viewModel: SearchViewModel) {
        query = viewModel.query
        selectedScope = viewModel.selectedScope
        selectedOrder = viewModel.selectedOrder
        state = viewModel.state
        hotSearchCount = viewModel.hotSearches.count
        hotSearchRevision = viewModel.hotSearchesRevision
        suggestionCount = viewModel.suggestions.count
        suggestionRevision = viewModel.suggestionsRevision
        resultCount = viewModel.results.count
        firstResultID = viewModel.results.first?.id
        lastResultID = viewModel.results.last?.id
        resultRevision = viewModel.resultsRevision
    }
}
