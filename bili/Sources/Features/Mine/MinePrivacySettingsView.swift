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
                    Label("无痕模式", systemImage: "eye.slash")
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.guestModeEnabled },
                    set: { libraryStore.setGuestModeEnabled($0) }
                )) {
                    Label("游客模式", systemImage: "person.crop.circle.badge.questionmark")
                }

                Text("无痕模式下播放取流仍使用账号信息，但不会上报观看进度到云端历史。游客模式会让首页推荐流按未登录状态请求，不使用账号数据生成推荐。点赞、投币、收藏、关注等账号操作不受影响。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
    }
}
