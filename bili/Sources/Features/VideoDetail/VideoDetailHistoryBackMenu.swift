import SwiftUI

struct VideoDetailHistoryBackMenu: View {
    let history: NavigationHistoryContext
    @ObservedObject private var controller: NavigationHistoryController
    @Environment(\.navigationHistoryBackAction) private var envOnBack
    private let explicitBackAction: (() -> Void)?
    private let circularControlSize: CGFloat?

    init(
        history: NavigationHistoryContext,
        onBack: (() -> Void)? = nil,
        circularControlSize: CGFloat? = nil
    ) {
        self.history = history
        controller = history.controller
        explicitBackAction = onBack
        self.circularControlSize = circularControlSize
    }

    private func performBack() {
        if let explicitBackAction {
            explicitBackAction()
        } else if let envOnBack {
            envOnBack()
        } else {
            history.popOne()
        }
    }

    @ViewBuilder
    private var iconLabel: some View {
        if let size = circularControlSize {
            Image(systemName: "chevron.backward")
                .font(.system(size: 17, weight: .medium))
                .frame(width: size, height: size)
                .contentShape(Circle())
        } else {
            Image(systemName: "chevron.backward")
        }
    }

    var body: some View {
        Group {
            if controller.entries.isEmpty {
                Button(action: performBack) {
                    iconLabel
                }
                .buttonStyle(.plain)
            } else {
                Menu {
                    ForEach(controller.entries) { entry in
                        Button(entry.title) { history.pop(to: entry) }
                            .accessibilityIdentifier("video.detail.history.depth.\(entry.depth)")
                    }
                } label: {
                    iconLabel
                } primaryAction: {
                    performBack()
                }
                .buttonStyle(.plain)
            }
        }
        .tint(.primary)
        .foregroundStyle(.primary)
        .accessibilityLabel("返回")
        .accessibilityHint("长按查看导航历史")
        .accessibilityIdentifier("video.detail.history-back")
        .onAppear { history.refresh() }
    }
}
