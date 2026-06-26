import SwiftUI

struct DanmakuSettingsDisplayAreaSection: View {
    @Binding var displayArea: DanmakuDisplayArea

    var body: some View {
        Section("显示区域") {
            Picker("覆盖范围", selection: $displayArea) {
                ForEach(DanmakuDisplayArea.allCases) { area in
                    Text(area.title).tag(area)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
        }
    }
}
