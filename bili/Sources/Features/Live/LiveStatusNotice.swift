import SwiftUI

struct LiveStatusNotice: View {
    @ObservedObject var viewModel: LiveRoomViewModel

    var body: some View {
        if let message = viewModel.streamFallbackMessage, !message.isEmpty {
            LiveStatusNoticeLabel(
                message: message,
                systemImage: "antenna.radiowaves.left.and.right"
            )
        } else if let message = viewModel.interactionMessage, !message.isEmpty {
            LiveStatusNoticeLabel(
                message: message,
                systemImage: "exclamationmark.circle"
            )
        } else if case .failed(let message) = viewModel.state {
            LiveStatusNoticeLabel(
                message: message,
                systemImage: "exclamationmark.circle"
            )
        }
    }
}

private struct LiveStatusNoticeLabel: View {
    let message: String
    let systemImage: String

    var body: some View {
        Label(message, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
