import Foundation

nonisolated enum LoadingState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }
}

nonisolated enum LoadingPresentationPolicy {
    static let minimumIndicatorDelay: Duration = .milliseconds(300)

    static func shouldPresentIndicator(after elapsed: Duration) -> Bool {
        elapsed >= minimumIndicatorDelay
    }
}
