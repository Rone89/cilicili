import Foundation
import Combine

@MainActor
final class UploaderViewModel: ObservableObject {
    @Published var profile: UploaderProfile?
    @Published var videos: [VideoItem] = []
    @Published var state: LoadingState = .idle
    @Published private(set) var isFollowing = false
    @Published private(set) var followerCount: Int?
    @Published private(set) var isMutatingFollow = false
    @Published var followMessage: String?

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
            applyProfile(try await api.fetchUploaderProfile(mid: seedOwner.mid))
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

    @discardableResult
    func toggleFollow() async -> Bool {
        guard !isMutatingFollow else { return false }
        guard seedOwner.mid > 0 else {
            followMessage = "没有找到 UP 主 UID，无法关注"
            return false
        }

        let targetState = !isFollowing
        let previousState = isFollowing
        let previousFollowerCount = followerCount
        isMutatingFollow = true
        isFollowing = targetState
        if let followerCount {
            self.followerCount = max(0, followerCount + (targetState ? 1 : -1))
        }
        followMessage = targetState ? "正在关注" : "正在取消关注"

        do {
            try await api.setUploaderFollowing(mid: seedOwner.mid, following: targetState)
            followMessage = targetState ? "已关注" : "已取消关注"
            isMutatingFollow = false
            return true
        } catch {
            isFollowing = previousState
            followerCount = previousFollowerCount
            followMessage = followFailureMessage(error)
            isMutatingFollow = false
            return false
        }
    }

    private func appendUnique(_ more: [VideoItem]) {
        let existing = Set(videos.map(\.id))
        videos.append(contentsOf: more.filter { !existing.contains($0.id) })
    }

    private func applyProfile(_ profile: UploaderProfile) {
        self.profile = profile
        isFollowing = profile.following == true
        followerCount = profile.follower ?? profile.card?.fans
        followMessage = nil
    }

    private func followFailureMessage(_ error: Error) -> String {
        if case BiliAPIError.missingSESSDATA = error {
            return "登录后才能关注 UP 主"
        }
        return "关注状态更新失败：\(error.localizedDescription)"
    }
}
