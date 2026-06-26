import Foundation
import Combine

@MainActor
final class UploaderViewModel: ObservableObject {
    @Published var profile: UploaderProfile? {
        didSet { profileRevision &+= 1 }
    }
    @Published var videos: [VideoItem] = [] {
        didSet { videosRevision &+= 1 }
    }
    @Published var state: LoadingState = .idle
    @Published private(set) var profileState: LoadingState = .idle
    @Published private(set) var isFollowing = false
    @Published private(set) var followerCount: Int?
    @Published private(set) var isMutatingFollow = false
    @Published var followMessage: String?
    @Published private(set) var profileRevision = 0
    @Published private(set) var videosRevision = 0

    let seedOwner: VideoOwner

    private let api: BiliAPIClient
    private let uploaderVideosTimeoutNanoseconds: UInt64 = 8_000_000_000
    private var page = 1

    init(seedOwner: VideoOwner, api: BiliAPIClient) {
        self.seedOwner = seedOwner
        self.api = api
    }

    func loadInitial() async {
        if profile == nil, !profileState.isLoading {
            Task { await loadProfile() }
        }
        guard videos.isEmpty, !state.isLoading else { return }
        await refresh()
    }

    func refresh() async {
        state = .loading
        page = 1
        if profile == nil, !profileState.isLoading {
            Task { await loadProfile() }
        }
        do {
            videos = try await fetchUploaderVideosWithTimeout(page: page)
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadProfile() async {
        guard !profileState.isLoading else { return }
        profileState = .loading
        do {
            applyProfile(try await api.fetchUploaderProfile(mid: seedOwner.mid))
            profileState = .loaded
        } catch {
            profileState = .failed(error.localizedDescription)
        }
    }

    func loadMoreIfNeeded(current video: VideoItem?) async {
        guard let video, videos.last?.id == video.id, !state.isLoading else { return }
        state = .loading
        page += 1
        do {
            appendUnique(try await fetchUploaderVideosWithTimeout(page: page))
            state = .loaded
        } catch {
            page = max(1, page - 1)
            state = .failed(error.localizedDescription)
        }
    }

    private func fetchUploaderVideosWithTimeout(page: Int) async throws -> [VideoItem] {
        try await withThrowingTaskGroup(of: [VideoItem].self) { group in
            let mid = seedOwner.mid
            let timeout = uploaderVideosTimeoutNanoseconds

            group.addTask(priority: .userInitiated) {
                try await self.api.fetchUploaderVideos(mid: mid, page: page)
            }
            group.addTask(priority: .utility) {
                try await Task.sleep(nanoseconds: timeout)
                throw BiliAPIError.api(code: -1, message: "投稿加载超时，请稍后重试")
            }

            guard let videos = try await group.next() else {
                group.cancelAll()
                throw BiliAPIError.emptyData
            }
            group.cancelAll()
            return videos
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
