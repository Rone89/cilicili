import Foundation

@MainActor
struct VideoDetailPlaybackRenderSnapshotFactory {
    let viewModel: VideoDetailViewModel

    var snapshot: VideoDetailPlaybackRenderSnapshot {
        VideoDetailPlaybackRenderSnapshot(
            historyVideo: viewModel.detail,
            historyCID: viewModel.selectedCID,
            duration: viewModel.detail.duration.map(TimeInterval.init),
            pages: viewModel.detail.pages ?? [],
            selectedCID: viewModel.selectedCID,
            playURLState: viewModel.playURLState,
            selectedPlayVariant: selectedPlayVariant,
            isDetailLoading: viewModel.state.isLoading,
            isDetailLoaded: viewModel.state == .loaded,
            failedMessage: failedMessage,
            isDanmakuEnabled: viewModel.isDanmakuEnabled,
            qualityInlineButtonTitle: qualityInlineButtonTitle,
            qualityAccessoryButtonTitle: qualityAccessoryButtonTitle,
            qualityButtonSystemImage: qualityButtonSystemImage,
            qualityMenuItems: qualityMenuItems,
            isSupplementingPlayQualities: viewModel.isSupplementingPlayQualities,
            isSwitchingPlayQuality: viewModel.isSwitchingPlayQuality
        )
    }
}
