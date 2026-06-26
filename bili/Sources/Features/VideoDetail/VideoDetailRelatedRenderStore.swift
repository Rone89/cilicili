import Combine
import Foundation

@MainActor
final class VideoDetailRelatedRenderStore: ObservableObject {
    @Published private var snapshot = VideoDetailRelatedRenderSnapshot()

    var related: [VideoItem] { snapshot.related }
    var relatedItems: [VideoDetailRelatedDisplayItem] { snapshot.relatedItems }
    var state: LoadingState { snapshot.state }
    var lastLoadTimedOut: Bool { snapshot.lastLoadTimedOut }

    func update(related: [VideoItem], state: LoadingState, lastLoadTimedOut: Bool) {
        setSnapshot(
            VideoDetailRelatedRenderSnapshot(
                related: related,
                state: state,
                lastLoadTimedOut: lastLoadTimedOut
            )
        )
    }

    func updateRelated(_ related: [VideoItem]) {
        updateSnapshot { $0.related = related }
    }

    func updateState(_ state: LoadingState) {
        updateSnapshot { $0.state = state }
    }

    func updateTimedOut(_ lastLoadTimedOut: Bool) {
        updateSnapshot { $0.lastLoadTimedOut = lastLoadTimedOut }
    }

    private func updateSnapshot(_ transform: (inout VideoDetailRelatedRenderSnapshot) -> Void) {
        var next = snapshot
        transform(&next)
        setSnapshot(next)
    }

    private func setSnapshot(_ next: VideoDetailRelatedRenderSnapshot) {
        guard next.changeSignature != snapshot.changeSignature else { return }
        snapshot = next
    }
}
