import Foundation

@MainActor
struct VideoDetailViewConfigurationActions {
    let seedVideo: VideoItem
    let dependencies: AppDependencies
    let holder: VideoDetailViewModelHolder

    func configureViewModel() {
        holder.configure(
            seedVideo: seedVideo,
            api: dependencies.api,
            libraryStore: dependencies.libraryStore,
            sponsorBlockService: dependencies.sponsorBlockService
        )
    }
}
