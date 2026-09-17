import SwiftUI

struct MinePrivacySettingsView: View {
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { libraryStore.incognitoModeEnabled },
                    set: { libraryStore.setIncognitoModeEnabled($0) }
                )) {
                    MineSettingsLabel("无痕模式", systemImage: "eye.slash")
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.guestModeEnabled },
                    set: { libraryStore.setGuestModeEnabled($0) }
                )) {
                    MineSettingsLabel("游客推荐模式", systemImage: "person.crop.circle.badge.questionmark")
                }

                Text("无痕模式下播放取流仍使用账号信息，但不会上报观看进度到云端历史。游客推荐模式只影响首页推荐：开启后按未登录状态请求，不使用账号画像；关闭后 App 端推荐会带登录状态请求。点赞、投币、收藏、关注等账号操作不受影响。多账号用途可在“账号管理”中调整。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(libraryStore.appTintColor)
        .formStyle(.grouped)
        .standardPageHorizontalContentMargins(libraryStore.standardPageHorizontalInset)
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
    }
}
