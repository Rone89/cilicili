import Foundation

struct VideoDetailPlayerPlaceholderPresentationCalculator {
    let playURLState: LoadingState
    let isDetailLoading: Bool
    let relatedState: LoadingState

    var loadingProgress: Double {
        if playURLState.isLoading { return 0.18 }
        if isDetailLoading { return 0.08 }
        if relatedState.isLoading { return 0.05 }
        return 0
    }

    var loadingMessage: String {
        if playURLState.isLoading { return "连接播放线路" }
        if isDetailLoading { return "加载视频信息" }
        if relatedState.isLoading { return "准备相关推荐" }
        return "准备播放"
    }

    var shouldWatchSlowLoading: Bool {
        playURLState.isLoading
            || isDetailLoading
            || relatedState.isLoading
    }

    func secondaryLoadingMessage(isTakingLong: Bool) -> String? {
        guard isTakingLong else { return nil }
        if playURLState.isLoading { return "网络较慢，继续保持连接" }
        if isDetailLoading { return "视频信息响应较慢，仍在等待" }
        if relatedState.isLoading { return "相关推荐稍后补齐，不影响播放" }
        return nil
    }
}
