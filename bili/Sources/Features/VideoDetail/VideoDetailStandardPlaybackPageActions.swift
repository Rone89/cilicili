import Foundation

@MainActor
struct VideoDetailStandardPlaybackPageActions {
    let viewModel: VideoDetailViewModel

    func selectPlayVariant(_ variant: PlayVariant) {
        guard canHandlePlaybackAction else { return }
        viewModel.selectPlayVariant(variant)
    }

    func toggleDanmaku() {
        guard canHandlePlaybackAction else { return }
        viewModel.toggleDanmaku()
    }

    func prepareForUserSeek(toProgress progress: Double) {
        guard canHandlePlaybackAction else { return }
        viewModel.prepareForUserSeek(toProgress: progress)
    }

    func updateDanmakuPlaybackTime(
        _ currentTime: TimeInterval,
        underLoad isLoadShedding: Bool
    ) {
        guard canHandlePlaybackAction else { return }
        viewModel.updateDanmakuPlaybackTime(currentTime, underLoad: isLoadShedding)
    }

    private var canHandlePlaybackAction: Bool {
        !viewModel.isPlaybackInvalidatedForNavigation
    }
}
