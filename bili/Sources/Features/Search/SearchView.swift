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
                ProgressView()
                    .task {
                        holder.configure(api: dependencies.api)
                    }
            }
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.large)
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
            Section {
                Picker("搜索类型", selection: Binding(
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
                .pickerStyle(.segmented)
            }

            if viewModel.showsDiscovery {
                if viewModel.state.isLoading {
                    loadingSection(viewModel)
                }

                if !viewModel.suggestions.isEmpty {
                    Section("搜索建议") {
                        ForEach(viewModel.suggestions) { item in
                            Button(item.value) {
                                Task { await viewModel.search(item.value) }
                            }
                        }
                    }
                }

                if viewModel.hotSearches.isEmpty {
                    EmptyStateView(title: "暂无热门搜索", systemImage: "magnifyingglass", message: "输入关键词后搜索。")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                } else {
                    Section("热门搜索") {
                        ForEach(viewModel.hotSearches) { item in
                            Button(item.showName ?? item.keyword) {
                                Task { await viewModel.search(item.keyword) }
                            }
                        }
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
                .padding(.vertical, 16)
            } else {
                if viewModel.selectedScope.supportsOrder {
                    sortSection(viewModel)
                }

                Section(viewModel.resultSectionTitle) {
                    ForEach(viewModel.results) { result in
                        resultRow(result)
                            .task {
                                await viewModel.loadMoreIfNeeded(current: result)
                            }
                    }

                    if viewModel.state.isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 10)
                    }
                }
            }
        }
        .nativeTopScrollEdgeEffect()
    }

    private func loadingSection(_ viewModel: SearchViewModel) -> some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 10) {
                    ProgressView()
                    Text("正在搜索 \(viewModel.query)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.vertical, 18)
        }
    }

    private func sortSection(_ viewModel: SearchViewModel) -> some View {
        Section {
            Menu {
                ForEach(SearchSortOrder.allCases) { order in
                    Button {
                        Task { await viewModel.selectOrder(order) }
                    } label: {
                        Label(order.title, systemImage: viewModel.selectedOrder == order ? "checkmark" : "line.3.horizontal.decrease.circle")
                    }
                }
            } label: {
                HStack {
                    Label(viewModel.selectedOrder.title, systemImage: "arrow.up.arrow.down")
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)
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

private struct SearchVideoResultRow: View {
    let video: VideoItem

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: video.pic.flatMap { URL(string: $0.biliCoverThumbnailURL(width: 360, height: 225)) }) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.gray.opacity(0.14)
            }
            .frame(width: 112, height: 70)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(video.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                Text(video.owner?.name ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Label(BiliFormatters.compactCount(video.stat?.view), systemImage: "play.rectangle")
                    Label(BiliFormatters.compactCount(video.stat?.danmaku), systemImage: "text.bubble")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SearchUserResultRow: View {
    let user: SearchUserItem

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: user.face.flatMap { URL(string: $0.normalizedBiliURL().biliAvatarThumbnailURL(size: 112)) }) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(user.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    if user.isFollowing == true {
                        Text("已关注")
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
                    Label(BiliFormatters.compactCount(user.fans), systemImage: "person.2")
                    Label(BiliFormatters.compactCount(user.videos), systemImage: "play.square.stack")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SearchMediaResultRow: View {
    let media: SearchMediaItem
    let kind: String

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: media.cover.flatMap { URL(string: $0.biliCoverThumbnailURL(width: 216, height: 288)) }) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.gray.opacity(0.14)
            }
            .frame(width: 72, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(media.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(media.typeName ?? kind)
                    if let rating = media.rating, !rating.isEmpty {
                        Text("\(rating)分")
                            .foregroundStyle(.pink)
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
        }
    }
}

private struct SearchArticleResultRow: View {
    let article: SearchArticleItem

    private var publishDate: String {
        BiliFormatters.publishDate(article.pubTime)
    }

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: article.imageURLs.first.flatMap { URL(string: $0.biliCoverThumbnailURL(width: 228, height: 228)) }) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.gray.opacity(0.14)
                    .overlay {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: 76, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
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
                    Label(BiliFormatters.compactCount(article.view), systemImage: "eye")
                    Label(BiliFormatters.compactCount(article.reply), systemImage: "bubble.left")
                    Label(BiliFormatters.compactCount(article.like), systemImage: "hand.thumbsup")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
final class SearchViewModelHolder: ObservableObject {
    @Published var viewModel: SearchViewModel?
    private var cancellable: AnyCancellable?

    func configure(api: BiliAPIClient) {
        if viewModel == nil {
            let viewModel = SearchViewModel(api: api)
            self.viewModel = viewModel
            cancellable = viewModel.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
    }
}
