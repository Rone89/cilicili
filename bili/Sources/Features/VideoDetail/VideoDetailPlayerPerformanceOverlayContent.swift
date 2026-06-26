import SwiftUI

struct PlayerPerformanceOverlayContent: View {
    let metricsID: String
    let session: PlayerPerformanceSession?
    let playerViewModel: PlayerStateViewModel?
    let panelWidth: CGFloat
    let maximumHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Capsule()
                .fill(.secondary.opacity(0.45))
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)

            PlayerPerformanceOverlayHeaderRow(
                metricsID: metricsID,
                copyText: PlayerPerformanceOverlayFormatting.performanceCopyText(
                    metricsID: metricsID,
                    session: session
                )
            )

            Divider()
                .opacity(0.55)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 7) {
                    if let session {
                        PlayerPerformanceOverlayLoadedContent(
                            session: session,
                            playerViewModel: playerViewModel
                        )
                    } else {
                        PlayerPerformanceOverlayEmptyContent()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.visible)
            .frame(maxHeight: max(maximumHeight - 44, 160), alignment: .top)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: panelWidth, alignment: .topLeading)
        .frame(maxHeight: maximumHeight, alignment: .topLeading)
        .background(
            PlayerPerformanceOverlayFormatting.panelBackground,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(PlayerPerformanceOverlayFormatting.panelStroke, lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
    }
}
