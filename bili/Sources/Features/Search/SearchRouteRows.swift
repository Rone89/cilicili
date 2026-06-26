import SwiftUI

struct SearchScopeMenu: View {
    @ObservedObject var viewModel: SearchViewModel

    var body: some View {
        Menu {
            ForEach(SearchScope.allCases) { scope in
                Button {
                    Task { await viewModel.selectScope(scope) }
                } label: {
                    Label(scope.title, systemImage: scope.systemImage)
                }
            }
        } label: {
            Image(systemName: viewModel.selectedScope.systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .biliPlayerClearGlass(interactive: true, in: Circle())
        .accessibilityLabel("搜索类型")
        .accessibilityValue(viewModel.selectedScope.title)
    }
}

struct SearchResultRouteRow: View {
    let result: SearchResultItem

    var body: some View {
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
            SearchExternalMediaRouteRow(media: media, kind: "番剧")
        case .movie(let media):
            SearchExternalMediaRouteRow(media: media, kind: "影视")
        case .article(let article):
            SearchArticleRouteRow(article: article)
        }
    }
}

private struct SearchExternalMediaRouteRow: View {
    let media: SearchMediaItem
    let kind: String

    var body: some View {
        if let url = media.destinationURL {
            Link(destination: url) {
                SearchMediaResultRow(media: media, kind: kind)
            }
        } else {
            SearchMediaResultRow(media: media, kind: kind)
        }
    }
}

private struct SearchArticleRouteRow: View {
    let article: SearchArticleItem

    var body: some View {
        if let url = article.destinationURL {
            Link(destination: url) {
                SearchArticleResultRow(article: article)
            }
        } else {
            SearchArticleResultRow(article: article)
        }
    }
}
