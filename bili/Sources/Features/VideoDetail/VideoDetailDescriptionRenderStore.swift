import Combine
import Foundation

@MainActor
final class VideoDetailDescriptionRenderStore: ObservableObject {
    @Published private var snapshot = VideoDetailDescriptionRenderSnapshot()

    var titleText: String { snapshot.titleText }
    var owner: VideoOwner? { snapshot.owner }
    var viewCountText: String { snapshot.viewCountText }
    var fanCountText: String { snapshot.fanCountText }
    var publishDateText: String { snapshot.publishDateText }
    var publishDateSubtitleText: String? { snapshot.publishDateSubtitleText }
    var descriptionText: String { snapshot.descriptionText }
    var hasResolvedDetailMetadata: Bool { snapshot.hasResolvedDetailMetadata }
    var canFavorite: Bool { snapshot.canFavorite }
    var shareURL: URL? { snapshot.shareURL }
    var shareSubject: String { snapshot.shareSubject }
    var shareMessage: String { snapshot.shareMessage }
    var isFollowing: Bool { snapshot.isFollowing }
    var isMutatingInteraction: Bool { snapshot.isMutatingInteraction }

    func update(_ next: VideoDetailDescriptionRenderSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
    }
}
