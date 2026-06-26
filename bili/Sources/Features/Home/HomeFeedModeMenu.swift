import SwiftUI

struct HomeFeedModeMenu: View {
    let currentMode: HomeFeedMode
    let onSelectMode: (HomeFeedMode) -> Void

    var body: some View {
        Menu {
            ForEach(HomeFeedMode.allCases, id: \.self) { mode in
                Button {
                    onSelectMode(mode)
                } label: {
                    Label(mode.title, systemImage: currentMode == mode ? "checkmark" : mode.systemImage)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.semibold))
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .biliPlayerClearGlass(interactive: true, in: Circle())
        .accessibilityLabel("首页内容")
        .accessibilityValue(currentMode.title)
    }
}
