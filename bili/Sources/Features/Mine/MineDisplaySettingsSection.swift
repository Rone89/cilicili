import SwiftUI

struct MineDisplaySettingsSection: View {
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        Section("显示") {
            Picker(selection: Binding(
                get: { libraryStore.appearanceMode },
                set: { libraryStore.setAppearanceMode($0) }
            )) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            } label: {
                Label("外观", systemImage: "circle.lefthalf.filled")
            }

            Toggle(isOn: Binding(
                get: { libraryStore.minimizesTabBarOnScroll },
                set: { libraryStore.setMinimizesTabBarOnScroll($0) }
            )) {
                Label("滑动时缩小底部 Tab", systemImage: "arrow.down.right.and.arrow.up.left")
            }

            Toggle(isOn: Binding(
                get: { libraryStore.force120HzScrollingEnabled },
                set: { libraryStore.setForce120HzScrollingEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("强制滑动 120Hz 刷新率", systemImage: "speedometer")

                    Text("开启后滑动会强制使用 120Hz，可能会引起耗电增加，请谨慎开启。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
