import Combine
import SwiftUI

@MainActor
final class UploaderViewModelHolder: ObservableObject {
    @Published var viewModel: UploaderViewModel?
    private var cancellable: AnyCancellable?
    private var lastSnapshot: UploaderRenderSnapshot?

    func configure(owner: VideoOwner, api: BiliAPIClient) {
        guard viewModel?.seedOwner.mid != owner.mid else { return }
        let viewModel = UploaderViewModel(seedOwner: owner, api: api)
        self.viewModel = viewModel
        lastSnapshot = UploaderRenderSnapshot(viewModel)
        cancellable = viewModel.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self, weak viewModel] in
                guard let self, let viewModel else { return }
                let snapshot = UploaderRenderSnapshot(viewModel)
                guard snapshot != self.lastSnapshot else { return }
                self.lastSnapshot = snapshot
                self.objectWillChange.send()
            }
        }
    }
}

private struct UploaderRenderSnapshot: Equatable {
    let state: LoadingState
    let profileState: LoadingState
    let profileRevision: Int
    let videosRevision: Int
    let videoCount: Int
    let firstVideoID: String?
    let lastVideoID: String?
    let isFollowing: Bool
    let followerCount: Int?
    let followingCount: Int?
    let likeCount: Int?
    let archiveCount: Int?
    let isMutatingFollow: Bool
    let followMessage: String?

    init(_ viewModel: UploaderViewModel) {
        state = viewModel.state
        profileState = viewModel.profileState
        profileRevision = viewModel.profileRevision
        videosRevision = viewModel.videosRevision
        videoCount = viewModel.videos.count
        firstVideoID = viewModel.videos.first?.id
        lastVideoID = viewModel.videos.last?.id
        isFollowing = viewModel.isFollowing
        followerCount = viewModel.followerCount
        followingCount = viewModel.followingCount
        likeCount = viewModel.likeCount
        archiveCount = viewModel.archiveCount
        isMutatingFollow = viewModel.isMutatingFollow
        followMessage = viewModel.followMessage
    }
}
