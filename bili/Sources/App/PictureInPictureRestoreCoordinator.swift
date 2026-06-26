import Foundation

@MainActor
final class PictureInPictureRestoreCoordinator {
    static let shared = PictureInPictureRestoreCoordinator()

    var restoreHandler: ((VideoItem) async -> Bool)?

    private init() {}

    func restorePlaybackUI(for video: VideoItem) async -> Bool {
        guard let restoreHandler else { return false }
        return await restoreHandler(video)
    }
}
