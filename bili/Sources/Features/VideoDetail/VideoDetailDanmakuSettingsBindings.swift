import SwiftUI

extension DanmakuSettingsSheet {
    var settingsSummary: String {
        if store.isDanmakuEnabled {
            return store.danmakuSettings.danmakuKit.summaryDescription
        }
        return "弹幕已关闭，播放时不会显示滚动评论。"
    }

    var hidesDanmakuInPortraitBinding: Binding<Bool> {
        Binding(
            get: { store.danmakuSettings.hidesInPortrait },
            set: { newValue in
                var settings = store.danmakuSettings
                settings.hidesInPortrait = newValue
                updateDanmakuSettings(settings)
            }
        )
    }

}
