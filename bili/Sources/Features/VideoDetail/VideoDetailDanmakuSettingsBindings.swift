import SwiftUI

extension DanmakuSettingsSheet {
    var settingsSummary: String {
        if store.isDanmakuEnabled {
            let settings = store.danmakuSettings.danmakuKit
            return "当前使用 \(settings.displayArea.title)，字号 \(Int((settings.fontScale * 100).rounded()))%，不透明度 \(Int((settings.opacity * 100).rounded()))%。"
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
