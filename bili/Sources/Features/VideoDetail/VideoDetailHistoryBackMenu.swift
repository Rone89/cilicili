import SwiftUI

struct VideoDetailHistoryBackMenu: View {
    let history: NavigationHistoryContext
    @ObservedObject private var controller: NavigationHistoryController
    @Environment(\.navigationHistoryBackAction) private var onBack

    init(history: NavigationHistoryContext) {
        self.history = history
        controller = history.controller
    }

    var body: some View {
        Menu {
            ForEach(controller.entries) { entry in
                Button(entry.title) { history.pop(to: entry) }
                    .accessibilityIdentifier("video.detail.history.depth.\(entry.depth)")
            }
        } label: {
            Image(systemName: "chevron.backward")
        } primaryAction: {
            if let onBack { onBack() }
            else { history.popOne() }
        }
        .tint(.primary)
        .accessibilityLabel("返回")
        .accessibilityHint("长按查看导航历史")
        .accessibilityIdentifier("video.detail.history-back")
        .onAppear { history.refresh() }
    }
}
