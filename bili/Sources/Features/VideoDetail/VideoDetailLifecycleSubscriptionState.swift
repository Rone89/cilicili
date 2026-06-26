import Combine

struct VideoDetailLifecycleSubscriptionState {
    var filterCancellable: AnyCancellable?
    var sponsorBlockCancellable: AnyCancellable?
    var playbackAutoOptimizationCancellable: AnyCancellable?
    var playbackPerformanceCancellable: AnyCancellable?
}

extension VideoDetailViewModel {
    var filterCancellable: AnyCancellable? {
        get { lifecycleSubscriptionState.filterCancellable }
        set { lifecycleSubscriptionState.filterCancellable = newValue }
    }

    var sponsorBlockCancellable: AnyCancellable? {
        get { lifecycleSubscriptionState.sponsorBlockCancellable }
        set { lifecycleSubscriptionState.sponsorBlockCancellable = newValue }
    }

    var playbackAutoOptimizationCancellable: AnyCancellable? {
        get { lifecycleSubscriptionState.playbackAutoOptimizationCancellable }
        set { lifecycleSubscriptionState.playbackAutoOptimizationCancellable = newValue }
    }

    var playbackPerformanceCancellable: AnyCancellable? {
        get { lifecycleSubscriptionState.playbackPerformanceCancellable }
        set { lifecycleSubscriptionState.playbackPerformanceCancellable = newValue }
    }
}
