import Foundation
import Combine

@MainActor
final class UploaderViewModel: ObservableObject {
    @Published var profile: UploaderProfile?
    @Published var videos: [VideoItem] = []
    @Published var state: LoadingState = .idle

    let seedOwner: VideoOwner

    private let api: BiliAPIClient
    private var page = 1

    init(seedOwner: VideoOwner, api: BiliAPIClient) {
        self.seedOwner = seedOwner
        self.api = api
    }

    func loadInitial() async {
        guard videos.isEmpty, profile == nil else { return }
        await refresh()
    }

    func refresh() async {
        state = .loading
        page = 1
        do {
            profile = try await api.fetchUploaderProfile(mid: seedOwner.mid)
            videos = try await api.fetchUploaderVideos(mid: seedOwner.mid, page: page)
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadMoreIfNeeded(current video: VideoItem?) async {
        guard let video, videos.last?.id == video.id, !state.isLoading else { return }
        state = .loading
        page += 1
        do {
            appendUnique(try await api.fetchUploaderVideos(mid: seedOwner.mid, page: page))
            state = .loaded
        } catch {
            page = max(1, page - 1)
            state = .failed(error.localizedDescription)
        }
    }

    private func appendUnique(_ more: [VideoItem]) {
        let existing = Set(videos.map(\.id))
        videos.append(contentsOf: more.filter { !existing.contains($0.id) })
    }
}
