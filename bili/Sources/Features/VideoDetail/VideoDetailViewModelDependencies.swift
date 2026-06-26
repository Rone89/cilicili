import Foundation

struct VideoDetailViewModelDependencies {
    let api: BiliAPIClient
    let libraryStore: LibraryStore
    let sponsorBlockService: SponsorBlockService
}

extension VideoDetailViewModel {
    var api: BiliAPIClient {
        serviceDependencies.api
    }

    var libraryStore: LibraryStore {
        serviceDependencies.libraryStore
    }

    var sponsorBlockService: SponsorBlockService {
        serviceDependencies.sponsorBlockService
    }
}
