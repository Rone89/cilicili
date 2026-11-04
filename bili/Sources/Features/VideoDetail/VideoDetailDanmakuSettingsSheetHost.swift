import SwiftUI

@MainActor
struct VideoDetailDanmakuSettingsSheetHost: View {
    @ObservedObject var viewModel: VideoDetailViewModel
    let actions: VideoDetailDanmakuSheetActions

    var body: some View {
        DanmakuSettingsSheet(
            store: viewModel.danmakuSettingsRenderStore,
            subtitleStore: viewModel.subtitleRenderStore,
            onSelectSubtitleTrack: { lan in
                Task { await viewModel.selectSubtitleTrack(lan: lan) }
            },
            toggleDanmaku: actions.toggleDanmaku,
            updateDanmakuSettings: actions.updateDanmakuSettings
        )
        .presentationDetents([.medium])
    }
}
