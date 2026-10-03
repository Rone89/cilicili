import Combine
import SwiftUI

@MainActor
final class RootHomeViewModelHolder: ObservableObject {
    @Published var viewModel: HomeViewModel?

    func configure(
        api: BiliAPIClient,
        libraryStore: LibraryStore,
        sessionStore: SessionStore,
        initialMode: HomeFeedMode
    ) {
        if viewModel == nil {
            let viewModel = HomeViewModel(
                api: api,
                libraryStore: libraryStore,
                sessionStore: sessionStore,
                initialMode: initialMode
            )
            self.viewModel = viewModel
        }
    }
}

extension View {
    func videoDestinations() -> some View {
        navigationDestination(for: VideoItem.self) { video in
            VideoDetailView(
                seedVideo: video
            )
        }
        .navigationDestination(for: VideoCommentRoute.self) { route in
            VideoDetailView(
                seedVideo: route.video,
                initialCommentAnchor: route.anchor
            )
        }
        .navigationDestination(for: PgcSeasonRoute.self) { route in
            PgcSeasonPlaybackRouteView(route: route)
                .navigationHistoryTitle(route.title)
        }
        .navigationDestination(for: VideoOwner.self) { owner in
            UploaderView(owner: owner)
                .navigationHistoryTitle(owner.name)
        }
        .navigationDestination(for: LiveRoom.self) { room in
            LiveRoomDetailView(seedRoom: room)
                .navigationHistoryTitle(room.title)
        }
    }
}

enum RootTab: String, Hashable {
    case home
    case search
    case dynamic
    case live
    case mine

    init?(argumentValue: String) {
        guard let tab = RootTab(rawValue: argumentValue.lowercased()) else {
            return nil
        }
        self = tab
    }

    var appTab: AppTab {
        switch self {
        case .home:
            return .home
        case .search:
            return .search
        case .dynamic:
            return .dynamic
        case .live:
            return .live
        case .mine:
            return .mine
        }
    }

    var title: String {
        appTab.title
    }

    var systemImage: String {
        appTab.systemImage
    }
}
