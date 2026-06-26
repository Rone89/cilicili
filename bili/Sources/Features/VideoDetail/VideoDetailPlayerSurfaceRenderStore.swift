import Combine
import Foundation

@MainActor
final class VideoDetailPlayerSurfaceRenderStore: ObservableObject {
    @Published private var snapshot = VideoDetailPlayerSurfaceRenderSnapshot()

    var historyVideo: VideoItem? { snapshot.historyVideo }
    var historyCID: Int? { snapshot.historyCID }
    var duration: TimeInterval? { snapshot.duration }
    var isDanmakuEnabled: Bool { snapshot.isDanmakuEnabled }

    func update(_ next: VideoDetailPlayerSurfaceRenderSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
    }
}
