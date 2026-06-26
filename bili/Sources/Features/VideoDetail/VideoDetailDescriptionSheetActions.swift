import Foundation

@MainActor
struct VideoDescriptionSheetActions {
    let toggleFollow: () async -> Void

    func toggleFollowAction() {
        Task { await toggleFollow() }
    }
}
