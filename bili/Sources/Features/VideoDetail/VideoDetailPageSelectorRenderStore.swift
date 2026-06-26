import Combine
import Foundation

@MainActor
final class VideoDetailPageSelectorRenderStore: ObservableObject {
    @Published private var snapshot = VideoDetailPageSelectorRenderSnapshot()

    var pages: [VideoPage] { snapshot.pages }
    var selectedCID: Int? { snapshot.selectedCID }
    var pageCountText: String { snapshot.pageCountText }
    var shouldShowPageSelector: Bool { snapshot.shouldShowPageSelector }

    func update(_ next: VideoDetailPageSelectorRenderSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
    }
}
