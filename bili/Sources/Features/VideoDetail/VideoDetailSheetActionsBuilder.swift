import Foundation

@MainActor
struct VideoDetailSheetActionsBuilder {
    let viewModel: VideoDetailViewModel

    var actions: VideoDetailSheetActions {
        VideoDetailSheetActions(viewModel: viewModel)
    }
}
