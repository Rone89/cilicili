import Combine

@MainActor
final class UploaderViewModelHolder: ObservableObject {
    @Published private(set) var viewModel: UploaderViewModel?
    private var spaceIdentity: UploaderSpaceRequestIdentity?

    func configure(owner: VideoOwner, api: BiliAPIClient) {
        let identity = UploaderSpaceRequestIdentity(api.requestSnapshot())
        guard viewModel?.seedOwner.mid != owner.mid || spaceIdentity != identity else { return }
        spaceIdentity = identity
        viewModel = UploaderViewModel(seedOwner: owner, api: api)
    }
}
