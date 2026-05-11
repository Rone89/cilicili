import Foundation
import Combine

enum SearchSortOrder: String, CaseIterable, Identifiable, Hashable {
    case comprehensive
    case mostPlayed
    case newest
    case mostDanmaku
    case mostSaved

    var id: String { rawValue }

    var title: String {
        switch self {
        case .comprehensive:
            return "综合排序"
        case .mostPlayed:
            return "最多播放"
        case .newest:
            return "最新发布"
        case .mostDanmaku:
            return "最多弹幕"
        case .mostSaved:
            return "最多收藏"
        }
    }

    var shortTitle: String {
        switch self {
        case .comprehensive:
            return "综合"
        case .mostPlayed:
            return "播放"
        case .newest:
            return "最新"
        case .mostDanmaku:
            return "弹幕"
        case .mostSaved:
            return "收藏"
        }
    }

    var apiValue: String? {
        switch self {
        case .comprehensive:
            return nil
        case .mostPlayed:
            return "click"
        case .newest:
            return "pubdate"
        case .mostDanmaku:
            return "dm"
        case .mostSaved:
            return "stow"
        }
    }
}

enum SearchScope: String, CaseIterable, Identifiable, Hashable {
    case video
    case user
    case bangumi
    case movie
    case article

    var id: String { rawValue }

    var title: String {
        switch self {
        case .video:
            return "视频"
        case .user:
            return "UP主"
        case .bangumi:
            return "番剧"
        case .movie:
            return "影视"
        case .article:
            return "专栏"
        }
    }

    var systemImage: String {
        switch self {
        case .video:
            return "play.rectangle"
        case .user:
            return "person.crop.circle"
        case .bangumi:
            return "sparkles.tv"
        case .movie:
            return "film"
        case .article:
            return "doc.text"
        }
    }

    var supportsOrder: Bool {
        self == .video
    }
}

enum SearchResultItem: Identifiable, Hashable {
    case video(VideoItem)
    case user(SearchUserItem)
    case bangumi(SearchMediaItem)
    case movie(SearchMediaItem)
    case article(SearchArticleItem)

    var id: String {
        switch self {
        case .video(let video):
            return "video-\(video.id)"
        case .user(let user):
            return "user-\(user.id)"
        case .bangumi(let media):
            return "bangumi-\(media.id)"
        case .movie(let media):
            return "movie-\(media.id)"
        case .article(let article):
            return "article-\(article.id)"
        }
    }
}

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var selectedScope: SearchScope = .video
    @Published var selectedOrder: SearchSortOrder = .comprehensive
    @Published var hotSearches: [HotSearchItem] = []
    @Published var suggestions: [SearchSuggestItem] = []
    @Published var results: [SearchResultItem] = []
    @Published var state: LoadingState = .idle

    private let api: BiliAPIClient
    private let debouncer = TaskDebouncer()
    private var page = 1
    private var lastKeyword = ""
    private var hasMore = false

    init(api: BiliAPIClient) {
        self.api = api
    }

    var showsDiscovery: Bool {
        results.isEmpty && lastKeyword.isEmpty
    }

    var showsEmptyResults: Bool {
        results.isEmpty && !lastKeyword.isEmpty && state == .loaded
    }

    var resultSectionTitle: String {
        "\(selectedScope.title)结果"
    }

    func loadHotSearch() async {
        do {
            hotSearches = try await api.fetchHotSearch()
        } catch {
            hotSearches = []
        }
    }

    func queryChanged() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            suggestions = []
            results = []
            lastKeyword = ""
            hasMore = false
            state = .idle
            return
        }
        if term != lastKeyword {
            results = []
            lastKeyword = ""
            hasMore = false
            state = .idle
        }
        debouncer.schedule { [weak self] in
            await self?.loadSuggestions(term: term)
        }
    }

    func clearQuery() {
        query = ""
        suggestions = []
        results = []
        lastKeyword = ""
        hasMore = false
        state = .idle
    }

    func search(_ keyword: String? = nil) async {
        let term = (keyword ?? query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        query = term
        page = 1
        lastKeyword = term
        hasMore = false
        suggestions = []
        state = .loading
        do {
            let fetched = try await fetchResults(keyword: term, page: page)
            results = fetched
            hasMore = !fetched.isEmpty
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func selectScope(_ scope: SearchScope) async {
        guard selectedScope != scope else { return }
        selectedScope = scope
        guard !lastKeyword.isEmpty else { return }
        await search(lastKeyword)
    }

    func selectOrder(_ order: SearchSortOrder) async {
        guard selectedOrder != order else { return }
        selectedOrder = order
        guard selectedScope.supportsOrder, !lastKeyword.isEmpty else { return }
        await search(lastKeyword)
    }

    func loadMoreIfNeeded(current item: SearchResultItem?) async {
        guard let item,
              results.last?.id == item.id,
              !state.isLoading,
              !lastKeyword.isEmpty,
              hasMore
        else { return }
        page += 1
        state = .loading
        do {
            let more = try await fetchResults(keyword: lastKeyword, page: page)
            if more.isEmpty {
                hasMore = false
            }
            appendUnique(more)
            state = .loaded
        } catch {
            page = max(1, page - 1)
            state = .failed(error.localizedDescription)
        }
    }

    private func fetchResults(keyword: String, page: Int) async throws -> [SearchResultItem] {
        switch selectedScope {
        case .video:
            return try await api.searchVideos(keyword: keyword, page: page, order: selectedOrder.apiValue)
                .map(SearchResultItem.video)
        case .user:
            return try await api.searchUsers(keyword: keyword, page: page)
                .map(SearchResultItem.user)
        case .bangumi:
            return try await api.searchBangumi(keyword: keyword, page: page)
                .map(SearchResultItem.bangumi)
        case .movie:
            return try await api.searchMovies(keyword: keyword, page: page)
                .map(SearchResultItem.movie)
        case .article:
            return try await api.searchArticles(keyword: keyword, page: page)
                .map(SearchResultItem.article)
        }
    }

    private func loadSuggestions(term: String) async {
        do {
            suggestions = try await api.fetchSearchSuggest(term: term)
        } catch {
            suggestions = []
        }
    }

    private func appendUnique(_ more: [SearchResultItem]) {
        let existing = Set(results.map(\.id))
        results.append(contentsOf: more.filter { !existing.contains($0.id) })
    }
}
