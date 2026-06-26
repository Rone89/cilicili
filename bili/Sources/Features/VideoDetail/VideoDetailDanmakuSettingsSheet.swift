import SwiftUI

struct DanmakuSettingsSheet: View {
    @ObservedObject var store: VideoDetailDanmakuSettingsRenderStore
    let toggleDanmaku: () -> Void
    let updateDanmakuSettings: (DanmakuSettings) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DanmakuSettingsSheetContent(
                store: store,
                summary: settingsSummary,
                displayAreaBinding: displayAreaBinding,
                fontScaleBinding: fontScaleBinding,
                fontWeightBinding: fontWeightBinding,
                opacityBinding: opacityBinding,
                toggleDanmaku: toggleDanmaku
            )
            .navigationTitle("弹幕设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                VideoDetailDoneToolbar(finish: dismissDanmakuSettings)
            }
        }
    }

    private func dismissDanmakuSettings() {
        dismiss()
    }
}
